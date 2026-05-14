import Observation
import SwiftUI


enum ChatRuntimeMode: String, Codable, CaseIterable, Identifiable {
    case chatGPTAccount
    case computerBridge
    case localModel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chatGPTAccount: return "ChatGPT Account"
        case .computerBridge: return "Computer Bridge"
        case .localModel: return "On-device Model"
        }
    }

    var shortTitle: String {
        switch self {
        case .chatGPTAccount: return "ChatGPT"
        case .computerBridge: return "Bridge"
        case .localModel: return "On-device"
        }
    }

    var systemImage: String {
        switch self {
        case .chatGPTAccount: return "person.crop.circle.badge.checkmark"
        case .computerBridge: return "desktopcomputer.and.macbook"
        case .localModel: return "iphone.gen3.radiowaves.left.and.right"
        }
    }
}

func isLocalGGUFModelSelection(_ selection: String?) -> Bool {
    let trimmed = selection?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.hasPrefix("local-gguf:")
}

func isLocalGGUFModelInfo(_ model: ModelInfo) -> Bool {
    isLocalGGUFModelSelection(model.id) || isLocalGGUFModelSelection(model.model)
}

@MainActor
@Observable
final class AppState {
    private struct ThreadPermissionOverride {
        var approvalPolicy: String
        var sandboxMode: String
        var isUserOverride: Bool
        var rawApprovalPolicy: AppAskForApproval?
        var rawSandboxPolicy: AppSandboxPolicy?
    }

    private static let approvalPolicyKey = "litter.approvalPolicy"
    private static let sandboxModeKey = "litter.sandboxMode"
    private static let preferredModelKey = "litter.preferredModel"
    private static let preferredAgentRuntimeKindKey = "litter.preferredAgentRuntimeKind"
    private static let preferredReasoningEffortKey = "litter.preferredReasoningEffort"
    private static let preferredChatRuntimeKey = "litter.preferredChatRuntime"
    private static let preferredBridgeServerIdKey = "litter.preferredBridgeServerId"
    private static let inheritPermissionValue = "inherit"
    private static let customPermissionValue = "custom"

    var currentCwd = ""
    var showServerPicker = false
    var collapsedSessionFolders: Set<String> = []
    var sessionsSelectedServerFilterId: String?
    var sessionsShowOnlyForks = false
    var sessionsWorkspaceSortModeRaw = "mostRecent"
    var selectedModel = ""
    var selectedAgentRuntimeKind: AgentRuntimeKind?
    var reasoningEffort = ""
    var preferredChatRuntimeRaw: String {
        didSet {
            UserDefaults.standard.set(preferredChatRuntimeRaw, forKey: Self.preferredChatRuntimeKey)
        }
    }
    var preferredBridgeServerId: String {
        didSet {
            UserDefaults.standard.set(preferredBridgeServerId, forKey: Self.preferredBridgeServerIdKey)
        }
    }
    var preferredChatRuntimeMode: ChatRuntimeMode {
        get { ChatRuntimeMode(rawValue: preferredChatRuntimeRaw) ?? .chatGPTAccount }
        set { preferredChatRuntimeRaw = newValue.rawValue }
    }
    var preferredModel: String {
        didSet {
            UserDefaults.standard.set(preferredModel, forKey: Self.preferredModelKey)
        }
    }
    var preferredAgentRuntimeKind: AgentRuntimeKind? {
        didSet {
            UserDefaults.standard.set(
                preferredAgentRuntimeKind.map(Self.agentRuntimeWireValue) ?? "",
                forKey: Self.preferredAgentRuntimeKindKey
            )
        }
    }
    var preferredReasoningEffort: String {
        didSet {
            UserDefaults.standard.set(preferredReasoningEffort, forKey: Self.preferredReasoningEffortKey)
        }
    }
    /// Collaboration mode the user picked before a thread exists (on the
    /// home composer). Applied to the first `startThread` via
    /// `setThreadCollaborationMode` immediately after creation.
    var pendingCollaborationMode: AppModeKind = .default
    var showModelSelector = false
    var showSettings = false
    var pendingThreadNavigation: ThreadKey?
    private var threadPermissionOverrides: [String: ThreadPermissionOverride] = [:]
    var approvalPolicy: String {
        didSet {
            UserDefaults.standard.set(approvalPolicy, forKey: Self.approvalPolicyKey)
        }
    }
    var sandboxMode: String {
        didSet {
            UserDefaults.standard.set(sandboxMode, forKey: Self.sandboxModeKey)
        }
    }

    init() {
        approvalPolicy = UserDefaults.standard.string(forKey: Self.approvalPolicyKey) ?? "inherit"
        sandboxMode = UserDefaults.standard.string(forKey: Self.sandboxModeKey) ?? "inherit"
        preferredModel = UserDefaults.standard.string(forKey: Self.preferredModelKey) ?? ""
        preferredAgentRuntimeKind = Self.agentRuntimeKind(
            UserDefaults.standard.string(forKey: Self.preferredAgentRuntimeKindKey) ?? ""
        )
        preferredReasoningEffort = UserDefaults.standard.string(forKey: Self.preferredReasoningEffortKey) ?? ""
        preferredChatRuntimeRaw = UserDefaults.standard.string(forKey: Self.preferredChatRuntimeKey) ?? ChatRuntimeMode.chatGPTAccount.rawValue
        preferredBridgeServerId = UserDefaults.standard.string(forKey: Self.preferredBridgeServerIdKey) ?? ""
    }

