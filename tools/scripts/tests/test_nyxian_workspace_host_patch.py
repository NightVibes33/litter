"""Regression tests for the embedded Nyxian shared workspace build mode."""

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "scripts"))
from nyxian_workspace_host_patch import (
    OLD_BRANCH,
    HOST_BRANCH,
    OLD_ENDIF,
    HOST_ENDIF,
    patch_workspace_host_selector,
)

UPSTREAM_WORKSPACE = """#import "LDEApplicationWorkspace.h"
#if __has_include(<Nyxian-Swift.h>)
#define LIVEPROCESS 0
#import <LindChain/ProcEnvironment/PELaunchServiceManager.h>
#import <LindChain/ProcEnvironment/PEProcessManager.h>
#else
#include <ksurface_config.h>
#import <Frameworks/LiveShim/LiveShimSyscall.h>
#define LIVEPROCESS 1
#endif /* __has_include(<Nyxian-Swift.h>) */
"""


class NyxianWorkspaceHostPatchTests(unittest.TestCase):
    def test_host_and_extension_both_preserved(self):
        patched = patch_workspace_host_selector(UPSTREAM_WORKSPACE)
        self.assertIn(HOST_BRANCH, patched)
        self.assertIn(HOST_ENDIF, patched)
        self.assertIn("#import <LindChain/ProcEnvironment/PEProcessManager.h>", patched)
        self.assertIn("#import <Frameworks/LiveShim/LiveShimSyscall.h>", patched)
        self.assertIn("#define LIVEPROCESS 1", patched)
        self.assertNotIn(OLD_BRANCH, patched)
        self.assertNotIn(OLD_ENDIF, patched)

    def test_idempotent(self):
        patched = patch_workspace_host_selector(UPSTREAM_WORKSPACE)
        self.assertEqual(patch_workspace_host_selector(patched), patched)

    def test_missing_upstream_selector_fails_loudly(self):
        with self.assertRaises(ValueError):
            patch_workspace_host_selector(UPSTREAM_WORKSPACE.replace(OLD_BRANCH, "#if DEBUG"))

    def test_duplicate_selector_fails_loudly(self):
        with self.assertRaises(ValueError):
            patch_workspace_host_selector(UPSTREAM_WORKSPACE.replace(OLD_BRANCH, OLD_BRANCH + "\n" + OLD_BRANCH))

    def test_liveprocess_branch_cannot_be_dropped(self):
        with self.assertRaises(ValueError):
            patch_workspace_host_selector(UPSTREAM_WORKSPACE.replace("#define LIVEPROCESS 1", ""))

    def test_ci_targets_real_workspace_and_explicit_host_flag(self):
        patch_script = (ROOT / "tools/scripts/patch-emexde-generated-swift-imports-for-ios-ci.py").read_text()
        project = (ROOT / "apps/ios/project.yml").read_text()
        self.assertIn("LiveProcess/LindChain/Services/bootstrapd/LDEApplicationWorkspace.m", patch_script)
        self.assertIn("if not workspace.is_file():", patch_script)
        self.assertIn("HOST_ENV=1", project)
        self.assertIn("- path: ../../ThirdParty/EmexDE/Source/LiveProcess/LindChain/Services/bootstrapd/LDEApplicationWorkspace.m", project)


if __name__ == "__main__":
    unittest.main()
