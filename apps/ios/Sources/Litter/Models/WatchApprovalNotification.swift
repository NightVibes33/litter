/// Identifiers shared between the iPhone scheduler and notification action
/// handler so approval banners stay in lockstep across app targets.
enum WatchApprovalNotification {
    static let categoryIdentifier = "litter.approval"
    static let allowActionIdentifier = "litter.approval.allow"
    static let denyActionIdentifier = "litter.approval.deny"
    static let requestIdKey = "requestId"
    static let serverIdKey = "serverId"
    static let threadIdKey = "threadId"
}
