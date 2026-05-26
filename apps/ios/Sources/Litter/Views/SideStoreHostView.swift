import SwiftUI
import UIKit
import SideStore

struct SideStoreHostView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        SideStoreEmbeddedFactory.makeRootViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