    private static func agentRuntimeWireValue(_ kind: AgentRuntimeKind) -> String {
        // AgentRuntimeKind is itself a `String` now (the alleycat agent id).
        // No mapping needed — the id IS the persisted wire value.
        kind
    }

    private static func agentRuntimeKind(_ raw: String) -> AgentRuntimeKind? {
        // Fold known aliases into the canonical alleycat id; anything
        // else round-trips as-is so an alleycat-only agent persists
        // correctly even without local knowledge.
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            return nil
        }
        switch trimmed {
        case "pi.dev", "pidev": return "pi"
        case "ampcode", "amp-code", "amp_code", "amp code": return "amp"
        case "open-code", "open_code", "open code": return "opencode"
        case "claude-code", "claude_code", "claude code": return "claude"
        case "factory", "factory-droid", "factory_droid", "factory droid": return "droid"
        default: return trimmed
        }
    }

    func toggleSessionFolder(_ folderPath: String) {
        if collapsedSessionFolders.contains(folderPath) {
            collapsedSessionFolders.remove(folderPath)
        } else {
            collapsedSessionFolders.insert(folderPath)
        }
    }

    func isSessionFolderCollapsed(_ folderPath: String) -> Bool {
        collapsedSessionFolders.contains(folderPath)
    }

    func approvalPolicy(for threadKey: ThreadKey?) -> String {
        guard let threadKey else { return approvalPolicy }
        return threadPermissionOverrides[permissionKey(for: threadKey)]?.approvalPolicy
            ?? Self.inheritPermissionValue
    }

    func sandboxMode(for threadKey: ThreadKey?) -> String {
        guard let threadKey else { return sandboxMode }
        return threadPermissionOverrides[permissionKey(for: threadKey)]?.sandboxMode
            ?? Self.inheritPermissionValue
    }

    func launchApprovalPolicy(for threadKey: ThreadKey?) -> AppAskForApproval? {
        guard let threadKey else {
            return AppAskForApproval(wireValue: approvalPolicy)
        }
        guard let permissions = outboundPermissionOverride(for: threadKey) else {
            return nil
        }
        return permissions.rawApprovalPolicy ?? AppAskForApproval(wireValue: permissions.approvalPolicy)
    }

    func launchSandboxMode(for threadKey: ThreadKey?) -> AppSandboxMode? {
        guard let threadKey else {
            return AppSandboxMode(wireValue: sandboxMode)
        }
        guard let permissions = outboundPermissionOverride(for: threadKey) else {
            return nil
        }
        return permissions.rawSandboxPolicy?.launchOverrideMode
            ?? AppSandboxMode(wireValue: permissions.sandboxMode)
    }

    func turnSandboxPolicy(for threadKey: ThreadKey?) -> AppSandboxPolicy? {
        guard let threadKey else {
            return TurnSandboxPolicy(mode: sandboxMode)?.ffiValue
        }
        guard let permissions = outboundPermissionOverride(for: threadKey) else {
            return nil
        }
        return permissions.rawSandboxPolicy ?? TurnSandboxPolicy(mode: permissions.sandboxMode)?.ffiValue
    }

    func setPermissions(approvalPolicy: String, sandboxMode: String, for threadKey: ThreadKey?) {
        guard let threadKey else {
            self.approvalPolicy = approvalPolicy
            self.sandboxMode = sandboxMode
            return
        }
        threadPermissionOverrides[permissionKey(for: threadKey)] = ThreadPermissionOverride(
            approvalPolicy: approvalPolicy,
            sandboxMode: sandboxMode,
            isUserOverride: true,
            rawApprovalPolicy: AppAskForApproval(wireValue: approvalPolicy),
            rawSandboxPolicy: TurnSandboxPolicy(mode: sandboxMode)?.ffiValue
        )
    }

    func hydratePermissions(from thread: AppThreadSnapshot?) {
        guard let thread else { return }
        let key = permissionKey(for: thread.key)
        if threadPermissionOverrides[key]?.isUserOverride == true { return }

        let rawApprovalPolicy = thread.effectiveApprovalPolicy
        let rawSandboxPolicy = thread.effectiveSandboxPolicy
        let approvalPolicy = displayValue(for: rawApprovalPolicy)
        let sandboxMode = displayValue(for: rawSandboxPolicy)

        if rawApprovalPolicy == nil && rawSandboxPolicy == nil {
            threadPermissionOverrides.removeValue(forKey: key)
            return
        }

        threadPermissionOverrides[key] = ThreadPermissionOverride(
            approvalPolicy: approvalPolicy,
            sandboxMode: sandboxMode,
            isUserOverride: false,
            rawApprovalPolicy: rawApprovalPolicy,
            rawSandboxPolicy: rawSandboxPolicy
        )
    }

    private func permissionKey(for threadKey: ThreadKey) -> String {
        "\(threadKey.serverId)/\(threadKey.threadId)"
    }

    private func outboundPermissionOverride(for threadKey: ThreadKey) -> ThreadPermissionOverride? {
        guard let permissions = threadPermissionOverrides[permissionKey(for: threadKey)],
              permissions.isUserOverride else {
            return nil
        }
        return permissions
    }

    private func displayValue(for approvalPolicy: AppAskForApproval?) -> String {
        guard let approvalPolicy else { return Self.inheritPermissionValue }
        return approvalPolicy.launchOverrideWireValue ?? Self.customPermissionValue
    }

    private func displayValue(for sandboxPolicy: AppSandboxPolicy?) -> String {
        guard let sandboxPolicy else { return Self.inheritPermissionValue }
        return sandboxPolicy.launchOverrideModeWireValue ?? Self.customPermissionValue
    }
}
