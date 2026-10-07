from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[3]
SCRIPT = REPO / 'tools/scripts/patch-emexde-generated-swift-imports-for-ios-ci.py'
SOURCE = Path('ThirdParty/EmexDE/Source')


class EmexDEImportPatchTests(unittest.TestCase):
    def test_userspace_notification_bridge_survives_import_replacement_and_rerun(self):
        sources = [
            'Nyxian/UI/UIInit/Terminal.swift',
            'Nyxian/LindChain/WindowServer/Session/NXWindowSessionTerminal.m',
            'Nyxian/UI/FileList/iOSVersionPickerView.swift',
            'Nyxian/LindChain/IDEFoundation/Project+NotificationServer.swift',
            'Nyxian/UI/Settings/ApplicationManagement.swift',
            'Nyxian/LindChain/IDEFoundation/NXBootstrap.m',
            'Nyxian/LindChain/ProcEnvironment/PEProcessManager.m',
            'Nyxian/LindChain/IDEFoundation/NXTarget.m',
            'Nyxian/LindChain/ProcEnvironment/PEUserspaceManager.m',
            'Nyxian/LindChain/IDEConsole/NXConsoleView.m',
            'Nyxian/LindChain/IDEFoundation/NXProject.m',
            'Frameworks/CoreCompiler/Tools/CCDriver.cpp',
            'LiveProcess/Info.plist',
        ]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for relative in sources:
                destination = root / SOURCE / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(REPO / SOURCE / relative, destination)
            subprocess.run([sys.executable, str(SCRIPT)], cwd=root, check=True, capture_output=True)
            path = root / SOURCE / 'Nyxian/LindChain/ProcEnvironment/PEUserspaceManager.m'
            first = path.read_text()
            self.assertIn('@interface NotificationServer : NSObject', first)
            self.assertIn('NotifLevelError = 2', first)
            self.assertIn('[NotificationServer NotifyUserWithLevel:NotifLevelError', first)
            self.assertNotIn('Nyxian-Swift.h', first)
            target_path = root / SOURCE / 'Nyxian/LindChain/IDEFoundation/NXTarget.m'
            target_first = target_path.read_text()
            self.assertIn('#import <MobileDevelopmentKit/MDKOSVersion.h>', target_first)
            self.assertIn('[MDKOSVersion versionWithVersionString:', target_first)
            self.assertNotIn('Nyxian-Swift.h', target_first)
            project_path = root / SOURCE / 'Nyxian/LindChain/IDEFoundation/NXProject.m'
            project_first = project_path.read_text()
            self.assertIn('#import <LindChain/IDEFoundation/NXBootstrap.h>', project_first)
            self.assertIn('NXBootstrap.shared.sdkURL.path', project_first)
            self.assertNotIn('Nyxian-Swift.h', project_first)
            subprocess.run([sys.executable, str(SCRIPT)], cwd=root, check=True, capture_output=True)
            self.assertEqual(project_first, project_path.read_text())
            self.assertEqual(first, path.read_text())
            self.assertEqual(target_first, target_path.read_text())
