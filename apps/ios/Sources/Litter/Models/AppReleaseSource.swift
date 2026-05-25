import Foundation

struct AppReleaseSource: Equatable, Sendable {
    var owner: String
    var repo: String
    var manifestAssetName: String
    var sourceAssetName: String
    var stableTag: String
    var releaseTagPrefix: String

    static let ownerKey = "LitterReleaseOwner"
    static let repoKey = "LitterReleaseRepo"
    static let manifestAssetNameKey = "LitterReleaseManifestAssetName"
    static let sourceAssetNameKey = "LitterReleaseSourceAssetName"
    static let stableTagKey = "LitterReleaseStableTag"
    static let releaseTagPrefixKey = "LitterReleaseTagPrefix"

    static let defaultOwner = "NightVibes33"
    static let defaultRepo = "litter"
    static let defaultManifestAssetName = "litter-update.json"
    static let defaultSourceAssetName = "litter-altstore-source.json"
    static let defaultStableTag = "app-source"
    static let defaultReleaseTagPrefix = "litter-v"

    static var current: AppReleaseSource {
        AppReleaseSource(
            owner: configuredValue(key: ownerKey, fallback: defaultOwner),
            repo: configuredValue(key: repoKey, fallback: defaultRepo),
            manifestAssetName: configuredValue(key: manifestAssetNameKey, fallback: defaultManifestAssetName),
            sourceAssetName: configuredValue(key: sourceAssetNameKey, fallback: defaultSourceAssetName),
            stableTag: configuredValue(key: stableTagKey, fallback: defaultStableTag),
            releaseTagPrefix: configuredValue(key: releaseTagPrefixKey, fallback: defaultReleaseTagPrefix)
        )
    }

    static func saveOverrides(
        owner: String? = nil,
        repo: String? = nil,
        manifestAssetName: String? = nil,
        sourceAssetName: String? = nil,
        stableTag: String? = nil,
        releaseTagPrefix: String? = nil
    ) {
        let defaults = UserDefaults.standard
        setOverride(owner, key: ownerKey, defaults: defaults)
        setOverride(repo, key: repoKey, defaults: defaults)
        setOverride(manifestAssetName, key: manifestAssetNameKey, defaults: defaults)
        setOverride(sourceAssetName, key: sourceAssetNameKey, defaults: defaults)
        setOverride(stableTag, key: stableTagKey, defaults: defaults)
        setOverride(releaseTagPrefix, key: releaseTagPrefixKey, defaults: defaults)
    }

    static func clearOverrides() {
        let defaults = UserDefaults.standard
        [ownerKey, repoKey, manifestAssetNameKey, sourceAssetNameKey, stableTagKey, releaseTagPrefixKey].forEach {
            defaults.removeObject(forKey: $0)
        }
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

    private static func setOverride(_ value: String?, key: String, defaults: UserDefaults) {
        guard let normalized = value.flatMap(normalize) else { return }
        defaults.set(normalized, forKey: key)
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
