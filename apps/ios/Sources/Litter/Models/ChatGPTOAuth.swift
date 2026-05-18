import AuthenticationServices
import CryptoKit
import Foundation
import Network
import Security
import UIKit

struct ChatGPTOAuthTokenBundle: Codable, Equatable {
    let accessToken: String
    let idToken: String
    let refreshToken: String?
    let accountID: String
    let planType: String?
    let email: String?
}

struct StoredChatGPTAccountSummary: Identifiable, Equatable {
    let accountID: String
    let email: String?
    let planType: String?
    let isActive: Bool

    var id: String { accountID }

    var displayName: String {
        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedEmail.isEmpty {
            return trimmedEmail
        }
        let suffix = String(accountID.suffix(6))
        return suffix.isEmpty ? "ChatGPT Account" : "ChatGPT ...\(suffix)"
    }

    var detailText: String {
        let plan = planType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return plan.isEmpty ? accountID : "\(plan) - \(accountID)"
    }
}

enum ChatGPTOAuthError: LocalizedError {
    case invalidAuthorizeURL
    case invalidCallbackURL
    case missingAuthorizationCode
    case oauthError(String)
    case stateMismatch
    case unableToStartSession
    case cancelled
    case callbackTimedOut
    case missingRefreshToken
    case missingStoredTokens
    case missingAccountID
    case tokenExchangeFailed(status: Int, message: String)
    case refreshAccountMismatch
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidAuthorizeURL:
            return "Failed to build the ChatGPT login URL."
        case .invalidCallbackURL:
            return "ChatGPT login returned an invalid callback."
        case .missingAuthorizationCode:
            return "ChatGPT login did not return an authorization code."
        case .oauthError(let message):
            return message
        case .stateMismatch:
            return "ChatGPT login state did not match the original request."
        case .unableToStartSession:
            return "Unable to start the ChatGPT login session."
        case .cancelled:
            return "ChatGPT login was cancelled."
        case .callbackTimedOut:
            return "ChatGPT login timed out before returning to Litter."
        case .missingRefreshToken:
            return "No ChatGPT refresh token is available."
        case .missingStoredTokens:
            return "No stored ChatGPT login is available to refresh."
        case .missingAccountID:
            return "ChatGPT login did not include an account identifier."
        case .tokenExchangeFailed(let status, let message):
            return "ChatGPT token exchange failed (\(status)): \(message)"
        case .refreshAccountMismatch:
            return "ChatGPT refresh returned a different account than expected."
        case .keychain(let status):
            return "Keychain error (\(status))"
        }
    }

    var isTransientKeychainAvailabilityFailure: Bool {
        guard case .keychain(let status) = self else { return false }
        return status == errSecInteractionNotAllowed || status == errSecNotAvailable
    }
}

final class ChatGPTOAuthTokenStore {
    static let shared = ChatGPTOAuthTokenStore()

    private let service = "com.sigkitten.litter.chatgpt.tokens"
    private let legacyAccount = "default"
    private let accountPrefix = "chatgpt:"
    private let activeAccountKey = "litter.chatgpt.activeAccountID"
    private let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    private init() {}

    func load() throws -> ChatGPTOAuthTokenBundle? {
        if let activeID = activeAccountID,
           let activeTokens = try load(accountID: activeID) {
            return activeTokens
        }

        guard let first = try storedTokenBundles().first else {
            return nil
        }
        activeAccountID = first.accountID
        return first
    }

    func load(accountID: String) throws -> ChatGPTOAuthTokenBundle? {
        if let tokens = try loadKeychainToken(accountName: keychainAccountName(for: accountID)) {
            return tokens
        }
        guard let legacy = try loadKeychainToken(accountName: legacyAccount),
              legacy.accountID == accountID else {
            return nil
        }
        try saveKeychainToken(legacy, accountName: keychainAccountName(for: legacy.accountID))
        return legacy
    }

    func save(_ tokens: ChatGPTOAuthTokenBundle) throws {
        try saveKeychainToken(tokens, accountName: keychainAccountName(for: tokens.accountID))
        activeAccountID = tokens.accountID
    }

    func storedAccounts() throws -> [StoredChatGPTAccountSummary] {
        let tokens = try storedTokenBundles()
        let activeID = activeAccountID ?? tokens.first?.accountID
        if activeAccountID == nil, let activeID {
            activeAccountID = activeID
        }
        return tokens
            .sorted { lhs, rhs in
                let lhsName = lhs.email?.lowercased() ?? lhs.accountID.lowercased()
                let rhsName = rhs.email?.lowercased() ?? rhs.accountID.lowercased()
                return lhsName < rhsName
            }
            .map { tokens in
                StoredChatGPTAccountSummary(
                    accountID: tokens.accountID,
                    email: tokens.email,
                    planType: tokens.planType,
                    isActive: tokens.accountID == activeID
                )
            }
    }

