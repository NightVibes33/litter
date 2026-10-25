import AVFoundation
import SwiftUI
import UIKit

/// A looping, muted video player for wallpaper backgrounds.
struct VideoWallpaperPlayerView: UIViewRepresentable {
    let fileURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.backgroundColor = .clear

        let player = AVQueuePlayer()
        player.isMuted = true

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(playerLayer)
        view.playerLayer = playerLayer

        let templateItem = AVPlayerItem(url: fileURL)
        let looper = AVPlayerLooper(player: player, templateItem: templateItem)

        context.coordinator.player = player
        context.coordinator.playerLayer = playerLayer
        context.coordinator.looper = looper
        context.coordinator.currentURL = fileURL
        context.coordinator.setupNotifications()

        player.play()

        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        // If the file URL changed, rebuild the looper
        if context.coordinator.currentURL != fileURL {
            context.coordinator.currentURL = fileURL
            if let player = context.coordinator.player {
                context.coordinator.looper?.disableLooping()
                context.coordinator.looper = nil
                player.removeAllItems()
                let templateItem = AVPlayerItem(url: fileURL)
                context.coordinator.looper = AVPlayerLooper(player: player, templateItem: templateItem)
                player.play()
            }
        }
    }

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        var player: AVQueuePlayer?
        var playerLayer: AVPlayerLayer?
        var looper: AVPlayerLooper?
        var currentURL: URL?
        private var backgroundObserver: NSObjectProtocol?
        private var foregroundObserver: NSObjectProtocol?

        func setupNotifications() {
            backgroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.player?.pause()
            }

            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.player?.play()
            }
        }

        func tearDown() {
            player?.pause()
            looper?.disableLooping()
            looper = nil
            player?.removeAllItems()
            player = nil
            if let bg = backgroundObserver {
                NotificationCenter.default.removeObserver(bg)
            }
            if let fg = foregroundObserver {
                NotificationCenter.default.removeObserver(fg)
            }
            backgroundObserver = nil
            foregroundObserver = nil
        }

        deinit {
            if let bg = backgroundObserver {
                NotificationCenter.default.removeObserver(bg)
            }
            if let fg = foregroundObserver {
                NotificationCenter.default.removeObserver(fg)
            }
        }
    }
}

/// UIView subclass that keeps its AVPlayerLayer sized to bounds via layoutSubviews.
final class PlayerContainerView: UIView {
    var playerLayer: AVPlayerLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }
}
