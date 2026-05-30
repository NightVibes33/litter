import Foundation
import ObjectiveC
import UIKit

enum KittyStoreEmbeddedBridge {
    struct TransportProbe: Sendable {
        var isReady: Bool
        var endpointReachable: Bool
        var detail: String
    }

    struct TransportResponse: Sendable {
        var ok: Bool
        var available: Bool
        var value: String
        var error: String
        var localizedDescription: String
        var isReady: Bool
        var endpointReachable: Bool
        var detail: String

        var failureMessage: String {
            if !localizedDescription.isEmpty { return localizedDescription }
            if !error.isEmpty { return error }
            return "KittyStore minimuxer transport failed."
        }

        init(dictionary: NSDictionary?) {
            let dictionary = dictionary as? [String: Any] ?? [:]
            ok = Self.boolValue(dictionary["ok"])
            available = Self.boolValue(dictionary["available"])
            value = Self.stringValue(dictionary["value"])
            error = Self.stringValue(dictionary["error"])
            localizedDescription = Self.stringValue(dictionary["localizedDescription"])
            isReady = Self.boolValue(dictionary["isReady"])
            endpointReachable = Self.boolValue(dictionary["endpointReachable"])
            detail = Self.stringValue(dictionary["detail"])
        }

        init(error message: String) {
            ok = false
            available = false
            value = ""
            error = message
            localizedDescription = message
            isReady = false
            endpointReachable = false
            detail = message
        }

        func requireSuccess() throws {
            guard ok else { throw TransportCallError.failed(failureMessage) }
        }

        private static func boolValue(_ value: Any?) -> Bool {
            if let bool = value as? Bool { return bool }
            if let number = value as? NSNumber { return number.boolValue }
            return false
        }

        private static func stringValue(_ value: Any?) -> String {
            if let string = value as? String { return string }
            if let number = value as? NSNumber { return number.stringValue }
            return ""
        }
    }

