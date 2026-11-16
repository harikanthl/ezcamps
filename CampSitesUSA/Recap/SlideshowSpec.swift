// Lifted from ezReels (Slideshow/SlideshowSpec.swift @ edd2483), minus brand, validation and history.
//
//  SlideshowSpec.swift
//  ezReels
//
//  Everything needed to draw a slideshow (M7.6 task 1), as one Codable value: the canvas, the look shared by
//  every slide (grid layout, gap, corner radius, background, overlay, logo), the slides themselves (role, a
//  photo per grid cell, text items) and the video options. The editor edits it, `SlideRenderer` draws it, and
//  the same value drives the preview, the carousel PNGs and the video frames, so preview equals export.
//
//  Ported from vireeel (`~/Projects/vireeel/packages/slides/src/spec.ts`, a zod schema). The zod refinements
//  became `SlideshowSpec.problems`, which lists every rule a spec breaks in plain words, and zod's defaults
//  became `decodeIfPresent` fallbacks, so a spec saved before a field existed still opens. Changes for the
//  phone: canvases are 9:16, 4:5 and 1:1 only (no 16:9: ezReels makes reels and carousels), images are
//  typed references (a Photos asset, a vireeel library image, or a file in the app) instead of asset ids,
//  and validation also requires each text box to sit inside the canvas horizontally (vireeel clamped it).
//
//  It is stored on a `ReelProject` of kind "slideshow" (`slideshowData`), with undo through
//  `SlideshowHistory` like `EditTimeline` / `EditHistory`. Pure: nonisolated, Sendable, unit-tested.
//

import CoreGraphics
import Foundation

// MARK: - Reading what a newer version wrote

extension KeyedDecodingContainer {
    /// A value that falls back to `fallback` when it's missing or this version doesn't know it (a font or layout added
    /// later), so one unknown word doesn't make the whole slideshow unreadable (sweep #13).
    nonisolated func lenient<T: Decodable>(_ key: Key, default fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

// MARK: - Canvas and layout

/// The slide's shape. 9:16 fills a reel and a TikTok photo post; 4:5 is Instagram's tallest carousel.
nonisolated enum SlideAspect: String, Codable, CaseIterable, Sendable, Identifiable {
    case vertical = "9:16", portrait = "4:5", square = "1:1"

    var id: String { rawValue }

    /// The canvas size slides are authored at (and exported at), in pixels.
    var size: (width: Int, height: Int) {
        switch self {
        case .vertical: (1080, 1920)
        case .portrait: (1080, 1350)
        case .square: (1080, 1080)
        }
    }
}

nonisolated struct SlideCanvas: Codable, Hashable, Sendable {
    var aspect: SlideAspect
    var width: Int
    var height: Int

    init(_ aspect: SlideAspect) {
        self.aspect = aspect
        (width, height) = aspect.size
    }

    var size: CGSize { CGSize(width: width, height: height) }
}

/// Grid layouts, as columns:rows.
nonisolated enum SlideLayout: String, Codable, CaseIterable, Sendable, Identifiable {
    case single, oneByTwo = "1:2", oneByThree = "1:3", twoByOne = "2:1", twoByTwo = "2:2"

    var id: String { rawValue }

    var columns: Int { self == .twoByOne || self == .twoByTwo ? 2 : 1 }
    var rows: Int {
        switch self {
        case .single, .twoByOne: 1
        case .oneByTwo, .twoByTwo: 2
        case .oneByThree: 3
        }
    }

    var cellCount: Int { columns * rows }

    /// Cell rectangles on a canvas, in reading order, top-left origin. `gap` separates the cells and frames them.
    func cells(canvas: CGSize, gap: CGFloat) -> [CGRect] {
        let cw = (canvas.width - gap * CGFloat(columns + 1)) / CGFloat(columns)
        let ch = (canvas.height - gap * CGFloat(rows + 1)) / CGFloat(rows)
        var out: [CGRect] = []
        for r in 0..<rows {
            for c in 0..<columns {
                out.append(CGRect(x: gap + CGFloat(c) * (cw + gap), y: gap + CGFloat(r) * (ch + gap), width: cw, height: ch))
            }
        }
        return out
    }
}

// MARK: - Text

nonisolated enum SlideTextStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Just the glyphs.
    case plain
    /// Glyphs with a stroke in `accent` under them.
    case outline
    /// A rounded box in `accent` behind each line.
    case background
    /// A white rounded box behind each line (TikTok's own text look).
    case lightBackground = "light-background"

    var id: String { rawValue }
}

nonisolated enum SlideTextAlignment: String, Codable, CaseIterable, Sendable {
    case left, center, right
}

/// Which point of the text block sits at `y`.
nonisolated enum SlideTextAnchor: String, Codable, CaseIterable, Sendable {
    case top, middle, bottom
}

/// The look of a text item without its words: what formats store per role.
nonisolated struct SlideTextPreset: Codable, Hashable, Sendable {
    var font: SlideFont = .tiktokSans
    /// Font size in canvas pixels.
    var size: Double = 64
    /// #rrggbb.
    var color = "#ffffff"
    var style: SlideTextStyle = .outline
    /// Box colour for `background`, stroke colour for `outline` (#rrggbb).
    var accent = "#000000"
    var align: SlideTextAlignment = .center
    /// The anchor point, as fractions of the canvas.
    var x = 0.5
    var y = 0.5
    var anchor: SlideTextAnchor = .middle
    /// The widest a line may be, as a fraction of the canvas width.
    var width = 0.84
    var uppercase = false
    var lineHeight = 1.15
}

nonisolated struct SlideTextItem: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var text: String
    var font: SlideFont
    var size: Double
    var color: String
    var style: SlideTextStyle
    var accent: String
    var align: SlideTextAlignment
    var x: Double
    var y: Double
    var anchor: SlideTextAnchor
    var width: Double
    var uppercase: Bool
    var lineHeight: Double

