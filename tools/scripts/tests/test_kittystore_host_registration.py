from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
CORE = ROOT / 'ThirdParty/SideStore/Source/AltStoreCore/Model'

class KittyStoreHostRegistrationTests(unittest.TestCase):
    def test_host_registration_does_not_skip_profiles_extensions_or_bundle_cache(self):
        database = (CORE / 'DatabaseManager/DatabaseManager.swift').read_text()
        self.assertNotIn('isEmbeddedSideStoreRuntime', database)
        self.assertIn('for appExtension in localApp.appExtensions', database)
        self.assertIn('installedApp.appExtensions = installedExtensions', database)
        self.assertIn('appId.hasSuffix(Bundle.main.bundleIdentifier!)', database)
        self.assertIn('try FileManager.default.copyItem(at: Bundle.main.bundleURL, to: temporaryFileURL)', database)
        self.assertIn('try update(appBundle, bundleID: StoreApp.altstoreAppID)', database)
        self.assertNotIn('Skipping self-app bundle cache', database)

    def test_original_host_identity_takes_precedence_over_resigned_identifier(self):
        source = (CORE / 'StoreApp.swift').read_text()
        start = source.index('static let altstoreAppID: String = {')
        end = source.index('}()', start)
        identity = source[start:end]
        self.assertIn('"LitterEmbedsSideStore"', identity)
        self.assertLess(identity.index('Bundle.Info.altBundleID'), identity.index('?? Bundle.main.bundleIdentifier'))
        self.assertIn('return Bundle.Info.appbundleIdentifier', identity)

if __name__ == '__main__':
    unittest.main()
