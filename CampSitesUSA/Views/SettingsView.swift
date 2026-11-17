import SwiftUI

/// Settings. AI is one choice: the model ezcamp uses for every AI feature, picked on a screen where
/// keys are added inline. Model lists come from the Operator catalog worker, so new models show up
/// without an app update.
struct SettingsView: View {
    @Environment(AISettings.self) private var ai
    @AppStorage("showGearTips") private var showGearTips = true
    @State private var debugChooser = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    AppLogo(size: 60)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ezcamp").font(.title3.weight(.bold))
                        Text("Version \(Self.version) · Camps from open public data")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            } footer: {
                Text("3D icons: Fluent Emoji © Microsoft Corporation, MIT License.")
            }

            CommunityAccountSection()

            Section {
                AIModelRow()
            } header: {
                Text("AI")
            } footer: {
                Text("Powers Ask ezcamp and Plan with AI. Campsites and facts always come from ezcamp's open data, never from the model.")
            }

            Section {
                Toggle("Show gear tips", isOn: $showGearTips).tint(.meadow)
            } header: {
                Text("Gear")
            } footer: {
                Text("Short packing tips when a night is freezing, rainy or smoky, or a camp has no water or signal.")
            }

        }
        .navigationTitle("Settings")
        .task { await ai.refreshCatalog() }
        #if DEBUG
        .navigationDestination(isPresented: $debugChooser) { ModelChooser() }
        .task { if DebugLaunch.flag("debugModelChooser") { try? await Task.sleep(for: .seconds(1)); debugChooser = true } }
        #endif
    }

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

private extension ISO8601DateFormatter {
    static let withFractions: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

/// The one AI setting: which model ezcamp uses. Opens the chooser, where keys are added inline.
private struct AIModelRow: View {
    @Environment(AISettings.self) private var ai

