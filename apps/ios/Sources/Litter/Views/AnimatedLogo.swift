import SwiftUI

/// Compact Alley Cat mark used in navigation chrome.
struct AnimatedLogo: View {
    var size: CGFloat = 44
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isLive = false

    var body: some View {
        AlleyCatMark(size: size * 0.82)
            .scaleEffect(isLive ? 1 : 0.94)
            .opacity(isLive ? 1 : 0.78)
            .animation(
                reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.72),
                value: isLive
            )
            .frame(width: size, height: size)
            .onAppear { isLive = true }
            .accessibilityHidden(true)
    }
}
