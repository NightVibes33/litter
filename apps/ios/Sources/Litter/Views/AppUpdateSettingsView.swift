import SwiftUI
import UIKit

struct AppUpdateSettingsView: View {
    @Environment(\.openURL) private var openURL
    @StateObject private var updater = AppUpdateStore()
    @StateObject private var toolchainDownloader = BuildKitAssetDownloadStore()
    @StateObject private var taskBag = ViewTaskBag()
    @State private var buildKitStatus: LitterBuildKitStatus?
    @State private var copiedMessage: String?
    @State private var shareItem: ShareItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                statusPanel

                if shouldShowDownloadPanel {
                    downloadPanel
                }

                installerPanel
                releasePanel
                runtimeAssetsPanel
                diagnosticsPanel
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(LitterTheme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Updates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    taskBag.run { await refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(updater.phase.isBusy)
                .accessibilityLabel("Refresh updates")
            }
        }
        .refreshable { await refreshAll() }
        .sheet(item: $shareItem) { item in
            ActivityView(activityItems: [item.url])
        }
        .onChange(of: toolchainDownloader.installRevision) { _, _ in
            taskBag.run { await refreshRuntimeAssets() }
        }
        .task { await refreshAll() }
        .onDisappear {
            taskBag.cancelAll()
            if updater.phase.isBusy { updater.cancelDownload() }
            if toolchainDownloader.phase.isBusy { toolchainDownloader.cancel() }
        }
    }

    private var statusPanel: some View {
        updatePanel(title: "Status", icon: availabilityIcon) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    UpdateIconBadge(systemName: availabilityIcon, color: availabilityColor)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(updater.availability.title)
                            .litterFont(.title3, weight: .bold)
                            .foregroundStyle(LitterTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(updater.statusMessage)
                            .litterFont(.caption)
                            .foregroundStyle(LitterTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                versionSummary

                VStack(spacing: 10) {
                    Button {
                        performPrimaryAction()
                    } label: {
                        Label(primaryActionTitle, systemImage: primaryActionIcon)
                            .litterFont(.subheadline, weight: .semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(primaryActionDisabled ? LitterTheme.textMuted : Color.white)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(primaryActionDisabled ? LitterTheme.surfaceLight.opacity(0.5) : availabilityColor)
                    )
                    .disabled(primaryActionDisabled)

                    HStack(spacing: 10) {
                        secondaryActionButton("Check", icon: "arrow.clockwise") {
                            taskBag.run { await refreshAll() }
                        }
                        .disabled(updater.phase.isBusy)

                        if let releaseURL = updater.releaseURL {
                            secondaryActionButton("Release", icon: "safari") {
                                openURL(releaseURL)
                            }
                        }
                    }
                }
            }
        }
    }

    private var versionSummary: some View {
        HStack(spacing: 8) {
            versionPill(title: "Installed", value: updater.installedVersion.displayString, color: LitterTheme.textSecondary)

            Image(systemName: "arrow.right")
                .litterFont(.caption, weight: .semibold)
                .foregroundStyle(LitterTheme.textMuted)
                .frame(width: 18)

            versionPill(title: "Latest", value: updater.latestManifest?.displayVersion ?? "Unknown", color: availabilityColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var downloadPanel: some View {
        updatePanel(title: "Download", icon: "arrow.down.circle") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(downloadTitle)
                        .litterFont(.subheadline, weight: .semibold)
                        .foregroundStyle(LitterTheme.textPrimary)
                    Spacer(minLength: 12)
                    Text(updater.speedText.isEmpty ? updater.phase.phaseLabel : updater.speedText)
                        .litterMonoFont(size: 11, weight: .regular)
                        .foregroundStyle(LitterTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                ProgressView(value: updater.downloadProgress)
                    .tint(availabilityColor)

                VStack(alignment: .leading, spacing: 5) {
                    Text(updater.progressText)
                        .litterMonoFont(size: 11, weight: .regular)
                        .foregroundStyle(LitterTheme.textSecondary)
                        .textSelection(.enabled)
                    Text(updater.checksumText)
                        .litterMonoFont(size: 11, weight: .regular)
                        .foregroundStyle(updater.canInstallDownloadedIPA ? LitterTheme.success : LitterTheme.textSecondary)
                        .textSelection(.enabled)
                }

                HStack(spacing: 10) {
                    if updater.phase.isBusy {
                        secondaryActionButton("Cancel", icon: "xmark.circle", tint: LitterTheme.danger) {
                            updater.cancelDownload()
                        }
                    }

                    if updater.downloadedIPAURL != nil {
                        secondaryActionButton("Remove", icon: "trash", tint: LitterTheme.danger) {
                            updater.removeDownloadedIPA()
                        }
                    }
                }
            }
        }
    }

    private var installerPanel: some View {
        updatePanel(title: "Install", icon: "square.and.arrow.down") {
            VStack(spacing: 10) {
                if let url = updater.sideStoreInstallURL {
                    actionRow("Install with SideStore", detail: "Open this build in SideStore", icon: "square.and.arrow.down") { openURL(url) }
                }

                if let url = updater.altStoreInstallURL {
                    actionRow("Install with AltStore", detail: "Open this build in AltStore", icon: "square.and.arrow.down.on.square") { openURL(url) }
                }

                if let downloadedURL = updater.downloadedIPAURL {
                    actionRow("Share downloaded IPA", detail: updater.canInstallDownloadedIPA ? "Send to Files, Feather, or another installer" : "Waiting for checksum verification", icon: "square.and.arrow.up", enabled: updater.canInstallDownloadedIPA) {
                        shareItem = ShareItem(url: downloadedURL)
                    }
                }

                if let url = updater.sideStoreSourceURL {
                    actionRow("Add SideStore source", detail: "Subscribe to the stable update feed", icon: "link.badge.plus") { openURL(url) }
                }

                if let url = updater.altStoreSourceURL {
                    actionRow("Add AltStore source", detail: "Use the same source in AltStore-compatible apps", icon: "link.badge.plus") { openURL(url) }
                }

                if let remote = updater.remoteIPAURL {
                    actionRow("Copy IPA link", detail: remote.host ?? "Release asset", icon: "doc.on.doc") {
                        UIPasteboard.general.string = remote.absoluteString
                        copiedMessage = "Copied IPA link"
                    }
                }

                if updater.latestManifest == nil {
                    emptyState("Check for updates to load installer links and source URLs.")
                }

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
        }
    }

    private var releasePanel: some View {
        updatePanel(title: "Release", icon: "doc.text") {
            VStack(alignment: .leading, spacing: 12) {
                if let manifest = updater.latestManifest {
                    metricGrid {
                        metricItem("Build", manifest.displayVersion)
                        metricItem("Asset", manifest.ipaAssetName)
                        if let size = manifest.size, size > 0 {
                            metricItem("Size", LitterDownloadSupport.formatBytes(size))
                        }
                        if let minimumIOSVersion = manifest.minimumIOSVersion, !minimumIOSVersion.isEmpty {
                            metricItem("Min iOS", minimumIOSVersion)
                        }
                        if let buildMode = manifest.buildMode, !buildMode.isEmpty {
                            metricItem("Mode", buildMode)
                        }
                        if let commit = manifest.commit, !commit.isEmpty {
                            metricItem("Commit", String(commit.prefix(12)))
                        }
                        if let published = manifest.publishedAt, !published.isEmpty {
                            metricItem("Published", published)
                        }
                    }

                    if let notes = manifest.releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                        Divider().overlay(LitterTheme.border.opacity(0.6))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notes")
                                .litterFont(.caption, weight: .semibold)
                                .foregroundStyle(LitterTheme.textPrimary)
                            Text(notes)
                                .litterFont(.caption)
                                .foregroundStyle(LitterTheme.textSecondary)
                                .textSelection(.enabled)
                                .lineLimit(14)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    emptyState("No release metadata loaded yet.")
                }
            }
        }
    }

    private var runtimeAssetsPanel: some View {
        updatePanel(title: "Runtime", icon: "hammer") {
            VStack(alignment: .leading, spacing: 12) {
                if let buildKitStatus {
                    HStack(spacing: 8) {
                        statusPill(buildKitStatus.readinessTitle, color: buildKitStatus.isReadyForNativeBuilds ? LitterTheme.success : LitterTheme.warning)
                        statusPill(buildKitStatus.canRunSwiftDirectly ? "Swift ready" : "Swift blocked", color: buildKitStatus.canRunSwiftDirectly ? LitterTheme.success : LitterTheme.warning)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        statusPill(buildKitStatus.canBuildUnsignedIPA ? "IPA ready" : "IPA blocked", color: buildKitStatus.canBuildUnsignedIPA ? LitterTheme.success : LitterTheme.warning)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    emptyState("Runtime status has not been scanned yet.")
                }

                if let pack = updater.latestManifest?.toolchainPack {
                    Divider().overlay(LitterTheme.border.opacity(0.6))
                    metricGrid {
                        metricItem("Toolchain", pack.sdkVersion ?? pack.assetName)
                        if let swiftVersion = pack.swiftCompatibilityVersion ?? pack.swiftVersion, !swiftVersion.isEmpty {
                            metricItem("Swift", swiftVersion)
                        }
                        if let size = pack.size, size > 0 {
                            metricItem("Pack size", LitterDownloadSupport.formatBytes(size))
                        }
                        if let mode = pack.nativeDriverMode, !mode.isEmpty {
                            metricItem("Driver", mode)
                        }
                    }

                    if toolchainDownloader.phase.isBusy || toolchainDownloader.progress > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(toolchainDownloader.phase.title)
                                    .litterFont(.caption, weight: .semibold)
                                    .foregroundStyle(LitterTheme.textPrimary)
                                Spacer()
                                Text(toolchainDownloader.speedText)
                                    .litterMonoFont(size: 11, weight: .regular)
                                    .foregroundStyle(LitterTheme.textSecondary)
                            }
                            ProgressView(value: toolchainDownloader.progress)
                            Text(toolchainDownloader.progressText)
                                .litterMonoFont(size: 11, weight: .regular)
                                .foregroundStyle(LitterTheme.textSecondary)
                        }
                    }

                    if let output = toolchainDownloader.lastOutput, !output.isEmpty {
                        Text(output)
                            .litterMonoFont(size: 11, weight: .regular)
                            .foregroundStyle(LitterTheme.textSecondary)
                            .textSelection(.enabled)
                            .lineLimit(6)
                    }

                    actionRow(
                        "Download toolchain pack",
                        detail: toolchainPackDetail(pack),
                        icon: "arrow.down.circle",
                        enabled: !toolchainDownloader.phase.isBusy && pack.downloadURL?.isEmpty == false && pack.normalizedSHA256 != nil
                    ) {
                        installToolchainPack(pack)
                    }
                }

                actionRow("Install bundled runtime assets", detail: "Repair compiler assets packaged inside the app", icon: "shippingbox") {
                    taskBag.run {
                        await LitterBuildKit.shared.installBundledAssetsIfAvailable()
                        await refreshRuntimeAssets()
                    }
                }

                NavigationLink {
                    BuildKitSettingsView()
                } label: {
                    actionRowLabel("BuildKit runtime assets", detail: "Open compiler, SDK, and self-test controls", icon: "hammer.fill", enabled: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var diagnosticsPanel: some View {
        updatePanel(title: "Diagnostics", icon: "stethoscope") {
            VStack(alignment: .leading, spacing: 10) {
                if let lastError = updater.lastError, !lastError.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(LitterTheme.danger)
                        Text(lastError)
                            .litterMonoFont(size: 11, weight: .regular)
                            .foregroundStyle(LitterTheme.danger)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("The updater reads the stable public app source first, then falls back to GitHub Releases. IPA installation still happens through SideStore, AltStore, Feather, Files, or another sideloading app.")
                        .litterFont(.caption)
                        .foregroundStyle(LitterTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                actionRow("Copy update feed", detail: "Stable JSON source used by in-app checks", icon: "doc.on.doc") {
                    UIPasteboard.general.string = updater.stableUpdateURL
                    copiedMessage = "Copied update feed"
                }
            }
        }
    }

    private var shouldShowDownloadPanel: Bool {
        updater.phase == .downloading ||
            updater.phase == .verifying ||
            updater.phase == .downloaded ||
            updater.phase == .failed ||
            updater.phase == .cancelled ||
            updater.downloadedIPAURL != nil
    }

    private var primaryActionTitle: String {
        switch updater.phase {
        case .checking: return "Checking"
        case .downloading: return "Downloading"
        case .verifying: return "Verifying"
        case .downloaded: return "Share IPA"
        case .failed: return "Retry Check"
        case .cancelled: return "Retry Download"
        default:
            if updater.canDownload { return "Download IPA" }
            return "Check Again"
        }
    }

    private var primaryActionIcon: String {
        switch updater.phase {
        case .checking: return "arrow.clockwise"
        case .downloading, .verifying: return "hourglass"
        case .downloaded: return "square.and.arrow.up"
        case .failed: return "exclamationmark.arrow.circlepath"
        case .cancelled: return "arrow.clockwise.circle"
        default:
            if updater.canDownload { return "arrow.down.circle.fill" }
            return "arrow.clockwise"
        }
    }

    private var primaryActionDisabled: Bool {
        if updater.phase.isBusy { return true }
        if updater.phase == .downloaded { return updater.downloadedIPAURL == nil || !updater.canInstallDownloadedIPA }
        return false
    }

    private func performPrimaryAction() {
        switch updater.phase {
        case .downloaded:
            if let downloadedURL = updater.downloadedIPAURL, updater.canInstallDownloadedIPA {
                shareItem = ShareItem(url: downloadedURL)
            }
        case .cancelled:
            updater.downloadUpdate()
        case .failed:
            taskBag.run { await refreshAll() }
        default:
            if updater.canDownload {
                updater.downloadUpdate()
            } else {
                taskBag.run { await refreshAll() }
            }
        }
    }

    private var downloadTitle: String {
        switch updater.phase {
        case .checking: return "Checking release feed"
        case .downloading: return "Downloading IPA"
        case .verifying: return "Verifying checksum"
        case .downloaded: return "Ready to share"
        case .failed: return "Download failed"
        case .cancelled: return "Download cancelled"
        default: return "IPA download"
        }
    }

    private var availabilityIcon: String {
        switch updater.availability {
        case .available: return "arrow.down.circle.fill"
        case .upToDate: return "checkmark.seal.fill"
        case .incompatibleIOS, .incomparable, .noCompatibleRelease: return "exclamationmark.triangle.fill"
        case .remoteOlder: return "arrow.up.circle.fill"
        case .unknown: return "clock.fill"
        }
    }

    private var availabilityColor: Color {
        switch updater.availability {
        case .available: return LitterTheme.accent
        case .upToDate: return LitterTheme.success
        case .incompatibleIOS, .incomparable, .noCompatibleRelease: return LitterTheme.warning
        case .remoteOlder: return LitterTheme.textSecondary
        case .unknown: return LitterTheme.textSecondary
        }
    }

    private func installToolchainPack(_ pack: AppUpdateToolchainPack) {
        toolchainDownloader.configure(from: pack)
        toolchainDownloader.downloadAndInstall()
    }

    private func toolchainPackDetail(_ pack: AppUpdateToolchainPack) -> String {
        var parts: [String] = []
        if let sdkVersion = pack.sdkVersion, !sdkVersion.isEmpty { parts.append("SDK \(sdkVersion)") }
        if let size = pack.size, size > 0 { parts.append(LitterDownloadSupport.formatBytes(size)) }
        if pack.normalizedSHA256 != nil { parts.append("SHA verified") }
        if parts.isEmpty { return "Install compiler SDK assets into Documents/BuildKit" }
        return parts.joined(separator: " / ")
    }

    private func refreshAll() async {
        await updater.checkForUpdates()
        await refreshRuntimeAssets()
    }

    private func refreshRuntimeAssets() async {
        buildKitStatus = await LitterBuildKit.shared.status()
    }

    private func updatePanel<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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

    private func versionPill(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .litterFont(size: 10, weight: .semibold)
                .foregroundStyle(LitterTheme.textMuted)
                .lineLimit(1)
            Text(value)
                .litterMonoFont(size: 13, weight: .semibold)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LitterTheme.surfaceLight.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func secondaryActionButton(_ title: String, icon: String, tint: Color = LitterTheme.accent, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .litterFont(.caption, weight: .semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .background(LitterTheme.surfaceLight.opacity(0.42), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

    private func metricGrid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 8)], alignment: .leading, spacing: 8) {
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
                .litterMonoFont(size: 11, weight: .semibold)
                .foregroundStyle(LitterTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .textSelection(.enabled)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(color.opacity(0.14), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 0.7))
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
}

private extension AppUpdatePhase {
    var phaseLabel: String {
        switch self {
        case .idle: return "Idle"
        case .checking: return "Checking"
        case .ready: return "Ready"
        case .downloading: return "Downloading"
        case .verifying: return "Verifying"
        case .downloaded: return "Downloaded"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

private struct UpdateIconBadge: View {
    var systemName: String
    var color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.16))
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: 46, height: 46)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(color.opacity(0.35), lineWidth: 0.8)
        )
    }
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityView: UIViewControllerRepresentable {
    var activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
