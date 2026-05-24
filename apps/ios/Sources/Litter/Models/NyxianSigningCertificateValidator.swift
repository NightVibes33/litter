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
        if profile.isEmpty {
            return "Imported \(commonName). Password, private key, trust, and revocation checks passed."
        }
        return "Imported \(commonName). Password, private key, trust, revocation, and \(profile) match passed."
    }

    var statusDetail: String {
        "\(commonName) (\(shortFingerprint))"
    }
}

struct NyxianProvisioningProfileSummary: Codable, Equatable, Sendable {
    var name: String
    var uuid: String
    var teamIdentifiers: [String]
    var bundleIdentifier: String
    var expiresAt: Date?
    var developerCertificateFingerprints: [String]
    var matchedCertificateFingerprint: String?

    var statusDetail: String {
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Provisioning profile" : name
        let bundle = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown bundle" : bundleIdentifier
        return "\(displayName) / \(bundle)"
    }

    var importMessage: String {
        var checks = ["profile parsed", "developer certificates present"]
        if matchedCertificateFingerprint != nil { checks.append("certificate match") }
        if expiresAt != nil { checks.append("expiration valid") }
        return "Imported \(statusDetail). \(checks.joined(separator: ", ")) passed."
    }
}

enum NyxianProvisioningProfileValidationError: LocalizedError {
    case emptyFile
    case unreadable(String)
    case expired(Date)
    case noDeveloperCertificates
    case certificateMismatch
    case bundleMismatch(profile: String, requested: String)

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "The selected provisioning profile is empty."
        case .unreadable(let reason):
            return "The provisioning profile could not be read: \(reason)"
        case .expired(let date):
            return "The provisioning profile expired on \(ISO8601DateFormatter().string(from: date))."
        case .noDeveloperCertificates:
            return "The provisioning profile does not contain developer certificates."
        case .certificateMismatch:
            return "The provisioning profile does not include the imported .p12 signing certificate."
        case .bundleMismatch(let profile, let requested):
            return "Provisioning profile bundle ID \(profile) does not match \(requested)."
        }
    }
}

enum NyxianProvisioningProfileValidator {
    static func validate(
        data: Data,
        signingCertificateFingerprint: String? = nil,
        requestedBundleIdentifier: String? = nil
    ) throws -> NyxianProvisioningProfileSummary {
        guard !data.isEmpty else { throw NyxianProvisioningProfileValidationError.emptyFile }
        guard let plistData = NyxianProvisioningProfilePlist.extractPlistData(from: data) else {
            throw NyxianProvisioningProfileValidationError.unreadable("no plist payload was found")
        }
        let plist: [String: Any]
        do {
            guard let decoded = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else {
                throw NyxianProvisioningProfileValidationError.unreadable("plist payload was not a dictionary")
            }
            plist = decoded
        } catch let error as NyxianProvisioningProfileValidationError {
            throw error
        } catch {
            throw NyxianProvisioningProfileValidationError.unreadable(error.localizedDescription)
        }

        let developerCertificates = plist["DeveloperCertificates"] as? [Data] ?? []
        guard !developerCertificates.isEmpty else { throw NyxianProvisioningProfileValidationError.noDeveloperCertificates }

        let expiresAt = plist["ExpirationDate"] as? Date
        if let expiresAt, expiresAt <= Date() {
            throw NyxianProvisioningProfileValidationError.expired(expiresAt)
        }

        let fingerprints = developerCertificates.map(sha256Fingerprint(for:))
        let cleanedCertificateFingerprint = signingCertificateFingerprint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        var matchedFingerprint: String?
        if !cleanedCertificateFingerprint.isEmpty {
            guard let match = fingerprints.first(where: { $0.lowercased() == cleanedCertificateFingerprint }) else {
                throw NyxianProvisioningProfileValidationError.certificateMismatch
            }
            matchedFingerprint = match
        }

        let bundleIdentifier = profileBundleIdentifier(from: plist)
        let requestedBundle = requestedBundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !requestedBundle.isEmpty, !bundleIdentifier.isEmpty, !profileBundleIdentifierAllows(requestedBundle, profileBundleIdentifier: bundleIdentifier) {
            throw NyxianProvisioningProfileValidationError.bundleMismatch(profile: bundleIdentifier, requested: requestedBundle)
        }

        return NyxianProvisioningProfileSummary(
            name: plist["Name"] as? String ?? "Provisioning profile",
            uuid: plist["UUID"] as? String ?? "",
            teamIdentifiers: plist["TeamIdentifier"] as? [String] ?? [],
            bundleIdentifier: bundleIdentifier,
            expiresAt: expiresAt,
            developerCertificateFingerprints: fingerprints,
            matchedCertificateFingerprint: matchedFingerprint
        )
    }

    private static func profileBundleIdentifier(from plist: [String: Any]) -> String {
        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        if let applicationIdentifier = entitlements["application-identifier"] as? String,
           let dot = applicationIdentifier.firstIndex(of: ".") {
            return String(applicationIdentifier[applicationIdentifier.index(after: dot)...])
        }
        return ""
    }

    private static func profileBundleIdentifierAllows(_ bundleIdentifier: String, profileBundleIdentifier: String) -> Bool {
        if profileBundleIdentifier == bundleIdentifier { return true }
        guard profileBundleIdentifier.hasSuffix(".*") else { return false }
        let prefix = String(profileBundleIdentifier.dropLast(2))
        return bundleIdentifier.hasPrefix(prefix + ".")
    }

