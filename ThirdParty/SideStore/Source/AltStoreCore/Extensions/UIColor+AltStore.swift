//
//  UIColor+AltStore.swift
//  AltStore
//
//  Created by Riley Testut on 5/9/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

public enum LitterSharedThemeColors
{
    private static let appGroupSuite = "group.com.sigkitten.litter"
    private static let appearanceModeKey = "appearanceMode"

    public static func background(fallback: UIColor) -> UIColor {
        themeColor(named: "background", fallback: fallback)
    }

    public static func surface(fallback: UIColor) -> UIColor {
        themeColor(named: "surface", fallback: fallback)
    }

    public static func accent(fallback: UIColor) -> UIColor {
        themeColor(named: "accent", fallback: fallback)
    }

    public static func accentStrong(fallback: UIColor) -> UIColor {
        themeColor(named: "accentStrong", fallback: fallback)
    }

    private static func themeColor(named key: String, fallback: UIColor) -> UIColor {
        UIColor { traits in
            guard let shared = UserDefaults(suiteName: appGroupSuite) else {
                return fallback.resolvedColor(with: traits)
            }

            let appearanceMode = shared.string(forKey: appearanceModeKey) ?? "system"
            let useDarkTheme: Bool
            switch appearanceMode {
            case "light":
                useDarkTheme = false
            case "dark":
                useDarkTheme = true
            default:
                useDarkTheme = traits.userInterfaceStyle == .dark
            }

            let prefix = useDarkTheme ? "theme.dark." : "theme.light."
            guard let hex = shared.string(forKey: "\(prefix)\(key)"),
                  let color = UIColor(hexString: hex) else {
                return fallback.resolvedColor(with: traits)
            }

            return color
        }
    }
}

public extension UIColor
{
    private static let colorBundle = Bundle(for: DatabaseManager.self)
    
    static var altPrimary: UIColor {
        LitterSharedThemeColors.accentStrong(
            fallback: UIColor(named: "Primary", in: colorBundle, compatibleWith: nil) ?? .systemBlue
        )
    }
    static let deltaPrimary = UIColor(named: "DeltaPrimary", in: colorBundle, compatibleWith: nil)
    static let clipPrimary = UIColor(named: "ClipPrimary", in: colorBundle, compatibleWith: nil)
    
    static let refreshRed = UIColor(named: "RefreshRed", in: colorBundle, compatibleWith: nil)!
    static let refreshOrange = UIColor(named: "RefreshOrange", in: colorBundle, compatibleWith: nil)!
    static let refreshYellow = UIColor(named: "RefreshYellow", in: colorBundle, compatibleWith: nil)!
    static let refreshGreen = UIColor(named: "RefreshGreen", in: colorBundle, compatibleWith: nil)!
}
