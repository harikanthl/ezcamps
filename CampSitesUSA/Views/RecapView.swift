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
            EzReelsPitch(onSave: { Task { await save() } }, saved: saved)
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

/// The case for ezReels: ezcamp's reel is the quick, silent version; ezReels makes the one people
/// replay. Only features ezReels has built are claimed here (PRD §3: Make it, Magic Clips,
/// slideshows with music on the beat, Surprise me, animated captions, titles, carousels).
struct EzReelsPitch: View {
    var onSave: () -> Void
    var saved: Bool
    @Environment(\.openURL) private var openURL

    private let points: [(String, String)] = [
        ("wand.and.stars", "One tap on Make it: the best moment first, dead air cut, captions on, music on the beat."),
        ("film.stack.fill", "Long hike video? Magic Clips finds the best 30 seconds and tells you why."),
        ("music.note", "Your photos as a slideshow that cuts on the beat, or a carousel ready for Instagram."),
        ("dice.fill", "Surprise me makes three different reels of the same trip. The family picks a favorite."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Turn this trip into a reel your family will replay")
                .font(.headline)
            ForEach(points, id: \.1) { icon, text in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(Color.berry).frame(width: 22)
                    Text(text).font(.subheadline)
                }
            }
            Button {
                if let store = RecapMaker.ezReelsStoreURL, saved { openURL(store) } else { onSave() }
            } label: {
                Label(saved ? "Saved. Open it in ezReels" : "Save to Photos, then open in ezReels",
                      systemImage: "film.stack.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent).tint(.berry)
            .disabled(saved && RecapMaker.ezReelsStoreURL == nil)
            Text("ezReels is our reel studio for iPhone. Your trip reel stays yours either way.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            LinearGradient(colors: [Color.berry.opacity(0.14), Color.dusk.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 20, style: .continuous))
    }
}
