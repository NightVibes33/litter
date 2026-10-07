from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
IOS = ROOT / "apps/ios/Sources/Litter"

class OnboardingConfigurationTests(unittest.TestCase):
    def test_first_run_is_presented_and_completion_persisted(self):
        source = (IOS / "LitterApp.swift").read_text()
        self.assertIn("@AppStorage(LitterOnboardingState.completedVersionKey)", source)
        self.assertIn("if onboardingCompletedVersion == 0", source)
        self.assertIn(".fullScreenCover(isPresented: $showFirstRunOnboarding)", source)
        self.assertIn("onboardingCompletedVersion = LitterOnboardingState.currentVersion", source)

    def test_settings_tool_rows_share_existing_style(self):
        source = (IOS / "Views/SettingsView.swift").read_text()
        for title in ("Files", "Terminal", "Replay Onboarding"):
            self.assertIn('SettingsRowLabel(title: "' + title + '"', source)
        self.assertIn("if experimentalFeatures.isEnabled(.terminal)", source)
        self.assertIn("case .terminal: ExperimentalFeatures.shared.isEnabled(.terminal)", source)

    def test_tour_uses_current_features_and_routes(self):
        source = (IOS / "Views/OnboardingView.swift").read_text()
        self.assertNotIn('title: "PiP"', source)
        self.assertNotIn('onOpenSettingsRoute("aiProviders")', source)
        self.assertIn('onOpenSettingsRoute("account")', source)
        self.assertIn('ExperimentalFeatures.shared.isEnabled(.terminal) ? "Open Terminal" : nil', source)
        self.assertNotIn("old Nyxian BuildKit", source)
