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
                capabilityRow("Metal", capability.metalDeviceName ?? "Unavailable")
                if !capability.supportedGPUFamilies.isEmpty {
                    capabilityRow("GPU Families", capability.supportedGPUFamilies.joined(separator: ", "))
                }
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
                Label("Download or Search Models", systemImage: "magnifyingglass.circle")
                    .foregroundColor(LitterTheme.accent)
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            if let statusMessage {
                Text(statusMessage)
                    .litterFont(.caption)
                    .foregroundColor(LitterTheme.textSecondary)
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
            }

            if providerStore.localModels.isEmpty {
                Text("No on-device models imported yet. Use quantized GGUF files; if a model is too large, run it on your PC with Ollama instead.")
                    .litterFont(.caption)
                    .foregroundColor(LitterTheme.textMuted)
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
            } else {
                ForEach(providerStore.localModels) { model in
                    VStack(alignment: .leading, spacing: 6) {
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
                        Text("\(model.displaySize)\(model.quantizationHint.map { " · \($0)" } ?? "")")
                            .litterFont(.caption)
                            .foregroundColor(LitterTheme.textSecondary)
                        Text(model.recommendation)
                            .litterFont(.caption)
                            .foregroundColor(LitterTheme.textMuted)
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
            Text("PC-hosted Ollama or LM Studio is the best path for powerful local models. On-device models can use Litter tools when the local inference runtime is connected, but they should be chosen based on device RAM, Metal support, thermal state, and storage.")
                .litterFont(.caption)
                .foregroundColor(LitterTheme.textMuted)
                .listRowBackground(LitterTheme.surface.opacity(0.6))
        } header: {
            Text("Reality Check")
                .foregroundColor(LitterTheme.textSecondary)
        }
    }

    private func capabilityRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .litterFont(.caption)
                .foregroundColor(LitterTheme.textMuted)
            Spacer()
            Text(value)
                .litterFont(.caption)
                .foregroundColor(LitterTheme.textSecondary)
                .multilineTextAlignment(.trailing)
        }
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
