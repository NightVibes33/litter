import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private final class KittyStoreAppleIDVerificationRequest: Identifiable, @unchecked Sendable {
    let id = UUID()
    private let callback: (String?) -> Void

    init(callback: @escaping (String?) -> Void) {
        self.callback = callback
    }

    func submit(_ code: String?) {
        callback(code)
    }
}

struct KittyStoreView: View {
    @Environment(\.openURL) private var openURL
    @StateObject private var taskBag = ViewTaskBag()
    @State private var sources: [KittyStoreSource] = []
    @State private var sourcePhase: KittyStoreSourcePhase = .idle
    @AppStorage("kittystore.source.urls.v1") private var storedSourceURLsJSON = ""
    @AppStorage("kittystore.backgroundRefresh.v1") private var kittyStoreBackgroundRefresh = true
    @AppStorage("kittystore.disableIdleTimeout.v1") private var kittyStoreDisableIdleTimeout = true
    @AppStorage("kittystore.allowSiriRefresh.v1") private var kittyStoreAllowSiriRefresh = false
    @AppStorage("kittystore.pairing.path.v1") private var storedPairingFilePath = ""
    @AppStorage("kittystore.pairing.name.v1") private var storedPairingFileName = ""
    @AppStorage("kittystore.pairing.size.v1") private var storedPairingFileSize = ""
    @AppStorage("kittystore.provisioning.path.v1") private var storedProvisioningProfilePath = ""
    @AppStorage("kittystore.provisioning.name.v1") private var storedProvisioningProfileName = ""
    @AppStorage("kittystore.provisioning.size.v1") private var storedProvisioningProfileSize = ""
    @State private var copiedMessage: String?
    @State private var shareItem: KittyStoreShareItem?
    @State private var showingAppleIDSignInSheet = false
    @State private var showingAppleIDTwoFactorPrompt = false
    @State private var appleIDVerificationRequest: KittyStoreAppleIDVerificationRequest?
    @State private var appleIDTwoFactorWasCancelled = false
    @State private var appleIDLoginInProgress = false
    @State private var selectedTab: KittyStoreTab = .news
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
    @State private var sourceURLInput = ""
    @State private var sourceActionMessage: String?
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

    private static var defaultSourceURLs: [String] {
        [
            "https://community-apps.sidestore.io/sidecommunity.json",
            AppReleaseSource.current.stableSourceURLString
        ]
    }

