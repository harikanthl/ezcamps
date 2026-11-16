// Lifted from ezReels (Slideshow/SlideRenderer.swift @ edd2483).
//
//  SlideRenderer.swift
//  ezReels
//
//  Draws one slide (M7.6 task 2). The single renderer behind the editor preview, the carousel PNGs and the video
//  frames: same spec in, same picture out at any size. Painting order, as vireeel's: background colour, photos
//  aspect-filled into the grid cells (rounded by `radius`, an empty cell is dark grey), the overlay, each text
//  item, then the logo.
//
//  Ported from vireeel (`~/Projects/vireeel/packages/slides/src/render/text.ts` and `render/svg.ts`; its DECISIONS
//  #22), where HarfBuzz shaped text into SVG glyph outlines and resvg rasterised them so the browser and the
//  render container matched. Here Core Text replaces both (docs/decisions.md, M7.6): it shapes every script,
//  breaks lines with the system's language-aware rules (Thai and CJK wrap without spaces) and falls back per
//  glyph to a font that has it. The layout rules are vireeel's, unchanged: lines no wider than `width` of the
//  canvas, a line box of `size × lineHeight` with the glyphs centred in it, the block anchored at `y` by its top,
//  middle or bottom and kept inside the canvas, uppercase per the slideshow's language, outline stroke
//  `0.16 × size` under the fill with round joins, and boxes padded `0.32 × size` sideways and `0.12 × size` above
//  and below with a `0.22 × size` corner.
//
//  Size independence: text is laid out once in canvas pixels and the whole slide is drawn through one scale
//  transform, so a 270×480 preview breaks lines exactly where the 1080×1920 export does. Glyphs are positioned
//  without subpixel quantisation or font smoothing, so a small render is the large one, downscaled (a test
//  measures it).
//
//  Two layers, for the video: `drawBase` paints the background and the photos (the only part a push-in moves) and
//  `drawTop` the overlay, the text and the logo (still for the whole slide). `draw` is both, in that order, so the
//  carousel and the preview are unchanged; the video draws the top layer once per slide (`renderTop`) and lays it over
//  each frame's photos instead of typesetting every frame (SlideVideo; the export on the phone ran at about a third
//  of real time, 2026-11-13).
//

import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// A text item laid out on the canvas, in canvas pixels, top-left origin.
nonisolated struct SlideTextLayout {
    struct Line {
        var line: CTLine
        /// Left edge of the glyphs.
        var x: CGFloat
        /// Ink advance without trailing spaces.
        var width: CGFloat
        /// The line box.
        var top: CGFloat
        var height: CGFloat
        var baseline: CGFloat
        var isEmpty: Bool
    }

    var lines: [Line]
    /// Ascent plus descent of the item's own font at its size.
    var contentHeight: CGFloat
    /// The block's top and height (lines × line box).
    var top: CGFloat
    var height: CGFloat
    /// The widest a line may be.
    var maxWidth: CGFloat
    /// The box the text may occupy: `width` of the canvas placed by `align` at `x`, the block's height.
    var box: CGRect
    /// The upper-cased (or not) text that was laid out.
    var text: String

    /// What is painted: the lines' ink advances, plus the padded boxes for a boxed style.
    var paintedBounds: CGRect {
        lines.filter { !$0.isEmpty }.reduce(CGRect.null) { $0.union(CGRect(x: $1.x, y: $1.top, width: $1.width, height: $1.height)) }
    }

    /// True when a line is wider than the box allows or the block doesn't fit the canvas height.
    func overflows(canvas: CGSize) -> Bool {
        lines.contains { $0.width > maxWidth + 0.5 } || top < -0.5 || top + height > canvas.height + 0.5
    }
}