    func setActiveAccountID(_ accountID: String) throws {
        guard try load(accountID: accountID) != nil else {
            throw ChatGPTOAuthError.missingStoredTokens
        }
        activeAccountID = accountID
    }

    func clearActiveAccount() throws {
        if let activeID = activeAccountID ?? storedTokenBundles().first?.accountID {
            try clear(accountID: activeID)
            return
        }
        try clear()
    }

    func clear(accountID: String) throws {
        try deleteKeychainToken(accountName: keychainAccountName(for: accountID))
        if let legacy = try loadKeychainToken(accountName: legacyAccount),
           legacy.accountID == accountID {
            try deleteKeychainToken(accountName: legacyAccount)
        }
        if activeAccountID == accountID {
            activeAccountID = try storedTokenBundles().first?.accountID
        }
    }

    func clear() throws {
        let query = serviceQuery()
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ChatGPTOAuthError.keychain(status)
        }
        activeAccountID = nil
    }

    var hasStoredTokens: Bool {
        (try? load()) != nil
    }

    private var activeAccountID: String? {
        get {
            let raw = UserDefaults.standard.string(forKey: activeAccountKey) ?? ""
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: activeAccountKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: activeAccountKey)
            }
        }
    }

    private func storedTokenBundles() throws -> [ChatGPTOAuthTokenBundle] {
        var seen: Set<String> = []
        var tokens: [ChatGPTOAuthTokenBundle] = []

        for bundle in try loadAllKeychainTokens() {
            guard !bundle.accountID.isEmpty, !seen.contains(bundle.accountID) else { continue }
            seen.insert(bundle.accountID)
            tokens.append(bundle)
        }

        if let legacy = try loadKeychainToken(accountName: legacyAccount),
           !seen.contains(legacy.accountID) {
            try saveKeychainToken(legacy, accountName: keychainAccountName(for: legacy.accountID))
            seen.insert(legacy.accountID)
            tokens.append(legacy)
        }

        return tokens
    }

    private func loadKeychainToken(accountName: String) throws -> ChatGPTOAuthTokenBundle? {
        let query = itemQuery(accountName: accountName).merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]) { _, new in new }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw ChatGPTOAuthError.missingStoredTokens
            }
            return try JSONDecoder().decode(ChatGPTOAuthTokenBundle.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw ChatGPTOAuthError.keychain(status)
        }
    }

    private func loadAllKeychainTokens() throws -> [ChatGPTOAuthTokenBundle] {
        let query = serviceQuery().merging([
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]) { _, new in new }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            return []
        default:
            throw ChatGPTOAuthError.keychain(status)
        }

        guard let rows = item as? [[String: Any]] else {
            return []
        }
        return rows.compactMap { row in
            let accountName = row[kSecAttrAccount as String] as? String ?? ""
            guard accountName.hasPrefix(accountPrefix) else { return nil }
            guard let data = row[kSecValueData as String] as? Data else { return nil }
            return try? JSONDecoder().decode(ChatGPTOAuthTokenBundle.self, from: data)
        }
    }

    private func saveKeychainToken(_ tokens: ChatGPTOAuthTokenBundle, accountName: String) throws {
        let data = try JSONEncoder().encode(tokens)
        let attributes: [String: Any] = itemQuery(accountName: accountName).merging([
            kSecAttrAccessible as String: accessibility,
            kSecValueData as String: data
        ]) { _, new in new }

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updates: [String: Any] = [
                kSecAttrAccessible as String: accessibility,
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(itemQuery(accountName: accountName) as CFDictionary, updates as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw ChatGPTOAuthError.keychain(updateStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw ChatGPTOAuthError.keychain(status)
        }
    }

    private func deleteKeychainToken(accountName: String) throws {
        let status = SecItemDelete(itemQuery(accountName: accountName) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ChatGPTOAuthError.keychain(status)
        }
    }

    private func keychainAccountName(for accountID: String) -> String {
        accountPrefix + accountID
    }

    private func serviceQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
    }

    private func itemQuery(accountName: String) -> [String: Any] {
        serviceQuery().merging([
            kSecAttrAccount as String: accountName
        ]) { _, new in new }
    }
}

@MainActor
enum ChatGPTOAuth {
    static let authIssuer = "https://auth.openai.com"
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let callbackBindHost = "127.0.0.1"
    static let callbackPublicHost = "localhost"
    static let callbackPort: UInt16 = 1455
    static let callbackPath = "/auth/callback"
    static let callbackTimeout: Duration = .seconds(600)

