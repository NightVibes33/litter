import CryptoKit
import Darwin
import Foundation
import Security

struct NyxianSigningCertificateSummary: Codable, Equatable, Sendable {
    var commonName: String
    var sha256Fingerprint: String
    var provisioningProfileName: String?
    var provisioningProfileUUID: String?
    var validatedAt: Date

    var shortFingerprint: String {
        let prefix = sha256Fingerprint.prefix(12)
        return prefix.isEmpty ? "unknown fingerprint" : String(prefix)
    }

    var importMessage: String {
        let profile = provisioningProfileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let profileText = profile.isEmpty ? "embedded provisioning profile" : profile
        return "Imported \(commonName). Password, private key, trust, revocation, and \(profileText) match passed."
    }

    var statusDetail: String {
        "\(commonName) (\(shortFingerprint))"
    }
}

enum NyxianSigningCertificateState: Equatable, Sendable {
    case missing
    case valid(NyxianSigningCertificateSummary)
    case invalid(String)

    var isUsable: Bool {
        if case .valid = self { return true }
        return false
    }

    var statusDetail: String {
        switch self {
        case .missing:
            return "Missing"
        case .valid(let summary):
            return summary.statusDetail
        case .invalid(let reason):
            return "Invalid: \(reason)"
        }
    }
}

enum NyxianSigningCertificateStorage {
    static let certificateDataKey = "LCCertificateData"
    static let certificatePasswordKey = "LCCertificatePassword"
    private static let validationSummaryKey = "LCCertificateValidationSummary"

    static func save(data: Data, password: String, summary: NyxianSigningCertificateSummary) {
        UserDefaults.standard.set(data, forKey: certificateDataKey)
        UserDefaults.standard.set(password, forKey: certificatePasswordKey)
        if let encoded = try? JSONEncoder().encode(summary) {
            UserDefaults.standard.set(encoded, forKey: validationSummaryKey)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: certificateDataKey)
        UserDefaults.standard.removeObject(forKey: certificatePasswordKey)
        UserDefaults.standard.removeObject(forKey: validationSummaryKey)
    }

    static func savedState(checkRevocation: Bool = false) -> NyxianSigningCertificateState {
        guard let data = UserDefaults.standard.data(forKey: certificateDataKey) else {
            return .missing
        }
        let password = UserDefaults.standard.string(forKey: certificatePasswordKey) ?? ""
        do {
            let summary = try NyxianSigningCertificateValidator.validate(
                pkcs12Data: data,
                password: password,
                checkRevocation: checkRevocation
            )
            return .valid(summary)
        } catch {
            return .invalid(error.localizedDescription)
        }
    }
}


struct NyxianLocalDevVPNState: Equatable, Sendable {
    var isConnected: Bool
    var detail: String
}

enum NyxianLocalDevVPNDetector {
    static func currentState() -> NyxianLocalDevVPNState {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else {
            return NyxianLocalDevVPNState(isConnected: false, detail: "Unable to inspect network interfaces")
        }
        defer { freeifaddrs(interfaces) }

        var candidates: [String] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            let flags = Int32(current.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0 else { continue }
            guard let rawName = current.pointee.ifa_name else { continue }
            let name = String(cString: rawName)
            if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") {
                candidates.append(name)
            }
        }

        if candidates.isEmpty {
            return NyxianLocalDevVPNState(isConnected: false, detail: "No active VPN tunnel interface detected")
        }
        return NyxianLocalDevVPNState(
            isConnected: true,
            detail: "Detected VPN tunnel: \(candidates.sorted().joined(separator: ", "))"
        )
    }
}

struct NyxianAppleIDAccount: Codable, Equatable, Sendable {
    var email: String
    var teamID: String
    var anisetteServerURL: String?
    var loggedInAt: Date

    enum CodingKeys: String, CodingKey {
        case email
        case teamID
        case anisetteServerURL
        case loggedInAt
        case updatedAt
    }

