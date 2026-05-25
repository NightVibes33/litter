import Foundation
#if canImport(WatchKit)
import WatchKit
#endif

/// Names the haptic patterns the watch fires for task transitions. Mirrors
/// `WKHapticType` so the side-effecting layer is a single `switch`.
enum WatchHaptic: String, Equatable {
    case start
    case success
    case failure
    case notification
}

/// Decides which haptics to play in response to a new tasks snapshot
/// versus the previously-known tasks. Pure logic so unit tests can drive
/// transitions without instantiating `WKInterfaceDevice`.
struct WatchHapticDetector {
    /// Minimum gap between haptics of the same type. Stops bursts of
    /// state changes (e.g. quick approval-followed-by-tool-complete) from
    /// turning the wrist into a metronome.
    let throttle: TimeInterval

    init(throttle: TimeInterval = 2.0) {
        self.throttle = throttle
    }

    struct Outcome: Equatable {
        var haptics: [WatchHaptic]
        var updatedLastFired: [WatchHaptic: Date]
    }

    /// Compute haptics to play given the diff `(oldTasks → newTasks)` and
    /// the `lastFired` map of each haptic kind's most recent emission.
    ///
    /// - `isFirstHydration: true` skips ALL haptics — we never want a
    ///   cold-launch flood of "everything is new!" buzzes.
    func evaluate(
        oldTasks: [WatchTask],
        newTasks: [WatchTask],
        lastFired: [WatchHaptic: Date],
        now: Date = .now,
        isFirstHydration: Bool = false
    ) -> Outcome {
        guard !isFirstHydration else {
            return Outcome(haptics: [], updatedLastFired: lastFired)
        }

        let oldById = Dictionary(uniqueKeysWithValues: oldTasks.map { ($0.id, $0) })
        var firedNow = lastFired
        var emitted: [WatchHaptic] = []
        var seenThisCall: Set<WatchHaptic> = []

        for new in newTasks {
            guard let old = oldById[new.id] else {
                // New task — only buzz on "needsApproval" arrival because a
                // brand-new running task is usually one the user just kicked
                // off on the phone, where they don't need a wrist nudge.
                if new.status == .needsApproval {
                    consider(.notification, into: &emitted, last: &firedNow, seen: &seenThisCall, now: now)
                }
                continue
            }
            guard old.status != new.status else { continue }
            if let haptic = transitionHaptic(from: old.status, to: new.status) {
                consider(haptic, into: &emitted, last: &firedNow, seen: &seenThisCall, now: now)
            }
        }

        return Outcome(haptics: emitted, updatedLastFired: firedNow)
    }

    private func transitionHaptic(
        from old: WatchTask.Status,
        to new: WatchTask.Status
    ) -> WatchHaptic? {
        switch (old, new) {
        case (.idle, .running):           return .start
        case (.running, .idle):           return .success
        case (.running, .error):          return .failure
        case (_, .needsApproval) where old != .needsApproval: return .notification
        default:                          return nil
        }
    }

    private func consider(
        _ haptic: WatchHaptic,
        into emitted: inout [WatchHaptic],
        last: inout [WatchHaptic: Date],
        seen: inout Set<WatchHaptic>,
        now: Date
    ) {
        // Coalesce per call: only one haptic of each kind per snapshot diff.
        guard !seen.contains(haptic) else { return }
        if let previous = last[haptic], now.timeIntervalSince(previous) < throttle {
            return
        }
        emitted.append(haptic)
        last[haptic] = now
        seen.insert(haptic)
    }
}

#if canImport(WatchKit)
extension WatchHaptic {
    /// Map to the closest `WKHapticType` so the side-effect layer is one
    /// line. Kept inside `#if canImport(WatchKit)` so the pure detector is
    /// usable from XCTest on iOS where WatchKit isn't linked.
    var wkType: WKHapticType {
        switch self {
        case .start:        return .start
        case .success:      return .success
        case .failure:      return .failure
        case .notification: return .notification
        }
    }
}
#endif
