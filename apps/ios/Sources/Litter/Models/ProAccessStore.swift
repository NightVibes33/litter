import Foundation
import Observation
import StoreKit

enum ProFeature: String, Identifiable, Hashable {
    case all
    case terminal
    case fileBrowser
    case appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Alley Cat Pro"
        case .terminal: return "Terminal Access"
        case .fileBrowser: return "File Browser Access"
        case .appearance: return "Chat Appearance"
        }
    }

    var iconName: String {
        switch self {
        case .all: return "pawprint.fill"
        case .terminal: return "terminal.fill"
        case .fileBrowser: return "folder.fill"
        case .appearance: return "paintbrush.fill"
        }
    }

    var lockedMessage: String {
        switch self {
        case .all:
            return "Unlock Terminal, the full file browser, import/export, and advanced local tools."
        case .terminal:
            return "Terminal is part of Alley Cat Pro. Unlock it once and keep access across your devices."
        case .fileBrowser:
            return "The full file browser is part of Alley Cat Pro. Unlock browsing, import/export, and advanced file tools."
        case .appearance:
            return "Chat Appearance is part of Alley Cat Pro. Preview every style, then unlock once to apply custom backgrounds and typing effects."
        }
    }
}

@MainActor
@Observable
final class ProAccessStore {
    enum PurchaseState: Equatable {
        case idle
        case loading
        case purchasing
        case purchased
        case failed(String)
    }

    static let shared = ProAccessStore()
    static let proProductID = "com.nightvibes.alleycat.pro"

    private(set) var product: Product?
    private(set) var hasProAccess = false
    private(set) var purchaseState: PurchaseState = .idle
    private(set) var isLoading = true

    private nonisolated(unsafe) var updatesTask: Task<Void, Never>?

    var displayPrice: String {
        product?.displayPrice ?? "$9.99"
    }

    var productDisplayName: String {
        product?.displayName ?? "Alley Cat Pro"
    }

    private init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refreshEntitlements()
                }
                _ = self
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        guard isLoading || product == nil else {
            await refreshEntitlements()
            return
        }
        purchaseState = .loading
        do {
            let products = try await Product.products(for: [Self.proProductID])
            product = products.first { $0.id == Self.proProductID }
            await refreshEntitlements()
            purchaseState = .idle
        } catch {
            await refreshEntitlements()
            purchaseState = .failed(error.localizedDescription)
        }
        isLoading = false
    }

    func purchasePro() async {
        guard let product else {
            purchaseState = .failed("Alley Cat Pro is not available right now. Check the in-app purchase setup in App Store Connect.")
            return
        }
        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    purchaseState = .failed("Unable to verify purchase.")
                    return
                }
                await transaction.finish()
                await refreshEntitlements()
                purchaseState = hasProAccess ? .purchased : .idle
            case .userCancelled:
                purchaseState = .idle
            case .pending:
                purchaseState = .idle
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    func restorePurchases() async {
        purchaseState = .purchasing
        do {
            try await StoreKit.AppStore.sync()
            await refreshEntitlements()
            purchaseState = hasProAccess ? .purchased : .idle
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    func refreshEntitlements() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == Self.proProductID else { continue }
            guard transaction.revocationDate == nil else { continue }
            unlocked = true
            break
        }
        hasProAccess = unlocked
    }
}
