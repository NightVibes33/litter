import importlib.util
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "prepare-sideload-entitlements.py"
spec = importlib.util.spec_from_file_location("sideload_entitlements", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SideloadEntitlementTests(unittest.TestCase):
    def test_missing_entitlement_fails_even_when_codesign_succeeds(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory)
            (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "Litter"}))
            (app / "Litter").write_bytes(b"fixture")
            response = subprocess.CompletedProcess([], 0, plistlib.dumps({}))
            with patch.object(module.subprocess, "run", return_value=response):
                with self.assertRaisesRegex(ValueError, "lost required"):
                    module.prepare(app)

    def test_signer_input_requests_real_capability_without_team_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory)
            (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "Litter"}))
            (app / "Litter").write_bytes(b"fixture")
            def codesign(args, **kwargs):
                if "--sign" in args:
                    requested = plistlib.loads(Path(args[args.index("--entitlements") + 1]).read_bytes())
                    self.assertEqual(requested, {module.VA: True})
                    self.assertEqual(args[args.index("--sign") + 1], "-")
                    self.assertEqual(args[-1], str(app / "Litter"))
                return subprocess.CompletedProcess(args, 0, plistlib.dumps({module.VA: True}))
            with patch.object(module.subprocess, "run", side_effect=codesign):
                module.prepare(app)

    def test_executable_cannot_escape_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory)
            (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "../Other"}))
            with self.assertRaisesRegex(ValueError, "Invalid"):
                module.prepare(app)
