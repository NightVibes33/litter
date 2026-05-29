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

private enum KittyStoreDynamicLoader {
    private static let frameworkName = "SideStore"
    private static let entryPointClassNames = [
        "KittyStoreEmbeddedEntryPoint",
        "SideStore.KittyStoreEmbeddedEntryPoint"
    ]

    @MainActor
    static func makeRootViewController() -> UIViewController {
        do {
            let entryPoint = try loadEntryPointClass()
            return try invokeRootViewController(on: entryPoint)
        } catch {
            return KittyStoreUnavailableViewController(message: error.localizedDescription)
        }
    }

    @MainActor
    static func startTransportIfPossible() {
        do {
            let entryPoint = try loadEntryPointClass()
            try invokeVoidClassMethod(NSSelectorFromString("startTransportIfPossible"), on: entryPoint)
        } catch {
            LLog.error("kittystore", "failed to start embedded transport", error: error)
        }
    }

    private static func loadEntryPointClass() throws -> AnyClass {
        let bundle = try loadFrameworkBundle()
        for className in entryPointClassNames {
            if let entryPoint = NSClassFromString(className) {
                return entryPoint
            }
        }
        let bundleID = bundle.bundleIdentifier ?? "unknown bundle"
        throw NSError(
            domain: "KittyStoreDynamicLoader",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "KittyStore entry point class was not found in \(bundleID)."]
        )
    }

    private static func loadFrameworkBundle() throws -> Bundle {
        let candidates = frameworkCandidates()
        for url in candidates {
            guard FileManager.default.fileExists(atPath: url.path), let bundle = Bundle(url: url) else { continue }
            if bundle.isLoaded { return bundle }
            var loadError: NSError?
            if bundle.loadAndReturnError(&loadError) {
                return bundle
            }
            throw loadError ?? NSError(
                domain: "KittyStoreDynamicLoader",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "KittyStore framework failed to load from \(url.path)."]
            )
        }
        let checked = candidates.map(\.path).joined(separator: "\n")
        throw NSError(
            domain: "KittyStoreDynamicLoader",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "KittyStore framework is missing. Checked:\n\(checked)"]
        )
    }

    private static func frameworkCandidates() -> [URL] {
        var urls: [URL] = []
        if let frameworksURL = Bundle.main.privateFrameworksURL {
            urls.append(frameworksURL.appendingPathComponent("\(frameworkName).framework", isDirectory: true))
        }
        urls.append(Bundle.main.bundleURL.appendingPathComponent("Frameworks/\(frameworkName).framework", isDirectory: true))
        return urls
    }

    @MainActor
    private static func invokeRootViewController(on entryPoint: AnyClass) throws -> UIViewController {
        let selector = NSSelectorFromString("makeRootViewController")
        guard let method = class_getClassMethod(entryPoint, selector) else {
            throw NSError(
                domain: "KittyStoreDynamicLoader",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "KittyStore entry point does not implement makeRootViewController."]
            )
        }
        typealias RootFactory = @convention(c) (AnyObject, Selector) -> AnyObject
        let implementation = method_getImplementation(method)
        let factory = unsafeBitCast(implementation, to: RootFactory.self)
        guard let viewController = factory(entryPoint as AnyObject, selector) as? UIViewController else {
            throw NSError(
                domain: "KittyStoreDynamicLoader",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "KittyStore entry point returned an invalid root view controller."]
            )
        }
        return viewController
    }

    private static func invokeVoidClassMethod(_ selector: Selector, on entryPoint: AnyClass) throws {
        guard let method = class_getClassMethod(entryPoint, selector) else {
            throw NSError(
                domain: "KittyStoreDynamicLoader",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "KittyStore entry point does not implement \(NSStringFromSelector(selector))."]
            )
        }
        typealias VoidMethod = @convention(c) (AnyObject, Selector) -> Void
        let implementation = method_getImplementation(method)
        let function = unsafeBitCast(implementation, to: VoidMethod.self)
        function(entryPoint as AnyObject, selector)
    }
}

private final class KittyStoreUnavailableViewController: UIViewController {
    private let message: String

    init(message: String) {
        self.message = message
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = message
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
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
