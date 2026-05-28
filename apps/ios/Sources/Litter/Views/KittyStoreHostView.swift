import SwiftUI
import UIKit
import SideStore

struct KittyStoreHostView: UIViewControllerRepresentable {
    @MainActor
    func makeUIViewController(context: Context) -> UIViewController {
        KittyStoreEmbeddedFactory.makeRootViewController()
    }

    @MainActor
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

struct KittyStoreRouteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @AppStorage("litterSettingsRequestedRoute") private var requestedSettingsRoute = ""

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground)
                .ignoresSafeArea()

            KittyStoreHostView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            HStack {
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
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .background(Color(.systemBackground).ignoresSafeArea())
        .ignoresSafeArea()
    }
}
