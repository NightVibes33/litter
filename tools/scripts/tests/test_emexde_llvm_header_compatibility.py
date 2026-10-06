import importlib.util
from pathlib import Path
import tempfile
import unittest

script = Path(__file__).parents[1] / 'patch-emexde-llvm-header-compatibility.py'
spec = importlib.util.spec_from_file_location('llvm_header_compatibility', script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class HeaderCompatibilityTests(unittest.TestCase):
    def test_old_headers_are_extended_without_replacing_layout_and_are_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            compiler = root / 'llvm/Support/Compiler.h'
            target = root / 'llvm/MC/MCTargetOptions.h'
            compiler.parent.mkdir(parents=True)
            target.parent.mkdir(parents=True)
            compiler.write_text('#define LLVM_EXTERNAL_VISIBILITY __attribute__((visibility("default")))\n')
            original = 'namespace llvm { class MCTargetOptions { public: unsigned Flags; }; }\n'
            target.write_text(original)
            module.patch_headers(root)
            first = (compiler.read_text(), target.read_text())
            self.assertTrue(first[1].startswith(original))
            self.assertIn('#define LLVM_ABI LLVM_EXTERNAL_VISIBILITY', first[0])
            self.assertIn('enum class CASBackendMode { Native, CASID, Verify };', first[1])
            module.patch_headers(root)
            self.assertEqual(first, (compiler.read_text(), target.read_text()))

    def test_existing_upstream_definitions_are_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = {'llvm/Support/Compiler.h': '#define LLVM_ABI __attribute__((visibility("default")))\n',
                     'llvm/MC/MCTargetOptions.h': 'namespace llvm { enum class CASBackendMode { Native, CASID, Verify }; }\n'}
            for path, text in paths.items():
                file = root / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(text)
            module.patch_headers(root)
            for path, text in paths.items():
                self.assertEqual((root / path).read_text(), text)
