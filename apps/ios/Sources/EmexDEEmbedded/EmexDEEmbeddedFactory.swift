import UIKit
import UIOnboarding

@MainActor
@objc(EmexDEEmbeddedFactory)
public final class EmexDEEmbeddedFactory: NSObject {
    @objc(makeRootViewController)
    public static func makeRootViewController() -> UIViewController {
        EmexDEEmbeddedRootViewController()
    }
}

private final class EmexDEEmbeddedRootViewController: UIViewController, UITabBarControllerDelegate, UIOnboardingViewControllerDelegate {
    private let tabViewController = UIThemedTabViewController()
    private var bootstrapped = false
    private var presentedOnboarding = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = currentTheme?.backgroundColor ?? .systemBackground
        installUpstreamRoot()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentOnboardingIfNeeded()
    }

    private func installUpstreamRoot() {
        UIViewController.swizzlePresentAndDismissOnce
        UIBarButtonItem.swizzleBarButtonitem

        #if !JAILBREAK_ENV
        guard liveProcessIsAvailable() else {
            installSingleChild(EmexDEMissingLiveProcessViewController())
            return
        }
        #endif

        if !bootstrapped {
            bootstrapped = true
            NXBootstrap.shared().bootstrap()
        }

        let contentViewController = ContentViewController()
        let settingsViewController = SettingsViewController()

        let contentNavigationController = UINavigationController(rootViewController: contentViewController)
        let settingsNavigationController = UINavigationController(rootViewController: settingsViewController)

        contentNavigationController.tabBarItem = UITabBarItem(title: "Projects", image: UIImage(systemName: "square.grid.2x2.fill"), tag: 0)
        settingsNavigationController.tabBarItem = UITabBarItem(title: "Settings", image: UIImage(systemName: "gear"), tag: 1)

        var viewControllers: [UIViewController] = [contentNavigationController, settingsNavigationController]
        if UIDevice.current.userInterfaceIdiom == .phone, #available(iOS 26.0, *) {
            let switcherViewController = UIViewController()
            switcherViewController.tabBarItem = UITabBarItem(tabBarSystemItem: .search, tag: 2)
            switcherViewController.tabBarItem.title = "Switcher"
            switcherViewController.tabBarItem.image = UIImage(systemName: "iphone.app.switcher")
            viewControllers.append(switcherViewController)
        }

        tabViewController.viewControllers = viewControllers
        tabViewController.delegate = self
        installSingleChild(tabViewController)
    }

    private func installSingleChild(_ child: UIViewController) {
        children.forEach { existing in
            existing.willMove(toParent: nil)
            existing.view.removeFromSuperview()
            existing.removeFromParent()
        }

        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            child.view.topAnchor.constraint(equalTo: view.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        child.didMove(toParent: self)
    }

    private func presentOnboardingIfNeeded() {
        guard !presentedOnboarding,
              UserDefaults.standard.object(forKey: "NXOnboardingSentinel") == nil,
              tabViewController.parent != nil else {
            return
        }

        presentedOnboarding = true
        let onboardingConfiguration = UIOnboardingViewConfiguration(
            appIcon: UIOnboardingHelper.setUpIcon(),
            firstTitleLine: UIOnboardingHelper.setUpFirstTitleLine(),
            secondTitleLine: UIOnboardingHelper.setUpSecondTitleLine(),
            features: UIOnboardingHelper.setUpFeatures(),
            textViewConfiguration: UIOnboardingHelper.setUpNotice(),
            buttonConfiguration: UIOnboardingHelper.setUpButton()
        )
        let onboardingController = UIOnboardingViewController(withConfiguration: onboardingConfiguration)
        onboardingController.delegate = self
        onboardingController.loadViewIfNeeded()
        tabViewController.present(onboardingController, animated: false)
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        if tabBarController.selectedViewController === viewController && Builder.builds {
            return false
        }
        if viewController.tabBarItem.tag == 2 {
            if let windowScene = view.window?.windowScene {
                NXWindowServer.shared(with: windowScene).showAppSwitcherExternal()
            }
            return false
        }
        return true
    }

    func didFinishOnboarding(onboardingViewController: UIOnboardingViewController) {
        onboardingViewController.modalTransitionStyle = .crossDissolve
        onboardingViewController.dismiss(animated: true)
        UserDefaults.standard.set(NSNumber(booleanLiteral: true), forKey: "NXOnboardingSentinel")
    }
}

private final class EmexDEMissingLiveProcessViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = currentTheme?.backgroundColor ?? .systemBackground

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.text = "LiveProcess.appex is missing. Rebuild Litter with the emexDE LiveProcess target embedded."

        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
