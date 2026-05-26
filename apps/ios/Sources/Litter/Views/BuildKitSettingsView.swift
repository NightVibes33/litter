import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct BuildKitSettingsView: View {
    @State private var status: LitterBuildKitStatus?
    @State private var isRefreshing = false
    @StateObject private var downloader = BuildKitAssetDownloadStore()
    @StateObject private var taskBag = ViewTaskBag()
    @State private var showingAssetImporter = false
    @State private var lastActionOutput: String?
    @State private var tokenInput = ""

    var body: some View {
        List {
            readinessSection
            privateAssetDownloadSection
            commandsSection
            pathsSection
            signingSection
            sourceSection
            actionOutputSection
        }
        .navigationTitle("BuildKit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh") { taskBag.run { await refresh() } }
                    .disabled(isRefreshing)
            }
        }
        .fileImporter(isPresented: $showingAssetImporter, allowedContentTypes: [.folder, .json, .zip], allowsMultipleSelection: false) { result in
            handleAssetImport(result)
        }
        .onChange(of: downloader.installRevision) { _, _ in
            taskBag.run { await refresh() }
        }
        .task {
            await refresh()
        }
        .onDisappear {
            taskBag.cancelAll()
            if downloader.phase.isBusy { downloader.cancel() }
        }
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
                taskBag.run {
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
                taskBag.run {
                    await LitterBuildKit.shared.installBundledAssetsIfAvailable()
                    await refresh()
                }
            } label: {
                Label("Install Bundled Assets", systemImage: "shippingbox")
                    .foregroundStyle(LitterTheme.accent)
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            Button {
                showingAssetImporter = true
            } label: {
                Label("Import Asset Folder or ZIP", systemImage: "folder.badge.plus")
                    .foregroundStyle(LitterTheme.accent)
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            Button {
                taskBag.run {
                    await runBuildKitCommand("litter-fs-doctor --timeout 60", title: "Fakefs Doctor")
                }
            } label: {
                Label("Run Fakefs Doctor", systemImage: "stethoscope")
                    .foregroundStyle(LitterTheme.accent)
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            Button {
                taskBag.run {
                    await runBuildKitCommand("litter-nyxian-status --timeout 60", title: "Nyxian Status")
                }
            } label: {
                Label("Run Nyxian Status", systemImage: "hammer")
                    .foregroundStyle(LitterTheme.accent)
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            Button {
                taskBag.run { await repairBuildKit() }
            } label: {
                Label("Repair BuildKit", systemImage: "wrench.and.screwdriver")
                    .foregroundStyle(LitterTheme.accent)
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            Button {
                taskBag.run { await runBuildKitCommand("litter-build-status", title: "Build Status") }
            } label: {
                Label("Run Build Status", systemImage: "list.clipboard")
                    .foregroundStyle(LitterTheme.accent)
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            Button {
                taskBag.run { await runSwiftSelfTest() }
            } label: {
                Label("Run Swift Self-Test", systemImage: "swift")
                    .foregroundStyle(LitterTheme.accent)
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))
        } header: {
            Text("On-device Swift BuildKit")
                .foregroundStyle(LitterTheme.textSecondary)
        }
    }

    private var privateAssetDownloadSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Private GitHub Release")
                    .litterFont(.caption, weight: .semibold)
                    .foregroundStyle(LitterTheme.textPrimary)
                Text("Default: NightVibes33/litter-buildkit-assets @ buildkit-ios26.4-v1. The app downloads LitterBuildKitAssets.zip, verifies SHA256, extracts it, and installs it into Documents/BuildKit.")
                    .litterFont(.caption)
                    .foregroundStyle(LitterTheme.textSecondary)
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            TextField("Owner", text: $downloader.config.owner)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .listRowBackground(LitterTheme.surface.opacity(0.6))
            TextField("Repo", text: $downloader.config.repo)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .listRowBackground(LitterTheme.surface.opacity(0.6))
            TextField("Release tag", text: $downloader.config.tag)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .listRowBackground(LitterTheme.surface.opacity(0.6))
            TextField("Asset name", text: $downloader.config.assetName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .listRowBackground(LitterTheme.surface.opacity(0.6))
            TextField("SHA256 or sidecar", text: $downloader.config.sha256)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .listRowBackground(LitterTheme.surface.opacity(0.6))

            SecureField(downloader.hasStoredToken ? "Token saved in Keychain" : "GitHub token for private repo", text: $tokenInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .listRowBackground(LitterTheme.surface.opacity(0.6))

            HStack(spacing: 12) {
                Button("Save Token") {
                    downloader.saveToken(tokenInput)
                    tokenInput = ""
                }
                .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Clear Token", role: .destructive) {
                    downloader.clearToken()
                    tokenInput = ""
                }
                .disabled(!downloader.hasStoredToken)
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(downloader.phase.title)
                        .litterFont(.caption, weight: .semibold)
                        .foregroundStyle(LitterTheme.textPrimary)
                    Spacer()
                    Text(downloader.speedText)
                        .litterMonoFont(size: 11, weight: .regular)
                        .foregroundStyle(LitterTheme.textSecondary)
                }
                ProgressView(value: downloader.progress)
                Text(downloader.progressText)
                    .litterMonoFont(size: 11, weight: .regular)
                    .foregroundStyle(LitterTheme.textSecondary)
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            HStack(spacing: 12) {
                Button {
                    downloader.downloadAndInstall()
                } label: {
                    Label("Download and Install ZIP", systemImage: "arrow.down.circle")
                        .foregroundStyle(LitterTheme.accent)
                }
                .disabled(downloader.phase.isBusy)

                if downloader.phase.isBusy {
                    Button("Cancel", role: .destructive) {
                        if downloader.phase.isBusy { downloader.cancel() }
                    }
                }
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            if let output = downloader.lastOutput, !output.isEmpty {
                Text(output)
                    .litterMonoFont(size: 11, weight: .regular)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .textSelection(.enabled)
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
            }
        } header: {
            Text("Private BuildKit Assets")
                .foregroundStyle(LitterTheme.textSecondary)
        } footer: {
            Text("Private release assets are user-owned. Downloaded assets enable data install; native frameworks may still need to be embedded by private CI so SideStore/AltStore signing can make the driver loadable.")
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
            statusRow("Swift direct build", status?.canRunSwiftDirectly == true ? "Ready" : "Blocked")
            statusRow("Unsigned IPA build", status?.canBuildUnsignedIPA == true ? "Ready" : "Blocked")
            statusRow("CoreCompiler", status?.nativeCompilerAssetsInstalled == true ? "Installed" : "Missing")
            statusRow("Native driver", status?.nativeDriverInstalled == true ? "Installed" : "Missing")
            statusRow("Driver loadable", status?.nativeDriverLoadable == true ? "Ready" : "Not ready")
            statusRow("Nyxian runner", status?.nativeRunnerInstalled == true ? "Installed" : "Missing")
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

    private var signingSection: some View {
        Section {
            Text("Apple ID sign-in and 2FA stay inside SideStore Settings. Settings > Signing owns Feather certificate import, provisioning profiles, pairing files, LocalDevVPN status, and signing options. BuildKit only reports whether those inputs are ready for the native runner.")
                .litterFont(.caption)
                .foregroundStyle(LitterTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .listRowBackground(LitterTheme.surface.opacity(0.6))

            statusRow("Embedded profile", status?.embeddedProvisionPresent == true ? "Present" : "Missing")
            statusRow("SideStore AltSign", KittyStoreSideStoreSigningBridge.isLinked ? "Linked" : "Missing")
            statusRow("Apple ID login", status?.appleIDConfigured == true ? "Logged in" : "Missing")
            statusRow("Apple ID detail", status?.appleIDDetail ?? "Missing")
            statusRow("Imported certificate", status?.nyxianSigningCertificateInstalled == true ? "Validated" : "Missing or invalid")
            statusRow("Certificate detail", status?.nyxianSigningCertificateDetail ?? "Missing")
            statusRow("Run/install signing", status?.canRunNyxianApps == true ? "Ready" : "Blocked")
            statusRow("LocalDevVPN", status?.localDevVPNConnected == true ? "Detected" : "Not detected")
            statusRow("VPN detail", status?.localDevVPNDetail ?? "No active VPN tunnel interface detected")
            statusRow("Full install/refresh", status?.canInstallOrRefreshOnDevice == true ? "Ready" : "Blocked")
        } header: {
            Text("KittyStore Signing State")
                .foregroundStyle(LitterTheme.textSecondary)
        } footer: {
            Text("BuildKit diagnostics stay read-only here so SideStore account transport and Feather signing options are not duplicated.")
        }
    }

    private var sourceSection: some View {
        Section {
            statusRow("Nyxian source", status?.sourceImportAvailable == true ? "Bundled manifest present" : "Missing")
            if let manifest = status?.assetManifest {
                statusRow("Asset bundle", manifest.bundleIdentifier)
                statusRow("SDK", manifest.sdkVersion)
                statusRow("Swift", manifest.swiftVersion ?? "Unknown")
                statusRow("Driver mode", manifest.toolchain.nativeDriverMode ?? "runner")
                statusRow("Capabilities", manifest.capabilities.isEmpty ? "None" : manifest.capabilities.joined(separator: ", "))
            }
            if let missing = status?.missingRequirements, !missing.isEmpty {
                Text("Missing: " + missing.joined(separator: ", "))
                    .litterFont(.caption)
                    .foregroundStyle(LitterTheme.warning)
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
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
                Text("Run Fakefs Doctor or Nyxian Status to validate /dev/random, /dev/urandom, toolchain assets, and BuildKit command paths.")
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
        case "litter-swift-selftest": return "Self-test"
        case "litter-swift-check": return "Swift diagnostics"
        case "litter-swift-build": return "Build app"
        case "litter-swift-test": return "Logic tests"
        case "litter-ipa-build": return "Unsigned IPA"
        case "litter-ipa-package": return "Package app"
        case "litter-nyxian-status": return "Nyxian"
        case "litter-kittystore-validate-profile": return "Profile"
        case "litter-kittystore-plan": return "Signing"
        case "litter-kittystore-sign": return "Signer"
        case "litter-kittystore-install", "litter-kittystore-refresh", "litter-kittystore-remove", "litter-kittystore-installed": return "Device"
        case "litter-buildkit-install-assets": return "Install"
        case "litter-fs-doctor": return "Doctor"
        case "litter-env-report": return "Environment"
        case "litter-dev-bootstrap": return "Bootstrap"
        case "litter-build-status": return "Logs"
        case "litter-build-cancel": return "Cancel"
        default: return "Status"
        }
    }

    @MainActor
    private func runBuildKitCommand(_ command: String, title: String) async {
        await LitterBuildKit.shared.installFakefsCommandShims()
        await LitterBuildKit.shared.startFakefsRequestMonitor()
        let result = await IshFS.run(command)
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        lastActionOutput = "\(title)\nCommand: \(command)\nExit code: \(result.exitCode)\n\n" + (output.isEmpty ? "No output." : output)
        await refresh()
    }

    @MainActor
    private func repairBuildKit() async {
        await LitterBuildKit.shared.installBundledAssetsIfAvailable()
        await LitterBuildKit.shared.installFakefsCommandShims()
        await LitterBuildKit.shared.startFakefsRequestMonitor()
        let doctor = await IshFS.run("litter-fs-doctor --timeout 60")
        lastActionOutput = "Repair BuildKit\nExit code: \(doctor.exitCode)\n\n" + doctor.output
        await refresh()
    }

    @MainActor
    private func runSwiftSelfTest() async {
        await runBuildKitCommand("litter-swift-selftest --timeout 240", title: "Swift Self-Test")
    }

    @MainActor
    private func handleAssetImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            taskBag.run {
                let output = await LitterBuildKit.shared.importAssetBundle(from: url)
                lastActionOutput = output
                await refresh()
            }
        case .failure(let error):
            lastActionOutput = "BuildKit asset import failed.\n\(error.localizedDescription)\n"
        }
    }

    @MainActor
    private func refresh() async {
        isRefreshing = true
        status = await LitterBuildKit.shared.status()
        isRefreshing = false
    }
}
