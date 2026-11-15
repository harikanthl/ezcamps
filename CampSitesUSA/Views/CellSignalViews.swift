import SwiftUI

/// Shared vocabulary for cell reports.
enum CellSignal {
    static let carriers = ["AT&T", "Verizon", "T-Mobile", "Other"]
    static let levels = ["No signal", "Weak", "Usable", "Strong"]

    static func color(_ level: Int) -> Color {
        [Color.berry, .canyon, .sky, .meadow][max(0, min(3, level))]
    }

    static func bars(_ level: Int) -> String {
        level == 0 ? "antenna.radiowaves.left.and.right.slash" : "cellularbars"
    }
}

/// Cell signal on the site card: the official note (NPS) plus reports from visits.
/// Per-carrier FCC coverage is planned once an FCC data API token is configured.
struct CellSignalSection: View {
    let site: Site
    let visits: [Visit]

    /// Latest report per carrier.
    private var reports: [(carrier: String, visit: Visit)] {
        var latest: [String: Visit] = [:]
        for v in visits where v.carrier != nil && v.signal != nil {
            if let existing = latest[v.carrier!], existing.date >= v.date { continue }
            latest[v.carrier!] = v
        }
        return CellSignal.carriers.compactMap { c in latest[c].map { (c, $0) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cell signal").font(.headline)

            if let official = site.cell {
                row(symbol: official == "none" ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right",
                    color: official == "none" ? .berry : official == "seasonal" ? .canyon : .meadow,
                    title: officialText(official), detail: "National Park Service")
            }

            ForEach(reports, id: \.carrier) { r in
                let level = r.visit.signal ?? 0
                row(symbol: CellSignal.bars(level), color: CellSignal.color(level),
                    title: "\(r.carrier): \(CellSignal.levels[level])",
                    detail: "Your visit · \(r.visit.date.formatted(.dateTime.month(.abbreviated).day().year()))"
                        + (r.visit.verified ? " · verified" : ""))
            }

            if site.cell == nil && reports.isEmpty {
                Text("No signal reports yet. Rate your stay to add one for your carrier.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func officialText(_ v: String) -> String {
        switch v {
        case "year-round": "Cell reception year-round"
        case "seasonal": "Cell reception in season only"
        default: "No cell reception"
        }
    }

    private func row(symbol: String, color: Color, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(color, in: .rect(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
