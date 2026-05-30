import Foundation

enum FeatherSigningUpstreamAdapter {
    static let optionsManagerReference = "ThirdParty/Feather/AppReference/Feather/Backend/Observable/OptionsManager.swift"
    static let signingHandlerReference = "ThirdParty/Feather/AppReference/Feather/Utilities/Handlers/SigningHandler.swift"
    static let zsignHandlerReference = "ThirdParty/Feather/AppReference/Feather/Utilities/Handlers/ZsignHandler.swift"
    static let tweakHandlerReference = "ThirdParty/Feather/AppReference/Feather/Utilities/Handlers/TweakHandler.swift"
    static let signingViewReference = "ThirdParty/Feather/AppReference/Feather/Views/Signing/SigningView.swift"
    static let signingPropertiesReference = "ThirdParty/Feather/AppReference/Feather/Views/Signing/SigningPropertiesView.swift"

    static func provenance() -> [String: Any] {
        [
            "featherReferences": [
                optionsManagerReference,
                signingHandlerReference,
                zsignHandlerReference,
                tweakHandlerReference,
                signingViewReference,
                signingPropertiesReference
            ],
            "sideStoreReferences": [
                "ThirdParty/SideStore/Source/AltStore/My Apps/MyAppsViewController.swift",
                "ThirdParty/SideStore/Source/AltStore/Sources/SourcesViewController.swift",
                "ThirdParty/SideStore/Source/Dependencies/minimuxer/Sources/Minimuxer.swift",
                "ThirdParty/SideStore/Source/Dependencies/minimuxer/Sources/Install.swift"
            ],
            "preservedLitterCustomizations": [
                "apps/ios/Sources/KittyStoreEmbedded/KittyStoreEmbeddedFactory.swift",
                "apps/ios/Sources/KittyStoreEmbedded/KittyStoreBranding.swift",
                "apps/ios/Sources/Litter/Views/KittyStoreHostView.swift",
                "apps/ios/Sources/Litter/Models/ThemeManager.swift",
                "apps/ios/Sources/Litter/Models/AppReleaseSource.swift"
            ]
        ]
    }

    static func signingOption(for signingType: FeatherSigningOptions.SigningType) -> String {
        signingOption(for: signingType.rawValue)
    }

    static func signingOption(for signingType: String) -> String {
        switch signingType.lowercased() {
        case "force", "modify", "onlymodify", "only-modify":
            return "onlyModify"
        case "adhoc", "ad-hoc", "ad_hoc":
            return "adhoc"
        default:
            return "default"
        }
    }

    static func properties(options: FeatherSigningOptions, customProperties: [String: Any]) -> [String: Any] {
        var properties = customProperties
        properties["appAppearance"] = options.appAppearance.rawValue
        properties["minimumAppRequirement"] = options.minimumRequirement.rawValue
        properties["signingOption"] = signingOption(for: options.signingType)
        properties["injectPath"] = options.injectPath.rawValue
        properties["injectFolder"] = options.injectFolder.rawValue
        properties["injectIntoExtensions"] = options.injectIntoExtensions
        properties["fileSharing"] = options.fileSharing
        properties["iTunesFileSharing"] = options.iTunesFileSharing
        properties["itunesFileSharing"] = options.iTunesFileSharing
        properties["proMotion"] = options.proMotion
        properties["gameMode"] = options.gameMode
        properties["ipadFullscreen"] = options.iPadFullscreen
        properties["removeURLScheme"] = options.removeURLScheme
        properties["removeProvisioning"] = options.removeProvisioning
        properties["changeLanguageFilesForCustomDisplayName"] = options.forceLocalize
        properties["experiment_supportLiquidGlass"] = options.supportLiquidGlass
        properties["experiment_replaceSubstrateWithEllekit"] = options.replaceSubstrateWithElleKit
        properties["postSigningAction"] = options.postSigningAction.rawValue
        properties["installAfterSigning"] = options.postSigningAction == .install
        properties["refreshAfterSigning"] = options.postSigningAction == .refresh
        properties["deleteAfterSigning"] = options.deleteAfterSigning
        properties["post_installAppAfterSigned"] = options.postSigningAction == .install
        properties["post_deleteAppAfterSigned"] = options.deleteAfterSigning
        return properties
    }

