import Foundation
import Security

struct PerplexityAccountSummary: Identifiable, Codable, Equatable {
    var id: String
    var label: String
    var isActive: Bool

    var displayName: String { label.isEmpty ? "Perplexity Account" : label }
}

struct PerplexityAccount: Codable, Equatable {
    var id: String
    var label: String
    var cookiesJSON: String
    var createdAt: Date
    var updatedAt: Date
}

final class PerplexityAccountStore {
    static let shared = PerplexityAccountStore()

    private let keychainService = "com.sigkitten.litter.perplexity-accounts"
    private let accountsKey = "perplexity.accounts.v1"
    private let activeAccountKey = "perplexity.activeAccountID.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    var hasActiveAccount: Bool {
        (try? activeAccount()) != nil
    }

    func summaries() throws -> [PerplexityAccountSummary] {
        let accounts = try loadAccounts()
        let activeID = activeAccountID ?? accounts.first?.id
        if activeAccountID == nil, let activeID {
            self.activeAccountID = activeID
        }
        return accounts.map { account in
            PerplexityAccountSummary(id: account.id, label: account.label, isActive: account.id == activeID)
        }
    }

    func save(label rawLabel: String, cookiesJSON rawCookiesJSON: String) throws {
        let cookiesJSON = try normalizedCookiesJSON(rawCookiesJSON)
        var accounts = try loadAccounts()
        let now = Date()
        let label = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = PerplexityAccount(
            id: UUID().uuidString,
            label: label.isEmpty ? "Perplexity Account \(accounts.count + 1)" : label,
            cookiesJSON: cookiesJSON,
            createdAt: now,
            updatedAt: now
        )
        accounts.append(account)
        try persist(accounts)
        activeAccountID = account.id
    }

    func saveCapturedSession(label rawLabel: String = "Perplexity", cookiesJSON rawCookiesJSON: String) throws {
        let cookiesJSON = try normalizedCookiesJSON(rawCookiesJSON)
        var accounts = try loadAccounts()
        let now = Date()
        let label = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLabel = label.isEmpty ? "Perplexity" : label
        if let existingIndex = accounts.firstIndex(where: { $0.label == resolvedLabel }) {
            accounts[existingIndex].cookiesJSON = cookiesJSON
            accounts[existingIndex].updatedAt = now
            try persist(accounts)
            activeAccountID = accounts[existingIndex].id
            return
        }
        let account = PerplexityAccount(
            id: UUID().uuidString,
            label: resolvedLabel,
            cookiesJSON: cookiesJSON,
            createdAt: now,
            updatedAt: now
        )
        accounts.append(account)
        try persist(accounts)
        activeAccountID = account.id
    }

    func setActiveAccountID(_ accountID: String) throws {
        guard try loadAccounts().contains(where: { $0.id == accountID }) else {
            throw PerplexityAccountStoreError.missingAccount
        }
        activeAccountID = accountID
    }

    func remove(accountID: String) throws {
        var accounts = try loadAccounts()
        accounts.removeAll { $0.id == accountID }
        try persist(accounts)
        if activeAccountID == accountID {
            activeAccountID = accounts.first?.id
        }
    }

    func activeAccount() throws -> PerplexityAccount? {
        let accounts = try loadAccounts()
        guard !accounts.isEmpty else { return nil }
        if let activeAccountID, let account = accounts.first(where: { $0.id == activeAccountID }) {
            return account
        }
        activeAccountID = accounts.first?.id
        return accounts.first
    }

    private func normalizedCookiesJSON(_ rawCookiesJSON: String) throws -> String {
        let cookiesJSON = rawCookiesJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cookiesJSON.isEmpty else { throw PerplexityAccountStoreError.emptyCookies }
        guard let data = cookiesJSON.data(using: .utf8),
              let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              !payload.isEmpty else {
            throw PerplexityAccountStoreError.invalidCookiesJSON
        }
        return cookiesJSON
    }

    private func loadAccounts() throws -> [PerplexityAccount] {
        guard let data = try loadData() else { return [] }
        return try decoder.decode([PerplexityAccount].self, from: data)
    }

    private func persist(_ accounts: [PerplexityAccount]) throws {
        let data = try encoder.encode(accounts)
        try saveData(data)
    }

    private var activeAccountID: String? {
        get {
            let raw = UserDefaults.standard.string(forKey: activeAccountKey) ?? ""
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: activeAccountKey)
            } else {
                UserDefaults.standard.removeObject(forKey: activeAccountKey)
            }
        }
    }

    private func saveData(_ data: Data) throws {
        let query = keychainQuery()
        let attrs = query.merging([
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]) { _, new in new }
        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard updateStatus == errSecSuccess else { throw PerplexityAccountStoreError.keychain(updateStatus) }
            return
        }
        guard status == errSecSuccess else { throw PerplexityAccountStoreError.keychain(status) }
    }

    private func loadData() throws -> Data? {
        let query = keychainQuery().merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]) { _, new in new }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw PerplexityAccountStoreError.keychain(status) }
        return item as? Data
    }

    private func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: accountsKey
        ]
    }
}

enum PerplexityAccountStoreError: LocalizedError {
    case emptyCookies
    case invalidCookiesJSON
    case missingAccount
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyCookies: return "Sign in to Perplexity first."
        case .invalidCookiesJSON: return "Could not capture a valid Perplexity session. Make sure sign-in finished, then tap Done."
        case .missingAccount: return "That Perplexity account is not saved."
        case .keychain(let status): return "Keychain error (\(status))."
        }
    }
}
