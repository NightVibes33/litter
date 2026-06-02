import ObjectiveC
import UIKit

enum EmexDEEmbeddedBridge {
    @MainActor
    static func makeRootViewController() -> UIViewController {
        if let viewController = invokeObject(
            classNames: embeddedFactoryClassNames,
            selectorName: "makeRootViewController"
        ) as? UIViewController {
            return viewController
        }
        return EmexDEBridgeUnavailableViewController()
    }

    private static let embeddedFactoryClassNames = [
        "EmexDEEmbeddedFactory",
        "emexDE.EmexDEEmbeddedFactory"
    ]

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
