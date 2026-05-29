//
//  UIColor+AltStore.swift
//  AltStore
//
//  Created by Riley Testut on 5/23/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit
import AltStoreCore

extension UIColor
{
    private static let altStoreBundle = Bundle(for: AppDelegate.self)

    static func altAssetColor(named name: String, fallback: UIColor) -> UIColor {
        UIColor(named: name, in: altStoreBundle, compatibleWith: nil) ?? fallback
    }

    static var altBackground: UIColor {
        LitterSharedThemeColors.background(fallback: altAssetColor(named: "Background", fallback: .systemBackground))
    }

    static var altGradientTop: UIColor {
        LitterSharedThemeColors.accentStrong(fallback: altAssetColor(named: "GradientTop", fallback: .systemBlue))
    }

    static var altGradientBottom: UIColor {
        LitterSharedThemeColors.accent(fallback: altAssetColor(named: "GradientBottom", fallback: .systemIndigo))
    }

    static let altDarkButtonBackground = altAssetColor(named: "DarkButtonBackground", fallback: .secondarySystemFill)
    static var altSettingsBackground: UIColor {
        LitterSharedThemeColors.background(fallback: altAssetColor(named: "SettingsBackground", fallback: .systemGroupedBackground))
    }

    static var altSettingsHighlighted: UIColor {
        LitterSharedThemeColors.accentStrong(fallback: altAssetColor(named: "SettingsHighlighted", fallback: .systemBlue))
    }

    static var altBlurTint: UIColor {
        LitterSharedThemeColors.surface(fallback: altAssetColor(named: "BlurTint", fallback: .secondarySystemBackground))
    }
}

extension UIColor
{
    private static let brightnessMaxThreshold = 0.85
    private static let brightnessMinThreshold = 0.35
    
    private static let saturationBrightnessThreshold = 0.5
    
    var adjustedForDisplay: UIColor {
        guard self.isTooBright || self.isTooDark else { return self }
        
        return UIColor { traits in
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            guard self.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil) else { return self }
            
            brightness = min(brightness, UIColor.brightnessMaxThreshold)
            
            if traits.userInterfaceStyle == .dark
            {
                // Only raise brightness when in dark mode.
                brightness = max(brightness, UIColor.brightnessMinThreshold)
            }
            
            let color = UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1.0)
            return color
        }
    }
    
    var isTooBright: Bool {
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        
        guard self.getHue(nil, saturation: &saturation, brightness: &brightness, alpha: nil) else { return false }
        
        let isTooBright = (brightness >= UIColor.brightnessMaxThreshold && saturation <= UIColor.saturationBrightnessThreshold)
        return isTooBright
    }
    
    var isTooDark: Bool {
        var brightness: CGFloat = 0
        guard self.getHue(nil, saturation: nil, brightness: &brightness, alpha: nil) else { return false }
                
        let isTooDark = brightness <= UIColor.brightnessMinThreshold
        return isTooDark
    }
}
