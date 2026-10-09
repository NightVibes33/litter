from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


class NyxianProjectCommandsTests(unittest.TestCase):
    def test_command_transport_reports_real_builder_diagnostics(self):
        bridge = (ROOT / "apps/ios/Sources/EmexDEEmbedded/NyxianCommandBridge.swift").read_text()
        shell = (ROOT / "apps/ios/Sources/Litter/Models/LitterBuildKit.swift").read_text()
        self.assertIn('case "info", "diagnostics", "clean", "build", "run":', shell)
        self.assertIn('"diagnosticsPath"]', shell)
        self.assertIn('project.cacheURL.appendingPathComponent("debug.json")', bridge)
        self.assertIn("NXBuilder.buildProject(withProject: project", bridge)
        self.assertIn("try builder.clean()", bridge)
        self.assertIn("bootstrapResult[\"exitCode\"] as? Int == 0", bridge)

    def test_diagnostics_are_bounded_and_not_read_during_a_build(self):
        bridge = (ROOT / "apps/ios/Sources/EmexDEEmbedded/NyxianCommandBridge.swift").read_text()
        self.assertIn("size.intValue <= 4_000_000", bridge)
        self.assertIn("guard data.count <= 4_000_000", bridge)
        self.assertIn("read(upToCount: 4_000_001)", bridge)
        self.assertIn("guard !NXBuilder.builds else", bridge)
        self.assertIn(".typeRegular", bridge)

    def test_utility_export_is_executable_and_completion_requires_artifact(self):
        bridge = (ROOT / "apps/ios/Sources/EmexDEEmbedded/NyxianCommandBridge.swift").read_text()
        self.assertIn('projectKind == .utility ? project.machoURL.path : project.packageURL.path', bridge)
        self.assertIn('if success, command == "build"', bridge)
        self.assertIn('size.int64Value > 0', bridge)
        self.assertIn('status: "build-artifact-missing"', bridge)
        self.assertIn('command == "run" ? "install-complete" : "build-complete"', bridge)
        self.assertIn('This does not report execution or a program exit status.', bridge)
