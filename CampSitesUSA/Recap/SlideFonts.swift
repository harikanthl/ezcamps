// Lifted from ezReels (Slideshow/SlideFonts.swift @ edd2483). ezcamp bundles only some faces; missing ones fall back.
//
//  SlideFonts.swift
//  ezReels
//
//  The slide fonts: the eleven faces a slide's text can use (TikTok Sans, Bebas Neue, Anton, Inter, Inter
//  Regular, Montserrat, Cormorant, "Georgia Italic", Playfair Display, Poppins, Archivo Black), drawn from ten
//  SIL OFL files bundled in `Resources/Fonts/Slides`. Every file is pinned to one google/fonts commit and its
//  sha256 (a test checks the bundled bytes), so a slide looks the same on every device and in every export.
//
//  Ported from vireeel (`~/Projects/vireeel/packages/slides/src/fonts.ts`, `render/fontset.ts`; its DECISIONS
//  #22). Its substitutions carry over: "TikTok Display" is TikTok Sans (OFL, TikTok's own family) and "Georgia
//  Italic" is Gelasio Italic (OFL, metric-compatible with Georgia). Variable fonts get their weight through a
//  Core Text variation, as vireeel set HarfBuzz axes. vireeel's script fallbacks (Noto Sans SC/KR/Thai/Arabic/
//  Devanagari, Noto Emoji, 33 MB together) are not bundled: Core Text's cascade falls back to the iOS system
//  fonts for those scripts (PingFang, Apple SD Gothic Neo, Thonburi, Geeza Pro, Kohinoor, Apple Color Emoji),
//  which also gives colour emoji. vireeel's caption fonts (Coiny, Concert One…) belong to captions, not slides.
//
//  Fonts are created straight from their files (`CTFontManagerCreateFontDescriptorsFromURL`), so the renderer
//  never depends on registration or on a PostScript name resolving. They are deliberately not registered with
//  the process: nothing needs them by name, and registering at launch (asynchronous) changed the fonts WebKit saw
//  while the first title template rendered, so its frames came out different between two renders.
//

import CoreText
import Foundation

nonisolated enum SlideFont: String, Codable, CaseIterable, Sendable, Identifiable {
    case tiktokSans = "tiktok-sans"
    case bebasNeue = "bebas-neue"
    case anton
    case inter
    case interRegular = "inter-regular"
    case montserrat
    case cormorant
    case georgiaItalic = "georgia-italic"
    case playfair
    case poppins
    case archivoBlack = "archivo-black"

    var id: String { rawValue }

    /// The name in the font menu.
    var label: String {
        switch self {
        case .tiktokSans: "TikTok Sans"
        case .bebasNeue: "Bebas Neue"
        case .anton: "Anton"
        case .inter: "Inter"
        case .interRegular: "Inter Regular"
        case .montserrat: "Montserrat"
        case .cormorant: "Cormorant"
        case .georgiaItalic: "Georgia Italic"
        case .playfair: "Playfair Display"
        case .poppins: "Poppins"
        case .archivoBlack: "Archivo Black"
        }
    }

    var file: SlideFontFile {
        switch self {
        case .tiktokSans: .tiktokSans
        case .bebasNeue: .bebasNeue
        case .anton: .anton
        case .inter, .interRegular: .inter
        case .montserrat: .montserrat
        case .cormorant: .cormorant
        case .georgiaItalic: .gelasioItalic
        case .playfair: .playfair
        case .poppins: .poppinsBold
        case .archivoBlack: .archivoBlack
        }
    }

    /// The `wght` axis value for a variable file, nil for a static one.
    var weight: Double? {
        switch self {
        case .tiktokSans, .montserrat: 800
        case .inter, .playfair: 700
        case .interRegular: 450
        case .cormorant: 600
        case .georgiaItalic: 500
        case .bebasNeue, .anton, .poppins, .archivoBlack: nil
        }
    }

    /// The slide font for a brand font family name (`Brand.font`, a composition family), if there is one.
    init?(family: String) {
        let wanted = family.lowercased()
        guard let match = Self.allCases.first(where: { $0.label.lowercased() == wanted }) else { return nil }
        self = match
    }
}

