// Lifted from ezReels (Compositions/StickerCutout.swift @ edd2483); stickers saved under Documents/Gear.
//
//  StickerCutout.swift
//  ezReels
//
//  Cut-out stickers from your own photos (M7.10 smaller items): pick a photo, Vision lifts what's in front
//  (`VNGenerateForegroundInstanceMaskRequest`, iOS 17+, the model behind "Lift subject"), and the photo through that
//  mask, trimmed to what's left, becomes a transparent PNG in the Stickers panel's "Yours" row. Placing one is an
//  ordinary still sticker (`StickerItem` kind `.sticker`), so the compositor draws it with alpha in the preview and
//  the export alike, and moving, keyframes and the Tracks lane all work as for a KLIPY sticker.
//
//  Built this way:
//  - **Every subject, soft edges.** All foreground instances are kept (a person holding a mug is one sticker), and
//    the mask is Vision's full-resolution soft mask (`generateScaledMaskForImage`), not its label map, so hair and
//    fur keep their feathering. The cut is done in Core Image (`CIBlendWithMask` over clear) by `cutOut(_:mask:)`,
//    which a test drives with a fixed mask: the simulator has no Neural Engine, so Vision's model can't run there.
//  - **Trimmed with a margin.** The PNG is cropped to the mask's opaque bounds plus 2 % so a sticker's box is the
//    subject, which is what makes placing and scaling it feel right; at most 1024 px on the long side.
//  - **Yours lives with the app, not a project** (Documents/Media/Stickers/Yours), so a cut-out made once is there in
//    every reel; placing one copies it into the project (`StickerFrames.adopt`), so deleting it from Yours never
//    breaks a reel that uses it. Nothing leaves the phone.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision
import os

nonisolated enum StickerCutout {
    enum CutoutError: LocalizedError {
        case unreadable
        case modelUnavailable
        case nothingInFront

        var errorDescription: String? {
            switch self {
            case .unreadable: "That photo couldn't be read."
            case .modelUnavailable: "Cut-outs need the iPhone's Neural Engine, and this device can't run it."
            case .nothingInFront: "We couldn't find anything to cut out in that photo. Try one with a clear subject."
            }
        }
    }

    static let maxSide: CGFloat = 1024
    /// Space kept around the subject, as a fraction of its larger side.
    static let margin: CGFloat = 0.02

    /// The upright photo in `data`, at most `maxSide * 2` on its long side (Vision works below that anyway).
    static func photo(_ data: Data) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide * 2,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw CutoutError.unreadable }
        return image
    }

    /// Vision's soft mask of everything in front, at the photo's size (white kept, black dropped).
    @concurrent
    static func foregroundMask(of image: CGImage) async throws -> CIImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        do {
            try handler.perform([request])
        } catch {
            throw CutoutError.modelUnavailable
        }
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else { throw CutoutError.nothingInFront }
        let mask = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
        return CIImage(cvPixelBuffer: mask)
    }

    /// The photo through `mask` (same size; white kept), trimmed to the kept part plus a margin and scaled to at most
    /// `maxSide`: the sticker, with alpha. Nil when the mask keeps nothing.
    static func cutOut(_ image: CGImage, mask: CIImage) -> CGImage? {
        let photo = CIImage(cgImage: image)
        // Masks may arrive at another size (Vision's analysis size, a test's fixed mask): fit them to the photo.
        let fitted = mask.transformed(by: CGAffineTransform(scaleX: photo.extent.width / mask.extent.width,
                                                            y: photo.extent.height / mask.extent.height))
        let blend = CIFilter.blendWithMask()
        blend.inputImage = photo
        blend.backgroundImage = CIImage(color: .clear).cropped(to: photo.extent)
        blend.maskImage = fitted
        guard let cut = blend.outputImage?.cropped(to: photo.extent) else { return nil }
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let bounds = opaqueBounds(of: fitted, in: photo.extent, context: context) else { return nil }
        let pad = max(bounds.width, bounds.height) * margin
        let crop = bounds.insetBy(dx: -pad, dy: -pad).intersection(photo.extent).integral
        let scale = min(1, maxSide / max(crop.width, crop.height))
        let trimmed = cut.cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let size = CGRect(x: 0, y: 0, width: (crop.width * scale).rounded(), height: (crop.height * scale).rounded())
        return context.createCGImage(trimmed, from: size, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    /// The bounds (Core Image space) of mask pixels above 10 %, read from a small copy of the mask.
    private static func opaqueBounds(of mask: CIImage, in extent: CGRect, context: CIContext) -> CGRect? {
        let side = 256.0
        let scale = side / max(extent.width, extent.height)
        let width = max(1, Int((extent.width * scale).rounded())), height = max(1, Int((extent.height * scale).rounded()))
        let small = mask.cropped(to: extent)
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        var pixels = [UInt8](repeating: 0, count: width * height)
        context.render(small, toBitmap: &pixels, rowBytes: width, bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       format: .L8, colorSpace: nil)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] > 25 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // Bitmap rows run top-down; Core Image's y runs bottom-up.
        return CGRect(x: extent.minX + CGFloat(minX) / scale,
                      y: extent.minY + CGFloat(height - 1 - maxY) / scale,
                      width: CGFloat(maxX - minX + 1) / scale,
                      height: CGFloat(maxY - minY + 1) / scale)
    }

    /// A photo's cut-out saved to Yours: Vision's mask, or `mask` when given (tests and the Debug harness, which
    /// stand in for the model the simulator can't run).
    @concurrent
    static func make(from data: Data, mask: CIImage? = nil) async throws -> URL {
        let image = try photo(data)
        let used: CIImage
        if let mask { used = mask } else { used = try await foregroundMask(of: image) }
        guard let sticker = cutOut(image, mask: used) else { throw CutoutError.nothingInFront }
        return try UserStickers.save(sticker)
    }
}

/// The person's own stickers (Documents/Media/Stickers/Yours), newest first.
nonisolated enum UserStickers {
    static var folder: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "Gear", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// How many times the folder was listed (for tests: the Stickers panel lists it once when it appears).
    static let listings = OSAllocatedUnfairLock(initialState: 0)

    static var all: [URL] {
        listings.withLock { $0 += 1 }
        let keys: [URLResourceKey] = [.creationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        func created(_ url: URL) -> Date { (try? url.resourceValues(forKeys: Set(keys)).creationDate) ?? .distantPast }
        // Stills (PNG with alpha) and moving cut-outs of tracked objects (M7.28: a stacked-matte clip, whose poster PNG
        // is its tile, not a sticker of its own).
        return files.filter { url in
            let name = url.lastPathComponent.lowercased()
            return (url.pathExtension.lowercased() == "png" && !name.hasSuffix(".poster.png")) || isMoving(url)
        }.sorted { created($0) > created($1) }
    }

    /// A moving cut-out (M7.28, Look/ObjectCutout.swift): colour and matte side by side in one clip.
    static func isMoving(_ url: URL) -> Bool { url.lastPathComponent.lowercased().hasSuffix(".stacked.mp4") }

    /// The still a moving cut-out's tile shows.
    static func poster(for clip: URL) -> URL {
        clip.deletingPathExtension().appendingPathExtension("poster.png")
    }

    /// Writes a sticker as PNG with its alpha; returns its file.
    static func save(_ image: CGImage) throws -> URL {
        let url = folder.appending(path: "cutout-\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        if isMoving(url) { try? FileManager.default.removeItem(at: poster(for: url)) }
    }
}
