"""Exercise the actual CI overlay against isolated pinned source copies."""
import ast
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'tools/scripts/patch-emexde-generated-swift-imports-for-ios-ci.py'


class SwiftImportOverlayTests(unittest.TestCase):
    def test_overlay_retains_native_declarations_and_is_repeatable(self):
        paths = {node.value for node in ast.walk(ast.parse(SCRIPT.read_text()))
                 if isinstance(node, ast.Constant) and isinstance(node.value, str)
                 and node.value.startswith('ThirdParty/EmexDE/Source/')
                 and Path(node.value).suffix in {'.swift', '.m', '.cpp', '.plist'}}
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            for relative in paths:
                destination = workspace / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, destination)
            subprocess.run([sys.executable, str(SCRIPT)], cwd=workspace, check=True, capture_output=True)
            first = {path: (workspace / path).read_bytes() for path in paths}
            subprocess.run([sys.executable, str(SCRIPT)], cwd=workspace, check=True, capture_output=True)
            self.assertEqual(first, {path: (workspace / path).read_bytes() for path in paths})
            project = (workspace / 'ThirdParty/EmexDE/Source/Nyxian/LindChain/IDEFoundation/NXProject.m').read_text()
            target = (workspace / 'ThirdParty/EmexDE/Source/Nyxian/LindChain/IDEFoundation/NXTarget.m').read_text()
            userspace = (workspace / 'ThirdParty/EmexDE/Source/Nyxian/LindChain/ProcEnvironment/PEUserspaceManager.m').read_text()
            self.assertIn('#import <LindChain/IDEFoundation/NXBootstrap.h>', project)
            self.assertIn('@"arm64-apple-ios18.0"', project)
            self.assertIn('#import <MobileDevelopmentKit/MDKOSVersion.h>', target)
            self.assertIn('@interface NotificationServer : NSObject', userspace)
            console = (workspace / 'ThirdParty/EmexDE/Source/Nyxian/LindChain/IDEConsole/NXConsoleView.m').read_text()
            theme = (workspace / 'ThirdParty/EmexDE/Source/Nyxian/UI/CodeEditor/CodeEditor+Theme.swift').read_text()
            self.assertIn('@interface LDETheme : NSObject', console)
            self.assertIn('UIColor *gutterHairlineColor', console)
            self.assertIn('@objc(LDETheme) class LDETheme', theme)
            bootstrap = (workspace / 'ThirdParty/EmexDE/Source/Nyxian/LindChain/IDEFoundation/NXBootstrap.m').read_text()
            self.assertIn('#import <LindChain/ProcEnvironment/Surface/trust/keychain.h>', bootstrap)


if __name__ == '__main__':
    unittest.main()
