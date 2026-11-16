import SwiftUI

/// Settings. AI is organised by the feature that uses it: each feature picks its model, and the keys
/// below unlock providers for all of them. Model lists come from the Operator catalog worker, so new
/// models show up without an app update.
struct SettingsView: View {
    @Environment(AISettings.self) private var ai
    @State private var refreshing = false
    @AppStorage("showGearTips") private var showGearTips = true

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

            ForEach(sections, id: \.self) { section in
                Section {
                    ForEach(AIFeature.allCases.filter { $0.section == section }) { feature in
                        FeatureModelRow(feature: feature)
                    }
                } header: {
                    Text("AI · \(section)")
                }
            }

            Section {
                ForEach(AIProvider.allCases) { provider in
                    ProviderKeyRow(provider: provider)
                }
            } header: {
                Text("Your API keys")
            } footer: {
                Text("Bring your own key for any provider. Keys stay in this iPhone's Keychain and go only to that provider; you pay them directly and ezcamp adds nothing. Add a model ID under a provider to use a model that isn't listed.")
            }

            Section {
                Toggle("Show gear tips", isOn: $showGearTips).tint(.meadow)
            } header: {
                Text("Gear")
            } footer: {
                Text("Short packing tips when a night is freezing, rainy or smoky, or a camp has no water or signal.")
            }

            Section {
                Button {
                    refreshing = true
                    Task {
                        await ai.refreshCatalog()
                        refreshing = false
                    }
                } label: {
                    HStack {
                        Text("Refresh model list")
                        Spacer()
                        if refreshing { ProgressView() }
                    }
                }
            } footer: {
                Text(catalogFooter)
            }
        }
        .navigationTitle("Settings")
        .task { await ai.refreshCatalog() }
    }

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var sections: [String] {
        var seen = Set<String>()
        return AIFeature.allCases.map(\.section).filter { seen.insert($0).inserted }
    }

    private var catalogFooter: String {
        _ = ai.version
        guard let raw = ai.catalog.updatedAt,
              let date = ISO8601DateFormatter.withFractions.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        else { return "Model lists update automatically." }
        return "Model lists update automatically. Last updated \(date.formatted(.relative(presentation: .named)))."
    }
}

private extension ISO8601DateFormatter {
    static let withFractions: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

/// One AI feature and the model it uses.
private struct FeatureModelRow: View {
    let feature: AIFeature
    @Environment(AISettings.self) private var ai

    var body: some View {
        let current = ai.model(for: feature)
        VStack(alignment: .leading, spacing: 8) {
            Picker(selection: Binding(get: { current }, set: { ai.setModel($0, for: feature) })) {
                ForEach(ai.pickerSections(current: current), id: \.provider) { section in
                    Section(section.provider?.title ?? "Private") {
                        ForEach(section.models, id: \.self) { Text($0.label).tag($0) }
                    }
                }
            } label: {
                Label(feature.title, systemImage: feature.symbol)
            }
            .pickerStyle(.navigationLink)
            Text(feature.explainer).font(.caption).foregroundStyle(.secondary)
            if current.isOnDevice, let why = TripAI.onDeviceStatus {
                Label("On-device model unavailable: \(why). Add a key below.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(Color.canyon)
            }
        }
        .padding(.vertical, 2)
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
                    TextField("Model ID (optional)", text: $modelID, prompt: Text(provider.modelIDPlaceholder))
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
