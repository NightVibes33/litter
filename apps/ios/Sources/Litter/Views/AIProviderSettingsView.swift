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
            Text("TurboQuant is only enabled when the linked llama.cpp runtime reports support. Standard builds keep it unavailable instead of showing a nonfunctional switch.")
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
                        Text(localModelSubtitle(model))
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
            Text("PC-hosted Ollama or LM Studio is still best for the largest models. On-device models use the native llama.cpp bridge when linked, guarded fakefs tools, approval requests for shell/write actions, retry events, streaming tool-call state, and user-controlled runtime settings.")
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

    private func localModelSubtitle(_ model: LocalModelRecord) -> String {
        var parts = [model.displaySize]
        if let quantizationHint = model.quantizationHint { parts.append(quantizationHint) }
        if let nativeContextLength = model.nativeContextLength { parts.append("\(nativeContextLength) ctx") }
        parts.append(model.validationStatus.displayName)
        return parts.joined(separator: " · ")
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


struct LocalModelRuntimeSettingsView: View {
    @StateObject private var providerStore = AIProviderStore.shared
    let model: LocalModelRecord
    @State private var capability = DeviceCapabilityProfile.current()

    var body: some View {
        Form {
            summarySection
            presetsSection
            agentSection
            samplingSection
            advancedSamplingSection
            runtimeSection
            promptSection
            expertRopeSection
            resetSection
        }
        .navigationTitle("Model Runtime")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            capability = .current()
            Task { await providerStore.refreshRuntimeCapabilities() }
        }
    }

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.fileName)
                    .litterFont(.subheadline, weight: .semibold)
                    .foregroundColor(LitterTheme.textPrimary)
                    .lineLimit(2)
                Text("Saved exactly as user preferences. Device detection only warns; it does not downgrade your context length.")
                    .litterFont(.caption)
                    .foregroundColor(LitterTheme.textSecondary)
                Text("Recommended context for this device: \(recommendedContextLabel)")
                    .litterFont(.caption)
                    .foregroundColor(LitterTheme.textMuted)
                if let warning = settings.warningSummary {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .litterFont(.caption)
                        .foregroundColor(LitterTheme.warning)
                }
            }
        } header: {
            Text("Preference Model")
        }
    }

    private var presetsSection: some View {
        Section {
            Button("Safe") { applyPreset(.safe) }
            Button("Balanced") { applyPreset(.balanced) }
            Button("Coding Agent") { applyPreset(.codingAgent) }
            Button("Experimental Max Context") { applyPreset(.experimentalMaxContext) }
                .foregroundColor(LitterTheme.warning)
        } header: {
            Text("Presets")
        } footer: {
            Text("Presets are shortcuts only. You can override every value afterward.")
        }
    }

    private var agentSection: some View {
        Section {
            Stepper("Context: \(settings.contextTokens) tokens", value: intBinding(\.contextTokens), in: 512...131_072, step: 512)
            Stepper("Max output: \(settings.maxOutputTokens) tokens", value: intBinding(\.maxOutputTokens), in: 64...16_384, step: 64)
            Stepper("Tool rounds: \(settings.maxToolRounds)", value: intBinding(\.maxToolRounds), in: 0...20)
            Stepper("Retry attempts: \(settings.retryAttempts)", value: intBinding(\.retryAttempts), in: 1...5)
            Picker("Tool Use", selection: toolModeBinding) {
                ForEach(LocalModelToolUseMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
        } header: {
            Text("Agent Behavior")
        }
    }

    private var samplingSection: some View {
        Section {
            SliderRow(title: "Temperature", value: doubleBinding(\.temperature), range: 0...2)
            SliderRow(title: "Top P", value: doubleBinding(\.topP), range: 0.05...1)
            Stepper("Top K: \(settings.topK)", value: intBinding(\.topK), in: 1...200)
            Stepper("Repeat window: \(settings.repeatLastN)", value: intBinding(\.repeatLastN), in: 0...4_096, step: 32)
            SliderRow(title: "Repeat penalty", value: doubleBinding(\.repeatPenalty), range: 0.8...1.5)
            SliderRow(title: "Frequency penalty", value: doubleBinding(\.frequencyPenalty), range: -2...2)
            SliderRow(title: "Presence penalty", value: doubleBinding(\.presencePenalty), range: -2...2)
            Stepper(seedLabel, value: intBinding(\.seed), in: -1...999_999)
        } header: {
            Text("Sampling")
        } footer: {
            Text("Seed -1 uses the runtime default random seed. Frequency and presence penalties are wired into llama.cpp generation.")
        }
    }

    private var advancedSamplingSection: some View {
        Section {
            SliderRow(title: "Min P", value: doubleBinding(\.minP), range: 0...1)
            SliderRow(title: "Typical P", value: doubleBinding(\.typicalP), range: 0...1)
            SliderRow(title: "Dynamic temp range", value: doubleBinding(\.dynamicTemperatureRange), range: 0...2)
            SliderRow(title: "Dynamic temp exponent", value: doubleBinding(\.dynamicTemperatureExponent), range: 0.1...8)
            Picker("Mirostat", selection: mirostatBinding) {
                ForEach(LocalModelMirostatMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            SliderRow(title: "Mirostat tau", value: doubleBinding(\.mirostatTau), range: 0.1...20)
            SliderRow(title: "Mirostat eta", value: doubleBinding(\.mirostatEta), range: 0.001...1)
        } header: {
            Text("Advanced Sampling")
        } footer: {
            Text("Min-P, typical sampling, dynamic temperature, and Mirostat are passed into the llama.cpp sampler chain when enabled.")
        }
    }

    private var runtimeSection: some View {
        Section {
            Toggle("Use Metal GPU", isOn: boolBinding(\.metalEnabled))
                .disabled(!capability.hasMetal)
            Stepper(gpuLayerLabel, value: intBinding(\.gpuLayerCount), in: -1...512)
                .disabled(!settings.metalEnabled)
            Toggle("Allow CPU fallback", isOn: boolBinding(\.cpuFallbackAllowed))
            Toggle("Stream tokens", isOn: boolBinding(\.streamingEnabled))
            Toggle("Memory map model", isOn: boolBinding(\.mmapEnabled))
            Toggle("Lock model in RAM", isOn: boolBinding(\.mlockEnabled))
            Toggle("Validate tensors on load", isOn: boolBinding(\.checkTensors))
            Stepper("Threads: \(settings.preferredThreadCount)", value: intBinding(\.preferredThreadCount), in: 1...max(1, ProcessInfo.processInfo.processorCount))
            Stepper(batchThreadLabel, value: intBinding(\.batchThreadCount), in: 0...max(1, ProcessInfo.processInfo.processorCount))
            Stepper("Batch: \(settings.batchSize)", value: intBinding(\.batchSize), in: 32...4_096, step: 32)
            Stepper("Microbatch: \(settings.microBatchSize)", value: intBinding(\.microBatchSize), in: 32...min(settings.batchSize, 2_048), step: 32)
            Picker("Flash Attention", selection: flashAttentionBinding) {
                ForEach(LocalModelFlashAttentionMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            Toggle("Offload KQV", isOn: boolBinding(\.offloadKQV))
                .disabled(!settings.metalEnabled)
            Toggle("Offload ops", isOn: boolBinding(\.opOffload))
                .disabled(!settings.metalEnabled)
            Toggle("Full SWA cache", isOn: boolBinding(\.swaFull))
            Toggle("Unified KV cache", isOn: boolBinding(\.kvUnified))
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
            Text("Memory / Offload")
        } footer: {
            Text("GPU layers, mmap, mlock, tensor validation, threads, batch sizes, Flash Attention, KQV/op offload, and KV cache options are passed to llama.cpp.")
        }
    }

    private var promptSection: some View {
        Section {
            Picker("Prompt Template", selection: promptTemplateBinding) {
                ForEach(LocalModelPromptTemplateMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            Toggle("Parse special tokens", isOn: boolBinding(\.parseSpecialTokens))
            TextEditor(text: stopSequencesTextBinding)
                .frame(minHeight: 70)
                .font(.system(.caption, design: .monospaced))
            TextEditor(text: stringBinding(\.systemPromptOverride))
                .frame(minHeight: 110)
                .font(.system(.caption, design: .monospaced))
            Text("Stop sequences are one per line. The system prompt override is optional; leave it empty to use the model-aware local-agent prompt template.")
                .litterFont(.caption)
                .foregroundColor(LitterTheme.textMuted)
        } header: {
            Text("Prompt / Template")
        }
    }

    private var expertRopeSection: some View {
        Section {
            Picker("RoPE Scaling", selection: ropeScalingBinding) {
                ForEach(LocalModelRopeScalingMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            SliderRow(title: "RoPE base", value: doubleBinding(\.ropeFrequencyBase), range: 0...1_000_000)
            SliderRow(title: "RoPE scale", value: doubleBinding(\.ropeFrequencyScale), range: 0...100)
            SliderRow(title: "YaRN extension", value: doubleBinding(\.yarnExtensionFactor), range: -1...100)
            SliderRow(title: "YaRN attention", value: doubleBinding(\.yarnAttentionFactor), range: -1...100)
            SliderRow(title: "YaRN beta fast", value: doubleBinding(\.yarnBetaFast), range: -1...256)
            SliderRow(title: "YaRN beta slow", value: doubleBinding(\.yarnBetaSlow), range: -1...256)
            Stepper("YaRN original ctx: \(settings.yarnOriginalContext)", value: intBinding(\.yarnOriginalContext), in: 0...131_072, step: 512)
        } header: {
            Text("Expert RoPE")
        } footer: {
            Text("Default sentinel values use llama.cpp or model metadata. Change these only for models that require explicit context scaling.")
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset This Model") { providerStore.resetRuntimeSettings(for: model) }
                .foregroundColor(LitterTheme.warning)
        }
    }

    private var settings: LocalModelRuntimeSettings {
        providerStore.runtimeSettings(for: model, capability: capability)
    }

    private var recommendedContextLabel: String {
        capability.recommendedContextTokens == 0 ? "PC-hosted" : "\(capability.recommendedContextTokens) tokens"
    }

    private var seedLabel: String {
        settings.seed < 0 ? "Seed: Random" : "Seed: \(settings.seed)"
    }


    private var gpuLayerLabel: String {
        settings.gpuLayerCount < 0 ? "GPU layers: All" : "GPU layers: \(settings.gpuLayerCount)"
    }

    private var batchThreadLabel: String {
        settings.batchThreadCount == 0 ? "Batch threads: Match generation" : "Batch threads: \(settings.batchThreadCount)"
    }

    private func applyPreset(_ preset: RuntimePreset) {
        providerStore.updateRuntimeSettings(for: model, capability: capability) { next in
            switch preset {
            case .safe:
                next.contextTokens = 2_048
                next.maxOutputTokens = 512
                next.temperature = 0.2
                next.topP = 0.9
                next.topK = 40
                next.repeatLastN = 64
                next.repeatPenalty = 1.08
                next.frequencyPenalty = 0
                next.presencePenalty = 0
                next.preferredThreadCount = max(1, min(4, ProcessInfo.processInfo.processorCount))
                next.batchSize = 512
                next.microBatchSize = 256
                next.maxToolRounds = 3
                next.retryAttempts = 2
                next.toolUseMode = .approvalRequired
            case .balanced:
                next.contextTokens = max(4_096, capability.recommendedContextTokens)
                next.maxOutputTokens = 1_024
                next.temperature = 0.2
                next.topP = 0.9
                next.topK = 40
                next.repeatLastN = 64
                next.repeatPenalty = 1.08
                next.frequencyPenalty = 0
                next.presencePenalty = 0
                next.preferredThreadCount = max(2, min(6, ProcessInfo.processInfo.processorCount))
                next.batchSize = 1_024
                next.microBatchSize = 512
                next.maxToolRounds = 5
                next.retryAttempts = 2
                next.toolUseMode = .approvalRequired
            case .codingAgent:
                next.contextTokens = max(8_192, capability.recommendedContextTokens)
                next.maxOutputTokens = 2_048
                next.temperature = 0.15
                next.topP = 0.92
                next.topK = 50
                next.repeatLastN = 128
                next.repeatPenalty = 1.1
                next.frequencyPenalty = 0
                next.presencePenalty = 0
                next.preferredThreadCount = max(2, min(6, ProcessInfo.processInfo.processorCount))
                next.batchSize = 1_024
                next.microBatchSize = 512
                next.maxToolRounds = 8
                next.retryAttempts = 3
                next.toolUseMode = .approvalRequired
            case .experimentalMaxContext:
                next.contextTokens = 32_768
                next.maxOutputTokens = 4_096
                next.temperature = 0.15
                next.topP = 0.95
                next.topK = 64
                next.repeatLastN = 256
                next.repeatPenalty = 1.08
                next.frequencyPenalty = 0
                next.presencePenalty = 0
                next.preferredThreadCount = max(1, ProcessInfo.processInfo.processorCount)
                next.batchSize = 2_048
                next.microBatchSize = 1_024
                next.maxToolRounds = 12
                next.retryAttempts = 3
                next.toolUseMode = .approvalRequired
            }
            applyAdvancedDefaults(to: &next)
            next.metalEnabled = capability.hasMetal
            next.cpuFallbackAllowed = false
            next.streamingEnabled = true
        }
    }

    private func applyAdvancedDefaults(to settings: inout LocalModelRuntimeSettings) {
        settings.minP = 0
        settings.typicalP = 1
        settings.dynamicTemperatureRange = 0
        settings.dynamicTemperatureExponent = 1
        settings.mirostatMode = .off
        settings.mirostatTau = 5
        settings.mirostatEta = 0.1
        settings.batchThreadCount = 0
        settings.gpuLayerCount = -1
        settings.mmapEnabled = true
        settings.mlockEnabled = false
        settings.checkTensors = false
        settings.flashAttentionMode = .automatic
        settings.offloadKQV = true
        settings.opOffload = true
        settings.swaFull = true
        settings.kvUnified = false
        settings.promptTemplateMode = .litter
        settings.parseSpecialTokens = true
        settings.stopSequences = []
        settings.ropeScalingMode = .modelDefault
        settings.ropeFrequencyBase = 0
        settings.ropeFrequencyScale = 0
        settings.yarnExtensionFactor = -1
        settings.yarnAttentionFactor = -1
        settings.yarnBetaFast = -1
        settings.yarnBetaSlow = -1
        settings.yarnOriginalContext = 0
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

    private var mirostatBinding: Binding<LocalModelMirostatMode> {
        Binding(
            get: { settings.mirostatMode },
            set: { value in providerStore.updateRuntimeSettings(for: model, capability: capability) { $0.mirostatMode = value } }
        )
    }

    private var flashAttentionBinding: Binding<LocalModelFlashAttentionMode> {
        Binding(
            get: { settings.flashAttentionMode },
            set: { value in providerStore.updateRuntimeSettings(for: model, capability: capability) { $0.flashAttentionMode = value } }
        )
    }

    private var promptTemplateBinding: Binding<LocalModelPromptTemplateMode> {
        Binding(
            get: { settings.promptTemplateMode },
            set: { value in providerStore.updateRuntimeSettings(for: model, capability: capability) { $0.promptTemplateMode = value } }
        )
    }

    private var ropeScalingBinding: Binding<LocalModelRopeScalingMode> {
        Binding(
            get: { settings.ropeScalingMode },
            set: { value in providerStore.updateRuntimeSettings(for: model, capability: capability) { $0.ropeScalingMode = value } }
        )
    }

    private var stopSequencesTextBinding: Binding<String> {
        Binding(
            get: { settings.stopSequences.joined(separator: "\n") },
            set: { value in
                providerStore.updateRuntimeSettings(for: model, capability: capability) {
                    $0.stopSequences = value.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                }
            }
        )
    }

    private enum RuntimePreset {
        case safe
        case balanced
        case codingAgent
        case experimentalMaxContext
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