    init(email: String, teamID: String, anisetteServerURL: String?, loggedInAt: Date) {
        self.email = email
        self.teamID = teamID
        self.anisetteServerURL = anisetteServerURL
        self.loggedInAt = loggedInAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        email = try container.decode(String.self, forKey: .email)
        teamID = try container.decode(String.self, forKey: .teamID)
        anisetteServerURL = try container.decodeIfPresent(String.self, forKey: .anisetteServerURL)
        loggedInAt = try container.decodeIfPresent(Date.self, forKey: .loggedInAt)
            ?? container.decodeIfPresent(Date.self, forKey: .updatedAt)
            ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(email, forKey: .email)
        try container.encode(teamID, forKey: .teamID)
        try container.encodeIfPresent(anisetteServerURL, forKey: .anisetteServerURL)
        try container.encode(loggedInAt, forKey: .loggedInAt)
    }

    var statusDetail: String {
        "\(email) / \(teamID)"
    }

    var anisetteDetail: String {
        anisetteServerURL ?? NyxianAnisetteServerDirectory.defaultServerURL
    }
}

enum NyxianAppleIDValidationError: LocalizedError {
    case invalidEmail
    case missingPassword
    case missingTeamID
    case invalidTeamID
    case invalidAnisetteURL

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "Enter the Apple ID email used by SideStore or AltStore."
        case .missingPassword:
            return "Enter the Apple ID password or app-specific password used by your signer."
        case .missingTeamID:
            return "Enter the Apple Developer Team ID for that Apple ID."
        case .invalidTeamID:
            return "Apple Developer Team IDs are 10 uppercase letters or numbers."
        case .invalidAnisetteURL:
            return "Enter a valid SideStore Anisette server URL."
        }
    }
}

struct NyxianAnisetteServer: Codable, Equatable, Identifiable, Sendable {
    var name: String
    var address: String

    var id: String { address }

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? address : trimmedName
    }
}

private struct NyxianAnisetteServerListPayload: Codable {
    var servers: [NyxianAnisetteServer]
    var cache: String?
}

enum NyxianAnisetteServerDirectory {
    static let officialListURL = "https://servers.sidestore.io/servers.json"
    static let defaultServerURL = "https://ani.sidestore.io"
    static let customSelectionID = "__custom_anisette_server__"

    static let fallbackServers: [NyxianAnisetteServer] = [
        NyxianAnisetteServer(name: "SideStore", address: "https://ani.sidestore.io"),
        NyxianAnisetteServer(name: "SideStore (.app)", address: "https://ani.sidestore.app"),
        NyxianAnisetteServer(name: "SideStore (.zip)", address: "https://ani.sidestore.zip"),
        NyxianAnisetteServer(name: "SideStore (.xyz)", address: "https://ani.846969.xyz"),
    ]

    static func fetchServers(listURL rawListURL: String = officialListURL) async throws -> [NyxianAnisetteServer] {
        let listURLString = try normalizedURL(rawListURL, defaultIfEmpty: officialListURL)
        guard let url = URL(string: listURLString) else {
            throw NyxianAppleIDValidationError.invalidAnisetteURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(
                domain: "NyxianAnisetteServerDirectory",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Anisette server list returned HTTP \(http.statusCode)"]
            )
        }

        let payload = try JSONDecoder().decode(NyxianAnisetteServerListPayload.self, from: data)
        let cleaned = payload.servers.compactMap { server -> NyxianAnisetteServer? in
            guard let address = try? normalizedURL(server.address, defaultIfEmpty: nil) else { return nil }
            return NyxianAnisetteServer(name: server.name, address: address)
        }
        let unique = deduplicated(cleaned)
        return unique.isEmpty ? fallbackServers : unique
    }

    static func normalizedServerURL(_ raw: String) throws -> String {
        try normalizedURL(raw, defaultIfEmpty: defaultServerURL)
    }

    static func normalizedListURL(_ raw: String) throws -> String {
        try normalizedURL(raw, defaultIfEmpty: officialListURL)
    }

