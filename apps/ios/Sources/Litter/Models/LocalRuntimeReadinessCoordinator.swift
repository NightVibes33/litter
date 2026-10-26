import Foundation

actor LocalRuntimeReadinessCoordinator {
    private var readinessTask: Task<Void, Error>?
    private var isReady = false
    private let prepare: @Sendable () async throws -> Void

    init(prepare: @escaping @Sendable () async throws -> Void) {
        self.prepare = prepare
    }

    func ensureReady(forceRefresh: Bool = false) async throws {
        if let readinessTask {
            return try await readinessTask.value
        }
        guard forceRefresh || !isReady else { return }

        let prepare = self.prepare
        let task = Task.detached(priority: .utility) {
            try await prepare()
        }
        readinessTask = task
        do {
            try await task.value
            isReady = true
            readinessTask = nil
        } catch {
            isReady = false
            readinessTask = nil
            throw error
        }
    }
}