/// One bundled font file, pinned to google/fonts commit `SlideFontFile.commit`.
nonisolated enum SlideFontFile: String, CaseIterable, Sendable {
    case tiktokSans = "TikTokSans.ttf"
    case bebasNeue = "BebasNeue-Regular.ttf"
    case anton = "Anton-Regular.ttf"
    case inter = "Inter.ttf"
    case montserrat = "Montserrat.ttf"
    case cormorant = "Cormorant.ttf"
    case gelasioItalic = "Gelasio-Italic.ttf"
    case playfair = "PlayfairDisplay.ttf"
    case poppinsBold = "Poppins-Bold.ttf"
    case archivoBlack = "ArchivoBlack-Regular.ttf"

    static let commit = "b5efa9c32e8f9b63005f5cdb1ad5527a77d2cd04"

    /// The path inside google/fonts, for re-downloading: https://raw.githubusercontent.com/google/fonts/<commit>/<source>.
    var source: String {
        switch self {
        case .tiktokSans: "ofl/tiktoksans/TikTokSans[opsz,slnt,wdth,wght].ttf"
        case .bebasNeue: "ofl/bebasneue/BebasNeue-Regular.ttf"
        case .anton: "ofl/anton/Anton-Regular.ttf"
        case .inter: "ofl/inter/Inter[opsz,wght].ttf"
        case .montserrat: "ofl/montserrat/Montserrat[wght].ttf"
        case .cormorant: "ofl/cormorant/Cormorant[wght].ttf"
        case .gelasioItalic: "ofl/gelasio/Gelasio-Italic[wght].ttf"
        case .playfair: "ofl/playfairdisplay/PlayfairDisplay[wght].ttf"
        case .poppinsBold: "ofl/poppins/Poppins-Bold.ttf"
        case .archivoBlack: "ofl/archivoblack/ArchivoBlack-Regular.ttf"
        }
    }

    var bytes: Int {
        switch self {
        case .tiktokSans: 761_964
        case .bebasNeue: 61_400
        case .anton: 170_812
        case .inter: 876_576
        case .montserrat: 744_936
        case .cormorant: 572_892
        case .gelasioItalic: 174_212
        case .playfair: 300_724
        case .poppinsBold: 155_996
        case .archivoBlack: 90_988
        }
    }

    var sha256: String {
        switch self {
        case .tiktokSans: "0e7f0a3e924c9a86478fc6fc2946de2e4ab8fc704ed72ee40434ade94bb9b0c6"
        case .bebasNeue: "08e4623805102d819f58601e46e345648846075e363b2ceb23313c2d1c83ec73"
        case .anton: "a4ba3a92350ebb031da0cb47630ac49eb265082ca1bc0450442f4a83ab947cab"
        case .inter: "29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"
        case .montserrat: "0f7b311b2f3279e4eef9b2f968bcdbab6e28f4daeb1f049f4f278a902bcd82f7"
        case .cormorant: "8f12cb21f05b61649192eaff13eeeb1b5619bc524feeae672fb916974259a076"
        case .gelasioItalic: "52559e845a4d33514e5f93bb9ae7dbeae1894a53f2c565a15f18af40cd337c09"
        case .playfair: "c40f2293766a503bc70cce9e512ef844a4ccb7cbcde792fe2ea31d191917d8d6"
        case .poppinsBold: "983676516167748b74de6f4771fb384c664fd913acb8b471122ecacf5da5ea6c"
        case .archivoBlack: "dd9a89a019b4849f66ab75455fe7bdf931311042cbb0f0f97acc061539703180"
        }
    }

    /// Where the file is in the app bundle (the synchronized group copies it to the bundle's root).
    var url: URL? {
        Bundle.main.url(forResource: (rawValue as NSString).deletingPathExtension, withExtension: "ttf")
    }
}

nonisolated enum SlideFonts {
    /// The `wght` variation axis tag as Core Text's number.
    private static let weightAxis = 0x7767_6874 // 'wght'

    /// One descriptor per slide font, read from its file once, with its weight variation applied.
    /// Immutable after creation, so sharing it across threads is safe.
    private nonisolated(unsafe) static let descriptors: [SlideFont: CTFontDescriptor] = {
        var out: [SlideFont: CTFontDescriptor] = [:]
        var fileDescriptors: [SlideFontFile: CTFontDescriptor] = [:]
        for file in SlideFontFile.allCases {
            guard let url = file.url,
                  let list = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                  let first = list.first else { continue }
            fileDescriptors[file] = first
        }
        for font in SlideFont.allCases {
            guard var descriptor = fileDescriptors[font.file] else { continue }
            if let weight = font.weight {
                descriptor = CTFontDescriptorCreateCopyWithVariation(descriptor, NSNumber(value: weightAxis) as CFNumber, CGFloat(weight))
            }
            out[font] = descriptor
        }
        return out
    }()

    /// Whether the font's file is in the bundle and readable.
    static func isAvailable(_ font: SlideFont) -> Bool { descriptors[font] != nil }

    /// The font at `size` canvas pixels. Falls back to the system's bold font if the file is missing, which a test
    /// rules out for the shipped app.
    static func ctFont(_ font: SlideFont, size: CGFloat) -> CTFont {
        if let descriptor = descriptors[font] { return CTFontCreateWithFontDescriptor(descriptor, size, nil) }
        return CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    }

}