    enum TransportCallError: Error, LocalizedError, CustomStringConvertible, Sendable {
        case failed(String)
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .failed(let message), .unavailable(let message):
                return message
            }
        }

        var description: String { errorDescription ?? "KittyStore minimuxer transport failed." }
    }

    @MainActor
    static func bootstrap() {
        invokeVoid(classNames: embeddedEntryPointClassNames, selectorName: "bootstrap")
    }

    @MainActor
    static func makeRootViewController() -> UIViewController {
        if let viewController = invokeObject(
            classNames: embeddedEntryPointClassNames,
            selectorName: "makeRootViewController"
        ) as? UIViewController {
            return viewController
        }
        return KittyStoreBridgeUnavailableViewController()
    }

    @MainActor
    static func startTransportIfPossible() {
        invokeVoid(classNames: embeddedEntryPointClassNames, selectorName: "startTransportIfPossible")
    }

    @MainActor
    static func applyCurrentTheme(to viewController: UIViewController) {
        invokeVoid(
            classNames: embeddedEntryPointClassNames,
            selectorName: "applyCurrentThemeTo:",
            argument: viewController
        )
    }

    static var isMinimuxerTransportAvailable: Bool {
        let response = callTransport(selectorName: "availability:")
        return response.ok && response.available
    }

    static func probeLocalDevVPN() -> TransportProbe {
        let response = callTransport(selectorName: "probeLocalDevVPN:")
        let detail = response.detail.isEmpty ? response.failureMessage : response.detail
        return TransportProbe(
            isReady: response.ok && response.isReady,
            endpointReachable: response.ok && response.endpointReachable,
            detail: detail
        )
    }

    static func startMinimuxer(pairingFile: String, logPath: String, loggingEnabled: Bool) throws {
        try callTransport(
            selectorName: "startMinimuxer:",
            request: [
                "pairingFile": pairingFile,
                "logPath": logPath,
                "loggingEnabled": loggingEnabled
            ]
        ).requireSuccess()
    }

    static func fetchDeviceUDID() throws -> String? {
        let response = callTransport(selectorName: "fetchDeviceUDID:")
        try response.requireSuccess()
        return response.value.isEmpty ? nil : response.value
    }

    static func installedAppsPlist() throws -> String {
        let response = callTransport(selectorName: "installedAppsPlist:")
        try response.requireSuccess()
        return response.value
    }

    static func installProvisioningProfile(_ profileData: Data) throws {
        try callTransport(
            selectorName: "installProvisioningProfile:",
            request: ["profileData": profileData]
        ).requireSuccess()
    }

    static func stageIPA(bundleIdentifier: String, ipaBytes: Data) throws {
        try callTransport(
            selectorName: "stageIPA:",
            request: [
                "bundleIdentifier": bundleIdentifier,
                "ipaBytes": ipaBytes
            ]
        ).requireSuccess()
    }

    static func installStagedIPA(bundleIdentifier: String) throws {
        try callTransport(
            selectorName: "installStagedIPA:",
            request: ["bundleIdentifier": bundleIdentifier]
        ).requireSuccess()
    }

    static func removeInstalledApp(bundleIdentifier: String) throws {
        try callTransport(
            selectorName: "removeInstalledApp:",
            request: ["bundleIdentifier": bundleIdentifier]
        ).requireSuccess()
    }

    private static let embeddedEntryPointClassNames = [
        "KittyStoreEmbeddedEntryPoint",
        "SideStore.KittyStoreEmbeddedEntryPoint"
    ]

    private static let transportEntryPointClassNames = [
        "KittyStoreMinimuxerTransportEntryPoint",
        "SideStore.KittyStoreMinimuxerTransportEntryPoint"
    ]

    private typealias ObjectNoArgIMP = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
    private typealias ObjectOneArgIMP = @convention(c) (AnyObject, Selector, AnyObject) -> Unmanaged<AnyObject>?
    private typealias VoidNoArgIMP = @convention(c) (AnyObject, Selector) -> Void
    private typealias VoidOneArgIMP = @convention(c) (AnyObject, Selector, AnyObject) -> Void

    private static func callTransport(
        selectorName: String,
        request: [String: Any] = [:]
    ) -> TransportResponse {
        let dictionary = request as NSDictionary
        let result = invokeObject(
            classNames: transportEntryPointClassNames,
            selectorName: selectorName,
            argument: dictionary
        ) as? NSDictionary

        if let result {
            return TransportResponse(dictionary: result)
        }

        return TransportResponse(error: "KittyStore minimuxer transport entry point is unavailable in this IPA.")
    }

    private static func invokeObject(
        classNames: [String],
        selectorName: String,
        argument: AnyObject? = nil
    ) -> Any? {
        guard let resolved = resolveClass(classNames: classNames, selectorName: selectorName) else {
            return nil
        }

        if let argument {
            let function = unsafeBitCast(method_getImplementation(resolved.method), to: ObjectOneArgIMP.self)
            return function(resolved.classObject, resolved.selector, argument)?.takeUnretainedValue()
        } else {
            let function = unsafeBitCast(method_getImplementation(resolved.method), to: ObjectNoArgIMP.self)
            return function(resolved.classObject, resolved.selector)?.takeUnretainedValue()
        }
    }

    private static func invokeVoid(
        classNames: [String],
        selectorName: String,
        argument: AnyObject? = nil
    ) {
        guard let resolved = resolveClass(classNames: classNames, selectorName: selectorName) else {
            return
        }

        if let argument {
            let function = unsafeBitCast(method_getImplementation(resolved.method), to: VoidOneArgIMP.self)
            function(resolved.classObject, resolved.selector, argument)
        } else {
            let function = unsafeBitCast(method_getImplementation(resolved.method), to: VoidNoArgIMP.self)
            function(resolved.classObject, resolved.selector)
        }
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

private final class KittyStoreBridgeUnavailableViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.text = "KittyStore could not load the embedded store framework."
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
