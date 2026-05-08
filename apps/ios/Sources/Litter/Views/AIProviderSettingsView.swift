import SwiftUI
import UniformTypeIdentifiers

struct AIProviderSettingsView: View {
    @StateObject private var providerStore = AIProviderStore.shared
    @State private var capability = DeviceCapabilityProfile.current()
    @State private var showAddProvider = false
    @State private var showImporter = false
    @State private var statusMessage: String?
    @State private var isImportingModel = false

    var body: some View {
        List {
            deviceSection
            modelSettingsSection
            providersSection
            localModelsSection
            notesSection
        }
        .navigationTitle("AI Providers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddProvider = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .foregroundColor(LitterTheme.accent)
            }
        }
        .sheet(isPresented: $showAddProvider) {
            NavigationStack {
                AddAIProviderView()
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleModelImport(result) }
        }
        .onAppear {
            capability = .current()
            providerStore.reload()
            Task { await providerStore.refreshRuntimeCapabilities() }
        }
    }


    private func handleModelImport(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.pathExtension.lowercased() == "gguf" else {
                statusMessage = "Only .gguf model files are supported for on-device import."
                return
            }
            isImportingModel = true
            statusMessage = "Importing \(url.lastPathComponent)..."
            defer { isImportingModel = false }
            do {
                let record = try await providerStore.importLocalModel(from: url, capability: capability)
                statusMessage = "Imported \(record.fileName): \(record.safety.displayName)."
            } catch {
                statusMessage = error.localizedDescription
            }
        case .failure(let error):
            statusMessage = error.localizedDescription
        }
    }

    private var deviceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(capability.localInferenceTier.displayName, systemImage: capability.hasMetal ? "gpu" : "exclamationmark.triangle")
                        .foregroundColor(capability.hasMetal ? LitterTheme.accent : LitterTheme.danger)
                    Spacer()
                    Button("Rescan") { capability = .current() }
                        .litterFont(.caption)
                }
                capabilityRow("Device", "\(capability.deviceName) · \(capability.modelIdentifier)")
                capabilityRow("iOS", capability.systemVersion)
                capabilityRow("Memory", String(format: "%.1f GB", capability.memoryGB))
                capabilityRow("Free Storage", String(format: "%.1f GB", capability.freeDiskGB))
                capabilityRow("Thermal", capability.thermalDisplayName, valueColor: thermalColor)
                capabilityRow("Metal", capability.metalDeviceName ?? "Unavailable")
                capabilityRow("Local Context", capability.recommendedContextTokens > 0 ? "\(capability.recommendedContextTokens) tokens" : "PC-hosted recommended")
                if !capability.supportedGPUFamilies.isEmpty {
                    capabilityRow("GPU Families", capability.supportedGPUFamilies.joined(separator: ", "))
                }
                Text(capability.modelSafetySummary)
                    .litterFont(.caption)
                    .foregroundColor(capability.isThermallyConstrained ? LitterTheme.warning : LitterTheme.textMuted)
                if capability.isLowPowerModeEnabled {
                    Text("Low Power Mode is on. Local model recommendations are downgraded.")
                        .litterFont(.caption)
                        .foregroundColor(LitterTheme.warning)
                }
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))
        } header: {
            Text("This iPhone")
                .foregroundColor(LitterTheme.textSecondary)
        }
    }


    private var modelSettingsSection: some View {
        Section {
            Picker("Default Route", selection: globalRoutingBinding) {
                ForEach(AIModelRoutingMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            Toggle("Validate after import/download", isOn: globalBoolBinding(\.autoValidateDownloads))
            Toggle("Allow cellular model downloads", isOn: globalBoolBinding(\.allowCellularDownloads))
            Toggle("Unload idle local models", isOn: globalBoolBinding(\.autoUnloadAfterIdle))
            Toggle("Warn on thermal pressure", isOn: globalBoolBinding(\.warnOnThermalPressure))
            Picker("TurboQuant", selection: turboPreferenceBinding) {
                ForEach(TurboQuantPreference.allCases) { preference in
                    Text(preference.displayName).tag(preference)
                }
            }
            .disabled(!providerStore.turboQuantAvailability.isAvailable)
            VStack(alignment: .leading, spacing: 4) {
                Text(providerStore.turboQuantAvailability.isAvailable ? "TurboQuant KV cache" : "TurboQuant unavailable")
                    .litterFont(.caption, weight: .semibold)
                    .foregroundColor(providerStore.turboQuantAvailability.isAvailable ? LitterTheme.success : LitterTheme.warning)
                Text(providerStore.turboQuantAvailability.summary)
                    .litterFont(.caption)
                    .foregroundColor(LitterTheme.textMuted)
            }
        } header: {
            Text("Model Settings")
                .foregroundColor(LitterTheme.textSecondary)
        } footer: {
            Text("TurboQuant is only enabled when the linked llama.cpp runtime reports support. Standard builds keep it unavailable instead of showing a fake switch.")
        }
    }

    private var providersSection: some View {
        Section {
            ForEach(providerStore.providers) { provider in
                NavigationLink {
                    AIProviderDetailView(provider: provider)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: icon(for: provider.kind))
                            .foregroundColor(LitterTheme.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(provider.displayName)
                                .litterFont(.subheadline)
                                .foregroundColor(LitterTheme.textPrimary)
                            Text(providerSubtitle(provider))
                                .litterFont(.caption)
                                .foregroundColor(LitterTheme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if provider.isEnabled {
                            Text("On")
                                .litterFont(.caption)
                                .foregroundColor(LitterTheme.accent)
                        }
                    }
                }
                .listRowBackground(LitterTheme.surface.opacity(0.6))
            }
        } header: {
            Text("Providers")
                .foregroundColor(LitterTheme.textSecondary)
        }
    }

    private var localModelsSection: some View {
        Section {
            Button {
                showImporter = true
            } label: {
                HStack {
                    Label("Import GGUF Model", systemImage: "square.and.arrow.down")
                    Spacer()
                    if isImportingModel {
                        ProgressView().scaleEffect(0.8)
                    }
                }
                .foregroundColor(LitterTheme.accent)
            }
            .disabled(isImportingModel)
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            NavigationLink {
                LocalModelSearchView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(LitterTheme.accent)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Download Local Models")
                            .litterFont(.subheadline, weight: .semibold)
                            .foregroundColor(LitterTheme.textPrimary)
                        Text("Recommended GGUFs, Hugging Face search, and direct URLs")
                            .litterFont(.caption)
                            .foregroundColor(LitterTheme.textSecondary)
                    }
                }
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            if let statusMessage {
                Text(statusMessage)
                    .litterFont(.caption)
                    .foregroundColor(LitterTheme.textSecondary)
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
            }

            if providerStore.localModels.isEmpty {
                Text("No on-device models installed yet. Tap Download Local Models to get a recommended GGUF, search Hugging Face, or paste a direct model URL.")
                    .litterFont(.caption)
                    .foregroundColor(LitterTheme.textMuted)
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
            } else {
                ForEach(providerStore.localModels) { model in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(model.fileName)
                                .litterFont(.subheadline)
                                .foregroundColor(LitterTheme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(model.safety.displayName)
                                .litterFont(.caption)
                                .foregroundColor(color(for: model.safety))
                        }
                        Text("\(model.displaySize)\(model.quantizationHint.map { " · \($0)" } ?? "") · \(model.validationStatus.displayName)")
                            .litterFont(.caption)
                            .foregroundColor(LitterTheme.textSecondary)
                        Text(model.recommendation)
                            .litterFont(.caption)
                            .foregroundColor(LitterTheme.textMuted)
                        NavigationLink("Runtime Settings") {
                            LocalModelRuntimeSettingsView(model: model)
                        }
                        .litterFont(.caption, weight: .semibold)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            try? providerStore.removeLocalModel(model)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
                }
            }
        } header: {
            Text("On-Device Models")
                .foregroundColor(LitterTheme.textSecondary)
        }
    }

    private var notesSection: some View {
        Section {
            Text("PC-hosted Ollama or LM Studio is the best path for powerful models. On-device models now have guarded fakefs tools, approval requests for shell/write actions, retry events, streaming tool-call state, and device-derived context defaults. Full Codex parity still requires the native llama.cpp token generator bridge to be connected.")
                .litterFont(.caption)
                .foregroundColor(LitterTheme.textMuted)
                .listRowBackground(LitterTheme.surface.opacity(0.6))
        } header: {
            Text("Reality Check")
                .foregroundColor(LitterTheme.textSecondary)
        }
    }

    private func capabilityRow(_ title: String, _ value: String, valueColor: Color = LitterTheme.textSecondary) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .litterFont(.caption)
                .foregroundColor(LitterTheme.textMuted)
            Spacer()
            Text(value)
                .litterFont(.caption)
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }

    private var thermalColor: Color {
        switch capability.thermalSeverityRank {
        case 3: return LitterTheme.danger
        case 2: return LitterTheme.warning
        case 1: return LitterTheme.textSecondary
        default: return LitterTheme.success
        }
    }

    private var globalRoutingBinding: Binding<AIModelRoutingMode> {
        Binding(
            get: { providerStore.globalModelSettings.routingMode },
            set: { value in providerStore.updateGlobalModelSettings { $0.routingMode = value } }
        )
    }

    private var turboPreferenceBinding: Binding<TurboQuantPreference> {
        Binding(
            get: { providerStore.globalModelSettings.turboQuantPreference },
            set: { value in providerStore.updateGlobalModelSettings { $0.turboQuantPreference = value } }
        )
    }

    private func globalBoolBinding(_ keyPath: WritableKeyPath<GlobalModelSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { providerStore.globalModelSettings[keyPath: keyPath] },
            set: { value in providerStore.updateGlobalModelSettings { $0[keyPath: keyPath] = value } }
        )
    }

    private func providerSubtitle(_ provider: AIProviderProfile) -> String {
        switch provider.kind {
        case .openAI: return provider.defaultModel.isEmpty ? provider.baseURL : "\(provider.defaultModel) · \(provider.baseURL)"
        case .openAICompatible: return provider.defaultModel.isEmpty ? provider.baseURL : "\(provider.defaultModel) · \(provider.baseURL)"
        case .localGGUF: return "\(providerStore.localModels.count) imported models"
        }
    }

    private func icon(for kind: AIProviderKind) -> String {
        switch kind {
        case .openAI: return "cloud"
        case .openAICompatible: return "desktopcomputer"
        case .localGGUF: return "iphone.gen3"
        }
    }

    private func color(for safety: LocalModelSafety) -> Color {
        switch safety {
        case .recommended: return LitterTheme.accent
        case .heavy: return LitterTheme.warning
        case .notRecommended, .pcRecommended: return LitterTheme.danger
        }
    }
}

