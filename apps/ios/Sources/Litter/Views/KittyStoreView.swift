import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct KittyStoreView: View {
    @Environment(\.openURL) private var openURL
    @StateObject private var taskBag = ViewTaskBag()
    @State private var source: KittyStoreSource?
    @State private var sourcePhase: KittyStoreSourcePhase = .idle
    @State private var copiedMessage: String?
    @State private var shareItem: KittyStoreShareItem?
    @State private var selectedTab: KittyStoreTab = .browse
    @State private var selectedSourceAppID: String?
    @State private var showingSigningSheet = false
    @State private var buildKitStatus: LitterBuildKitStatus?
    @State private var selectedSigningMode: KittyStoreSigningMode = .certificate
    @State private var signingImportKind: KittyStoreImportKind = .ipa
    @State private var showingSigningImporter = false
    @State private var signingAlert: KittyStoreSigningAlert?
    @State private var pendingDeviceRemoval: KittyStoreRemovalRequest?
    @State private var signingInProgress = false
    @State private var deviceActionInProgress = false
    @State private var installedDeviceAppsInProgress = false
    @State private var sourceIPADownloadInProgress = false
    @State private var sourceIPADownloadMessage: String?
    @State private var appleIDEmailInput = ""
    @State private var appleIDTeamIDInput = ""
    @State private var appleIDPasswordInput = ""
    @State private var appleIDTwoFactorCodeInput = ""
    @State private var appleIDAnisetteURLInput = NyxianAnisetteServerDirectory.defaultServerURL
    @State private var selectedAnisetteServerAddress = NyxianAnisetteServerDirectory.defaultServerURL
    @State private var anisetteServerListURLInput = NyxianAnisetteServerDirectory.officialListURL
    @State private var anisetteServers = NyxianAnisetteServerDirectory.fallbackServers
    @State private var appleIDTeams: [KittyStoreSideStoreSigningBridge.TeamSummary] = []
    @State private var appleIDActionMessage: String?
    @State private var anisetteServerMessage: String?
    @State private var certificatePasswordInput = ""
    @State private var certificateActionMessage: String?
    @State private var pendingCertificateFile: KittyStoreImportedFile?
    @State private var sideStoreAccountActionMessage: String?
    @State private var importedIPA: KittyStoreImportedFile?
    @State private var importedProvisioningProfile: KittyStoreImportedFile?
    @State private var importedPairingFile: KittyStoreImportedFile?
    @State private var installedDeviceApps: [KittyStoreInstalledDeviceApp] = []
    @State private var installedDeviceAppsMessage: String?
    @State private var existingDylibs: [KittyStoreImportedFile] = []
    @State private var removeDylibNames = ""
    @State private var removeAppFiles = ""
    @State private var frameworksAndPlugins: [KittyStoreImportedFile] = []
    @State private var tweaks: [KittyStoreImportedFile] = []
    @State private var appNameOverride = ""
    @State private var bundleIdentifierOverride = ""
    @State private var appVersionOverride = ""
    @State private var entitlementsText = "{\n}\n"
    @State private var signingType: KittyStoreFeatherSigningType = .standard
    @State private var appAppearance: KittyStoreAppAppearance = .default
    @State private var minimumAppRequirement: KittyStoreMinimumRequirement = .default
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
    @State private var postSigningAction: KittyStorePostSigningAction = .install
    @State private var deleteAfterSigning = false
    @State private var replaceSubstrateWithElleKit = true
    @State private var enableLiquidGlass = false

    private var apps: [KittyStoreApp] { source?.apps ?? [] }
    private var currentBundleIdentifier: String { Bundle.main.bundleIdentifier ?? "com.sigkitten.litter" }
    private var app: KittyStoreApp? {
        if let selectedSourceAppID,
           let selected = apps.first(where: { $0.bundleIdentifier == selectedSourceAppID }) {
            return selected
        }
        return apps.first { $0.bundleIdentifier == currentBundleIdentifier } ?? apps.first
    }
    private var selectedAppName: String { app?.name ?? "App" }
    private var versions: [KittyStoreVersion] { app?.versions ?? [] }
    private var latestVersion: KittyStoreVersion? { versions.first }
    private var sourceURL: String { source?.sourceURL ?? AppReleaseSource.current.stableSourceURLString }

    var body: some View {
        TabView(selection: $selectedTab) {
            newsWorkspace
                .tabItem { Label("News", systemImage: "newspaper") }
                .tag(KittyStoreTab.news)

            sourcesWorkspace
                .tabItem { Label("Sources", systemImage: "list.bullet.rectangle") }
                .tag(KittyStoreTab.sources)

            browseWorkspace
                .tabItem { Label("Browse", systemImage: "bag") }
                .tag(KittyStoreTab.browse)

            myAppsWorkspace
                .tabItem { Label("My Apps", systemImage: "square.stack.3d.up.fill") }
                .tag(KittyStoreTab.myApps)

            settingsWorkspace
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(KittyStoreTab.settings)
        }
        .tint(LitterTheme.accent)
        .background(LitterTheme.backgroundGradient.ignoresSafeArea())
        .navigationTitle(selectedTab.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    taskBag.run { await refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(sourcePhase.isBusy || sourceIPADownloadInProgress)
                .accessibilityLabel("Refresh KittyStore")
            }
        }
        .refreshable { await refreshAll() }
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
        .sheet(isPresented: $showingSigningSheet) {
            NavigationStack {
                signingWorkspace
                    .navigationTitle("Signing")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingSigningSheet = false }
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        startSigningBar
                    }
            }
            .background(LitterTheme.backgroundGradient.ignoresSafeArea())
        }
        .alert(item: $signingAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .confirmationDialog(
            "Remove from Device",
            isPresented: Binding(
                get: { pendingDeviceRemoval != nil },
                set: { isPresented in
                    if !isPresented { pendingDeviceRemoval = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            if let request = pendingDeviceRemoval {
                Button("Remove \(request.name)", role: .destructive) {
                    removeSelectedAppFromDevice(request)
                    pendingDeviceRemoval = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeviceRemoval = nil
            }
        } message: {
            if let request = pendingDeviceRemoval {
                Text("Uninstall \(request.bundleIdentifier) through the SideStore minimuxer bridge.")
            }
        }
        .onChange(of: selectedAnisetteServerAddress) { _, newValue in
            guard newValue != NyxianAnisetteServerDirectory.customSelectionID else { return }
            appleIDAnisetteURLInput = newValue
        }
        .task {
            await refreshAll()
            await refreshAnisetteServers(showSuccess: false)
        }
        .onDisappear {
            taskBag.cancelAll()
        }
    }

    private var newsWorkspace: some View {
        storeScroll {
            latestNewsPanel
            versionHistoryPanel
        }
    }

    private var sourcesWorkspace: some View {
        storeScroll {
            sourcePanel
        }
    }

    private var browseWorkspace: some View {
        storeScroll {
            heroPanel
            sourceAppsPanel
            versionHistoryPanel
        }
    }

    private var myAppsWorkspace: some View {
        storeScroll {
            myAppsPanel
        }
    }

    private var settingsWorkspace: some View {
        storeScroll {
            accountSettingsPanel
            signingSettingsPanel
            transportSettingsPanel
            diagnosticsSettingsPanel
        }
    }

    private func storeScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var signingWorkspace: some View {
        Form {
            signingCustomizationSection
            signingIdentitySection
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
                    Text(source?.name ?? "KittyLitter Store")
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
                metricItem("Source", source?.name ?? "Not Loaded")
                metricItem("Apps", apps.isEmpty ? "Unknown" : "\(apps.count)")
                metricItem("Latest", latestVersion?.version ?? "Unknown")
                metricItem("Versions", versions.isEmpty ? "Unknown" : "\(versions.count)")
                if let size = latestVersion?.size, size > 0 {
                    metricItem("IPA Size", LitterDownloadSupport.formatBytes(size))
                }
            }
        }
    }

    private var sourceAppsPanel: some View {
        panel(title: "Browse", icon: "bag") {
            VStack(spacing: 10) {
                if let sourceIPADownloadMessage {
                    readinessRow(
                        sourceIPADownloadInProgress ? "IPA Download" : "IPA Ready",
                        detail: sourceIPADownloadMessage,
                        state: sourceIPADownloadInProgress ? nil : importedIPA != nil
                    )
                }

                if apps.isEmpty {
                    emptyState(sourcePhase.message)
                } else {
                    ForEach(apps) { storeApp in
                        sourceAppRow(storeApp)
                    }
                }
            }
        }
    }

    private var myAppsPanel: some View {
        panel(title: "My Apps", icon: "square.stack.3d.up.fill") {
            VStack(spacing: 10) {
                readinessRow(
                    "Device Apps",
                    detail: installedDeviceAppsInProgress ? "Loading installed apps from SideStore minimuxer." : (installedDeviceAppsMessage ?? "Load apps from the paired device."),
                    state: installedDeviceApps.isEmpty ? nil : true
                )

                actionRow("Load Installed Apps", detail: importedPairingFile == nil ? "Import a pairing file in Settings before browsing installed apps." : "Browse installed apps through the SideStore minimuxer bridge.", icon: "iphone.gen3", enabled: importedPairingFile != nil && KittyStoreMinimuxerBridge.isLinked && !installedDeviceAppsInProgress) {
                    loadInstalledDeviceApps()
                }

                if installedDeviceApps.isEmpty {
                    emptyState(installedDeviceAppsMessage ?? "No installed apps loaded from the paired device yet.")
                } else {
                    ForEach(Array(installedDeviceApps.prefix(30))) { installedApp in
                        installedDeviceAppRow(installedApp)
                    }
                }
            }
        }
    }

    private var latestNewsPanel: some View {
        panel(title: "News", icon: "newspaper") {
            VStack(spacing: 10) {
                if let latestVersion {
                    readinessRow(
                        "\(selectedAppName) \(latestVersion.version ?? latestVersion.buildVersion ?? "Latest")",
                        detail: latestVersion.cleanedDescription.isEmpty ? "Latest source release is ready to install or sign." : shortNotes(latestVersion.cleanedDescription),
                        state: true
                    )
                    HStack(spacing: 8) {
                        if let sideStoreURL = installerURL(scheme: "sidestore", host: "install", targetURL: latestVersion.downloadURL) {
                            compactButton("Install", icon: "square.and.arrow.down") { openURL(sideStoreURL) }
                        }
                        if let selectedApp = app {
                            compactButton("Sign", icon: "signature") {
                                downloadSourceIPAForSigning(storeApp: selectedApp, version: latestVersion, openSigning: true)
                            }
                        }
                    }
                } else {
                    emptyState(sourcePhase.message)
                }
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

    private var sourcePanel: some View {
        panel(title: "Source", icon: "link") {
            VStack(spacing: 10) {
                actionRow("Add Source in SideStore", detail: "Subscribe to the current compatible source", icon: "link.badge.plus") {
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

    private var accountSettingsPanel: some View {
        panel(title: "Account", icon: "person.crop.circle") {
            VStack(spacing: 10) {
                readinessRow(
                    "Apple ID",
                    detail: buildKitStatus?.appleIDDetail ?? "Not logged in.",
                    state: buildKitStatus?.appleIDConfigured
                )

                settingsTextField("Apple ID email", text: $appleIDEmailInput, keyboardType: .emailAddress, textContentType: .username)
                settingsTextField("Team ID (optional)", text: $appleIDTeamIDInput, autocapitalization: .characters)
                settingsSecureField("Apple ID password or app-specific password", text: $appleIDPasswordInput)
                settingsTextField("Two-factor code", text: $appleIDTwoFactorCodeInput, keyboardType: .numberPad, textContentType: .oneTimeCode)

                Picker("Anisette server", selection: $selectedAnisetteServerAddress) {
                    ForEach(anisetteServers) { server in
                        Text(server.displayName).tag(server.address)
                    }
                    Text("Custom").tag(NyxianAnisetteServerDirectory.customSelectionID)
                }
                .pickerStyle(.menu)
                .padding(10)
                .background(LitterTheme.surfaceLight.opacity(0.3), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                if selectedAnisetteServerAddress == NyxianAnisetteServerDirectory.customSelectionID {
                    settingsTextField("Custom Anisette server URL", text: $appleIDAnisetteURLInput, keyboardType: .URL)
                }
                settingsTextField("Anisette server list URL", text: $anisetteServerListURLInput, keyboardType: .URL)

                if !appleIDTeams.isEmpty {
                    Picker("Signing team", selection: $appleIDTeamIDInput) {
                        ForEach(appleIDTeams, id: \.id) { team in
                            Text(team.displayText).tag(team.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(10)
                    .background(LitterTheme.surfaceLight.opacity(0.3), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    actionRow("Save Selected Team", detail: appleIDTeamIDInput.isEmpty ? "Choose a team returned by Apple ID login." : "Use \(appleIDTeamIDInput) for SideStore signing.", icon: "person.2.badge.gearshape") {
                        taskBag.run { await saveSelectedAppleIDTeam() }
                    }
                }

                actionRow("Login Apple ID", detail: KittyStoreSideStoreSigningBridge.isLinked ? "Authenticate with SideStore AltSign and save the selected team." : "Save the account locally; this build is missing AltSign linkage.", icon: "person.badge.key.fill", enabled: !appleIDEmailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !appleIDPasswordInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    taskBag.run { await saveKittyStoreAppleID() }
                }
                actionRow("Import SideStore Account", detail: "Import a .sideconf account, ADI fields, certificate, and password.", icon: "person.crop.circle.badge.plus") {
                    presentImporter(.sideStoreAccount)
                }
                actionRow("Refresh Anisette Servers", detail: "Reload the SideStore Anisette server list.", icon: "arrow.clockwise.circle") {
                    taskBag.run { await refreshAnisetteServers(showSuccess: true) }
                }
                actionRow("Clear Apple ID Login", detail: "Remove the saved Apple ID and Keychain password.", icon: "person.crop.circle.badge.xmark", enabled: NyxianAppleIDStore.load() != nil) {
                    clearKittyStoreAppleID()
                }

                if let appleIDActionMessage, !appleIDActionMessage.isEmpty {
                    messageBlock(appleIDActionMessage)
                }
                if let sideStoreAccountActionMessage, !sideStoreAccountActionMessage.isEmpty {
                    messageBlock(sideStoreAccountActionMessage)
                }
                if let anisetteServerMessage, !anisetteServerMessage.isEmpty {
                    messageBlock(anisetteServerMessage)
                }
            }
        }
    }

    private var signingSettingsPanel: some View {
        panel(title: "Certificate Pair", icon: "signature") {
            VStack(spacing: 10) {
                readinessRow(
                    "Certificate (.p12)",
                    detail: buildKitStatus?.nyxianSigningCertificateDetail ?? "Import the .p12 half of the Feather certificate pair. KittyStore validates password, private key, expiry, and revocation.",
                    state: buildKitStatus?.nyxianSigningCertificateInstalled
                )
                settingsSecureField("Certificate password", text: $certificatePasswordInput)
                if let pendingCertificateFile {
                    readinessRow("Selected .p12", detail: pendingCertificateFile.displayName, state: nil)
                }
                actionRow("Import .p12", detail: "Choose the certificate identity used with a .mobileprovision profile.", icon: "key") {
                    presentImporter(.certificate)
                }
                actionRow("Validate & Save Certificate", detail: "Reject wrong passwords, missing private keys, expired certs, and revoked certs.", icon: "checkmark.seal", enabled: pendingCertificateFile != nil) {
                    saveImportedCertificate()
                }
                actionRow("Clear .p12", detail: "Remove the saved certificate identity and password.", icon: "trash", enabled: NyxianSigningCertificateStorage.loadIdentity() != nil) {
                    clearKittyStoreCertificate()
                }

                actionRow("Signing Workspace", detail: "Import IPAs, profiles, dylibs, tweaks, entitlements, and properties.", icon: "slider.horizontal.3") {
                    showingSigningSheet = true
                }

                if let certificateActionMessage, !certificateActionMessage.isEmpty {
                    messageBlock(certificateActionMessage)
                }
            }
        }
    }

    private var transportSettingsPanel: some View {
        panel(title: "App Refresh", icon: "antenna.radiowaves.left.and.right") {
            VStack(spacing: 10) {
                readinessRow(
                    "Pairing File",
                    detail: importedPairingFile?.displayName ?? "Import the iOS pairing file used by SideStore/minimuxer.",
                    state: importedPairingFile != nil
                )
                readinessRow(
                    "LocalDevVPN",
                    detail: buildKitStatus?.localDevVPNDetail ?? "Required for direct on-device install and refresh.",
                    state: buildKitStatus?.localDevVPNConnected
                )
                readinessRow(
                    "Minimuxer Bridge",
                    detail: KittyStoreMinimuxerBridge.isLinked ? "Linked into this build." : "This IPA was not linked with SideStore minimuxer yet.",
                    state: KittyStoreMinimuxerBridge.isLinked
                )
                actionRow("Open LocalDevVPN", detail: "Launch the real LocalDevVPN app and enable its tunnel before install or refresh.", icon: "network") {
                    if let url = URL(string: "localdevvpn://") { openURL(url) }
                }
                actionRow("Import Pairing File", detail: "Choose the pairing file used for SideStore install and refresh.", icon: "doc.badge.gearshape") {
                    presentImporter(.pairingFile)
                }
            }
        }
    }

    private var diagnosticsSettingsPanel: some View {
        panel(title: "Diagnostics", icon: "stethoscope") {
            VStack(spacing: 10) {
                readinessRow("Source Feed", detail: sourcePhase.message, state: source != nil)
                readinessRow("BuildKit", detail: buildKitStatus == nil ? "Status has not loaded yet." : "Status refreshed from the local BuildKit bridge.", state: buildKitStatus != nil)
                actionRow("Refresh Diagnostics", detail: "Reload source, account, certificate, and LocalDevVPN state.", icon: "arrow.clockwise") {
                    taskBag.run { await refreshAll() }
                }
                navigationActionRow("Advanced BuildKit Diagnostics", detail: "Open raw BuildKit assets, commands, and fakefs checks.", icon: "wrench.and.screwdriver") {
                    BuildKitSettingsView()
                }
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
                KittyStoreTextEditorView(title: "Version", text: $appVersionOverride, placeholder: latestVersion?.version ?? "1.0")
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

            Button {
                showingSigningSheet = false
                selectedTab = .settings
            } label: {
                LabeledContent("Certificate (.p12)") {
                    Text(buildKitStatus?.nyxianSigningCertificateInstalled == true ? "Validated" : "No Certificate")
                        .foregroundStyle(buildKitStatus?.nyxianSigningCertificateInstalled == true ? LitterTheme.success : LitterTheme.warning)
                }
            }
            .buttonStyle(.plain)

            Button {
                presentImporter(.provisioningProfile)
            } label: {
                LabeledContent("Profile (.mobileprovision)") {
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
            Text("Certificate Pair")
        } footer: {
            Text("Feather-style certificate signing uses both files: a validated .p12 identity from KittyStore Settings and a per-app .mobileprovision profile selected here.")
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

                NavigationLink("Remove Dylibs") {
                    KittyStoreCodeEditorView(title: "Remove Dylibs", text: $removeDylibNames)
                }

                NavigationLink("Remove Files") {
                    KittyStoreCodeEditorView(title: "Remove Files", text: $removeAppFiles)
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
                    appAppearance: $appAppearance,
                    minimumAppRequirement: $minimumAppRequirement,
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
                    postSigningAction: $postSigningAction,
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
                Text(signingInProgress ? "Signing..." : "Start Signing")
                    .litterFont(.headline, weight: .semibold)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(LitterTheme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(signingInProgress || sourceIPADownloadInProgress)
            .opacity((signingInProgress || sourceIPADownloadInProgress) ? 0.72 : 1)
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
        if let source, !apps.isEmpty {
            let sourceName = source.name ?? "Source"
            return "\(sourceName) is loaded as a SideStore/AltStore-compatible source with \(apps.count) app(s). Signing uses SideStore AltSign and Feather-style options."
        }
        return "Load a SideStore/AltStore source, import IPAs, sign with Apple ID or a certificate pair, then install through the SideStore minimuxer bridge."
    }

    private var sourceHost: String {
        URL(string: sourceURL)?.host ?? "source feed"
    }

    private var importedIPAName: String {
        importedIPA?.displayName ?? latestVersion.map { "\(selectedAppName) \($0.version ?? "IPA")" } ?? "Imported IPA"
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
        return latestVersion?.version ?? latestVersion?.buildVersion ?? "Unknown"
    }

    private var profileFallbackTitle: String {
        buildKitStatus?.embeddedProvisionPresent == true ? "Use Embedded Profile" : "Not Imported"
    }

    private var signingReadinessMessage: String? {
        if sourceIPADownloadInProgress { return sourceIPADownloadMessage ?? "Downloading the selected source IPA." }
        guard importedIPA != nil else { return "Import an IPA before signing." }
        if postSigningAction.requiresDeviceTransfer {
            if selectedSigningMode == .certificate && signingType == .adhoc { return "Ad Hoc signed IPAs cannot be installed or refreshed through SideStore on stock iOS." }
            if importedPairingFile == nil { return "Import the iOS pairing file for SideStore-style \(postSigningAction.transferVerb)." }
            if !KittyStoreMinimuxerBridge.isLinked { return "This build was not linked with the SideStore minimuxer bridge yet." }
            if buildKitStatus?.localDevVPNConnected != true { return "Ready to try SideStore signing. LocalDevVPN will be verified by minimuxer during \(postSigningAction.transferVerb)." }
        }
        switch selectedSigningMode {
        case .certificate:
            if signingType == .adhoc { return signingInProgress ? "Native Feather/Zsign ad-hoc signing is running." : "Ready to ad-hoc sign with the native Feather/Zsign path." }
            if buildKitStatus?.nyxianSigningCertificateInstalled != true { return "Import a valid certificate in KittyStore Settings." }
            return signingInProgress ? "Native Feather/Zsign signing is running." : "Ready to sign with the native Feather/Zsign path."
        case .appleID:
            if buildKitStatus?.appleIDConfigured != true { return "Add Apple ID login in KittyStore Settings." }
            if importedPairingFile == nil { return "Import the iOS pairing file for SideStore Apple ID signing." }
            if !KittyStoreMinimuxerBridge.isLinked { return "This build was not linked with the SideStore minimuxer bridge yet." }
            return signingInProgress ? "Native signing or transfer is running." : "Inputs are ready for signing and SideStore-style \(postSigningAction.transferVerb)."
        }
    }

    private func refreshAll() async {
        await refreshSource()
        await refreshBuildKitStatus()
    }

    private func refreshSource() async {
        guard let url = URL(string: sourceURL) else {
            sourcePhase = .failed("Invalid source URL.")
            return
        }
        sourcePhase = .loading
        do {
            let data = try await GitHubReleaseAPI.data(url: url)
            let decodedSource = try JSONDecoder().decode(KittyStoreSource.self, from: data)
            source = decodedSource
            if let selectedSourceAppID, !decodedSource.apps.contains(where: { $0.bundleIdentifier == selectedSourceAppID }) {
                self.selectedSourceAppID = nil
            }
            sourcePhase = .loaded
        } catch {
            sourcePhase = .failed(error.localizedDescription)
        }
    }

    @MainActor
    private func refreshBuildKitStatus() async {
        buildKitStatus = await LitterBuildKit.shared.status(checkRevocation: true)
        loadKittyStoreSettingsFields()
    }

    private var anisetteURLForLogin: String {
        if selectedAnisetteServerAddress == NyxianAnisetteServerDirectory.customSelectionID {
            return appleIDAnisetteURLInput
        }
        return selectedAnisetteServerAddress
    }

    @MainActor
    private func loadKittyStoreSettingsFields() {
        guard let account = NyxianAppleIDStore.load() else { return }
        if appleIDEmailInput.isEmpty { appleIDEmailInput = account.email }
        if appleIDTeamIDInput.isEmpty { appleIDTeamIDInput = account.teamID }
        if appleIDAnisetteURLInput == NyxianAnisetteServerDirectory.defaultServerURL {
            appleIDAnisetteURLInput = account.anisetteServerURL ?? NyxianAnisetteServerDirectory.defaultServerURL
            syncAnisetteSelectionFromInput()
        }
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
    private func saveKittyStoreAppleID() async {
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
                let existingAccount = NyxianAppleIDStore.load()
                let shouldPreserveSideStoreADI = existingAccount?.email.caseInsensitiveCompare(summary.email) == .orderedSame
                let account = try NyxianAppleIDStore.login(
                    email: summary.email,
                    password: appleIDPasswordInput,
                    teamID: summary.teamID,
                    anisetteServerURL: summary.anisetteServerURL,
                    sideStoreLocalUserIdentifier: shouldPreserveSideStoreADI ? existingAccount?.sideStoreLocalUserIdentifier : nil,
                    sideStoreAdiPB: shouldPreserveSideStoreADI ? existingAccount?.sideStoreAdiPB : nil
                )
                appleIDEmailInput = account.email
                appleIDTeamIDInput = summary.teamID
                appleIDTeams = summary.availableTeams
                appleIDAnisetteURLInput = summary.anisetteServerURL
                syncAnisetteSelectionFromInput()
                appleIDPasswordInput = ""
                appleIDTwoFactorCodeInput = ""
                appleIDActionMessage = "SideStore Apple ID login verified for \(summary.statusDetail). Teams found: \(summary.availableTeams.map(\.displayText).joined(separator: ", "))."
            } else {
                let existingAccount = NyxianAppleIDStore.load()
                let loginEmail = appleIDEmailInput.trimmingCharacters(in: .whitespacesAndNewlines)
                let shouldPreserveSideStoreADI = existingAccount?.email.caseInsensitiveCompare(loginEmail) == .orderedSame
                let account = try NyxianAppleIDStore.login(
                    email: appleIDEmailInput,
                    password: appleIDPasswordInput,
                    teamID: appleIDTeamIDInput,
                    anisetteServerURL: anisetteURL,
                    sideStoreLocalUserIdentifier: shouldPreserveSideStoreADI ? existingAccount?.sideStoreLocalUserIdentifier : nil,
                    sideStoreAdiPB: shouldPreserveSideStoreADI ? existingAccount?.sideStoreAdiPB : nil
                )
                appleIDEmailInput = account.email
                appleIDTeamIDInput = account.teamID
                appleIDTeams = []
                appleIDAnisetteURLInput = account.anisetteServerURL ?? NyxianAnisetteServerDirectory.defaultServerURL
                syncAnisetteSelectionFromInput()
                appleIDPasswordInput = ""
                appleIDTwoFactorCodeInput = ""
                appleIDActionMessage = "Apple ID login saved locally, but SideStore AltSign is not linked in this build yet."
            }
            await refreshBuildKitStatus()
        } catch {
            appleIDActionMessage = "Apple ID login failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func saveSelectedAppleIDTeam() async {
        do {
            guard let account = NyxianAppleIDStore.load() else {
                appleIDActionMessage = "Log in with Apple ID before saving a signing team."
                return
            }
            guard let password = try NyxianAppleIDCredentialStore.shared.loadPassword() else {
                appleIDActionMessage = "Apple ID password is missing from Keychain. Log in again before saving a signing team."
                return
            }
            let updated = try NyxianAppleIDStore.login(
                email: account.email,
                password: password,
                teamID: appleIDTeamIDInput,
                anisetteServerURL: account.anisetteServerURL ?? NyxianAnisetteServerDirectory.defaultServerURL,
                sideStoreLocalUserIdentifier: account.sideStoreLocalUserIdentifier,
                sideStoreAdiPB: account.sideStoreAdiPB
            )
            appleIDEmailInput = updated.email
            appleIDTeamIDInput = updated.teamID
            appleIDAnisetteURLInput = updated.anisetteServerURL ?? NyxianAnisetteServerDirectory.defaultServerURL
            syncAnisetteSelectionFromInput()
            appleIDActionMessage = "Saved signing team \(updated.teamID)."
            await refreshBuildKitStatus()
        } catch {
            appleIDActionMessage = "Could not save signing team: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func clearKittyStoreAppleID() {
        do {
            try NyxianAppleIDStore.clear()
            appleIDEmailInput = ""
            appleIDTeamIDInput = ""
            appleIDPasswordInput = ""
            appleIDTwoFactorCodeInput = ""
            appleIDTeams = []
            appleIDAnisetteURLInput = NyxianAnisetteServerDirectory.defaultServerURL
            selectedAnisetteServerAddress = NyxianAnisetteServerDirectory.defaultServerURL
            appleIDActionMessage = "Removed Apple ID login."
            taskBag.run { await refreshBuildKitStatus() }
        } catch {
            appleIDActionMessage = "Could not remove Apple ID login: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func saveImportedCertificate() {
        guard let pendingCertificateFile else {
            certificateActionMessage = "Import a .p12 certificate first."
            return
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: pendingCertificateFile.stagedPath))
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
            self.pendingCertificateFile = nil
            certificatePasswordInput = ""
            certificateActionMessage = summary.importMessage
            taskBag.run { await refreshBuildKitStatus() }
        } catch {
            certificateActionMessage = "Certificate import failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func clearKittyStoreCertificate() {
        NyxianSigningCertificateStorage.clear()
        pendingCertificateFile = nil
        certificatePasswordInput = ""
        certificateActionMessage = "Removed the imported signing certificate."
        taskBag.run { await refreshBuildKitStatus() }
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
        case .certificate:
            pendingCertificateFile = files.first
            certificateActionMessage = files.first.map { "Selected \($0.displayName). Enter its password and tap Validate & Save Certificate." }
        case .sideStoreAccount:
            importSideStoreAccount(files.first)
        case .provisioningProfile:
            guard let file = files.first else { return }
            do {
                let summary = try validateProvisioningProfile(file, requireCertificateMatch: false)
                importedProvisioningProfile = file
                signingAlert = KittyStoreSigningAlert(title: "Provisioning Profile Ready", message: summary.importMessage)
            } catch {
                importedProvisioningProfile = nil
                signingAlert = KittyStoreSigningAlert(title: "Provisioning Profile Failed", message: error.localizedDescription)
            }
        case .pairingFile:
            importedPairingFile = files.first
            installedDeviceApps.removeAll()
            installedDeviceAppsMessage = "Pairing file imported. Load installed apps to browse the device."
        case .existingDylibs:
            existingDylibs.append(contentsOf: files)
        case .frameworksAndPlugins:
            frameworksAndPlugins.append(contentsOf: files)
        case .tweaks:
            tweaks.append(contentsOf: files)
        }
    }

    @MainActor
    private func importSideStoreAccount(_ file: KittyStoreImportedFile?) {
        guard let file else { return }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: file.stagedPath))
            let summary = try KittyStoreSideStoreAccountImporter.importSideconf(
                data: data,
                anisetteServerURL: anisetteURLForLogin
            )
            appleIDEmailInput = summary.account.email
            appleIDTeamIDInput = summary.account.teamID
            appleIDAnisetteURLInput = summary.account.anisetteServerURL ?? NyxianAnisetteServerDirectory.defaultServerURL
            syncAnisetteSelectionFromInput()
            appleIDPasswordInput = ""
            appleIDTwoFactorCodeInput = ""
            certificatePasswordInput = ""
            pendingCertificateFile = nil
            appleIDActionMessage = summary.message
            sideStoreAccountActionMessage = summary.message
            certificateActionMessage = summary.certificate.importMessage
            taskBag.run { await refreshBuildKitStatus() }
        } catch {
            sideStoreAccountActionMessage = "SideStore account import failed: \(error.localizedDescription)"
        }
    }

    private func validateProvisioningProfile(_ file: KittyStoreImportedFile, requireCertificateMatch: Bool) throws -> NyxianProvisioningProfileSummary {
        let data = try Data(contentsOf: URL(fileURLWithPath: file.stagedPath))
        var certificateFingerprint: String?
        if let identity = NyxianSigningCertificateStorage.loadIdentity() {
            let certificateSummary = try NyxianSigningCertificateValidator.validate(
                pkcs12Data: identity.data,
                password: identity.password,
                checkRevocation: true
            )
            certificateFingerprint = certificateSummary.sha256Fingerprint
        } else if requireCertificateMatch {
            throw NSError(
                domain: "KittyStoreProvisioningProfileValidation",
                code: 64,
                userInfo: [NSLocalizedDescriptionKey: "Import and validate a .p12 certificate before using this provisioning profile for certificate signing."]
            )
        }

        return try NyxianProvisioningProfileValidator.validate(
            data: data,
            signingCertificateFingerprint: certificateFingerprint,
            requestedBundleIdentifier: displayedBundleIdentifier
        )
    }

    @MainActor
    private func selectSourceApp(_ storeApp: KittyStoreApp) {
        selectedSourceAppID = storeApp.bundleIdentifier
    }

    @MainActor
    private func prepareSigningFields(for storeApp: KittyStoreApp, version: KittyStoreVersion?) {
        selectSourceApp(storeApp)
        appNameOverride = storeApp.name
        bundleIdentifierOverride = storeApp.bundleIdentifier
        appVersionOverride = version?.version ?? version?.buildVersion ?? ""
    }

    @MainActor
    private func downloadSourceIPAForSigning(storeApp: KittyStoreApp, version: KittyStoreVersion, openSigning: Bool) {
        guard !sourceIPADownloadInProgress else { return }
        prepareSigningFields(for: storeApp, version: version)
        guard let remoteURL = URL(string: version.downloadURL) else {
            signingAlert = KittyStoreSigningAlert(title: "Invalid IPA URL", message: "The selected source version does not have a valid IPA download URL.")
            return
        }

        sourceIPADownloadInProgress = true
        sourceIPADownloadMessage = "Downloading \(storeApp.name) \(version.version ?? version.buildVersion ?? "IPA")"
        taskBag.run {
            do {
                let directory = try LitterDownloadSupport.appSupportDirectory(named: "KittyStoreSourceIPAs")
                let fileName = sourceIPAFileName(for: storeApp, version: version, remoteURL: remoteURL)
                let destination = directory.appendingPathComponent(fileName)
                let request = GitHubReleaseAPI.request(url: remoteURL, accept: "application/octet-stream")
                let driver = FileDownloadDriver(destination: destination) { written, expected in
                    Task { @MainActor in
                        updateSourceDownloadProgress(written: written, expected: expected, appName: storeApp.name)
                    }
                }
                let fileURL = try await driver.start(request: request)
                if let expectedSHA = version.normalizedSHA256 {
                    sourceIPADownloadMessage = "Verifying \(storeApp.name) checksum"
                    let actualSHA = try LitterDownloadSupport.sha256Hex(for: fileURL)
                    guard actualSHA == expectedSHA else {
                        try? FileManager.default.removeItem(at: fileURL)
                        throw NSError(
                            domain: "KittyStoreSourceChecksum",
                            code: 65,
                            userInfo: [NSLocalizedDescriptionKey: "Downloaded IPA checksum mismatch. Expected \(expectedSHA), got \(actualSHA)."]
                        )
                    }
                }
                let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
                let size = values?.fileSize.map(Int64.init)
                if let expectedSize = version.size, expectedSize > 0, let size, size != expectedSize {
                    try? FileManager.default.removeItem(at: fileURL)
                    throw NSError(
                        domain: "KittyStoreSourceSize",
                        code: 65,
                        userInfo: [NSLocalizedDescriptionKey: "Downloaded IPA size mismatch. Expected \(LitterDownloadSupport.formatBytes(expectedSize)), got \(LitterDownloadSupport.formatBytes(size))."]
                    )
                }
                importedIPA = KittyStoreImportedFile(displayName: fileName, stagedPath: fileURL.path, size: size, isDirectory: false)
                sourceIPADownloadInProgress = false
                if let shortSHA = version.shortSHA256 {
                    sourceIPADownloadMessage = "Ready to sign \(fileName) (verified \(shortSHA))"
                } else {
                    sourceIPADownloadMessage = "Ready to sign \(fileName)"
                }
                if openSigning { showingSigningSheet = true }
            } catch is CancellationError {
                sourceIPADownloadInProgress = false
                sourceIPADownloadMessage = "IPA download cancelled."
            } catch {
                sourceIPADownloadInProgress = false
                sourceIPADownloadMessage = "IPA download failed."
                signingAlert = KittyStoreSigningAlert(title: "Download Failed", message: error.localizedDescription)
            }
        }
    }

    private func sourceIPAFileName(for storeApp: KittyStoreApp, version: KittyStoreVersion, remoteURL: URL) -> String {
        let remoteName = remoteURL.lastPathComponent.removingPercentEncoding ?? remoteURL.lastPathComponent
        if remoteName.lowercased().hasSuffix(".ipa") { return sanitizeFileName(remoteName) }
        let versionToken = version.version ?? version.buildVersion ?? "source"
        return sanitizeFileName("\(storeApp.name)-\(versionToken).ipa")
    }

    @MainActor
    private func updateSourceDownloadProgress(written: Int64, expected: Int64, appName: String) {
        if expected > 0 {
            sourceIPADownloadMessage = "Downloading \(appName): \(LitterDownloadSupport.formatBytes(written)) / \(LitterDownloadSupport.formatBytes(expected))"
        } else {
            sourceIPADownloadMessage = "Downloading \(appName): \(LitterDownloadSupport.formatBytes(written))"
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

        let selectedPostSigningAction = postSigningAction
        if selectedPostSigningAction.requiresDeviceTransfer {
            if selectedSigningMode == .certificate && signingType == .adhoc {
                signingAlert = KittyStoreSigningAlert(title: "Ad Hoc Cannot Install", message: "Feather/Zsign ad-hoc output is useful for local inspection and LiveContainer-style loading, but stock iOS install/refresh through SideStore requires Apple-signed provisioning.")
                return
            }
            guard importedPairingFile != nil else {
                signingAlert = KittyStoreSigningAlert(title: "Pairing File Missing", message: "Import the SideStore-style iOS pairing file before \(selectedPostSigningAction.transferVerb).")
                return
            }
            guard KittyStoreMinimuxerBridge.isLinked else {
                signingAlert = KittyStoreSigningAlert(title: "Minimuxer Missing", message: "This IPA was not linked with the SideStore minimuxer bridge, so direct on-device install and refresh cannot run.")
                return
            }
        }

        switch selectedSigningMode {
        case .certificate:
            if signingType != .adhoc {
                guard buildKitStatus?.nyxianSigningCertificateInstalled == true else {
                    signingAlert = KittyStoreSigningAlert(title: "No Certificate", message: "Import and validate a .p12 certificate in KittyStore Settings first. Bad passwords, missing private keys, revoked certs, and profile mismatches stay blocked there.")
                    return
                }
                if let importedProvisioningProfile {
                    do {
                        _ = try validateProvisioningProfile(importedProvisioningProfile, requireCertificateMatch: true)
                    } catch {
                        signingAlert = KittyStoreSigningAlert(title: "Provisioning Profile Failed", message: error.localizedDescription)
                        return
                    }
                }
            }
        case .appleID:
            guard buildKitStatus?.appleIDConfigured == true else {
                signingAlert = KittyStoreSigningAlert(title: "Apple ID Missing", message: "Save the Apple ID, password, and Anisette server in KittyStore Settings first. Team selection happens after authentication when needed.")
                return
            }
            guard importedPairingFile != nil else {
                signingAlert = KittyStoreSigningAlert(title: "Pairing File Missing", message: "Import the SideStore-style iOS pairing file before direct install or refresh.")
                return
            }
            guard KittyStoreMinimuxerBridge.isLinked else {
                signingAlert = KittyStoreSigningAlert(title: "Minimuxer Missing", message: "This IPA was not linked with the SideStore minimuxer bridge, so direct on-device install and refresh cannot run.")
                return
            }
        }

        let plan = signingPlanJSON()
        let pairingPath = importedPairingFile?.stagedPath
        let profilePath = importedProvisioningProfile?.stagedPath
        let bundleID = displayedBundleIdentifier
        UIPasteboard.general.string = plan

        if selectedSigningMode == .certificate,
           signingType == .standard,
           KittyStoreSideStoreSigningBridge.isLinked,
           let importedIPA,
           let importedProvisioningProfile {
            startSideStoreAltSignSigning(
                importedIPA: importedIPA,
                provisioningProfile: importedProvisioningProfile,
                postSigningAction: selectedPostSigningAction,
                pairingPath: pairingPath,
                bundleID: bundleID
            )
            return
        }

        if selectedSigningMode == .appleID,
           KittyStoreSideStoreSigningBridge.isLinked,
           let importedIPA {
            startSideStoreAppleIDSigning(
                importedIPA: importedIPA,
                postSigningAction: selectedPostSigningAction,
                pairingPath: pairingPath,
                bundleID: bundleID
            )
            return
        }

        signingInProgress = true
        taskBag.run {
            let result = await LitterBuildKit.shared.signKittyStorePlan(planJSON: plan)
            signingInProgress = false
            buildKitStatus = await LitterBuildKit.shared.status(checkRevocation: true)
            let artifacts = result.fakefsArtifacts.isEmpty ? "" : "\n\nSigned IPA: \(result.fakefsArtifacts.joined(separator: "\n"))"
            if result.exitCode == 0 {
                if selectedPostSigningAction.requiresDeviceTransfer, let signedPath = result.fakefsArtifacts.first, let pairingPath {
                    signingInProgress = true
                    let installResult = await LitterBuildKit.shared.installKittyStoreIPA(
                        ipaPath: signedPath,
                        bundleIdentifier: bundleID,
                        pairingPath: pairingPath,
                        profilePath: profilePath,
                        refresh: selectedPostSigningAction == .refresh
                    )
                    signingInProgress = false
                    buildKitStatus = await LitterBuildKit.shared.status(checkRevocation: true)
                    if installResult.exitCode == 0 {
                        signingAlert = KittyStoreSigningAlert(
                            title: selectedPostSigningAction.successTitle,
                            message: "KittyStore signed the IPA and \(selectedPostSigningAction.completedVerb) it through the SideStore minimuxer bridge.\(artifacts)"
                        )
                    } else {
                        signingAlert = KittyStoreSigningAlert(
                            title: selectedPostSigningAction.failureTitle,
                            message: "Signing succeeded, but \(selectedPostSigningAction.transferVerb) failed.\nStatus: \(installResult.status)\n\n\(installResult.log.prefix(1800))\(artifacts)"
                        )
                    }
                    return
                }
                signingAlert = KittyStoreSigningAlert(
                    title: "Signed IPA Ready",
                    message: "KittyStore signed the IPA with the native Feather/Zsign path.\(artifacts)"
                )
            } else {
                signingAlert = KittyStoreSigningAlert(
                    title: "Signing Failed",
                    message: "Status: \(result.status)\n\n\(result.log.prefix(1800))"
                )
            }
        }
    }

    @MainActor
    private func startSideStoreAppleIDSigning(
        importedIPA: KittyStoreImportedFile,
        postSigningAction: KittyStorePostSigningAction,
        pairingPath: String?,
        bundleID: String
    ) {
        guard let account = NyxianAppleIDStore.load() else {
            signingAlert = KittyStoreSigningAlert(title: "Apple ID Missing", message: "Log in with Apple ID in KittyStore Settings before using SideStore Apple ID signing.")
            return
        }
        let password: String
        do {
            guard let storedPassword = try NyxianAppleIDCredentialStore.shared.loadPassword() else {
                signingAlert = KittyStoreSigningAlert(title: "Apple ID Password Missing", message: "Save the Apple ID password or app-specific password in KittyStore Settings first.")
                return
            }
            password = storedPassword
        } catch {
            signingAlert = KittyStoreSigningAlert(title: "Apple ID Password Failed", message: error.localizedDescription)
            return
        }

        signingInProgress = true
        taskBag.run {
            let outputDirectory: URL
            do {
                outputDirectory = try LitterDownloadSupport.appSupportDirectory(named: "KittyStoreSignedIPAs")
            } catch {
                signingInProgress = false
                signingAlert = KittyStoreSigningAlert(title: "Signing Failed", message: "Could not create the signed IPA output folder.\n\(error.localizedDescription)")
                return
            }

            var pairingContents: String?
            var deviceUDID: String?
            if let pairingPath {
                do {
                    let pairing = try String(contentsOfFile: pairingPath, encoding: .utf8)
                    pairingContents = pairing
                    let udidResult = await KittyStoreMinimuxerBridge.fetchUDID(pairingFileContents: pairing, consoleLoggingEnabled: true)
                    guard udidResult.exitCode == 0 else {
                        signingInProgress = false
                        signingAlert = KittyStoreSigningAlert(
                            title: "Pairing Failed",
                            message: "Could not read the device UDID through SideStore minimuxer.\nStatus: \(udidResult.status)\n\n\(udidResult.log.prefix(1200))"
                        )
                        return
                    }
                    deviceUDID = udidResult.log.trimmingCharacters(in: .whitespacesAndNewlines)
                } catch {
                    signingInProgress = false
                    signingAlert = KittyStoreSigningAlert(title: "Pairing Failed", message: "Could not read the imported pairing file.\n\(error.localizedDescription)")
                    return
                }
            }

            let signingResult = await KittyStoreSideStoreSigningBridge.signIPAWithAppleID(
                ipaURL: URL(fileURLWithPath: importedIPA.stagedPath),
                outputDirectory: outputDirectory,
                bundleIdentifier: bundleID,
                appName: displayedAppName,
                appVersion: displayedVersion,
                email: account.email,
                password: password,
                requestedTeamID: account.teamID,
                anisetteServerURL: account.anisetteServerURL ?? NyxianAnisetteServerDirectory.defaultServerURL,
                twoFactorCode: "",
                deviceUDID: deviceUDID
            )
            signingInProgress = false
            buildKitStatus = await LitterBuildKit.shared.status(checkRevocation: true)

            guard signingResult.exitCode == 0, let signedPath = signingResult.signedIPAPath else {
                signingAlert = KittyStoreSigningAlert(
                    title: "Apple ID Signing Failed",
                    message: "Status: \(signingResult.status)\n\n\(signingResult.log.prefix(1800))"
                )
                return
            }

            if postSigningAction.requiresDeviceTransfer, let pairing = pairingContents, let minimuxerAction = postSigningAction.minimuxerAction {
                do {
                    signingInProgress = true
                    let installResult = await KittyStoreMinimuxerBridge.installOrRefresh(
                        action: minimuxerAction,
                        bundleIdentifier: bundleID,
                        pairingFileContents: pairing,
                        ipaURL: URL(fileURLWithPath: signedPath),
                        provisioningProfileData: signingResult.provisioningProfileData,
                        consoleLoggingEnabled: true
                    )
                    signingInProgress = false
                    if installResult.exitCode == 0 {
                        signingAlert = KittyStoreSigningAlert(
                            title: postSigningAction.successTitle,
                            message: "SideStore Apple ID signing finished and minimuxer \(postSigningAction.completedVerb) the IPA.\n\nSigned IPA: \(signedPath)\n\n\(installResult.log.prefix(1400))"
                        )
                    } else {
                        signingAlert = KittyStoreSigningAlert(
                            title: postSigningAction.failureTitle,
                            message: "SideStore Apple ID signing succeeded, but minimuxer \(postSigningAction.transferVerb) failed.\nStatus: \(installResult.status)\n\n\(installResult.log.prefix(1600))\n\nSigned IPA: \(signedPath)"
                        )
                    }
                } catch {
                    signingInProgress = false
                    signingAlert = KittyStoreSigningAlert(
                        title: "Signed IPA Ready",
                        message: "SideStore Apple ID signing finished, but the pairing file could not be read for \(postSigningAction.transferVerb).\n\(error.localizedDescription)\n\nSigned IPA: \(signedPath)"
                    )
                }
            } else {
                signingAlert = KittyStoreSigningAlert(
                    title: "Signed IPA Ready",
                    message: "SideStore Apple ID signing finished.\n\nSigned IPA: \(signedPath)\n\n\(signingResult.log.prefix(1200))"
                )
            }
        }
    }

    @MainActor
    private func startSideStoreAltSignSigning(
        importedIPA: KittyStoreImportedFile,
        provisioningProfile: KittyStoreImportedFile,
        postSigningAction: KittyStorePostSigningAction,
        pairingPath: String?,
        bundleID: String
    ) {
        guard let identity = NyxianSigningCertificateStorage.loadIdentity() else {
            signingAlert = KittyStoreSigningAlert(title: "No Certificate", message: "Import and validate a .p12 certificate before using SideStore AltSign.")
            return
        }

        signingInProgress = true
        taskBag.run {
            let profileData: Data
            do {
                profileData = try Data(contentsOf: URL(fileURLWithPath: provisioningProfile.stagedPath))
            } catch {
                signingInProgress = false
                signingAlert = KittyStoreSigningAlert(title: "Profile Failed", message: "Could not read the imported provisioning profile.\n\(error.localizedDescription)")
                return
            }

            do {
                let certificateSummary = try NyxianSigningCertificateValidator.validate(
                    pkcs12Data: identity.data,
                    password: identity.password,
                    checkRevocation: true
                )
                _ = try NyxianProvisioningProfileValidator.validate(
                    data: profileData,
                    signingCertificateFingerprint: certificateSummary.sha256Fingerprint,
                    requestedBundleIdentifier: bundleID
                )
            } catch {
                signingInProgress = false
                signingAlert = KittyStoreSigningAlert(
                    title: "Certificate Failed",
                    message: "The saved .p12 or provisioning profile is no longer valid for SideStore AltSign.\n\(error.localizedDescription)"
                )
                return
            }

            let outputDirectory: URL
            do {
                outputDirectory = try LitterDownloadSupport.appSupportDirectory(named: "KittyStoreSignedIPAs")
            } catch {
                signingInProgress = false
                signingAlert = KittyStoreSigningAlert(title: "Signing Failed", message: "Could not create the signed IPA output folder.\n\(error.localizedDescription)")
                return
            }

            let account = NyxianAppleIDStore.load()
            let signingResult = await KittyStoreSideStoreSigningBridge.signIPAWithImportedIdentity(
                ipaURL: URL(fileURLWithPath: importedIPA.stagedPath),
                outputDirectory: outputDirectory,
                bundleIdentifier: bundleID,
                appName: displayedAppName,
                appVersion: displayedVersion,
                teamID: account?.teamID ?? "",
                teamName: nil,
                certificateData: identity.data,
                certificatePassword: identity.password,
                provisioningProfileData: profileData
            )
            signingInProgress = false
            buildKitStatus = await LitterBuildKit.shared.status(checkRevocation: true)

            guard signingResult.exitCode == 0, let signedPath = signingResult.signedIPAPath else {
                signingAlert = KittyStoreSigningAlert(
                    title: "SideStore Signing Failed",
                    message: "Status: \(signingResult.status)\n\n\(signingResult.log.prefix(1800))"
                )
                return
            }

            if postSigningAction.requiresDeviceTransfer, let pairingPath, let minimuxerAction = postSigningAction.minimuxerAction {
                do {
                    let pairing = try String(contentsOfFile: pairingPath, encoding: .utf8)
                    signingInProgress = true
                    let installResult = await KittyStoreMinimuxerBridge.installOrRefresh(
                        action: minimuxerAction,
                        bundleIdentifier: bundleID,
                        pairingFileContents: pairing,
                        ipaURL: URL(fileURLWithPath: signedPath),
                        provisioningProfileData: profileData,
                        consoleLoggingEnabled: true
                    )
                    signingInProgress = false
                    if installResult.exitCode == 0 {
                        signingAlert = KittyStoreSigningAlert(
                            title: postSigningAction.successTitle,
                            message: "SideStore AltSign signed the IPA and minimuxer \(postSigningAction.completedVerb) it.\n\nSigned IPA: \(signedPath)\n\n\(installResult.log.prefix(1400))"
                        )
                    } else {
                        signingAlert = KittyStoreSigningAlert(
                            title: postSigningAction.failureTitle,
                            message: "SideStore AltSign signing succeeded, but minimuxer \(postSigningAction.transferVerb) failed.\nStatus: \(installResult.status)\n\n\(installResult.log.prefix(1600))\n\nSigned IPA: \(signedPath)"
                        )
                    }
                } catch {
                    signingInProgress = false
                    signingAlert = KittyStoreSigningAlert(
                        title: "Signed IPA Ready",
                        message: "SideStore AltSign signed the IPA, but the pairing file could not be read for \(postSigningAction.transferVerb).\n\(error.localizedDescription)\n\nSigned IPA: \(signedPath)"
                    )
                }
            } else {
                signingAlert = KittyStoreSigningAlert(
                    title: "Signed IPA Ready",
                    message: "SideStore AltSign signed the IPA.\n\nSigned IPA: \(signedPath)\n\n\(signingResult.log.prefix(1200))"
                )
            }
        }
    }

    @MainActor
    private func loadInstalledDeviceApps() {
        guard let pairingPath = importedPairingFile?.stagedPath else {
            signingAlert = KittyStoreSigningAlert(title: "Pairing File Missing", message: "Import the SideStore-style iOS pairing file before loading installed apps.")
            return
        }
        guard KittyStoreMinimuxerBridge.isLinked else {
            signingAlert = KittyStoreSigningAlert(title: "Minimuxer Missing", message: "This IPA was not linked with the SideStore minimuxer bridge, so installed app browsing cannot run.")
            return
        }

        installedDeviceAppsInProgress = true
        installedDeviceAppsMessage = "Loading installed apps from SideStore minimuxer."
        taskBag.run {
            do {
                let pairing = try String(contentsOfFile: pairingPath, encoding: .utf8)
                let result = await KittyStoreMinimuxerBridge.listInstalledApps(
                    pairingFileContents: pairing,
                    consoleLoggingEnabled: true
                )
                installedDeviceAppsInProgress = false
                buildKitStatus = await LitterBuildKit.shared.status(checkRevocation: true)
                installedDeviceApps = result.apps
                if result.exitCode == 0 {
                    installedDeviceAppsMessage = "Loaded \(result.apps.count) user-installed app(s) from the connected device."
                } else {
                    installedDeviceAppsMessage = "Failed to load installed apps: \(result.status)."
                    signingAlert = KittyStoreSigningAlert(
                        title: "Device Apps Failed",
                        message: "Status: \(result.status)\n\n\(result.log.prefix(1600))"
                    )
                }
            } catch {
                installedDeviceAppsInProgress = false
                installedDeviceAppsMessage = "Could not read the imported pairing file."
                signingAlert = KittyStoreSigningAlert(title: "Device Apps Failed", message: "Could not read the imported pairing file.\n\(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func removeSelectedAppFromDevice(_ request: KittyStoreRemovalRequest) {
        guard let pairingPath = importedPairingFile?.stagedPath else {
            signingAlert = KittyStoreSigningAlert(title: "Pairing File Missing", message: "Import the SideStore-style iOS pairing file before removing an app from the device.")
            return
        }
        guard KittyStoreMinimuxerBridge.isLinked else {
            signingAlert = KittyStoreSigningAlert(title: "Minimuxer Missing", message: "This IPA was not linked with the SideStore minimuxer bridge, so direct on-device remove cannot run.")
            return
        }

        deviceActionInProgress = true
        taskBag.run {
            do {
                let pairing = try String(contentsOfFile: pairingPath, encoding: .utf8)
                let result = await KittyStoreMinimuxerBridge.removeApp(
                    bundleIdentifier: request.bundleIdentifier,
                    pairingFileContents: pairing,
                    consoleLoggingEnabled: true
                )
                deviceActionInProgress = false
                buildKitStatus = await LitterBuildKit.shared.status(checkRevocation: true)
                if result.exitCode == 0 {
                    installedDeviceApps.removeAll { $0.bundleIdentifier == request.bundleIdentifier }
                    installedDeviceAppsMessage = "Removed \(request.name) from the connected device."
                    signingAlert = KittyStoreSigningAlert(
                        title: "Removed",
                        message: "SideStore minimuxer removed \(request.name).\n\n\(result.log.prefix(1400))"
                    )
                } else {
                    signingAlert = KittyStoreSigningAlert(
                        title: "Remove Failed",
                        message: "Status: \(result.status)\n\n\(result.log.prefix(1600))"
                    )
                }
            } catch {
                deviceActionInProgress = false
                signingAlert = KittyStoreSigningAlert(title: "Remove Failed", message: "Could not read the imported pairing file.\n\(error.localizedDescription)")
            }
        }
    }

    private func parsedRemoveDylibNames() -> [String] {
        removeDylibNames
            .components(separatedBy: CharacterSet(charactersIn: "\n,"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func parsedRemoveAppFiles() -> [String] {
        removeAppFiles
            .components(separatedBy: CharacterSet(charactersIn: "\n,"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
                "removeDylibs": parsedRemoveDylibNames(),
                "removeFiles": parsedRemoveAppFiles(),
                "frameworksAndPlugins": frameworksAndPlugins.map(\.stagedPath),
                "tweaks": tweaks.map(\.stagedPath),
                "entitlements": entitlementsText
            ],
            "properties": [
                "appAppearance": appAppearance.rawValue,
                "minimumAppRequirement": minimumAppRequirement.rawValue,
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
                "postSigningAction": postSigningAction.rawValue,
                "installAfterSigning": postSigningAction == .install,
                "refreshAfterSigning": postSigningAction == .refresh,
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

    private func installedDeviceAppRow(_ installedApp: KittyStoreInstalledDeviceApp) -> some View {
        let matchingSourceApp = apps.first { $0.bundleIdentifier == installedApp.bundleIdentifier }
        let latest = matchingSourceApp?.versions.first

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LitterTheme.surfaceLight.opacity(0.55))
                    Text(String(installedApp.displayName.prefix(1)).uppercased())
                        .litterFont(.title3, weight: .bold)
                        .foregroundStyle(LitterTheme.accent)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(installedApp.displayName)
                        .litterFont(.headline, weight: .semibold)
                        .foregroundStyle(LitterTheme.textPrimary)
                        .lineLimit(1)
                    Text(installedApp.bundleIdentifier)
                        .litterMonoFont(size: 11, weight: .regular)
                        .foregroundStyle(LitterTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !installedApp.path.isEmpty {
                        Text(installedApp.path)
                            .litterMonoFont(size: 10, weight: .regular)
                            .foregroundStyle(LitterTheme.textMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)
                statusPill(installedApp.displayVersion, color: matchingSourceApp == nil ? LitterTheme.warning : LitterTheme.success)
            }

            HStack(spacing: 8) {
                if let matchingSourceApp, let latest {
                    compactButton("Refresh", icon: "arrow.triangle.2.circlepath") {
                        selectedSourceAppID = matchingSourceApp.bundleIdentifier
                        postSigningAction = .refresh
                        downloadSourceIPAForSigning(storeApp: matchingSourceApp, version: latest, openSigning: true)
                    }
                } else {
                    statusPill("No Source Match", color: LitterTheme.warning)
                }
                compactButton("Remove", icon: "trash") {
                    pendingDeviceRemoval = KittyStoreRemovalRequest(name: installedApp.displayName, bundleIdentifier: installedApp.bundleIdentifier)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LitterTheme.surfaceLight.opacity(0.34), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func sourceAppRow(_ storeApp: KittyStoreApp) -> some View {
        let latest = storeApp.versions.first
        let isSelected = storeApp.bundleIdentifier == app?.bundleIdentifier

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LitterTheme.surfaceLight.opacity(0.55))
                    Text(String(storeApp.name.prefix(1)).uppercased())
                        .litterFont(.title3, weight: .bold)
                        .foregroundStyle(LitterTheme.accent)
                }
                .frame(width: 52, height: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? LitterTheme.accent.opacity(0.9) : LitterTheme.border.opacity(0.45), lineWidth: isSelected ? 1.2 : 0.8)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(storeApp.name)
                        .litterFont(.headline, weight: .semibold)
                        .foregroundStyle(LitterTheme.textPrimary)
                        .lineLimit(1)
                    Text(storeApp.subtitle ?? storeApp.developerName ?? storeApp.bundleIdentifier)
                        .litterFont(.caption)
                        .foregroundStyle(LitterTheme.textSecondary)
                        .lineLimit(2)
                    Text(storeApp.bundleIdentifier)
                        .litterMonoFont(size: 11, weight: .regular)
                        .foregroundStyle(LitterTheme.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if isSelected {
                    statusPill("Selected", color: LitterTheme.success)
                } else if let version = latest?.version {
                    statusPill(version, color: LitterTheme.accent)
                }
            }

            if let description = storeApp.localizedDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                Text(description)
                    .litterFont(.caption)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let latest {
                HStack(spacing: 8) {
                    compactButton(isSelected ? "Selected" : "View", icon: isSelected ? "checkmark.circle.fill" : "rectangle.and.text.magnifyingglass") {
                        selectSourceApp(storeApp)
                    }
                    if let sideStoreURL = installerURL(scheme: "sidestore", host: "install", targetURL: latest.downloadURL) {
                        compactButton("SideStore", icon: "square.and.arrow.down") { openURL(sideStoreURL) }
                    }
                    compactButton(sourceIPADownloadInProgress ? "Wait" : "Sign", icon: "signature") {
                        downloadSourceIPAForSigning(storeApp: storeApp, version: latest, openSigning: true)
                    }
                    compactButton("Copy", icon: "doc.on.doc") {
                        UIPasteboard.general.string = latest.downloadURL
                        copiedMessage = "Copied \(storeApp.name) IPA link"
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LitterTheme.surfaceLight.opacity(isSelected ? 0.48 : 0.34),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? LitterTheme.accent.opacity(0.5) : Color.clear, lineWidth: 0.8)
        )
    }

    private func versionRow(_ version: KittyStoreVersion) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(selectedAppName) \(version.version ?? "Unknown")")
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
                if let shortSHA = version.shortSHA256 {
                    statusPill(shortSHA, color: LitterTheme.textSecondary)
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
                if let storeApp = app {
                    compactButton(sourceIPADownloadInProgress ? "Wait" : "Sign", icon: "signature") {
                        downloadSourceIPAForSigning(storeApp: storeApp, version: version, openSigning: true)
                    }
                }
                compactButton("Copy", icon: "doc.on.doc") {
                    UIPasteboard.general.string = version.downloadURL
                    copiedMessage = "Copied \(selectedAppName) \(version.version ?? "IPA") link"
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LitterTheme.surfaceLight.opacity(0.34), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func settingsTextField(
        _ title: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        autocapitalization: TextInputAutocapitalization = .never
    ) -> some View {
        TextField(title, text: text)
            .keyboardType(keyboardType)
            .textContentType(textContentType)
            .textInputAutocapitalization(autocapitalization)
            .autocorrectionDisabled()
            .padding(10)
            .background(LitterTheme.surfaceLight.opacity(0.3), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func settingsSecureField(_ title: String, text: Binding<String>) -> some View {
        SecureField(title, text: text)
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(10)
            .background(LitterTheme.surfaceLight.opacity(0.3), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func messageBlock(_ message: String) -> some View {
        Text(message)
            .litterMonoFont(size: 11, weight: .regular)
            .foregroundStyle(LitterTheme.textSecondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LitterTheme.surfaceLight.opacity(0.28), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

    private func navigationActionRow<Destination: View>(_ title: String, detail: String, icon: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            actionRowLabel(title, detail: detail, icon: icon, enabled: true)
        }
        .buttonStyle(.plain)
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

private enum KittyStoreTab: String, CaseIterable, Identifiable {
    case news
    case sources
    case browse
    case myApps
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .news: return "News"
        case .sources: return "Sources"
        case .browse: return "Browse"
        case .myApps: return "My Apps"
        case .settings: return "Settings"
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

private enum KittyStoreAppAppearance: String, CaseIterable, Identifiable {
    case `default` = "default"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .default: return "Default"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

private enum KittyStoreMinimumRequirement: String, CaseIterable, Identifiable {
    case `default` = "default"
    case iOS16 = "16.0"
    case iOS15 = "15.0"
    case iOS14 = "14.0"
    case iOS13 = "13.0"
    case iOS12 = "12.0"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .default: return "Default"
        default: return rawValue
        }
    }
}

private enum KittyStorePostSigningAction: String, CaseIterable, Identifiable {
    case none
    case install
    case refresh

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .install: return "Install"
        case .refresh: return "Refresh"
        }
    }

    var requiresDeviceTransfer: Bool { self != .none }

    var transferVerb: String {
        switch self {
        case .none: return "save"
        case .install: return "install"
        case .refresh: return "refresh"
        }
    }

    var completedVerb: String {
        switch self {
        case .none: return "saved"
        case .install: return "installed"
        case .refresh: return "refreshed"
        }
    }

    var successTitle: String {
        switch self {
        case .none: return "Signed IPA Ready"
        case .install: return "Installed"
        case .refresh: return "Refreshed"
        }
    }

    var failureTitle: String {
        switch self {
        case .none: return "Signing Failed"
        case .install: return "Install Failed"
        case .refresh: return "Refresh Failed"
        }
    }

    var minimuxerAction: KittyStoreMinimuxerBridge.Action? {
        switch self {
        case .none: return nil
        case .install: return .install
        case .refresh: return .refresh
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
    case certificate
    case sideStoreAccount
    case provisioningProfile
    case pairingFile
    case existingDylibs
    case frameworksAndPlugins
    case tweaks

    var title: String {
        switch self {
        case .ipa: return "IPA"
        case .certificate: return "Certificate"
        case .sideStoreAccount: return "SideStore Account"
        case .provisioningProfile: return "Provisioning Profile"
        case .pairingFile: return "Pairing File"
        case .existingDylibs: return "Existing Dylibs"
        case .frameworksAndPlugins: return "Frameworks & PlugIns"
        case .tweaks: return "Tweaks"
        }
    }

    var allowsMultipleSelection: Bool {
        switch self {
        case .ipa, .certificate, .sideStoreAccount, .provisioningProfile, .pairingFile: return false
        case .existingDylibs, .frameworksAndPlugins, .tweaks: return true
        }
    }

    var allowedContentTypes: [UTType] {
        switch self {
        case .ipa:
            return [UTType(filenameExtension: "ipa") ?? .data, .zip, .data]
        case .certificate:
            return [UTType(filenameExtension: "p12") ?? .data, .data]
        case .sideStoreAccount:
            return [UTType(filenameExtension: "sideconf") ?? .data, .json, .data]
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

private struct KittyStoreRemovalRequest: Identifiable {
    let id = UUID()
    var name: String
    var bundleIdentifier: String
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
        case .idle: return "The source has not loaded yet."
        case .loading: return "Loading source."
        case .loaded: return "Source loaded."
        case .failed(let message): return "Could not load source: \(message)"
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

private struct KittyStoreApp: Decodable, Equatable, Identifiable {
    var name: String
    var bundleIdentifier: String
    var developerName: String?
    var iconURL: String?
    var subtitle: String?
    var localizedDescription: String?
    var versions: [KittyStoreVersion]

    var id: String { bundleIdentifier }
}

private struct KittyStoreVersion: Decodable, Equatable, Identifiable {
    var version: String?
    var buildVersion: String?
    var date: String?
    var localizedDescription: String?
    var downloadURL: String
    var size: Int64?
    var minOSVersion: String?
    var sha256: String?

    var id: String { "\(version ?? "unknown")-\(buildVersion ?? "0")-\(downloadURL)" }

    var cleanedDescription: String {
        localizedDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var normalizedSHA256: String? {
        LitterDownloadSupport.normalizedSHA256(sha256)
    }

    var shortSHA256: String? {
        normalizedSHA256.map { "SHA \(String($0.prefix(12)))" }
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
    @Binding var appAppearance: KittyStoreAppAppearance
    @Binding var minimumAppRequirement: KittyStoreMinimumRequirement
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
    @Binding var postSigningAction: KittyStorePostSigningAction
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
                Picker("Appearance", selection: $appAppearance) {
                    ForEach(KittyStoreAppAppearance.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                Picker("Minimum iOS", selection: $minimumAppRequirement) {
                    ForEach(KittyStoreMinimumRequirement.allCases) { value in
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
                Picker("After Signing", selection: $postSigningAction) {
                    ForEach(KittyStorePostSigningAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }
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
