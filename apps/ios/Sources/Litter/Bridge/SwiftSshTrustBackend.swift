import Foundation
import Security

/// Keychain-backed implementation of the Rust `TerminalSshTrustBackend`
/// callback interface. Stores per-host SHA-256 fingerprints under a
/// dedicated service so they don't collide with the SSH credential
/// keychain entries (`SSHCredentialStore`).
final class SwiftSshTrustBackend: TerminalSshTrustBackend, @unchecked Sendable {
    static let shared = SwiftSshTrustBackend()

    private let service = "com.litter.ssh.trust"

    private init() {}

    func read(host: String, port: UInt16) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(host: host, port: port),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    func write(host: String, port: UInt16, fingerprint: String) {
        let account = account(host: host, port: port)
        guard let data = fingerprint.data(using: .utf8) else { return }
        let addAttributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let addStatus = SecItemAdd(addAttributes as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let updates: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        }
    }

    func remove(host: String, port: UInt16) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(host: host, port: port),
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func account(host: String, port: UInt16) -> String {
        "\(host.lowercased()):\(port)"
    }
}
