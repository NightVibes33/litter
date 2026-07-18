import SwiftUI

struct BrandLogo: View {
    var size: CGFloat

    var body: some View {
        VStack(spacing: max(7, size * 0.065)) {
            AlleyCatMark(size: size * 0.64)
            Text("ALLEY C\u{00C3}T")
                .litterFont(size: max(11, size * 0.13), weight: .bold)
                .tracking(max(0.8, size * 0.01))
                .foregroundStyle(LitterTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Alley C\u{00E3}t")
    }
}

struct AlleyCatMark: View {
    var size: CGFloat

    var body: some View {
        Image("app_icon_current")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: max(0.5, size * 0.012))
            }
            .shadow(color: Color.black.opacity(0.18), radius: size * 0.12, x: 0, y: size * 0.06)
            .accessibilityHidden(true)
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