nonisolated enum SlideRenderer {
    /// What an empty grid cell is filled with.
    static let emptyCell = "#262626"

    // MARK: Layout

    /// Lays out one text item on a canvas, in canvas pixels.
    static func layout(_ item: SlideTextItem, canvas: CGSize, language: String) -> SlideTextLayout {
        let size = CGFloat(item.size)
        let font = SlideFonts.ctFont(item.font, size: size)
        let maxWidth = CGFloat(item.width) * canvas.width
        let text = item.uppercase ? item.text.uppercased(with: Locale(identifier: language)) : item.text

        // 1. Break each paragraph into lines no wider than the box (Core Text's line breaking, which follows the
        // language's rules and breaks inside a word only when the word alone is too wide).
        var broken: [(line: CTLine, width: CGFloat, isEmpty: Bool)] = []
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTLanguageAttributeName: language as CFString,
            kCTForegroundColorFromContextAttributeName: true,
        ]
        let paragraphs = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        for paragraph in paragraphs {
            let string = CFAttributedStringCreate(nil, String(paragraph) as CFString, attributes as CFDictionary)!
            let length = CFAttributedStringGetLength(string)
            if length == 0 {
                broken.append((CTLineCreateWithAttributedString(string), 0, true))
                continue
            }
            let typesetter = CTTypesetterCreateWithAttributedString(string)
            var start = 0
            while start < length {
                var count = CTTypesetterSuggestLineBreak(typesetter, start, Double(maxWidth))
                if count <= 0 { count = 1 }
                let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
                let advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) - CGFloat(CTLineGetTrailingWhitespaceWidth(line))
                broken.append((line, max(0, advance), false))
                start += count
            }
        }

        // 2. Vertical metrics from the item's own font; the block anchored at y and kept on the canvas.
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let contentHeight = ascent + descent
        let lineBox = size * CGFloat(item.lineHeight)
        let total = CGFloat(broken.count) * lineBox
        let anchorY = CGFloat(item.y) * canvas.height
        var top: CGFloat = switch item.anchor {
        case .top: anchorY
        case .middle: anchorY - total / 2
        case .bottom: anchorY - total
        }
        top = min(max(top, 0), max(0, canvas.height - total))
        // Kept on the canvas sideways too (sweep library #21): a left-aligned block near the right edge (or a right-aligned
        // one near the left) used to run off the slide in the export. The anchor moves just enough for the widest line.
        let widest = broken.map(\.width).max() ?? 0
        let (lowest, highest): (CGFloat, CGFloat) = switch item.align {
        case .left: (0, canvas.width - widest)
        case .right: (widest, canvas.width)
        case .center: (widest / 2, canvas.width - widest / 2)
        }
        let anchorX = min(max(CGFloat(item.x) * canvas.width, lowest), max(lowest, highest))

        // 3. Place each line by the alignment.
        let lines = broken.enumerated().map { i, b -> SlideTextLayout.Line in
            let x: CGFloat = switch item.align {
            case .left: anchorX
            case .right: anchorX - b.width
            case .center: anchorX - b.width / 2
            }
            let lineTop = top + CGFloat(i) * lineBox
            let baseline = lineTop + (lineBox - contentHeight) / 2 + ascent
            return SlideTextLayout.Line(line: b.line, x: x, width: b.width, top: lineTop, height: lineBox, baseline: baseline, isEmpty: b.isEmpty)
        }
        let boxLeft: CGFloat = switch item.align {
        case .left: anchorX
        case .right: anchorX - maxWidth
        case .center: anchorX - maxWidth / 2
        }
        return SlideTextLayout(lines: lines, contentHeight: contentHeight, top: top, height: total, maxWidth: maxWidth,
                               box: CGRect(x: boxLeft, y: top, width: maxWidth, height: total), text: text)
    }

    // MARK: Rendering

    /// The slide as a `CIImage` of `size` pixels (origin at zero). A size of another shape than the canvas gets the
    /// slide scaled to fit and centred on the background colour.
    static func render(_ spec: SlideshowSpec, slide index: Int, size: CGSize, images: [SlideImage: CGImage]) -> CIImage {
        guard let image = renderCGImage(spec, slide: index, size: size, images: images) else {
            return CIImage(color: CIColor(cgColor: color(spec.style.background))).cropped(to: CGRect(origin: .zero, size: size))
        }
        return CIImage(cgImage: image)
    }

    /// The slide as a `CGImage`, for PNG export and tests; nil only if a bitmap of that size can't be made.
    static func renderCGImage(_ spec: SlideshowSpec, slide index: Int, size: CGSize, images: [SlideImage: CGImage]) -> CGImage? {
        let width = max(1, Int(size.width.rounded())), height = max(1, Int(size.height.rounded()))
        guard spec.slides.indices.contains(index),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        draw(spec, slide: index, in: context, size: CGSize(width: width, height: height), images: images)
        return context.makeImage()
    }

    /// Draws the slide into a bitmap context of `size` pixels whose origin is bottom-left (Core Graphics' default).
    /// `zoom` scales the photos (not the text) about each one's `focus` (0–1 within the photo; centre when absent): the
    /// video's slow push-in (Slideshow/SlideVideo.swift). 1 draws the still slide.
    static func draw(_ spec: SlideshowSpec, slide index: Int, in context: CGContext, size: CGSize, images: [SlideImage: CGImage],
                     zoom: CGFloat = 1, focus: [SlideImage: CGPoint] = [:]) {
        drawBase(spec, slide: index, in: context, size: size, images: images, zoom: zoom, focus: focus)
        drawTop(spec, slide: index, in: context, size: size, images: images)
    }

    /// The slide's still layer (overlay, text, logo) on a clear bitmap of `size`, for laying over moving photos.
    static func renderTop(_ spec: SlideshowSpec, slide index: Int, size: CGSize, images: [SlideImage: CGImage]) -> CGImage? {
        let width = max(1, Int(size.width.rounded())), height = max(1, Int(size.height.rounded()))
        guard spec.slides.indices.contains(index), let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        drawTop(spec, slide: index, in: context, size: CGSize(width: width, height: height), images: images)
        return context.makeImage()
    }

    /// Canvas pixels, y down, centred in `size`, with the text settings every layer draws with.
    private static func enterCanvas(_ spec: SlideshowSpec, context: CGContext, size: CGSize) {
        let canvas = spec.canvas.size
        let scale = min(size.width / canvas.width, size.height / canvas.height)
        context.translateBy(x: (size.width - canvas.width * scale) / 2, y: size.height - (size.height - canvas.height * scale) / 2)
        context.scaleBy(x: scale, y: -scale)
        context.interpolationQuality = .high
        context.setAllowsAntialiasing(true)
        context.setShouldSmoothFonts(false)
        context.setAllowsFontSubpixelQuantization(false)
        context.setShouldSubpixelQuantizeFonts(false)
        context.setAllowsFontSubpixelPositioning(true)
        context.setShouldSubpixelPositionFonts(true)
    }

    /// The background colour and the photos, aspect-filled into the cells and pushed in by `zoom`.
    static func drawBase(_ spec: SlideshowSpec, slide index: Int, in context: CGContext, size: CGSize, images: [SlideImage: CGImage],
                         zoom: CGFloat = 1, focus: [SlideImage: CGPoint] = [:]) {
        let slide = spec.slides[index]
        let canvas = spec.canvas.size
        let style = spec.style
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(color(style.background))
        context.fill(CGRect(origin: .zero, size: size))
        enterCanvas(spec, context: context, size: size)

        // Photos, aspect-filled into the cells.
        let radius = CGFloat(style.radius)
        let cells = style.layout.cells(canvas: canvas, gap: CGFloat(style.gap))
        for (i, cell) in cells.enumerated() {
            let path = roundedRect(cell, radius: radius)
            if i < slide.images.count, let ref = slide.images[i], let image = images[ref] {
                context.saveGState()
                context.addPath(path)
                context.clip()
                var rect = aspectFill(CGSize(width: image.width, height: image.height), in: cell)
                if zoom != 1 {
                    let f = focus[ref] ?? CGPoint(x: 0.5, y: 0.5)
                    let pivot = CGPoint(x: rect.minX + rect.width * f.x, y: rect.minY + rect.height * f.y)
                    rect = CGRect(x: pivot.x - (pivot.x - rect.minX) * zoom, y: pivot.y - (pivot.y - rect.minY) * zoom,
                                  width: rect.width * zoom, height: rect.height * zoom)
                }
                drawImage(image, in: rect, context: context)
                context.restoreGState()
            } else {
                context.setFillColor(color(emptyCell))
                context.addPath(path)
                context.fillPath()
            }
        }
    }

    /// The overlay, each text item and the logo: what stays still while the photos push in.
    static func drawTop(_ spec: SlideshowSpec, slide index: Int, in context: CGContext, size: CGSize, images: [SlideImage: CGImage]) {
        let slide = spec.slides[index]
        let canvas = spec.canvas.size
        let style = spec.style
        context.saveGState()
        defer { context.restoreGState() }
        enterCanvas(spec, context: context, size: size)

        if style.overlay.opacity > 0 {
            context.setFillColor(color(style.overlay.color, alpha: style.overlay.opacity))
            context.fill(CGRect(origin: .zero, size: canvas))
        }

        for item in slide.texts where !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            drawText(item, layout: layout(item, canvas: canvas, language: spec.language), context: context)
        }

        if let logo = style.logo, let image = images[logo.image] {
            let side = canvas.width * CGFloat(logo.scale)
            let pad = canvas.width * 0.04
            let box = CGRect(x: logo.position.isLeft ? pad : canvas.width - pad - side,
                             y: logo.position.isTop ? pad : canvas.height - pad - side, width: side, height: side)
            // A square box with the logo fitted into its corner: a wide logo keeps its width, a tall one its height.
            let fit = min(side / CGFloat(image.width), side / CGFloat(image.height))
            let w = CGFloat(image.width) * fit, h = CGFloat(image.height) * fit
            let rect = CGRect(x: logo.position.isLeft ? box.minX : box.maxX - w, y: logo.position.isTop ? box.minY : box.maxY - h, width: w, height: h)
            drawImage(image, in: rect, context: context)
        }
    }

    private static func drawText(_ item: SlideTextItem, layout: SlideTextLayout, context: CGContext) {
        let size = CGFloat(item.size)
        if item.style == .background || item.style == .lightBackground {
            let fill = item.style == .lightBackground ? "#ffffff" : item.accent
            let padX = size * 0.32, padY = size * 0.12, corner = size * 0.22
            context.setFillColor(color(fill))
            for line in layout.lines where !line.isEmpty {
                let h = layout.contentHeight + padY * 2
                let rect = CGRect(x: line.x - padX, y: line.top + (line.height - h) / 2, width: line.width + padX * 2, height: h)
                context.addPath(roundedRect(rect, radius: corner))
                context.fillPath()
            }
        }

        context.saveGState()
        // Text space: y up, inside the y-down canvas.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        if item.style == .outline {
            context.setTextDrawingMode(.stroke)
            context.setLineWidth(size * 0.16)
            context.setLineJoin(.round)
            context.setStrokeColor(color(item.accent))
            for line in layout.lines where !line.isEmpty {
                context.textPosition = CGPoint(x: line.x, y: line.baseline)
                CTLineDraw(line.line, context)
            }
        }
        context.setTextDrawingMode(.fill)
        context.setFillColor(color(item.color))
        for line in layout.lines where !line.isEmpty {
            context.textPosition = CGPoint(x: line.x, y: line.baseline)
            CTLineDraw(line.line, context)
        }
        context.restoreGState()
    }

    // MARK: Helpers

    /// The rect an image of `size` fills `cell` with, centred, cropping the overflow (CSS `object-fit: cover`).
    static func aspectFill(_ size: CGSize, in cell: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return cell }
        let s = max(cell.width / size.width, cell.height / size.height)
        let w = size.width * s, h = size.height * s
        return CGRect(x: cell.midX - w / 2, y: cell.midY - h / 2, width: w, height: h)
    }

    /// Draws an image upright into a y-down context.
    private static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: rect.minY + rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: rect)
        context.restoreGState()
    }

    private static func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let r = min(radius, rect.width / 2, rect.height / 2)
        return r > 0 ? CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil) : CGPath(rect: rect, transform: nil)
    }

    /// An sRGB colour for "#rrggbb" (black when malformed; validation rejects that first).
    static func color(_ hex: String, alpha: Double = 1) -> CGColor {
        let c = hexComponents(hex) ?? (0, 0, 0)
        return CGColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: alpha)
    }

    /// "#rrggbb" → 0…1 components (inlined from ezReels' Brand.components).
    static func hexComponents(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
}
