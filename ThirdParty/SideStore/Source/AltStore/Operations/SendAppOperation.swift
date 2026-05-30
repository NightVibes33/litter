import UIKit
//
//  SendAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/7/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//
import Foundation
import Network
import AltStoreCore
import Minimuxer

@objc(SendAppOperation)
final class SendAppOperation: ResultOperation<()>
{
    let context: InstallAppOperationContext
    
    private let dispatchQueue = DispatchQueue(label: "com.sidestore.SendAppOperation")
    
    init(context: InstallAppOperationContext)
    {
        self.context = context
        
        super.init()
        
        self.progress.totalUnitCount = 1
    }
    
    override func main() {
        super.main()

        if let error = self.context.error {
            return self.finish(.failure(error))
        }

        guard let resignedApp = self.context.resignedApp else {
            return self.finish(.failure(OperationError.invalidParameters("SendAppOperation.main: self.resignedApp is nil")))
        }

        self.context.fillMissingBundleIdentifier(from: resignedApp.bundleIdentifier)
        let bundleIdentifier = self.context.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleIdentifier.isEmpty else {
            return self.finish(.failure(OperationError.invalidParameters("SendAppOperation.main: app bundle identifier is missing")))
        }

        let app = AnyApp(name: resignedApp.name, bundleIdentifier: bundleIdentifier, url: resignedApp.fileURL, storeApp: nil)
        let fileURL = InstalledApp.refreshedIPAURL(for: app)
        print("AFC App `fileURL`: \(fileURL.absoluteString)")

        DispatchQueue.global().async {
            self.processFile(at: fileURL, for: app.bundleIdentifier)
        }
    }

    private func processFile(at fileURL: URL, for bundleIdentifier: String) {
        guard let data = NSData(contentsOf: fileURL) else {
            print("IPA doesn't exist????")
            return self.finish(.failure(OperationError(.appNotFound(name: bundleIdentifier))))
        }

        do {
            let bytes = Data(data)
            try yeetAppAFC(bundleIdentifier, bytes)
            self.progress.completedUnitCount += 1
            self.finish(.success(()))
        } catch {
            self.progress.completedUnitCount += 1
            self.finish(.failure(error))
        }
    }
}
