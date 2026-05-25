import Foundation

extension PendingUserInputRequest {
    func isRelevant(to threadKey: ThreadKey) -> Bool {
        guard serverId == threadKey.serverId else { return false }

        let requestThreadId = threadId.trimmingCharacters(in: .whitespacesAndNewlines)
        return requestThreadId.isEmpty || requestThreadId == threadKey.threadId
    }
}
