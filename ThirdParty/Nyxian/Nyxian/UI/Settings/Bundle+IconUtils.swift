//
//  IconTool.swift
//  Nyxian
//
//  Created by Frida on 17.05.26.
//

import Foundation

extension Bundle {
    public var alternateIconNames: [String] {
        guard let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
              let alt = icons["CFBundleAlternateIcons"] as? [String: Any] else { return [] }
        return Array(alt.keys)
    }
}
