import Foundation
import Nuke
import UIKit
import AltStoreCore

public enum SideStoreEmbeddedFactory {
    @MainActor
    public static func makeRootViewController() -> UIViewController {
        SideStoreEmbeddedRuntime.startIfNeeded()

        let storyboard = UIStoryboard(name: "Main", bundle: Bundle(for: AppDelegate.self))
        guard let viewController = storyboard.instantiateInitialViewController() else {
            return SideStoreUnavailableViewController(message: "SideStore Main.storyboard did not contain an initial view controller.")
        }

        return viewController
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
    static var consoleLogProvider: (() -> ConsoleLog?)?

    @MainActor
    static func startIfNeeded() {
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

        DatabaseManager.shared.start { error in
            if let error {
                print("[SideStoreEmbedded] Failed to start DatabaseManager: \(error)")
            } else {
                print("[SideStoreEmbedded] Started DatabaseManager.")
            }
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
