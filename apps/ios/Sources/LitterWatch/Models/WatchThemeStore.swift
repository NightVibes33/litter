import SwiftUI

/// Observable holder for the active palette pushed from the iPhone. Falls back
/// to `WatchTheme` defaults until a payload arrives, so cold launches with no
/// snapshot look identical to the prior hardcoded design.
@MainActor
final class WatchThemeStore: ObservableObject {
    static let shared = WatchThemeStore()

    @Published private(set) var palette: WatchThemePayload?

    func apply(_ payload: WatchThemePayload?) {
        guard payload != palette else { return }
        palette = payload
    }

    // MARK: - Resolved colors

    var accent: Color        { palette.map { Color(themeHex: $0.accent) } ?? WatchTheme.ginger }
    var accentStrong: Color  { palette.map { Color(themeHex: $0.accentStrong) } ?? WatchTheme.ginger }
    var accentSoft: Color    { accent.opacity(0.7) }
    var textPrimary: Color   { palette.map { Color(themeHex: $0.textPrimary) } ?? WatchTheme.text }
    var textSecondary: Color { palette.map { Color(themeHex: $0.textSecondary) } ?? WatchTheme.dim }
    var textMuted: Color     { palette.map { Color(themeHex: $0.textMuted) } ?? WatchTheme.dimMore }
    var surface: Color       { palette.map { Color(themeHex: $0.surface) } ?? WatchTheme.surface }
    var surfaceLight: Color  { palette.map { Color(themeHex: $0.surfaceLight) } ?? WatchTheme.surfaceHi }
    var border: Color        { palette.map { Color(themeHex: $0.border) } ?? WatchTheme.border }
    var borderHi: Color      { border.opacity(0.85) }
    var danger: Color        { palette.map { Color(themeHex: $0.danger) } ?? WatchTheme.danger }
    var success: Color       { palette.map { Color(themeHex: $0.success) } ?? WatchTheme.success }
    var successSoft: Color   { success.opacity(0.7) }
    var warning: Color       { palette.map { Color(themeHex: $0.warning) } ?? WatchTheme.ginger }
    var textOnAccent: Color  { palette.map { Color(themeHex: $0.textOnAccent) } ?? WatchTheme.onAccent }

    var backgroundTop: Color    { palette.map { Color(themeHex: $0.backgroundTop) } ?? WatchTheme.bg }
    var backgroundBottom: Color { palette.map { Color(themeHex: $0.backgroundBottom) } ?? WatchTheme.bg }

    var backgroundGradient: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom],
                       startPoint: .top, endPoint: .bottom)
    }

    var isDark: Bool { palette?.isDark ?? true }
    var colorScheme: ColorScheme { isDark ? .dark : .light }
}

// MARK: - String hex helper (distinct label avoids colliding with Color(hex: UInt32))

extension Color {
    init(themeHex string: String) {
        let cleaned = string.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8)  & 0xFF) / 255
        let b = Double(v         & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
