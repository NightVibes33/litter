import SwiftUI
import UIKit
import SideStore

struct KittyStoreHostView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        KittyStoreEmbeddedFactory.makeRootViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

struct KittyStoreRouteView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(.systemBackground)
                .ignoresSafeArea()

            KittyStoreHostView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

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
            .padding(.leading, 12)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .background(Color(.systemBackground).ignoresSafeArea())
        .ignoresSafeArea()
    }
}