    private static func normalizedURL(_ raw: String, defaultIfEmpty: String?) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty, let defaultIfEmpty { return defaultIfEmpty }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host?.isEmpty == false else {
            throw NyxianAppleIDValidationError.invalidAnisetteURL
        }
        return trimmed
    }

    private static func deduplicated(_ servers: [NyxianAnisetteServer]) -> [NyxianAnisetteServer] {
        var seen = Set<String>()
        var unique: [NyxianAnisetteServer] = []
        for server in servers {
            guard seen.insert(server.address).inserted else { continue }
            unique.append(server)
        }
        return unique
    }
}

enum NyxianAppleIDStore {
    private static let accountKey = "LCAppleIDAccount"

    static func load() -> NyxianAppleIDAccount? {
        guard let data = UserDefaults.standard.data(forKey: accountKey) else {
            return nil
        }
        return try? JSONDecoder().decode(NyxianAppleIDAccount.self, from: data)
    }

    static var isLoggedIn: Bool {
        load() != nil && NyxianAppleIDCredentialStore.shared.hasStoredPassword
    }

    static func login(
        email rawEmail: String,
        password rawPassword: String,
        teamID rawTeamID: String,
        anisetteServerURL rawAnisetteServerURL: String
    ) throws -> NyxianAppleIDAccount {
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = rawPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let teamID = rawTeamID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let anisetteServerURL = try NyxianAnisetteServerDirectory.normalizedServerURL(rawAnisetteServerURL)
        guard email.contains("@"), email.contains(".") else {
            throw NyxianAppleIDValidationError.invalidEmail
        }
        guard !password.isEmpty else {
            throw NyxianAppleIDValidationError.missingPassword
        }
        guard !teamID.isEmpty else {
            throw NyxianAppleIDValidationError.missingTeamID
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        guard teamID.count == 10,
              teamID.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw NyxianAppleIDValidationError.invalidTeamID
        }

        let account = NyxianAppleIDAccount(
            email: email,
            teamID: teamID,
            anisetteServerURL: anisetteServerURL,
            loggedInAt: Date()
        )
        let encoded = try JSONEncoder().encode(account)
        UserDefaults.standard.set(encoded, forKey: accountKey)
        try NyxianAppleIDCredentialStore.shared.save(password: password)
        return account
    }

    static func clear() throws {
        UserDefaults.standard.removeObject(forKey: accountKey)
        try NyxianAppleIDCredentialStore.shared.clear()
    }
}

final class NyxianAppleIDCredentialStore {
    static let shared = NyxianAppleIDCredentialStore()

    private let service = "com.sigkitten.litter.nyxian-apple-id"
    private let passwordAccount = "apple-id-password"

    private init() {}

    var hasStoredPassword: Bool {
        (try? loadPassword())?.isEmpty == false
    }

    func loadPassword() throws -> String? {
        let query = baseQuery().merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]) { _, new in new }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let password = String(data: data, encoding: .utf8) else {
                return nil
            }
            let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case errSecItemNotFound:
            return nil
        default:
            throw keychainError(status)
        }
    }

    func save(password: String) throws {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = Data(trimmed.utf8)
        let attributes = baseQuery().merging([
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data,
        ]) { _, new in new }
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [String: Any] = [
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                kSecValueData as String: data,
            ]
            let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else { throw keychainError(updateStatus) }
            return
        }
        guard status == errSecSuccess else { throw keychainError(status) }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passwordAccount,
        ]
    }

    private func keychainError(_ status: OSStatus) -> NSError {
        NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: "Keychain error (\(status))"]
        )
    }
}

