import SwiftUI

/// Download public-lands maps per state so the land layer and "Can I camp here?" work without signal.
struct OfflineMapsView: View {
    @Environment(OfflineStore.self) private var offline
    @State private var query = ""
    @State private var confirmDelete: StateBounds?

    private var downloaded: [StateBounds] { offline.states.filter { offline.packs[$0.code] != nil } }
    private var available: [StateBounds] {
        offline.states.filter { offline.packs[$0.code] == nil }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.code == query.uppercased() }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Works without signal", systemImage: "antenna.radiowaves.left.and.right.slash")
                        .font(.headline).foregroundStyle(Color.sky)
                    included("checkmark.circle.fill", "Every campsite, trail and activity is already on your phone.")
                    included("square.2.layers.3d.top.filled", "Download a state to keep its public-lands map and offline “Can I camp here?” answers.")
                    included("map.fill", "For turn-by-turn directions without signal, also download the area in Apple Maps (your profile › Offline Maps).")
                }
                .padding(.vertical, 4)
            }

            if let code = offline.downloading, let state = offline.state(code) {
                Section("Downloading") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(state.name).font(.body.weight(.semibold))
                            Spacer()
                            Text(offline.progress.formatted(.percent.precision(.fractionLength(0))))
                                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                        }
                        ProgressView(value: offline.progress).tint(.sky)
                        Button("Cancel", role: .cancel) { offline.cancel() }.font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
            }

            if let error = offline.lastError {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.berry) }
            }

            if !downloaded.isEmpty {
                Section {
                    ForEach(downloaded) { state in
                        let pack = offline.packs[state.code]!
                        HStack(spacing: 12) {
                            badge(state.code, filled: true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(state.name).font(.body.weight(.semibold))
                                Text("\(ByteCountFormatter.string(fromByteCount: Int64(pack.bytes), countStyle: .file)) · saved \(pack.downloadedAt.formatted(.dateTime.month(.abbreviated).day()))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.meadow)
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = state }
                        }
                    }
                } header: {
                    Text("On this iPhone")
                } footer: {
                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(offline.totalBytes), countStyle: .file)) in total. Swipe to delete.")
                }
            }

            Section("States") {
                ForEach(available) { state in
                    HStack(spacing: 12) {
                        badge(state.code, filled: false)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.name).font(.body.weight(.semibold))
                            Text("About \(max(1, Int(state.estimatedMB.rounded()))) MB").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            offline.download([state.code])
                        } label: {
                            Image(systemName: "arrow.down.circle.fill").font(.title2)
                        }
                        .buttonStyle(.pressable)
                        .foregroundStyle(Color.sky)
                        .disabled(offline.downloading != nil)
                        .accessibilityLabel("Download \(state.name)")
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Find a state")
        .navigationTitle("Offline maps")
        .confirmationDialog("Delete \(confirmDelete?.name ?? "")?", isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button("Delete offline map", role: .destructive) {
                if let s = confirmDelete { offline.delete(s.code) }
                confirmDelete = nil
            }
        } message: {
            Text("You can download it again any time you have signal.")
        }
    }

    private func included(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Color.sky)
        }
    }

    private func badge(_ code: String, filled: Bool) -> some View {
        Text(code)
            .font(.caption.weight(.bold).monospaced())
            .foregroundStyle(filled ? .white : Color.sky)
            .frame(width: 40, height: 40)
            .background(filled ? AnyShapeStyle(Color.sky) : AnyShapeStyle(Color.sky.opacity(0.14)),
                        in: .rect(cornerRadius: 10, style: .continuous))
    }
}
