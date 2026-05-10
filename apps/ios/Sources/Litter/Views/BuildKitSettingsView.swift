import SwiftUI

struct BuildKitSettingsView: View {
    @State private var status: LitterBuildKitStatus?
    @State private var isRefreshing = false

    var body: some View {
        List {
            readinessSection
            commandsSection
            pathsSection
            sourceSection
        }
        .navigationTitle("BuildKit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh") { Task { await refresh() } }
                    .disabled(isRefreshing)
            }
        }
        .task { await refresh() }
    }

    private var readinessSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 6) {
                    Text(status?.readinessTitle ?? "Scanning BuildKit")
                        .litterFont(.subheadline, weight: .semibold)
                        .foregroundStyle(LitterTheme.textPrimary)
                    Text(status?.readinessDetail ?? "Checking Nyxian source import, fakefs shims, and native compiler assets.")
                        .litterFont(.caption)
                        .foregroundStyle(LitterTheme.textSecondary)
                }
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            Button {
                Task {
                    await LitterBuildKit.shared.installFakefsCommandShims()
                    await LitterBuildKit.shared.startFakefsRequestMonitor()
                    await refresh()
                }
            } label: {
                Label("Install Fakefs Commands", systemImage: "terminal")
                    .foregroundStyle(LitterTheme.accent)
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))
        } header: {
            Text("On-device Swift BuildKit")
                .foregroundStyle(LitterTheme.textSecondary)
        }
    }

    private var commandsSection: some View {
        Section {
            ForEach(status?.commands ?? [], id: \.self) { command in
                HStack {
                    Text(command)
                        .litterMonoFont(size: 13, weight: .semibold)
                        .foregroundStyle(LitterTheme.textPrimary)
                    Spacer()
                    Text(commandPurpose(command))
                        .litterFont(.caption)
                        .foregroundStyle(LitterTheme.textSecondary)
                }
                .listRowBackground(LitterTheme.surface.opacity(0.6))
            }
        } header: {
            Text("Bot Commands")
                .foregroundStyle(LitterTheme.textSecondary)
        } footer: {
            Text("These commands are visible inside /root through iSH. They queue requests for the native Litter BuildKit bridge; Alpine itself is not pretending to be Xcode.")
        }
    }

    private var pathsSection: some View {
        Section {
            statusRow("Fakefs shims", status?.commandShimsInstalled == true ? "Installed" : "Missing")
            statusRow("Request monitor", status?.requestMonitorRunning == true ? "Running" : "Stopped")
            statusRow("Compiler assets", status?.nativeCompilerAssetsInstalled == true ? "Installed" : "Missing")
            statusRow("iPhoneOS SDK", status?.sdkInstalled == true ? "Installed" : "Missing")
            if let status {
                pathRow("Toolchain", status.toolchainRoot)
                pathRow("SDK", status.sdkRoot)
            }
        } header: {
            Text("Status")
                .foregroundStyle(LitterTheme.textSecondary)
        }
    }

    private var sourceSection: some View {
        Section {
            statusRow("Nyxian source", status?.sourceImportAvailable == true ? "Bundled manifest present" : "Missing")
            Text("Direct source imports live under ThirdParty/Nyxian in the repository with AGPL-3.0 attribution. The raw imported files are kept out of the app target until each compiler/runtime component is adapted and verified.")
                .litterFont(.caption)
                .foregroundStyle(LitterTheme.textSecondary)
                .listRowBackground(LitterTheme.surface.opacity(0.6))
        } header: {
            Text("Source Import")
                .foregroundStyle(LitterTheme.textSecondary)
        }
    }

    private var statusIcon: String {
        if status?.nativeCompilerAssetsInstalled == true && status?.sdkInstalled == true { return "checkmark.seal.fill" }
        if status?.sourceImportAvailable == true { return "shippingbox.fill" }
        return "exclamationmark.triangle.fill"
    }

    private var statusColor: Color {
        if status?.nativeCompilerAssetsInstalled == true && status?.sdkInstalled == true { return LitterTheme.success }
        if status?.sourceImportAvailable == true { return LitterTheme.warning }
        return LitterTheme.danger
    }

    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(LitterTheme.textPrimary)
            Spacer()
            Text(value)
                .litterFont(.caption, weight: .semibold)
                .foregroundStyle(LitterTheme.textSecondary)
        }
        .listRowBackground(LitterTheme.surface.opacity(0.6))
    }

    private func pathRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .foregroundStyle(LitterTheme.textPrimary)
            Text(value)
                .litterMonoFont(size: 11, weight: .regular)
                .foregroundStyle(LitterTheme.textSecondary)
                .textSelection(.enabled)
        }
        .listRowBackground(LitterTheme.surface.opacity(0.6))
    }

    private func commandPurpose(_ command: String) -> String {
        switch command {
        case "litter-swift-check": return "Swift diagnostics"
        case "litter-swift-test": return "Logic tests"
        case "litter-ipa-build": return "Unsigned IPA"
        case "litter-ipa-package": return "Package app"
        case "litter-build-status": return "Logs"
        case "litter-build-cancel": return "Cancel"
        default: return "Status"
        }
    }

    @MainActor
    private func refresh() async {
        isRefreshing = true
        status = await LitterBuildKit.shared.status()
        isRefreshing = false
    }
}
