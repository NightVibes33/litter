import Combine
import Foundation

@MainActor
final class ViewTaskBag: ObservableObject {
    private var tasks: [Task<Void, Never>] = []

    func run(_ operation: @escaping @MainActor () async -> Void) {
        let task = Task { @MainActor in
            await operation()
        }
        tasks.append(task)
    }

    func cancelAll() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }
}
