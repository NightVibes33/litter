import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("layout", ROOT / "tools/scripts/verify-nyxian-runtime-layout.py")
layout = importlib.util.module_from_spec(spec)
spec.loader.exec_module(layout)


class NyxianRuntimeLayoutTests(unittest.TestCase):
    def fixture(self, app):
        (app / "Shared").mkdir()
        for name in ("include", "lib", "swift"):
            with zipfile.ZipFile(app / "Shared" / (name + ".zip"), "w") as archive:
                archive.writestr(name + "/runtime-resource", b"upstream")
        framework = app / "Frameworks/CoreCompiler.framework"
        framework.mkdir(parents=True)
        (framework / "CoreCompiler").write_bytes(b"in-process compiler")

    def test_upstream_layout_passes_without_standalone_compiler(self):
        with tempfile.TemporaryDirectory() as folder:
            app = Path(folder)
            self.fixture(app)
            layout.verify(app)

    def test_standalone_toolchain_in_either_bundle_is_rejected(self):
        for relative in ("Shared/SwiftToolchain", "Frameworks/emexDE.framework/Shared/SwiftToolchain"):
            with self.subTest(relative=relative), tempfile.TemporaryDirectory() as folder:
                app = Path(folder)
                self.fixture(app)
                (app / relative).mkdir(parents=True)
                with self.assertRaisesRegex(ValueError, "Standalone"):
                    layout.verify(app)

    def test_missing_or_invalid_compressed_resource_fails(self):
        with tempfile.TemporaryDirectory() as folder:
            app = Path(folder)
            self.fixture(app)
            (app / "Shared/swift.zip").write_bytes(b"not a zip")
            with self.assertRaisesRegex(ValueError, "swift"):
                layout.verify(app)

    def test_compiler_framework_is_retained(self):
        with tempfile.TemporaryDirectory() as folder:
            app = Path(folder)
            self.fixture(app)
            (app / "Frameworks/CoreCompiler.framework/CoreCompiler").unlink()
            with self.assertRaisesRegex(ValueError, "CoreCompiler"):
                layout.verify(app)
