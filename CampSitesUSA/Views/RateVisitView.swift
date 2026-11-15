import SwiftUI
import SwiftData

struct RateVisitView: View {
    let site: Site

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationProvider.self) private var location

    @State private var rating = 0
    @State private var date = Date.now
    @State private var tags: Set<String> = []
    @State private var note = ""

    private var distance: Double? { location.distance(to: site.coordinate) }
    private var isOnSite: Bool { (distance ?? .infinity) <= Visit.verifyRadius }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Text(site.name).font(.headline).multilineTextAlignment(.center)
                    StarPicker(rating: $rating)
                    Text(ratingCaption).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                        .animation(.easeOut(duration: 0.15), value: rating)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                verification
            }

            Section("What stood out?") {
                FlowLayout(spacing: 8) {
                    ForEach(Visit.tagOptions, id: \.self) { tag in
                        Chip(title: tag, tint: .sunset, isOn: tags.contains(tag)) {
                            tags.formSymmetricDifference([tag])
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Notes") {
                DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                TextField("Road condition, best spots, tips…", text: $note, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle("Rate your stay")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(rating == 0).fontWeight(.semibold)
            }
        }
        .tint(.sunset)
        .task { location.start() }
    }

    private var ratingCaption: String {
        ["Tap a star to rate", "Wouldn't return", "Meh", "Decent", "Really good", "Hidden gem!"][rating]
    }

    @ViewBuilder private var verification: some View {
        if isOnSite {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("You're here. This will be a verified visit").font(.subheadline.weight(.semibold))
                    Text("Verified ratings carry more weight for other campers.").font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.meadow)
            }
        } else {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(distance.map { "You're \(Measurement(value: $0, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))) away" }
                         ?? "Location unavailable")
                        .font(.subheadline.weight(.semibold))
                    Text("Rate while you're at the site to get a Verified visit badge.").font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "location.slash.fill").foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        context.insert(Visit(site: site, date: date, rating: rating,
                             tags: Visit.tagOptions.filter(tags.contains), note: note, verified: isOnSite))
        dismiss()
    }
}

/// Simple wrapping layout for tag chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (i, p) in result.positions.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        var positions: [CGPoint] = []
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            positions.append(CGPoint(x: x, y: y))
            x += s.width + spacing
            rowH = max(rowH, s.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowH), positions)
    }
}