    init(id: String, text: String, preset: SlideTextPreset = SlideTextPreset()) {
        self.id = id
        self.text = text
        font = preset.font
        size = preset.size
        color = preset.color
        style = preset.style
        accent = preset.accent
        align = preset.align
        x = preset.x
        y = preset.y
        anchor = preset.anchor
        width = preset.width
        uppercase = preset.uppercase
        lineHeight = preset.lineHeight
    }

    /// The look alone, for "save as format" and for restyling a role.
    var preset: SlideTextPreset {
        get {
            SlideTextPreset(font: font, size: size, color: color, style: style, accent: accent, align: align, x: x, y: y,
                            anchor: anchor, width: width, uppercase: uppercase, lineHeight: lineHeight)
        }
        set { self = SlideTextItem(id: id, text: text, preset: newValue) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, font, size, color, style, accent, align, x, y, anchor, width, uppercase, lineHeight
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        font = c.lenient(.font, default: .tiktokSans)
        size = try c.decode(Double.self, forKey: .size)
        color = try c.decode(String.self, forKey: .color)
        style = c.lenient(.style, default: .outline)
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? "#000000"
        align = c.lenient(.align, default: .center)
        x = try c.decode(Double.self, forKey: .x)
        y = try c.decode(Double.self, forKey: .y)
        anchor = c.lenient(.anchor, default: .middle)
        width = try c.decode(Double.self, forKey: .width)
        uppercase = try c.decodeIfPresent(Bool.self, forKey: .uppercase) ?? false
        lineHeight = try c.decodeIfPresent(Double.self, forKey: .lineHeight) ?? 1.15
    }
}

// MARK: - Images

/// Where a cell's photo (or the logo) comes from.
nonisolated enum SlideImage: Codable, Hashable, Sendable {
    /// A Photos library asset, by local identifier.
    case photos(localIdentifier: String)
    /// A vireeel library image, by catalogue id ("vireeel:<id>"), streamed and cached by `LibraryCache`.
    case library(id: String)
    /// A file the app keeps, by name inside `SlideImages.directory` (never an absolute path: the container moves).
    case file(name: String)
}

// MARK: - Slides

nonisolated enum SlideRole: String, Codable, CaseIterable, Sendable {
    /// Slide 1: the tension that stops the scroll.
    case hook
    case body
    /// The last slide's soft call to action.
    case cta
}

nonisolated struct Slide: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var role: SlideRole
    /// One image per layout cell, in reading order; nil draws an empty cell.
    var images: [SlideImage?]
    var texts: [SlideTextItem]
    /// How long the slide holds in the video, or nil for the slideshow's `video.slideMs`.
    var durationMs: Int?

    init(id: String, role: SlideRole, images: [SlideImage?] = [], texts: [SlideTextItem] = [], durationMs: Int? = nil) {
        self.id = id
        self.role = role
        self.images = images
        self.texts = texts
        self.durationMs = durationMs
    }

    private enum CodingKeys: String, CodingKey { case id, role, images, texts, durationMs }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        role = c.lenient(.role, default: .body)
        images = try c.decodeIfPresent([SlideImage?].self, forKey: .images) ?? []
        texts = try c.decodeIfPresent([SlideTextItem].self, forKey: .texts) ?? []
        durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs)
    }
}

// MARK: - Style

nonisolated struct SlideOverlay: Codable, Hashable, Sendable {
    /// #rrggbb.
    var color = "#000000"
    /// 0 (none) to 0.9.
    var opacity = 0.25
}

nonisolated enum SlideCorner: String, Codable, CaseIterable, Sendable {
    case topLeft = "top-left", topRight = "top-right", bottomLeft = "bottom-left", bottomRight = "bottom-right"

    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }
}

/// A logo on every slide: `scale` of the canvas width, 4 % of the width in from its corner's two edges.
nonisolated struct SlideLogo: Codable, Hashable, Sendable {
    var image: SlideImage
    var position: SlideCorner = .bottomRight
    /// 0.06 to 0.3 of the canvas width.
    var scale = 0.12
}