    var body: some View {
        let current = ai.model(for: .chat)
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink {
                ModelChooser()
            } label: {
                LabeledContent {
                    Text(current.isOnDevice ? "On this iPhone" : current.label)
                        .lineLimit(1)
                } label: {
                    Label("Model", systemImage: "sparkles")
                }
            }
            if current.isOnDevice, let why = TripAI.onDeviceStatus {
                Label("On-device model unavailable: \(why). Choose a provider model instead.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(Color.canyon)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Pick the model ezcamp uses for every AI feature. Every provider is listed; ones without a key show the key
/// field inline, so adding a key and choosing a model happen on the same screen.
private struct ModelChooser: View {
    @Environment(AISettings.self) private var ai
    @State private var refreshing = false

    var body: some View {
        let current = ai.model(for: .chat)
        List {
            Section {
                choiceRow(.onDevice, current: current,
                          detail: TripAI.onDeviceStatus.map { "Not available: \($0)" } ?? "Private and free. Runs on Apple Intelligence.")
            } header: {
                Text("On this iPhone")
            }
            ForEach(AIProvider.allCases) { provider in
                Section {
                    if ai.hasKey(provider) {
                        let models = ai.models(for: provider)
                        if models.isEmpty {
                            Text("No models listed yet. Add a model ID under the key below.").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(models.prefix(12), id: \.self) { m in choiceRow(m, current: current, detail: nil) }
                    } else {
                        // No key yet: still name the models, so people know what a key unlocks.
                        ForEach(ai.models(for: provider).prefix(6), id: \.self) { m in
                            HStack {
                                Text(m.label).foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.tertiary)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityHint("Add a \(provider.shortTitle) key below to use this model.")
                        }
                    }
                    ProviderKeyRow(provider: provider)
                } header: {
                    Text(provider.title)
                } footer: {
                    if !ai.hasKey(provider) {
                        Text("Add your \(provider.shortTitle) key to use its models. It stays in this iPhone's Keychain.")
                    }
                }
            }
            Section {
                Button {
                    refreshing = true
                    Task { await ai.refreshCatalog(); refreshing = false }
                } label: {
                    HStack {
                        Text("Refresh model list")
                        Spacer()
                        if refreshing { ProgressView() }
                    }
                }
            } footer: {
                Text("Bring your own key for any provider. Keys stay in this iPhone's Keychain and go only to that provider; you pay them directly and ezcamp adds nothing. \(catalogFooter)")
            }
        }
        .navigationTitle("AI model")
        .navigationBarTitleDisplayMode(.inline)
        .task { await ai.refreshCatalog() }
    }

    private var catalogFooter: String {
        _ = ai.version
        guard let raw = ai.catalog.updatedAt,
              let date = ISO8601DateFormatter.withFractions.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        else { return "Model lists update automatically." }
        return "Model lists update automatically. Last updated \(date.formatted(.relative(presentation: .named)))."
    }

    private func choiceRow(_ m: ModelChoice, current: ModelChoice, detail: String?) -> some View {
        let selected = m == current
        let disabled = m.isOnDevice && TripAI.onDeviceStatus != nil
        return Button {
            for f in AIFeature.allCases { ai.setModel(m, for: f) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.isOnDevice ? "Apple on-device model" : m.label).foregroundStyle(.primary)
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Color.sunset)
                }
            }
            .contentShape(.rect)
        }
        .disabled(disabled && !selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A provider: key (save / test / remove), custom model IDs, and where to get a key.
struct ProviderKeyRow: View {
    let provider: AIProvider
    @Environment(AISettings.self) private var ai
    @State private var key = ""
    @State private var modelID = ""
    @State private var status: Status = .idle
    @State private var expanded = false

    enum Status: Equatable { case idle, checking, ok, failed(String) }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                if provider == .custom {
                    @Bindable var ai = ai
                    TextField("Base URL", text: $ai.customBaseURL, prompt: Text("https://your-host/v1"))
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                }
                HStack {
                    SecureField(ai.hasKey(provider) ? "Saved. Paste to replace" : "API key", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save") { save() }
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                // Any provider: type a model that isn't in the list.
                HStack {
                    TextField("Model ID (optional)", text: $modelID,
                              prompt: Text(ai.models(for: provider).first.map { "Other model, e.g. \($0.modelID)" } ?? provider.modelIDPlaceholder))
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit(addModel)
                    Button("Add") { addModel() }
                        .disabled(modelID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(ai.customModels(for: provider), id: \.self) { id in
                    HStack {
                        Label(id, systemImage: "cpu").font(.subheadline).lineLimit(1)
                        Spacer()
                        Button(role: .destructive) {
                            ai.removeCustomModel(id, for: provider)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .accessibilityLabel("Remove \(id)")
                    }
                }

                HStack(spacing: 14) {
                    if ai.hasKey(provider) {
                        Button("Test") { test() }
                        Button("Remove key", role: .destructive) {
                            _ = ai.setKey("", for: provider)
                            status = .idle
                        }
                    }
                    if let url = provider.keyURL { Link("Get a key", destination: url) }
                    Spacer()
                    statusView
                }
                .buttonStyle(.borderless)
                .font(.subheadline)
            }
            .padding(.vertical, 4)
        } label: {
            HStack {
                Text(provider.title)
                Spacer()
                if ai.hasKey(provider) {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.meadow)
                }
            }
        }
    }

    @ViewBuilder private var statusView: some View {
        switch status {
        case .idle: EmptyView()
        case .checking: ProgressView().controlSize(.small)
        case .ok: Label("Key works", systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(Color.meadow)
        case .failed(let message): Text(message).font(.caption).foregroundStyle(Color.berry).lineLimit(2)
        }
    }

    private func save() {
        if let error = ai.setKey(key, for: provider) {
            status = .failed(error)
            return
        }
        key = ""
        addModel()
        test()
    }

    /// Saves the typed model ID for this provider and, with a key present, uses it for features
    /// that are still on-device.
    private func addModel() {
        guard let choice = ai.addCustomModel(modelID, for: provider) else { return }
        modelID = ""
        if ai.hasKey(provider) {
            for f in AIFeature.allCases where ai.model(for: f).isOnDevice { ai.setModel(choice, for: f) }
        }
    }

    private func test() {
        status = .checking
        Task {
            do {
                try await ai.verify(provider)
                status = .ok
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }
}
