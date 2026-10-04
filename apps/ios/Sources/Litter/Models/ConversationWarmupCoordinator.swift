import Foundation
import Observation

@MainActor
@Observable
final class ConversationWarmupCoordinator {
    private(set) var activeWarmupID: UUID?
    private(set) var hasCompletedWarmup = false

    @ObservationIgnored private var isPrewarming = false
    @ObservationIgnored private var pendingContinuations: [CheckedContinuation<Void, Never>] = []

    func prewarmIfNeeded() async {
        guard !hasCompletedWarmup else { return }

        if isPrewarming {
            await withCheckedContinuation { continuation in
                pendingContinuations.append(continuation)
            }
            return
        }

        isPrewarming = true
        activeWarmupID = UUID()

        await withCheckedContinuation { continuation in
            pendingContinuations.append(continuation)
        }
    }

    func finishWarmup() {
        guard isPrewarming else { return }

        hasCompletedWarmup = true
        isPrewarming = false
        activeWarmupID = nil

        let continuations = pendingContinuations
        pendingContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }
}
