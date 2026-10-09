import importlib.util
import plistlib
from pathlib import Path
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[3]

class KittyStoreIntentIntegrationTests(unittest.TestCase):
    def test_real_definitions_and_handlers_are_included_and_stub_removed(self):
        project = yaml.safe_load((ROOT / 'apps/ios/project.yml').read_text())
        for target in ('AltStoreCore', 'SideStore'):
            sources = project['targets'][target]['sources']
            for source in sources:
                if isinstance(source, dict):
                    self.assertNotIn('Intents/**', source.get('excludes', []))
                    self.assertNotIn('Extensions/INInteraction+AltStore.swift', source.get('excludes', []))
            self.assertEqual(project['targets'][target]['settings']['base']['INTENTS_CODEGEN_LANGUAGE'], 'Swift')
        compatibility = (ROOT / 'apps/ios/Sources/KittyStoreEmbedded/KittyStoreNukeCompatibility.swift').read_text()
        self.assertNotIn('final class RefreshAllIntent', compatibility)
        factory = (ROOT / 'apps/ios/Sources/KittyStoreEmbedded/KittyStoreEmbeddedFactory.swift').read_text()
        self.assertIn('case is RefreshAllIntent: return refreshIntentHandler', factory)
        self.assertIn('case is ViewAppIntent: return viewAppIntentHandler', factory)

    def test_safe_build_removes_legacy_registration_and_discovery(self):
        info = (ROOT / 'apps/ios/Sources/Litter/Info.plist').read_text()
        self.assertEqual(plistlib.loads(info.encode())['INIntentsSupported'], ['RefreshAllIntent', 'ViewAppIntent'])
        spec = importlib.util.spec_from_file_location('fast_intents', ROOT / 'tools/scripts/patch-ios-testflight-fast-project.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertNotIn('INIntentsSupported', plistlib.loads(module.strip_info_plist_app_store_sensitive_keys(info).encode()))
        discovery = (ROOT / 'apps/ios/Sources/Litter/Models/KittyStoreIntentDiscovery.swift').read_text()
        self.assertIn('#if !LITTER_APP_STORE_SAFE && canImport(SideStore)', discovery)
        self.assertIn('[KittyStoreAppIntentsPackage.self]', discovery)

    def test_modern_intent_retains_upstream_refresh_and_embedded_only_bootstrap(self):
        source = (ROOT / 'ThirdParty/SideStore/Source/AltStore/Intents/App Intents/RefreshAllAppsIntent.swift').read_text()
        self.assertIn('#if ALLEY_CAT_EMBEDDED_STORE', source)
        self.assertIn('KittyStoreEmbeddedFactory.startTransportIfPossible()', source)
        self.assertIn('InstalledApp.fetchAppsForRefreshingAll(in: context)', source)
        self.assertIn('AppManager.shared.backgroundRefresh(installedApps', source)
        self.assertIn('requestToContinueInForeground()', source)
        self.assertIn('taskGroup.cancelAll()', source)

if __name__ == '__main__':
    unittest.main()
