"""Regression checks for the embedded SideStore recommendation integration.

The native iOS target builds in Actions; these checks protect source-level
contracts until the full upstream SideStore framework migration is complete.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCES = ROOT / 'ThirdParty/SideStore/Source/AltStore/Operations/UpdateKnownSourcesOperation.swift'
ANISETTE = ROOT / 'ThirdParty/SideStore/Source/AltStore/Operations/FetchAnisetteDataOperation.swift'


class SideStoreCatalogContractTests(unittest.TestCase):
    def test_official_defaults_and_custom_catalog_are_merged(self):
        code = SOURCES.read_text()
        self.assertIn('case defaultSources = "default"', code)
        self.assertIn('(response.defaultSources ?? [])', code)
        self.assertIn('(response.sources ?? [])', code)
        self.assertIn('(response.trusted ?? [])', code)
        self.assertIn('responses[url]?.blocked ?? []', code)

    def test_sources_remain_opt_in(self):
        code = SOURCES.read_text()
        self.assertIn('The Add Source screen still needs an explicit plus/confirmation.', code)
        self.assertIn('sourceURL.scheme?.lowercased() == "https"', code)
        self.assertIn('if seen.insert(key).inserted', code)

    def test_catalog_callbacks_do_not_mutate_captured_local_dictionaries(self):
        code = SOURCES.read_text()
        self.assertIn('private final class CatalogCollector: @unchecked Sendable', code)
        self.assertIn('let (responses, lastError) = collector.snapshot()', code)
        self.assertNotIn('responses[url] = parsed', code)

    def test_anisette_rejects_missing_device_identity_without_logging_secrets(self):
        code = ANISETTE.read_text()
        self.assertIn('if let object = parsed as? [String: Any]', code)
        self.assertIn('guard let clientInfo = self.clientInfo', code)
        self.assertNotIn('self.printOut("Anisette used:', code)
        self.assertNotIn('self.printOut("Original JSON:', code)


if __name__ == '__main__':
    unittest.main()
