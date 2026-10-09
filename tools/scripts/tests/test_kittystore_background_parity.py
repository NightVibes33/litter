from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]

class KittyStoreBackgroundParityTests(unittest.TestCase):
    def test_refresh_methods_are_retained_from_standalone_delegate(self):
        upstream = (ROOT / 'ThirdParty/SideStore/Source/AltStore/AppDelegate.swift').read_text()
        embedded = (ROOT / 'apps/ios/Sources/KittyStoreEmbedded/KittyStoreBackgroundRefresh.swift').read_text()
        marker = '    func application(_ application: UIApplication, performFetchWithCompletionHandler'
        end = '\nprivate extension AppDelegate\n{\n    func fetchSources'
        retained = upstream[upstream.index(marker):upstream.index(end)]
        self.assertIn(retained, embedded)
        fetch = upstream[upstream.index(end):].replace('private extension AppDelegate', 'private extension KittyStoreBackgroundRefresh', 1)
        fetch = fetch.replace('''                DispatchQueue.main.async {
                    UIApplication.shared.applicationIconBadgeNumber = updates.count
                }
''', '                // The shared host owns its application badge.\n')
        self.assertTrue(embedded.endswith(fetch))

    def test_saved_proxy_preference_and_database_recreation_are_honored(self):
        runtime = (ROOT / 'apps/ios/Sources/KittyStoreEmbedded/KittyStoreEmbeddedFactory.swift').read_text()
        self.assertNotIn('UserDefaults.standard.enableEMPforWireguard = false', runtime)
        self.assertIn('if UserDefaults.standard.recreateDatabaseOnNextStart', runtime)
        self.assertLess(runtime.index('DatabaseManager.recreateDatabase()'), runtime.index('static func startIfNeeded'))
        host = (ROOT / 'apps/ios/Sources/Litter/LitterApp.swift').read_text()
        self.assertIn('guard AppDistributionCapabilities.includesKittyStore else { completionHandler(.noData); return }', host)
        self.assertIn('KittyStoreEmbeddedBridge.performBackgroundFetch(completion: completionHandler)', host)

if __name__ == '__main__':
    unittest.main()
