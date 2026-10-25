import Foundation

struct AppThreadLaunchConfig: Equatable, Sendable {
    var agentRuntimeKind: AgentRuntimeKind? = nil
    var model: String? = nil
    var approvalPolicy: AppAskForApproval?
    var sandbox: AppSandboxMode?
    var developerInstructions: String?
    var persistExtendedHistory: Bool = true

    func threadStartRequest(cwd: String, dynamicTools: [AppDynamicToolSpec]? = nil) -> AppStartThreadRequest {
        AppStartThreadRequest(
            agentRuntimeKind: agentRuntimeKind,
            model: model,
            cwd: cwd,
            approvalPolicy: approvalPolicy,
            sandbox: sandbox,
            developerInstructions: developerInstructions,
            persistExtendedHistory: persistExtendedHistory,
            dynamicTools: dynamicTools
        )
    }

    func threadResumeRequest(threadId: String, cwdOverride: String?) -> AppResumeThreadRequest {
        AppResumeThreadRequest(
            threadId: threadId,
            model: model,
            cwd: cwdOverride,
            approvalPolicy: approvalPolicy,
            sandbox: sandbox,
            developerInstructions: developerInstructions,
            persistExtendedHistory: persistExtendedHistory
        )
    }

    func threadForkRequest(threadId: String, cwdOverride: String?) -> AppForkThreadRequest {
        AppForkThreadRequest(
            threadId: threadId,
            model: model,
            cwd: cwdOverride,
            approvalPolicy: approvalPolicy,
            sandbox: sandbox,
            developerInstructions: developerInstructions,
            persistExtendedHistory: persistExtendedHistory
        )
    }

    func forkThreadFromMessageRequest(cwdOverride: String?) -> AppForkThreadFromMessageRequest {
        AppForkThreadFromMessageRequest(
            model: model,
            cwd: cwdOverride,
            approvalPolicy: approvalPolicy,
            sandbox: sandbox,
            developerInstructions: developerInstructions,
            persistExtendedHistory: persistExtendedHistory
        )
    }
}

struct ComposerFileAttachment: Identifiable, Equatable, Sendable {
    var label: String
    var path: String

    var id: String { "\(label)\u{0}\(path)" }
}

struct AppComposerPayload: Equatable, Sendable {
    var text: String
    var additionalInputs: [AppUserInput]
    var fileAttachments: [ComposerFileAttachment] = []
    var approvalPolicy: AppAskForApproval?
    var sandboxPolicy: AppSandboxPolicy?
    var model: String?
    var effort: ReasoningEffort?
    var serviceTier: ServiceTier?

    /// Reject iPhone File Provider URLs and device-only fakefs paths before
    /// they can become misleading file references in a remote agent turn.
    /// File-search results already on the selected computer remain valid.
    static func attachmentPathIssue(_ raw: String, isLocal: Bool) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let path: String
        if trimmed.lowercased().hasPrefix("file://"),
           let url = URL(string: trimmed) {
            path = url.path
        } else {
            path = trimmed
        }
        let iosOnlyPrefixes = [
            "/private/var/mobile/Containers/",
            "/var/mobile/Containers/",
            "/private/var/mobile/Library/Mobile Documents/",
            "/var/mobile/Library/Mobile Documents/"
        ]
        if iosOnlyPrefixes.contains(where: { path.hasPrefix($0) }) {
            return "The selected file is still in iPhone storage and has not been transferred to the agent. Attach the file again using Files."
        }
        let localOnlyPrefixes = [
            "/root/.alleycat/attachments/",
            "/root/.litter/attachments/"
        ]
        if !isLocal && localOnlyPrefixes.contains(where: { path.hasPrefix($0) }) {
            return "This ZIP is in the iPhone's iSH filesystem, not the remote Linux workspace. Upload it to the remote computer before sending."
        }
        return nil
    }

    func validateAttachmentReferences(isLocal: Bool) throws {
        var paths = fileAttachments.map(\.path)
        for input in additionalInputs {
            if case .mention(_, let path) = input {
                paths.append(path)
            }
        }
        if let issue = paths.compactMap({ Self.attachmentPathIssue($0, isLocal: isLocal) }).first {
            throw NSError(domain: "AlleyCatAttachments", code: 101, userInfo: [
                NSLocalizedDescriptionKey: issue
            ])
        }
    }

    func turnStartRequest(threadId: String) -> AppStartTurnRequest {
        var inputs = additionalInputs
        let composedText = desktopStylePromptText(text: text, fileAttachments: fileAttachments)
        if !composedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inputs.insert(.text(text: composedText, textElements: []), at: 0)
        }
        return AppStartTurnRequest(
            threadId: threadId,
            input: inputs,
            approvalPolicy: approvalPolicy,
            sandboxPolicy: sandboxPolicy,
            model: model,
            serviceTier: serviceTier,
            effort: effort
        )
    }
}

private func desktopStylePromptText(
    text: String,
    fileAttachments: [ComposerFileAttachment]
) -> String {
    let validAttachments = fileAttachments.compactMap { attachment -> ComposerFileAttachment? in
        let label = sanitizeFileContextValue(attachment.label)
        let path = sanitizeFileContextValue(attachment.path)
        guard !path.isEmpty else { return nil }
        return ComposerFileAttachment(label: label.isEmpty ? path : label, path: path)
    }
    guard !validAttachments.isEmpty else { return text }

    let files = validAttachments
        .map { "## \($0.label): \($0.path)" }
        .joined(separator: "\n\n")
    return """
    # Files mentioned by the user:

    \(files)

    ## My request for Codex:
    \(text)
    """
}

private func sanitizeFileContextValue(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
