from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]

class NyxianEmbeddedStartupTests(unittest.TestCase):
    def test_signing_validation_waits_for_onboarding_and_attached_root(self):
        source = (ROOT / 'apps/ios/Sources/EmexDEEmbedded/EmexDEEmbeddedFactory.swift').read_text()
        start = source.index('private func checkSigningAfterOnboardingIfNeeded()')
        end = source.index('private func makeEmbeddedOnboardingConfiguration()', start)
        body = source[start:end]
        for guard in ['!checkedSigningSetup', 'tabViewController.parent != nil', '"NXOnboardingSentinel"', 'tabViewController.presentedViewController == nil']:
            self.assertIn(guard, body)
        self.assertIn('checkSigningSetup()', body)
        self.assertIn('self?.checkSigningAfterOnboardingIfNeeded()', source)

    def test_switcher_and_build_tab_guards_match_standalone_conditions(self):
        source = (ROOT / 'apps/ios/Sources/EmexDEEmbedded/EmexDEEmbeddedFactory.swift').read_text()
        self.assertIn('!NXApplicationState.extensionLessMode, #available(iOS 26.0, *)', source)
        self.assertIn('tabBarController.selectedViewController === viewController && NXBuilder.builds', source)

    def test_embedded_launch_preserves_host_uikit_appearance(self):
        source = (ROOT / 'apps/ios/Sources/EmexDEEmbedded/EmexDEEmbeddedFactory.swift').read_text()
        # The upstream helper resets appearance proxies globally. Its use in
        # an embedded controller would modify Alley Cat and KittyStore rows.
        self.assertNotRegex(source, r'(?m)^\s*RevertUI\(\)')
        self.assertIn('LDETheme.currentTheme = LDEThemeReader.shared.currentlySelectedTheme()', source)

    def test_loader_default_and_recovery_use_existing_upstream_state(self):
        source = (ROOT / 'apps/ios/Sources/EmexDEEmbedded/EmexDEEmbeddedFactory.swift').read_text()
        setting = 'NXApplicationState.loadKernelExtensions = UserDefaults.standard.bool(forKey: "nyxian.boot.kextLoading")'
        self.assertIn(setting, source)
        self.assertLess(source.index(setting), source.index('PEUserspaceManager.shared().boot'))
        self.assertIn('NXUITabBarController()', source)
        self.assertIn('NXSettingsTableViewController()', source)
        self.assertNotIn('UIThemedTabViewController()', source)
        self.assertNotIn('SettingsViewController()', source)
        self.assertNotIn('= currentTheme?.backgroundColor', source)
        self.assertIn('NXApplicationState.restartAppWithoutKEXTLoadingEnabled()', source)
        settings = (ROOT / 'apps/ios/Sources/Litter/Views/SettingsView.swift').read_text()
        self.assertIn('if AppDistributionCapabilities.includesEmexDE', settings)
        self.assertIn('showNyxianRecoveryConfirmation', settings)
        self.assertIn('Save any open files first.', settings)

if __name__ == '__main__':
    unittest.main()
