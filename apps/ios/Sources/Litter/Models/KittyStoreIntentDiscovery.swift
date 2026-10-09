#if !LITTER_APP_STORE_SAFE && canImport(SideStore) && !targetEnvironment(macCatalyst)
import AppIntents
import SideStore

@available(iOS 17, *)
struct AlleyCatSideloadIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [KittyStoreAppIntentsPackage.self]
    }
}
#endif
