import SwiftUI

/// Themed eyebrow heading — small uppercased mono text. When `color` is nil
/// it falls back to the live `WatchThemeStore` accent so unstyled callers
/// inherit the user's selected theme.
struct WatchEyebrow: View {
    @EnvironmentObject var theme: WatchThemeStore
    let text: String
    var color: Color? = nil
    var size: CGFloat = 11

    var body: some View {
        Text(text.uppercased())
            .font(WatchTheme.mono(size, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(color ?? theme.accent)
    }
}

/// Pulsing dot used to signal activity.
struct PulsingDot: View {
    let color: Color
    var size: CGFloat = 6
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.9), radius: pulse ? 5 : 2)
            .scaleEffect(pulse ? 1.15 : 1)
            .animation(
                .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                value: pulse
            )
            .onAppear { pulse = true }
    }
}

/// Skeleton placeholder for a single `TaskPage`. Three of these stack inside
/// a `TabView` during the cold-launch syncing window so the home feels alive
/// instead of presenting an empty card. Pulses opacity in/out subtly.
struct SkeletonTaskPlaceholder: View {
    @EnvironmentObject var theme: WatchThemeStore
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            chip(width: 56, height: 10)

            VStack(alignment: .leading, spacing: 6) {
                bar(width: nil, height: 13)
                bar(width: 0.7, height: 13)
            }
            .padding(.top, 2)

            chip(width: 110, height: 9)
                .padding(.top, 2)

            bar(width: 0.9, height: 10)
            bar(width: 0.6, height: 10)

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                Capsule()
                    .fill(theme.surfaceLight)
                    .frame(maxWidth: .infinity, minHeight: 28)
                Capsule()
                    .fill(theme.surfaceLight)
                    .frame(width: 32, height: 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .opacity(pulse ? 0.55 : 0.85)
        .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                   value: pulse)
        .onAppear { pulse = true }
    }

    private func bar(width: CGFloat?, height: CGFloat) -> some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 3)
                .fill(theme.surfaceLight)
                .frame(width: width.map { geo.size.width * $0 } ?? geo.size.width,
                       height: height)
        }
        .frame(height: height)
    }

    private func chip(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(theme.surfaceLight)
            .frame(width: width, height: height)
    }
}

/// Centered empty-state card. Used when the watch has no data for a
/// surface yet — either no pending approval, no running task, etc.
struct WatchEmptyState: View {
    @EnvironmentObject var theme: WatchThemeStore
    let icon: String
    let title: String
    let subtitle: String?

    init(icon: String, title: String, subtitle: String? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.textSecondary)
            Text(title)
                .font(WatchTheme.mono(12, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(WatchTheme.mono(10))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 6)
    }
}
