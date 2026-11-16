import SwiftUI

// MARK: - Palette
// Bright, lively, outdoorsy. Saturated fills carry white text in both light and dark mode.

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    static let sunset = Color(hex: 0xFF6B3D)     // primary accent: coral sunset
    static let meadow = Color(hex: 0x1FBF75)     // free / go
    static let sky = Color(hex: 0x1EA7FD)        // water, RV parks
    static let sunshine = Color(hex: 0xFFC233)   // stars, highlights
    static let berry = Color(hex: 0xF0437A)      // saved / hearts
    static let dusk = Color(hex: 0x7B61FF)       // trips, night
    static let canyon = Color(hex: 0xFF8A1F)     // dispersed sites
}

extension Site.Kind {
    var color: Color {
        switch self {
        case .campground: .dusk
        case .dispersed: .canyon
        case .rvPark: .sky
        }
    }
}

// MARK: - Press feedback
// Pressables scale to 0.97 with a quick ease-out (≈160ms) so the UI feels like it's listening.
// Release is just as fast. Reduce Motion drops the scale and keeps a light opacity cue.

struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.8 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

// MARK: - Chips & badges

/// Filter chip. Toggled many times per session, so only a short color change, no movement.
struct Chip: View {
    let title: String
    var symbol: String?
    var tint: Color = .sunset
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.caption.weight(.semibold)) }
                Text(title).font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .background(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(.regularMaterial), in: .capsule)
            .overlay(Capsule().strokeBorder(isOn ? .clear : tint.opacity(0.35), lineWidth: 1))
            .animation(.easeOut(duration: 0.12), value: isOn)
            .contentShape(.capsule)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct Badge: View {
    let text: String
    var symbol: String?
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption.weight(.bold))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(.white)
        .background(color, in: .capsule)
    }
}

/// Big, colorful action tile used in the site sheet.
struct ActionTile: View {
    let title: String
    let symbol: String
    let color: Color
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title3.weight(.semibold))
                Text(title).font(.caption.weight(.semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(filled ? .white : color)
            .background(filled ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.14)),
                        in: .rect(cornerRadius: 16, style: .continuous))
            .contentShape(.rect(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Stars

struct StarRatingView: View {
    let rating: Double
    var size: Font = .caption

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: Double(i) <= rating ? "star.fill"
                      : Double(i) - 0.5 <= rating ? "star.leadinghalf.filled" : "star")
            }
        }
        .font(size)
        .foregroundStyle(Color.sunshine)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: "%.1f out of 5 stars", rating))
    }
}

/// Tap-to-rate stars. Picking a star gives a small spring "pop" on that star. Rating is a rare,
/// deliberate action, so a touch of delight is fine here.
struct StarPicker: View {
    @Binding var rating: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    rating = i
                } label: {
                    Image(systemName: i <= rating ? "star.fill" : "star")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(i <= rating ? Color.sunshine : Color.secondary.opacity(0.4))
                        .scaleEffect(i == rating && !reduceMotion ? 1.12 : 1)
                        .animation(.spring(duration: 0.3, bounce: 0.3), value: rating)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("\(i) star\(i == 1 ? "" : "s")")
            }
        }
        .sensoryFeedback(.selection, trigger: rating)
    }
}

// MARK: - Logo

/// The ezcamp glass-tile logo (same art as the app icon), clipped to the iOS icon shape.
struct AppLogo: View {
    var size: CGFloat = 64

    var body: some View {
        Image("Logo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: size * 0.225, style: .continuous))
            .shadow(color: Color.dusk.opacity(0.35), radius: size * 0.12, y: size * 0.06)
            .accessibilityHidden(true)
    }
}

// MARK: - 3D icons (Microsoft Fluent Emoji 3D, MIT)

/// A 3D icon from Assets › Icons3D. Decorative: the text next to it carries the meaning.
/// Used for content (section headers, amenities, activities, services, empty states); controls,
/// tab bar and map clusters keep flat SF Symbols, which read better small.
struct Icon3D: View {
    let name: String
    var size: CGFloat = 24

    init(_ name: String, size: CGFloat = 24) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Image("e3d-\(name)")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Section title with its 3D icon, e.g. 🌙 Night conditions.
struct SectionTitle: View {
    let title: String
    let icon: String
    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 26

    init(_ title: String, icon: String) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 8) {
            Icon3D(icon, size: size)
            Text(title).font(.headline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Empty state with a 3D icon instead of a flat symbol.
struct EmptyState3D: View {
    let title: String
    let icon: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: 12) {
                Icon3D(icon, size: 72)
                Text(title)
            }
        } description: {
            Text(message)
        }
    }
}

extension Site.Kind {
    var icon3D: String {
        switch self {
        case .campground: "camping"
        case .dispersed: "mountain"
        case .rvPark: "minibus"
        }
    }
}

extension Amenity {
    var icon3D: String {
        switch self {
        case .water: "droplet"
        case .toilets: "toilet"
        case .showers: "shower"
        case .dump: "wastebasket"
        case .electric: "voltage"
        case .tents: "tent"
        case .rv: "minibus"
        case .wifi: "antenna"
        case .fireRing: "fire"
        case .picnicTable: "forkknife"
        }
    }
}

extension Activity.Kind {
    var icon3D: String {
        switch self {
        case .hike: "boot"
        case .bike: "bicycle"
        case .horse: "horse"
        case .ohv: "suv"
        case .climb: "climbing"
        case .paddle: "canoe"
        case .boat: "sailboat"
        case .swim: "swimming"
        case .fish: "fishing"
        case .snow: "snowflake"
        case .scenic: "sunrise"
        case .program: "speech"
        case .other: "sparkles"
        }
    }
}

extension ServiceKind {
    var icon3D: String {
        switch self {
        case .gas: "fuel"
        case .groceries: "cart"
        case .hospital: "hospital"
        case .police: "police"
        }
    }
}
