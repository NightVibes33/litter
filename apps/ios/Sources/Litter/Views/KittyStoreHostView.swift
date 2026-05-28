import SwiftUI
import UIKit
import ObjectiveC

struct KittyStoreHostView: UIViewControllerRepresentable {
    @MainActor
    func makeUIViewController(context: Context) -> UIViewController {
        KittyStoreDynamicLoader.makeRootViewController()
    }

    @MainActor
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

@MainActor
private enum KittyStoreDynamicLoader {
    private typealias MakeRootViewControllerIMP = @convention(c) (AnyClass, Selector) -> UIViewController

    private static var cachedEntryPoint: NSObject.Type?

    static func makeRootViewController() -> UIViewController {
        do {
            let entryPoint = try loadEntryPoint()
            let selector = NSSelectorFromString("makeRootViewController")
            guard let method = class_getClassMethod(entryPoint, selector) else {
                throw KittyStoreDynamicLoaderError.entryPointMissing
            }

            let implementation = method_getImplementation(method)
            let makeRootViewController = unsafeBitCast(implementation, to: MakeRootViewControllerIMP.self)
            return makeRootViewController(entryPoint, selector)
        } catch {
            return KittyStoreUnavailableHostController(message: error.localizedDescription)
        }
    }

    private static func loadEntryPoint() throws -> NSObject.Type {
        if let cachedEntryPoint { return cachedEntryPoint }

        let frameworksURL = Bundle.main.privateFrameworksURL
            ?? Bundle.main.bundleURL.appendingPathComponent("Frameworks", isDirectory: true)
        let frameworkURL = frameworksURL.appendingPathComponent("SideStore.framework", isDirectory: true)
        guard let bundle = Bundle(url: frameworkURL) else {
            throw KittyStoreDynamicLoaderError.frameworkMissing(frameworkURL.path)
        }

        if !bundle.isLoaded, !bundle.load() {
            throw KittyStoreDynamicLoaderError.frameworkLoadFailed(frameworkURL.path)
        }

        for className in ["KittyStoreEmbeddedEntryPoint", "SideStore.KittyStoreEmbeddedEntryPoint"] {
            if let entryPoint = NSClassFromString(className) as? NSObject.Type {
                cachedEntryPoint = entryPoint
                return entryPoint
            }
        }

        throw KittyStoreDynamicLoaderError.entryPointMissing
    }
}

private enum KittyStoreDynamicLoaderError: LocalizedError {
    case frameworkMissing(String)
    case frameworkLoadFailed(String)
    case entryPointMissing

    var errorDescription: String? {
        switch self {
        case .frameworkMissing(let path):
            return "KittyStore framework is missing at " + path
        case .frameworkLoadFailed(let path):
            return "KittyStore framework could not be loaded from " + path
        case .entryPointMissing:
            return "KittyStore framework loaded, but its embedded entry point is missing."
        }
    }
}

private final class KittyStoreUnavailableHostController: UIViewController {
    private let message: String

    init(message: String) {
        self.message = message
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.message = "KittyStore could not be loaded."
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.text = "KittyStore Unavailable"
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        let messageLabel = UILabel()
        messageLabel.text = message
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, messageLabel])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
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
