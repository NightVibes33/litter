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
    private static var runtimeBootstrapped = false

    private let tabViewController = UIThemedTabViewController()
    private var installedRoot = false
    private var presentedOnboarding = false

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do not construct Nyxian's UI until this controller is attached to a
        // UIWindowScene. NXWindowServer is a process-wide singleton and the
        // upstream presentation swizzle assumes it already exists.
        view.backgroundColor = .systemBackground
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installUpstreamRootIfNeeded()
        presentOnboardingIfNeeded()
    }

    private func installUpstreamRootIfNeeded() {
        guard !installedRoot else { return }

        #if !JAILBREAK_ENV
        guard liveProcessIsAvailable() else {
            installedRoot = true
            installSingleChild(EmexDEMissingLiveProcessViewController())
            return
        }
        #endif

        guard let windowScene = view.window?.windowScene else {
            installedRoot = true
            installSingleChild(
                EmexDEStartupErrorViewController(
                    message: "EmexDE could not attach to Alley Cat's active window scene. Close EmexDE and open it again."
                )
            )
            return
        }

        installedRoot = true

        // Match Nyxian's standalone SceneDelegate startup order. In the
        // embedded build there is no Nyxian SceneDelegate, so these steps must
        // be performed by the host before ContentViewController/Settings are
        // created. In particular, presenting a sheet after installing the
        // upstream swizzle dereferences NXWindowServer.shared().
        RevertUI()
        _ = NXWindowServer.shared(with: windowScene)
        UIViewController.swizzlePresentAndDismissOnce
        UIBarButtonItem.swizzleBarButtonitem

        if !Self.runtimeBootstrapped {
            Self.runtimeBootstrapped = true
            NXBootstrap.shared().bootstrap()
        }

        view.backgroundColor = currentTheme?.backgroundColor ?? .systemBackground

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
              installedRoot,
              UserDefaults.standard.object(forKey: "NXOnboardingSentinel") == nil,
              tabViewController.parent != nil else {
            return
        }

        presentedOnboarding = true
        let onboardingController = UIOnboardingViewController(withConfiguration: makeEmbeddedOnboardingConfiguration())
        onboardingController.delegate = self
        onboardingController.backgroundColor = currentTheme?.backgroundColor ?? .systemBackground
        onboardingController.loadViewIfNeeded()
        tabViewController.present(onboardingController, animated: false)
    }

    private func makeEmbeddedOnboardingConfiguration() -> UIOnboardingViewConfiguration {
        let frameworkBundle = Bundle(for: EmexDEEmbeddedFactory.self)
        let appIcon = UIImage(
            named: "IconPreviewDefaultOld",
            in: frameworkBundle,
            compatibleWith: nil
        ) ?? UIImage(systemName: "hammer.circle.fill") ?? UIImage()

        let firstTitleLine = UIOnboardingHelper.setUpFirstTitleLine()
        let secondTitleLine = NSMutableAttributedString(
            string: "EmexDE",
            attributes: [
                .foregroundColor: UIColor { trait in
                    trait.userInterfaceStyle == .dark
                        ? UIColor(red: 0.85, green: 0.74, blue: 0.93, alpha: 1.0)
                        : UIColor(red: 0.62, green: 0.48, blue: 0.78, alpha: 1.0)
                }
            ]
        )

        let lightBackground = (currentTheme?.backgroundColor ?? UIColor.systemBackground)
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let buttonConfiguration = UIOnboardingButtonConfiguration(
            title: "Continue",
            titleColor: lightBackground,
            backgroundColor: UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 0.85, green: 0.74, blue: 0.93, alpha: 1.0)
                    : UIColor(red: 0.62, green: 0.48, blue: 0.78, alpha: 1.0)
            }
        )

        return UIOnboardingViewConfiguration(
            appIcon: appIcon,
            firstTitleLine: firstTitleLine,
            secondTitleLine: secondTitleLine,
            features: UIOnboardingHelper.setUpFeatures(),
            textViewConfiguration: UIOnboardingHelper.setUpNotice(),
            buttonConfiguration: buttonConfiguration
        )
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        if NXBuilder.builds {
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
        label.text = "LiveProcess.appex is missing. Rebuild Litter with the EmexDE LiveProcess target embedded."

        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}

private final class EmexDEStartupErrorViewController: UIViewController {
    private let message: String

    init(message: String) {
        self.message = message
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.text = message

        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