private struct AddAIProviderView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var providerStore = AIProviderStore.shared
    @State private var name = "Ollama on PC"
    @State private var baseURL = "http://192.168.1.20:11434/v1"
    @State private var apiKey = ""
    @State private var defaultModel = ""
    @State private var isTesting = false
    @State private var report = AIProviderHealthReport(status: .unknown, models: [])

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                TextField("Base URL", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("API key optional for Ollama", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Default model", text: $defaultModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("OpenAI-Compatible Server")
            } footer: {
                Text("For Ollama, use the /v1 endpoint, for example http://your-pc-ip:11434/v1. Keep it on LAN, VPN, or Tailscale; do not expose unauthenticated Ollama publicly.")
            }

            Section {
                Button {
                    Task { await test() }
                } label: {
                    HStack {
                        if isTesting { ProgressView().scaleEffect(0.8) }
                        Text("Test Connection")
                    }
                }
                .disabled(isTesting || baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Text(report.summary)
                    .foregroundColor(reportColor)

                if !report.models.isEmpty {
                    Picker("Detected model", selection: $defaultModel) {
                        Text("Manual").tag(defaultModel)
                        ForEach(report.models, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }
            }
        }
        .navigationTitle("Add AI Server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || baseURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var reportColor: Color {
        switch report.status {
        case .healthy: return LitterTheme.accent
        case .warning: return LitterTheme.warning
        case .failed: return LitterTheme.danger
        case .unknown: return LitterTheme.textSecondary
        }
    }

    private func profile() -> AIProviderProfile {
        AIProviderProfile.ollama(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            defaultModel: defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func test() async {
        isTesting = true
        let next = profile()
        report = await providerStore.testProvider(next, apiKey: apiKey)
        if defaultModel.isEmpty, let first = report.models.first {
            defaultModel = first
        }
        isTesting = false
    }

    private func save() {
        do {
            try providerStore.upsertProvider(profile(), apiKey: apiKey.isEmpty ? nil : apiKey)
            dismiss()
        } catch {
            report = AIProviderHealthReport(status: .failed(error.localizedDescription), models: [])
        }
    }
}

private struct AIProviderDetailView: View {
    @StateObject private var providerStore = AIProviderStore.shared
    let provider: AIProviderProfile
    @State private var report = AIProviderHealthReport(status: .unknown, models: [])
    @State private var isTesting = false

    var body: some View {
        List {
            Section {
                Text(provider.displayName)
                Text(provider.kind.displayName)
                Text(provider.baseURL)
                    .foregroundColor(LitterTheme.textSecondary)
                if !provider.defaultModel.isEmpty {
                    Text("Default model: \(provider.defaultModel)")
                }
            }
            Section {
                Button {
                    Task { await test() }
                } label: {
                    HStack {
                        if isTesting { ProgressView().scaleEffect(0.8) }
                        Text(provider.kind == .localGGUF ? "Refresh Models" : "Test Connection")
                    }
                }
                Text(report.summary)
                    .foregroundColor(reportColor)
                ForEach(report.models, id: \.self) { model in
                    Text(model)
                        .litterFont(.caption)
                        .foregroundColor(LitterTheme.textSecondary)
                }
            }
            if provider.kind != .openAI {
                Section {
                    Button(role: .destructive) {
                        try? providerStore.deleteProvider(provider)
                    } label: {
                        Text("Delete Provider")
                    }
                }
            }
        }
        .navigationTitle(provider.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var reportColor: Color {
        switch report.status {
        case .healthy: return LitterTheme.accent
        case .warning: return LitterTheme.warning
        case .failed: return LitterTheme.danger
        case .unknown: return LitterTheme.textSecondary
        }
    }

    private func test() async {
        isTesting = true
        report = await providerStore.testProvider(provider, apiKey: nil)
        isTesting = false
    }
}


private struct LocalModelRuntimeSettingsView: View {
    @StateObject private var providerStore = AIProviderStore.shared
    let model: LocalModelRecord
    @State private var capability = DeviceCapabilityProfile.current()

    var body: some View {
        Form {
            Section {
                Stepper("Context: \(settings.contextTokens) tokens", value: intBinding(\.contextTokens), in: 512...16_384, step: 512)
                Stepper("Max output: \(settings.maxOutputTokens) tokens", value: intBinding(\.maxOutputTokens), in: 64...4_096, step: 64)
                Stepper("Tool rounds: \(settings.maxToolRounds)", value: intBinding(\.maxToolRounds), in: 0...12)
                Picker("Tool Use", selection: toolModeBinding) {
                    ForEach(LocalModelToolUseMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            } header: {
                Text("Agent Behavior")
            }

            Section {
                SliderRow(title: "Temperature", value: doubleBinding(\.temperature), range: 0...2)
                SliderRow(title: "Top P", value: doubleBinding(\.topP), range: 0.05...1)
                Stepper("Top K: \(settings.topK)", value: intBinding(\.topK), in: 1...200)
                SliderRow(title: "Repeat penalty", value: doubleBinding(\.repeatPenalty), range: 0.8...1.5)
            } header: {
                Text("Sampling")
            }

            Section {
                Toggle("Use Metal GPU", isOn: boolBinding(\.metalEnabled))
                    .disabled(!capability.hasMetal)
                Toggle("Allow CPU fallback", isOn: boolBinding(\.cpuFallbackAllowed))
                Toggle("Stream tokens", isOn: boolBinding(\.streamingEnabled))
                Stepper("Threads: \(settings.preferredThreadCount)", value: intBinding(\.preferredThreadCount), in: 1...max(1, ProcessInfo.processInfo.processorCount))
                Picker("KV Cache", selection: kvCacheBinding) {
                    ForEach(LocalModelKVCacheMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .disabled(!providerStore.turboQuantAvailability.isAvailable && settings.kvCacheMode.requiresTurboQuant)
                Text(providerStore.turboQuantAvailability.summary)
                    .litterFont(.caption)
                    .foregroundColor(providerStore.turboQuantAvailability.isAvailable ? LitterTheme.success : LitterTheme.warning)
            } header: {
                Text("Runtime")
            }

            Section {
                TextEditor(text: stringBinding(\.systemPromptOverride))
                    .frame(minHeight: 90)
                    .font(.system(.caption, design: .monospaced))
                Text("Optional. Leave empty to use the Gemma/Qwen/Llama-aware prompt template.")
                    .litterFont(.caption)
                    .foregroundColor(LitterTheme.textMuted)
            } header: {
                Text("System Prompt Override")
            }

            Section {
                Button("Reset This Model") { providerStore.resetRuntimeSettings(for: model) }
                    .foregroundColor(LitterTheme.warning)
            }
        }
        .navigationTitle("Model Runtime")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            capability = .current()
            Task { await providerStore.refreshRuntimeCapabilities() }
        }
    }

    private var settings: LocalModelRuntimeSettings {
        providerStore.runtimeSettings(for: model, capability: capability)
    }

    private func intBinding(_ keyPath: WritableKeyPath<LocalModelRuntimeSettings, Int>) -> Binding<Int> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in providerStore.updateRuntimeSettings(for: model, capability: capability) { $0[keyPath: keyPath] = value } }
        )
    }

    private func doubleBinding(_ keyPath: WritableKeyPath<LocalModelRuntimeSettings, Double>) -> Binding<Double> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in providerStore.updateRuntimeSettings(for: model, capability: capability) { $0[keyPath: keyPath] = value } }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<LocalModelRuntimeSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in providerStore.updateRuntimeSettings(for: model, capability: capability) { $0[keyPath: keyPath] = value } }
        )
    }

    private func stringBinding(_ keyPath: WritableKeyPath<LocalModelRuntimeSettings, String>) -> Binding<String> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in providerStore.updateRuntimeSettings(for: model, capability: capability) { $0[keyPath: keyPath] = value } }
        )
    }

    private var toolModeBinding: Binding<LocalModelToolUseMode> {
        Binding(
            get: { settings.toolUseMode },
            set: { value in providerStore.updateRuntimeSettings(for: model, capability: capability) { $0.toolUseMode = value } }
        )
    }

    private var kvCacheBinding: Binding<LocalModelKVCacheMode> {
        Binding(
            get: { settings.kvCacheMode },
            set: { value in providerStore.updateRuntimeSettings(for: model, capability: capability) { $0.kvCacheMode = value } }
        )
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.2f", value))
                    .foregroundColor(LitterTheme.textSecondary)
            }
            Slider(value: $value, in: range)
        }
    }
}
