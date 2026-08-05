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
    private var threadIdentifierByTurnID: [String: String]
    private(set) var activeThreadKey: ThreadKey?

    private init(defaults: UserDefaults = .standard) {
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: [StoredEvent]].self, from: data) {
            eventsByThread = decoded
        } else {
            eventsByThread = [:]
        }

        var turnIndex: [String: String] = [:]
        for (threadIdentifier, events) in eventsByThread {
            for event in events {
                turnIndex[event.turnID] = threadIdentifier
            }
        }
        threadIdentifierByTurnID = turnIndex
    }

    func activate(_ threadKey: ThreadKey) {
        activeThreadKey = threadKey
    }

    func beginTurn(request: String) -> String? {
        guard let threadKey = activeThreadKey else { return nil }
        let threadIdentifier = Self.identifier(for: threadKey)
        let turnID = "apple-local-turn-\(UUID().uuidString.lowercased())"
        threadIdentifierByTurnID[turnID] = threadIdentifier
        append(
            kind: .user,
            turnID: turnID,
            text: request,
            threadIdentifier: threadIdentifier
        )
        return turnID
    }

    func appendAssistant(turnID: String?, text: String) {
        appendToTurn(
            kind: .assistant,
            turnID: turnID,
            text: text
        )
    }

    func appendNote(turnID: String?, title: String, body: String) {
        appendToTurn(
            kind: .note,
            turnID: turnID,
            title: title,
            text: body
        )
    }

    func appendError(turnID: String?, title: String = "Apple On-Device Error", message: String) {
        appendToTurn(
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
        appendToTurn(
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

        appendToTurn(
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
        guard let removedEvents = eventsByThread.removeValue(forKey: identifier) else { return }
        let removedTurnIDs = Set(removedEvents.map(\.turnID))
        threadIdentifierByTurnID = threadIdentifierByTurnID.filter {
            !removedTurnIDs.contains($0.key)
        }
        persist()
        postChange(identifier: identifier)
    }

    private func appendToTurn(
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
        guard let turnID,
              !turnID.isEmpty,
              let threadIdentifier = threadIdentifierByTurnID[turnID] else { return }
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
            threadIdentifier: threadIdentifier
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
        threadIdentifier: String
    ) {
        var events = eventsByThread[threadIdentifier] ?? []
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
            let retainedTurnIDs = Set(events.map(\.turnID))
            threadIdentifierByTurnID = threadIdentifierByTurnID.filter {
                $0.value != threadIdentifier || retainedTurnIDs.contains($0.key)
            }
        }
        eventsByThread[threadIdentifier] = events
        persist()
        postChange(identifier: threadIdentifier)
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
