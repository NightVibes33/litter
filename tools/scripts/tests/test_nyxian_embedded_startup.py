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

if __name__ == '__main__':
    unittest.main()
