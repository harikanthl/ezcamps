// Lifted from ezReels (Slideshow/SlideVideo.swift @ edd2483). The reel/music stage is replaced by
// RecapMaker's own mux; everything else is unchanged.
//
//  SlideVideo.swift
//  ezReels
//
//  A slideshow as a reel (M7.6 task 6). Two steps, so a slideshow plays and exports exactly like any reel:
//  1. `SlideVideo.render` draws the slides into a silent 1080×1920 movie: each slide held for its time, its photos
//     pushed in slowly (1.0 → 1.06, toward the photo's subject) while the text stays still, and a crossfade into the
//     next slide. With "cut on the beat" and music, every slide change is moved onto the nearest beat of the track.
//     Every frame comes from `SlideRenderer.draw`, the renderer behind the editor's preview and the carousel PNGs.
//  2. `SlideVideo.reel` wraps that movie as an `EditTimeline` with the music bed and hands it to `ReelCompositor`
//     and `VideoExporter`: the same path, mix and −14 LUFS loudness as every other reel (preview equals export).
//
//  The editor's Play preview (Slideshow/SlidePreview.swift) takes both steps too, with step 1 drawn at 540×960; the
//  export always draws 1080×1920.
//
//  The export on the phone (iPhone 17 Pro Max, 2026-11-13) failed after rendering, "The operation could not be
//  completed": the silent movie made the compositor lay an empty speech track, which the export session refused
//  (AVFoundation −11800, underlying −12710; fixed in ReelCompositor, and every export step now logs its name). It was
//  also slow, 24 s of video in 67 s. Now each slide's still layer (overlay, text, logo) is drawn once
//  (`SlideRenderer.renderTop`) instead of typeset every frame, frames are drawn several at a time across the cores and
//  appended in order, and the movie ends exactly on its last frame (`endSession`), so its length is the length this
//  returns. A failing step throws `SlideVideo.Failure`, naming it.
//
//  Ported from vireeel's slideshow video render (`packages/slides/src/render/`), re-done with Core Graphics frames
//  into AVAssetWriter.
//

import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import Vision

