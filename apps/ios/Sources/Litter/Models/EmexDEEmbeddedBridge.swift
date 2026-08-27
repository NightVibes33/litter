import ObjectiveC
import UIKit

enum EmexDEEmbeddedBridge {
    @MainActor
    static func makeRootViewController() -> UIViewController {
        loadEmbeddedFrameworksIfNeeded()
        if let viewController = invokeObject(
            classNames: embeddedFactoryClassNames,
            selectorName: "makeRootViewController"
        ) as? UIViewController {
            return viewController
        }
        return EmexDEBridgeUnavailableViewController()
    }
    #if !LITTER_APP_STORE_SAFE
    @MainActor
    static func runCommandJSON(_ requestJSON: String) -> String? {
        guard AppDistributionCapabilities.includesEmexDE else { return nil }
        loadEmbeddedFrameworksIfNeeded()
        let classes = ["NyxianCommandBridge", "emexDE.NyxianCommandBridge"]
        guard let resolved = resolveClass(classNames: classes, selectorName: "runJSON:") else { return nil }
        let function = unsafeBitCast(method_getImplementation(resolved.method), to: ObjectStringIMP.self)
        return function(resolved.classObject, resolved.selector, requestJSON as NSString)?.takeUnretainedValue() as? String
    }
    #endif

    private static let embeddedFactoryClassNames = [
        "EmexDEEmbeddedFactory",
        "emexDE.EmexDEEmbeddedFactory"
    ]

    private typealias ObjectStringIMP = @convention(c) (AnyObject, Selector, NSString) -> Unmanaged<AnyObject>?
    private static let embeddedFrameworkNames = [
        "CoreCompiler",
        "MobileDevelopmentKit",
        "emexDE"
    ]

    @MainActor
    private static var didAttemptFrameworkLoad = false

    @MainActor
    private static func loadEmbeddedFrameworksIfNeeded() {
        guard !didAttemptFrameworkLoad else { return }
        didAttemptFrameworkLoad = true

        guard let frameworksURL = Bundle.main.privateFrameworksURL else { return }
        for name in embeddedFrameworkNames {
            let frameworkURL = frameworksURL.appendingPathComponent("\(name).framework", isDirectory: true)
            guard let bundle = Bundle(url: frameworkURL), !bundle.isLoaded else { continue }
            _ = bundle.load()
        }
    }

    private typealias ObjectNoArgIMP = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?

    private static func invokeObject(
        classNames: [String],
        selectorName: String
    ) -> Any? {
        guard let resolved = resolveClass(classNames: classNames, selectorName: selectorName) else {
            return nil
        }
        let function = unsafeBitCast(method_getImplementation(resolved.method), to: ObjectNoArgIMP.self)
        return function(resolved.classObject, resolved.selector)?.takeUnretainedValue()
    }

    private static func resolveClass(
        classNames: [String],
        selectorName: String
    ) -> (classObject: AnyObject, selector: Selector, method: Method)? {
        let selector = NSSelectorFromString(selectorName)
        for className in classNames {
            guard let candidate = NSClassFromString(className),
                  let method = class_getClassMethod(candidate, selector) else {
                continue
            }
            return (candidate as AnyObject, selector, method)
        }
        return nil
    }
}

private final class EmexDEBridgeUnavailableViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.text = "emexDE could not load the embedded development framework."
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
