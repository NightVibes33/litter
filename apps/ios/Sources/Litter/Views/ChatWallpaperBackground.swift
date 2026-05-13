import SwiftUI

/// Displays a scoped wallpaper (thread → server → fallback gradient).
struct ChatWallpaperBackground: View {
    @Environment(WallpaperManager.self) private var wallpaperManager
    @Environment(ThemeManager.self) private var themeManager

    var threadKey: ThreadKey?

    var body: some View {
        let _ = wallpaperManager.version // trigger recomposition on wallpaper changes
        let config = wallpaperManager.resolveConfig(for: threadKey)

        if let config, config.type != .none {
            wallpaperContent(for: config)
                .blur(radius: config.blur * 20)
                .opacity(config.brightness)
                .ignoresSafeArea()
        } else {
            LitterTheme.backgroundGradient.ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func wallpaperContent(for config: WallpaperConfig) -> some View {
        switch config.type {
        case .preset:
            if let slug = config.presetSlug,
               let image = wallpaperManager.generatePresetWallpaper(presetSlug: slug) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LitterTheme.backgroundGradient
            }
        case .theme:
            if let slug = config.themeSlug,
               let image = wallpaperManager.generateWallpaper(themeSlug: slug, themeManager: themeManager) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LitterTheme.backgroundGradient
            }
        case .customImage:
            if let scope = wallpaperScope,
               let image = wallpaperManager.wallpaperImage(for: config, scope: scope, themeManager: themeManager) {
                FittedWallpaperImage(image: image)
            } else {
                LitterTheme.backgroundGradient
            }
        case .solidColor:
            if let hex = config.colorHex {
                Color(hex: hex)
            } else {
                LitterTheme.backgroundGradient
            }
        case .customVideo, .videoUrl:
            if let scope = wallpaperScope,
               FileManager.default.fileExists(atPath: wallpaperManager.videoFileURL(for: scope).path) {
                VideoWallpaperPlayerView(fileURL: wallpaperManager.videoFileURL(for: scope))
            } else {
                LitterTheme.backgroundGradient
            }
        case .none:
            LitterTheme.backgroundGradient
        }
    }

    private var wallpaperScope: WallpaperScope? {
        guard let key = threadKey else { return nil }
        // Check if there's a thread-specific config first
        let threadScopeKey = "\(key.serverId)::\(key.threadId)"
        // We just need to determine scope for image loading
        return .thread(key)
    }
}

struct FittedWallpaperImage: View {
    let image: UIImage

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LitterTheme.backgroundGradient
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
