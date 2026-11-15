import SwiftUI

/// "Pack for this" cards. Quiet by design: shown only when conditions call for them, no animation,
/// and they can be turned off in Settings.
struct GearTipsSection: View {
    let tips: [GearTip]
    var title = "Pack for this"
    @AppStorage("showGearTips") private var showGearTips = true
    @Environment(\.openURL) private var openURL

    var body: some View {
        if showGearTips && !tips.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                ForEach(tips) { tip in card(tip) }
                if GearLinks.hasAffiliates {
                    Text("ezcamps may earn a commission from these links, at no cost to you.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func card(_ tip: GearTip) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tip.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.canyon, in: .rect(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(tip.title).font(.subheadline.weight(.semibold))
                Text(tip.why).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    ForEach(GearLinks.retailers) { r in
                        if let url = r.searchURL(tip.query) {
                            Button {
                                openURL(url)
                            } label: {
                                Label(r.name, systemImage: "bag")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .foregroundStyle(Color.canyon)
                                    .background(Color.canyon.opacity(0.12), in: .capsule)
                            }
                            .buttonStyle(.pressable)
                            .accessibilityLabel("Shop \(tip.query) at \(r.name)")
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.canyon.opacity(0.07), in: .rect(cornerRadius: 14, style: .continuous))
    }
}
