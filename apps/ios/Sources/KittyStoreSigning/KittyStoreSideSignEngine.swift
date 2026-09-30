import Foundation
import SideSign

/// Keep the host's account and UI models stable while using SideStore's new signer.
enum KittyStoreSideSignEngine {
    static func sign(
        appURL: URL,
        teamIdentifier: String,
        teamName: String,
        teamType: String,
        certificateP12: Data,
        provisioningProfileData: [Data],
        progress: Progress? = nil
    ) async throws {
        try Task.checkCancellation()
        let type: SideSign.TeamType
        switch teamType {
        case "free": type = .free
        case "individual": type = .individual
        case "organization": type = .organization
        default: type = .unknown
        }
        let team = SideSign.Team(identifier: teamIdentifier, name: teamName, type: type)
        let certificate = try SideSign.KeyStore(p12Data: certificateP12, password: nil)
        let profiles = try provisioningProfileData.map { try SideSign.ProvisioningProfile(data: $0) }
        let signer = SideSign.AppBundleSigner(team: team, keyStore: certificate)
        try await signer.signApp(at: appURL, provisioningProfiles: profiles, progress: progress)
        try Task.checkCancellation()
        if let progress { progress.completedUnitCount = progress.totalUnitCount }
    }
}