    static func optionsPayload(appName: String,
                               appVersion: String,
                               appIdentifier: String,
                               entitlementsFile: String,
                               signingType: String,
                               injectionFiles: [String],
                               frameworkAndPluginFiles: [String],
                               disInjectionFiles: [String],
                               removeFiles: [String],
                               properties: [String: Any]) -> [String: Any] {
        [
            "appName": appName,
            "appVersion": appVersion,
            "appIdentifier": appIdentifier,
            "appEntitlementsFile": entitlementsFile,
            "appAppearance": string(properties, "appAppearance", default: "default"),
            "minimumAppRequirement": string(properties, "minimumAppRequirement", default: "default"),
            "signingOption": signingOption(for: signingType),
            "injectPath": string(properties, "injectPath", default: "@executable_path"),
            "injectFolder": string(properties, "injectFolder", default: "/Frameworks/"),
            "ppqString": string(properties, "ppqString", default: ""),
            "ppqProtection": bool(properties, "ppqProtection"),
            "dynamicProtection": bool(properties, "dynamicProtection"),
            "identifiers": dictionary(properties, "identifiers"),
            "displayNames": dictionary(properties, "displayNames"),
            "injectionFiles": injectionFiles,
            "frameworkAndPluginFiles": frameworkAndPluginFiles,
            "disInjectionFiles": disInjectionFiles,
            "removeFiles": removeFiles,
            "fileSharing": bool(properties, "fileSharing"),
            "itunesFileSharing": bool(properties, "itunesFileSharing") || bool(properties, "iTunesFileSharing"),
            "proMotion": bool(properties, "proMotion"),
            "gameMode": bool(properties, "gameMode"),
            "ipadFullscreen": bool(properties, "ipadFullscreen"),
            "removeURLScheme": bool(properties, "removeURLScheme"),
            "removeProvisioning": bool(properties, "removeProvisioning"),
            "changeLanguageFilesForCustomDisplayName": bool(properties, "changeLanguageFilesForCustomDisplayName"),
            "injectIntoExtensions": bool(properties, "injectIntoExtensions"),
            "experiment_supportLiquidGlass": bool(properties, "experiment_supportLiquidGlass"),
            "experiment_replaceSubstrateWithEllekit": bool(properties, "experiment_replaceSubstrateWithEllekit"),
            "post_installAppAfterSigned": bool(properties, "post_installAppAfterSigned") || bool(properties, "installAfterSigning"),
            "post_deleteAppAfterSigned": bool(properties, "post_deleteAppAfterSigned") || bool(properties, "deleteAfterSigning"),
            "sourceFiles": [
                optionsManagerReference,
                signingHandlerReference,
                zsignHandlerReference,
                tweakHandlerReference
            ]
        ]
    }

    private static func string(_ dictionary: [String: Any], _ key: String, default defaultValue: String) -> String {
        guard let value = dictionary[key] else { return defaultValue }
        if let string = value as? String, !string.isEmpty { return string }
        if let convertible = value as? CustomStringConvertible { return convertible.description }
        return defaultValue
    }

    private static func bool(_ dictionary: [String: Any], _ key: String, default defaultValue: Bool = false) -> Bool {
        guard let value = dictionary[key] else { return defaultValue }
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "y", "on": return true
            case "0", "false", "no", "n", "off": return false
            default: return defaultValue
            }
        }
        return defaultValue
    }

    private static func dictionary(_ dictionary: [String: Any], _ key: String) -> [String: String] {
        guard let raw = dictionary[key] else { return [:] }
        if let value = raw as? [String: String] { return value }
        if let value = raw as? [String: Any] {
            return value.reduce(into: [String: String]()) { result, entry in
                if let string = entry.value as? String { result[entry.key] = string }
            }
        }
        return [:]
    }
}
