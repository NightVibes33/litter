import Foundation

struct KittyStoreSideStoreImportedAccount: Codable, Equatable, Sendable {
    var email: String
    var password: String
    var cert: Data
    var certpass: String
    var local_user: String
    var adiPB: String
}

struct KittyStoreSideStoreAccountImportSummary: Equatable, Sendable {
    var account: NyxianAppleIDAccount
    var certificate: NyxianSigningCertificateSummary
    var importedLocalUser: Bool
    var importedAdiPB: Bool

    var message: String {
        var lines = [
            "Imported SideStore .sideconf for \(account.email).",
            "Certificate: \(certificate.commonName)",
            "SHA256: \(certificate.sha256Fingerprint)",
            account.hasSelectedTeam ? "Team: \(account.teamID)" : "Team: not selected yet"
        ]
        if importedLocalUser && importedAdiPB {
            lines.append("SideStore ADI fields preserved for Apple API compatibility.")
        } else {
            lines.append("SideStore ADI fields were missing from this file.")
        }
        return lines.joined(separator: "\n")
    }
}

enum KittyStoreSideStoreAccountImporter {
    static func importSideconf(data: Data, anisetteServerURL: String) throws -> KittyStoreSideStoreAccountImportSummary {
        let imported = try JSONDecoder().decode(KittyStoreSideStoreImportedAccount.self, from: data)
        let certificateSummary = try NyxianSigningCertificateValidator.validate(
            pkcs12Data: imported.cert,
            password: imported.certpass,
            checkRevocation: true
        )
        NyxianSigningCertificateStorage.save(
            data: imported.cert,
            password: imported.certpass,
            summary: certificateSummary
        )
        let account = try NyxianAppleIDStore.login(
            email: imported.email,
            password: imported.password,
            teamID: "",
            anisetteServerURL: anisetteServerURL,
            sideStoreLocalUserIdentifier: imported.local_user,
            sideStoreAdiPB: imported.adiPB
        )
        return KittyStoreSideStoreAccountImportSummary(
            account: account,
            certificate: certificateSummary,
            importedLocalUser: !imported.local_user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            importedAdiPB: !imported.adiPB.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }
}
