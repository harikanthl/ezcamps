import Foundation
import SwiftData
import Vision
import CoreGraphics
import ImageIO

// "My gear": the things you own, as cut-out stickers on shelves, so pack lists can be ticked off
// with your own gear. Categories follow Packstack's MIT category list, adapted for car camping,
// fishing and hunting (docs/GEAR-CLOSET.md). Everything stays on the phone.

enum GearCategory: String, CaseIterable, Identifiable, Codable {
    case shelter, sleep, kitchen, water, lighting, clothing, footwear, packs, tools, firstAid, safety, navigation, fishing, hunting, comfort

    var id: String { rawValue }

    var label: String {
        switch self {
        case .shelter: "Shelter"
        case .sleep: "Sleep"
        case .kitchen: "Kitchen"
        case .water: "Water"
        case .lighting: "Lighting"
        case .clothing: "Clothing"
        case .footwear: "Footwear"
        case .packs: "Packs and bags"
        case .tools: "Tools"
        case .firstAid: "First aid"
        case .safety: "Safety"
        case .navigation: "Navigation"
        case .fishing: "Fishing"
        case .hunting: "Hunting"
        case .comfort: "Fun and comfort"
        }
    }

    var icon3D: String {
        switch self {
        case .shelter: "tent"
        case .sleep: "moon"
        case .kitchen: "forkknife"
        case .water: "droplet"
        case .lighting: "voltage"
        case .clothing: "shield"
        case .footwear: "boot"
        case .packs: "camping"
        case .tools: "compass"
        case .firstAid: "hospital"
        case .safety: "warning"
        case .navigation: "compass"
        case .fishing: "fishing"
        case .hunting: "deer"
        case .comfort: "sparkles"
        }
    }

    /// Which categories matter for an activity, for the pack list's "My gear" tab.
    static func relevant(to acts: Set<PackActivity>) -> [GearCategory] {
        var out: [GearCategory] = [.water, .firstAid, .lighting, .clothing, .navigation, .safety]
        if acts.contains(.camping) || acts.contains(.backpacking) || acts.contains(.hunting) || acts.contains(.fishing) {
            out += [.shelter, .sleep, .kitchen, .comfort, .tools]
        }
        if acts.contains(where: { [.dayHiking, .backpacking, .trailRunning, .hunting].contains($0) }) { out += [.footwear, .packs] }
        if acts.contains(.mountainBiking) { out += [.packs, .tools] }
        if acts.contains(.fishing) { out.append(.fishing) }
        if acts.contains(.hunting) { out.append(.hunting) }
        var seen = Set<GearCategory>()
        return allCases.filter { c in out.contains(c) && seen.insert(c).inserted }
    }
}

@Model
final class GearItem {
    var id: UUID = UUID()
    var name: String = ""
    var categoryRaw: String = GearCategory.comfort.rawValue
    /// PNG in Documents/Gear: a cut-out sticker, or the photo itself when the cut-out couldn't run.
    var imageFile: String = ""
    var isCutout: Bool = true
    var quantity: Int = 1
    var weightGrams: Int?
    var notes: String = ""
    var addedAt: Date = Date.now
    /// False while it waits in the Review tray for the person to confirm the name and category.
    var reviewed: Bool = false

    init(name: String, category: GearCategory, imageFile: String, isCutout: Bool) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.imageFile = imageFile
        self.isCutout = isCutout
    }

    var category: GearCategory {
        get { GearCategory(rawValue: categoryRaw) ?? .comfort }
        set { categoryRaw = newValue.rawValue }
    }

    var imageURL: URL { GearStore.folder.appending(path: imageFile) }
}

enum GearStore {
    static var folder: URL { UserStickers.folder }

    /// Cuts every item out of the photo (on-device Vision): lay your gear on the ground, take one photo, and
    /// each thing becomes its own sticker. Where Vision can't run (the Simulator, very old devices) the photo
    /// itself is kept as one item.
    static func makeStickers(from data: Data) async throws -> [(file: String, isCutout: Bool, image: CGImage)] {
        do {
            return try await StickerCutout.makeEach(from: data).compactMap { url in
                guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
                return (url.lastPathComponent, true, img)
            }
        } catch StickerCutout.CutoutError.nothingInFront {
            throw StickerCutout.CutoutError.nothingInFront
        } catch {
            let photo = try StickerCutout.photo(data)
            let url = try UserStickers.save(photo)
            return [(url.lastPathComponent, false, photo)]
        }
    }

    static func delete(_ item: GearItem) {
        try? FileManager.default.removeItem(at: item.imageURL)
    }

    /// A suggested name and category from Apple's on-device image classifier. Only a suggestion:
    /// new items wait in the Review tray until the person confirms.
    static func suggest(for image: CGImage) async -> (name: String, category: GearCategory) {
        let request = ClassifyImageRequest()
        guard let results = try? await request.perform(on: image) else { return ("New gear", .comfort) }
        let top = results.filter { $0.confidence > 0.1 }.prefix(8).map(\.identifier)
        for id in top {
            if let c = category(for: id) { return (pretty(id), c) }
        }
        return (top.first.map(pretty) ?? "New gear", .comfort)
    }

    private static func pretty(_ id: String) -> String {
        id.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static let keywords: [(GearCategory, [String])] = [
        (.shelter, ["tent", "tarp", "canopy", "hammock", "awning"]),
        (.sleep, ["sleeping", "bag", "pillow", "mattress", "blanket", "cot", "pad"]),
        (.kitchen, ["stove", "pot", "pan", "cookware", "kettle", "cup", "mug", "plate", "utensil", "cooler", "grill", "spatula", "bottle opener"]),
        (.water, ["water bottle", "bottle", "canteen", "filter", "jug", "flask"]),
        (.lighting, ["lantern", "flashlight", "headlamp", "lamp", "torch", "candle"]),
        (.footwear, ["boot", "shoe", "sandal", "sneaker"]),
        (.clothing, ["jacket", "coat", "shirt", "pants", "hat", "glove", "sock", "fleece", "sweater", "vest", "raincoat"]),
        (.packs, ["backpack", "bag", "rucksack", "duffel", "dry bag", "pack"]),
        (.tools, ["knife", "axe", "hatchet", "saw", "multitool", "shovel", "hammer", "rope", "tool"]),
        (.firstAid, ["bandage", "first aid", "medicine", "kit"]),
        (.navigation, ["compass", "map", "gps"]),
        (.safety, ["whistle", "spray", "helmet", "orange", "vest"]),
        (.fishing, ["fishing", "rod", "reel", "tackle", "lure", "net", "fish"]),
        (.hunting, ["rifle", "bow", "arrow", "binocular", "decoy", "camouflage", "blind", "scope"]),
        (.comfort, ["chair", "table", "guitar", "game", "book", "speaker"]),
    ]

    private static func category(for identifier: String) -> GearCategory? {
        let id = identifier.lowercased().replacingOccurrences(of: "_", with: " ")
        return keywords.first { $0.1.contains(where: id.contains) }?.0
    }
}
