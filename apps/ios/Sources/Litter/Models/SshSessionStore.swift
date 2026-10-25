import Foundation

actor SshSessionStore {
    static let shared = SshSessionStore()

    private var sessionIdsByServerId: [String: String] = [:]

    func record(sessionId: String, for serverId: String) {
        LLog.trace("ssh", "record SSH session", fields: ["serverId": serverId, "sessionId": sessionId])
        sessionIdsByServerId[serverId] = sessionId
    }

    func clear(serverId: String) {
        LLog.trace("ssh", "clear SSH session", fields: ["serverId": serverId])
        sessionIdsByServerId.removeValue(forKey: serverId)
    }

    func close(serverId: String, ssh: SshBridge) async {
        guard let sessionId = sessionIdsByServerId.removeValue(forKey: serverId) else { return }
        LLog.trace("ssh", "close SSH session", fields: ["serverId": serverId, "sessionId": sessionId])
        do {
            try await ssh.sshClose(sessionId: sessionId)
        } catch {
            LLog.error("ssh", "failed to close SSH session", error: error, fields: ["serverId": serverId, "sessionId": sessionId])
        }
    }
}
