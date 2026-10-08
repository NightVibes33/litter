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

    def test_tools_are_controlled_from_advanced_and_launched_from_home(self):
        settings = (IOS / "Views/SettingsView.swift").read_text()
        self.assertIn('SettingsRowLabel(title: "Replay Onboarding"', settings)
        self.assertNotIn('NavigationLink(value: AlleyCatToolRoute.files)', settings)
        self.assertNotIn('NavigationLink(value: AlleyCatToolRoute.terminal)', settings)
        for feature in ("files", "terminal"):
            self.assertIn(f"case .{feature}: ExperimentalFeatures.shared.isEnabled(.{feature})", settings)
            model = (IOS / "Models/ExperimentalFeatures.swift").read_text()
            self.assertIn(f"case .{feature}: return false", model)
            app = (IOS / "LitterApp.swift").read_text()
            self.assertIn(f"guard experimentalFeatures.isEnabled(.{feature})", app)
        home = (IOS / "Views/HomeDashboardView.swift").read_text()
        self.assertIn("if let onShowFiles", home)

    def test_tour_uses_current_features_and_routes(self):
        source = (IOS / "Views/OnboardingView.swift").read_text()
        self.assertNotIn('title: "PiP"', source)
        self.assertNotIn('onOpenSettingsRoute("aiProviders")', source)
        self.assertIn('onOpenSettingsRoute("account")', source)
        self.assertIn('ExperimentalFeatures.shared.isEnabled(.terminal) ? "Open Terminal" : nil', source)
        self.assertNotIn("old Nyxian BuildKit", source)

    def test_disabled_file_actions_open_advanced_instead_of_dismissing_to_nowhere(self):
        onboarding = (IOS / "Views/OnboardingView.swift").read_text()
        self.assertIn('onOpenSettingsRoute("advanced")', onboarding)
        self.assertNotIn('finishAndOpen { onOpenFiles(', onboarding)
        settings = (IOS / "Views/SettingsView.swift").read_text()
        self.assertIn('case .advanced: settingsPage("Advanced") { advancedSections }', settings)
        files = (IOS / "Views/LocalFileWorkspaceView.swift").read_text()
        self.assertIn('guard ExperimentalFeatures.shared.isEnabled(.terminal)', files)
