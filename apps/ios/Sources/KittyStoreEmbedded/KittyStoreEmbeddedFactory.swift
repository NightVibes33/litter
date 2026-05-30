import Foundation
import Nuke
import UIKit
import AltStoreCore
import Minimuxer

public enum KittyStoreEmbeddedFactory {
    public struct MinimuxerProbe: Sendable {
        public let isReady: Bool
        public let endpointReachable: Bool
        public let detail: String
    }

    public static var isMinimuxerTransportAvailable: Bool { true }

    public static func probeLocalDevVPN() -> MinimuxerProbe {
        #if targetEnvironment(simulator)
        return MinimuxerProbe(
            isReady: true,
            endpointReachable: true,
            detail: "Simulator build treats the SideStore minimuxer transport as ready."
        )
        #else
        bindTunnelConfig()
        retargetUsbmuxdAddr()
        let ready = isMinimuxerReady
        let endpointReachable = Minimuxer.testDeviceConnection(ifaddr: "10.7.0.1")
        let detail: String
        if ready {
            detail = "SideStore minimuxer is ready through LocalDevVPN."
        } else if endpointReachable {
            detail = "LocalDevVPN 10.7.0.1 is reachable. Pairing will be checked during install or refresh."
        } else {
            detail = "LocalDevVPN 10.7.0.1 is not reachable yet."
        }
        return MinimuxerProbe(isReady: ready, endpointReachable: endpointReachable, detail: detail)
        #endif
    }

    public static func startMinimuxer(pairingFile: String, logPath: String, loggingEnabled: Bool) throws {
        #if targetEnvironment(simulator)
        return
        #else
        retargetUsbmuxdAddr()
        try minimuxerStartWithLogger(pairingFile, logPath, loggingEnabled)
        startAutoMounter(logPath)
        #endif
    }

    public static func fetchDeviceUDID() -> String? {
        fetchUDID()
    }

    public static func installProvisioningProfile(_ profileData: Data) throws {
        try installProvisioningProfiles(profileData)
    }

    public static func stageIPA(bundleIdentifier: String, ipaBytes: Data) throws {
        try yeetAppAFC(bundleIdentifier, ipaBytes)
    }

    public static func installStagedIPA(bundleIdentifier: String) throws {
        try installIPA(bundleIdentifier)
    }

    public static func removeInstalledApp(bundleIdentifier: String) throws {
        try removeApp(bundleIdentifier)
    }