enum NyxianSigningCertificateValidationError: LocalizedError {
    case emptyFile
    case incorrectPassword
    case invalidPKCS12(OSStatus)
    case noSigningIdentity
    case noPrivateKey(OSStatus)
    case noCertificate(OSStatus)
    case embeddedProvisioningProfileMissing
    case embeddedProvisioningProfileUnreadable(String)
    case provisioningProfileHasNoDeveloperCertificates
    case certificateDoesNotMatchProvisioningProfile(String)
    case trustCreationFailed(OSStatus)
    case trustEvaluationFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "The selected certificate file is empty."
        case .incorrectPassword:
            return "The .p12 password is incorrect."
        case .invalidPKCS12(let status):
            return "The selected file is not a valid .p12 signing identity (\(Self.describe(status)))."
        case .noSigningIdentity:
            return "The .p12 did not contain an Apple signing identity."
        case .noPrivateKey(let status):
            return "The .p12 did not contain an exportable private key (\(Self.describe(status)))."
        case .noCertificate(let status):
            return "The .p12 identity did not contain a certificate (\(Self.describe(status)))."
        case .embeddedProvisioningProfileMissing:
            return "The installed Litter app has no embedded.mobileprovision to match against. Install Litter through SideStore, AltStore, or another signer first."
        case .embeddedProvisioningProfileUnreadable(let reason):
            return "The embedded provisioning profile could not be read: \(reason)"
        case .provisioningProfileHasNoDeveloperCertificates:
            return "The embedded provisioning profile does not list developer certificates."
        case .certificateDoesNotMatchProvisioningProfile(let name):
            return "\(name) does not match the certificate that signed this installed Litter app."
        case .trustCreationFailed(let status):
            return "Could not build a trust check for the certificate (\(Self.describe(status)))."
        case .trustEvaluationFailed(let reason):
            return "The certificate failed trust or revocation validation: \(reason)"
        }
    }

    private static func describe(_ status: OSStatus) -> String {
        let message = SecCopyErrorMessageString(status, nil) as String?
        return message ?? "OSStatus \(status)"
    }
}

enum NyxianSigningCertificateValidator {
    static func validate(
        pkcs12Data data: Data,
        password: String,
        checkRevocation: Bool = true
    ) throws -> NyxianSigningCertificateSummary {
        guard !data.isEmpty else { throw NyxianSigningCertificateValidationError.emptyFile }

        let importOptions = [kSecImportExportPassphrase as String: password] as CFDictionary
        var importedItems: CFArray?
        let importStatus = SecPKCS12Import(data as CFData, importOptions, &importedItems)
        if importStatus == errSecAuthFailed {
            throw NyxianSigningCertificateValidationError.incorrectPassword
        }
        guard importStatus == errSecSuccess else {
            throw NyxianSigningCertificateValidationError.invalidPKCS12(importStatus)
        }
        guard let items = importedItems as? [[String: Any]],
              let item = items.first(where: { $0[kSecImportItemIdentity as String] != nil }),
              let identity = item[kSecImportItemIdentity as String] as? SecIdentity else {
            throw NyxianSigningCertificateValidationError.noSigningIdentity
        }

        var privateKey: SecKey?
        let privateKeyStatus = SecIdentityCopyPrivateKey(identity, &privateKey)
        guard privateKeyStatus == errSecSuccess, privateKey != nil else {
            throw NyxianSigningCertificateValidationError.noPrivateKey(privateKeyStatus)
        }

        var certificateRef: SecCertificate?
        let certificateStatus = SecIdentityCopyCertificate(identity, &certificateRef)
        guard certificateStatus == errSecSuccess, let certificate = certificateRef else {
            throw NyxianSigningCertificateValidationError.noCertificate(certificateStatus)
        }

        let certificateData = SecCertificateCopyData(certificate) as Data
        let commonName = certificateCommonName(certificate)
        let provisioningProfile = try EmbeddedProvisioningProfile.load()
        guard !provisioningProfile.developerCertificates.isEmpty else {
            throw NyxianSigningCertificateValidationError.provisioningProfileHasNoDeveloperCertificates
        }
        guard provisioningProfile.developerCertificates.contains(certificateData) else {
            throw NyxianSigningCertificateValidationError.certificateDoesNotMatchProvisioningProfile(commonName)
        }

        let chain = certificateChain(from: item)
        try evaluateTrust(
            certificate: certificate,
            certificateChain: chain.isEmpty ? [certificate] : chain,
            checkRevocation: checkRevocation
        )

        return NyxianSigningCertificateSummary(
            commonName: commonName,
            sha256Fingerprint: sha256Fingerprint(for: certificateData),
            provisioningProfileName: provisioningProfile.name,
            provisioningProfileUUID: provisioningProfile.uuid,
            validatedAt: Date()
        )
    }

