"""Regression coverage for LiveProcess's hidden LiveShim syscall declaration."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location(
    "nyxian_objc_ci_imports", ROOT / "tools/scripts/patch-nyxian-objc-ci-imports.py"
)
PATCH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PATCH)


class NyxianObjCImportsTests(unittest.TestCase):
    def test_explicit_module_import_for_both_upstream_header_styles(self):
        for directive in ("import", "include"):
            source = f"#import <Foundation/Foundation.h>\n#{directive} <LiveShim/LiveShimSyscall.h>\nvoid run(void) {{ liveshim_syscall(1, 2); }}\n"
            result = PATCH.patch_liveshim_module_import(source)
            self.assertIn("@import LiveShim;", result)
            self.assertIn("void run(void) { liveshim_syscall(1, 2); }", result)
            self.assertEqual(PATCH.patch_liveshim_module_import(result), result)

    def test_missing_or_ambiguous_import_fails_instead_of_inventing_a_prototype(self):
        for source in ("void run(void);", "#import <LiveShim/LiveShimSyscall.h>\n" * 2):
            with self.assertRaises(ValueError):
                PATCH.patch_liveshim_module_import(source)

    @unittest.skipUnless(shutil.which("clang") or shutil.which("clang-18"), "Clang module compiler required")
    def test_patched_consumer_can_see_syscall_after_another_submodule_import(self):
        clang = shutil.which("clang") or shutil.which("clang-18")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            headers = root / "LiveShim.framework/Headers"
            modules = root / "LiveShim.framework/Modules"
            source_headers = root / "source/LiveShim"
            headers.mkdir(parents=True)
            modules.mkdir()
            source_headers.mkdir(parents=True)
            (headers / "LiveShim.h").write_text('#include "Service.h"\n#include "LiveShimSyscall.h"\n')
            (headers / "Service.h").write_text("void service(void);\n")
            syscall_header = "#ifndef LIVESHIMPREFS_H\n#define LIVESHIMPREFS_H\nlong liveshim_syscall(unsigned int syscall_num, ...);\n#endif\n"
            (headers / "LiveShimSyscall.h").write_text(syscall_header)
            (source_headers / "LiveShimSyscall.h").write_text(syscall_header)
            (modules / "module.modulemap").write_text('framework module LiveShim { umbrella header "LiveShim.h" export * module * { export * } }\n')
            # Xcode has both raw source headers and copied framework headers.
            # A header guard from another module include can suppress the raw
            # declaration without making the framework declaration visible.
            source = '#import <LiveShim/Service.h>\n#define LIVESHIMPREFS_H\n#import <LiveShim/LiveShimSyscall.h>\nlong run(void) { return liveshim_syscall(1, 2); }\n'
            consumer = root / "consumer.m"
            command = [
                clang, "-x", "objective-c", "-fmodules", "-fimplicit-module-maps",
                "-fmodules-cache-path=" + str(root / "cache"),
                "-I", str(root / "source"), "-F", str(root),
                "-Werror=implicit-function-declaration", "-fsyntax-only", str(consumer),
            ]
            consumer.write_text(source)
            broken = subprocess.run(command, text=True, capture_output=True)
            self.assertNotEqual(broken.returncode, 0)
            self.assertIn("must be imported from module", broken.stderr)
            consumer.write_text(PATCH.patch_liveshim_module_import(source))
            result = subprocess.run(command, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