nonisolated struct SlideStyle: Codable, Hashable, Sendable {
    var layout: SlideLayout = .single
    /// Gap between grid cells and around them, in canvas pixels.
    var gap = 0
    /// Corner radius of the image cells, in canvas pixels.
    var radius = 0
    /// #rrggbb, shows in gaps.
    var background = "#111111"
    var overlay = SlideOverlay()
    var logo: SlideLogo?

    init(layout: SlideLayout = .single, gap: Int = 0, radius: Int = 0, background: String = "#111111",
         overlay: SlideOverlay = SlideOverlay(), logo: SlideLogo? = nil) {
        self.layout = layout
        self.gap = gap
        self.radius = radius
        self.background = background
        self.overlay = overlay
        self.logo = logo
    }

    private enum CodingKeys: String, CodingKey { case layout, gap, radius, background, overlay, logo }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layout = c.lenient(.layout, default: .single)
        gap = try c.decode(Int.self, forKey: .gap)
        radius = try c.decode(Int.self, forKey: .radius)
        background = try c.decode(String.self, forKey: .background)
        overlay = try c.decode(SlideOverlay.self, forKey: .overlay)
        logo = try c.decodeIfPresent(SlideLogo.self, forKey: .logo)
    }
}

// MARK: - Video

nonisolated enum SlideTransition: String, Codable, CaseIterable, Sendable {
    case none, crossfade
}

nonisolated struct SlideVideoOptions: Codable, Hashable, Sendable {
    /// How long each slide holds unless it sets its own `durationMs`.
    var slideMs = 4000
    var transition: SlideTransition = .crossfade
    var transitionMs = 400
    /// A vireeel music track ("vireeel:<id>"), or nil for none.
    var musicID: String?
    /// Slide changes land on the music's beats.
    var cutOnBeat = true

    init(slideMs: Int = 4000, transition: SlideTransition = .crossfade, transitionMs: Int = 400, musicID: String? = nil, cutOnBeat: Bool = true) {
        self.slideMs = slideMs
        self.transition = transition
        self.transitionMs = transitionMs
        self.musicID = musicID
        self.cutOnBeat = cutOnBeat
    }

    private enum CodingKeys: String, CodingKey { case slideMs, transition, transitionMs, musicID, cutOnBeat }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slideMs = try c.decodeIfPresent(Int.self, forKey: .slideMs) ?? 4000
        transition = c.lenient(.transition, default: .crossfade)
        transitionMs = try c.decodeIfPresent(Int.self, forKey: .transitionMs) ?? 400
        musicID = try c.decodeIfPresent(String.self, forKey: .musicID)
        cutOnBeat = try c.decodeIfPresent(Bool.self, forKey: .cutOnBeat) ?? true
    }
}

// MARK: - The spec

nonisolated struct SlideshowSpec: Codable, Hashable, Sendable {
    var version = 1
    /// BCP 47 tag; drives uppercasing and line breaking.
    var language = "en"
    var canvas: SlideCanvas
    var style: SlideStyle
    var slides: [Slide]
    var video: SlideVideoOptions

    static let maxSlides = 20
    static let maxTextsPerSlide = 6
    static let maxTextLength = 400

    init(language: String = "en", canvas: SlideCanvas, style: SlideStyle = SlideStyle(), slides: [Slide],
         video: SlideVideoOptions = SlideVideoOptions()) {
        self.language = language
        self.canvas = canvas
        self.style = style
        self.slides = slides
        self.video = video
    }

    private enum CodingKeys: String, CodingKey { case version, language, canvas, style, slides, video }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? "en"
        canvas = try c.decode(SlideCanvas.self, forKey: .canvas)
        style = try c.decode(SlideStyle.self, forKey: .style)
        slides = try c.decode([Slide].self, forKey: .slides)
        video = try c.decodeIfPresent(SlideVideoOptions.self, forKey: .video) ?? SlideVideoOptions()
    }

    /// How long slide `index` holds in the video, in seconds.
    func duration(ofSlide index: Int) -> Double {
        Double(slides[index].durationMs ?? video.slideMs) / 1000
    }

    /// Every image the slides and logo draw, in first-use order, each once.
    var images: [SlideImage] {
        var seen = Set<SlideImage>()
        var out: [SlideImage] = []
        for slide in slides {
            for case let image? in slide.images.prefix(style.layout.cellCount) where seen.insert(image).inserted { out.append(image) }
        }
        if let logo = style.logo, seen.insert(logo.image).inserted { out.append(logo.image) }
        return out
    }

    /// "#rrggbb" in lower case, or nil when `hex` isn't a colour.
    static func normalizedColor(_ hex: String) -> String? {
        let trimmed = hex.trimmingCharacters(in: .whitespaces).lowercased()
        return isColor(trimmed) ? trimmed : nil
    }

    static func isColor(_ value: String) -> Bool {
        value.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil
    }
}
