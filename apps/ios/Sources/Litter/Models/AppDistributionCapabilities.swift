import Foundation

enum AppDistributionCapabilities {
    static var isAppStoreSafe: Bool {
        #if LITTER_APP_STORE_SAFE
        true
        #else
        false
        #endif
    }

    static var unlocksProForSideload: Bool {
        #if ALLEY_CAT_SIDELOAD_UNLOCKED
        true
        #else
        false
        #endif
    }

    static var includesKittyStore: Bool {
        #if LITTER_APP_STORE_SAFE
        false
        #else
        bundleFlag(named: "LitterEmbedsSideStore", defaultValue: true)
        #endif
    }

    static var includesEmexDE: Bool {
        #if LITTER_APP_STORE_SAFE
        false
        #else
        bundleFlag(named: "LitterEmbedsEmexDE", defaultValue: true)
        #endif
    }

    private static func bundleFlag(named key: String, defaultValue: Bool) -> Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) else {
            return defaultValue
        }
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes": return true
            case "0", "false", "no": return false
            default: return defaultValue
            }
        }
        return defaultValue
    }
}
