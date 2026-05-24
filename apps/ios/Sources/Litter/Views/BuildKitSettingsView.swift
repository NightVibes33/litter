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
    @State private var showingCertificateImporter = false
    @State private var appleIDEmailInput = ""
    @State private var appleIDTeamIDInput = ""
    @State private var appleIDPasswordInput = ""
    @State private var appleIDTwoFactorCodeInput = ""
    @State private var appleIDAnisetteURLInput = NyxianAnisetteServerDirectory.defaultServerURL
    @State private var selectedAnisetteServerAddress = NyxianAnisetteServerDirectory.defaultServerURL
    @State private var anisetteServerListURLInput = NyxianAnisetteServerDirectory.officialListURL
    @State private var anisetteServers = NyxianAnisetteServerDirectory.fallbackServers
    @State private var appleIDActionMessage: String?
    @State private var anisetteServerMessage: String?
    @State private var certificatePasswordInput = ""
    @State private var certificateActionMessage: String?

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
        .fileImporter(isPresented: $showingCertificateImporter, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            handleCertificateImport(result)
        }
        .onChange(of: downloader.installRevision) { _, _ in
            taskBag.run { await refresh() }
        }
        .onChange(of: selectedAnisetteServerAddress) { _, newValue in
            guard newValue != NyxianAnisetteServerDirectory.customSelectionID else { return }
            appleIDAnisetteURLInput = newValue
        }
        .task {
            await refresh()
            await refreshAnisetteServers(showSuccess: false)
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
            Text("SideStore or AltStore signs the unsigned Litter IPA with your Apple ID. Original Nyxian run/install needs this Apple ID login, a SideStore Anisette server, and the matching .p12 certificate saved here. Full on-device install/refresh also requires LocalDevVPN connected.")
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

            TextField("Apple ID email", text: $appleIDEmailInput)
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .listRowBackground(LitterTheme.surface.opacity(0.6))

            TextField("Team ID (optional)", text: $appleIDTeamIDInput)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .listRowBackground(LitterTheme.surface.opacity(0.6))

            Text("Leave Team ID blank for login. Litter can save the Apple ID first; the team is only needed after authentication when choosing a signing team, the same way SideStore/AltStore discover a Personal Team or paid developer team.")
                .litterFont(.caption)
                .foregroundStyle(LitterTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .listRowBackground(LitterTheme.surface.opacity(0.6))

            SecureField("Apple ID password or app-specific password", text: $appleIDPasswordInput)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .listRowBackground(LitterTheme.surface.opacity(0.6))

            TextField("Two-factor code", text: $appleIDTwoFactorCodeInput)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .listRowBackground(LitterTheme.surface.opacity(0.6))

            Picker("Anisette server", selection: $selectedAnisetteServerAddress) {
                ForEach(anisetteServers) { server in
                    Text(server.displayName).tag(server.address)
                }
                Text("Custom").tag(NyxianAnisetteServerDirectory.customSelectionID)
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            if selectedAnisetteServerAddress == NyxianAnisetteServerDirectory.customSelectionID {
                TextField("Custom Anisette server URL", text: $appleIDAnisetteURLInput)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
            }

            TextField("Anisette server list URL", text: $anisetteServerListURLInput)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .listRowBackground(LitterTheme.surface.opacity(0.6))

            Button {
                taskBag.run { await refreshAnisetteServers(showSuccess: true) }
            } label: {
                Label("Refresh Anisette Servers", systemImage: "arrow.clockwise.circle")
                    .foregroundStyle(LitterTheme.accent)
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            if let anisetteServerMessage, !anisetteServerMessage.isEmpty {
                Text(anisetteServerMessage)
                    .litterFont(.caption)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .textSelection(.enabled)
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
            }

            Button {
                taskBag.run { await saveNyxianAppleID() }
            } label: {
                Label("Login Apple ID", systemImage: "person.badge.key.fill")
                    .foregroundStyle(LitterTheme.accent)
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            Button(role: .destructive) {
                clearNyxianAppleID()
            } label: {
                Label("Clear Apple ID Login", systemImage: "person.crop.circle.badge.xmark")
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            if let appleIDActionMessage, !appleIDActionMessage.isEmpty {
                Text(appleIDActionMessage)
                    .litterFont(.caption)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .textSelection(.enabled)
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
            }

            SecureField("Certificate password", text: $certificatePasswordInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .listRowBackground(LitterTheme.surface.opacity(0.6))

            Button {
                showingCertificateImporter = true
            } label: {
                Label("Import SideStore Certificate", systemImage: "key")
                    .foregroundStyle(LitterTheme.accent)
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            Button(role: .destructive) {
                clearNyxianCertificate()
            } label: {
                Label("Clear Imported Certificate", systemImage: "trash")
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            if let certificateActionMessage, !certificateActionMessage.isEmpty {
                Text(certificateActionMessage)
                    .litterFont(.caption)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .textSelection(.enabled)
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
            }
        } header: {
            Text("Nyxian Signing")
                .foregroundStyle(LitterTheme.textSecondary)
        } footer: {
            Text("This does not sign CI release IPAs. It stores the certificate in the original Nyxian keys used by LCUtils for on-device run/install after the app has been signed by SideStore, AltStore, or another sideload signer.")
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
    private func handleCertificateImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try Data(contentsOf: url)
                let summary = try NyxianSigningCertificateValidator.validate(
                    pkcs12Data: data,
                    password: certificatePasswordInput,
                    checkRevocation: true
                )
                NyxianSigningCertificateStorage.save(
                    data: data,
                    password: certificatePasswordInput,
                    summary: summary
                )
                certificateActionMessage = summary.importMessage
                lastActionOutput = "Nyxian signing certificate validated and saved.\nSubject: \(summary.commonName)\nSHA256: \(summary.sha256Fingerprint)"
                taskBag.run { await refresh() }
            } catch {
                certificateActionMessage = "Certificate import failed: \(error.localizedDescription)"
                lastActionOutput = "Nyxian signing certificate import failed.\n\(error.localizedDescription)"
            }
        case .failure(let error):
            certificateActionMessage = "Certificate import failed: \(error.localizedDescription)"
        }
    }

    private var anisetteURLForLogin: String {
        if selectedAnisetteServerAddress == NyxianAnisetteServerDirectory.customSelectionID {
            return appleIDAnisetteURLInput
        }
        return selectedAnisetteServerAddress
    }

    @MainActor
    private func refreshAnisetteServers(showSuccess: Bool) async {
        do {
            let listURL = try NyxianAnisetteServerDirectory.normalizedListURL(anisetteServerListURLInput)
            anisetteServerListURLInput = listURL
            anisetteServers = try await NyxianAnisetteServerDirectory.fetchServers(listURL: listURL)
            syncAnisetteSelectionFromInput()
            if showSuccess {
                anisetteServerMessage = "Loaded \(anisetteServers.count) SideStore Anisette servers."
            }
        } catch {
            anisetteServers = NyxianAnisetteServerDirectory.fallbackServers
            syncAnisetteSelectionFromInput()
            anisetteServerMessage = "Could not refresh SideStore Anisette servers: \(error.localizedDescription). Using bundled defaults."
        }
    }

    @MainActor
    private func syncAnisetteSelectionFromInput() {
        let raw = appleIDAnisetteURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = raw.isEmpty ? NyxianAnisetteServerDirectory.defaultServerURL : raw
        if anisetteServers.contains(where: { $0.address == target }) {
            selectedAnisetteServerAddress = target
            appleIDAnisetteURLInput = target
        } else {
            selectedAnisetteServerAddress = NyxianAnisetteServerDirectory.customSelectionID
            appleIDAnisetteURLInput = target
        }
    }

    @MainActor
    private func saveNyxianAppleID() async {
        do {
            let anisetteURL = anisetteURLForLogin
            if KittyStoreSideStoreSigningBridge.isLinked {
                let result = await KittyStoreSideStoreSigningBridge.authenticate(
                    email: appleIDEmailInput,
                    password: appleIDPasswordInput,
                    requestedTeamID: appleIDTeamIDInput,
                    anisetteServerURL: anisetteURL,
                    twoFactorCode: appleIDTwoFactorCodeInput
                )
                let summary = try result.get()
                let account = try NyxianAppleIDStore.login(
                    email: summary.email,
                    password: appleIDPasswordInput,
                    teamID: summary.teamID,
                    anisetteServerURL: summary.anisetteServerURL
                )
                appleIDEmailInput = account.email
                appleIDTeamIDInput = summary.teamID
                appleIDAnisetteURLInput = summary.anisetteServerURL
                syncAnisetteSelectionFromInput()
                appleIDPasswordInput = ""
                appleIDTwoFactorCodeInput = ""
                appleIDActionMessage = "SideStore Apple ID login verified for \(summary.statusDetail). Teams found: \(summary.availableTeams.map(\.displayText).joined(separator: ", "))."
            } else {
                let account = try NyxianAppleIDStore.login(
                    email: appleIDEmailInput,
                    password: appleIDPasswordInput,
                    teamID: appleIDTeamIDInput,
                    anisetteServerURL: anisetteURL
                )
                appleIDEmailInput = account.email
                appleIDTeamIDInput = account.teamID
                appleIDAnisetteURLInput = account.anisetteServerURL ?? NyxianAnisetteServerDirectory.defaultServerURL
                syncAnisetteSelectionFromInput()
                appleIDPasswordInput = ""
                appleIDTwoFactorCodeInput = ""
                appleIDActionMessage = "Apple ID login saved locally, but SideStore AltSign is not linked in this build yet."
            }
            await refresh()
        } catch {
            appleIDActionMessage = "Apple ID login failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func clearNyxianAppleID() {
        do {
            try NyxianAppleIDStore.clear()
            appleIDEmailInput = ""
            appleIDTeamIDInput = ""
            appleIDPasswordInput = ""
            appleIDTwoFactorCodeInput = ""
            appleIDAnisetteURLInput = NyxianAnisetteServerDirectory.defaultServerURL
            selectedAnisetteServerAddress = NyxianAnisetteServerDirectory.defaultServerURL
            appleIDActionMessage = "Removed Apple ID login."
            taskBag.run { await refresh() }
        } catch {
            appleIDActionMessage = "Could not remove Apple ID login: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func clearNyxianCertificate() {
        NyxianSigningCertificateStorage.clear()
        certificatePasswordInput = ""
        certificateActionMessage = "Removed the imported Nyxian signing certificate."
        taskBag.run { await refresh() }
    }

    @MainActor
    private func refresh() async {
        isRefreshing = true
        status = await LitterBuildKit.shared.status()
        if let account = NyxianAppleIDStore.load(), appleIDEmailInput.isEmpty, appleIDTeamIDInput.isEmpty {
            appleIDEmailInput = account.email
            appleIDTeamIDInput = account.teamID
            appleIDAnisetteURLInput = account.anisetteServerURL ?? NyxianAnisetteServerDirectory.defaultServerURL
            syncAnisetteSelectionFromInput()
        }
        isRefreshing = false
    }
}
