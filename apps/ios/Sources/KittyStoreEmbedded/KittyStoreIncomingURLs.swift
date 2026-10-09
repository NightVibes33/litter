import Foundation
import UIKit

/// SideStore's SceneDelegate callbacks, delivered after the embedded storyboard loads.
/// All queued UI payloads remain on the main actor, including backup Result values.
@MainActor
enum KittyStoreIncomingURLs {
    private enum Action {
        case notification(Notification.Name, [AnyHashable: Any])
        case pairing(String)
    }
    private static var pending: [Action] = []
    private static weak var controller: UIViewController?

    static func receive(_ url: URL) -> Bool {
        let action: Action
        if url.isFileURL {
            guard url.pathExtension.lowercased() == "ipa" else { return false }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let copy = directory.appendingPathComponent(url.lastPathComponent)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: url, to: copy)
            } catch {
                try? FileManager.default.removeItem(at: directory)
                // Do not log incoming URLs, which may contain credentials.
                print("KittyStore: IPA import could not be staged.")
                return false
            }
            action = .notification(AppDelegate.importAppDeepLinkNotification, [AppDelegate.importAppDeepLinkURLKey: copy])
        } else {
            guard url.scheme?.lowercased() == "kittystore",
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let host = components.host?.lowercased() else { return false }
            let query = components.queryItems?.reduce(into: [String: String]()) { $0[$1.name.lowercased()] = $1.value } ?? [:]
            switch host {
            case "install", "source":
                guard let value = query["url"], let target = URL(string: value),
                      ["https", "http"].contains(target.scheme?.lowercased() ?? "") else { return false }
                action = host == "install"
                    ? .notification(AppDelegate.importAppDeepLinkNotification, [AppDelegate.importAppDeepLinkURLKey: target])
                    : .notification(AppDelegate.addSourceDeepLinkNotification, [AppDelegate.addSourceDeepLinkURLKey: target])
            case "appbackupresponse":
                let result: Result<Void, Error>
                switch url.path.lowercased() {
                case "/success": result = .success(())
                case "/failure":
                    guard let domain = query["errordomain"], let codeText = query["errorcode"],
                          let code = Int(codeText), let message = query["errordescription"] else { return false }
                    result = .failure(NSError(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey: message]))
                default: return false
                }
                action = .notification(AppDelegate.appBackupDidFinish, [AppDelegate.appBackupResultKey: result])
            case "certificate":
                guard let template = query["callback_template"]?.removingPercentEncoding,
                      template.contains("$(BASE64_CERT)") else { return false }
                action = .notification(AppDelegate.exportCertificateNotification, [AppDelegate.exportCertificateCallbackTemplateKey: template])
            case "pairing":
                guard let scheme = query["urlname"]?.removingPercentEncoding,
                      let callback = URL(string: "\(scheme)://pairingFile"), callback.scheme == scheme else { return false }
                action = .pairing(scheme)
            default: return false
            }
        }
        pending.append(action)
        if controller?.viewIfLoaded?.window != nil { flush() }
        // Host opens Settings/KittyStore before dispatching to upstream observers.
        return true
    }

    static func attach(_ viewController: UIViewController) {
        controller = viewController
        if let tabs = viewController as? UITabBarController {
            for tab in tabs.viewControllers ?? [] {
                tab.loadViewIfNeeded()
                (tab as? UINavigationController)?.viewControllers.first?.loadViewIfNeeded()
            }
        }
        flush()
    }

    private static func flush() {
        let actions = pending
        pending.removeAll()
        DispatchQueue.main.async {
            for action in actions { deliver(action) }
        }
    }

    private static func deliver(_ action: Action) {
        guard let controller else { pending.append(action); return }
        switch action {
        case .notification(let name, let info):
            NotificationCenter.default.post(name: name, object: nil, userInfo: info)
        case .pairing(let scheme):
            // Unlike upstream's automatic export, require consent before sending a pairing credential.
            let alert = UIAlertController(title: "Export Pairing File?", message: "Send your device pairing file to \(scheme)? Only continue if you trust that app.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Export", style: .default) { _ in
                let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("ALTPairingFile.mobiledevicepairing")
                guard let data = try? Data(contentsOf: file) else {
                    let error = UIAlertController(title: "Pairing File Unavailable", message: "Import a pairing file in KittyStore Settings first.", preferredStyle: .alert)
                    error.addAction(UIAlertAction(title: "OK", style: .default))
                    controller.present(error, animated: true)
                    return
                }
                var callback = URLComponents()
                callback.scheme = scheme
                callback.host = "pairingFile"
                callback.queryItems = [URLQueryItem(name: "data", value: data.base64EncodedString())]
                callback.percentEncodedQuery = callback.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
                if let url = callback.url { UIApplication.shared.open(url) }
            })
            controller.present(alert, animated: true)
        }
    }
}
