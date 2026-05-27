import Foundation
import Nuke
import UIKit
import AltStoreCore

public enum SideStoreEmbeddedFactory {
    @MainActor
    public static func makeRootViewController() -> UIViewController {
        KittyStoreRootViewController()
    }

    @MainActor
    public static func bootstrap() {
        SideStoreEmbeddedRuntime.startIfNeeded()
    }
}

open class AppDelegate: NSObject, UIApplicationDelegate {
    public static let openPatreonSettingsDeepLinkNotification = Notification.Name(Bundle.Info.appbundleIdentifier + ".OpenPatreonSettingsDeepLinkNotification")
    public static let importAppDeepLinkNotification = Notification.Name(Bundle.Info.appbundleIdentifier + ".ImportAppDeepLinkNotification")
    public static let addSourceDeepLinkNotification = Notification.Name(Bundle.Info.appbundleIdentifier + ".AddSourceDeepLinkNotification")
    public static let appBackupDidFinish = Notification.Name(Bundle.Info.appbundleIdentifier + ".AppBackupDidFinish")
    public static let exportCertificateNotification = Notification.Name(Bundle.Info.appbundleIdentifier + ".ExportCertificateNotification")

    public static let importAppDeepLinkURLKey = "fileURL"
    public static let appBackupResultKey = "result"
    public static let addSourceDeepLinkURLKey = "sourceURL"
    public static let exportCertificateCallbackTemplateKey = "callback"

    let consoleLog = ConsoleLog()

    public override init() {
        super.init()
        SideStoreEmbeddedRuntime.consoleLogProvider = { [weak self] in self?.consoleLog }
    }
}

private enum SideStoreEmbeddedRuntime {
    @MainActor private static var didStart = false
    @MainActor private static var didFinishStartup = false
    @MainActor private static var startupError: Error?
    @MainActor private static var startupCompletions: [((Error?) -> Void)] = []

    static var consoleLogProvider: (() -> ConsoleLog?)?

    @MainActor
    static func startIfNeeded(completion: ((Error?) -> Void)? = nil) {
        if let completion {
            if didFinishStartup {
                completion(startupError)
            } else {
                startupCompletions.append(completion)
            }
        }

        guard !didStart else { return }
        didStart = true

        UserDefaults.registerDefaults()
        SecureValueTransformer.register()
        prepareImageCache()
        consoleLogProvider?()?.startCapturing()

        if UserDefaults.standard.firstLaunch == nil {
            Keychain.shared.reset()
            UserDefaults.standard.firstLaunch = Date()
        }

        UserDefaults.standard.preferredServerID = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.serverID) as? String

        guard !DatabaseManager.shared.isStarted else {
            finishStartup(error: nil)
            return
        }

        DatabaseManager.shared.start { error in
            Task { @MainActor in
                if let error {
                    print("[SideStoreEmbedded] Failed to start DatabaseManager: \(error)")
                } else {
                    print("[SideStoreEmbedded] Started DatabaseManager.")
                }
                finishStartup(error: error)
            }
        }
    }

    @MainActor
    private static func finishStartup(error: Error?) {
        guard !didFinishStartup else { return }

        startupError = error
        didFinishStartup = true

        if error == nil {
            AppManager.shared.update()
            AppManager.shared.updateAllSources { result in
                if case .failure(let error) = result {
                    print("[SideStoreEmbedded] Failed to update sources on startup: \(error.localizedDescription)")
                }
            }
        }

        let completions = startupCompletions
        startupCompletions.removeAll()
        completions.forEach { completion in
            completion(error)
        }
    }

    private static func prepareImageCache() {
        DataLoader.sharedUrlCache.diskCapacity = 0

        let pipeline = ImagePipeline { configuration in
            do {
                let dataCache = try DataCache(name: "io.sidestore.Nuke")
                dataCache.sizeLimit = 512 * 1024 * 1024
                configuration.dataCache = dataCache
            } catch {
                print("[SideStoreEmbedded] Failed to create SideStore image cache: \(error.localizedDescription)")
            }
        }

        ImagePipeline.shared = pipeline
    }
}

private final class KittyStoreRootViewController: UIViewController {
    private var embeddedViewController: UIViewController?
    private var loadingView: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        showLoadingView()

        SideStoreEmbeddedRuntime.startIfNeeded { [weak self] error in
            guard let self else { return }
            if let error {
                self.showUnavailable(message: "KittyStore could not start the embedded store database.\n\n\(error.localizedDescription)")
            } else {
                self.showStoreInterface()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyBranding()
    }

    private func showLoadingView() {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Opening KittyStore..."
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        label.textAlignment = .center

        container.addSubview(activityIndicator)
        container.addSubview(label)
        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            activityIndicator.topAnchor.constraint(equalTo: container.topAnchor),
            activityIndicator.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            label.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        loadingView = container
    }

    private func showStoreInterface() {
        guard embeddedViewController == nil else { return }

        let storyboard = UIStoryboard(name: "Main", bundle: Bundle(for: AppDelegate.self))
        let viewController = storyboard.instantiateViewController(withIdentifier: "tabBarController")
        embed(viewController)
        applyBranding()
    }

    private func showUnavailable(message: String) {
        guard embeddedViewController == nil else { return }
        embed(SideStoreUnavailableViewController(message: message))
    }

    private func embed(_ viewController: UIViewController) {
        loadingView?.removeFromSuperview()
        loadingView = nil

        addChild(viewController)
        viewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(viewController.view)
        NSLayoutConstraint.activate([
            viewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            viewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            viewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            viewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        viewController.didMove(toParent: self)
        embeddedViewController = viewController
    }

    private func applyBranding() {
        guard let embeddedViewController else { return }
        Self.applyBranding(to: embeddedViewController)
        Self.applyBranding(to: view)
    }

    private static func branded(_ text: String?) -> String? {
        text?.replacingOccurrences(of: "SideStore", with: "KittyStore")
    }

    private static func applyBranding(to viewController: UIViewController) {
        viewController.title = branded(viewController.title)
        viewController.navigationItem.title = branded(viewController.navigationItem.title)
        viewController.tabBarItem.title = branded(viewController.tabBarItem.title)

        if let tabBarController = viewController as? UITabBarController {
            tabBarController.tabBar.items?.forEach { item in
                item.title = branded(item.title)
            }
        }

        viewController.children.forEach { child in
            applyBranding(to: child)
        }

        if let presentedViewController = viewController.presentedViewController {
            applyBranding(to: presentedViewController)
        }
    }

    private static func applyBranding(to view: UIView) {
        switch view {
        case let label as UILabel:
            label.text = branded(label.text)
        case let button as UIButton:
            [UIControl.State.normal, .highlighted, .selected, .disabled].forEach { state in
                button.setTitle(branded(button.title(for: state)), for: state)
            }
        case let textField as UITextField:
            textField.text = branded(textField.text)
            textField.placeholder = branded(textField.placeholder)
        case let textView as UITextView:
            textView.text = branded(textView.text)
        default:
            break
        }

        view.subviews.forEach { subview in
            applyBranding(to: subview)
        }
    }
}

private final class SideStoreUnavailableViewController: UIViewController {
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
        label.font = .preferredFont(forTextStyle: .body)
        label.numberOfLines = 0
        label.textAlignment = .center

        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}

public func startEMProxy(bind_addr: String) {
    print("[SideStoreEmbedded] em_proxy is not linked in Litter yet; startEMProxy(\(bind_addr)) ignored.")
}

public func stopEMProxy() {
    print("[SideStoreEmbedded] em_proxy is not linked in Litter yet; stopEMProxy() ignored.")
}
