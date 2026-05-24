import SwiftUI
import UIKit

struct KittyStoreView: View {
    @Environment(\.openURL) private var openURL
    @StateObject private var updater = AppUpdateStore()
    @StateObject private var taskBag = ViewTaskBag()
    @State private var source: KittyStoreSource?
    @State private var sourcePhase: KittyStoreSourcePhase = .idle
    @State private var copiedMessage: String?
    @State private var shareItem: KittyStoreShareItem?
    @State private var selectedSection: KittyStoreSection = .featured

    private var app: KittyStoreApp? { source?.apps.first }
    private var versions: [KittyStoreVersion] { app?.versions ?? [] }
    private var latestVersion: KittyStoreVersion? { versions.first }
    private var sourceURL: String { updater.latestManifest?.sideStoreSourceURL ?? updater.stableSourceURL }

    var body: some View {
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
                case .setup:
                    setupPanel
                    sourcePanel
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(LitterTheme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("KittyStore")
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
        .sheet(item: $shareItem) { item in
            KittyStoreActivityView(activityItems: [item.url])
        }
        .task { await refreshAll() }
        .onDisappear {
            taskBag.cancelAll()
            if updater.phase.isBusy { updater.cancelDownload() }
        }
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
                Label(section.title, systemImage: section.systemImage).tag(section)
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
                readinessRow("SideStore install", detail: "Uses sidestore:// links; SideStore still signs and installs the IPA.", state: updater.sideStoreInstallURL != nil)
                readinessRow("LocalDevVPN", detail: "Required later for direct on-device install/refresh transport, not for viewing the source.", state: nil)
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
    case setup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .featured: return "Featured"
        case .versions: return "Versions"
        case .setup: return "Setup"
        }
    }

    var systemImage: String {
        switch self {
        case .featured: return "sparkles"
        case .versions: return "clock.arrow.circlepath"
        case .setup: return "checklist"
        }
    }
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
