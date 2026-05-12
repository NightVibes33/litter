import Foundation
import Combine

@MainActor
final class ViewTaskBag: ObservableObject {
    private var tasks: [UUID: Task<Void, Never>] = [:]

    deinit {
        for task in tasks.values {
            task.cancel()
        }
    }

    func run(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            defer { self?.tasks[id] = nil }
            await operation()
        }
        tasks[id] = task
    }

    func cancelAll() {
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
    }
}