    private static func certificateCommonName(_ certificate: SecCertificate) -> String {
        let summary = SecCertificateCopySubjectSummary(certificate) as String?
        let trimmed = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Signing certificate" : trimmed
    }

    private static func certificateChain(from item: [String: Any]) -> [SecCertificate] {
        guard let rawChain = item[kSecImportItemCertChain as String] as? [Any] else {
            return []
        }
        return rawChain.compactMap { $0 as? SecCertificate }
    }

    private static func evaluateTrust(
        certificate: SecCertificate,
        certificateChain: [SecCertificate],
        checkRevocation: Bool
    ) throws {
        var policies = [SecPolicyCreateBasicX509()]
        if checkRevocation {
            policies.append(SecPolicyCreateRevocation(CFOptionFlags(kSecRevocationUseAnyAvailableMethod)))
        }

        let trustInput: CFTypeRef
        if certificateChain.count > 1 {
            trustInput = certificateChain as CFArray
        } else {
            trustInput = certificate
        }

        var trust: SecTrust?
        let trustStatus = SecTrustCreateWithCertificates(trustInput, policies as CFArray, &trust)
        guard trustStatus == errSecSuccess, let trust else {
            throw NyxianSigningCertificateValidationError.trustCreationFailed(trustStatus)
        }

        _ = SecTrustSetNetworkFetchAllowed(trust, checkRevocation)
        var trustError: CFError?
        guard SecTrustEvaluateWithError(trust, &trustError) else {
            let reason = trustError.map { CFErrorCopyDescription($0) as String? ?? $0.localizedDescription } ?? "unknown trust failure"
            throw NyxianSigningCertificateValidationError.trustEvaluationFailed(reason)
        }
    }

    private static func sha256Fingerprint(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private struct EmbeddedProvisioningProfile {
    var name: String?
    var uuid: String?
    var developerCertificates: [Data]

    static func load() throws -> EmbeddedProvisioningProfile {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") else {
            throw NyxianSigningCertificateValidationError.embeddedProvisioningProfileMissing
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw NyxianSigningCertificateValidationError.embeddedProvisioningProfileUnreadable(error.localizedDescription)
        }
        guard let plistData = extractPlistData(from: data) else {
            throw NyxianSigningCertificateValidationError.embeddedProvisioningProfileUnreadable("no plist payload was found")
        }
        do {
            guard let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else {
                throw NyxianSigningCertificateValidationError.embeddedProvisioningProfileUnreadable("plist payload was not a dictionary")
            }
            return EmbeddedProvisioningProfile(
                name: plist["Name"] as? String,
                uuid: plist["UUID"] as? String,
                developerCertificates: plist["DeveloperCertificates"] as? [Data] ?? []
            )
        } catch let error as NyxianSigningCertificateValidationError {
            throw error
        } catch {
            throw NyxianSigningCertificateValidationError.embeddedProvisioningProfileUnreadable(error.localizedDescription)
        }
    }

    private static func extractPlistData(from data: Data) -> Data? {
        let startMarker = Data("<?xml".utf8)
        let endMarker = Data("</plist>".utf8)
        guard let start = data.range(of: startMarker)?.lowerBound,
              let endRange = data.range(of: endMarker, options: [], in: start..<data.endIndex) else {
            return nil
        }
        return Data(data[start..<endRange.upperBound])
    }
}
