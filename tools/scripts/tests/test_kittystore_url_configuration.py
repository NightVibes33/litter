import importlib.util
import plistlib
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]

class KittyStoreURLConfigurationTests(unittest.TestCase):
    def test_unsigned_owns_only_its_store_scheme_and_signed_preserves_login(self):
        source = (ROOT / 'apps/ios/Sources/Litter/Info.plist').read_text()
        original = plistlib.loads(source.encode())
        schemes = [s for entry in original['CFBundleURLTypes'] for s in entry['CFBundleURLSchemes']]
        self.assertIn('kittystore', schemes)
        self.assertNotIn('sidestore', schemes)
        self.assertNotIn('altstore', schemes)
        spec = importlib.util.spec_from_file_location('fast_project', ROOT / 'tools/scripts/patch-ios-testflight-fast-project.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        patched = module.strip_info_plist_app_store_sensitive_keys(source)
        safe = plistlib.loads(patched.encode())
        self.assertEqual([s for entry in safe['CFBundleURLTypes'] for s in entry['CFBundleURLSchemes']], ['litterauth'])
        self.assertEqual(module.strip_info_plist_app_store_sensitive_keys(patched), patched)

if __name__ == '__main__':
    unittest.main()