    private static func decodeSourceURLs(_ text: String) -> [String] {
        guard let data = text.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            return defaultSourceURLs
        }
        let urls = uniqueSourceURLs(decoded.compactMap(normalizedSourceURL))
        return urls.isEmpty ? defaultSourceURLs : urls
    }

    private static func encodeSourceURLs(_ urls: [String]) -> String {
        let normalized = uniqueSourceURLs(urls.compactMap(normalizedSourceURL))
        guard let data = try? JSONEncoder().encode(normalized),
              let text = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return text
    }

    private static func uniqueSourceURLs(_ urls: [String]) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []
        for url in urls {
            let key = url.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(url)
        }
        return unique
    }

    private static func normalizedSourceURL(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let components = URLComponents(string: trimmed),
           let scheme = components.scheme?.lowercased(),
           ["sidestore", "altstore"].contains(scheme),
           let sourceURL = components.queryItems?.first(where: { $0.name == "url" })?.value {
            return normalizedSourceURL(sourceURL)
        }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return nil
        }
        return url.absoluteString
    }

    private var source: KittyStoreSource? {
        if let selectedSourceURL = app?.sourceURL {
            return sources.first { $0.resolvedSourceURL == selectedSourceURL }
        }
        return sources.first
    }
    private var apps: [KittyStoreApp] { sources.flatMap(\.apps) }
    private var newsItems: [KittyStoreNewsItem] {
        let sourceNews = sources.flatMap(\.news)
        let appReleaseNews = apps.compactMap(latestReleaseNewsItem(for:))
        return (sourceNews + appReleaseNews)
            .sorted { ($0.date ?? "") > ($1.date ?? "") }
    }
    private var app: KittyStoreApp? {
        if let selectedSourceAppID,
           let selected = apps.first(where: { $0.id == selectedSourceAppID || $0.bundleIdentifier == selectedSourceAppID }) {
            return selected
        }
        return apps.first
    }
    private var selectedAppName: String { app?.name ?? "App" }
    private var versions: [KittyStoreVersion] { app?.versions ?? [] }
    private var latestVersion: KittyStoreVersion? { versions.first }
    private var sourceURL: String { app?.sourceURL ?? source?.resolvedSourceURL ?? AppReleaseSource.current.stableSourceURLString }
    private var configuredSourceURLs: [String] { Self.decodeSourceURLs(storedSourceURLsJSON) }

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
        .sheet(isPresented: $showingAppleIDSignInSheet) {
            NavigationStack {
                appleIDSignInWorkspace
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { showingAppleIDSignInSheet = false }
                        }
                    }
            }
            .background(LitterTheme.backgroundGradient.ignoresSafeArea())
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
        .alert("Please enter the 6-digit verification code that was sent to your Apple devices.", isPresented: $showingAppleIDTwoFactorPrompt) {
            TextField("Verification code", text: $appleIDTwoFactorCodeInput)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
            Button("Cancel", role: .cancel) {
                cancelAppleIDVerificationCode()
            }
            Button("Continue") {
                submitAppleIDVerificationCode()
            }
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
            restorePersistedImports()
            if sourceURLInput.isEmpty { sourceURLInput = configuredSourceURLs.first ?? "" }
            await refreshAll()
            await refreshAnisetteServers(showSuccess: false)
        }
        .onDisappear {
            taskBag.cancelAll()
        }
    }

    private var newsWorkspace: some View {
        storeScroll(spacing: 18) {
            if newsItems.isEmpty {
                latestNewsPanel
            } else {
                ForEach(newsItems) { newsItem in
                    newsItemCard(newsItem)
                }
            }
        }
    }

    private var sourcesWorkspace: some View {
        storeScroll {
            sourcePanel
        }
    }

    private var browseWorkspace: some View {
        storeScroll {
            sourceAppsPanel
        }
    }

    private var myAppsWorkspace: some View {
        storeScroll {
            myAppsPanel
        }
    }

    private var settingsWorkspace: some View {
        storeScroll(spacing: 18) {
            accountSettingsPanel
            signingSettingsPanel
            transportSettingsPanel
            storeOptionsSettingsPanel
        }
    }

    private func storeScroll<Content: View>(spacing: CGFloat = 14, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: spacing) {
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

                actionRow("Load Installed Apps", detail: installedDeviceAppsActionDetail, icon: "iphone.gen3", enabled: canLoadInstalledDeviceApps) {
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


    private func newsItemCard(_ item: KittyStoreNewsItem) -> some View {
        newsArticleCard(
            title: item.title,
            caption: item.caption,
            tint: newsTintColor(item.tintColor),
            symbol: item.appID == nil ? "newspaper.fill" : "square.and.arrow.down.fill",
            footer: [item.sourceName, item.displayDate].compactMap { $0 }.joined(separator: " - "),
            imageURL: item.imageURL
        ) {
            newsDestinationURL(for: item)
        }
    }

    private func newsArticleCard(
        title: String,
        caption: String,
        tint: Color,
        symbol: String,
        footer: String? = nil,
        imageURL: String? = nil,
        destination: @escaping () -> URL? = { nil }
    ) -> some View {
        Button {
            if let url = destination() {
                openURL(url)
            }
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: symbol)
                    .font(.system(size: 92, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(18)
                if let imageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(width: 74, height: 74)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .shadow(color: .black.opacity(0.24), radius: 10, y: 4)
                        default:
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(18)
                }

                VStack(alignment: .leading, spacing: 10) {
                    if let footer, !footer.isEmpty {
                        Text(footer)
                            .litterFont(.caption, weight: .semibold)
                            .foregroundStyle(Color.white.opacity(0.82))
                            .textCase(.uppercase)
                    }
                    Text(title)
                        .litterFont(.title2, weight: .bold)
                        .foregroundStyle(Color.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(caption)
                        .litterFont(.subheadline, weight: .medium)
                        .foregroundStyle(Color.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .frame(maxWidth: .infinity, minHeight: 178, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
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
        panel(title: "Sources", icon: "list.bullet.rectangle") {
            VStack(spacing: 10) {
                settingsTextField("Source URL", text: $sourceURLInput, keyboardType: .URL)

                actionRow("Add Source", detail: "Add any SideStore or AltStore source URL to KittyStore.", icon: "plus.circle.fill", enabled: !sourceURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    addSourceURL()
                }

                actionRow("Refresh Sources", detail: sourcePhase.message, icon: "arrow.clockwise") {
                    taskBag.run { await refreshSource() }
                }

                if configuredSourceURLs.isEmpty {
                    emptyState("No sources configured. Add a SideStore or AltStore source URL.")
                } else {
                    ForEach(configuredSourceURLs, id: \.self) { url in
                        sourceURLRow(url)
                    }
                }

                actionRow("Restore Recommended Sources", detail: "Use KittyLitter plus SideStore community defaults.", icon: "arrow.counterclockwise") {
                    resetSourceURLs()
                }

                if let sourceActionMessage, !sourceActionMessage.isEmpty {
                    messageBlock(sourceActionMessage)
                }
                copiedNotice
            }
        }
    }

    private func sourceURLRow(_ url: String) -> some View {
        let loadedSource = sources.first { $0.resolvedSourceURL == url }
        let title = loadedSource?.name ?? sourceHost(for: url)
        let detail = loadedSource.map { "\($0.apps.count) app(s), \($0.news.count) news item(s)" } ?? url

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: loadedSource == nil ? "link" : "checkmark.circle.fill")
                    .foregroundStyle(loadedSource == nil ? LitterTheme.textMuted : LitterTheme.success)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .litterFont(.subheadline, weight: .semibold)
                        .foregroundStyle(LitterTheme.textPrimary)
                        .lineLimit(1)
                    Text(detail)
                        .litterFont(.caption)
                        .foregroundStyle(LitterTheme.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                compactButton("Open", icon: "safari") {
                    if let url = URL(string: url) { openURL(url) }
                }
                compactButton("Copy", icon: "doc.on.doc") {
                    UIPasteboard.general.string = url
                    copiedMessage = "Copied source URL"
                }
                compactButton("Remove", icon: "trash") {
                    removeSourceURL(url)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LitterTheme.surfaceLight.opacity(0.34), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var accountSettingsPanel: some View {
        let account = NyxianAppleIDStore.load()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                settingsSectionHeader("Account")
                Spacer(minLength: 0)
                if account != nil {
                    Button("SIGN OUT") {
                        clearKittyStoreAppleID()
                    }
                    .buttonStyle(.plain)
                    .litterFont(.caption, weight: .heavy)
                    .foregroundStyle(LitterTheme.accent)
                }
            }

            if let account {
                signedInAccountCard(account)
            } else {
                Button {
                    showingAppleIDSignInSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Text("Sign in with Apple ID")
                            .litterFont(.headline, weight: .bold)
                            .foregroundStyle(LitterTheme.textPrimary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .litterFont(.headline, weight: .bold)
                            .foregroundStyle(LitterTheme.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .background(settingsBlockBackground)
                }
                .buttonStyle(.plain)
                Text("Sign in with your Apple ID to download, sign, install, and refresh apps from KittyStore.")
                    .settingsFootnoteStyle()
            }

            if let appleIDActionMessage, !appleIDActionMessage.isEmpty {
                messageBlock(appleIDActionMessage)
            }
        }
    }

    private var appleIDSignInWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome to KittyStore.")
                        .litterFont(size: 38, weight: .heavy)
                        .foregroundStyle(LitterTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Sign in with your Apple ID to get started.")
                        .litterFont(.title3, weight: .semibold)
                        .foregroundStyle(LitterTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 18)

                VStack(alignment: .leading, spacing: 18) {
                    sideStoreField("Apple ID", text: $appleIDEmailInput, placeholder: "name@email.com", keyboardType: .emailAddress, textContentType: .username)
                    sideStoreSecureField("Password", text: $appleIDPasswordInput, placeholder: "••••••••")
                    if appleIDVerificationRequest != nil || !appleIDTwoFactorCodeInput.isEmpty {
                        sideStoreField("Verification Code", text: $appleIDTwoFactorCodeInput, placeholder: "123456", keyboardType: .numberPad, textContentType: .oneTimeCode)
                    }
                    appleIDSignInButton
                }

                if !appleIDTeams.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        settingsSectionHeader("Signing Team")
                        Picker("Signing team", selection: $appleIDTeamIDInput) {
                            ForEach(appleIDTeams, id: \.id) { team in
                                Text(team.displayText).tag(team.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(14)
                        .background(settingsBlockBackground)

                        Button {
                            taskBag.run { await saveSelectedAppleIDTeam() }
                        } label: {
                            Text(appleIDTeamIDInput.isEmpty ? "Save Selected Team" : "Use \(appleIDTeamIDInput)")
                                .litterFont(.headline, weight: .bold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(LitterTheme.accent)
                        .background(LitterTheme.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    settingsSectionHeader("Anisette")
                    Picker("Anisette server", selection: $selectedAnisetteServerAddress) {
                        ForEach(anisetteServers) { server in
                            Text(server.displayName).tag(server.address)
                        }
                        Text("Custom").tag(NyxianAnisetteServerDirectory.customSelectionID)
                    }
                    .pickerStyle(.menu)
                    .padding(14)
                    .background(settingsBlockBackground)

                    if selectedAnisetteServerAddress == NyxianAnisetteServerDirectory.customSelectionID {
                        sideStoreField("Custom Anisette Server", text: $appleIDAnisetteURLInput, placeholder: NyxianAnisetteServerDirectory.defaultServerURL, keyboardType: .URL)
                    }
                    sideStoreField("Server List", text: $anisetteServerListURLInput, placeholder: NyxianAnisetteServerDirectory.officialListURL, keyboardType: .URL)
                    actionRow("Refresh Anisette Servers", detail: "Reload the SideStore Anisette server list.", icon: "arrow.clockwise.circle") {
                        taskBag.run { await refreshAnisetteServers(showSuccess: true) }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Why do we need this?")
                        .litterFont(.title3, weight: .heavy)
                        .foregroundStyle(LitterTheme.textPrimary)
                    Text("Your Apple ID is used to configure apps so they can be installed on this device. Your credentials are stored securely in this device's Keychain and sent only to Apple for authentication.")
                        .litterFont(.body, weight: .medium)
                        .foregroundStyle(LitterTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let appleIDActionMessage, !appleIDActionMessage.isEmpty {
                    messageBlock(appleIDActionMessage)
                }
                if let anisetteServerMessage, !anisetteServerMessage.isEmpty {
                    messageBlock(anisetteServerMessage)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 34)
        }
        .scrollContentBackground(.hidden)
        .background(LitterTheme.backgroundGradient.ignoresSafeArea())
    }

    private var supportSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingsSectionHeader("Support Us")
            navigationActionRow("Support the team", detail: "Support KittyLitter by helping fund ongoing development.", icon: "heart.fill") {
                TipJarView()
            }
        }
    }

    private var displaySettingsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingsSectionHeader("Display")
            actionRow("Change App Icon", detail: "Choose an alternate KittyLitter app icon when alternate icons are bundled.", icon: "app.badge") {
                signingAlert = KittyStoreSigningAlert(title: "App Icons", message: "Alternate KittyStore icons are not bundled in this build yet.")
            }
        }
    }

    private var refreshSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingsSectionHeader("Refreshing Apps")
            VStack(spacing: 0) {
                settingsToggleRow("Background Refresh", isOn: $kittyStoreBackgroundRefresh)
                settingsDivider
                settingsToggleRow("Disable Idle Timeout", isOn: $kittyStoreDisableIdleTimeout)
                settingsDivider
                settingsToggleRow("Allow Siri To Refresh Apps...", isOn: $kittyStoreAllowSiriRefresh)
            }
            .background(settingsBlockBackground)
            Text("Enable Background Refresh to automatically refresh apps in the background when connected to Wi-Fi.")
                .settingsFootnoteStyle()
            Text("Enable Disable Idle Timeout to keep your device awake during a refresh or install of any apps.")
                .settingsFootnoteStyle()
            actionRow("How it works", detail: "Review the LocalDevVPN, pairing file, and refresh requirements.", icon: "questionmark.circle") {
                selectedTab = .settings
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

                readinessRow(
                    "Provisioning Profile (.mobileprovision)",
                    detail: importedProvisioningProfile?.displayName ?? "Import the second Feather certificate-pair file for per-app signing.",
                    state: importedProvisioningProfile != nil
                )
                actionRow("Import .mobileprovision", detail: "Choose the provisioning profile that matches the app and certificate.", icon: "doc.badge.gearshape") {
                    presentImporter(.provisioningProfile)
                }
                actionRow("Clear .mobileprovision", detail: "Remove the saved provisioning profile from KittyStore.", icon: "trash", enabled: importedProvisioningProfile != nil) {
                    clearPersistedProvisioningProfile()
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
                actionRow("Clear Pairing File", detail: "Remove the saved pairing file from KittyStore.", icon: "trash", enabled: importedPairingFile != nil) {
                    clearPersistedPairingFile()
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

    private var storeOptionsSettingsPanel: some View {
        panel(title: "Store Options", icon: "slider.horizontal.3") {
            VStack(spacing: 10) {
                VStack(spacing: 0) {
                    settingsToggleRow("Background Refresh", isOn: $kittyStoreBackgroundRefresh)
                    settingsDivider
                    settingsToggleRow("Disable Idle Timeout", isOn: $kittyStoreDisableIdleTimeout)
                    settingsDivider
                    settingsToggleRow("Allow Siri To Refresh Apps...", isOn: $kittyStoreAllowSiriRefresh)
                }
                .background(settingsBlockBackground)
                actionRow("Change App Icon", detail: "Choose an alternate KittyLitter app icon when alternate icons are bundled.", icon: "app.badge") {
                    signingAlert = KittyStoreSigningAlert(title: "App Icons", message: "Alternate KittyStore icons are not bundled in this build yet.")
                }
                navigationActionRow("Support the team", detail: "Support KittyLitter by helping fund ongoing development.", icon: "heart.fill") {
                    TipJarView()
                }
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
        sourceHost(for: sourceURL)
    }

    private func sourceHost(for url: String) -> String {
        URL(string: url)?.host ?? "source feed"
    }

    private func latestReleaseNewsItem(for storeApp: KittyStoreApp) -> KittyStoreNewsItem? {
        guard let latest = storeApp.versions.first else { return nil }
        let versionText = latest.version ?? latest.buildVersion ?? "Latest"
        let notes = latest.cleanedDescription
        let caption: String
        if !notes.isEmpty {
            caption = shortNotes(notes)
        } else if let subtitle = storeApp.subtitle, !subtitle.isEmpty {
            caption = subtitle
        } else if let description = storeApp.localizedDescription, !description.isEmpty {
            caption = shortNotes(description)
        } else {
            caption = "New source release is available to install or sign."
        }
        return KittyStoreNewsItem(
            identifier: "release-\(storeApp.bundleIdentifier)-\(latest.id)",
            date: latest.date,
            title: "\(storeApp.name) \(versionText)",
            caption: caption,
            tintColor: nil,
            imageURL: storeApp.iconURL,
            externalURL: latest.downloadURL,
            appID: storeApp.bundleIdentifier,
            sourceName: storeApp.sourceName,
            sourceURL: storeApp.sourceURL
        )
    }

    private func resolvedSourceAssetURL(_ rawValue: String?, sourceURL: String) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute.absoluteString
        }
        if trimmed.hasPrefix("//"), let scheme = URL(string: sourceURL)?.scheme {
            return "\(scheme):\(trimmed)"
        }
        guard let base = URL(string: sourceURL), let resolved = URL(string: trimmed, relativeTo: base) else {
            return trimmed
        }
        return resolved.absoluteURL.absoluteString
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

    private var localDevVPNReadyForDeviceTransfer: Bool {
        buildKitStatus?.localDevVPNConnected == true
    }

    private var canLoadInstalledDeviceApps: Bool {
        importedPairingFile != nil
            && localDevVPNReadyForDeviceTransfer
            && KittyStoreMinimuxerBridge.isLinked
            && !installedDeviceAppsInProgress
    }

    private var installedDeviceAppsActionDetail: String {
        if importedPairingFile == nil { return "Import a pairing file in Settings before browsing installed apps." }
        if !localDevVPNReadyForDeviceTransfer { return "Enable LocalDevVPN before browsing installed apps." }
        if !KittyStoreMinimuxerBridge.isLinked { return "This IPA was not linked with the SideStore minimuxer bridge." }
        return "Browse installed apps through LocalDevVPN and the SideStore minimuxer bridge."
    }

    private var signingReadinessMessage: String? {
        if sourceIPADownloadInProgress { return sourceIPADownloadMessage ?? "Downloading the selected source IPA." }
        guard importedIPA != nil else { return "Import an IPA before signing." }
        if postSigningAction.requiresDeviceTransfer {
            if selectedSigningMode == .certificate && signingType == .adhoc { return "Ad Hoc signed IPAs cannot be installed or refreshed through SideStore on stock iOS." }
            if importedPairingFile == nil { return "Import the iOS pairing file for SideStore-style \(postSigningAction.transferVerb)." }
            if !KittyStoreMinimuxerBridge.isLinked { return "This build was not linked with the SideStore minimuxer bridge yet." }
            if !localDevVPNReadyForDeviceTransfer { return "Open LocalDevVPN and enable its tunnel before SideStore-style \(postSigningAction.transferVerb)." }
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
            if !localDevVPNReadyForDeviceTransfer { return "Open LocalDevVPN and enable its tunnel before SideStore Apple ID signing." }
            if postSigningAction == .none { return signingInProgress ? "Native signing is running." : "Inputs are ready for SideStore Apple ID signing." }
            return signingInProgress ? "Native signing or transfer is running." : "Inputs are ready for SideStore Apple ID signing and \(postSigningAction.transferVerb)."
        }
    }

    private func refreshAll() async {
        await refreshSource()
        await refreshBuildKitStatus()
    }

    @MainActor
    private func addSourceURL() {
        guard let normalized = Self.normalizedSourceURL(sourceURLInput) else {
            sourceActionMessage = "That is not a valid SideStore or AltStore source URL."
            return
        }
        var urls = configuredSourceURLs
        if !urls.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
            urls.append(normalized)
        }
        storedSourceURLsJSON = Self.encodeSourceURLs(urls)
        sourceURLInput = normalized
        sourceActionMessage = "Added source: \(sourceHost(for: normalized))."
        taskBag.run { await refreshSource() }
    }

    @MainActor
    private func removeSourceURL(_ url: String) {
        let urls = configuredSourceURLs.filter { $0 != url }
        guard !urls.isEmpty else {
            resetSourceURLs()
            return
        }
        storedSourceURLsJSON = Self.encodeSourceURLs(urls)
        sources.removeAll { $0.resolvedSourceURL == url }
        if selectedSourceAppID != nil, !apps.contains(where: { $0.id == selectedSourceAppID || $0.bundleIdentifier == selectedSourceAppID }) {
            selectedSourceAppID = nil
        }
        sourceActionMessage = "Removed source: \(sourceHost(for: url))."
    }

    @MainActor
    private func resetSourceURLs() {
        storedSourceURLsJSON = Self.encodeSourceURLs(Self.defaultSourceURLs)
        sourceURLInput = Self.defaultSourceURLs.first ?? ""
        sourceActionMessage = "Restored KittyStore recommended sources."
        taskBag.run { await refreshSource() }
    }

    private func refreshSource() async {
        let urls = configuredSourceURLs
        guard !urls.isEmpty else {
            sources = []
            sourcePhase = .failed("No source URLs are configured.")
            return
        }

        sourcePhase = .loading
        var loadedSources: [KittyStoreSource] = []
        var failures: [String] = []
        let decoder = JSONDecoder()

        for rawURL in urls {
            guard let url = URL(string: rawURL) else {
                failures.append("\(rawURL): invalid URL")
                continue
            }
            do {
                let data = try await GitHubReleaseAPI.data(url: url, accept: "application/json")
                var decodedSource = try decoder.decode(KittyStoreSource.self, from: data)
                let sourceName = decodedSource.name ?? sourceHost(for: rawURL)
                decodedSource.resolvedSourceURL = rawURL
                if decodedSource.sourceURL == nil { decodedSource.sourceURL = rawURL }
                decodedSource.iconURL = resolvedSourceAssetURL(decodedSource.iconURL, sourceURL: rawURL)
                decodedSource.apps = decodedSource.apps.map { app in
                    var next = app
                    next.sourceName = sourceName
                    next.sourceURL = rawURL
                    next.iconURL = resolvedSourceAssetURL(next.iconURL, sourceURL: rawURL)
                    next.versions = next.versions.map { version in
                        var resolvedVersion = version
                        resolvedVersion.downloadURL = resolvedSourceAssetURL(resolvedVersion.downloadURL, sourceURL: rawURL) ?? resolvedVersion.downloadURL
                        return resolvedVersion
                    }
                    return next
                }
                decodedSource.news = decodedSource.news.map { news in
                    var next = news
                    next.sourceName = sourceName
                    next.sourceURL = rawURL
                    next.imageURL = resolvedSourceAssetURL(next.imageURL, sourceURL: rawURL)
                    next.externalURL = resolvedSourceAssetURL(next.externalURL, sourceURL: rawURL)
                    return next
                }
                loadedSources.append(decodedSource)
            } catch {
                failures.append("\(sourceHost(for: rawURL)): \(error.localizedDescription)")
            }
        }

        sources = loadedSources
        if let selectedSourceAppID,
           !apps.contains(where: { $0.id == selectedSourceAppID || $0.bundleIdentifier == selectedSourceAppID }) {
            self.selectedSourceAppID = nil
        }

        if loadedSources.isEmpty {
            sourcePhase = .failed(failures.joined(separator: "\n"))
        } else if failures.isEmpty {
            let appCount = loadedSources.reduce(0) { $0 + $1.apps.count }
            sourcePhase = .loaded("Loaded \(loadedSources.count) source(s) with \(appCount) app(s).")
        } else {
            let appCount = loadedSources.reduce(0) { $0 + $1.apps.count }
            sourcePhase = .loaded("Loaded \(loadedSources.count) source(s) with \(appCount) app(s). Some sources failed: \(failures.joined(separator: "; "))")
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
    private func restorePersistedImports() {
        if importedPairingFile == nil,
           let file = restoredImportedFile(path: storedPairingFilePath, name: storedPairingFileName, sizeText: storedPairingFileSize) {
            importedPairingFile = file
            installedDeviceAppsMessage = "Restored pairing file: \(file.displayName)."
        }
        if importedProvisioningProfile == nil,
           let file = restoredImportedFile(path: storedProvisioningProfilePath, name: storedProvisioningProfileName, sizeText: storedProvisioningProfileSize) {
            importedProvisioningProfile = file
        }
    }

    private func restoredImportedFile(path: String, name: String, sizeText: String) -> KittyStoreImportedFile? {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
        let resolvedName = name.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : name
        return KittyStoreImportedFile(displayName: resolvedName, stagedPath: path, size: Int64(sizeText), isDirectory: false)
    }

    @MainActor
    private func persistPairingFile(_ file: KittyStoreImportedFile) {
        storedPairingFilePath = file.stagedPath
        storedPairingFileName = file.displayName
        storedPairingFileSize = file.size.map(String.init) ?? ""
    }

    @MainActor
    private func persistProvisioningProfile(_ file: KittyStoreImportedFile) {
        storedProvisioningProfilePath = file.stagedPath
        storedProvisioningProfileName = file.displayName
        storedProvisioningProfileSize = file.size.map(String.init) ?? ""
    }

    @MainActor
    private func clearPersistedPairingFile() {
        importedPairingFile = nil
        installedDeviceApps.removeAll()
        storedPairingFilePath = ""
        storedPairingFileName = ""
        storedPairingFileSize = ""
        installedDeviceAppsMessage = "Removed the pairing file from KittyStore."
    }

    @MainActor
    private func clearPersistedProvisioningProfile() {
        importedProvisioningProfile = nil
        storedProvisioningProfilePath = ""
        storedProvisioningProfileName = ""
        storedProvisioningProfileSize = ""
        certificateActionMessage = "Removed the provisioning profile from KittyStore."
    }

    @MainActor
    private func appleIDVerificationHandler(fallbackCode: String) -> ((@escaping (String?) -> Void) -> Void) {
        { callback in
            let code = fallbackCode.trimmingCharacters(in: .whitespacesAndNewlines)
            if !code.isEmpty {
                callback(code)
                return
            }
            let request = KittyStoreAppleIDVerificationRequest(callback: callback)
            Task { @MainActor in
                appleIDVerificationRequest = request
                appleIDTwoFactorCodeInput = ""
                appleIDActionMessage = "Apple sent a verification code. Enter the 6-digit code to continue."
                showingAppleIDTwoFactorPrompt = true
            }
        }
    }

    @MainActor
    private func submitAppleIDVerificationCode() {
        let trimmedCode = appleIDTwoFactorCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCode.count == 6 else {
            appleIDActionMessage = "Enter the 6-digit verification code from your Apple devices."
            showingAppleIDTwoFactorPrompt = true
            return
        }
        if let request = appleIDVerificationRequest {
            appleIDVerificationRequest = nil
            request.submit(trimmedCode)
        } else {
            taskBag.run { await saveKittyStoreAppleID() }
        }
    }

    @MainActor
    private func cancelAppleIDVerificationCode() {
        appleIDTwoFactorWasCancelled = true
        let request = appleIDVerificationRequest
        appleIDVerificationRequest = nil
        request?.submit(nil)
        appleIDActionMessage = "Apple ID verification cancelled."
    }

    @MainActor
    private func saveKittyStoreAppleID() async {
        let trimmedEmail = appleIDEmailInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = appleIDPasswordInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = appleIDTwoFactorCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !trimmedPassword.isEmpty else {
            appleIDActionMessage = "Enter your Apple ID and password before signing in."
            return
        }
        if !trimmedCode.isEmpty, trimmedCode.count != 6 {
            appleIDActionMessage = "Enter the 6-digit verification code from your Apple devices."
            showingAppleIDTwoFactorPrompt = true
            return
        }

        appleIDTwoFactorWasCancelled = false
        appleIDLoginInProgress = true
        defer { appleIDLoginInProgress = false }

        do {
            let anisetteURL = anisetteURLForLogin
            if KittyStoreSideStoreSigningBridge.isLinked {
                let result = await KittyStoreSideStoreSigningBridge.authenticate(
                    email: trimmedEmail,
                    password: trimmedPassword,
                    requestedTeamID: appleIDTeamIDInput,
                    anisetteServerURL: anisetteURL,
                    twoFactorCode: trimmedCode,
                    verificationHandler: appleIDVerificationHandler(fallbackCode: trimmedCode)
                )
                let summary = try result.get()
                let existingAccount = NyxianAppleIDStore.load()
                let shouldPreserveSideStoreADI = existingAccount?.email.caseInsensitiveCompare(summary.email) == .orderedSame
                let account = try NyxianAppleIDStore.login(
                    email: summary.email,
                    password: trimmedPassword,
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
                appleIDVerificationRequest = nil
                let teamMessage = summary.availableTeams.isEmpty
                    ? "No developer teams were returned."
                    : "Teams found: " + summary.availableTeams.map(\.displayText).joined(separator: ", ") + "."
                appleIDActionMessage = "SideStore Apple ID login verified for \(summary.statusDetail). \(teamMessage)"
                if summary.availableTeams.count <= 1 {
                    showingAppleIDSignInSheet = false
                }
            } else {
                let existingAccount = NyxianAppleIDStore.load()
                let shouldPreserveSideStoreADI = existingAccount?.email.caseInsensitiveCompare(trimmedEmail) == .orderedSame
                let account = try NyxianAppleIDStore.login(
                    email: trimmedEmail,
                    password: trimmedPassword,
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
                appleIDVerificationRequest = nil
                showingAppleIDSignInSheet = false
                appleIDActionMessage = "Apple ID login saved locally, but SideStore AltSign is not linked in this build yet."
            }
            await refreshBuildKitStatus()
        } catch {
            if appleIDTwoFactorWasCancelled {
                appleIDTwoFactorWasCancelled = false
                appleIDActionMessage = "Apple ID verification cancelled."
            } else if appleIDErrorNeedsTwoFactor(error) {
                appleIDActionMessage = "Enter the 6-digit verification code from your Apple devices, then tap Continue."
                showingAppleIDTwoFactorPrompt = true
            } else {
                appleIDActionMessage = "Apple ID login failed: \(error.localizedDescription)"
            }
        }
    }

    private func appleIDErrorNeedsTwoFactor(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain.contains("ALTAppleAPI"), nsError.code == 3018 || nsError.code == 3019 {
            return true
        }
        let message = "\(error.localizedDescription) \(String(describing: error))".lowercased()
        return message.contains("two-factor")
            || message.contains("two factor")
            || message.contains("2fa")
            || message.contains("verification code")
            || message.contains("requires signing in")
            || message.contains("incorrect verification")
            || message.contains("trusted device")
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
        case .provisioningProfile:
            guard let file = files.first else { return }
            do {
                let summary = try validateProvisioningProfile(file, requireCertificateMatch: false)
                importedProvisioningProfile = file
                persistProvisioningProfile(file)
                signingAlert = KittyStoreSigningAlert(title: "Provisioning Profile Ready", message: summary.importMessage)
            } catch {
                importedProvisioningProfile = nil
                signingAlert = KittyStoreSigningAlert(title: "Provisioning Profile Failed", message: error.localizedDescription)
            }
        case .pairingFile:
            importedPairingFile = files.first
            if let file = files.first { persistPairingFile(file) }
            installedDeviceApps.removeAll()
            installedDeviceAppsMessage = files.first.map { "Pairing file imported and saved: \($0.displayName). Load installed apps to browse the device." } ?? "Pairing file imported."
        case .existingDylibs:
            existingDylibs.append(contentsOf: files)
        case .frameworksAndPlugins:
            frameworksAndPlugins.append(contentsOf: files)
        case .tweaks:
            tweaks.append(contentsOf: files)
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
        selectedSourceAppID = storeApp.id
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
        try kind.validateSelectedURL(url, isDirectory: isDirectory)
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
            guard localDevVPNReadyForDeviceTransfer else {
                signingAlert = KittyStoreSigningAlert(title: "LocalDevVPN Required", message: "Open LocalDevVPN and enable its tunnel before direct on-device \(selectedPostSigningAction.transferVerb).")
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
                signingAlert = KittyStoreSigningAlert(title: "Pairing File Missing", message: "Import the SideStore-style iOS pairing file before SideStore Apple ID signing.")
                return
            }
            guard KittyStoreMinimuxerBridge.isLinked else {
                signingAlert = KittyStoreSigningAlert(title: "Minimuxer Missing", message: "This IPA was not linked with the SideStore minimuxer bridge, so direct on-device install and refresh cannot run.")
                return
            }
            guard localDevVPNReadyForDeviceTransfer else {
                signingAlert = KittyStoreSigningAlert(title: "LocalDevVPN Required", message: "Open LocalDevVPN and enable its tunnel before SideStore Apple ID signing.")
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
        guard localDevVPNReadyForDeviceTransfer else {
            signingAlert = KittyStoreSigningAlert(title: "LocalDevVPN Required", message: "Open LocalDevVPN and enable its tunnel before loading installed apps from the device.")
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
        guard localDevVPNReadyForDeviceTransfer else {
            signingAlert = KittyStoreSigningAlert(title: "LocalDevVPN Required", message: "Open LocalDevVPN and enable its tunnel before removing apps from the device.")
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
                    if let matchingSourceApp {
                        KittyStoreAppIconView(app: matchingSourceApp, size: 48)
                    } else {
                        Text(String(installedApp.displayName.prefix(1)).uppercased())
                            .litterFont(.title3, weight: .bold)
                            .foregroundStyle(LitterTheme.accent)
                    }
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
                        selectedSourceAppID = matchingSourceApp.id
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
        let isSelected = storeApp.id == app?.id

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LitterTheme.surfaceLight.opacity(0.55))
                    KittyStoreAppIconView(app: storeApp, size: 52)
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
                    if let sourceName = storeApp.sourceName {
                        Text(sourceName)
                            .litterFont(.caption, weight: .semibold)
                            .foregroundStyle(LitterTheme.accent)
                            .lineLimit(1)
                    }
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

    private var settingsBlockBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(LitterTheme.surfaceLight.opacity(0.38))
    }

    private var settingsDivider: some View {
        Rectangle()
            .fill(LitterTheme.border.opacity(0.48))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    private var appleIDCanSubmit: Bool {
        !appleIDEmailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !appleIDPasswordInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !appleIDLoginInProgress
    }

    private var appleIDSignInButton: some View {
        Button {
            taskBag.run { await saveKittyStoreAppleID() }
        } label: {
            HStack(spacing: 10) {
                if appleIDLoginInProgress {
                    ProgressView()
                        .tint(LitterTheme.textOnAccent)
                }
                Text(appleIDLoginInProgress ? "Signing in" : "Sign in")
                    .litterFont(.headline, weight: .heavy)
            }
            .foregroundStyle(LitterTheme.textOnAccent)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(appleIDCanSubmit ? LitterTheme.accent : LitterTheme.surfaceLight.opacity(0.34))
            )
        }
        .buttonStyle(.plain)
        .disabled(!appleIDCanSubmit)
    }

    private func settingsSectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .litterFont(.caption, weight: .heavy)
            .foregroundStyle(LitterTheme.textSecondary)
            .textCase(.uppercase)
            .accessibilityAddTraits(.isHeader)
    }

    private func signedInAccountCard(_ account: NyxianAppleIDAccount) -> some View {
        VStack(spacing: 0) {
            accountInfoRow("Name", value: appleIDDisplayName(account))
            settingsDivider
            accountInfoRow("Email", value: account.email)
            settingsDivider
            accountInfoRow("Type", value: appleIDAccountType(account))
        }
        .background(settingsBlockBackground)
    }

    private func accountInfoRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .litterFont(.headline, weight: .semibold)
                .foregroundStyle(LitterTheme.textSecondary)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .litterFont(.headline, weight: .heavy)
                .foregroundStyle(LitterTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
    }

    private func appleIDDisplayName(_ account: NyxianAppleIDAccount) -> String {
        let localPart = account.email.split(separator: "@").first.map(String.init) ?? account.email
        let pieces = localPart
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { piece in piece.prefix(1).uppercased() + String(piece.dropFirst()) }
        return pieces.isEmpty ? account.email : pieces.joined(separator: " ")
    }

    private func appleIDAccountType(_ account: NyxianAppleIDAccount) -> String {
        account.teamID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Free Developer Account"
            : "Developer Team " + account.teamID
    }

    private func sideStoreField(
        _ title: String,
        text: Binding<String>,
        placeholder: String,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        autocapitalization: TextInputAutocapitalization = .never
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            settingsSectionHeader(title)
            TextField(placeholder, text: text)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
                .litterFont(.title3, weight: .semibold)
                .foregroundStyle(LitterTheme.textPrimary)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                .background(settingsBlockBackground)
        }
    }

    private func sideStoreSecureField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            settingsSectionHeader(title)
            SecureField(placeholder, text: text)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .litterFont(.title3, weight: .semibold)
                .foregroundStyle(LitterTheme.textPrimary)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                .background(settingsBlockBackground)
        }
    }

    private func settingsToggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .litterFont(.headline, weight: .heavy)
                .foregroundStyle(LitterTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
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

    private func newsDestinationURL(for item: KittyStoreNewsItem) -> URL? {
        guard let target = item.externalURL, !target.isEmpty else { return nil }
        if target.lowercased().contains(".ipa"),
           let sideStoreURL = installerURL(scheme: "sidestore", host: "install", targetURL: target) {
            return sideStoreURL
        }
        return URL(string: target)
    }

    private func newsTintColor(_ value: String?) -> Color {
        guard let value else { return LitterTheme.accent }
        let sanitized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard sanitized.count == 6, let number = Int(sanitized, radix: 16) else { return LitterTheme.accent }
        let red = Double((number >> 16) & 0xff) / 255.0
        let green = Double((number >> 8) & 0xff) / 255.0
        let blue = Double(number & 0xff) / 255.0
        return Color(red: red, green: green, blue: blue)
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

private extension View {
    func settingsFootnoteStyle() -> some View {
        self
            .litterFont(.callout, weight: .semibold)
            .foregroundStyle(LitterTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
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
    case provisioningProfile
    case pairingFile
    case existingDylibs
    case frameworksAndPlugins
    case tweaks

    private static let ipaType = UTType(filenameExtension: "ipa") ?? UTType(importedAs: "com.sigkitten.litter.ipa", conformingTo: .zip)
    private static let p12Type = UTType(filenameExtension: "p12") ?? UTType(importedAs: "com.rsa.pkcs-12", conformingTo: .data)
    private static let pfxType = UTType(filenameExtension: "pfx") ?? UTType(importedAs: "com.rsa.pkcs-12", conformingTo: .data)
    private static let mobileProvisionType = UTType(filenameExtension: "mobileprovision") ?? UTType(importedAs: "com.apple.mobileprovision", conformingTo: .data)
    private static let provisionProfileType = UTType(filenameExtension: "provisionprofile") ?? UTType(importedAs: "com.apple.mobileprovision", conformingTo: .data)
    private static let mobileDevicePairingType = UTType(filenameExtension: "mobiledevicepairing") ?? UTType(importedAs: "com.apple.mobiledevicepairing", conformingTo: .data)
    private static let pairingType = UTType(filenameExtension: "pairing") ?? UTType(importedAs: "com.apple.mobiledevicepairing", conformingTo: .data)
    private static let plistType = UTType(filenameExtension: "plist") ?? .propertyList

    var title: String {
        switch self {
        case .ipa: return "IPA"
        case .certificate: return "Certificate"
        case .provisioningProfile: return "Provisioning Profile"
        case .pairingFile: return "Pairing File"
        case .existingDylibs: return "Existing Dylibs"
        case .frameworksAndPlugins: return "Frameworks & PlugIns"
        case .tweaks: return "Tweaks"
        }
    }

    var allowsMultipleSelection: Bool {
        switch self {
        case .ipa, .certificate, .provisioningProfile, .pairingFile: return false
        case .existingDylibs, .frameworksAndPlugins, .tweaks: return true
        }
    }

    var allowedContentTypes: [UTType] {
        switch self {
        case .ipa:
            return [Self.ipaType]
        case .certificate:
            return [Self.p12Type, Self.pfxType]
        case .provisioningProfile:
            return [Self.mobileProvisionType, Self.provisionProfileType]
        case .pairingFile:
            return [Self.mobileDevicePairingType, Self.pairingType, Self.plistType]
        case .existingDylibs:
            return [UTType(filenameExtension: "dylib") ?? .data]
        case .frameworksAndPlugins:
            return [.folder, UTType(filenameExtension: "framework") ?? .data, UTType(filenameExtension: "appex") ?? .data, UTType(filenameExtension: "dylib") ?? .data, .zip]
        case .tweaks:
            return [UTType(filenameExtension: "deb") ?? .data, UTType(filenameExtension: "dylib") ?? .data, .folder, .zip]
        }
    }

    var acceptedFileExtensions: Set<String>? {
        switch self {
        case .ipa:
            return ["ipa"]
        case .certificate:
            return ["p12", "pfx"]
        case .provisioningProfile:
            return ["mobileprovision", "provisionprofile"]
        case .pairingFile:
            return ["mobiledevicepairing", "pairing", "plist"]
        case .existingDylibs, .frameworksAndPlugins, .tweaks:
            return nil
        }
    }

    var acceptedFileDescription: String {
        switch self {
        case .ipa:
            return ".ipa"
        case .certificate:
            return ".p12 or .pfx"
        case .provisioningProfile:
            return ".mobileprovision or .provisionprofile"
        case .pairingFile:
            return ".mobiledevicepairing, .pairing, or .plist"
        case .existingDylibs:
            return ".dylib"
        case .frameworksAndPlugins:
            return ".framework, .appex, .dylib, .zip, or a folder"
        case .tweaks:
            return ".deb, .dylib, .zip, or a folder"
        }
    }

    func validateSelectedURL(_ url: URL, isDirectory: Bool) throws {
        guard let acceptedFileExtensions else { return }
        guard !isDirectory else {
            throw NSError(
                domain: "KittyStoreImport",
                code: 64,
                userInfo: [NSLocalizedDescriptionKey: "Select a file for \(title), not a folder. Required format: \(acceptedFileDescription)."]
            )
        }
        let fileExtension = url.pathExtension.lowercased()
        guard acceptedFileExtensions.contains(fileExtension) else {
            throw NSError(
                domain: "KittyStoreImport",
                code: 65,
                userInfo: [NSLocalizedDescriptionKey: "Wrong file type for \(title). Selected \(url.lastPathComponent), but KittyStore needs \(acceptedFileDescription)."]
            )
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
    case loaded(String)
    case failed(String)

    var isBusy: Bool {
        if case .loading = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .idle: return "No sources have loaded yet."
        case .loading: return "Loading sources."
        case .loaded(let message): return message
        case .failed(let message): return "Could not load sources: \(message)"
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
    var resolvedSourceURL: String?
    var apps: [KittyStoreApp]
    var news: [KittyStoreNewsItem]

    private enum CodingKeys: String, CodingKey {
        case name
        case identifier
        case sourceURL
        case subtitle
        case description
        case iconURL
        case developerName
        case apps
        case news
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        iconURL = try container.decodeIfPresent(String.self, forKey: .iconURL)
        developerName = try container.decodeIfPresent(String.self, forKey: .developerName)
        resolvedSourceURL = sourceURL
        apps = try container.decodeIfPresent([KittyStoreApp].self, forKey: .apps) ?? []
        news = try container.decodeIfPresent([KittyStoreNewsItem].self, forKey: .news) ?? []
    }
}

private struct KittyStoreNewsItem: Decodable, Equatable, Identifiable {
    var identifier: String?
    var date: String?
    var title: String
    var caption: String
    var tintColor: String?
    var imageURL: String?
    var externalURL: String?
    var appID: String?
    var sourceName: String?
    var sourceURL: String?

    var id: String {
        "\(sourceURL ?? "source")|\(identifier ?? title)|\(externalURL ?? date ?? caption)"
    }

    var displayDate: String? {
        guard let date, !date.isEmpty else { return nil }
        return String(date.prefix(10))
    }

    private enum CodingKeys: String, CodingKey {
        case identifier
        case date
        case title
        case caption
        case tintColor
        case imageURL
        case externalURL = "url"
        case appID
    }

    init(
        identifier: String?,
        date: String?,
        title: String,
        caption: String,
        tintColor: String?,
        imageURL: String?,
        externalURL: String?,
        appID: String?,
        sourceName: String?,
        sourceURL: String?
    ) {
        self.identifier = identifier
        self.date = date
        self.title = title
        self.caption = caption
        self.tintColor = tintColor
        self.imageURL = imageURL
        self.externalURL = externalURL
        self.appID = appID
        self.sourceName = sourceName
        self.sourceURL = sourceURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "News"
        caption = try container.decodeIfPresent(String.self, forKey: .caption) ?? ""
        tintColor = try container.decodeIfPresent(String.self, forKey: .tintColor)
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
        externalURL = try container.decodeIfPresent(String.self, forKey: .externalURL)
        appID = try container.decodeIfPresent(String.self, forKey: .appID)
        sourceName = nil
        sourceURL = nil
    }
}

private struct KittyStoreAppIconView: View {
    var app: KittyStoreApp
    var size: CGFloat

    var body: some View {
        Group {
            if let iconURL = app.iconURL, let url = URL(string: iconURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(8, size * 0.22), style: .continuous))
    }

    private var fallback: some View {
        Text(String(app.name.prefix(1)).uppercased())
            .litterFont(size: size * 0.34, weight: .bold)
            .foregroundStyle(LitterTheme.accent)
            .frame(width: size, height: size)
    }
}

private struct KittyStoreApp: Decodable, Equatable, Identifiable {
    var name: String
    var bundleIdentifier: String
    var developerName: String?
    var iconURL: String?
    var subtitle: String?
    var localizedDescription: String?
    var versions: [KittyStoreVersion]
    var sourceName: String?
    var sourceURL: String?

    var id: String { "\(sourceURL ?? "source")|\(bundleIdentifier)" }
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
