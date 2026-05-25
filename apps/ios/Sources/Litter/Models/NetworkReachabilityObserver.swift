import Foundation
import Network

/// Observes the host network's reachability and feeds change events to the
/// shared Rust client so iroh-backed (alleycat) sessions can re-evaluate
/// paths immediately on Wi-Fi ↔ cellular handoff, VPN toggle, etc.
///
/// Without this, iroh would only notice a fundamental network change via
/// the QUIC idle timeout (~30s); we'd rather hint it the moment iOS does.
///
/// `NWPathMonitor.pathUpdateHandler` fires for every path-related change
/// — including secondary VPN interfaces appearing, expensive/constrained
/// flag flipping, gateway hints, etc. We collapse those down to a small
/// fingerprint and only forward when the fingerprint changes, so the
/// Rust hint isn't spammed while the network is fundamentally stable.
@MainActor
final class NetworkReachabilityObserver {
    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    private weak var appModel: AppModel?

    private var lastFingerprint: PathFingerprint?
    private var lastSatisfied: Bool?
    private var debounceTask: Task<Void, Never>?

    /// Coalesce bursty path-update callbacks (iOS often fires several in a
    /// row when interfaces flap). 250ms is short enough to feel instant
    /// and long enough to avoid spamming the Rust hint.
    private static let debounceInterval: Duration = .milliseconds(250)

    /// What we actually care about for "did the network meaningfully
    /// change?" Two paths with the same fingerprint produce no hint.
    private struct PathFingerprint: Equatable {
        let status: NWPath.Status
        let interfaceTypes: [NWInterface.InterfaceType]
        let isExpensive: Bool
        let isConstrained: Bool
    }

    init() {
        self.monitor = NWPathMonitor()
        self.queue = DispatchQueue(label: "com.litter.network-reachability", qos: .utility)
    }

    func bind(appModel: AppModel) {
        self.appModel = appModel
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let fingerprint = PathFingerprint(
                status: path.status,
                interfaceTypes: path.availableInterfaces.map(\.type),
                isExpensive: path.isExpensive,
                isConstrained: path.isConstrained
            )
            Task { @MainActor [weak self] in
                self?.scheduleNotify(fingerprint: fingerprint)
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func scheduleNotify(fingerprint: PathFingerprint) {
        // Drop the very first observation: iOS fires it synchronously
        // on start with the current path, which we don't want to treat
        // as a change. After that, only meaningful fingerprint changes
        // get forwarded.
        guard let previous = lastFingerprint else {
            lastFingerprint = fingerprint
            lastSatisfied = (fingerprint.status == .satisfied)
            return
        }
        if previous == fingerprint { return }

        let satisfied = (fingerprint.status == .satisfied)
        let regainedAfterLoss = satisfied && (lastSatisfied == false)
        lastFingerprint = fingerprint
        lastSatisfied = satisfied

        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.debounceInterval)
            guard let self, !Task.isCancelled, let appModel = self.appModel else { return }
            LLog.info(
                "network",
                "reachability change",
                fields: [
                    "satisfied": satisfied,
                    "regainedAfterLoss": regainedAfterLoss,
                    "interfaces": fingerprint.interfaceTypes.map { String(describing: $0) },
                    "isExpensive": fingerprint.isExpensive,
                    "isConstrained": fingerprint.isConstrained
                ]
            )
            await appModel.reconnectController.notifyNetworkChange()
            // When the network just came back from a real outage, also
            // run reconnect — `notify_network_change` is only a hint and
            // doesn't itself drive saved-server reconnects.
            if regainedAfterLoss {
                _ = await appModel.reconnectController.onNetworkReachable()
            }
        }
    }
}
