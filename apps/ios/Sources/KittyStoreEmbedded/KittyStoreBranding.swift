import Foundation

enum KittyStoreBranding {
    static func text(_ text: String?) -> String? {
        guard let text else { return nil }

        return text
            .replacingOccurrences(of: "SideStore/AltStore", with: "KittyStore/AltStore")
            .replacingOccurrences(of: "SideStore and AltStore", with: "KittyStore and AltStore")
            .replacingOccurrences(of: "SideStore or AltStore", with: "KittyStore or AltStore")
            .replacingOccurrences(of: "SideStore-compatible", with: "KittyStore-compatible")
            .replacingOccurrences(of: "SideStore News", with: "KittyStore News")
            .replacingOccurrences(of: "AltStore News", with: "KittyStore News")
            .replacingOccurrences(of: "SideStore", with: "KittyStore")
            .replacingOccurrences(of: "Side Store", with: "KittyStore")
            .replacingOccurrences(of: "AltServer", with: "LocalDevVPN")
            .replacingOccurrences(of: "KittyStore KittyStore", with: "KittyStore")
            .replacingOccurrences(of: "KittyStore/KittyStore", with: "KittyStore/AltStore")
    }

    static func attributedText(_ attributedText: NSAttributedString?) -> NSAttributedString? {
        guard let attributedText,
              let brandedText = text(attributedText.string),
              brandedText != attributedText.string else {
            return attributedText
        }

        let copy = NSMutableAttributedString(attributedString: attributedText)
        copy.mutableString.setString(brandedText)
        return copy
    }
}
