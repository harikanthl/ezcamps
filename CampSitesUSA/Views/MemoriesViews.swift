import SwiftUI
import SwiftData
import PhotosUI
import AVKit
import UniformTypeIdentifiers

/// "Memories" on a trip: photos and videos grouped by camp, added from Photos or the camera, with
/// a recap video made from them.
struct TripMemoriesSection: View {
    @Bindable var trip: Trip
    var onMakeRecap: () -> Void

    @Environment(\.modelContext) private var context
    @State private var picks: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var camera = false
    @State private var viewing: Memory?

    /// Any video long enough that finding the good part is the hard bit (Magic Clips' job).
    @State private var hasLongVideo = false

    private var groups: [(title: String, memories: [Memory])] {
        let sorted = trip.memories.sorted { $0.takenAt < $1.takenAt }
        var out: [(String, [Memory])] = []
        for m in sorted {
            let title = m.siteName ?? "On the road"
            if let i = out.firstIndex(where: { $0.0 == title }) { out[i].1.append(m) } else { out.append((title, [m])) }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle("Memories", icon: "camping")
                Spacer()
                addMenu
            }
            if trip.memories.isEmpty {
                Text("Every trip is a story worth telling. Add your photos and videos, and ezcamp turns them into a reel you can share with the people you love.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(groups, id: \.title) { g in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(g.title).font(.caption.weight(.bold)).foregroundStyle(Color.dusk)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                            ForEach(g.memories) { m in
                                MemoryThumb(memory: m)
                                    .onTapGesture { viewing = m }
                                    .contextMenu {
                                        Button("Delete", systemImage: "trash", role: .destructive) { delete(m) }
                                    }
                            }
                        }
                    }
                }
                Button(action: onMakeRecap) {
                    Label("Make my trip reel", systemImage: "film.stack")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent).tint(.dusk)
                Label(hasLongVideo ? "Long video in here? ezReels' Magic Clips finds its best 30 seconds." : "Want music, captions and a cut on every beat? Open your reel in ezReels.", systemImage: "sparkles")
                    .font(.caption).foregroundStyle(Color.berry)
            }
            if importing { ProgressView("Adding…").font(.caption) }
        }
        .onChange(of: picks) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPicks(items) }
        }
        .fullScreenCover(isPresented: $camera) {
            CameraCapture { result in Task { await importCaptured(result) } }
                .ignoresSafeArea()
        }
        .fullScreenCover(item: $viewing) { m in MemoryViewer(memory: m) }
        .task(id: trip.memories.count) {
            var long = false
            for m in trip.memories where m.isVideo {
                if let d = try? await AVURLAsset(url: m.url).load(.duration), d.seconds > 120 { long = true; break }
            }
            hasLongVideo = long
        }
    }

    private var addMenu: some View {
        Menu {
            PhotosPicker(selection: $picks, maxSelectionCount: 50, matching: .any(of: [.images, .videos])) {
                Label("From Photos", systemImage: "photo.on.rectangle")
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take a photo or video", systemImage: "camera") { camera = true }
            }
        } label: {
            Label("Add", systemImage: "plus.circle.fill").font(.subheadline.weight(.semibold))
        }
        .tint(.sunset)
    }

    // MARK: Import

    private func importPicks(_ items: [PhotosPickerItem]) async {
        importing = true
        defer { importing = false; picks = [] }
        for item in items {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }),
               let movie = try? await item.loadTransferable(type: PickedMovie.self),
               let saved = try? await MemoryFiles.saveVideo(from: movie.url) {
                add(fileName: saved.fileName, isVideo: true, takenAt: saved.takenAt, coordinate: saved.coordinate)
                try? FileManager.default.removeItem(at: movie.url)
            } else if let data = try? await item.loadTransferable(type: Data.self),
                      let saved = try? MemoryFiles.savePhoto(data) {
                add(fileName: saved.fileName, isVideo: false, takenAt: saved.takenAt, coordinate: saved.coordinate)
            }
        }
    }

    private func importCaptured(_ result: CameraCapture.Result) async {
        switch result {
        case .photo(let data):
            if let saved = try? MemoryFiles.savePhoto(data) { add(fileName: saved.fileName, isVideo: false, takenAt: .now, coordinate: nil) }
        case .video(let url):
            if let saved = try? await MemoryFiles.saveVideo(from: url) { add(fileName: saved.fileName, isVideo: true, takenAt: .now, coordinate: saved.coordinate) }
        }
    }

    private func add(fileName: String, isVideo: Bool, takenAt: Date?, coordinate: CLLocationCoordinate2D?) {
        let m = Memory(fileName: fileName, isVideo: isVideo, takenAt: takenAt ?? .now, coordinate: coordinate)
        context.insert(m)
        trip.memories.append(m)
        if let stop = trip.stop(for: m) {
            m.siteID = stop.siteID
            m.siteName = stop.name
        }
    }

    private func delete(_ m: Memory) {
        MemoryFiles.delete(m)
        trip.memories.removeAll { $0.id == m.id }
        context.delete(m)
    }
}

/// A grid cell: the thumbnail, with a play badge on videos.
struct MemoryThumb: View {
    let memory: Memory
    @State private var image: UIImage?

    var body: some View {
        Color.secondary.opacity(0.12)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if memory.isVideo {
                    Image(systemName: "play.fill").font(.caption2.weight(.bold)).foregroundStyle(.white)
                        .padding(5).background(.black.opacity(0.45), in: .circle).padding(5)
                }
            }
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
            .contentShape(.rect)
            .task(id: memory.id) {
                let img = await MemoryFiles.thumbnail(memory)
                withAnimation(.easeOut(duration: 0.2)) { image = img }
            }
            .accessibilityLabel(memory.isVideo ? "Video" : "Photo")
            .accessibilityAddTraits(.isButton)
    }
}

/// Full-screen photo or video.
struct MemoryViewer: View {
    let memory: Memory
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if memory.isVideo {
                VideoPlayer(player: AVPlayer(url: memory.url)).ignoresSafeArea()
            } else if let img = UIImage(contentsOfFile: memory.url.path()) {
                Image(uiImage: img).resizable().scaledToFit().ignoresSafeArea()
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(.ultraThinMaterial, in: .circle)
            }
            .padding()
            .accessibilityLabel("Close")
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 2) {
                if let s = memory.siteName { Text(s).font(.headline) }
                Text(memory.takenAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
            }
            .foregroundStyle(.white)
            .padding()
            .shadow(radius: 4)
        }
    }
}

/// A movie from the photo picker, copied somewhere we can read it.
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

/// The system camera for a quick photo or video.
struct CameraCapture: UIViewControllerRepresentable {
    enum Result { case photo(Data), video(URL) }
    var onCapture: (Result) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        p.videoQuality = .typeHigh
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture
        init(_ p: CameraCapture) { parent = p }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL {
                parent.onCapture(.video(url))
            } else if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
                parent.onCapture(.photo(data))
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
