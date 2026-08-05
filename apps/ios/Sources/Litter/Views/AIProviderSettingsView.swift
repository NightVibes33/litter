import SwiftUI

struct AIProviderSettingsView: View {
    @StateObject private var providerStore = AIProviderStore.shared
    @State private var showAddProvider = false

    var body: some View {
        List {
            appleIntelligenceSection
            modelSettingsSection
            providersSection
            notesSection
        }
        .scrollContentBackground(.hidden)
        .background(AlleyBackdrop().ignoresSafeArea())
        .tint(LitterTheme.accent)
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
                .accessibilityLabel("Add compatible AI server")
            }
        }
        .sheet(isPresented: $showAddProvider) {
            NavigationStack {
                AddAIProviderView()
            }
        }
        .onAppear {
            providerStore.reload()
        }
    }

    private var appleIntelligenceSection: some View {
        Section {
            NavigationLink {
                PocketKernelChatView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "apple.intelligence")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(LitterTheme.accent)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("PocketKernel Chat")
                            .foregroundStyle(LitterTheme.textPrimary)
                        Text(AppleFoundationModelProvider.shared.availability().summary)
                            .litterFont(.caption)
                            .foregroundStyle(
                                AppleFoundationModelProvider.shared.availability().isAvailable
                                    ? LitterTheme.accent
                                    : LitterTheme.warning
                            )
                            .lineLimit(2)
                    }
                }
            }
            .listRowBackground(LitterTheme.surface.opacity(0.88))
        } header: {
            Text("On-device agent")
                .foregroundColor(LitterTheme.textSecondary)
        } footer: {
            Text("PocketKernel plans locally with Apple Intelligence. Commands and file changes require approval before the embedded iSH runtime executes them.")
                .foregroundStyle(LitterTheme.textMuted)
        }
    }

    private var modelSettingsSection: some View {
        Section {
            Picker("Default Route", selection: globalRoutingBinding) {
                ForEach(AIModelRoutingMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            Text("Apple On-Device is the default and does not require an account, API key, or network connection. Cloud and compatible-server routes remain optional.")
                .litterFont(.caption)
                .foregroundColor(LitterTheme.textMuted)
        } header: {
            Text("Routing")
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
                                .lineLimit(2)
                        }
                        Spacer()
                        if provider.isEnabled {
                            Text("On")
                                .litterFont(.caption)
                                .foregroundColor(LitterTheme.accent)
                        }
                    }
                }
                .listRowBackground(LitterTheme.surface.opacity(0.88))
            }
        } header: {
            Text("Providers")
                .foregroundColor(LitterTheme.textSecondary)
        }
    }

    private var notesSection: some View {
        Section {
            Text("Apple's system language model runs on the device. Optional OpenAI-compatible providers can still be added for models hosted on a computer over LAN, VPN, or Tailscale.")
                .litterFont(.caption)
                .foregroundColor(LitterTheme.textMuted)
                .listRowBackground(LitterTheme.surface.opacity(0.88))
        } header: {
            Text("Runtime guidance")
                .foregroundColor(LitterTheme.textSecondary)
        }
    }

    private var globalRoutingBinding: Binding<AIModelRoutingMode> {
        Binding(
            get: { providerStore.globalModelSettings.routingMode },
            set: { value in
                providerStore.updateGlobalModelSettings {
                    $0.routingMode = value
                    $0.preferredProviderId = value == .appleOnDevice
                        ? AIProviderProfile.appleOnDeviceProviderID
                        : nil
                }
            }
        )
    }

    private func providerSubtitle(_ provider: AIProviderProfile) -> String {
        switch provider.kind {
        case .appleOnDevice:
            return AppleFoundationModelProvider.shared.availability().summary
        case .openAI, .openAICompatible:
            return provider.defaultModel.isEmpty
                ? provider.baseURL
                : "\(provider.defaultModel) · \(provider.baseURL)"
        }
    }

    private func icon(for kind: AIProviderKind) -> String {
        switch kind {
        case .appleOnDevice: return "apple.intelligence"
        case .openAI: return "cloud"
        case .openAICompatible: return "desktopcomputer"
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
        .scrollContentBackground(.hidden)
        .background(AlleyBackdrop().ignoresSafeArea())
        .tint(LitterTheme.accent)
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
                Text(providerSubtitle)
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
                        Text(provider.kind == .appleOnDevice ? "Check Availability" : "Test Connection")
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
            if provider.kind == .openAICompatible {
                Section {
                    Button(role: .destructive) {
                        try? providerStore.deleteProvider(provider)
                    } label: {
                        Text("Delete Provider")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AlleyBackdrop().ignoresSafeArea())
        .tint(LitterTheme.accent)
        .navigationTitle(provider.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var providerSubtitle: String {
        provider.kind == .appleOnDevice
            ? AppleFoundationModelProvider.shared.availability().summary
            : provider.baseURL
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
