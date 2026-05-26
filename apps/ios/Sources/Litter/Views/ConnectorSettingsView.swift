import SwiftUI
import Foundation

struct ConnectorSettingsView: View {
    @AppStorage("litterConnectorRelayBaseURL") private var relayBaseURL = ""
    @State private var localHealth: ConnectorHealthResponse?
    @State private var localConnectors: [ConnectorCatalogEntry] = []
    @State private var relayHealth: ConnectorHealthResponse?
    @State private var relayConnectors: [ConnectorCatalogEntry] = []
    @State private var loadingLocal = false
    @State private var loadingRelay = false
    @State private var errorMessage: String?

    private var displayedConnectors: [ConnectorCatalogEntry] {
        !localConnectors.isEmpty ? localConnectors : relayConnectors
    }

    private var trimmedRelayBaseURL: String {
        relayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var body: some View {
        ZStack {
            LitterTheme.backgroundGradient.ignoresSafeArea()
            Form {
                Section {
                    statusRow(
                        title: "Local Broker",
                        subtitle: localHealth?.baseURL ?? LocalConnectorBroker.shared.baseURLString,
                        systemImage: "iphone.and.arrow.forward",
                        isReady: localHealth?.ok == true,
                        isLoading: loadingLocal,
                        actionTitle: "Refresh",
                        action: { Task { await refreshLocalBroker() } }
                    )
                    settingsDetailRow(title: "Manifest", value: LocalConnectorBroker.manifestPath)
                    settingsDetailRow(title: "Bot Command", value: "litter-connectors")
                } header: {
                    Text("On Device")
                        .foregroundColor(LitterTheme.textSecondary)
                }

                Section {
                    TextField("https://your-relay.vercel.app", text: $relayBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .listRowBackground(LitterTheme.surface.opacity(0.6))

                    statusRow(
                        title: "Vercel Relay",
                        subtitle: trimmedRelayBaseURL.isEmpty ? "Not configured" : trimmedRelayBaseURL,
                        systemImage: "network",
                        isReady: relayHealth?.ready == true || relayHealth?.ok == true,
                        isLoading: loadingRelay,
                        actionTitle: "Check",
                        action: { Task { await refreshRelay() } }
                    )
                } header: {
                    Text("Hosted Relay")
                        .foregroundColor(LitterTheme.textSecondary)
                } footer: {
                    Text("Use Vercel only for providers that need HTTPS callbacks, client secrets, or server-side token exchange. Tokens still hand off to Litter for Keychain storage.")
                        .foregroundColor(LitterTheme.textMuted)
                }

                Section {
                    if displayedConnectors.isEmpty {
                        Text("Refresh the local broker or hosted relay to load connector support.")
                            .foregroundColor(LitterTheme.textSecondary)
                            .listRowBackground(LitterTheme.surface.opacity(0.6))
                    } else {
                        ForEach(displayedConnectors) { connector in
                            ConnectorSettingsRow(connector: connector)
                                .listRowBackground(LitterTheme.surface.opacity(0.6))
                        }
                    }
                } header: {
                    Text("Connectors")
                        .foregroundColor(LitterTheme.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Connectors")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reload") {
                    Task {
                        await refreshLocalBroker()
                        await refreshRelay()
                    }
                }
                .foregroundColor(LitterTheme.accent)
                .disabled(loadingLocal || loadingRelay)
            }
        }
        .task { await refreshLocalBroker() }
        .alert("Connector Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unable to check connectors.")
        }
    }

    private func statusRow(
        title: String,
        subtitle: String,
        systemImage: String,
        isReady: Bool,
        isLoading: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundColor(isReady ? .green : LitterTheme.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .litterFont(.subheadline)
                    .foregroundColor(LitterTheme.textPrimary)
                Text(subtitle)
                    .litterFont(.caption)
                    .foregroundColor(LitterTheme.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            if isLoading {
                ProgressView()
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .listRowBackground(LitterTheme.surface.opacity(0.6))
    }

    private func settingsDetailRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundColor(LitterTheme.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundColor(LitterTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .litterFont(.caption)
        .listRowBackground(LitterTheme.surface.opacity(0.6))
    }

    private func refreshLocalBroker() async {
        loadingLocal = true
        defer { loadingLocal = false }
        LocalConnectorBroker.shared.start()
        do {
            guard let healthURL = URL(string: "\(LocalConnectorBroker.shared.baseURLString)/v1/health"),
                  let connectorsURL = URL(string: "\(LocalConnectorBroker.shared.baseURLString)/v1/connectors") else {
                throw ConnectorSettingsError.invalidURL
            }
            async let health: ConnectorHealthResponse = fetchJSON(healthURL)
            async let connectors: ConnectorListResponse = fetchJSON(connectorsURL)
            localHealth = try await health
            let localCatalog = try await connectors
            localConnectors = localCatalog.connectors

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshRelay() async {
        guard !trimmedRelayBaseURL.isEmpty else { return }
        loadingRelay = true
        defer { loadingRelay = false }
        do {
            guard let healthURL = URL(string: "\(trimmedRelayBaseURL)/health"),
                  let connectorsURL = URL(string: "\(trimmedRelayBaseURL)/connectors") else {
                throw ConnectorSettingsError.invalidURL
            }
            async let health: ConnectorHealthResponse = fetchJSON(healthURL)
            async let connectors: ConnectorListResponse = fetchJSON(connectorsURL)
            relayHealth = try await health
            let relayCatalog = try await connectors
            relayConnectors = relayCatalog.connectors

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchJSON<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ConnectorSettingsError.httpStatus(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct ConnectorSettingsRow: View {
    let connector: ConnectorCatalogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .foregroundColor(statusColor)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(connector.name)
                        .litterFont(.subheadline)
                        .foregroundColor(LitterTheme.textPrimary)
                    Spacer(minLength: 8)
                    Text(connector.status ?? connector.authMode)
                        .litterFont(.caption2)
                        .foregroundColor(statusColor)
                }
                Text(connector.provider ?? "manual")
                    .litterFont(.caption)
                    .foregroundColor(LitterTheme.textSecondary)
                Text(connector.authMode)
                    .litterFont(.caption2)
                    .foregroundColor(LitterTheme.textMuted)
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch connector.status {
        case "relayRequired": return "network"
        case "connected": return "checkmark.seal.fill"
        default: return "link.badge.plus"
        }
    }

    private var statusColor: Color {
        switch connector.status {
        case "connected": return .green
        case "relayRequired": return .orange
        default: return LitterTheme.accent
        }
    }
}

private struct ConnectorHealthResponse: Decodable {
    let ok: Bool
    let service: String?
    let version: Int?
    let ready: Bool?
    let baseURL: String?
}

private struct ConnectorListResponse: Decodable {
    let ok: Bool
    let connectors: [ConnectorCatalogEntry]
}

private struct ConnectorCatalogEntry: Decodable, Identifiable {
    let id: String
    let name: String
    let provider: String?
    let authMode: String
    let status: String?
}

private enum ConnectorSettingsError: LocalizedError {
    case invalidURL
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Connector URL is invalid."
        case .httpStatus(let status):
            return "Connector endpoint returned HTTP \(status)."
        }
    }
}
