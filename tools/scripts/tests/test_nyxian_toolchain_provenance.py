import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

script = Path(__file__).parents[1] / 'nyxian-toolchain-provenance.py'
spec = importlib.util.spec_from_file_location('toolchain_provenance', script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ToolchainProvenanceTests(unittest.TestCase):
    def test_matching_complete_artifacts_pass_but_other_revisions_and_tampering_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            expected = {'nyxian_revision': 'a', 'llvm_on_ios_revision': 'b', 'swift_tag': 'swift-6.3.3-RELEASE'}
            for name in module.FILES:
                (root / name).write_bytes(b'matching build output')
            manifest = {'schema': 1, 'sources': expected,
                        'built_revisions': {'swift': 'c', 'llvm-project': 'd'},
                        'sha256': {name: module.digest(root / name) for name in module.FILES}}
            (root / 'provenance.json').write_text(json.dumps(manifest))
            module.verify(root, expected)
            with self.assertRaisesRegex(ValueError, 'pinned'):
                module.verify(root, {**expected, 'llvm_on_ios_revision': 'another-revision'})
            (root / module.FILES[0]).write_bytes(b'old compiler substituted')
            with self.assertRaisesRegex(ValueError, 'checksum'):
                module.verify(root, expected)

    def test_unproven_artifacts_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'provenance.json').write_text(json.dumps({'schema': 1, 'sources': {}, 'sha256': {}}))
            with self.assertRaisesRegex(ValueError, 'checksum'):
                module.verify(root, {})
