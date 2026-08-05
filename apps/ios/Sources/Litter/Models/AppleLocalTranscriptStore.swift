import Foundation

extension Notification.Name {
    static let appleLocalTranscriptDidChange = Notification.Name(
        "com.litter.apple-local-transcript-did-change"
    )
}

@MainActor
final class AppleLocalTranscriptStore {
    static let shared = AppleLocalTranscriptStore()

    private enum EventKind: String, Codable {
        case user
        case assistant
        case note
        case error
        case command
        case fileChange
    }

    private struct StoredEvent: Codable, Equatable {
        var id: String
        var turnID: String
        var sequence: Int
        var timestamp: Date
        var kind: EventKind
        var title: String?
        var text: String
        var command: String?
        var cwd: String?
        var output: String?
        var exitCode: Int?
        var path: String?
        var diff: String?
        var additions: Int?
        var deletions: Int?
    }

    private static let defaultsKey = "litter.apple-local-transcript.v1"
    private static let notificationThreadKey = "threadIdentifier"
    private static let maximumEventsPerThread = 500

    private var eventsByThread: [String: [StoredEvent]]
    private(set) var activeThreadKey: ThreadKey?

    private init(defaults: UserDefaults = .standard) {
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: [StoredEvent]].self, from: data) {
            eventsByThread = decoded
        } else {
            eventsByThread = [:]
        }
    }

    func activate(_ threadKey: ThreadKey) {
        activeThreadKey = threadKey
    }

    func beginTurn(request: String) -> String? {
        guard let threadKey = activeThreadKey else { return nil }
        let turnID = "apple-local-turn-\(UUID().uuidString.lowercased())"
        append(
            kind: .user,
            turnID: turnID,
            text: request,
            for: threadKey
        )
        return turnID
    }

    func appendAssistant(turnID: String?, text: String) {
        appendToActiveThread(
            kind: .assistant,
            turnID: turnID,
            text: text
        )
    }

    func appendNote(turnID: String?, title: String, body: String) {
        appendToActiveThread(
            kind: .note,
            turnID: turnID,
            title: title,
            text: body
        )
    }

    func appendError(turnID: String?, title: String = "Apple On-Device Error", message: String) {
        appendToActiveThread(
            kind: .error,
            turnID: turnID,
            title: title,
            text: message
        )
    }

    func appendCommand(
        turnID: String?,
        command: String,
        cwd: String,
        output: String,
        exitCode: Int
    ) {
        appendToActiveThread(
            kind: .command,
            turnID: turnID,
            text: output,
            command: command,
            cwd: cwd,
            output: output,
            exitCode: exitCode
        )
    }

    func appendFileChange(
        turnID: String?,
        path: String,
        content: String,
        summary: String
    ) {
        let lineCount = content.split(whereSeparator: { $0.isNewline }).count
        let diff = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "+\($0)" }
            .joined(separator: "\n")

        appendToActiveThread(
            kind: .fileChange,
            turnID: turnID,
            text: summary,
            path: path,
            diff: diff,
            additions: lineCount,
            deletions: 0
        )
    }

    func items(for threadKey: ThreadKey) -> [ConversationItem] {
        let identifier = Self.identifier(for: threadKey)
        return (eventsByThread[identifier] ?? [])
            .sorted {
                if $0.sequence == $1.sequence {
                    return $0.timestamp < $1.timestamp
                }
                return $0.sequence < $1.sequence
            }
            .map(Self.conversationItem)
    }

    func notification(_ notification: Notification, matches threadKey: ThreadKey) -> Bool {
        guard let identifier = notification.userInfo?[Self.notificationThreadKey] as? String else {
            return false
        }
        return identifier == Self.identifier(for: threadKey)
    }

    func clear(threadKey: ThreadKey) {
        let identifier = Self.identifier(for: threadKey)
        guard eventsByThread.removeValue(forKey: identifier) != nil else { return }
        persist()
        postChange(identifier: identifier)
    }

    private func appendToActiveThread(
        kind: EventKind,
        turnID: String?,
        title: String? = nil,
        text: String,
        command: String? = nil,
        cwd: String? = nil,
        output: String? = nil,
        exitCode: Int? = nil,
        path: String? = nil,
        diff: String? = nil,
        additions: Int? = nil,
        deletions: Int? = nil
    ) {
        guard let threadKey = activeThreadKey,
              let turnID,
              !turnID.isEmpty else { return }
        append(
            kind: kind,
            turnID: turnID,
            title: title,
            text: text,
            command: command,
            cwd: cwd,
            output: output,
            exitCode: exitCode,
            path: path,
            diff: diff,
            additions: additions,
            deletions: deletions,
            for: threadKey
        )
    }

    private func append(
        kind: EventKind,
        turnID: String,
        title: String? = nil,
        text: String,
        command: String? = nil,
        cwd: String? = nil,
        output: String? = nil,
        exitCode: Int? = nil,
        path: String? = nil,
        diff: String? = nil,
        additions: Int? = nil,
        deletions: Int? = nil,
        for threadKey: ThreadKey
    ) {
        let identifier = Self.identifier(for: threadKey)
        var events = eventsByThread[identifier] ?? []
        let nextSequence = (events.last?.sequence ?? -1) + 1
        events.append(
            StoredEvent(
                id: "apple-local-item-\(UUID().uuidString.lowercased())",
                turnID: turnID,
                sequence: nextSequence,
                timestamp: Date(),
                kind: kind,
                title: title,
                text: text,
                command: command,
                cwd: cwd,
                output: output,
                exitCode: exitCode,
                path: path,
                diff: diff,
                additions: additions,
                deletions: deletions
            )
        )
        if events.count > Self.maximumEventsPerThread {
            events.removeFirst(events.count - Self.maximumEventsPerThread)
            for index in events.indices {
                events[index].sequence = index
            }
        }
        eventsByThread[identifier] = events
        persist()
        postChange(identifier: identifier)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(eventsByThread) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private func postChange(identifier: String) {
        NotificationCenter.default.post(
            name: .appleLocalTranscriptDidChange,
            object: self,
            userInfo: [Self.notificationThreadKey: identifier]
        )
    }

    private static func identifier(for threadKey: ThreadKey) -> String {
        Data("\(threadKey.serverId)\n\(threadKey.threadId)".utf8).base64EncodedString()
    }

    private static func conversationItem(from event: StoredEvent) -> ConversationItem {
        let content: ConversationItemContent
        switch event.kind {
        case .user:
            content = .user(
                ConversationUserMessageData(
                    text: event.text,
                    images: []
                )
            )

        case .assistant:
            content = .assistant(
                ConversationAssistantMessageData(
                    text: event.text,
                    agentNickname: "Apple On-Device",
                    agentRole: "Private local model",
                    phase: nil
                )
            )

        case .note:
            content = .note(
                ConversationNoteData(
                    title: event.title ?? "Apple On-Device",
                    body: event.text
                )
            )

        case .error:
            content = .error(
                ConversationSystemErrorData(
                    title: event.title ?? "Apple On-Device Error",
                    message: event.text,
                    details: nil
                )
            )

        case .command:
            content = .commandExecution(
                ConversationCommandExecutionData(
                    command: event.command ?? "",
                    cwd: event.cwd ?? "/root",
                    status: .completed,
                    output: event.output ?? event.text,
                    exitCode: event.exitCode ?? 0,
                    durationMs: nil,
                    processId: nil,
                    actions: []
                )
            )

        case .fileChange:
            content = .fileChange(
                ConversationFileChangeData(
                    status: .completed,
                    changes: [
                        ConversationFileChangeEntry(
                            path: event.path ?? "",
                            kind: "write",
                            diff: event.diff ?? "",
                            additions: event.additions ?? 0,
                            deletions: event.deletions ?? 0
                        )
                    ],
                    outputDelta: event.text
                )
            )
        }

        return ConversationItem(
            id: event.id,
            content: content,
            sourceTurnId: event.turnID,
            sourceTurnIndex: nil,
            timestamp: event.timestamp,
            isFromUserTurnBoundary: false
        )
    }
}
