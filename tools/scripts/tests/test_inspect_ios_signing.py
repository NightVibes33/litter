import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('signing', Path(__file__).parents[1] / 'inspect-ios-signing.py')
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


class SigningTests(unittest.TestCase):
    def test_empty_filtered_lookup_falls_back_to_exact_paginated_match(self):
        class Apple:
            def collection(self, path):
                if 'filter%5Bidentifier%5D' in path:
                    return []
                if path == '/v1/bundleIds?limit=200':
                    return [
                        {'id': 'wrong', 'attributes': {'identifier': 'com.example.other'}},
                        {'id': 'right', 'attributes': {'identifier': 'com.example.app'}},
                    ]
                if path != '/v1/bundleIds/right/bundleIdCapabilities?limit=200':
                    raise AssertionError(path)
                return []
        self.assertEqual(signing.inspect(Apple(), 'com.example.app')['capabilityTypes'], [])

    def test_exact_bundle_capabilities_are_read_without_mutation(self):
        calls = []

        class Apple:
            def collection(self, path):
                calls.append(path)
                if len(calls) == 1:
                    return [{'id': 'app-resource', 'attributes': {'identifier': 'com.example.app', 'platform': 'IOS'}}]
                return [{'attributes': {'capabilityType': 'EXTENDED_VIRTUAL_ADDRESSING'}}]

        result = signing.inspect(Apple(), 'com.example.app')
        self.assertEqual(result['capabilityTypes'], ['EXTENDED_VIRTUAL_ADDRESSING'])
        self.assertIn('filter%5Bidentifier%5D=com.example.app', calls[0])
        self.assertEqual(calls[1], '/v1/bundleIds/app-resource/bundleIdCapabilities?limit=200')

    def test_duplicate_or_wrong_bundle_is_rejected_before_capability_lookup(self):
        for bundles in ([], [{'attributes': {'identifier': 'wrong'}}], [None, None]):
            class Apple:
                def collection(self, path):
                    return bundles
            with self.assertRaises(RuntimeError):
                signing.inspect(Apple(), 'com.example.app')
