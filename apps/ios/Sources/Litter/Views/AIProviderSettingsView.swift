import SwiftUI

// Build trigger: compiler fixes verified
struct AIProviderSettingsView: View {
    @StateObject private var providerStore = AIProviderStore.shared
    @StateObject private var perplexityInstaller = PerplexityFakefsInstaller.shared
    @State private var showAddProvider = false

    var body: some View {
        List {
            modelSettingsSection
            providersSection
            if !AppDistributionCapabilities.isAppStoreSafe {
                perplexitySection
            }
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
        .onAppear {
            providerStore.reload()
        }
    }

    private var modelSettingsSection: some View {
        Section {
            Picker("Default Route", selection: globalRoutingBinding) {
                ForEach(availableRoutingModes) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            Text("Choose which account handles chat. ChatGPT uses the local Codex route; Perplexity sends turns only to the logged-in Perplexity route in sideload builds.")
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

    private var perplexitySection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "sparkle.magnifyingglass")
                    .foregroundColor(LitterTheme.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Perplexity Chat Runtime")
                        .litterFont(.subheadline)
                        .foregroundColor(LitterTheme.textPrimary)
                    Text("Installs the Perplexity client, chat runtime, MCP entrypoint, and command shims into /root/alley-cat/perplexity-ai.")
                        .litterFont(.caption)
                        .foregroundColor(LitterTheme.textSecondary)
                }
            }
            Button {
                Task { await perplexityInstaller.install() }
            } label: {
                HStack {
                    if perplexityInstaller.isInstalling { ProgressView().scaleEffect(0.8) }
                    Text(perplexityInstaller.isInstalling ? "Installing" : "Install Perplexity Runtime")
                }
            }
            .disabled(perplexityInstaller.isInstalling)
            Text(perplexityInstaller.lastStatus)
                .litterFont(.caption)
                .foregroundColor(LitterTheme.textMuted)
                
            Toggle("Run Local Tools Proxy (Port 8001)", isOn: Binding(
                get: { perplexityInstaller.isProxyRunning },
                set: { newValue in Task { await handleProxyToggle(isOn: newValue) } }
            ))
            .onAppear {
                Task { await perplexityInstaller.checkProxyStatus() }
            }
        } header: {
            Text("Sideload Perplexity")
                .foregroundColor(LitterTheme.textSecondary)
        } footer: {
            Text("Commands after install: perplexity-setup, perplexity-chat, and perplexity-mcp. Add your own Perplexity cookies with PERPLEXITY_COOKIES or ~/.config/alley-cat/perplexity-cookies.json for account-backed modes.")
        }
    }

    private func handleProxyToggle(isOn: Bool) {
        Task {
            if isOn {
                var account: PerplexityAccount? = nil
                do {
                    account = try PerplexityAccountStore.shared.activeAccount()
                } catch {
                    print("Failed to get active account: \(error)")
                }
                await perplexityInstaller.startOpenAIProxy(account: account)
            } else {
                await perplexityInstaller.stopOpenAIProxy()
            }
        }
    }

    private var notesSection: some View {
        Section {
            Text("For private/local models, run them on a computer and add the server's OpenAI-compatible /v1 endpoint here. The iPhone app stays focused on the terminal, file browser, remote bridges, and Swift BuildKit.")
                .litterFont(.caption)
                .foregroundColor(LitterTheme.textMuted)
                .listRowBackground(LitterTheme.surface.opacity(0.6))
        } header: {
            Text("Runtime Guidance")
                .foregroundColor(LitterTheme.textSecondary)
        }
    }

    private var availableRoutingModes: [AIModelRoutingMode] {
        AIModelRoutingMode.allCases.filter { mode in
            mode != .perplexity || !AppDistributionCapabilities.isAppStoreSafe
        }
    }

    private var globalRoutingBinding: Binding<AIModelRoutingMode> {
        Binding(
            get: { providerStore.globalModelSettings.routingMode },
            set: { value in
                let next = (value == .perplexity && AppDistributionCapabilities.isAppStoreSafe) ? .automatic : value
                providerStore.updateGlobalModelSettings { $0.routingMode = next }
            }
        )
    }

    private func providerSubtitle(_ provider: AIProviderProfile) -> String {
        switch provider.kind {
        case .openAI: return provider.defaultModel.isEmpty ? provider.baseURL : "\(provider.defaultModel) · \(provider.baseURL)"
        case .openAICompatible: return provider.defaultModel.isEmpty ? provider.baseURL : "\(provider.defaultModel) · \(provider.baseURL)"
        case .perplexity: return "Sideload chat runtime · \(provider.baseURL)"
        }
    }

    private func icon(for kind: AIProviderKind) -> String {
        switch kind {
        case .openAI: return "cloud"
        case .openAICompatible: return "desktopcomputer"
        case .perplexity: return "sparkle.magnifyingglass"
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
                        Text("Test Connection")
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
            if provider.kind == .perplexity {
                Section {
                    Button {
                        Task { await PerplexityFakefsInstaller.shared.install() }
                    } label: {
                        Text("Install Perplexity Runtime")
                    }
                    Text("/root/alley-cat/perplexity-ai")
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