    public static func installedAppsPlist() throws -> String {
        #if targetEnvironment(simulator)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><array/></plist>
        """
        #else
        return try Minimuxer.listInstalledAppsPlist()
        #endif
    }

    @MainActor
    public static func makeRootViewController() -> UIViewController {
        KittyStoreRootViewController()
    }

    @MainActor
    public static func bootstrap() {
        KittyStoreEmbeddedRuntime.prepareForLaunch()
    }

    @MainActor
    public static func startTransportIfPossible() {
        KittyStoreEmbeddedRuntime.startTransportIfPossible()
    }

    @MainActor
    public static func applyCurrentTheme(to viewController: UIViewController) {
        KittyStoreRootViewController.applyCurrentTheme(to: viewController)
    }
}

@MainActor
@objc(KittyStoreEmbeddedEntryPoint)
public final class KittyStoreEmbeddedEntryPoint: NSObject {
    @objc public static func makeRootViewController() -> UIViewController {
        KittyStoreEmbeddedFactory.makeRootViewController()
    }

    @objc public static func startTransportIfPossible() {
        KittyStoreEmbeddedFactory.startTransportIfPossible()
    }

    @objc public static func applyCurrentTheme(to viewController: UIViewController) {
        KittyStoreEmbeddedFactory.applyCurrentTheme(to: viewController)
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
        KittyStoreEmbeddedRuntime.consoleLogProvider = { [weak self] in self?.consoleLog }
    }
}

private enum KittyStoreEmbeddedRuntime {
    @MainActor private static var didPrepare = false
    @MainActor private static var didStart = false
    @MainActor private static var didFinishStartup = false
    @MainActor private static var didStartMinimuxer = false
    @MainActor private static var startupError: Error?
    @MainActor private static var startupCompletions: [((Error?) -> Void)] = []

    static var consoleLogProvider: (() -> ConsoleLog?)?

    @MainActor
    static func resourcePreflightError() -> Error? {
        let missing = requiredResourceFailures()
        guard !missing.isEmpty else { return nil }
        return KittyStoreResourcePreflightError(missingResources: missing)
    }

    @MainActor
    private static func requiredResourceFailures() -> [String] {
        let storeBundle = Bundle(for: AppDelegate.self)
        let coreBundle = Bundle(for: DatabaseManager.self)
        var missing: [String] = []

        func require(_ label: String, _ name: String, _ ext: String?, in bundle: Bundle) {
            if bundle.url(forResource: name, withExtension: ext) == nil {
                let resource = ext.map { "\(name).\($0)" } ?? name
                missing.append("\(label): missing \(resource) in \(bundle.bundlePath)")
            }
        }

        require("KittyStore main storyboard", "Main", "storyboardc", in: storeBundle)
        require("KittyStore authentication storyboard", "Authentication", "storyboardc", in: storeBundle)
        require("KittyStore settings storyboard", "Settings", "storyboardc", in: storeBundle)
        require("KittyStore sources storyboard", "Sources", "storyboardc", in: storeBundle)
        require("KittyStore app banner nib", "AppBannerView", "nib", in: storeBundle)
        require("KittyStore update cell nib", "UpdateCollectionViewCell", "nib", in: storeBundle)
        require("KittyStore installed apps header nib", "InstalledAppsCollectionHeaderView", "nib", in: storeBundle)
        require("KittyStore news cell nib", "NewsCollectionViewCell", "nib", in: storeBundle)
        require("KittyStore settings header/footer nib", "SettingsHeaderFooterView", "nib", in: storeBundle)
        require("KittyStore about header nib", "AboutPatreonHeaderView", "nib", in: storeBundle)
        require("KittyStore source header nib", "SourceHeaderView", "nib", in: storeBundle)
        require("KittyStore asset catalog", "Assets", "car", in: storeBundle)
        require("KittyStore alternate icons manifest", "AltIcons", "plist", in: storeBundle)
        require("KittyStore release entitlements", "ReleaseEntitlements", "plist", in: storeBundle)
        require("KittyStore silent audio", "Silence", "m4a", in: storeBundle)
        require("AltStoreCore Core Data model", "AltStore", "momd", in: coreBundle)
        require("AltStoreCore permissions manifest", "Permissions", "plist", in: coreBundle)

        if UIColor(named: "Background", in: storeBundle, compatibleWith: nil) == nil {
            missing.append("KittyStore color asset: missing Background in \(storeBundle.bundlePath)")
        }

        if UIColor(named: "SettingsHighlighted", in: storeBundle, compatibleWith: nil) == nil {
            missing.append("KittyStore color asset: missing SettingsHighlighted in \(storeBundle.bundlePath)")
        }

        return missing
    }

    @MainActor
    static func prepareForLaunch() {
        guard !didPrepare else { return }
        didPrepare = true

        UserDefaults.registerDefaults()
        UserDefaults.standard.enableEMPforWireguard = false
        SecureValueTransformer.register()
        prepareImageCache()
        consoleLogProvider?()?.startCapturing()

        if UserDefaults.standard.firstLaunch == nil {
            Keychain.shared.reset()
            UserDefaults.standard.firstLaunch = Date()
        }

        UserDefaults.standard.preferredServerID = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.serverID) as? String
    }

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
        prepareForLaunch()

        if let error = resourcePreflightError() {
            print("[KittyStoreEmbedded] Resource preflight failed: \(error.localizedDescription)")
            finishStartup(error: error)
            return
        }

        guard !DatabaseManager.shared.isStarted else {
            finishStartup(error: nil)
            return
        }

        DatabaseManager.shared.start { error in
            Task { @MainActor in
                if let error {
                    print("[KittyStoreEmbedded] Failed to start DatabaseManager: \(error)")
                } else {
                    print("[KittyStoreEmbedded] Started DatabaseManager.")
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
                    print("[KittyStoreEmbedded] Failed to update sources on startup: \(error.localizedDescription)")
                }
            }
        }

        let completions = startupCompletions
        startupCompletions.removeAll()
        completions.forEach { completion in
            completion(error)
        }
    }

    @MainActor
    static func startTransportIfPossible() {
        startMinimuxerIfPossible()
    }

    @MainActor
    private static func startMinimuxerIfPossible() {
        #if targetEnvironment(simulator)
        return
        #else
        guard !didStartMinimuxer else { return }

        let pairingURL = FileManager.default.documentsDirectory.appendingPathComponent(pairingFileName)
        guard FileManager.default.fileExists(atPath: pairingURL.path),
              let pairingFile = try? String(contentsOf: pairingURL),
              !pairingFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[KittyStoreEmbedded] Pairing file not imported yet; minimuxer startup deferred.")
            return
        }

        didStartMinimuxer = true
        retargetUsbmuxdAddr()
        let documentsDirectory = FileManager.default.documentsDirectory.absoluteString
        do {
            let loggingEnabled = UserDefaults.standard.isMinimuxerConsoleLoggingEnabled
            try minimuxerStartWithLogger(pairingFile, documentsDirectory, loggingEnabled)
            startAutoMounter(documentsDirectory)
            print("[KittyStoreEmbedded] Started minimuxer for embedded KittyStore.")
        } catch {
            didStartMinimuxer = false
            print("[KittyStoreEmbedded] Failed to start minimuxer: \(error.localizedDescription)")
        }
        #endif
    }

    private static func prepareImageCache() {
        DataLoader.sharedUrlCache.diskCapacity = 0

        let pipeline = ImagePipeline { configuration in
            do {
                let dataCache = try DataCache(name: "com.sigkitten.litter.kittystore.Nuke")
                dataCache.sizeLimit = 512 * 1024 * 1024
                configuration.dataCache = dataCache
            } catch {
                print("[KittyStoreEmbedded] Failed to create KittyStore image cache: \(error.localizedDescription)")
            }
        }

        ImagePipeline.shared = pipeline
    }
}


private struct KittyStoreResourcePreflightError: LocalizedError {
    let missingResources: [String]

    var errorDescription: String? {
        "KittyStore is missing required embedded resources.\n" + missingResources.joined(separator: "\n")
    }
}

private final class KittyStoreRootViewController: UIViewController {
    private static let litterThemeDidChange = Notification.Name("com.litter.themeDidChange")

    private var embeddedViewController: UIViewController?
    private var splashView: KittyStoreSplashView?
    private var didRequestStoreInterface = false
    private var themeObserver: NSObjectProtocol?

    deinit {
        if let themeObserver {
            NotificationCenter.default.removeObserver(themeObserver)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .altBackground
        view.clipsToBounds = true
        view.insetsLayoutMarginsFromSafeArea = false
        view.layoutMargins = .zero
        view.directionalLayoutMargins = .zero
        view.preservesSuperviewLayoutMargins = false
        viewRespectsSystemMinimumLayoutMargins = false
        edgesForExtendedLayout = [.all]
        extendedLayoutIncludesOpaqueBars = true
        showSplashView()
        observeThemeChanges()

        KittyStoreEmbeddedRuntime.startIfNeeded { [weak self] error in
            guard let self else { return }
            if let error {
                self.showUnavailable(message: "KittyStore could not start the embedded store database.\n\n\(error.localizedDescription)")
            } else {
                self.showStoreInterfaceAfterSplash()
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyBranding()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        embeddedViewController?.view.frame = view.bounds
        applyBranding()
    }

    private func showSplashView() {
        let splashView = KittyStoreSplashView()
        splashView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splashView)
        NSLayoutConstraint.activate([
            splashView.topAnchor.constraint(equalTo: view.topAnchor),
            splashView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            splashView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splashView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        self.splashView = splashView
    }

    private func showStoreInterfaceAfterSplash() {
        guard !didRequestStoreInterface else { return }
        didRequestStoreInterface = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.showStoreInterface()
        }
    }

    private func showStoreInterface() {
        guard embeddedViewController == nil else { return }

        if let error = KittyStoreEmbeddedRuntime.resourcePreflightError() {
            showUnavailable(message: error.localizedDescription)
            return
        }

        let bundle = Bundle(for: AppDelegate.self)
        guard bundle.url(forResource: "Main", withExtension: "storyboardc") != nil else {
            showUnavailable(message: "KittyStore could not find Main.storyboardc in \(bundle.bundlePath).")
            return
        }

        LaunchViewController.isEmbeddedHostMode = true
        let storyboard = UIStoryboard(name: "Main", bundle: bundle)
        let viewController = storyboard.instantiateViewController(withIdentifier: "tabBarController")

        if let tabBarController = viewController as? UITabBarController {
            if let viewControllers = tabBarController.viewControllers,
               viewControllers.indices.contains(2) {
                tabBarController.selectedIndex = 2
            }
            configureTabBar(tabBarController)
        }

        embed(viewController)
        applyBranding()
    }

    private func observeThemeChanges() {
        guard themeObserver == nil else { return }
        themeObserver = NotificationCenter.default.addObserver(
            forName: Self.litterThemeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyBranding()
        }
    }

    private func showUnavailable(message: String) {
        guard embeddedViewController == nil else { return }
        embed(KittyStoreUnavailableViewController(message: message))
    }

    private func embed(_ viewController: UIViewController) {
        addChild(viewController)
        viewController.edgesForExtendedLayout = [.all]
        viewController.extendedLayoutIncludesOpaqueBars = true
        viewController.additionalSafeAreaInsets = .zero
        viewController.viewRespectsSystemMinimumLayoutMargins = false
        viewController.view.translatesAutoresizingMaskIntoConstraints = false
        viewController.view.insetsLayoutMarginsFromSafeArea = false
        viewController.view.layoutMargins = .zero
        viewController.view.directionalLayoutMargins = .zero
        viewController.view.preservesSuperviewLayoutMargins = false
        viewController.view.clipsToBounds = true
        viewController.view.backgroundColor = .altBackground
        Self.applyCurrentTheme(to: viewController)
        viewController.view.alpha = 0
        view.addSubview(viewController.view)
        NSLayoutConstraint.activate([
            viewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            viewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            viewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            viewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        viewController.didMove(toParent: self)
        embeddedViewController = viewController

        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
            viewController.view.alpha = 1
            self.splashView?.alpha = 0
        } completion: { _ in
            self.splashView?.removeFromSuperview()
            self.splashView = nil
        }
    }

    private func applyBranding() {
        Self.applyCurrentTheme(to: self)
        Self.applyCurrentTheme(to: view)

        guard let embeddedViewController else { return }
        Self.applyCurrentTheme(to: embeddedViewController)
        Self.applyBranding(to: embeddedViewController)
        Self.applyBranding(to: view)
    }

    private static func branded(_ text: String?) -> String? {
        KittyStoreBranding.text(text)
    }

    private static func branded(_ attributedText: NSAttributedString?) -> NSAttributedString? {
        KittyStoreBranding.attributedText(attributedText)
    }

    private func configureTabBar(_ tabBarController: UITabBarController) {
        Self.applyTabBarTheme(to: tabBarController)
    }

    private static func brand(_ item: UIBarItem?) {
        item?.title = branded(item?.title)
        item?.accessibilityLabel = branded(item?.accessibilityLabel)
    }

    static func applyCurrentTheme(to viewController: UIViewController) {
        viewController.view.backgroundColor = .altBackground
        viewController.view.tintColor = .altPrimary
        applyCurrentTheme(to: viewController.view)

        if let tabBarController = viewController as? UITabBarController {
            applyTabBarTheme(to: tabBarController)
            tabBarController.viewControllers?.forEach { child in
                applyCurrentTheme(to: child)
            }
        }

        if let navigationController = viewController as? UINavigationController {
            applyNavigationTheme(to: navigationController)
            navigationController.viewControllers.forEach { child in
                applyCurrentTheme(to: child)
            }
        }

        if let splitViewController = viewController as? UISplitViewController {
            splitViewController.viewControllers.forEach { child in
                applyCurrentTheme(to: child)
            }
        }

        viewController.children.forEach { child in
            applyCurrentTheme(to: child)
        }

        if let presentedViewController = viewController.presentedViewController {
            applyCurrentTheme(to: presentedViewController)
        }
    }

    static func applyCurrentTheme(to view: UIView) {
        switch view {
        case let collectionView as UICollectionView:
            collectionView.backgroundColor = .altBackground
        case let tableView as UITableView:
            tableView.backgroundColor = .altSettingsBackground
        case let navigationBar as UINavigationBar:
            navigationBar.tintColor = .altPrimary
        case let tabBar as UITabBar:
            tabBar.tintColor = .altPrimary
            tabBar.backgroundColor = .altBackground
        default:
            break
        }

        view.subviews.forEach { subview in
            applyCurrentTheme(to: subview)
        }
    }

    private static func applyTabBarTheme(to tabBarController: UITabBarController) {
        tabBarController.view.backgroundColor = .altBackground
        tabBarController.view.tintColor = .altPrimary
        tabBarController.tabBar.tintColor = .altPrimary
        tabBarController.tabBar.backgroundColor = .altBackground
        tabBarController.tabBar.isTranslucent = false

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = .altBackground
        appearance.stackedLayoutAppearance.selected.iconColor = .altPrimary
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.altPrimary]
        appearance.inlineLayoutAppearance.selected.iconColor = .altPrimary
        appearance.inlineLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.altPrimary]
        appearance.compactInlineLayoutAppearance.selected.iconColor = .altPrimary
        appearance.compactInlineLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.altPrimary]

        tabBarController.tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBarController.tabBar.scrollEdgeAppearance = appearance
        }
    }

    private static func applyNavigationTheme(to navigationController: UINavigationController) {
        navigationController.view.backgroundColor = .altBackground
        navigationController.view.tintColor = .altPrimary
        navigationController.navigationBar.tintColor = .altPrimary

        let standardAppearance = navigationController.navigationBar.standardAppearance
        standardAppearance.backgroundColor = .altBackground
        navigationController.navigationBar.standardAppearance = standardAppearance

        if let compactAppearance = navigationController.navigationBar.compactAppearance {
            compactAppearance.backgroundColor = .altBackground
            navigationController.navigationBar.compactAppearance = compactAppearance
        }

        if let scrollEdgeAppearance = navigationController.navigationBar.scrollEdgeAppearance {
            scrollEdgeAppearance.backgroundColor = .altBackground
            navigationController.navigationBar.scrollEdgeAppearance = scrollEdgeAppearance
        }
    }

    private static func applyBranding(to viewController: UIViewController) {
        viewController.title = branded(viewController.title)
        viewController.navigationItem.title = branded(viewController.navigationItem.title)
        viewController.navigationItem.prompt = branded(viewController.navigationItem.prompt)
        viewController.navigationItem.backButtonTitle = branded(viewController.navigationItem.backButtonTitle)
        viewController.tabBarItem.title = branded(viewController.tabBarItem.title)
        viewController.toolbarItems?.forEach { brand($0) }
        viewController.navigationItem.leftBarButtonItems?.forEach { brand($0) }
        viewController.navigationItem.rightBarButtonItems?.forEach { brand($0) }
        brand(viewController.navigationItem.backBarButtonItem)
        brand(viewController.navigationItem.leftBarButtonItem)
        brand(viewController.navigationItem.rightBarButtonItem)

        if let alert = viewController as? UIAlertController {
            alert.title = branded(alert.title)
            alert.message = branded(alert.message)
        }

        if let tabBarController = viewController as? UITabBarController {
            tabBarController.tabBar.items?.forEach { item in
                brand(item)
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
            label.attributedText = branded(label.attributedText)
        case let button as UIButton:
            [UIControl.State.normal, .highlighted, .selected, .disabled].forEach { state in
                button.setTitle(branded(button.title(for: state)), for: state)
                button.setAttributedTitle(branded(button.attributedTitle(for: state)), for: state)
            }
            if var configuration = button.configuration {
                configuration.title = branded(configuration.title)
                configuration.subtitle = branded(configuration.subtitle)
                button.configuration = configuration
            }
        case let textField as UITextField:
            textField.text = branded(textField.text)
            textField.placeholder = branded(textField.placeholder)
            textField.attributedPlaceholder = branded(textField.attributedPlaceholder)
        case let textView as UITextView:
            textView.text = branded(textView.text)
            textView.attributedText = branded(textView.attributedText)
        case let searchBar as UISearchBar:
            searchBar.text = branded(searchBar.text)
            searchBar.placeholder = branded(searchBar.placeholder)
            searchBar.prompt = branded(searchBar.prompt)
        case let segmentedControl as UISegmentedControl:
            for index in 0..<segmentedControl.numberOfSegments {
                segmentedControl.setTitle(branded(segmentedControl.titleForSegment(at: index)), forSegmentAt: index)
            }
        case let cell as UITableViewCell:
            cell.textLabel?.text = branded(cell.textLabel?.text)
            cell.detailTextLabel?.text = branded(cell.detailTextLabel?.text)
        default:
            break
        }

        view.subviews.forEach { subview in
            applyBranding(to: subview)
        }
    }
}

private final class KittyStoreSplashView: UIView {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .altBackground
        buildView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildView() {
        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.backgroundColor = .secondarySystemBackground
        iconContainer.layer.cornerRadius = 28
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.layer.shadowColor = UIColor.black.cgColor
        iconContainer.layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.35 : 0.14
        iconContainer.layer.shadowOffset = CGSize(width: 0, height: 8)
        iconContainer.layer.shadowRadius = 18

        iconView.image = Self.appIconImage() ?? UIImage(systemName: "storefront.fill")
        iconView.contentMode = .scaleAspectFill
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.layer.cornerRadius = 24
        iconView.layer.cornerCurve = .continuous
        iconView.clipsToBounds = true
        iconContainer.addSubview(iconView)

        titleLabel.text = "KittyStore"
        titleLabel.font = .systemFont(ofSize: 30, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true

        subtitleLabel.text = "Loading store"
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.adjustsFontForContentSizeCategory = true

        activityIndicator.startAnimating()

        let stackView = UIStackView(arrangedSubviews: [iconContainer, titleLabel, subtitleLabel, activityIndicator])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 10
        stackView.setCustomSpacing(16, after: iconContainer)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),

            iconContainer.widthAnchor.constraint(equalToConstant: 116),
            iconContainer.heightAnchor.constraint(equalToConstant: 116),
            iconView.topAnchor.constraint(equalTo: iconContainer.topAnchor),
            iconView.bottomAnchor.constraint(equalTo: iconContainer.bottomAnchor),
            iconView.leadingAnchor.constraint(equalTo: iconContainer.leadingAnchor),
            iconView.trailingAnchor.constraint(equalTo: iconContainer.trailingAnchor)
        ])
    }

    private static func appIconImage() -> UIImage? {
        let primaryIcon = (Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any]
        let iconFiles = primaryIcon?["CFBundleIconFiles"] as? [String]
        let names = Array((iconFiles ?? []).reversed()) + ["AppIcon60x60", "AppIcon", "Icon-1024", "brand_logo"]

        for name in names {
            if let image = UIImage(named: name) {
                return image
            }
            if let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let image = UIImage(contentsOfFile: url.path) {
                return image
            }
        }

        return nil
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
        view.backgroundColor = .altBackground

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
    print("[KittyStoreEmbedded] em_proxy is not linked in Litter yet; startEMProxy(\(bind_addr)) ignored.")
}

public func stopEMProxy() {
    print("[KittyStoreEmbedded] em_proxy is not linked in Litter yet; stopEMProxy() ignored.")
}
