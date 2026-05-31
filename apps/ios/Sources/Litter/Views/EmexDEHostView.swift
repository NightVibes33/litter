import SwiftUI
import UIKit

#if !targetEnvironment(macCatalyst)
import emexDE
#endif

struct EmexDEHostView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        #if targetEnvironment(macCatalyst)
        EmexDEUnavailableViewController()
        #else
        EmexDEEmbeddedFactory.makeRootViewController()
        #endif
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

struct EmexDERouteView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .background(LitterTheme.background)
                .overlay(alignment: .bottom) { Divider() }

            EmexDEHostView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .background(LitterTheme.background.ignoresSafeArea())
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
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

            Text("emexDE")
                .litterFont(size: 16, weight: .semibold)
                .foregroundColor(LitterTheme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private final class EmexDEUnavailableViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.text = "emexDE is available in the iOS build."

        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
