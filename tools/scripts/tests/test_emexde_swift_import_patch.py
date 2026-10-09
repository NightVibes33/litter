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
            'Nyxian/UI/CodeEditor/CodeEditor+Theme.swift',
            'Nyxian/LindChain/WindowServer/Session/NXWindowSessionTerminal.m',
            'Nyxian/UI/FileList/iOSVersionPickerView.swift',
            'Nyxian/LindChain/IDEFoundation/Project+NotificationServer.swift',
            'Nyxian/UI/Settings/ApplicationManagement.swift',
            'Nyxian/LindChain/IDEFoundation/NXBootstrap.m',
            'Nyxian/LindChain/ProcEnvironment/PEProcessManager.m',
            'Nyxian/LindChain/IDEFoundation/NXTarget.m',
            'Nyxian/LindChain/ProcEnvironment/PEUserspaceManager.m',
            'Nyxian/LindChain/ProcEnvironment/Shims/LSApplicationWorkspace.m',
            'Nyxian/LindChain/IDEConsole/NXConsoleView.m',
            'Nyxian/LindChain/IDEFoundation/NXProject.m',
            'Frameworks/CoreCompiler/Tools/CCDriver.cpp',
            'LiveProcess/Info.plist',
            'LiveProcess/LindChain/Services/applicationmgmtd/LDEApplicationWorkspace.m',
        ]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for relative in sources:
                destination = root / SOURCE / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(REPO / SOURCE / relative, destination)
            subprocess.run([sys.executable, str(SCRIPT)], cwd=root, check=True, capture_output=True)
            launch_services_path = root / SOURCE / 'Nyxian/LindChain/ProcEnvironment/Shims/LSApplicationWorkspace.m'
            launch_services_first = launch_services_path.read_text()
            self.assertIn('[super load];\n#if LITTER_EMBEDDED_NYXIAN\n    return;\n#endif', launch_services_first)
            bootstrap_path = root / SOURCE / 'Nyxian/LindChain/IDEFoundation/NXBootstrap.m'
            bootstrap_first = bootstrap_path.read_text()
            self.assertIn('#import <LindChain/ProcEnvironment/Surface/trust/keychain.h>', bootstrap_first)
            self.assertIn('ksurface_keychain_update()', bootstrap_first)
            self.assertIn('stringByAppendingPathComponent:@"Documents/Nyxian"', bootstrap_first)
            self.assertNotIn('stringByAppendingPathComponent:@"Documents"]];', bootstrap_first)
            self.assertIn('NSDataWritingAtomic error:&error', bootstrap_first)
            self.assertNotIn('failed to move emexlabs public rootca key', bootstrap_first)
            workspace_path = root / SOURCE / 'LiveProcess/LindChain/Services/applicationmgmtd/LDEApplicationWorkspace.m'
            workspace_first = workspace_path.read_text()
            self.assertIn('#if HOST_ENV\n#define LIVEPROCESS 0', workspace_first)
            self.assertIn('#import <LindChain/ProcEnvironment/PEProcessManager.h>', workspace_first)
            self.assertNotIn('#if __has_include(<Nyxian-Swift.h>)', workspace_first)
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
            theme_path = root / SOURCE / 'Nyxian/UI/CodeEditor/CodeEditor+Theme.swift'
            theme_first = theme_path.read_text()
            theme_original = (REPO / SOURCE / 'Nyxian/UI/CodeEditor/CodeEditor+Theme.swift').read_text()
            self.assertEqual(theme_original.replace('@objc class LDETheme: NSObject, Theme {',
                                                   '@objc(LDETheme) class LDETheme: NSObject, Theme {'),
                             theme_first)
            self.assertIn('@objc(LDETheme) class LDETheme: NSObject, Theme {', theme_first)
            console_path = root / SOURCE / 'Nyxian/LindChain/IDEConsole/NXConsoleView.m'
            console_first = console_path.read_text()
            self.assertIn('@interface LDETheme : NSObject', console_first)
            self.assertIn('+ (nullable LDETheme *)current;', console_first)
            self.assertIn('UIColor *gutterHairlineColor;', console_first)
            self.assertIn('[[LDETheme current] gutterHairlineColor]', console_first)
            self.assertNotIn('Nyxian-Swift.h', console_first)
            subprocess.run([sys.executable, str(SCRIPT)], cwd=root, check=True, capture_output=True)
            self.assertEqual(workspace_first, workspace_path.read_text())
            self.assertEqual(launch_services_first, launch_services_path.read_text())
            self.assertEqual(bootstrap_first, bootstrap_path.read_text())
            self.assertEqual(console_first, console_path.read_text())
            self.assertEqual(theme_first, theme_path.read_text())
            self.assertEqual(project_first, project_path.read_text())
            self.assertEqual(first, path.read_text())
            self.assertEqual(target_first, target_path.read_text())
