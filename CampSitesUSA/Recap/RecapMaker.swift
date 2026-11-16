import Foundation
import AVFoundation
import MapKit
import ImageIO
import UIKit

/// Turns a trip into a short vertical recap video with ezReels' slideshow renderer: a route map
/// opener with the trip's stats, each camp's photos (videos contribute a frame) with a "Day N ·
/// Camp" title, and a closing card. 1080×1920, crossfades, gentle push-in toward what's in each
/// photo. Silent for now; music, captions and cuts are what ezReels is for.
enum RecapMaker {
    /// ezReels on the App Store, once it's live (nil shows "open it in ezReels" without a link).
    static let ezReelsStoreURL: URL? = nil

    struct Stats: Sendable {
        var miles: Int?
        var nights: Int
        var camps: Int
    }

    /// The slides and the images they use, built on the main actor from the trip.
    @MainActor
    static func plan(trip: Trip, stats: Stats) async throws -> (SlideshowSpec, [SlideImage: CGImage]) {
        var images: [SlideImage: CGImage] = [:]
        var slides: [Slide] = []
        let canvas = SlideCanvas(.vertical)

        // 1. The route on a map, with the trip's name and numbers.
        if let map = await routeMap(trip: trip, size: canvas.size) {
            let key = SlideImage.file(name: "route-map")
            images[key] = map
            var parts: [String] = []
            if let m = stats.miles { parts.append("\(m.formatted()) mi") }
            parts.append("\(stats.nights) night\(stats.nights == 1 ? "" : "s")")
            parts.append("\(stats.camps) camp\(stats.camps == 1 ? "" : "s")")
            slides.append(Slide(id: "open", role: .hook, images: [key], texts: [
                text("title", trip.name, font: .anton, size: 104, y: 0.16, style: .outline, upper: true),
                text("stats", parts.joined(separator: " · "), font: .inter, size: 46, y: 0.26, style: .background),
            ], durationMs: 3200))
        }

        // 2. Each camp's memories, in the order they were taken; at most ~16 so the recap stays short.
        let memories = trip.memories.sorted { $0.takenAt < $1.takenAt }
        let picked = evenly(memories, count: 16)
        var lastCamp: String?
        let stops = trip.orderedStops
        for m in picked {
            guard let cg = await image(for: m) else { continue }
            let key = SlideImage.file(name: m.fileName)
            images[key] = cg
            var texts: [SlideTextItem] = []
            let camp = m.siteName ?? "On the road"
            if camp != lastCamp {
                let day = stops.firstIndex { $0.siteID == m.siteID }.map { dayNumber(stopIndex: $0, stops: stops) }
                texts.append(text("camp-\(slides.count)", (day.map { "Day \($0) · " } ?? "") + camp,
                                  font: .inter, size: 52, y: 0.86, style: .background))
                lastCamp = camp
            }
            slides.append(Slide(id: "m\(slides.count)", role: .body, images: [key], texts: texts))
        }
        guard slides.count > 1 else { throw RecapError.noPhotos }

        // 3. Closing card.
        slides.append(Slide(id: "close", role: .cta, images: [], texts: [
            text("end", trip.name, font: .anton, size: 88, y: 0.44, style: .plain, upper: true),
            text("by", "Planned with ezcamp", font: .inter, size: 40, y: 0.54, style: .plain),
        ], durationMs: 2400))

        let spec = SlideshowSpec(canvas: canvas,
                                 style: SlideStyle(background: "#1d1440", overlay: SlideOverlay(color: "#000000", opacity: 0.12)),
                                 slides: slides,
                                 video: SlideVideoOptions(slideMs: 2600, transition: .crossfade, transitionMs: 450, musicID: nil, cutOnBeat: false))
        return (spec, images)
    }

    /// Renders the recap to a temporary .mp4 and returns its URL.
    static func render(_ spec: SlideshowSpec, images: [SlideImage: CGImage], progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "ezcamp-recap-\(UUID().uuidString.prefix(8)).mp4")
        _ = try await SlideVideo.render(spec, images: images, to: url, progress: progress)
        return url
    }

    enum RecapError: LocalizedError {
        case noPhotos
        var errorDescription: String? { "Add a few photos to the trip first." }
    }

    // MARK: Helpers

    private static func text(_ id: String, _ s: String, font: SlideFont, size: Double, y: Double,
                             style: SlideTextStyle, upper: Bool = false) -> SlideTextItem {
        var p = SlideTextPreset()
        p.font = font
        p.size = size
        p.y = y
        p.style = style
        p.uppercase = upper
        p.accent = style == .background ? "#7b61ff" : "#000000"
        return SlideTextItem(id: id, text: s, preset: p)
    }

    /// Up to `count` items spread across the list, keeping the first and last.
    private static func evenly<T>(_ list: [T], count: Int) -> [T] {
        guard list.count > count, count > 1 else { return list }
        return (0..<count).map { list[Int((Double($0) * Double(list.count - 1) / Double(count - 1)).rounded())] }
    }

    private static func dayNumber(stopIndex: Int, stops: [TripStop]) -> Int {
        1 + stops.prefix(stopIndex).map(\.nights).reduce(0, +)
    }

    private static func image(for m: Memory) async -> CGImage? {
        let url = m.url
        if m.isVideo {
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 2160, height: 2160)
            return try? await gen.image(at: .init(seconds: 1, preferredTimescale: 600)).image
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2160,
        ] as CFDictionary)
    }

    /// A map of the trip with the route drawn through every camp, start and end.
    @MainActor
    private static func routeMap(trip: Trip, size: CGSize) async -> CGImage? {
        let points = trip.waypoints
        guard points.count >= 2 else { return nil }
        let lats = points.map(\.latitude), lons = points.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.2, (lats.max()! - lats.min()!) * 1.9),
                                    longitudeDelta: max(0.2, (lons.max()! - lons.min()!) * 1.4))
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, span: span)
        options.size = CGSize(width: size.width / 3, height: size.height / 3)
        options.scale = 3
        options.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .muted)
        guard let snap = try? await MKMapSnapshotter(options: options).start() else { return nil }
        let renderer = UIGraphicsImageRenderer(size: options.size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 3; return f }())
        let image = renderer.image { ctx in
            snap.image.draw(at: .zero)
            let g = ctx.cgContext
            let pts = points.map { snap.point(for: $0) }
            g.setLineCap(.round)
            g.setLineJoin(.round)
            g.setStrokeColor(UIColor.white.cgColor)
            g.setLineWidth(9)
            g.addLines(between: pts)
            g.strokePath()
            g.setStrokeColor(UIColor(red: 1, green: 0.42, blue: 0.24, alpha: 1).cgColor)
            g.setLineWidth(5)
            g.addLines(between: pts)
            g.strokePath()
            for (i, p) in pts.enumerated() {
                let r: CGFloat = (i == 0 || i == pts.count - 1) ? 11 : 8
                g.setFillColor(UIColor.white.cgColor)
                g.fillEllipse(in: CGRect(x: p.x - r - 2, y: p.y - r - 2, width: (r + 2) * 2, height: (r + 2) * 2))
                g.setFillColor((i == 0 ? UIColor(red: 0.12, green: 0.75, blue: 0.46, alpha: 1)
                                : i == pts.count - 1 ? UIColor(red: 0.94, green: 0.26, blue: 0.48, alpha: 1)
                                : UIColor(red: 0.48, green: 0.38, blue: 1, alpha: 1)).cgColor)
                g.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
        }
        return image.cgImage
    }
}
