import SwiftUI
import SwiftData
import PhotosUI

/// "My gear": your things as cut-out stickers on shelves. Add by photo (cut out on the iPhone),
/// confirm the suggested name and category in the Review tray, and they show up in pack lists.
struct GearClosetView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \GearItem.addedAt, order: .reverse) private var items: [GearItem]
    @State private var picks: [PhotosPickerItem] = []
    @State private var camera = false
    @State private var working = 0
    @State private var editing: GearItem?
    @State private var note: String?

    private var review: [GearItem] { items.filter { !$0.reviewed } }
    private var shelves: [(GearCategory, [GearItem])] {
        GearCategory.allCases.compactMap { c in
            let list = items.filter { $0.reviewed && $0.category == c }
            return list.isEmpty ? nil : (c, list)
        }
    }
    private var totalWeight: Int { items.compactMap { w in w.weightGrams.map { $0 * w.quantity } }.reduce(0, +) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if items.isEmpty { empty }
                if !review.isEmpty { reviewTray }
                ForEach(shelves, id: \.0) { c, list in shelf(c, list) }
                if let note { Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
            }
            .padding()
        }
        .onChange(of: picks) { _, list in
            guard !list.isEmpty else { return }
            Task { await addPicks(list) }
        }
        .fullScreenCover(isPresented: $camera) {
            CameraCapture { result in
                if case .photo(let data) = result { Task { await add(data) } }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $editing) { GearEditor(item: $0) }
        #if DEBUG
        // Testing aid: `-debugSeedGear <folder>` adds the folder's photos as gear (two confirmed).
        .task {
            guard let dir = DebugLaunch.string("debugSeedGear"),
                  let files = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil) else { return }
            for f in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                if let data = try? Data(contentsOf: f) { await add(data) }
            }
            for (i, item) in items.enumerated() where i < 4 { item.reviewed = true; item.category = [.shelter, .kitchen, .lighting, .fishing][i] }
        }
        #endif
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(items.count) item\(items.count == 1 ? "" : "s")").font(.title3.weight(.bold))
                if totalWeight > 0 {
                    Text(weightText(totalWeight) + " weighed").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if working > 0 { ProgressView().padding(.trailing, 6) }
            Menu {
                PhotosPicker(selection: $picks, maxSelectionCount: 30, matching: .images) {
                    Label("From Photos", systemImage: "photo.on.rectangle")
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take a photo", systemImage: "camera") { camera = true }
                }
            } label: {
                Label("Add gear", systemImage: "plus").font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color.sunset, in: .capsule).foregroundStyle(.white)
            }
            .buttonStyle(.pressable)
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Icon3D("tent", size: 72)
            Text("Your gear, as stickers").font(.headline)
            Text("Snap your tent, stove, headlamp, rod. Each one is cut out on your iPhone and lands on a shelf, ready to tick off when you pack.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var reviewTray: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Check these", systemImage: "sparkles").font(.subheadline.weight(.semibold)).foregroundStyle(Color.dusk)
            Text("We guessed the name and shelf. Tap to fix, or confirm.").font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(review) { item in
                        VStack(spacing: 6) {
                            GearSticker(item: item, size: 96).onTapGesture { editing = item }
                            Text(item.name).font(.caption.weight(.semibold)).lineLimit(1).frame(width: 100)
                            Text(item.category.label).font(.caption2).foregroundStyle(.secondary)
                            Button("Looks right") {
                                withAnimation(.spring(duration: 0.35, bounce: 0.15)) { item.reviewed = true }
                            }
                            .font(.caption.weight(.semibold)).buttonStyle(.bordered).tint(.meadow).controlSize(.small)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
        .padding(12)
        .background(Color.dusk.opacity(0.08), in: .rect(cornerRadius: 18, style: .continuous))
    }

    private func shelf(_ c: GearCategory, _ list: [GearItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Icon3D(c.icon3D, size: 20)
                Text(c.label).font(.subheadline.weight(.semibold))
                Text("\(list.count)").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 14) {
                    ForEach(list) { item in
                        GearSticker(item: item, size: 84)
                            .onTapGesture { editing = item }
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { editing = item }
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(item) }
                            }
                    }
                }
                .padding(.horizontal, 6).padding(.top, 6)
            }
            .scrollClipDisabled()
            // The shelf itself.
            RoundedRectangle(cornerRadius: 3).fill(Color.canyon.opacity(0.35)).frame(height: 6)
                .shadow(color: .black.opacity(0.12), radius: 2, y: 2)
        }
    }

    // MARK: Adding

    private func addPicks(_ list: [PhotosPickerItem]) async {
        defer { picks = [] }
        for p in list {
            if let data = try? await p.loadTransferable(type: Data.self) { await add(data) }
        }
    }

    private func add(_ data: Data) async {
        working += 1
        defer { working -= 1 }
        do {
            let sticker = try await GearStore.makeSticker(from: data)
            let guess = await GearStore.suggest(for: sticker.image)
            let item = GearItem(name: guess.name, category: guess.category, imageFile: sticker.file, isCutout: sticker.isCutout)
            withAnimation(.spring(duration: 0.35, bounce: 0.15)) { context.insert(item) }
            if !sticker.isCutout { note = "Cut-outs need the iPhone's Neural Engine; this one keeps the full photo." }
        } catch {
            note = error.localizedDescription
        }
    }

    private func delete(_ item: GearItem) {
        GearStore.delete(item)
        context.delete(item)
    }

    private func weightText(_ grams: Int) -> String {
        Measurement(value: Double(grams), unit: UnitMass.grams)
            .formatted(.measurement(width: .abbreviated, usage: .personWeight, numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }
}

/// One item as a die-cut sticker: a white border hugging the cut-out and a soft shadow, with a
/// gentle lift when pressed.
struct GearSticker: View {
    let item: GearItem
    var size: CGFloat = 84
    var packed = false
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    if item.isCutout {
                        Image(uiImage: image).resizable().scaledToFit()
                            // A die-cut white border: the silhouette drawn white, a little bigger, behind.
                            .background {
                                Image(uiImage: image).renderingMode(.template).resizable().scaledToFit()
                                    .foregroundStyle(.white)
                                    .padding(-4)
                            }
                            .shadow(color: .black.opacity(0.22), radius: 4, y: 3)
                    } else {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(.rect(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white, lineWidth: 4))
                            .shadow(color: .black.opacity(0.22), radius: 4, y: 3)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.quaternary)
                }
            }
            .frame(width: size, height: size)
            .opacity(packed ? 0.55 : 1)
            if item.quantity > 1 {
                Text("×\(item.quantity)").font(.caption2.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.dusk, in: .capsule).foregroundStyle(.white)
            }
            if packed {
                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.white, Color.meadow)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .contentShape(.rect)
        .task(id: item.imageFile) { image = UIImage(contentsOfFile: item.imageURL.path()) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name + (packed ? ", packed" : ""))
        .accessibilityAddTraits(.isButton)
    }
}

