//
//  LocalDevVPNApp.swift
//  LocalDevVPN
//
//  Created by Stossy11 on 28/03/2025.
//

import SwiftUI

@main
struct LocalDevVPNApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    handleURL(url)
                }
        }
    }
    
    private func handleURL(_ url: URL) {
        guard url.scheme == "localdevvpn" else { return }
        
        let tunnelManager = TunnelManager.shared
        
        switch url.host {
        case "enable":
            tunnelManager.startVPN()
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let schemeParam = components.queryItems?.first(where: { $0.name == "scheme" })?.value {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let callbackURL = URL(string: "\(schemeParam)://")!
                    UIApplication.shared.open(callbackURL)
                }
            }
        case "disable":
            tunnelManager.stopVPN()
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let schemeParam = components.queryItems?.first(where: { $0.name == "scheme" })?.value {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let callbackURL = URL(string: "\(schemeParam)://")!
                    UIApplication.shared.open(callbackURL)
                }
            }
        default:
            break
        }
    }
}
