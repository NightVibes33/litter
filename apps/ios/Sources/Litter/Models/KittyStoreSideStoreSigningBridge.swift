import Foundation
import UIKit

#if canImport(AltSign)
import AltSign
#endif

#if canImport(CAltSign)
import CAltSign
#endif

enum KittyStoreSideStoreSigningBridge {
    struct AuthenticationSummary: Equatable, Sendable {
        var email: String
        var teamID: String
        var teamName: String
        var teamType: String
        var availableTeams: [TeamSummary]
        var anisetteServerURL: String

        var statusDetail: String {
            if teamID.isEmpty { return "\(email) / Team not selected yet" }
            return "\(email) / \(teamName) (\(teamID))"
        }
    }

    struct TeamSummary: Equatable, Sendable {
        var id: String
        var name: String
        var type: String

        var displayText: String {
            "\(name) (\(id), \(type))"
        }
    }

    struct OperationResult: Equatable, Sendable {
        var exitCode: Int
        var status: String
        var log: String
        var signedIPAPath: String?
        var provisioningProfileData: Data?
    }

    static var isLinked: Bool {
        #if canImport(AltSign) && canImport(CAltSign)
        true
        #else
        false
        #endif
    }

    static func authenticate(
        email rawEmail: String,
        password rawPassword: String,
        requestedTeamID rawRequestedTeamID: String,
        anisetteServerURL rawAnisetteServerURL: String,
        twoFactorCode rawTwoFactorCode: String,
        verificationHandler: ((@escaping (String?) -> Void) -> Void)? = nil
    ) async -> Result<AuthenticationSummary, Error> {
        #if canImport(AltSign) && canImport(CAltSign)
        do {
            let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let password = rawPassword.trimmingCharacters(in: .whitespacesAndNewlines)
            let requestedTeamID = rawRequestedTeamID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let twoFactorCode = rawTwoFactorCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let anisetteServerURL = try NyxianAnisetteServerDirectory.normalizedServerURL(rawAnisetteServerURL)

            guard email.contains("@"), email.contains(".") else { throw NyxianAppleIDValidationError.invalidEmail }
            guard !password.isEmpty else { throw NyxianAppleIDValidationError.missingPassword }

            let anisetteData = try await fetchAnisetteData(serverURL: anisetteServerURL)
            let (account, session) = try await authenticateAccount(
                email: email,
                password: password,
                anisetteData: anisetteData,
                twoFactorCode: twoFactorCode,
                verificationHandler: verificationHandler
            )
            let teams = try await fetchTeams(account: account, session: session)
            guard let selectedTeam = selectTeam(from: teams, requestedTeamID: requestedTeamID) else {
                let teamText = teams.map { teamSummary($0).displayText }.joined(separator: "\n")
                throw NSError(
                    domain: "KittyStoreSideStoreSigningBridge",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: teamText.isEmpty ? "Apple ID authenticated, but no Apple Developer team was returned." : "Team ID not found. Available teams:\n\(teamText)"]
                )
            }

            let summary = AuthenticationSummary(
                email: account.appleID.isEmpty ? email : account.appleID,
                teamID: selectedTeam.identifier,
                teamName: selectedTeam.name,
                teamType: teamTypeDescription(selectedTeam.type),
                availableTeams: teams.map(teamSummary(_:)),
                anisetteServerURL: anisetteServerURL
            )
            return .success(summary)
        } catch {
            return .failure(error)
        }
        #else
        return .failure(unavailableError)
        #endif
    }

    static func signIPAWithAppleID(
        ipaURL: URL,
        outputDirectory: URL,
        bundleIdentifier: String,
        appName: String,
        appVersion: String,
        email: String,
        password: String,
        requestedTeamID: String,
        anisetteServerURL: String,
        twoFactorCode: String,
        deviceUDID: String?
    ) async -> OperationResult {
        #if canImport(AltSign) && canImport(CAltSign)
        do {
            let auth = try await authenticatedSession(
                email: email,
                password: password,
                requestedTeamID: requestedTeamID,
                anisetteServerURL: anisetteServerURL,
                twoFactorCode: twoFactorCode
            )
            if let deviceUDID, !deviceUDID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                _ = try await registerDeviceIfNeeded(udid: deviceUDID, team: auth.team, session: auth.session)
            }
            let certificate = try await requestCertificate(team: auth.team, session: auth.session, appName: appName)
            let prepared = try await prepareSideStoreAppleIDSigningInput(
                ipaURL: ipaURL,
                outputDirectory: outputDirectory,
                requestedBundleIdentifier: bundleIdentifier,
                appName: appName,
                appVersion: appVersion,
                team: auth.team,
                session: auth.session
            )
            defer { try? FileManager.default.removeItem(at: prepared.workingDirectoryURL) }

            let signer = ALTSigner(team: auth.team, certificate: certificate)
            try await sign(signer: signer, appURL: prepared.appBundleURL, provisioningProfiles: prepared.profiles)
            let signedArchiveURL = try FileManager.default.zipAppBundle(at: prepared.appBundleURL)
            let outputURL = try stagedOutputURL(for: ipaURL, in: outputDirectory)
            if FileManager.default.fileExists(atPath: outputURL.path) { try FileManager.default.removeItem(at: outputURL) }
            try FileManager.default.copyItem(at: signedArchiveURL, to: outputURL)
            try? FileManager.default.removeItem(at: signedArchiveURL)

            return OperationResult(
                exitCode: 0,
                status: "sidestore-appleid-sign-ok",
                log: "Signed IPA with SideStore Apple ID flow.\nInput: \(ipaURL.path)\nOutput: \(outputURL.path)\nTeam: \(auth.team.name) (\(auth.team.identifier))\nOriginal bundle ID: \(prepared.originalBundleIdentifier)\nSigned bundle ID: \(prepared.mainBundleIdentifier)\nProfiles: \(prepared.profiles.map { $0.bundleIdentifier }.joined(separator: ", "))\n",
                signedIPAPath: outputURL.path,
                provisioningProfileData: prepared.mainProfile.data
            )
        } catch {
            return OperationResult(exitCode: 70, status: "sidestore-appleid-sign-failed", log: error.localizedDescription + "\n", signedIPAPath: nil, provisioningProfileData: nil)
        }
        #else
        return OperationResult(exitCode: 78, status: "sidestore-altsign-not-linked", log: unavailableError.localizedDescription + "\n", signedIPAPath: nil, provisioningProfileData: nil)
        #endif
    }

    static func signIPAWithImportedIdentity(
        ipaURL: URL,
        outputDirectory: URL,
        bundleIdentifier: String,
        appName: String,
        appVersion: String,
        teamID rawTeamID: String,
        teamName rawTeamName: String?,
        certificateData: Data,
        certificatePassword: String,
        provisioningProfileData: Data
    ) async -> OperationResult {
        #if canImport(AltSign) && canImport(CAltSign)
        do {
            do {
                let certificateSummary = try NyxianSigningCertificateValidator.validate(
                    pkcs12Data: certificateData,
                    password: certificatePassword,
                    checkRevocation: true
                )
                _ = try NyxianProvisioningProfileValidator.validate(
                    data: provisioningProfileData,
                    signingCertificateFingerprint: certificateSummary.sha256Fingerprint,
                    requestedBundleIdentifier: bundleIdentifier
                )
            } catch {
                return OperationResult(
                    exitCode: 65,
                    status: "sidestore-certificate-validation-failed",
                    log: "SideStore AltSign rejected the imported .p12/profile before signing. \(error.localizedDescription)\n",
                    signedIPAPath: nil,
                    provisioningProfileData: nil
                )
            }

            guard let certificate = ALTCertificate(p12Data: certificateData, password: certificatePassword) else {
                return OperationResult(exitCode: 65, status: "sidestore-certificate-invalid", log: "AltSign could not open the .p12 identity. The password may be wrong or the file may not contain a signing identity.\n", signedIPAPath: nil, provisioningProfileData: nil)
            }
            guard certificate.privateKey != nil else {
                return OperationResult(exitCode: 65, status: "sidestore-certificate-no-private-key", log: "AltSign opened the certificate but it does not contain a private key.\n", signedIPAPath: nil, provisioningProfileData: nil)
            }
            guard let profile = ALTProvisioningProfile(data: provisioningProfileData) else {
                return OperationResult(exitCode: 66, status: "sidestore-profile-invalid", log: "AltSign could not parse the mobileprovision profile.\n", signedIPAPath: nil, provisioningProfileData: nil)
            }

            let requestedTeamID = rawTeamID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let profileTeamID = profile.teamIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let teamID = requestedTeamID.isEmpty ? profileTeamID : requestedTeamID
            guard !teamID.isEmpty else {
                return OperationResult(exitCode: 64, status: "sidestore-team-missing", log: "SideStore/AltSign signing requires a team ID from the selected Apple account or the imported provisioning profile.\n", signedIPAPath: nil, provisioningProfileData: nil)
            }
            if !profileTeamID.isEmpty, profileTeamID != teamID {
                return OperationResult(
                    exitCode: 67,
                    status: "sidestore-profile-team-mismatch",
                    log: "Provisioning profile team ID \(profileTeamID) does not match selected team \(teamID).\n",
                    signedIPAPath: nil,
                    provisioningProfileData: nil
                )
            }

            if !profile.certificates.contains(where: { $0.serialNumber == certificate.serialNumber }) {
                return OperationResult(
                    exitCode: 67,
                    status: "sidestore-profile-certificate-mismatch",
                    log: "The imported provisioning profile does not include the selected signing certificate.\n",
                    signedIPAPath: nil,
                    provisioningProfileData: nil
                )
            }

            let profileBundleID = profile.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            let requestedBundleID = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            if !profileBundleID.isEmpty, !requestedBundleID.isEmpty, !profileBundleIdentifierAllows(requestedBundleID, profileBundleIdentifier: profileBundleID) {
                return OperationResult(
                    exitCode: 67,
                    status: "sidestore-profile-bundle-mismatch",
                    log: "Provisioning profile bundle ID \(profileBundleID) does not match \(requestedBundleID).\n",
                    signedIPAPath: nil,
                    provisioningProfileData: nil
                )
            }

            let account = ALTAccount()
            account.appleID = ""
            account.firstName = appDisplayName
            account.lastName = ""
            let cleanedTeamName = rawTeamName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let profileName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let teamName = !cleanedTeamName.isEmpty ? cleanedTeamName : (!profileName.isEmpty ? profileName : "Imported Signing Team")
            let team = ALTTeam(
                name: teamName,
                identifier: teamID,
                type: .unknown,
                account: account
            )
            let prepared = try prepareSideStoreImportedIdentitySigningInput(
                ipaURL: ipaURL,
                outputDirectory: outputDirectory,
                requestedBundleIdentifier: bundleIdentifier,
                appName: appName,
                appVersion: appVersion,
                profile: profile
            )
            defer { try? FileManager.default.removeItem(at: prepared.workingDirectoryURL) }

            let outputURL = try stagedOutputURL(for: ipaURL, in: outputDirectory)
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: outputURL.path) { try fileManager.removeItem(at: outputURL) }
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)

            let signer = ALTSigner(team: team, certificate: certificate)
            try await sign(signer: signer, appURL: prepared.appBundleURL, provisioningProfiles: [profile])
            let signedArchiveURL = try fileManager.zipAppBundle(at: prepared.appBundleURL)
            try fileManager.copyItem(at: signedArchiveURL, to: outputURL)
            try? fileManager.removeItem(at: signedArchiveURL)
            return OperationResult(
                exitCode: 0,
                status: "sidestore-altsign-sign-ok",
                log: "Signed IPA with SideStore AltSign.\nInput: \(ipaURL.path)\nOutput: \(outputURL.path)\nProfile: \(profile.name) / \(profile.bundleIdentifier)\nTeam: \(teamID)\nOriginal bundle ID: \(prepared.originalBundleIdentifier)\nSigned bundle ID: \(prepared.mainBundleIdentifier)\n",
                signedIPAPath: outputURL.path,
                provisioningProfileData: profile.data
            )
        } catch {
            return OperationResult(exitCode: 70, status: "sidestore-altsign-sign-failed", log: error.localizedDescription + "\n", signedIPAPath: nil, provisioningProfileData: nil)
        }
        #else
        return OperationResult(exitCode: 78, status: "sidestore-altsign-not-linked", log: unavailableError.localizedDescription + "\n", signedIPAPath: nil, provisioningProfileData: nil)
        #endif
    }

    private static var unavailableError: NSError {
        NSError(
            domain: "KittyStoreSideStoreSigningBridge",
            code: 78,
            userInfo: [NSLocalizedDescriptionKey: "SideStore AltSign is not linked into this build. Re-run XcodeGen and build with the vendored ThirdParty/SideStore/AltSign package available."]
        )
    }
}

