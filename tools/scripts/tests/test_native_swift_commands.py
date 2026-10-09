from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


class NativeSwiftCommandsTests(unittest.TestCase):
    def test_version_queries_execute_frontend_and_never_fabricate_metadata(self):
        swift = (ROOT / "apps/ios/Sources/Litter/Models/LitterBuildKit.swift").read_text()
        native = (ROOT / "ThirdParty/Nyxian/LitterBuildKitNative/LitterBuildKitInProcess.mm").read_text()
        self.assertNotIn("compatibilityVersionLog", swift)
        self.assertEqual(swift.count("return await nativeCompilerVersion(cwd: cwd, buildDir: buildDir)"), 2)
        self.assertIn('jobWithType:kCCJobTypeSwiftCompiler withArguments:@[@"-version"]', native)
        self.assertIn("LBIExecuteJob(job, &diagnostics, nil)", native)
        self.assertIn("if(!ok || output.length == 0)", native)
        self.assertIn("@finally", native)
        self.assertIn("dup2(saved, STDOUT_FILENO)", native)

    def test_no_success_claim_for_unexecuted_tests_or_interpreter(self):
        swift = (ROOT / "apps/ios/Sources/Litter/Models/LitterBuildKit.swift").read_text()
        native = (ROOT / "ThirdParty/Nyxian/LitterBuildKitNative/LitterBuildKitInProcess.mm").read_text()
        self.assertNotIn("swift-e-check-ok", swift)
        self.assertNotIn("swift-test-ok", native)
        self.assertIn('exitCode: 64, status: "swift-tests-unavailable"', swift)
        self.assertIn('exitCode: 64, status: "swift-execution-unavailable"', swift)
        self.assertIn('exitCode: 64, status: "swiftpm-unavailable"', swift)
