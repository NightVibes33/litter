import Foundation

/// Pure deep-link parser for `litter-watch://…` URLs. The watch root view
/// reads `pendingDeepLink` on appear and acts on it, so AppIntents that
/// run while the app is suspended can stash a destination and have the
/// UI apply it once SwiftUI rehydrates.
@MainActor
final class WatchDeepLinkRouter: ObservableObject {
    enum Destination: Equatable {
        case task(id: String)
        case server(id: String)
        case voice
    }

    static let shared = WatchDeepLinkRouter()
    private init() {}

    /// Latest deep-link destination that the UI hasn't yet consumed.
    @Published var pendingDeepLink: Destination?

    /// Called by `LitterWatchApp.onOpenURL` AND by AppIntent `.perform`
    /// implementations after `openAppWhenRun = true` brings the app up.
    func handle(_ url: URL) {
        guard let destination = Self.destination(for: url) else { return }
        pendingDeepLink = destination
    }

    func clear() {
        pendingDeepLink = nil
    }

    /// Static so tests can drive parsing without owning a singleton.
    nonisolated static func destination(for url: URL) -> Destination? {
        guard url.scheme == "litter-watch" else { return nil }
        switch url.host {
        case "task":
            let id = url.pathComponents.dropFirst().first ?? ""
            return id.isEmpty ? nil : .task(id: id)
        case "server":
            let id = url.pathComponents.dropFirst().first ?? ""
            return id.isEmpty ? nil : .server(id: id)
        case "voice":
            return .voice
        default:
            return nil
        }
    }
}