/// Name, shelf, quantity, weight and notes for one item.
struct GearEditor: View {
    @Bindable var item: GearItem
    @Environment(\.dismiss) private var dismiss
    @State private var weightText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack { Spacer(); GearSticker(item: item, size: 140); Spacer() }
                        .listRowBackground(Color.clear)
                }
                Section {
                    TextField("Name", text: $item.name)
                    Picker("Shelf", selection: Binding(get: { item.category }, set: { item.category = $0 })) {
                        ForEach(GearCategory.allCases) { Text($0.label).tag($0) }
                    }
                    Stepper("Quantity: \(item.quantity)", value: $item.quantity, in: 1...20)
                    TextField("Weight in grams (optional)", text: $weightText)
                        .keyboardType(.numberPad)
                        .onChange(of: weightText) { _, t in item.weightGrams = Int(t.filter(\.isNumber)) }
                } footer: {
                    Text("Weigh it at home for an honest total. Leave blank if you don't know.")
                }
                Section("Notes") {
                    TextField("Brand, size, where it lives…", text: $item.notes, axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle(item.reviewed ? "Gear" : "Check this one")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { item.reviewed = true; dismiss() }.fontWeight(.semibold)
                }
            }
            .onAppear { weightText = item.weightGrams.map(String.init) ?? "" }
        }
    }
}
