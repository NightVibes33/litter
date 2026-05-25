import Foundation

struct AppReleaseSource: Equatable, Sendable {
    var owner: String
    var repo: String
    var manifestAssetName: String
    var sourceAssetName: String
    var stableTag: String
    var releaseTagPrefix: String

    static let defaultOwner = "NightVibes33"
    static let defaultRepo = "litter"
    static let defaultManifestAssetName = "litter-update.json"
    static let defaultSourceAssetName = "litter-altstore-source.json"
    static let defaultStableTag = "app-source"
    static let defaultReleaseTagPrefix = "litter-v"

    static var current: AppReleaseSource {
        AppReleaseSource(
            owner: configuredValue(key: "LitterReleaseOwner", fallback: defaultOwner),
            repo: configuredValue(key: "LitterReleaseRepo", fallback: defaultRepo),
            manifestAssetName: configuredValue(key: "LitterReleaseManifestAssetName", fallback: defaultManifestAssetName),
            sourceAssetName: configuredValue(key: "LitterReleaseSourceAssetName", fallback: defaultSourceAssetName),
            stableTag: configuredValue(key: "LitterReleaseStableTag", fallback: defaultStableTag),
            releaseTagPrefix: configuredValue(key: "LitterReleaseTagPrefix", fallback: defaultReleaseTagPrefix)
        )
    }

    var repositoryPath: String {
        "\(owner)/\(repo)"
    }

    var releasesURLString: String {
        "https://github.com/\(repositoryPath)/releases"
    }

    var stableUpdateURLString: String {
        stableAssetURLString(assetName: manifestAssetName)
    }

    var stableSourceURLString: String {
        stableAssetURLString(assetName: sourceAssetName)
    }

    func releaseURLString(version: String) -> String {
        "https://github.com/\(repositoryPath)/releases/tag/\(releaseTagPrefix)\(version)"
    }

    private func stableAssetURLString(assetName: String) -> String {
        "https://github.com/\(repositoryPath)/releases/download/\(stableTag)/\(assetName)"
    }

    private static func configuredValue(key: String, fallback: String) -> String {
        if let value = UserDefaults.standard.string(forKey: key), let normalized = normalize(value) {
            return normalized
        }
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, let normalized = normalize(value) {
            return normalized
        }
        return fallback
    }

    private static func normalize(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }
}
