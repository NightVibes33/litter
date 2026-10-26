import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("upstream_parity", Path(__file__).resolve().parents[1] / "upstream_parity.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReviewedParityTests(unittest.TestCase):
    def classify(self, upstream="upstream", fork="reviewed", reason="Crash prevention"):
        return module.classify_drift(["core"], {"core": upstream}, {"core": fork}, {
            "core": {"upstream_blob": "upstream", "fork_blob": "reviewed", "reason": reason}
        })

    def test_exact_reviewed_pair_is_reported(self):
        self.assertEqual(self.classify(), ([], ["core"]))

    def test_new_upstream_changes_still_fail(self):
        self.assertEqual(self.classify(upstream="new"), (["core"], []))

    def test_new_fork_changes_still_fail(self):
        self.assertEqual(self.classify(fork="unreviewed"), (["core"], []))

    def test_missing_reason_is_not_an_exception(self):
        self.assertEqual(self.classify(reason=""), (["core"], []))

    def test_removed_file_still_fails(self):
        self.assertEqual(module.classify_drift(["core"], {"core": "upstream"}, {}, {}), (["core"], []))

    def test_identical_core_needs_no_exception(self):
        self.assertEqual(module.classify_drift(["core"], {"core": "same"}, {"core": "same"}, {}), ([], []))
