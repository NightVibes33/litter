import SwiftUI
import UIKit
import SideStore

struct KittyStoreHostView: UIViewControllerRepresentable {
    @MainActor
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = KittyStoreEmbeddedFactory.makeRootViewController()
        KittyStoreEmbeddedFactory.startTransportIfPossible()
        return viewController
    }

    @MainActor
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        KittyStoreEmbeddedFactory.startTransportIfPossible()
    }
}

private enum KittyStoreHostPalette {
    static var background: Color {
        let bundle = Bundle(for: SideStore.AppDelegate.self)
        let fallback = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.1098, green: 0.1098, blue: 0.1176, alpha: 1)
                : .systemBackground
        }
        return Color(uiColor: UIColor(named: "Background", in: bundle, compatibleWith: nil) ?? fallback)
    }
}

struct KittyStoreRouteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @AppStorage("litterSettingsRequestedRoute") private var requestedSettingsRoute = ""

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .background(KittyStoreHostPalette.background)
                .overlay(alignment: .bottom) {
                    Divider()
                }

            KittyStoreHostView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .background(KittyStoreHostPalette.background.ignoresSafeArea())
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .litterFont(size: 17, weight: .semibold)
                    .foregroundColor(LitterTheme.textPrimary)
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .modifier(GlassCircleModifier())
            .accessibilityLabel("Back")

            Spacer(minLength: 0)

            Text("KittyStore")
                .litterFont(size: 16, weight: .semibold)
                .foregroundColor(LitterTheme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                requestedSettingsRoute = SettingsRoute.signing.rawValue
                appState.showSettings = true
            } label: {
                Image(systemName: "link.badge.plus")
                    .litterFont(size: 17, weight: .semibold)
                    .foregroundColor(LitterTheme.textPrimary)
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .modifier(GlassCircleModifier())
            .accessibilityLabel("Import Pairing File")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