nonisolated enum SlideVideo {
    static let fps: Int32 = 30
    static let size = CGSize(width: 1080, height: 1920)
    /// How far a photo pushes in over its slide.
    static let pushIn: CGFloat = 0.06

    /// When each slide starts (seconds) and the total length: the slides' own lengths, with each change moved to the
    /// nearest beat when `beats` (seconds on the reel clock) are given, never closer than 1 s to the last.
    static func schedule(_ spec: SlideshowSpec, beats: [Double]? = nil) -> (starts: [Double], duration: Double) {
        var starts: [Double] = []
        var t = 0.0
        for i in spec.slides.indices {
            starts.append(t)
            t += spec.duration(ofSlide: i)
        }
        guard let beats, !beats.isEmpty, starts.count > 1 else { return (starts, t) }
        var snapped = [0.0]
        for i in starts.indices.dropFirst() {
            let wanted = starts[i]
            let nearest = beats.min { abs($0 - wanted) < abs($1 - wanted) } ?? wanted
            let floor = snapped[i - 1] + 1
            snapped.append(abs(nearest - wanted) <= spec.duration(ofSlide: i - 1) / 2 && nearest >= floor ? nearest : max(wanted, floor))
        }
        let end = snapped.last! + spec.duration(ofSlide: starts.count - 1)
        let endBeat = beats.filter { $0 >= end - 0.5 && $0 <= end + 1 }.min { abs($0 - end) < abs($1 - end) }
        return (snapped, endBeat ?? end)
    }

    /// Where each photo's subject is (0–1, top-left origin), for the push-in: Vision's objectness saliency, else centre.
    static func focusPoints(_ images: [SlideImage: CGImage]) -> [SlideImage: CGPoint] {
        var out: [SlideImage: CGPoint] = [:]
        for (ref, image) in images {
            let request = VNGenerateObjectnessBasedSaliencyImageRequest()
            try? VNImageRequestHandler(cgImage: image).perform([request])
            if let box = request.results?.first?.salientObjects?.max(by: { $0.confidence < $1.confidence })?.boundingBox {
                out[ref] = CGPoint(x: box.midX, y: 1 - box.midY)
            }
        }
        return out
    }

    /// A render step that failed, by name, with the writer's error.
    struct Failure: LocalizedError {
        var step: String
        var underlying: (any Error)?
        var errorDescription: String? {
            "The slideshow video couldn't be drawn (\(step))" + (underlying.map { ": \($0.localizedDescription)" } ?? ".")
        }
    }

    /// Frames drawn at once: one per core, at least two.
    static var batch: Int { max(2, ProcessInfo.processInfo.activeProcessorCount) }

    /// Draws the slideshow into a silent H.264 movie at `url`, `size` pixels (the export's 1080×1920 unless the
    /// editor's Play preview asks for less). `progress` gets 0…1. Returns the movie's length: a whole number of frames.
    /// `@concurrent`: with approachable concurrency a plain `nonisolated async` function runs on its caller's actor,
    /// and every caller is the main actor, so drawing a thousand frames (and Vision's saliency) would freeze the UI
    /// for the whole export. This runs on the cooperative pool instead.
    @concurrent static func render(_ spec: SlideshowSpec, images: [SlideImage: CGImage], beats: [Double]? = nil, to url: URL,
                       size: CGSize = SlideVideo.size, progress: @Sendable (Double) -> Void = { _ in }) async throws -> Double {
        let (starts, duration) = schedule(spec, beats: beats)
        let focus = focusPoints(images)
        let tops = spec.slides.indices.map { SlideRenderer.renderTop(spec, slide: $0, size: size, images: images) }
        try? FileManager.default.removeItem(at: url)
        let writer: AVAssetWriter
        do { writer = try AVAssetWriter(outputURL: url, fileType: .mp4) } catch { throw Failure(step: "opening the movie", underlying: error) }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: Int(12_000_000 * size.width * size.height / (1080 * 1920))],
            // Rec. 709, as every reel leaves the compositor, so the slides' colours survive the trip through it.
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        guard writer.canAdd(input) else { throw Failure(step: "adding the video track", underlying: writer.error) }
        writer.add(input)
        guard writer.startWriting() else { throw Failure(step: "starting the writer", underlying: writer.error) }
        writer.startSession(atSourceTime: .zero)

        let frames = max(1, Int((duration * Double(fps)).rounded()))
        let fade = spec.video.transition == .crossfade ? Double(spec.video.transitionMs) / 1000 : 0
        var next = 0
        while next < frames {
            try Task.checkCancellation()
            let range = next..<min(frames, next + batch)
            guard let pool = adaptor.pixelBufferPool else { throw Failure(step: "the frame pool", underlying: writer.error) }
            var buffers: [CVPixelBuffer] = []
            for frame in range {
                var made: CVPixelBuffer?
                let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
                guard let buffer = made else {
                    throw Failure(step: "a buffer for frame \(frame) (CoreVideo \(status))", underlying: writer.error)
                }
                CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
                CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
                CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
                buffers.append(buffer)
            }
            // Each buffer is drawn by one thread only; the pixel data is all they share.
            nonisolated(unsafe) let drawing = buffers
            let first = range.lowerBound
            DispatchQueue.concurrentPerform(iterations: drawing.count) { i in
                let t = Double(first + i) / Double(fps)
                draw(spec, at: t, starts: starts, duration: duration, fade: fade, images: images, focus: focus, tops: tops, into: drawing[i])
            }
            for (i, frame) in range.enumerated() {
                while !input.isReadyForMoreMediaData {
                    if writer.status == .failed { throw Failure(step: "encoding frame \(frame)", underlying: writer.error) }
                    try await Task.sleep(for: .milliseconds(2))
                }
                guard adaptor.append(buffers[i], withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps)) else {
                    throw Failure(step: "appending frame \(frame) of \(frames)", underlying: writer.error)
                }
            }
            next = range.upperBound
            progress(Double(next) / Double(frames))
        }
        input.markAsFinished()
        // The movie ends on its last frame's end, not wherever the encoder puts it: its length is `frames / fps`.
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frames), timescale: fps))
        await writer.finishWriting()
        guard writer.status == .completed else { throw Failure(step: "finishing the movie", underlying: writer.error) }
        progress(1)
        return Double(frames) / Double(fps)
    }

    /// One frame at reel time `t`: the slide showing (its photos pushed in by how far through it we are), and in the
    /// last `fade` seconds before the next slide, that slide fading in over it.
    /// `tops`: each slide's still layer (`SlideRenderer.renderTop` at the buffer's size); a slide without one is drawn
    /// whole.
    static func draw(_ spec: SlideshowSpec, at t: Double, starts: [Double], duration: Double, fade: Double,
                     images: [SlideImage: CGImage], focus: [SlideImage: CGPoint], tops: [CGImage?] = [], into buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: CVPixelBufferGetWidth(buffer),
                                      height: CVPixelBufferGetHeight(buffer), bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }
        let index = starts.lastIndex { $0 <= t } ?? 0
        let end = index + 1 < starts.count ? starts[index + 1] : duration
        func zoom(_ i: Int, _ at: Double) -> CGFloat {
            let start = starts[i], stop = i + 1 < starts.count ? starts[i + 1] : duration
            return 1 + pushIn * CGFloat(min(1, max(0, (at - start) / max(0.1, stop - start))))
        }
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        func slide(_ i: Int, zoom: CGFloat) {
            if let top = tops.element(at: i) ?? nil, top.width == Int(size.width), top.height == Int(size.height) {
                SlideRenderer.drawBase(spec, slide: i, in: context, size: size, images: images, zoom: zoom, focus: focus)
                context.draw(top, in: CGRect(origin: .zero, size: size))
            } else {
                SlideRenderer.draw(spec, slide: i, in: context, size: size, images: images, zoom: zoom, focus: focus)
            }
        }
        slide(index, zoom: zoom(index, t))
        if fade > 0, index + 1 < starts.count, t > end - fade {
            context.saveGState()
            context.setAlpha(CGFloat((t - (end - fade)) / fade))
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            slide(index + 1, zoom: 1)
            context.endTransparencyLayer()
            context.restoreGState()
        }
    }
}

extension Array {
    /// The element at `i`, or nil past the end.
    nonisolated func element(at i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
