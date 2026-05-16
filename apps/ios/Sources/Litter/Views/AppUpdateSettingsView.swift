import SwiftUI
import UIKit

struct AppUpdateSettingsView: View {
    @Environment(\.openURL) private var openURL
    @StateObject private var updater = AppUpdateStore()
    @StateObject private var taskBag = ViewTaskBag()
    @State private var buildKitStatus: LitterBuildKitStatus?
    @State private var copiedMessage: String?
    @State private var shareItem: ShareItem?

    var body: some View {
        List {
            installedSection
            releaseSection
            downloadSection
            installerSection
            runtimeAssetsSection
            diagnosticsSection
        }
        .navigationTitle("Updates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh") {
                    taskBag.run { await refreshAll() }
                }
                .disabled(updater.phase.isBusy)
            }
        }
        .sheet(item: $shareItem) { item in
            ActivityView(activityItems: [item.url])
        }
        .task { await refreshAll() }
        .onDisappear {
            taskBag.cancelAll()
            if updater.phase.isBusy { updater.cancelDownload() }
        }
    }

    private var installedSection: some View {
        Section {
            statusHeader(
                icon: availabilityIcon,
                color: availabilityColor,
                title: updater.availability.title,
                detail: updater.statusMessage
            )
            infoRow("Installed", updater.installedVersion.displayString)
            if let manifest = updater.latestManifest {
                infoRow("Latest", manifest.displayVersion)
                infoRow("Asset", manifest.ipaAssetName)
                if let size = manifest.size, size > 0 {
                    infoRow("Size", LitterDownloadSupport.formatBytes(size))
                }
                if let published = manifest.publishedAt, !published.isEmpty {
                    infoRow("Published", published)
                }
            }
        } header: {
            Text("App")
                .foregroundStyle(LitterTheme.textSecondary)
        }
    }

    private var releaseSection: some View {
        Section {
            Button {
                taskBag.run { await updater.checkForUpdates() }
            } label: {
                Label(updater.phase == .checking ? "Checking" : "Check for Updates", systemImage: "arrow.clockwise")
                    .foregroundStyle(LitterTheme.accent)
            }
            .disabled(updater.phase.isBusy)
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            if let releaseURL = updater.releaseURL {
                Button {
                    openURL(releaseURL)
                } label: {
                    Label("Open Release Page", systemImage: "safari")
                        .foregroundStyle(LitterTheme.accent)
                }
                .listRowBackground(LitterTheme.surface.opacity(0.6))
            }

            if let notes = updater.latestManifest?.releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                Text(notes)
                    .litterFont(.caption)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .textSelection(.enabled)
                    .lineLimit(12)
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
            }
        } header: {
            Text("Release")
                .foregroundStyle(LitterTheme.textSecondary)
        }
    }

    private var downloadSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(downloadTitle)
                        .litterFont(.caption, weight: .semibold)
                        .foregroundStyle(LitterTheme.textPrimary)
                    Spacer()
                    Text(updater.speedText)
                        .litterMonoFont(size: 11, weight: .regular)
                        .foregroundStyle(LitterTheme.textSecondary)
                }
                ProgressView(value: updater.downloadProgress)
                Text(updater.progressText)
                    .litterMonoFont(size: 11, weight: .regular)
                    .foregroundStyle(LitterTheme.textSecondary)
                Text(updater.checksumText)
                    .litterMonoFont(size: 11, weight: .regular)
                    .foregroundStyle(updater.canInstallDownloadedIPA ? LitterTheme.success : LitterTheme.textSecondary)
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            HStack(spacing: 12) {
                Button {
                    updater.downloadUpdate()
                } label: {
                    Label("Download IPA", systemImage: "arrow.down.circle")
                        .foregroundStyle(LitterTheme.accent)
                }
                .disabled(!updater.canDownload)

                if updater.phase.isBusy {
                    Button("Cancel", role: .destructive) {
                        updater.cancelDownload()
                    }
                }
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            if updater.downloadedIPAURL != nil {
                Button("Remove Download", role: .destructive) {
                    updater.removeDownloadedIPA()
                }
                .listRowBackground(LitterTheme.surface.opacity(0.6))
            }
        } header: {
            Text("Download")
                .foregroundStyle(LitterTheme.textSecondary)
        } footer: {
            Text("The IPA still has to be installed by a sideloading app. Litter cannot replace its own installed bundle from inside iOS.")
        }
    }

    private var installerSection: some View {
        Section {
            if let url = updater.sideStoreInstallURL {
                actionButton("Install with SideStore", icon: "square.and.arrow.down") { openURL(url) }
            }
            if let url = updater.altStoreInstallURL {
                actionButton("Install with AltStore", icon: "square.and.arrow.down.on.square") { openURL(url) }
            }
            if let url = updater.sideStoreSourceURL {
                actionButton("Add SideStore Source", icon: "link.badge.plus") { openURL(url) }
            }
            if let url = updater.altStoreSourceURL {
                actionButton("Add AltStore Source", icon: "link.badge.plus") { openURL(url) }
            }
            if let downloadedURL = updater.downloadedIPAURL {
                Button {
                    shareItem = ShareItem(url: downloadedURL)
                } label: {
                    Label("Share IPA", systemImage: "square.and.arrow.up")
                        .foregroundStyle(updater.canInstallDownloadedIPA ? LitterTheme.accent : LitterTheme.textMuted)
                }
                .disabled(!updater.canInstallDownloadedIPA)
                .listRowBackground(LitterTheme.surface.opacity(0.6))
            }
            if let remote = updater.remoteIPAURL {
                Button {
                    UIPasteboard.general.string = remote.absoluteString
                    copiedMessage = "Copied IPA link"
                } label: {
                    Label("Copy IPA Link", systemImage: "doc.on.doc")
                        .foregroundStyle(LitterTheme.accent)
                }
                .listRowBackground(LitterTheme.surface.opacity(0.6))
            }
            if let copiedMessage {
                Text(copiedMessage)
                    .litterFont(.caption)
                    .foregroundStyle(LitterTheme.success)
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
            }
        } header: {
            Text("Install")
                .foregroundStyle(LitterTheme.textSecondary)
        }
    }

    private var runtimeAssetsSection: some View {
        Section {
            if let buildKitStatus {
                infoRow("BuildKit", buildKitStatus.readinessTitle)
                infoRow("Swift direct build", buildKitStatus.canRunSwiftDirectly ? "Ready" : "Blocked")
                infoRow("Unsigned IPA build", buildKitStatus.canBuildUnsignedIPA ? "Ready" : "Blocked")
            } else {
                Text("Runtime status has not been scanned yet.")
                    .litterFont(.caption)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
            }

            Button {
                taskBag.run {
                    await LitterBuildKit.shared.installBundledAssetsIfAvailable()
                    await refreshRuntimeAssets()
                }
            } label: {
                Label("Install Bundled Runtime Assets", systemImage: "shippingbox")
                    .foregroundStyle(LitterTheme.accent)
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))

            NavigationLink {
                BuildKitSettingsView()
            } label: {
                Label("BuildKit Runtime Assets", systemImage: "hammer.fill")
                    .foregroundStyle(LitterTheme.accent)
            }
            .listRowBackground(LitterTheme.surface.opacity(0.6))
        } header: {
            Text("Runtime Assets")
                .foregroundStyle(LitterTheme.textSecondary)
        } footer: {
            Text("Runtime assets can be repaired in-app. App IPA updates still require SideStore, AltStore, Feather, Files, or another installer.")
        }
    }

    private var diagnosticsSection: some View {
        Section {
            if let lastError = updater.lastError, !lastError.isEmpty {
                Text(lastError)
                    .litterMonoFont(size: 11, weight: .regular)
                    .foregroundStyle(LitterTheme.danger)
                    .textSelection(.enabled)
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
            } else {
                Text("Release metadata comes from public GitHub Releases. Private GitHub tokens are not used for app IPA updates.")
                    .litterFont(.caption)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .listRowBackground(LitterTheme.surface.opacity(0.6))
            }
        } header: {
            Text("Diagnostics")
                .foregroundStyle(LitterTheme.textSecondary)
        }
    }

    private var downloadTitle: String {
        switch updater.phase {
        case .checking: return "Checking"
        case .downloading: return "Downloading"
        case .verifying: return "Verifying"
        case .downloaded: return "Downloaded"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        default: return "IPA"
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

    private func refreshAll() async {
        await updater.checkForUpdates()
        await refreshRuntimeAssets()
    }

    private func refreshRuntimeAssets() async {
        buildKitStatus = await LitterBuildKit.shared.status()
    }

    private func statusHeader(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .litterFont(.subheadline, weight: .semibold)
                    .foregroundStyle(LitterTheme.textPrimary)
                Text(detail)
                    .litterFont(.caption)
                    .foregroundStyle(LitterTheme.textSecondary)
            }
        }
        .listRowBackground(LitterTheme.surface.opacity(0.6))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(LitterTheme.textPrimary)
            Spacer(minLength: 12)
            Text(value)
                .litterFont(.caption, weight: .semibold)
                .foregroundStyle(LitterTheme.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .listRowBackground(LitterTheme.surface.opacity(0.6))
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .foregroundStyle(LitterTheme.accent)
        }
        .listRowBackground(LitterTheme.surface.opacity(0.6))
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