#if canImport(AltSign) && canImport(CAltSign)
private extension KittyStoreSideStoreSigningBridge {
    struct AuthenticatedSession {
        var account: ALTAccount
        var session: ALTAppleAPISession
        var team: ALTTeam
        var teams: [ALTTeam]
    }

    struct PreparedAppleIDSigningInput {
        var workingDirectoryURL: URL
        var appBundleURL: URL
        var originalBundleIdentifier: String
        var mainBundleIdentifier: String
        var profiles: [ALTProvisioningProfile]
        var mainProfile: ALTProvisioningProfile
    }

    struct PreparedImportedIdentitySigningInput {
        var workingDirectoryURL: URL
        var appBundleURL: URL
        var originalBundleIdentifier: String
        var mainBundleIdentifier: String
    }

    static func authenticatedSession(
        email rawEmail: String,
        password rawPassword: String,
        requestedTeamID rawRequestedTeamID: String,
        anisetteServerURL rawAnisetteServerURL: String,
        twoFactorCode rawTwoFactorCode: String
    ) async throws -> AuthenticatedSession {
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let password = rawPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedTeamID = rawRequestedTeamID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let twoFactorCode = rawTwoFactorCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let anisetteServerURL = try NyxianAnisetteServerDirectory.normalizedServerURL(rawAnisetteServerURL)
        guard email.contains("@"), email.contains(".") else { throw NyxianAppleIDValidationError.invalidEmail }
        guard !password.isEmpty else { throw NyxianAppleIDValidationError.missingPassword }

        let anisetteData = try await fetchAnisetteData(serverURL: anisetteServerURL)
        let (account, session) = try await authenticateAccount(
            email: email,
            password: password,
            anisetteData: anisetteData,
            twoFactorCode: twoFactorCode
        )
        let teams = try await fetchTeams(account: account, session: session)
        guard let team = selectTeam(from: teams, requestedTeamID: requestedTeamID) else {
            let teamText = teams.map { teamSummary($0).displayText }.joined(separator: "\n")
            throw NSError(
                domain: "KittyStoreSideStoreSigningBridge",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: teamText.isEmpty ? "Apple ID authenticated, but no Apple Developer team was returned." : "Team ID not found. Available teams:\n\(teamText)"]
            )
        }
        return AuthenticatedSession(account: account, session: session, team: team, teams: teams)
    }

    static func prepareSideStoreAppleIDSigningInput(
        ipaURL: URL,
        outputDirectory: URL,
        requestedBundleIdentifier: String,
        appName: String,
        appVersion: String,
        team: ALTTeam,
        session: ALTAppleAPISession
    ) async throws -> PreparedAppleIDSigningInput {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)
        let workingDirectoryURL = outputDirectory.appendingPathComponent("SideStoreWork-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workingDirectoryURL, withIntermediateDirectories: true, attributes: nil)

        let appBundleURL = try fileManager.unzipAppBundle(at: ipaURL, toDirectory: workingDirectoryURL)
        guard let application = ALTApplication(fileURL: appBundleURL) else {
            throw NSError(domain: "KittyStoreSideStoreSigningBridge", code: 65, userInfo: [NSLocalizedDescriptionKey: "AltSign could not read an app bundle from the imported IPA."])
        }
        let originalMainBundleIdentifier = application.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let mainBundleIdentifier = sideStoreBundleIdentifier(
            requestedBundleIdentifier: requestedBundleIdentifier,
            originalBundleIdentifier: originalMainBundleIdentifier,
            teamID: team.identifier
        )

        var profilesByOriginalBundleID: [String: ALTProvisioningProfile] = [:]
        let mainProfile = try await fetchFreshProvisioningProfile(
            name: application.name.isEmpty ? appName : application.name,
            bundleIdentifier: mainBundleIdentifier,
            team: team,
            session: session
        )
        profilesByOriginalBundleID[originalMainBundleIdentifier] = mainProfile

        var extensionBundleIdentifiers: [String: String] = [:]
        for appExtension in application.appExtensions {
            let originalExtensionBundleIdentifier = appExtension.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !originalExtensionBundleIdentifier.isEmpty else { continue }
            let effectiveExtensionBundleIdentifier = sideStoreExtensionBundleIdentifier(
                originalExtensionBundleIdentifier: originalExtensionBundleIdentifier,
                originalMainBundleIdentifier: originalMainBundleIdentifier,
                effectiveMainBundleIdentifier: mainBundleIdentifier
            )
            extensionBundleIdentifiers[originalExtensionBundleIdentifier] = effectiveExtensionBundleIdentifier
            let profile = try await fetchFreshProvisioningProfile(
                name: [application.name, appExtension.name].filter { !$0.isEmpty }.joined(separator: " "),
                bundleIdentifier: effectiveExtensionBundleIdentifier,
                team: team,
                session: session
            )
            profilesByOriginalBundleID[originalExtensionBundleIdentifier] = profile
        }

        try applySideStoreBundleIdentifiers(
            application: application,
            mainBundleIdentifier: mainBundleIdentifier,
            extensionBundleIdentifiers: extensionBundleIdentifiers,
            appName: appName,
            appVersion: appVersion
        )

        let profiles = Array(profilesByOriginalBundleID.values)
        return PreparedAppleIDSigningInput(
            workingDirectoryURL: workingDirectoryURL,
            appBundleURL: appBundleURL,
            originalBundleIdentifier: originalMainBundleIdentifier,
            mainBundleIdentifier: mainBundleIdentifier,
            profiles: profiles,
            mainProfile: mainProfile
        )
    }

    static func prepareSideStoreImportedIdentitySigningInput(
        ipaURL: URL,
        outputDirectory: URL,
        requestedBundleIdentifier: String,
        appName: String,
        appVersion: String,
        profile: ALTProvisioningProfile
    ) throws -> PreparedImportedIdentitySigningInput {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)
        let workingDirectoryURL = outputDirectory.appendingPathComponent("SideStoreImportWork-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workingDirectoryURL, withIntermediateDirectories: true, attributes: nil)

        let appBundleURL = try fileManager.unzipAppBundle(at: ipaURL, toDirectory: workingDirectoryURL)
        guard let application = ALTApplication(fileURL: appBundleURL) else {
            throw NSError(domain: "KittyStoreSideStoreSigningBridge", code: 65, userInfo: [NSLocalizedDescriptionKey: "AltSign could not read an app bundle from the imported IPA."])
        }

        let originalMainBundleIdentifier = application.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let mainBundleIdentifier = importedIdentityBundleIdentifier(
            requestedBundleIdentifier: requestedBundleIdentifier,
            originalBundleIdentifier: originalMainBundleIdentifier,
            profileBundleIdentifier: profile.bundleIdentifier
        )
        if !profile.bundleIdentifier.isEmpty,
           !mainBundleIdentifier.isEmpty,
           !profileBundleIdentifierAllows(mainBundleIdentifier, profileBundleIdentifier: profile.bundleIdentifier) {
            throw NSError(
                domain: "KittyStoreSideStoreSigningBridge",
                code: 67,
                userInfo: [NSLocalizedDescriptionKey: "Provisioning profile bundle ID \(profile.bundleIdentifier) does not allow \(mainBundleIdentifier)."]
            )
        }

        var extensionBundleIdentifiers: [String: String] = [:]
        for appExtension in application.appExtensions {
            let originalExtensionBundleIdentifier = appExtension.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !originalExtensionBundleIdentifier.isEmpty else { continue }
            extensionBundleIdentifiers[originalExtensionBundleIdentifier] = sideStoreExtensionBundleIdentifier(
                originalExtensionBundleIdentifier: originalExtensionBundleIdentifier,
                originalMainBundleIdentifier: originalMainBundleIdentifier,
                effectiveMainBundleIdentifier: mainBundleIdentifier
            )
        }

        try applySideStoreBundleIdentifiers(
            application: application,
            mainBundleIdentifier: mainBundleIdentifier,
            extensionBundleIdentifiers: extensionBundleIdentifiers,
            appName: appName,
            appVersion: appVersion
        )

        return PreparedImportedIdentitySigningInput(
            workingDirectoryURL: workingDirectoryURL,
            appBundleURL: appBundleURL,
            originalBundleIdentifier: originalMainBundleIdentifier,
            mainBundleIdentifier: mainBundleIdentifier
        )
    }

    static func sideStoreBundleIdentifier(requestedBundleIdentifier: String, originalBundleIdentifier: String, teamID: String) -> String {
        let requested = requestedBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = originalBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let team = teamID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let base = requested.isEmpty ? original : requested
        guard !team.isEmpty, !base.hasSuffix("." + team) else {
            return base
        }
        return base + "." + team
    }

    static func importedIdentityBundleIdentifier(requestedBundleIdentifier: String, originalBundleIdentifier: String, profileBundleIdentifier: String) -> String {
        let requested = requestedBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if !requested.isEmpty { return requested }
        let profile = profileBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if !profile.isEmpty, !profile.hasSuffix(".*") { return profile }
        return originalBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sideStoreExtensionBundleIdentifier(
        originalExtensionBundleIdentifier: String,
        originalMainBundleIdentifier: String,
        effectiveMainBundleIdentifier: String
    ) -> String {
        if originalExtensionBundleIdentifier.hasPrefix(originalMainBundleIdentifier + ".") {
            let suffix = String(originalExtensionBundleIdentifier.dropFirst(originalMainBundleIdentifier.count))
            return effectiveMainBundleIdentifier + suffix
        }
        let fallbackName = originalExtensionBundleIdentifier.split(separator: ".").last.map(String.init) ?? "Extension"
        return effectiveMainBundleIdentifier + "." + fallbackName
    }

    static func applySideStoreBundleIdentifiers(
        application: ALTApplication,
        mainBundleIdentifier: String,
        extensionBundleIdentifiers: [String: String],
        appName: String,
        appVersion: String
    ) throws {
        try rewriteInfoPlist(
            in: application.fileURL,
            bundleIdentifier: mainBundleIdentifier,
            displayName: appName,
            version: appVersion
        )
        for appExtension in application.appExtensions {
            let originalBundleIdentifier = appExtension.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let bundleIdentifier = extensionBundleIdentifiers[originalBundleIdentifier] else { continue }
            try rewriteInfoPlist(
                in: appExtension.fileURL,
                bundleIdentifier: bundleIdentifier,
                displayName: "",
                version: appVersion
            )
        }
    }

    static func rewriteInfoPlist(in bundleURL: URL, bundleIdentifier: String, displayName: String, version: String) throws {
        let infoPlistURL = bundleURL.appendingPathComponent("Info.plist")
        guard let infoDictionary = NSMutableDictionary(contentsOf: infoPlistURL) else {
            throw NSError(domain: "KittyStoreSideStoreSigningBridge", code: 66, userInfo: [NSLocalizedDescriptionKey: "Could not read Info.plist at \(infoPlistURL.path)."])
        }
        let cleanedBundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedBundleIdentifier.isEmpty {
            infoDictionary[kCFBundleIdentifierKey as String] = cleanedBundleIdentifier
        }
        if !cleanedDisplayName.isEmpty {
            infoDictionary["CFBundleName"] = cleanedDisplayName
            infoDictionary["CFBundleDisplayName"] = cleanedDisplayName
        }
        if !cleanedVersion.isEmpty, cleanedVersion.lowercased() != "unknown" {
            infoDictionary["CFBundleShortVersionString"] = cleanedVersion
            infoDictionary["CFBundleVersion"] = cleanedVersion
        }
        infoDictionary.removeObject(forKey: "DTXcode")
        infoDictionary.removeObject(forKey: "DTXcodeBuild")
        guard infoDictionary.write(to: infoPlistURL, atomically: true) else {
            throw NSError(domain: "KittyStoreSideStoreSigningBridge", code: 66, userInfo: [NSLocalizedDescriptionKey: "Could not write Info.plist at \(infoPlistURL.path)."])
        }
        let signatureURL = bundleURL.appendingPathComponent("_CodeSignature", isDirectory: true)
        if FileManager.default.fileExists(atPath: signatureURL.path) {
            try FileManager.default.removeItem(at: signatureURL)
        }
    }

    static func requestCertificate(team: ALTTeam, session: ALTAppleAPISession, appName: String) async throws -> ALTCertificate {
        let certificate: ALTCertificate = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ALTCertificate, Error>) in
            let machineName = certificateMachineName(appName: appName, accountFirstName: team.account.firstName)
            ALTAppleAPI.shared.addCertificate(machineName: machineName, to: team, session: session) { certificate, error in
                if let error { continuation.resume(throwing: error) }
                else if let certificate { continuation.resume(returning: certificate) }
                else { continuation.resume(throwing: NSError(domain: "KittyStoreSideStoreSigningBridge", code: 500, userInfo: [NSLocalizedDescriptionKey: "Apple did not return a signing certificate."])) }
            }
        }
        guard let privateKey = certificate.privateKey else {
            throw NSError(domain: "KittyStoreSideStoreSigningBridge", code: 500, userInfo: [NSLocalizedDescriptionKey: "Apple returned a certificate without a private key."])
        }
        let certificates = try await fetchCertificates(team: team, session: session)
        if let serverCertificate = certificates.first(where: { $0.serialNumber == certificate.serialNumber }) {
            serverCertificate.privateKey = privateKey
            return serverCertificate
        }
        return certificate
    }

    static func fetchCertificates(team: ALTTeam, session: ALTAppleAPISession) async throws -> [ALTCertificate] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ALTCertificate], Error>) in
            ALTAppleAPI.shared.fetchCertificates(for: team, session: session) { certificates, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: certificates ?? []) }
            }
        }
    }

    static func registerDeviceIfNeeded(udid rawUDID: String, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTDevice {
        let udid = rawUDID.trimmingCharacters(in: .whitespacesAndNewlines)
        let devices = try await fetchDevices(team: team, session: session)
        if let existing = devices.first(where: { $0.identifier.caseInsensitiveCompare(udid) == .orderedSame }) {
            return existing
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ALTDevice, Error>) in
            ALTAppleAPI.shared.registerDevice(name: deviceRegistrationName, identifier: udid, type: .iphone, team: team, session: session) { device, error in
                if let error { continuation.resume(throwing: error) }
                else if let device { continuation.resume(returning: device) }
                else { continuation.resume(throwing: NSError(domain: "KittyStoreSideStoreSigningBridge", code: 500, userInfo: [NSLocalizedDescriptionKey: "Apple did not return a registered device."])) }
            }
        }
    }

    static func fetchDevices(team: ALTTeam, session: ALTAppleAPISession) async throws -> [ALTDevice] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ALTDevice], Error>) in
            ALTAppleAPI.shared.fetchDevices(for: team, types: [.iphone, .ipad], session: session) { devices, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: devices ?? []) }
            }
        }
    }

    static func fetchOrCreateAppID(name: String, bundleIdentifier: String, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTAppID {
        let appIDs = try await fetchAppIDs(team: team, session: session)
        if let existing = appIDs.first(where: { $0.bundleIdentifier.lowercased() == bundleIdentifier.lowercased() }) {
            return existing
        }
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let appIDName = !cleanedName.isEmpty && cleanedName.unicodeScalars.allSatisfy { $0.isASCII } ? cleanedName : bundleIdentifier
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ALTAppID, Error>) in
            ALTAppleAPI.shared.addAppID(withName: appIDName, bundleIdentifier: bundleIdentifier, team: team, session: session) { appID, error in
                if let error { continuation.resume(throwing: error) }
                else if let appID { continuation.resume(returning: appID) }
                else { continuation.resume(throwing: NSError(domain: "KittyStoreSideStoreSigningBridge", code: 500, userInfo: [NSLocalizedDescriptionKey: "Apple did not return an App ID."])) }
            }
        }
    }

    static func fetchAppIDs(team: ALTTeam, session: ALTAppleAPISession) async throws -> [ALTAppID] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ALTAppID], Error>) in
            ALTAppleAPI.shared.fetchAppIDs(for: team, session: session) { appIDs, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: appIDs ?? []) }
            }
        }
    }

    static func fetchFreshProvisioningProfile(name: String, bundleIdentifier: String, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTProvisioningProfile {
        let appID = try await fetchOrCreateAppID(name: name, bundleIdentifier: bundleIdentifier, team: team, session: session)
        let profile = try await fetchProvisioningProfile(appID: appID, team: team, session: session)
        do {
            _ = try await deleteProvisioningProfile(profile, team: team, session: session)
            return try await fetchProvisioningProfile(appID: appID, team: team, session: session)
        } catch {
            return profile
        }
    }

    static func fetchProvisioningProfile(appID: ALTAppID, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTProvisioningProfile {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ALTProvisioningProfile, Error>) in
            ALTAppleAPI.shared.fetchProvisioningProfile(for: appID, deviceType: .iphone, team: team, session: session) { profile, error in
                if let error { continuation.resume(throwing: error) }
                else if let profile { continuation.resume(returning: profile) }
                else { continuation.resume(throwing: NSError(domain: "KittyStoreSideStoreSigningBridge", code: 500, userInfo: [NSLocalizedDescriptionKey: "Apple did not return a provisioning profile."])) }
            }
        }
    }

    static func deleteProvisioningProfile(_ profile: ALTProvisioningProfile, team: ALTTeam, session: ALTAppleAPISession) async throws -> Bool {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            ALTAppleAPI.shared.delete(profile, for: team, session: session) { success, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: success) }
            }
        }
    }

    static func fetchAnisetteData(serverURL rawServerURL: String) async throws -> ALTAnisetteData {
        guard let url = URL(string: rawServerURL) else { throw NyxianAppleIDValidationError.invalidAnisetteURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "KittyStoreSideStoreSigningBridge", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Anisette server returned HTTP \(http.statusCode)"])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw NSError(domain: "KittyStoreSideStoreSigningBridge", code: 422, userInfo: [NSLocalizedDescriptionKey: "Anisette server did not return the SideStore header JSON format."])
        }

        var formatted: [String: String] = ["deviceSerialNumber": json["X-Apple-I-SRL-NO"] ?? "0"]
        if let value = json["X-Apple-I-MD-M"] { formatted["machineID"] = value }
        if let value = json["X-Apple-I-MD"] { formatted["oneTimePassword"] = value }
        if let value = json["X-Apple-I-MD-RINFO"] { formatted["routingInfo"] = value }
        if let value = json["X-MMe-Client-Info"] { formatted["deviceDescription"] = value }
        if let value = json["X-Apple-I-MD-LU"] { formatted["localUserID"] = value }
        if let value = json["X-Mme-Device-Id"] { formatted["deviceUniqueIdentifier"] = value }
        if let value = json["X-Apple-I-Client-Time"] { formatted["date"] = value }
        if let value = json["X-Apple-Locale"] { formatted["locale"] = value }
        if let value = json["X-Apple-I-TimeZone"] { formatted["timeZone"] = value }

        guard let anisetteData = ALTAnisetteData(json: formatted) else {
            throw NSError(domain: "KittyStoreSideStoreSigningBridge", code: 422, userInfo: [NSLocalizedDescriptionKey: "Anisette headers were incomplete or invalid for AltSign."])
        }
        return anisetteData
    }

    static func authenticateAccount(
        email: String,
        password: String,
        anisetteData: ALTAnisetteData,
        twoFactorCode: String,
        verificationHandler providedVerificationHandler: ((@escaping (String?) -> Void) -> Void)? = nil
    ) async throws -> (ALTAccount, ALTAppleAPISession) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(ALTAccount, ALTAppleAPISession), Error>) in
            let trimmedTwoFactorCode = twoFactorCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let verificationHandler: ((@escaping (String?) -> Void) -> Void)? = providedVerificationHandler ?? { callback in
                callback(trimmedTwoFactorCode.isEmpty ? nil : trimmedTwoFactorCode)
            }
            ALTAppleAPI.shared.authenticate(
                appleID: email,
                password: password,
                anisetteData: anisetteData,
                verificationHandler: verificationHandler
            ) { account, session, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let account, let session {
                    continuation.resume(returning: (account, session))
                } else {
                    continuation.resume(throwing: NSError(domain: "KittyStoreSideStoreSigningBridge", code: 500, userInfo: [NSLocalizedDescriptionKey: "Apple authentication returned no account session."]))
                }
            }
        }
    }

    static func fetchTeams(account: ALTAccount, session: ALTAppleAPISession) async throws -> [ALTTeam] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ALTTeam], Error>) in
            ALTAppleAPI.shared.fetchTeams(for: account, session: session) { teams, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: teams ?? []) }
            }
        }
    }

    static func selectTeam(from teams: [ALTTeam], requestedTeamID: String) -> ALTTeam? {
        if !requestedTeamID.isEmpty {
            return teams.first { $0.identifier.uppercased() == requestedTeamID }
        }
        return teams.first { $0.type == .free } ?? teams.first
    }

    static func teamSummary(_ team: ALTTeam) -> TeamSummary {
        TeamSummary(id: team.identifier, name: team.name, type: teamTypeDescription(team.type))
    }

    static func teamTypeDescription(_ type: ALTTeamType) -> String {
        switch type {
        case .free: return "free"
        case .individual: return "individual"
        case .organization: return "organization"
        default: return "unknown"
        }
    }

    static var appDisplayName: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let displayName = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? "Litter"
        let cleaned = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Litter" : cleaned
    }

    static var deviceRegistrationName: String {
        let cleaned = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? UIDevice.current.model : cleaned
    }

    static func certificateMachineName(appName: String, accountFirstName: String) -> String {
        let cleanedAppName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let brandName = cleanedAppName.isEmpty ? appDisplayName : cleanedAppName
        let asciiBrand = brandName.unicodeScalars.allSatisfy(\.isASCII) ? brandName : appDisplayName
        let owner = accountFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let ownerText = owner.isEmpty ? "user" : owner
        return "\(asciiBrand) - \(ownerText)'s \(deviceRegistrationName)"
    }

    static func stagedOutputURL(for ipaURL: URL, in directory: URL) throws -> URL {
        let baseName = ipaURL.deletingPathExtension().lastPathComponent
        let safeBase = baseName.isEmpty ? "Signed" : baseName
        return directory.appendingPathComponent("\(safeBase)-SideStoreSigned-\(UUID().uuidString.prefix(8)).ipa")
    }

    static func profileBundleIdentifierAllows(_ bundleIdentifier: String, profileBundleIdentifier: String) -> Bool {
        if profileBundleIdentifier == bundleIdentifier {
            return true
        }
        guard profileBundleIdentifier.hasSuffix(".*") else {
            return false
        }
        let prefix = String(profileBundleIdentifier.dropLast(2))
        return bundleIdentifier.hasPrefix(prefix + ".")
    }

    static func sign(signer: ALTSigner, appURL: URL, provisioningProfiles: [ALTProvisioningProfile]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            _ = signer.signApp(at: appURL, provisioningProfiles: provisioningProfiles) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "KittyStoreSideStoreSigningBridge", code: 70, userInfo: [NSLocalizedDescriptionKey: "AltSign failed without a specific error."]))
                }
            }
        }
    }
}
#endif
