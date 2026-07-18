import SwiftUI

struct BrandLogo: View {
    var size: CGFloat

    var body: some View {
        VStack(spacing: max(5, size * 0.055)) {
            AlleyCatMark(size: size * 0.62)
            Text("ALLEY C\u{00C3}T")
                .litterFont(size: max(11, size * 0.135), weight: .bold)
                .tracking(max(1.4, size * 0.018))
                .foregroundStyle(LitterTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Alley C\u{00E3}t")
    }
}

struct AlleyCatMark: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: size * 0.08,
                bottomLeadingRadius: size * 0.28,
                bottomTrailingRadius: size * 0.08,
                topTrailingRadius: size * 0.28,
                style: .continuous
            )
            .fill(LitterTheme.surface)
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: size * 0.08,
                    bottomLeadingRadius: size * 0.28,
                    bottomTrailingRadius: size * 0.08,
                    topTrailingRadius: size * 0.28,
                    style: .continuous
                )
                .stroke(LitterTheme.accent.opacity(0.9), lineWidth: max(1.5, size * 0.035))
            }

            Image(systemName: "cat.fill")
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(LitterTheme.accent)

            Rectangle()
                .fill(LitterTheme.accentStrong)
                .frame(width: size * 0.34, height: max(2, size * 0.045))
                .offset(x: size * 0.29, y: -size * 0.34)
        }
        .frame(width: size, height: size)
    }
}

#if DEBUG
#Preview("Brand Logo") {
    ZStack {
        AlleyBackdrop().ignoresSafeArea()
        BrandLogo(size: 128)
    }
}
#endif