    private static func sha256Fingerprint(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
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

    static func loadIdentity() -> (data: Data, password: String)? {
        guard let data = UserDefaults.standard.data(forKey: certificateDataKey) else {
            return nil
        }
        let password = UserDefaults.standard.string(forKey: certificatePasswordKey) ?? ""
        return (data, password)
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
        let tunnelInterfaces = activeTunnelInterfaces()

        #if KITTYSTORE_MINIMUXER_LINKED
        setenv("USBMUXD_SOCKET_ADDRESS", "127.0.0.1:27015", 1)
        if KittyStoreMinimuxerBridge.isRuntimeReady {
            let interfaceText = tunnelInterfaces.isEmpty ? "no public tunnel interface name reported" : tunnelInterfaces.sorted().joined(separator: ", ")
            return NyxianLocalDevVPNState(
                isConnected: true,
                detail: "SideStore minimuxer reports LocalDevVPN ready (\(interfaceText))."
            )
        }
        if tunnelInterfaces.isEmpty {
            return NyxianLocalDevVPNState(
                isConnected: false,
                detail: "SideStore minimuxer is not ready and no active tunnel interface was found. Open LocalDevVPN, connect it, then retry with a valid pairing file."
            )
        }
        return NyxianLocalDevVPNState(
            isConnected: false,
            detail: "Found active tunnel interface(s) \(tunnelInterfaces.sorted().joined(separator: ", ")), but SideStore minimuxer is not ready. This is not treated as LocalDevVPN ready."
        )
        #else
        if tunnelInterfaces.isEmpty {
            return NyxianLocalDevVPNState(
                isConnected: false,
                detail: "SideStore minimuxer is not linked, and no active tunnel interface was found."
            )
        }
        return NyxianLocalDevVPNState(
            isConnected: false,
            detail: "Found active tunnel interface(s) \(tunnelInterfaces.sorted().joined(separator: ", ")), but this build cannot verify LocalDevVPN because the SideStore minimuxer bridge is not linked."
        )
        #endif
    }

    private static func activeTunnelInterfaces() -> [String] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return [] }
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
        return candidates
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
        teamID = try container.decodeIfPresent(String.self, forKey: .teamID) ?? ""
        anisetteServerURL = try container.decodeIfPresent(String.self, forKey: .anisetteServerURL)
        loggedInAt = try container.decodeIfPresent(Date.self, forKey: .loggedInAt)
            ?? container.decodeIfPresent(Date.self, forKey: .updatedAt)
            ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(email, forKey: .email)
        if !teamID.isEmpty { try container.encode(teamID, forKey: .teamID) }
        try container.encodeIfPresent(anisetteServerURL, forKey: .anisetteServerURL)
        try container.encode(loggedInAt, forKey: .loggedInAt)
    }

    var hasSelectedTeam: Bool {
        !teamID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var statusDetail: String {
        hasSelectedTeam ? "\(email) / \(teamID)" : "\(email) / Team not selected yet"
    }

    var anisetteDetail: String {
        anisetteServerURL ?? NyxianAnisetteServerDirectory.defaultServerURL
    }
}

enum NyxianAppleIDValidationError: LocalizedError {
    case invalidEmail
    case missingPassword
    case invalidTeamID
    case invalidAnisetteURL

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "Enter the Apple ID email used by SideStore or AltStore."
        case .missingPassword:
            return "Enter the Apple ID password or app-specific password used by your signer."
        case .invalidTeamID:
            return "Apple Developer Team IDs are 10 uppercase letters or numbers. Leave it blank if you want Litter to discover/select the team after Apple ID authentication."
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
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        if !teamID.isEmpty {
            guard teamID.count == 10,
                  teamID.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
                throw NyxianAppleIDValidationError.invalidTeamID
            }
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
        checkRevocation: Bool = true,
        requireEmbeddedProfileMatch: Bool = false
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
              let identityObject = item[kSecImportItemIdentity as String] else {
            throw NyxianSigningCertificateValidationError.noSigningIdentity
        }
        let identity = identityObject as! SecIdentity

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
        var matchedProvisioningProfile: EmbeddedProvisioningProfile?
        do {
            let provisioningProfile = try EmbeddedProvisioningProfile.load()
            if provisioningProfile.developerCertificates.isEmpty {
                if requireEmbeddedProfileMatch { throw NyxianSigningCertificateValidationError.provisioningProfileHasNoDeveloperCertificates }
            } else if provisioningProfile.developerCertificates.contains(certificateData) {
                matchedProvisioningProfile = provisioningProfile
            } else if requireEmbeddedProfileMatch {
                throw NyxianSigningCertificateValidationError.certificateDoesNotMatchProvisioningProfile(commonName)
            }
        } catch let error as NyxianSigningCertificateValidationError {
            if requireEmbeddedProfileMatch { throw error }
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
            provisioningProfileName: matchedProvisioningProfile?.name,
            provisioningProfileUUID: matchedProvisioningProfile?.uuid,
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
        return rawChain.map { $0 as! SecCertificate }
    }

    private static func evaluateTrust(
        certificate: SecCertificate,
        certificateChain: [SecCertificate],
        checkRevocation: Bool
    ) throws {
        var policies: [SecPolicy] = [SecPolicyCreateBasicX509()]
        if checkRevocation, let revocationPolicy = SecPolicyCreateRevocation(CFOptionFlags(kSecRevocationUseAnyAvailableMethod)) {
            policies.append(revocationPolicy)
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
        guard let plistData = NyxianProvisioningProfilePlist.extractPlistData(from: data) else {
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

}

private enum NyxianProvisioningProfilePlist {
    static func extractPlistData(from data: Data) -> Data? {
        let startMarker = Data("<?xml".utf8)
        let endMarker = Data("</plist>".utf8)
        guard let start = data.range(of: startMarker)?.lowerBound,
              let endRange = data.range(of: endMarker, options: [], in: start..<data.endIndex) else {
            return nil
        }
        return Data(data[start..<endRange.upperBound])
    }
}
