import SwiftUI
import AVKit
import Photos

/// Makes the trip's recap video, plays it, and offers Save, Share and "Edit in ezReels".
struct RecapView: View {
    let trip: Trip
    let miles: Int?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var progress = 0.0
    @State private var url: URL?
    @State private var player: AVPlayer?
    @State private var error: String?
    @State private var saved = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let player {
                    VideoPlayer(player: player)
                        .aspectRatio(9 / 16, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 20, style: .continuous))
                        .onAppear { player.play() }
                    actions
                } else if let error {
                    ContentUnavailableView("Couldn't make the recap", systemImage: "film", description: Text(error))
                } else {
                    Spacer()
                    VStack(spacing: 14) {
                        AppLogo(size: 64)
                        Text("Turning your trip into a reel…").font(.headline)
                        ProgressView(value: progress).tint(.dusk).frame(maxWidth: 240)
                        Text("Your route on the map, every camp by day, and the moments that made it.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    Spacer()
                }
            }
            .padding()
            .navigationTitle("Your trip reel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await make() }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { Task { await save() } } label: {
                    Label(saved ? "Saved" : "Save to Photos", systemImage: saved ? "checkmark" : "square.and.arrow.down")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent).tint(.dusk)
                .disabled(saved)
                if let url {
                    ShareLink(item: url) {
                        Label("Share with family", systemImage: "heart.fill").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered).tint(.dusk)
                }
            }
            // ezReels does music, captions and twin cuts; point people there instead of rebuilding it.
            VStack(alignment: .leading, spacing: 4) {
                Label("Make it unforgettable in ezReels", systemImage: "sparkles").font(.subheadline.weight(.semibold))
                Text("Music that hits on the beat, captions and twin cuts, ready for the family group chat. Save your reel to Photos, then open it in ezReels.")
                    .font(.caption).foregroundStyle(.secondary)
                if let store = RecapMaker.ezReelsStoreURL {
                    Button("Get ezReels") { openURL(store) }.font(.caption.weight(.semibold))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.berry.opacity(0.1), in: .rect(cornerRadius: 14, style: .continuous))
        }
    }

    private func make() async {
        guard url == nil else { return }
        do {
            let stats = RecapMaker.Stats(miles: miles, nights: trip.totalNights, camps: trip.stops.count)
            let (spec, images) = try await RecapMaker.plan(trip: trip, stats: stats)
            let out = try await RecapMaker.render(spec, images: images) { p in
                Task { @MainActor in progress = p }
            }
            url = out
            player = AVPlayer(url: out)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        guard let url else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            error = "Allow ezcamp to add to Photos in Settings to save the recap."
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            withAnimation(.easeOut(duration: 0.2)) { saved = true }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