    static func login() async throws -> ChatGPTOAuthTokenBundle {
        let state = UUID().uuidString
        let codeVerifier = generatePKCECodeVerifier()
        let codeChallenge = generatePKCECodeChallenge(codeVerifier)
        let authSession = try await ChatGPTOAuthSessionRunner.shared.authenticate(
            timeout: callbackTimeout
        ) { redirectURI in
            try buildAuthorizeURL(
                state: state,
                codeChallenge: codeChallenge,
                redirectURI: redirectURI
            )
        }
        let tokens = try await completeAuthorization(
            callbackURL: authSession.callbackURL,
            expectedState: state,
            codeVerifier: codeVerifier,
            redirectURI: authSession.redirectURI
        )
        try ChatGPTOAuthTokenStore.shared.save(tokens)
        return tokens
    }

    static func remoteControlEnrollmentStepUpToken() async throws -> String {
        let state = UUID().uuidString
        let codeVerifier = generatePKCECodeVerifier()
        let codeChallenge = generatePKCECodeChallenge(codeVerifier)
        LLog.info("slingshot", "remote-control step-up auth starting", fields: [
            "state": state
        ])
        let authSession = try await ChatGPTOAuthSessionRunner.shared.authenticate(
            timeout: callbackTimeout,
            label: "remote-control-step-up",
            prefersEphemeralWebBrowserSession: false
        ) { redirectURI in
            try buildRemoteControlStepUpAuthorizeURL(
                state: state,
                codeChallenge: codeChallenge,
                redirectURI: redirectURI
            )
        }
        LLog.info("slingshot", "remote-control step-up auth callback received", fields: [
            "redirectURI": authSession.redirectURI
        ])
        let token = try await completeAuthorizationForAccessToken(
            callbackURL: authSession.callbackURL,
            expectedState: state,
            codeVerifier: codeVerifier,
            redirectURI: authSession.redirectURI
        )
        LLog.info("slingshot", "remote-control step-up token received", fields: [
            "tokenLength": token.count
        ])
        return token
    }

    static func isRemoteControlAuthorizationRequired(_ error: Error) -> Bool {
        let message = "\(error.localizedDescription) \(String(describing: error))".lowercased()
        return message.contains("missing slingshot remote-control authorization token")
            || message.contains("missing slingshot client session token")
            || message.contains("remote-control authorization")
    }

    static func loadStoredOrRefreshedTokens() async throws -> ChatGPTOAuthTokenBundle {
        let stored = try ChatGPTOAuthTokenStore.shared.load()
        do {
            return try await refreshStoredTokens(
                previousAccountID: stored?.accountID,
                storedTokens: stored
            )
        } catch {
            if let stored {
                return stored
            }
            throw error
        }
    }

    static func refreshStoredTokens(
        previousAccountID: String?,
        storedTokens: ChatGPTOAuthTokenBundle? = nil
    ) async throws -> ChatGPTOAuthTokenBundle {
        guard let stored = try (storedTokens ?? ChatGPTOAuthTokenStore.shared.load()) else {
            throw ChatGPTOAuthError.missingStoredTokens
        }
        guard let refreshToken = stored.refreshToken, !refreshToken.isEmpty else {
            throw ChatGPTOAuthError.missingRefreshToken
        }

        let refreshed = try await exchangeRefreshToken(
            refreshToken,
            fallbackRefreshToken: refreshToken
        )
        if let previousAccountID, !previousAccountID.isEmpty,
           refreshed.accountID != previousAccountID {
            throw ChatGPTOAuthError.refreshAccountMismatch
        }
        try ChatGPTOAuthTokenStore.shared.save(refreshed)
        return refreshed
    }

