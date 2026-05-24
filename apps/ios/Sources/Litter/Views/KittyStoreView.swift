import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct KittyStoreView: View {
    @Environment(\.openURL) private var openURL
    @StateObject private var updater = AppUpdateStore()
    @StateObject private var taskBag = ViewTaskBag()
    @State private var source: KittyStoreSource?
    @State private var sourcePhase: KittyStoreSourcePhase = .idle
    @State private var copiedMessage: String?
    @State private var shareItem: KittyStoreShareItem?
    @State private var selectedSection: KittyStoreSection = .featured
    @State private var buildKitStatus: LitterBuildKitStatus?
    @State private var selectedSigningMode: KittyStoreSigningMode = .certificate
    @State private var signingImportKind: KittyStoreImportKind = .ipa
    @State private var showingSigningImporter = false
    @State private var signingAlert: KittyStoreSigningAlert?
    @State private var importedIPA: KittyStoreImportedFile?
    @State private var importedProvisioningProfile: KittyStoreImportedFile?
    @State private var importedPairingFile: KittyStoreImportedFile?
    @State private var existingDylibs: [KittyStoreImportedFile] = []
    @State private var frameworksAndPlugins: [KittyStoreImportedFile] = []
    @State private var tweaks: [KittyStoreImportedFile] = []
    @State private var appNameOverride = ""
    @State private var bundleIdentifierOverride = ""
    @State private var appVersionOverride = ""
    @State private var entitlementsText = "{\n}\n"
    @State private var signingType: KittyStoreFeatherSigningType = .standard
    @State private var injectPath: KittyStoreInjectPath = .executable
    @State private var injectFolder: KittyStoreInjectFolder = .frameworks
    @State private var ppqProtection = true
    @State private var injectIntoExtensions = true
    @State private var fileSharing = false
    @State private var iTunesFileSharing = false
    @State private var proMotion = true
    @State private var gameMode = false
    @State private var iPadFullscreen = false
    @State private var removeURLScheme = false
    @State private var removeProvisioning = false
    @State private var installAfterSigning = true
    @State private var deleteAfterSigning = false
    @State private var replaceSubstrateWithElleKit = true
    @State private var enableLiquidGlass = false

    private var app: KittyStoreApp? { source?.apps.first }
    private var versions: [KittyStoreVersion] { app?.versions ?? [] }
    private var latestVersion: KittyStoreVersion? { versions.first }
    private var sourceURL: String { updater.latestManifest?.sideStoreSourceURL ?? updater.stableSourceURL }

    var body: some View {
        Group {
            if selectedSection == .sign {
                signingWorkspace
            } else {
                storeWorkspace
            }
        }
        .background(LitterTheme.backgroundGradient.ignoresSafeArea())
        .navigationTitle(selectedSection == .sign ? "Signing" : "KittyStore")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    taskBag.run { await refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(updater.phase.isBusy || sourcePhase.isBusy)
                .accessibilityLabel("Refresh KittyStore")
            }
        }
        .refreshable { await refreshAll() }
        .safeAreaInset(edge: .bottom) {
            if selectedSection == .sign {
                startSigningBar
            }
        }
        .fileImporter(
            isPresented: $showingSigningImporter,
            allowedContentTypes: signingImportKind.allowedContentTypes,
            allowsMultipleSelection: signingImportKind.allowsMultipleSelection
        ) { result in
            handleSigningImport(result)
        }
        .sheet(item: $shareItem) { item in
            KittyStoreActivityView(activityItems: [item.url])
        }
        .alert(item: $signingAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .task { await refreshAll() }
        .onDisappear {
            taskBag.cancelAll()
            if updater.phase.isBusy { updater.cancelDownload() }
        }
    }

    private var storeWorkspace: some View {
        ScrollView {
            VStack(spacing: 14) {
                heroPanel
                sectionPicker

                switch selectedSection {
                case .featured:
                    featuredPanel
                    installPanel
                case .versions:
                    versionHistoryPanel
                case .sign:
                    EmptyView()
                case .setup:
                    setupPanel
                    sourcePanel
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var signingWorkspace: some View {
        Form {
            Section {
                sectionPicker
            }
            .listRowBackground(LitterTheme.surface.opacity(0.62))

            signingCustomizationSection
            signingIdentitySection
            sideStoreTransportSection
            signingAdvancedSection

            Section {
                Color.clear.frame(height: 56)
            }
            .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
    }

    private var heroPanel: some View {
        panel {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LitterTheme.accent.opacity(0.18))
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(LitterTheme.accent)
                }
                .frame(width: 56, height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(LitterTheme.accent.opacity(0.38), lineWidth: 0.8)
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("KittyLitter Store")
                        .litterFont(.title3, weight: .bold)
                        .foregroundStyle(LitterTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(heroDetail)
                        .litterFont(.caption)
                        .foregroundStyle(LitterTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            metricGrid {
                metricItem("Installed", updater.installedVersion.displayString)
                metricItem("Latest", updater.latestManifest?.displayVersion ?? latestVersion?.version ?? "Unknown")
                metricItem("Versions", versions.isEmpty ? "Unknown" : "\(versions.count)")
                if let size = updater.latestManifest?.size ?? latestVersion?.size, size > 0 {
                    metricItem("IPA Size", LitterDownloadSupport.formatBytes(size))
                }
            }
        }
    }

    private var sectionPicker: some View {
        Picker("KittyStore section", selection: $selectedSection) {
            ForEach(KittyStoreSection.allCases) { section in
                Text(section.title).tag(section)
            }
        }
        .pickerStyle(.segmented)
    }

    private var featuredPanel: some View {
        panel(title: "Featured Build", icon: "sparkles") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    statusPill(updater.availability.title, color: availabilityColor)
                    if updater.phase.isBusy || sourcePhase.isBusy {
                        statusPill("Refreshing", color: LitterTheme.warning)
                    }
                    Spacer(minLength: 0)
                }

                Text(updater.statusMessage)
                    .litterFont(.caption)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let notes = updater.latestManifest?.releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                    Text(shortNotes(notes))
                        .litterMonoFont(size: 11, weight: .regular)
                        .foregroundStyle(LitterTheme.textSecondary)
                        .textSelection(.enabled)
                        .lineLimit(12)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LitterTheme.surfaceLight.opacity(0.3), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else if let latestVersion {
                    Text(latestVersion.cleanedDescription)
                        .litterMonoFont(size: 11, weight: .regular)
                        .foregroundStyle(LitterTheme.textSecondary)
                        .textSelection(.enabled)
                        .lineLimit(12)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LitterTheme.surfaceLight.opacity(0.3), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    emptyState(sourcePhase.message)
                }
            }
        }
    }

    private var installPanel: some View {
        panel(title: "Install", icon: "square.and.arrow.down") {
            VStack(spacing: 10) {
                if let url = updater.sideStoreInstallURL {
                    actionRow("Install Latest", detail: "Open the newest IPA in SideStore", icon: "square.and.arrow.down") { openURL(url) }
                }

                if let url = updater.altStoreInstallURL {
                    actionRow("Install with AltStore", detail: "Open the newest IPA in AltStore", icon: "square.and.arrow.down.on.square") { openURL(url) }
                }

                Button {
                    updater.downloadUpdate()
                } label: {
                    actionRowLabel(downloadTitle, detail: updater.progressText, icon: downloadIcon, enabled: updater.canDownload)
                }
                .buttonStyle(.plain)
                .disabled(!updater.canDownload)

                if updater.phase == .downloading || updater.phase == .verifying {
                    ProgressView(value: updater.downloadProgress)
                        .tint(LitterTheme.accent)
                    if !updater.speedText.isEmpty {
                        Text(updater.speedText)
                            .litterMonoFont(size: 11, weight: .regular)
                            .foregroundStyle(LitterTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let downloadedURL = updater.downloadedIPAURL {
                    actionRow("Share Downloaded IPA", detail: updater.canInstallDownloadedIPA ? updater.checksumText : "Waiting for checksum verification", icon: "square.and.arrow.up", enabled: updater.canInstallDownloadedIPA) {
                        shareItem = KittyStoreShareItem(url: downloadedURL)
                    }
                }

                if let remote = updater.remoteIPAURL {
                    actionRow("Copy IPA Link", detail: remote.host ?? "Release asset", icon: "doc.on.doc") {
                        UIPasteboard.general.string = remote.absoluteString
                        copiedMessage = "Copied IPA link"
                    }
                }

                if let releaseURL = updater.releaseURL {
                    actionRow("Open Release", detail: releaseURL.host ?? "GitHub Releases", icon: "safari") { openURL(releaseURL) }
                }

                copiedNotice
            }
        }
    }

    private var versionHistoryPanel: some View {
        panel(title: "Version History", icon: "clock.arrow.circlepath") {
            VStack(spacing: 10) {
                if versions.isEmpty {
                    emptyState(sourcePhase.message)
                } else {
                    ForEach(versions) { version in
                        versionRow(version)
                    }
                }
            }
        }
    }

    private var setupPanel: some View {
        panel(title: "Setup", icon: "checklist") {
            VStack(spacing: 10) {
                readinessRow("Unsigned IPA source", detail: "KittyStore reads the same AltStore/SideStore source that release CI publishes.", state: source != nil)
                readinessRow("Version history", detail: versions.isEmpty ? "Refresh the source to load historical IPA versions." : "\(versions.count) installable IPA versions are listed.", state: !versions.isEmpty)
                readinessRow("SideStore install", detail: "Uses sidestore:// links; SideStore signs and installs the IPA.", state: updater.sideStoreInstallURL != nil)
                readinessRow("LocalDevVPN", detail: buildKitStatus?.localDevVPNDetail ?? "Required for SideStore-style on-device install and refresh.", state: buildKitStatus?.localDevVPNConnected)
            }
        }
    }

    private var sourcePanel: some View {
        panel(title: "Source", icon: "link") {
            VStack(spacing: 10) {
                actionRow("Add KittyStore Source", detail: "Subscribe in SideStore", icon: "link.badge.plus") {
                    if let url = installerURL(scheme: "sidestore", host: "source", targetURL: sourceURL) { openURL(url) }
                }

                actionRow("Add in AltStore", detail: "Use the same compatible source", icon: "link.badge.plus") {
                    if let url = installerURL(scheme: "altstore", host: "source", targetURL: sourceURL) { openURL(url) }
                }

                actionRow("Copy Source URL", detail: sourceHost, icon: "doc.on.doc") {
                    UIPasteboard.general.string = sourceURL
                    copiedMessage = "Copied source URL"
                }

                if let url = URL(string: sourceURL) {
                    actionRow("Open Source JSON", detail: url.host ?? "Source feed", icon: "safari") { openURL(url) }
                }

                copiedNotice
            }
        }
    }

    private var signingCustomizationSection: some View {
        Section {
            Button {
                presentImporter(.ipa)
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LitterTheme.accent.opacity(0.16))
                        Image(systemName: importedIPA == nil ? "shippingbox" : "app.dashed")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(LitterTheme.accent)
                    }
                    .frame(width: 58, height: 58)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(LitterTheme.border.opacity(0.45), lineWidth: 0.8)
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(importedIPA == nil ? "Import IPA" : importedIPAName)
                            .litterFont(.subheadline, weight: .semibold)
                            .foregroundStyle(LitterTheme.textPrimary)
                        Text(importedIPA?.detail ?? "Choose the IPA you want KittyStore to sign.")
                            .litterFont(.caption)
                            .foregroundStyle(LitterTheme.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(LitterTheme.textMuted)
                }
            }
            .buttonStyle(.plain)

            signingInfoLink("Name", value: displayedAppName) {
                KittyStoreTextEditorView(title: "Name", text: $appNameOverride, placeholder: app?.name ?? importedIPAName)
            }
            signingInfoLink("Identifier", value: displayedBundleIdentifier) {
                KittyStoreTextEditorView(title: "Identifier", text: $bundleIdentifierOverride, placeholder: app?.bundleIdentifier ?? "com.example.app")
            }
            signingInfoLink("Version", value: displayedVersion) {
                KittyStoreTextEditorView(title: "Version", text: $appVersionOverride, placeholder: latestVersion?.version ?? updater.latestManifest?.displayVersion ?? "1.0")
            }
        } header: {
            Text("Customization")
        }
        .listRowBackground(LitterTheme.surface.opacity(0.62))
    }

    private var signingIdentitySection: some View {
        Section {
            Picker("Signing Mode", selection: $selectedSigningMode) {
                ForEach(KittyStoreSigningMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Picker("Signing Type", selection: $signingType) {
                ForEach(KittyStoreFeatherSigningType.allCases) { value in
                    Text(value.title).tag(value)
                }
            }

            NavigationLink {
                BuildKitSettingsView()
            } label: {
                LabeledContent("Certificate") {
                    Text(buildKitStatus?.nyxianSigningCertificateInstalled == true ? "Validated" : "No Certificate")
                        .foregroundStyle(buildKitStatus?.nyxianSigningCertificateInstalled == true ? LitterTheme.success : LitterTheme.warning)
                }
            }

            Button {
                presentImporter(.provisioningProfile)
            } label: {
                LabeledContent("Provisioning Profile") {
                    Text(importedProvisioningProfile?.displayName ?? profileFallbackTitle)
                        .foregroundStyle(importedProvisioningProfile == nil ? LitterTheme.textSecondary : LitterTheme.textPrimary)
                }
            }
            .buttonStyle(.plain)

            if let detail = buildKitStatus?.nyxianSigningCertificateDetail, !detail.isEmpty {
                Text(detail)
                    .litterFont(.caption)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Signing")
        } footer: {
            Text("Certificate signing follows Feather's flow. Certificate validation, bad password detection, private key checks, profile matching, and revocation checks are handled in BuildKit settings before a certificate is treated as usable.")
        }
        .listRowBackground(LitterTheme.surface.opacity(0.62))
    }

    private var sideStoreTransportSection: some View {
        Section {
            NavigationLink {
                BuildKitSettingsView()
            } label: {
                LabeledContent("Apple ID") {
                    Text(buildKitStatus?.appleIDConfigured == true ? "Logged In" : "Missing")
                        .foregroundStyle(buildKitStatus?.appleIDConfigured == true ? LitterTheme.success : LitterTheme.warning)
                }
            }

            Button {
                presentImporter(.pairingFile)
            } label: {
                LabeledContent("Pairing File") {
                    Text(importedPairingFile?.displayName ?? "Not Imported")
                        .foregroundStyle(importedPairingFile == nil ? LitterTheme.textSecondary : LitterTheme.textPrimary)
                }
            }
            .buttonStyle(.plain)

            LabeledContent("LocalDevVPN") {
                Text(buildKitStatus?.localDevVPNConnected == true ? "Connected" : "Not Detected")
                    .foregroundStyle(buildKitStatus?.localDevVPNConnected == true ? LitterTheme.success : LitterTheme.warning)
            }

            if let detail = buildKitStatus?.appleIDDetail, !detail.isEmpty {
                Text(detail)
                    .litterFont(.caption)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .textSelection(.enabled)
            }
            if let detail = buildKitStatus?.localDevVPNDetail, !detail.isEmpty {
                Text(detail)
                    .litterFont(.caption)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .textSelection(.enabled)
            }
        } header: {
            Text("SideStore Install")
        } footer: {
            Text("Apple ID, SideStore Anisette, pairing file, and LocalDevVPN are the SideStore-style path for direct on-device install and refresh. They are separate from Feather-style certificate signing.")
        }
        .listRowBackground(LitterTheme.surface.opacity(0.62))
    }

    private var signingAdvancedSection: some View {
        Section {
            DisclosureGroup("Modify") {
                NavigationLink("Existing Dylibs") {
                    KittyStoreFilesListView(
                        title: "Existing Dylibs",
                        files: $existingDylibs,
                        importKind: .existingDylibs,
                        currentImportKind: $signingImportKind,
                        showingImporter: $showingSigningImporter,
                        emptyMessage: "Import dylibs to track removals or replacement targets before signing."
                    )
                }

                NavigationLink("Frameworks & PlugIns") {
                    KittyStoreFilesListView(
                        title: "Frameworks & PlugIns",
                        files: $frameworksAndPlugins,
                        importKind: .frameworksAndPlugins,
                        currentImportKind: $signingImportKind,
                        showingImporter: $showingSigningImporter,
                        emptyMessage: "Import .framework, .appex, .dylib, or plugin folders to include in the signing plan."
                    )
                }

                NavigationLink("Entitlements (BETA)") {
                    KittyStoreCodeEditorView(title: "Entitlements", text: $entitlementsText)
                }

                NavigationLink("Tweaks") {
                    KittyStoreFilesListView(
                        title: "Tweaks",
                        files: $tweaks,
                        importKind: .tweaks,
                        currentImportKind: $signingImportKind,
                        showingImporter: $showingSigningImporter,
                        emptyMessage: "Import .deb, .dylib, or tweak bundles to inject during signing."
                    )
                }
            }

            NavigationLink("Properties") {
                KittyStoreSigningPropertiesView(
                    signingType: $signingType,
                    injectPath: $injectPath,
                    injectFolder: $injectFolder,
                    ppqProtection: $ppqProtection,
                    injectIntoExtensions: $injectIntoExtensions,
                    fileSharing: $fileSharing,
                    iTunesFileSharing: $iTunesFileSharing,
                    proMotion: $proMotion,
                    gameMode: $gameMode,
                    iPadFullscreen: $iPadFullscreen,
                    removeURLScheme: $removeURLScheme,
                    removeProvisioning: $removeProvisioning,
                    installAfterSigning: $installAfterSigning,
                    deleteAfterSigning: $deleteAfterSigning,
                    replaceSubstrateWithElleKit: $replaceSubstrateWithElleKit,
                    enableLiquidGlass: $enableLiquidGlass
                )
            }
        } header: {
            Text("Advanced")
        }
        .listRowBackground(LitterTheme.surface.opacity(0.62))
    }

    private var startSigningBar: some View {
        VStack(spacing: 8) {
            if let signingReadinessMessage {
                Text(signingReadinessMessage)
                    .litterFont(.caption)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            Button {
                startSigning()
            } label: {
                Text("Start Signing")
                    .litterFont(.headline, weight: .semibold)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(LitterTheme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .padding(.top, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var copiedNotice: some View {
        if let copiedMessage {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                Text(copiedMessage)
            }
            .litterFont(.caption, weight: .semibold)
            .foregroundStyle(LitterTheme.success)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var heroDetail: String {
        if let app {
            return app.subtitle ?? app.localizedDescription ?? "KittyStore is the KittyLitter-branded source for Litter sideload builds."
        }
        return "KittyStore is the KittyLitter-branded source for Litter sideload builds, compatible with SideStore and AltStore."
    }

    private var sourceHost: String {
        URL(string: sourceURL)?.host ?? "KittyStore source"
    }

    private var importedIPAName: String {
        importedIPA?.displayName ?? latestVersion.map { "Litter \($0.version ?? "IPA")" } ?? "Imported IPA"
    }

    private var displayedAppName: String {
        let trimmed = appNameOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return app?.name ?? importedIPA?.nameWithoutExtension ?? "No IPA"
    }

    private var displayedBundleIdentifier: String {
        let trimmed = bundleIdentifierOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return app?.bundleIdentifier ?? "Import an IPA"
    }

    private var displayedVersion: String {
        let trimmed = appVersionOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return latestVersion?.version ?? updater.latestManifest?.displayVersion ?? "Unknown"
    }

    private var profileFallbackTitle: String {
        buildKitStatus?.embeddedProvisionPresent == true ? "Use Embedded Profile" : "Not Imported"
    }

    private var signingReadinessMessage: String? {
        guard importedIPA != nil else { return "Import an IPA before signing." }
        switch selectedSigningMode {
        case .certificate:
            if buildKitStatus?.nyxianSigningCertificateInstalled != true { return "Import a valid certificate in BuildKit settings." }
            return "Feather-style certificate signing plan is ready to hand to the native signer."
        case .appleID:
            if buildKitStatus?.appleIDConfigured != true { return "Add Apple ID login in BuildKit settings." }
            if importedPairingFile == nil { return "Import the iOS pairing file for SideStore-style install." }
            if buildKitStatus?.localDevVPNConnected != true { return "Connect LocalDevVPN for direct install and refresh." }
            return "SideStore-style install and refresh inputs are ready."
        }
    }

    private var availabilityColor: Color {
        switch updater.availability {
        case .available: return LitterTheme.accent
        case .upToDate: return LitterTheme.success
        case .incompatibleIOS, .incomparable, .noCompatibleRelease: return LitterTheme.warning
        case .remoteOlder, .unknown: return LitterTheme.textSecondary
        }
    }

    private var downloadTitle: String {
        switch updater.phase {
        case .downloading: return "Downloading IPA"
        case .verifying: return "Verifying IPA"
        case .downloaded: return "Downloaded"
        case .failed: return "Retry Download"
        default: return updater.canDownload ? "Download IPA" : "Download IPA"
        }
    }

    private var downloadIcon: String {
        switch updater.phase {
        case .downloading, .verifying: return "hourglass"
        case .downloaded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.arrow.circlepath"
        default: return "arrow.down.circle.fill"
        }
    }

    private func refreshAll() async {
        await updater.checkForUpdates()
        await refreshSource()
        await refreshBuildKitStatus()
    }

    private func refreshSource() async {
        guard let url = URL(string: sourceURL) else {
            sourcePhase = .failed("Invalid KittyStore source URL.")
            return
        }
        sourcePhase = .loading
        do {
            let data = try await GitHubReleaseAPI.data(url: url)
            source = try JSONDecoder().decode(KittyStoreSource.self, from: data)
            sourcePhase = .loaded
        } catch {
            sourcePhase = .failed(error.localizedDescription)
        }
    }

    @MainActor
    private func refreshBuildKitStatus() async {
        buildKitStatus = await LitterBuildKit.shared.status(checkRevocation: true)
    }

    @MainActor
    private func presentImporter(_ kind: KittyStoreImportKind) {
        signingImportKind = kind
        showingSigningImporter = true
    }

    @MainActor
    private func handleSigningImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            do {
                let stagedFiles = try urls.map { try stageImportedFile($0, kind: signingImportKind) }
                applyImportedFiles(stagedFiles, kind: signingImportKind)
            } catch {
                signingAlert = KittyStoreSigningAlert(title: "Import Failed", message: error.localizedDescription)
            }
        case .failure(let error):
            signingAlert = KittyStoreSigningAlert(title: "Import Failed", message: error.localizedDescription)
        }
    }

    @MainActor
    private func applyImportedFiles(_ files: [KittyStoreImportedFile], kind: KittyStoreImportKind) {
        guard !files.isEmpty else { return }
        switch kind {
        case .ipa:
            importedIPA = files.first
            if appNameOverride.isEmpty, let name = files.first?.nameWithoutExtension { appNameOverride = name }
        case .provisioningProfile:
            importedProvisioningProfile = files.first
        case .pairingFile:
            importedPairingFile = files.first
        case .existingDylibs:
            existingDylibs.append(contentsOf: files)
        case .frameworksAndPlugins:
            frameworksAndPlugins.append(contentsOf: files)
        case .tweaks:
            tweaks.append(contentsOf: files)
        }
    }

    private func stageImportedFile(_ url: URL, kind: KittyStoreImportKind) throws -> KittyStoreImportedFile {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        let isDirectory = resourceValues.isDirectory ?? false
        let directory = try LitterDownloadSupport.appSupportDirectory(named: "KittyStoreImports")
        let destinationName = "\(kind.rawValue)-\(UUID().uuidString)-\(sanitizeFileName(url.lastPathComponent))"
        let destination = directory.appendingPathComponent(destinationName, isDirectory: isDirectory)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: url, to: destination)
        let copiedValues = try? destination.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        let size = copiedValues?.isDirectory == true ? nil : copiedValues?.fileSize.map(Int64.init)
        return KittyStoreImportedFile(
            displayName: url.lastPathComponent.isEmpty ? kind.title : url.lastPathComponent,
            stagedPath: destination.path,
            size: size,
            isDirectory: isDirectory
        )
    }

    private func sanitizeFileName(_ value: String) -> String {
        let fallback = "Imported"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let sanitized = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "-"
        }.joined()
        let result = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return result.isEmpty ? fallback : result
    }

    @MainActor
    private func startSigning() {
        guard importedIPA != nil else {
            signingAlert = KittyStoreSigningAlert(title: "No IPA", message: "Import an IPA before starting the Feather-style signing flow.")
            return
        }

        switch selectedSigningMode {
        case .certificate:
            guard buildKitStatus?.nyxianSigningCertificateInstalled == true else {
                signingAlert = KittyStoreSigningAlert(title: "No Certificate", message: "Import and validate a .p12 certificate in BuildKit settings first. Bad passwords, missing private keys, revoked certs, and profile mismatches stay blocked there.")
                return
            }
        case .appleID:
            guard buildKitStatus?.appleIDConfigured == true else {
                signingAlert = KittyStoreSigningAlert(title: "Apple ID Missing", message: "Save the Apple ID, Team ID, password, and Anisette server in BuildKit settings first.")
                return
            }
            guard importedPairingFile != nil else {
                signingAlert = KittyStoreSigningAlert(title: "Pairing File Missing", message: "Import the SideStore-style iOS pairing file before direct install or refresh.")
                return
            }
            guard buildKitStatus?.localDevVPNConnected == true else {
                signingAlert = KittyStoreSigningAlert(title: "LocalDevVPN Missing", message: "Connect LocalDevVPN before using SideStore-style on-device install or refresh.")
                return
            }
        }

        UIPasteboard.general.string = signingPlanJSON()
        signingAlert = KittyStoreSigningAlert(
            title: "Signing Plan Ready",
            message: "KittyStore copied a Feather/SideStore-compatible signing plan. The native signer still needs the Feather Zsign path and SideStore install bridge wired before this button can produce and install the final IPA."
        )
    }

    private func signingPlanJSON() -> String {
        let payload: [String: Any] = [
            "mode": selectedSigningMode.rawValue,
            "app": [
                "name": displayedAppName,
                "bundleIdentifier": displayedBundleIdentifier,
                "version": displayedVersion,
                "ipa": importedIPA?.stagedPath ?? ""
            ],
            "signing": [
                "type": signingType.rawValue,
                "certificateReady": buildKitStatus?.nyxianSigningCertificateInstalled == true,
                "provisioningProfile": importedProvisioningProfile?.stagedPath ?? "embedded",
                "appleIDReady": buildKitStatus?.appleIDConfigured == true,
                "pairingFile": importedPairingFile?.stagedPath ?? "",
                "localDevVPNReady": buildKitStatus?.localDevVPNConnected == true
            ],
            "modify": [
                "existingDylibs": existingDylibs.map(\.stagedPath),
                "frameworksAndPlugins": frameworksAndPlugins.map(\.stagedPath),
                "tweaks": tweaks.map(\.stagedPath),
                "entitlements": entitlementsText
            ],
            "properties": [
                "injectPath": injectPath.rawValue,
                "injectFolder": injectFolder.rawValue,
                "ppqProtection": ppqProtection,
                "injectIntoExtensions": injectIntoExtensions,
                "fileSharing": fileSharing,
                "iTunesFileSharing": iTunesFileSharing,
                "proMotion": proMotion,
                "gameMode": gameMode,
                "iPadFullscreen": iPadFullscreen,
                "removeURLScheme": removeURLScheme,
                "removeProvisioning": removeProvisioning,
                "installAfterSigning": installAfterSigning,
                "deleteAfterSigning": deleteAfterSigning,
                "replaceSubstrateWithElleKit": replaceSubstrateWithElleKit,
                "enableLiquidGlass": enableLiquidGlass
            ]
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }

    private func signingInfoLink<V: View>(_ title: String, value: String, @ViewBuilder destination: () -> V) -> some View {
        NavigationLink {
            destination()
        } label: {
            LabeledContent(title) {
                Text(value)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
    }

    private func versionRow(_ version: KittyStoreVersion) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Litter \(version.version ?? "Unknown")")
                    .litterFont(.subheadline, weight: .semibold)
                    .foregroundStyle(LitterTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 8)
                Text("Build \(version.buildVersion ?? "0")")
                    .litterMonoFont(size: 11, weight: .semibold)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                if let date = version.displayDate {
                    statusPill(date, color: LitterTheme.textSecondary)
                }
                if let size = version.size, size > 0 {
                    statusPill(LitterDownloadSupport.formatBytes(size), color: LitterTheme.textSecondary)
                }
                if let minOS = version.minOSVersion, !minOS.isEmpty {
                    statusPill("iOS \(minOS)+", color: LitterTheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !version.cleanedDescription.isEmpty {
                Text(shortNotes(version.cleanedDescription))
                    .litterFont(.caption)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if let sideStoreURL = installerURL(scheme: "sidestore", host: "install", targetURL: version.downloadURL) {
                    compactButton("SideStore", icon: "square.and.arrow.down") { openURL(sideStoreURL) }
                }
                if let altStoreURL = installerURL(scheme: "altstore", host: "install", targetURL: version.downloadURL) {
                    compactButton("AltStore", icon: "square.and.arrow.down.on.square") { openURL(altStoreURL) }
                }
                compactButton("Copy", icon: "doc.on.doc") {
                    UIPasteboard.general.string = version.downloadURL
                    copiedMessage = "Copied Litter \(version.version ?? "IPA") link"
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LitterTheme.surfaceLight.opacity(0.34), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func readinessRow(_ title: String, detail: String, state: Bool?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: readinessIcon(for: state))
                .foregroundStyle(readinessColor(for: state))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .litterFont(.subheadline, weight: .semibold)
                    .foregroundStyle(LitterTheme.textPrimary)
                Text(detail)
                    .litterFont(.caption)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(LitterTheme.surfaceLight.opacity(0.3), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func readinessIcon(for state: Bool?) -> String {
        guard let state else { return "info.circle.fill" }
        return state ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private func readinessColor(for state: Bool?) -> Color {
        guard let state else { return LitterTheme.accent }
        return state ? LitterTheme.success : LitterTheme.warning
    }

    private func panel<Content: View>(title: String? = nil, icon: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title, let icon {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .foregroundStyle(LitterTheme.accent)
                        .frame(width: 18)
                    Text(title)
                        .litterFont(.caption, weight: .semibold)
                        .foregroundStyle(LitterTheme.textSecondary)
                        .textCase(.uppercase)
                    Spacer(minLength: 0)
                }
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LitterTheme.surface.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(LitterTheme.border.opacity(0.55), lineWidth: 0.8)
        )
    }

    private func metricGrid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
            content()
        }
    }

    private func metricItem(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .litterFont(size: 10, weight: .semibold)
                .foregroundStyle(LitterTheme.textMuted)
                .lineLimit(1)
            Text(value)
                .litterMonoFont(size: 12, weight: .semibold)
                .foregroundStyle(LitterTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(LitterTheme.surfaceLight.opacity(0.36), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func statusPill(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .litterFont(.caption, weight: .semibold)
                .foregroundStyle(LitterTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(color.opacity(0.14), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 0.7))
    }

    private func actionRow(_ title: String, detail: String, icon: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionRowLabel(title, detail: detail, icon: icon, enabled: enabled)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func actionRowLabel(_ title: String, detail: String, icon: String, enabled: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(enabled ? LitterTheme.accent : LitterTheme.textMuted)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .litterFont(.subheadline, weight: .semibold)
                    .foregroundStyle(enabled ? LitterTheme.textPrimary : LitterTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .litterFont(.caption)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .litterFont(.caption, weight: .semibold)
                .foregroundStyle(LitterTheme.textMuted)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LitterTheme.surfaceLight.opacity(enabled ? 0.38 : 0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func compactButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .litterFont(.caption, weight: .semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(LitterTheme.accent)
        .background(LitterTheme.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .litterFont(.caption)
            .foregroundStyle(LitterTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(LitterTheme.surfaceLight.opacity(0.28), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func installerURL(scheme: String, host: String, targetURL: String?) -> URL? {
        guard let targetURL, !targetURL.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: "url", value: targetURL)]
        return components.url
    }

    private func shortNotes(_ notes: String) -> String {
        let lines = notes
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        return lines.prefix(18).joined(separator: "\n")
    }
}

private enum KittyStoreSection: String, CaseIterable, Identifiable {
    case featured
    case versions
    case sign
    case setup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .featured: return "Store"
        case .versions: return "Versions"
        case .sign: return "Sign"
        case .setup: return "Setup"
        }
    }

    var systemImage: String {
        switch self {
        case .featured: return "sparkles"
        case .versions: return "clock.arrow.circlepath"
        case .sign: return "signature"
        case .setup: return "checklist"
        }
    }
}

private enum KittyStoreSigningMode: String, CaseIterable, Identifiable {
    case certificate
    case appleID

    var id: String { rawValue }

    var title: String {
        switch self {
        case .certificate: return "Certificate"
        case .appleID: return "Apple ID"
        }
    }
}

private enum KittyStoreFeatherSigningType: String, CaseIterable, Identifiable {
    case standard = "default"
    case adhoc
    case force

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Default"
        case .adhoc: return "Ad Hoc"
        case .force: return "Force"
        }
    }
}

private enum KittyStoreInjectPath: String, CaseIterable, Identifiable {
    case executable = "@executable_path"
    case rpath = "@rpath"
    case frameworks = "/Frameworks/"

    var id: String { rawValue }
    var title: String { rawValue }
}

private enum KittyStoreInjectFolder: String, CaseIterable, Identifiable {
    case frameworks = "Frameworks"
    case plugins = "PlugIns"
    case root = "Root"

    var id: String { rawValue }
    var title: String { rawValue }
}

private enum KittyStoreImportKind: String {
    case ipa
    case provisioningProfile
    case pairingFile
    case existingDylibs
    case frameworksAndPlugins
    case tweaks

    var title: String {
        switch self {
        case .ipa: return "IPA"
        case .provisioningProfile: return "Provisioning Profile"
        case .pairingFile: return "Pairing File"
        case .existingDylibs: return "Existing Dylibs"
        case .frameworksAndPlugins: return "Frameworks & PlugIns"
        case .tweaks: return "Tweaks"
        }
    }

    var allowsMultipleSelection: Bool {
        switch self {
        case .ipa, .provisioningProfile, .pairingFile: return false
        case .existingDylibs, .frameworksAndPlugins, .tweaks: return true
        }
    }

    var allowedContentTypes: [UTType] {
        switch self {
        case .ipa:
            return [UTType(filenameExtension: "ipa") ?? .data, .zip, .data]
        case .provisioningProfile:
            return [UTType(filenameExtension: "mobileprovision") ?? .data, .propertyList, .data]
        case .pairingFile:
            return [UTType(filenameExtension: "mobiledevicepairing") ?? .data, .propertyList, .data]
        case .existingDylibs:
            return [UTType(filenameExtension: "dylib") ?? .data, .data]
        case .frameworksAndPlugins:
            return [.folder, UTType(filenameExtension: "framework") ?? .data, UTType(filenameExtension: "appex") ?? .data, UTType(filenameExtension: "dylib") ?? .data, .zip, .data]
        case .tweaks:
            return [UTType(filenameExtension: "deb") ?? .data, UTType(filenameExtension: "dylib") ?? .data, .folder, .zip, .data]
        }
    }
}

private struct KittyStoreImportedFile: Identifiable, Equatable {
    let id = UUID()
    var displayName: String
    var stagedPath: String
    var size: Int64?
    var isDirectory: Bool

    var nameWithoutExtension: String {
        (displayName as NSString).deletingPathExtension
    }

    var detail: String {
        if isDirectory { return stagedPath }
        if let size { return "\(LitterDownloadSupport.formatBytes(size)) - \(stagedPath)" }
        return stagedPath
    }
}

private struct KittyStoreSigningAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

private enum KittyStoreSourcePhase: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)

    var isBusy: Bool {
        if case .loading = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .idle: return "KittyStore has not loaded the source yet."
        case .loading: return "Loading KittyStore source."
        case .loaded: return "KittyStore source loaded."
        case .failed(let message): return "Could not load KittyStore source: \(message)"
        }
    }
}

private struct KittyStoreSource: Decodable, Equatable {
    var name: String?
    var identifier: String?
    var sourceURL: String?
    var subtitle: String?
    var description: String?
    var iconURL: String?
    var developerName: String?
    var apps: [KittyStoreApp]
}

private struct KittyStoreApp: Decodable, Equatable {
    var name: String
    var bundleIdentifier: String
    var developerName: String?
    var iconURL: String?
    var subtitle: String?
    var localizedDescription: String?
    var versions: [KittyStoreVersion]
}

private struct KittyStoreVersion: Decodable, Equatable, Identifiable {
    var version: String?
    var buildVersion: String?
    var date: String?
    var localizedDescription: String?
    var downloadURL: String
    var size: Int64?
    var minOSVersion: String?

    var id: String { "\(version ?? "unknown")-\(buildVersion ?? "0")-\(downloadURL)" }

    var cleanedDescription: String {
        localizedDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var displayDate: String? {
        guard let date, !date.isEmpty else { return nil }
        return String(date.prefix(10))
    }
}

private struct KittyStoreShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct KittyStoreActivityView: UIViewControllerRepresentable {
    var activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct KittyStoreTextEditorView: View {
    var title: String
    @Binding var text: String
    var placeholder: String

    var body: some View {
        Form {
            Section {
                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(LitterTheme.backgroundGradient.ignoresSafeArea())
    }
}

private struct KittyStoreCodeEditorView: View {
    var title: String
    @Binding var text: String

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 280)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(LitterTheme.backgroundGradient.ignoresSafeArea())
    }
}

private struct KittyStoreFilesListView: View {
    var title: String
    @Binding var files: [KittyStoreImportedFile]
    var importKind: KittyStoreImportKind
    @Binding var currentImportKind: KittyStoreImportKind
    @Binding var showingImporter: Bool
    var emptyMessage: String

    var body: some View {
        Form {
            Section {
                Button {
                    currentImportKind = importKind
                    showingImporter = true
                } label: {
                    Label("Import", systemImage: "plus.circle")
                }
            }

            Section {
                if files.isEmpty {
                    Text(emptyMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(files) { file in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text(file.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .onDelete { offsets in
                        files.remove(atOffsets: offsets)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(LitterTheme.backgroundGradient.ignoresSafeArea())
    }
}

private struct KittyStoreSigningPropertiesView: View {
    @Binding var signingType: KittyStoreFeatherSigningType
    @Binding var injectPath: KittyStoreInjectPath
    @Binding var injectFolder: KittyStoreInjectFolder
    @Binding var ppqProtection: Bool
    @Binding var injectIntoExtensions: Bool
    @Binding var fileSharing: Bool
    @Binding var iTunesFileSharing: Bool
    @Binding var proMotion: Bool
    @Binding var gameMode: Bool
    @Binding var iPadFullscreen: Bool
    @Binding var removeURLScheme: Bool
    @Binding var removeProvisioning: Bool
    @Binding var installAfterSigning: Bool
    @Binding var deleteAfterSigning: Bool
    @Binding var replaceSubstrateWithElleKit: Bool
    @Binding var enableLiquidGlass: Bool

    var body: some View {
        Form {
            Section("Protection") {
                Toggle("PPQ Protection", isOn: $ppqProtection)
            }

            Section("General") {
                Picker("Signing Type", selection: $signingType) {
                    ForEach(KittyStoreFeatherSigningType.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
            }

            Section("Tweaks") {
                Picker("Injection Path", selection: $injectPath) {
                    ForEach(KittyStoreInjectPath.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                Picker("Injection Folder", selection: $injectFolder) {
                    ForEach(KittyStoreInjectFolder.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                Toggle("Inject into Extensions", isOn: $injectIntoExtensions)
            }

            Section("App Features") {
                Toggle("File Sharing", isOn: $fileSharing)
                Toggle("iTunes File Sharing", isOn: $iTunesFileSharing)
                Toggle("Pro Motion", isOn: $proMotion)
                Toggle("Game Mode", isOn: $gameMode)
                Toggle("iPad Fullscreen", isOn: $iPadFullscreen)
            }

            Section("Removal") {
                Toggle("Remove URL Scheme", isOn: $removeURLScheme)
                Toggle("Remove Provisioning", isOn: $removeProvisioning)
            }

            Section("Post Signing") {
                Toggle("Install After Signing", isOn: $installAfterSigning)
                Toggle("Delete After Signing", isOn: $deleteAfterSigning)
            }

            Section("Experiments") {
                Toggle("Replace Substrate with ElleKit", isOn: $replaceSubstrateWithElleKit)
                Toggle("Enable Liquid Glass", isOn: $enableLiquidGlass)
            }
        }
        .navigationTitle("Properties")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(LitterTheme.backgroundGradient.ignoresSafeArea())
    }
}
