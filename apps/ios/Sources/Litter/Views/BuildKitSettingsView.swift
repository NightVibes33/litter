import SwiftUI

struct BuildKitSettingsView: View {
    @State private var status: LitterBuildKitStatus?
    @State private var isRefreshing = false
    @State private var lastActionOutput: String?

    var body: some View {
        List {
            readinessSection
            commandsSection
            pathsSection
            sourceSection
            actionOutputSection
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

            Button {
                Task {
                    await LitterBuildKit.shared.installBundledAssetsIfAvailable()
                    await refresh()
                }
            } label: {
                Label("Install Private Assets", systemImage: "shippingbox")
                    .foregroundStyle(LitterTheme.accent)
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            Button {
                Task {
                    await LitterBuildKit.shared.installFakefsCommandShims()
                    let result = await IshFS.run("litter-fs-doctor --timeout 60")
                    lastActionOutput = result.output
                    await refresh()
                }
            } label: {
                Label("Run Fakefs Doctor", systemImage: "stethoscope")
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
            statusRow("Private assets", status?.privateAssetsInstalled == true ? "Installed" : "Missing")
            statusRow("CoreCompiler", status?.nativeCompilerAssetsInstalled == true ? "Installed" : "Missing")
            statusRow("Native driver", status?.nativeDriverInstalled == true ? "Installed" : "Missing")
            statusRow("Driver loadable", status?.nativeDriverLoadable == true ? "Ready" : "Not ready")
            statusRow("Swift support libs", status?.supportLibrariesInstalled == true ? "Installed" : "Missing")
            statusRow("iPhoneOS SDK", status?.sdkInstalled == true ? "Installed" : "Missing")
            if let status {
                pathRow("BuildKit", status.buildKitRoot)
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
            if let manifest = status?.assetManifest {
                statusRow("Asset bundle", manifest.bundleIdentifier)
                statusRow("SDK", manifest.sdkVersion)
                statusRow("Swift", manifest.swiftVersion ?? "Unknown")
            }
            Text("Direct source imports live under ThirdParty/Nyxian in the repository with AGPL-3.0 attribution. Apple SDK files must come from a private user-owned BuildKitAssets bundle and are not committed to the public repo.")
                .litterFont(.caption)
                .foregroundStyle(LitterTheme.textSecondary)
                .listRowBackground(LitterTheme.surface.opacity(0.6))
        } header: {
            Text("Source Import")
                .foregroundStyle(LitterTheme.textSecondary)
        }
    }

    private var actionOutputSection: some View {
        Section {
            if let lastActionOutput, !lastActionOutput.isEmpty {
                Text(lastActionOutput)
                    .litterMonoFont(size: 11, weight: .regular)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .textSelection(.enabled)
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
            } else {
                Text("Run Fakefs Doctor to validate /dev/random, /dev/urandom, temp files, and BuildKit command paths.")
                    .litterFont(.caption)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
            }
        } header: {
            Text("Diagnostics")
                .foregroundStyle(LitterTheme.textSecondary)
        }
    }

    private var statusIcon: String {
        if status?.isReadyForNativeBuilds == true { return "checkmark.seal.fill" }
        if status?.sourceImportAvailable == true { return "shippingbox.fill" }
        return "exclamationmark.triangle.fill"
    }

    private var statusColor: Color {
        if status?.isReadyForNativeBuilds == true { return LitterTheme.success }
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
        case "litter-swift-build": return "Build app"
        case "litter-swift-test": return "Logic tests"
        case "litter-ipa-build": return "Unsigned IPA"
        case "litter-ipa-package": return "Package app"
        case "litter-buildkit-install-assets": return "Install"
        case "litter-fs-doctor": return "Doctor"
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