    static func buildAuthorizeURL(
        state: String,
        codeChallenge: String,
        redirectURI: String
    ) throws -> URL {
        var components = URLComponents(string: "\(authIssuer)/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(
                name: "scope",
                value: "openid profile email offline_access"
            ),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true")
        ]
        guard let url = components?.url else {
            throw ChatGPTOAuthError.invalidAuthorizeURL
        }
        return url
    }

    static func buildRemoteControlStepUpAuthorizeURL(
        state: String,
        codeChallenge: String,
        redirectURI: String
    ) throws -> URL {
        var components = URLComponents(string: "\(authIssuer)/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "codex.remote_control.enroll"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "originator", value: "Codex Desktop"),
            URLQueryItem(name: "reauth", value: "remote_control"),
            URLQueryItem(name: "max_age", value: "0"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true")
        ]
        guard let url = components?.url else {
            throw ChatGPTOAuthError.invalidAuthorizeURL
        }
        return url
    }

    static func completeAuthorization(
        callbackURL: URL,
        expectedState: String,
        codeVerifier: String,
        redirectURI: String
    ) async throws -> ChatGPTOAuthTokenBundle {
        let components = try validateCallbackURL(callbackURL)

        let queryItems = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
        if let error = queryItems["error"], !error.isEmpty {
            let description = queryItems["error_description"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ChatGPTOAuthError.oauthError(description?.isEmpty == false ? description! : error)
        }
        guard queryItems["state"] == expectedState else {
            throw ChatGPTOAuthError.stateMismatch
        }
        guard let code = queryItems["code"], !code.isEmpty else {
            throw ChatGPTOAuthError.missingAuthorizationCode
        }

        return try await exchangeAuthorizationCode(
            code: code,
            codeVerifier: codeVerifier,
            redirectURI: redirectURI
        )
    }

    static func completeAuthorizationForAccessToken(
        callbackURL: URL,
        expectedState: String,
        codeVerifier: String,
        redirectURI: String
    ) async throws -> String {
        let components = try validateCallbackURL(callbackURL)

        let queryItems = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
        if let error = queryItems["error"], !error.isEmpty {
            let description = queryItems["error_description"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ChatGPTOAuthError.oauthError(description?.isEmpty == false ? description! : error)
        }
        guard queryItems["state"] == expectedState else {
            throw ChatGPTOAuthError.stateMismatch
        }
        guard let code = queryItems["code"], !code.isEmpty else {
            throw ChatGPTOAuthError.missingAuthorizationCode
        }

        return try await exchangeAuthorizationCodeForAccessToken(
            code: code,
            codeVerifier: codeVerifier,
            redirectURI: redirectURI
        )
    }

    static func validateCallbackURL(_ callbackURL: URL) throws -> URLComponents {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw ChatGPTOAuthError.invalidCallbackURL
        }
        let isHTTP = callbackURL.scheme == "http"
        let hostMatches =
            components.host == callbackBindHost ||
            components.host == callbackPublicHost
        let pathMatches = components.path == callbackPath
        guard isHTTP, hostMatches, pathMatches else {
            throw ChatGPTOAuthError.invalidCallbackURL
        }
        return components
    }

    private static func exchangeAuthorizationCode(
        code: String,
        codeVerifier: String,
        redirectURI: String
    ) async throws -> ChatGPTOAuthTokenBundle {
        let body = [
            "grant_type=authorization_code",
            "code=\(urlEncode(code))",
            "redirect_uri=\(urlEncode(redirectURI))",
            "client_id=\(urlEncode(clientID))",
            "code_verifier=\(urlEncode(codeVerifier))"
        ].joined(separator: "&")
        return try await exchangeToken(body: body)
    }

    private static func exchangeAuthorizationCodeForAccessToken(
        code: String,
        codeVerifier: String,
        redirectURI: String
    ) async throws -> String {
        let body = [
            "grant_type=authorization_code",
            "code=\(urlEncode(code))",
            "redirect_uri=\(urlEncode(redirectURI))",
            "client_id=\(urlEncode(clientID))",
            "code_verifier=\(urlEncode(codeVerifier))"
        ].joined(separator: "&")
        return try await exchangeAccessToken(body: body)
    }

    private static func exchangeRefreshToken(
        _ refreshToken: String,
        fallbackRefreshToken: String? = nil
    ) async throws -> ChatGPTOAuthTokenBundle {
        let body = [
            "grant_type=refresh_token",
            "refresh_token=\(urlEncode(refreshToken))",
            "client_id=\(urlEncode(clientID))"
        ].joined(separator: "&")
        return try await exchangeToken(
            body: body,
            fallbackRefreshToken: fallbackRefreshToken
        )
    }

    private static func exchangeToken(
        body: String,
        fallbackRefreshToken: String? = nil
    ) async throws -> ChatGPTOAuthTokenBundle {
        guard let url = URL(string: "\(authIssuer)/oauth/token") else {
            throw ChatGPTOAuthError.invalidAuthorizeURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body.data(using: .utf8)
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        LLog.info("auth", "ChatGPT token exchange request", fields: [
            "url": url.absoluteString,
            "grantType": formValue("grant_type", in: body) ?? "<unknown>"
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ChatGPTOAuthError.tokenExchangeFailed(status: -1, message: "missing HTTP response")
        }
        let responseText = String(decoding: data, as: UTF8.self)
        LLog.info("auth", "ChatGPT token exchange response", fields: [
            "status": http.statusCode,
            "keys": jsonObjectKeys(data).joined(separator: ",")
        ])
        guard (200...299).contains(http.statusCode) else {
            LLog.warn("auth", "ChatGPT token exchange failed", fields: [
                "status": http.statusCode,
                "body": redactedOAuthResponsePreview(responseText)
            ])
            throw ChatGPTOAuthError.tokenExchangeFailed(
                status: http.statusCode,
                message: String(responseText.prefix(300))
            )
        }

        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return try tokenBundle(
            from: payload,
            statusCode: http.statusCode,
            fallbackRefreshToken: fallbackRefreshToken
        )
    }

    private static func exchangeAccessToken(body: String) async throws -> String {
        guard let url = URL(string: "\(authIssuer)/oauth/token") else {
            throw ChatGPTOAuthError.invalidAuthorizeURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body.data(using: .utf8)
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        LLog.info("auth", "ChatGPT access-token exchange request", fields: [
            "url": url.absoluteString,
            "grantType": formValue("grant_type", in: body) ?? "<unknown>"
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ChatGPTOAuthError.tokenExchangeFailed(status: -1, message: "missing HTTP response")
        }
        let responseText = String(decoding: data, as: UTF8.self)
        LLog.info("auth", "ChatGPT access-token exchange response", fields: [
            "status": http.statusCode,
            "keys": jsonObjectKeys(data).joined(separator: ",")
        ])
        guard (200...299).contains(http.statusCode) else {
            LLog.warn("auth", "ChatGPT access-token exchange failed", fields: [
                "status": http.statusCode,
                "body": redactedOAuthResponsePreview(responseText)
            ])
            throw ChatGPTOAuthError.tokenExchangeFailed(
                status: http.statusCode,
                message: String(responseText.prefix(300))
            )
        }

        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let accessToken = (payload?["access_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !accessToken.isEmpty else {
            throw ChatGPTOAuthError.tokenExchangeFailed(
                status: http.statusCode,
                message: "missing access_token"
            )
        }
        return accessToken
    }

    static func tokenBundle(
        from payload: [String: Any]?,
        statusCode: Int,
        fallbackRefreshToken: String? = nil
    ) throws -> ChatGPTOAuthTokenBundle {
        let accessToken = (payload?["access_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let idToken = (payload?["id_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let refreshTokenString = (payload?["refresh_token"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let refreshToken = refreshTokenString.flatMap { token in
            token.isEmpty ? nil : token
        } ?? fallbackRefreshToken
        guard !accessToken.isEmpty, !idToken.isEmpty else {
            throw ChatGPTOAuthError.tokenExchangeFailed(
                status: statusCode,
                message: "missing access_token or id_token"
            )
        }

        let idClaims = decodeJWTClaims(idToken)
        let accessClaims = decodeJWTClaims(accessToken)
        let accountID = resolveAccountID(idClaims: idClaims, accessClaims: accessClaims)
        guard !accountID.isEmpty else {
            throw ChatGPTOAuthError.missingAccountID
        }
        let planType = resolvePlanType(idClaims: idClaims, accessClaims: accessClaims)

        return ChatGPTOAuthTokenBundle(
            accessToken: accessToken,
            idToken: idToken,
            refreshToken: refreshToken,
            accountID: accountID,
            planType: planType,
            email: resolveEmail(idClaims: idClaims, accessClaims: accessClaims)
        )
    }

    private static func formValue(_ name: String, in body: String) -> String? {
        var components = URLComponents()
        components.query = body
        return components.queryItems?.first(where: { $0.name == name })?.value
    }

    private static func jsonObjectKeys(_ data: Data) -> [String] {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return payload.keys.sorted()
    }

    private static func redactedOAuthResponsePreview(_ text: String) -> String {
        guard
            let data = text.data(using: .utf8),
            var payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return String(text.prefix(300))
        }
        for key in payload.keys where isSensitiveOAuthKey(key) {
            payload[key] = "<redacted>"
        }
        guard
            let redacted = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
            let rendered = String(data: redacted, encoding: .utf8)
        else {
            return String(text.prefix(300))
        }
        return String(rendered.prefix(300))
    }

    private static func isSensitiveOAuthKey(_ key: String) -> Bool {
        let normalized = key.replacingOccurrences(of: "_", with: "").lowercased()
        return normalized.contains("token") || normalized.contains("authorization")
    }

    private static func resolveAccountID(
        idClaims: [String: Any],
        accessClaims: [String: Any]
    ) -> String {
        let candidates: [String?] = [
            idClaims["chatgpt_account_id"] as? String,
            accessClaims["chatgpt_account_id"] as? String,
            idClaims["organization_id"] as? String,
            accessClaims["organization_id"] as? String
        ]
        if let accountID = candidates
            .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return accountID
        }
        return ""
    }

    private static func resolvePlanType(
        idClaims: [String: Any],
        accessClaims: [String: Any]
    ) -> String? {
        let candidates: [String?] = [
            accessClaims["chatgpt_plan_type"] as? String,
            idClaims["chatgpt_plan_type"] as? String
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private static func resolveEmail(
        idClaims: [String: Any],
        accessClaims: [String: Any]
    ) -> String? {
        let idProfile = idClaims["https://api.openai.com/profile"] as? [String: Any]
        let accessProfile = accessClaims["https://api.openai.com/profile"] as? [String: Any]
        let candidates: [String?] = [
            idClaims["email"] as? String,
            accessClaims["email"] as? String,
            idProfile?["email"] as? String,
            accessProfile?["email"] as? String,
            idClaims["https://api.openai.com/profile"] as? String,
            accessClaims["https://api.openai.com/profile"] as? String
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private static func decodeJWTClaims(_ jwt: String) -> [String: Any] {
        let parts = jwt.split(separator: ".")
        guard parts.count > 1 else { return [:] }
        let payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = payload.padding(
            toLength: ((payload.count + 3) / 4) * 4,
            withPad: "=",
            startingAt: 0
        )
        guard let data = Data(base64Encoded: padded),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        if let authClaims = object["https://api.openai.com/auth"] as? [String: Any] {
            return authClaims
        }
        return object
    }

    private static func generatePKCECodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func generatePKCECodeChallenge(_ codeVerifier: String) -> String {
        let digest = SHA256.hash(data: Data(codeVerifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func urlEncode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

@MainActor
private final class ChatGPTOAuthSessionRunner: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = ChatGPTOAuthSessionRunner()

    private var activeSession: ASWebAuthenticationSession?
    private var activeCallbackServer: ChatGPTOAuthLoopbackServer?
    private var callbackTask: Task<Void, Never>?
    private var continuation: CheckedContinuation<ChatGPTOAuthSessionResult, Error>?
    private var didResolve = false

    func authenticate(
        timeout: Duration,
        label: String = "login",
        prefersEphemeralWebBrowserSession: Bool = true,
        buildAuthorizeURL: @escaping (String) throws -> URL
    ) async throws -> ChatGPTOAuthSessionResult {
        try await cancelActiveAttempt()

        let callbackServer = try ChatGPTOAuthLoopbackServer(
            bindHost: ChatGPTOAuth.callbackBindHost,
            publicHost: ChatGPTOAuth.callbackPublicHost,
            port: ChatGPTOAuth.callbackPort,
            path: ChatGPTOAuth.callbackPath,
            timeout: timeout
        )
        LLog.info("auth", "ChatGPT auth callback listener starting", fields: [
            "label": label,
            "bindHost": ChatGPTOAuth.callbackBindHost,
            "publicHost": ChatGPTOAuth.callbackPublicHost,
            "port": ChatGPTOAuth.callbackPort,
            "path": ChatGPTOAuth.callbackPath
        ])
        let redirectURI = try await callbackServer.start()
        let authorizeURL = try buildAuthorizeURL(redirectURI)
        LLog.info("auth", "ChatGPT auth session prepared", fields: [
            "label": label,
            "redirectURI": redirectURI,
            "authorize": sanitizedAuthorizeURL(authorizeURL),
            "ephemeral": prefersEphemeralWebBrowserSession
        ])

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.didResolve = false
            self.activeCallbackServer = callbackServer
            self.activeRedirectURI = redirectURI
            self.activeLabel = label
            self.callbackTask = Task { [weak self] in
                do {
                    let callbackURL = try await callbackServer.waitForCallback()
                    await MainActor.run {
                        self?.finishSuccess(
                            callbackURL: callbackURL,
                            redirectURI: redirectURI
                        )
                    }
                } catch {
                    await MainActor.run {
                        self?.finishFailure(error)
                    }
                }
            }

            let session = ASWebAuthenticationSession(
                url: authorizeURL,
                callbackURLScheme: nil
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    self?.handleSessionCompletion(callbackURL: callbackURL, error: error)
                }
            }
            // Start from a clean web auth session to avoid stale provider state
            // carrying over after failed attempts and tripping invalid_state.
            session.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
            session.presentationContextProvider = self
            activeSession = session
            guard session.start() else {
                finishFailure(ChatGPTOAuthError.unableToStartSession)
                return
            }
            LLog.info("auth", "ChatGPT auth session started", fields: [
                "label": label,
                "ephemeral": prefersEphemeralWebBrowserSession
            ])
        }
    }

    private var activeRedirectURI: String?
    private var activeLabel: String?

    private func handleSessionCompletion(callbackURL: URL?, error: Error?) {
        let label = activeLabel ?? "unknown"
        if let callbackURL {
            LLog.info("auth", "ChatGPT auth session returned callback URL", fields: [
                "label": label,
                "scheme": callbackURL.scheme ?? "",
                "host": callbackURL.host ?? "",
                "path": callbackURL.path
            ])
            finishSuccess(
                callbackURL: callbackURL,
                redirectURI: activeRedirectURI ?? "http://\(ChatGPTOAuth.callbackPublicHost):\(ChatGPTOAuth.callbackPort)\(ChatGPTOAuth.callbackPath)"
            )
            return
        }

        activeSession = nil
        guard !didResolve else { return }

        if let authError = error as? ASWebAuthenticationSessionError,
           authError.code == .canceledLogin {
            LLog.warn("auth", "ChatGPT auth session cancelled", fields: [
                "label": label
            ])
            finishFailure(ChatGPTOAuthError.cancelled)
            return
        }
        if let error {
            LLog.warn("auth", "ChatGPT auth session failed", fields: [
                "label": label,
                "error": error.localizedDescription
            ])
            finishFailure(error)
            return
        }
        LLog.warn("auth", "ChatGPT auth session completed without callback", fields: [
            "label": label
        ])
        finishFailure(ChatGPTOAuthError.cancelled)
    }

    private func finishSuccess(callbackURL: URL, redirectURI: String) {
        guard !didResolve else { return }
        didResolve = true
        let continuation = self.continuation
        resetActiveState(cancelSession: true)
        continuation?.resume(
            returning: ChatGPTOAuthSessionResult(
                callbackURL: callbackURL,
                redirectURI: redirectURI
            )
        )
    }

    private func finishFailure(_ error: Error) {
        guard !didResolve else { return }
        didResolve = true
        let continuation = self.continuation
        resetActiveState(cancelSession: true)
        continuation?.resume(throwing: error)
    }

    private func cancelActiveAttempt() async throws {
        guard continuation != nil || activeSession != nil || activeCallbackServer != nil else { return }
        finishFailure(ChatGPTOAuthError.cancelled)
    }

    private func resetActiveState(cancelSession: Bool) {
        if cancelSession {
            activeSession?.cancel()
        }
        activeSession = nil
        callbackTask?.cancel()
        callbackTask = nil
        activeCallbackServer?.stop()
        activeCallbackServer = nil
        continuation = nil
        activeRedirectURI = nil
        activeLabel = nil
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) {
            return window
        }
        return ASPresentationAnchor()
    }

    private func sanitizedAuthorizeURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.queryItems = components.queryItems?.map { item in
            switch item.name {
            case "code_challenge":
                return URLQueryItem(name: item.name, value: "<redacted>")
            default:
                return item
            }
        }
        return components.url?.absoluteString ?? url.absoluteString
    }
}

private struct ChatGPTOAuthSessionResult {
    let callbackURL: URL
    let redirectURI: String
}

private final class ChatGPTOAuthLoopbackServer: @unchecked Sendable {
    private let bindHost: String
    private let publicHost: String
    private let port: UInt16
    private let path: String
    private let timeout: Duration
    private let queue = DispatchQueue(label: "com.sigkitten.litter.chatgpt-oauth")
    private let stateLock = NSLock()

    private var listener: NWListener?
    private var startContinuation: CheckedContinuation<String, Error>?
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var pendingCallbackResult: Result<URL, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var didDeliverCallback = false

    init(bindHost: String, publicHost: String, port: UInt16, path: String, timeout: Duration) throws {
        self.bindHost = bindHost
        self.publicHost = publicHost
        self.port = port
        self.path = path
        self.timeout = timeout
    }

    func start() async throws -> String {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ChatGPTOAuthError.invalidCallbackURL
        }
        let listener = try NWListener(using: .tcp, on: nwPort)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.startContinuation = continuation
            listener.stateUpdateHandler = { [weak self] (state: NWListener.State) in
                guard let self else { return }
                switch state {
                case .ready:
                    LLog.info("auth", "ChatGPT auth callback listener ready", fields: [
                        "bindHost": self.bindHost,
                        "publicHost": self.publicHost,
                        "port": self.port,
                        "path": self.path
                    ])
                    self.timeoutTask = Task { [weak self] in
                        do {
                            try await Task.sleep(for: self?.timeout ?? .seconds(0))
                        } catch {
                            return
                        }
                        guard !Task.isCancelled else { return }
                        LLog.warn("auth", "ChatGPT auth callback listener timed out", fields: [
                            "port": self?.port ?? 0
                        ])
                        self?.resumeCallback(with: .failure(ChatGPTOAuthError.callbackTimedOut))
                    }
                    self.resumeStart(
                        with: .success("http://\(self.publicHost):\(self.port)\(self.path)")
                    )
                case .failed(let error):
                    LLog.warn("auth", "ChatGPT auth callback listener failed", fields: [
                        "error": error.localizedDescription
                    ])
                    self.resumeStart(with: .failure(error))
                    self.resumeCallback(with: .failure(error))
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func waitForCallback() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let pendingResult: Result<URL, Error>? = withStateLock {
                if let pendingCallbackResult {
                    self.pendingCallbackResult = nil
                    self.didDeliverCallback = true
                    return pendingCallbackResult
                }
                callbackContinuation = continuation
                return nil
            }

            guard let pendingResult else { return }
            switch pendingResult {
            case .success(let callbackURL):
                continuation.resume(returning: callbackURL)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }

    func stop() {
        let state = withStateLock { () -> (Task<Void, Never>?, NWListener?) in
            let state = (timeoutTask, listener)
            timeoutTask = nil
            listener = nil
            startContinuation = nil
            callbackContinuation = nil
            pendingCallbackResult = nil
            didDeliverCallback = true
            return state
        }
        state.0?.cancel()
        state.1?.cancel()
    }

    private func handle(_ connection: NWConnection) {
        LLog.info("auth", "ChatGPT auth callback connection accepted")
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if let error {
                self.resumeCallback(with: .failure(error))
                connection.cancel()
                return
            }

            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            let hasHeaders = nextBuffer.range(of: Data("\r\n\r\n".utf8)) != nil
            if hasHeaders || isComplete {
                self.processRequestData(nextBuffer, on: connection)
                return
            }

            self.receiveRequest(on: connection, buffer: nextBuffer)
        }
    }

    private func processRequestData(_ data: Data, on connection: NWConnection) {
        let requestText = String(decoding: data, as: UTF8.self)
        let requestLine = requestText.components(separatedBy: "\r\n").first ?? ""
        LLog.info("auth", "ChatGPT auth callback request received", fields: [
            "requestLine": requestLine
        ])
        let pathWithQuery = requestLine
            .split(separator: " ", omittingEmptySubsequences: true)
            .dropFirst()
            .first
            .map(String.init) ?? ""

        guard !pathWithQuery.isEmpty,
              let callbackURL = URL(string: "http://\(publicHost):\(port)\(pathWithQuery)"),
              let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              components.path == path else {
            LLog.warn("auth", "ChatGPT auth callback rejected", fields: [
                "requestLine": requestLine,
                "pathWithQuery": pathWithQuery
            ])
            sendResponse(
                statusLine: "HTTP/1.1 404 Not Found",
                body: "<html><body><h3>Not found</h3></body></html>",
                on: connection
            )
            return
        }

        sendResponse(
            statusLine: "HTTP/1.1 200 OK",
            body: "<html><body><h3>Login complete</h3><p>You can return to Litter.</p></body></html>",
            on: connection
        )
        LLog.info("auth", "ChatGPT auth callback accepted", fields: [
            "path": path,
            "hasCode": URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?
                .contains(where: { $0.name == "code" }) ?? false,
            "hasError": URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?
                .contains(where: { $0.name == "error" }) ?? false
        ])
        resumeCallback(with: .success(callbackURL))
    }

    private func sendResponse(statusLine: String, body: String, on connection: NWConnection) {
        let bodyData = Data(body.utf8)
        let header = [
            statusLine,
            "Content-Type: text/html; charset=UTF-8",
            "Connection: close",
            "Content-Length: \(bodyData.count)",
            "",
            ""
        ].joined(separator: "\r\n")
        var response = Data(header.utf8)
        response.append(bodyData)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func resumeStart(with result: Result<String, Error>) {
        let continuation = withStateLock {
            let continuation = startContinuation
            startContinuation = nil
            return continuation
        }
        guard let continuation else { return }
        switch result {
        case .success(let redirectURI):
            continuation.resume(returning: redirectURI)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func resumeCallback(with result: Result<URL, Error>) {
        let state = withStateLock { () -> (CheckedContinuation<URL, Error>?, Task<Void, Never>?, NWListener?) in
            guard !didDeliverCallback else { return (nil, nil, nil) }
            didDeliverCallback = true
            let continuation = callbackContinuation
            callbackContinuation = nil
            if continuation == nil {
                pendingCallbackResult = result
            }
            let timeoutTask = self.timeoutTask
            self.timeoutTask = nil
            let listener = self.listener
            self.listener = nil
            return (continuation, timeoutTask, listener)
        }
        state.1?.cancel()
        state.2?.cancel()
        guard let continuation = state.0 else { return }
        switch result {
        case .success(let callbackURL):
            continuation.resume(returning: callbackURL)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }
}
