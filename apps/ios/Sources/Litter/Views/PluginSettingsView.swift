import SwiftUI

struct PluginSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var plugins: [PluginSummary] = []
    @State private var loading = false
    @State private var query = ""
    @State private var errorMessage: String?
    @State private var authNotice: String?
    @State private var mutatingPluginKeys: Set<String> = []

    private var targetServer: AppServerSnapshot? {
        appModel.snapshot?.servers.first(where: { $0.isLocal && $0.canUseTransportActions })
            ?? appModel.snapshot?.servers.first(where: { $0.canUseTransportActions })
    }

    private var visiblePlugins: [PluginSummary] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return plugins }
        return plugins.filter { plugin in
            if plugin.name.lowercased().contains(needle) { return true }
            if plugin.displayTitle.lowercased().contains(needle) { return true }
            if plugin.marketplaceName.lowercased().contains(needle) { return true }
            if plugin.keywords.contains(where: { $0.lowercased().contains(needle) }) { return true }
            if let category = plugin.interface?.category?.lowercased(), category.contains(needle) { return true }
            if let description = plugin.interface?.shortDescription?.lowercased(), description.contains(needle) { return true }
            return false
        }
    }

    var body: some View {
        ZStack {
            LitterTheme.backgroundGradient.ignoresSafeArea()
            Form {
                Section {
                    TextField("Search plugins", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .listRowBackground(LitterTheme.surface.opacity(0.6))
                    if let targetServer {
                        Label(targetServer.isLocal ? "Local Codex runtime" : targetServer.displayName, systemImage: targetServer.isLocal ? "iphone" : "server.rack")
                            .litterFont(.caption)
                            .foregroundColor(LitterTheme.textSecondary)
                            .listRowBackground(LitterTheme.surface.opacity(0.6))
                    } else {
                        Label("Connect a Codex server to manage plugins", systemImage: "exclamationmark.triangle")
                            .litterFont(.caption)
                            .foregroundColor(.orange)
                            .listRowBackground(LitterTheme.surface.opacity(0.6))
                    }
                    if let authNotice {
                        Label(authNotice, systemImage: "key")
                            .litterFont(.caption)
                            .foregroundColor(LitterTheme.textSecondary)
                            .listRowBackground(LitterTheme.surface.opacity(0.6))
                    }
                } header: {
                    Text("Catalog")
                        .foregroundColor(LitterTheme.textSecondary)
                }

                Section {
                    if loading && plugins.isEmpty {
                        HStack {
                            ProgressView()
                            Text("Loading plugins")
                                .foregroundColor(LitterTheme.textSecondary)
                        }
                        .listRowBackground(LitterTheme.surface.opacity(0.6))
                    } else if visiblePlugins.isEmpty {
                        Text(query.isEmpty ? "No plugins found" : "No matching plugins")
                            .foregroundColor(LitterTheme.textSecondary)
                            .listRowBackground(LitterTheme.surface.opacity(0.6))
                    } else {
                        ForEach(visiblePlugins, id: \.mentionPath) { plugin in
                            PluginSettingsRow(
                                plugin: plugin,
                                isWorking: mutatingPluginKeys.contains(plugin.mentionPath),
                                onInstall: { Task { await install(plugin) } },
                                onUninstall: { Task { await uninstall(plugin) } }
                            )
                            .listRowBackground(LitterTheme.surface.opacity(0.6))
                        }
                    }
                } header: {
                    HStack {
                        Text("Plugins")
                        Spacer()
                        if loading && !plugins.isEmpty {
                            ProgressView()
                        }
                    }
                    .foregroundColor(LitterTheme.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Plugins")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reload") { Task { await loadPlugins() } }
                    .foregroundColor(LitterTheme.accent)
                    .disabled(loading || targetServer == nil)
            }
        }
        .task { await loadPlugins() }
        .refreshable { await loadPlugins() }
        .alert("Plugin Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unable to update plugins.")
        }
    }

    private func loadPlugins() async {
        guard let targetServer else { return }
        loading = true
        defer { loading = false }
        do {
            plugins = try await appModel.client.listPluginCatalog(
                serverId: targetServer.serverId,
                params: AppListPluginsRequest(cwds: [])
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func install(_ plugin: PluginSummary) async {
        guard let targetServer else { return }
        let key = plugin.mentionPath
        mutatingPluginKeys.insert(key)
        defer { mutatingPluginKeys.remove(key) }
        do {
            let response = try await appModel.client.installPlugin(
                serverId: targetServer.serverId,
                params: AppPluginInstallRequest(
                    marketplacePath: plugin.marketplacePath,
                    remoteMarketplaceName: remoteMarketplaceName(for: plugin),
                    pluginName: installName(for: plugin)
                )
            )
            if !response.appsNeedingAuth.isEmpty {
                let names = response.appsNeedingAuth.map(\.name).joined(separator: ", ")
                authNotice = "Installed \(plugin.displayTitle). Connect \(names) before use."
            } else {
                authNotice = "Installed \(plugin.displayTitle)."
            }
            await loadPlugins()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func uninstall(_ plugin: PluginSummary) async {
        guard let targetServer else { return }
        let key = plugin.mentionPath
        mutatingPluginKeys.insert(key)
        defer { mutatingPluginKeys.remove(key) }
        do {
            try await appModel.client.uninstallPlugin(
                serverId: targetServer.serverId,
                params: AppPluginUninstallRequest(pluginId: uninstallId(for: plugin))
            )
            authNotice = "Removed \(plugin.displayTitle)."
            await loadPlugins()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remoteMarketplaceName(for plugin: PluginSummary) -> String? {
        plugin.marketplacePath == nil ? plugin.marketplaceName : nil
    }

    private func installName(for plugin: PluginSummary) -> String {
        plugin.marketplacePath == nil ? (plugin.remotePluginId ?? plugin.id) : plugin.name
    }

    private func uninstallId(for plugin: PluginSummary) -> String {
        plugin.remotePluginId ?? plugin.id
    }
}

private struct PluginSettingsRow: View {
    let plugin: PluginSummary
    let isWorking: Bool
    let onInstall: () -> Void
    let onUninstall: () -> Void

    private var canInstall: Bool {
        guard !plugin.installed && !plugin.enabled else { return false }
        guard plugin.installPolicy == .available else { return false }
        return plugin.availability == .available
    }

    private var canUninstall: Bool {
        plugin.installed || plugin.enabled
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .foregroundColor(statusColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(plugin.displayTitle)
                        .litterFont(.subheadline)
                        .foregroundColor(LitterTheme.textPrimary)
                    Spacer(minLength: 8)
                    Text(statusLabel)
                        .litterFont(.caption2)
                        .foregroundColor(statusColor)
                }

                if let description = plugin.interface?.shortDescription, !description.isEmpty {
                    Text(description)
                        .litterFont(.caption)
                        .foregroundColor(LitterTheme.textSecondary)
                }

                HStack(spacing: 6) {
                    Text(plugin.marketplaceName)
                    if let category = plugin.interface?.category, !category.isEmpty {
                        Text("·")
                        Text(category)
                    }
                    if let developer = plugin.interface?.developerName, !developer.isEmpty {
                        Text("·")
                        Text(developer)
                    }
                }
                .litterFont(.caption2)
                .foregroundColor(LitterTheme.textMuted)
            }

            if isWorking {
                ProgressView()
            } else if canInstall {
                Button("Install", action: onInstall)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(LitterTheme.accent)
            } else if canUninstall {
                Button("Remove", role: .destructive, action: onUninstall)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        if plugin.installed || plugin.enabled { return "checkmark.seal.fill" }
        if plugin.availability == .disabledByAdmin { return "lock.fill" }
        return "shippingbox"
    }

    private var statusLabel: String {
        if plugin.installed { return plugin.enabled ? "installed" : "disabled" }
        if plugin.enabled { return "enabled" }
        if plugin.installPolicy == .installedByDefault { return "default" }
        if plugin.availability == .disabledByAdmin { return "blocked" }
        if plugin.installPolicy == .available { return "available" }
        return "unavailable"
    }

    private var statusColor: Color {
        if plugin.installed || plugin.enabled { return LitterTheme.accent }
        if plugin.availability == .disabledByAdmin { return .orange }
        if plugin.installPolicy == .available { return LitterTheme.textSecondary }
        return LitterTheme.textMuted
    }
}
