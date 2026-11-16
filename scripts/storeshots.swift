import AppKit
import CoreText

let args = CommandLine.arguments
let (inDir, outDir, fontDir, iconDir) = (args[1], args[2], args[3], args[4])
for f in ["Anton-Regular.ttf", "Inter.ttf"] {
    CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "\(fontDir)/\(f)") as CFURL, .process, nil)
}
func hex(_ h: UInt32) -> NSColor { NSColor(srgbRed: CGFloat((h >> 16) & 0xff) / 255, green: CGFloat((h >> 8) & 0xff) / 255, blue: CGFloat(h & 0xff) / 255, alpha: 1) }

// (screen file, headline, subline, gradient top, gradient bottom, stickers)
let slides: [(String, String, String, UInt32, UInt32, [String])] = [
    ("01.png", "JUST ASK.", "Where to camp, tonight's weather,\nwhat to pack. Answers with sources.", 0xffb347, 0xff5f8f, ["sparkles", "tent"]),
    ("02.png", "29,105 CAMPSITES", "Every state, from open public data.\nOnly the ones you can judge.", 0x5eead4, 0x2f9bff, ["camping", "mountain"]),
    ("03.png", "CAN I CAMP HERE?", "Long-press anywhere to see\nwho manages the land.", 0xffd166, 0xff7a45, ["compass", "tent"]),
    ("04.png", "KNOW BEFORE YOU GO", "Camper reports, the nearest help,\nand county context.", 0xff8fb1, 0x9b6bff, ["shield", "hospital"]),
    ("05.png", "FISH & HUNT SMARTER", "What's biting, live river flow,\nand license rules for every state.", 0x7dd3fc, 0x22c55e, ["fishing", "deer"]),
    ("06.png", "PACK EXACTLY RIGHT", "Water, food and gear for your trip.\nEvery line has a source.", 0xa3e635, 0x10b981, ["boot", "droplet"]),
    ("07.png", "A CAMP EVERY NIGHT", "Road trips planned around\nhow far you like to drive.", 0xc084fc, 0xff8a1f, ["minibus", "fire"]),
    ("08.png", "TONIGHT, NOT NOON", "Lows, wind, smoke and fires\nfor the nights you'll be there.", 0x60a5fa, 0xa855f7, ["moon", "star"]),
]

func sticker(_ name: String) -> NSImage? { NSImage(contentsOfFile: "\(iconDir)/e3d-\(name).imageset/\(name).png") }
let confettiColors: [UInt32] = [0xffffff, 0xffd166, 0xff6b3d, 0x7b61ff, 0x1fbf75, 0x1ea7fd, 0xf0437a]

let W: CGFloat = 1206, H: CGFloat = 2622
for (n, (file, title, sub, top, bottom, stickers)) in slides.enumerated() {
    guard let shot = NSImage(contentsOfFile: "\(inDir)/\(file)") else { continue }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // Background: a vertical gradient with a soft glow behind the phone.
    NSGradient(starting: hex(top), ending: hex(bottom))!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.35), .clear])!
        .draw(in: NSBezierPath(ovalIn: NSRect(x: W * 0.1, y: H * 0.18, width: W * 0.8, height: H * 0.55)), relativeCenterPosition: .zero)

    // Confetti: soft dots, placed the same way every run.
    var seed = UInt64(n + 7) &* 6364136223846793005
    func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
    for _ in 0..<26 {
        let r = 6 + rnd() * 14
        hex(confettiColors[Int(rnd() * CGFloat(confettiColors.count)) % confettiColors.count]).withAlphaComponent(0.55 + rnd() * 0.35).setFill()
        NSBezierPath(ovalIn: NSRect(x: rnd() * W, y: H * 0.62 + rnd() * H * 0.38, width: r, height: r)).fill()
    }
    // Two tilted 3D stickers beside the headline.
    for (i, name) in stickers.prefix(2).enumerated() {
        guard let img = sticker(name) else { continue }
        let size: CGFloat = 190
        let center = i == 0 ? NSPoint(x: 120, y: H - 140) : NSPoint(x: W - 120, y: H - 520)
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform(); t.translateX(by: center.x, yBy: center.y); t.rotate(byDegrees: i == 0 ? 14 : -12); t.concat()
        let sh = NSShadow(); sh.shadowBlurRadius = 18; sh.shadowOffset = NSSize(width: 0, height: -8); sh.shadowColor = NSColor.black.withAlphaComponent(0.25); sh.set()
        img.draw(in: NSRect(x: -size / 2, y: -size / 2, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
    }

    // Headline and subline.
    let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineSpacing = 6
    let titleAttrs: [NSAttributedString.Key: Any] = [.font: NSFont(name: "Anton-Regular", size: 118) ?? .boldSystemFont(ofSize: 110),
                                                     .foregroundColor: NSColor.white, .paragraphStyle: para, .kern: 1.5, .shadow: { let t = NSShadow(); t.shadowBlurRadius = 14; t.shadowOffset = NSSize(width: 0, height: -4); t.shadowColor = NSColor.black.withAlphaComponent(0.22); return t }()]
    let subAttrs: [NSAttributedString.Key: Any] = [.font: NSFont(name: "Inter", size: 50) ?? .systemFont(ofSize: 50, weight: .medium),
                                                   .foregroundColor: NSColor.white, .paragraphStyle: para, .shadow: { let t = NSShadow(); t.shadowBlurRadius = 10; t.shadowOffset = NSSize(width: 0, height: -2); t.shadowColor = NSColor.black.withAlphaComponent(0.18); return t }()]
    (title as NSString).draw(in: NSRect(x: 50, y: H - 330, width: W - 100, height: 170), withAttributes: titleAttrs)
    (sub as NSString).draw(in: NSRect(x: 70, y: H - 500, width: W - 140, height: 150), withAttributes: subAttrs)

    // The phone: the real screen, rounded, with a dark bezel and a shadow, running off the bottom.
    let pw: CGFloat = W * 0.80, ph = pw * (2622 / 1206)
    let px = (W - pw) / 2, py = H - 580 - ph
    let bezel = NSRect(x: px - 18, y: py - 18, width: pw + 36, height: ph + 36)
    let shadow = NSShadow(); shadow.shadowBlurRadius = 60; shadow.shadowOffset = NSSize(width: 0, height: -24)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    NSGraphicsContext.saveGraphicsState(); shadow.set()
    hex(0x111015).setFill(); NSBezierPath(roundedRect: bezel, xRadius: 92, yRadius: 92).fill()
    NSGraphicsContext.restoreGraphicsState()
    let screen = NSRect(x: px, y: py, width: pw, height: ph)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: screen, xRadius: 76, yRadius: 76).addClip()
    shot.draw(in: screen)
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(file)"))
}
print("done")
