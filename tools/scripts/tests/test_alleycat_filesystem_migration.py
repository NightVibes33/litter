"""Black-box tests for Alley Cat fakefs migration (never write to real /root)."""

from pathlib import Path
import re
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[3] / "apps/ios/Sources/Litter/Models/IshFS.swift"


def migration_script(fake_root: Path) -> str:
    swift = SOURCE.read_text(encoding="utf-8")
    match = re.search(
        r'private static let alleyCatFilesystemMigrationScript = """\n(.*?)\n    """',
        swift,
        re.DOTALL,
    )
    if match is None:
        raise AssertionError("Alley Cat fakefs migration script missing")
    script = match.group(1)
    # Rebase ALL app-owned /root paths into the private fixture. No test code
    # should ever execute the migration against a real device/root filesystem.
    script = re.sub(
        r'(?<![\w/])/root(?=/|\s|$)',
        str(fake_root),
        script,
    )
    if "/root/" in script or " /root " in script:
        raise AssertionError("Unrebased /root path; refusing to execute")
    return script


def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


class AlleyCatFilesystemMigrationTests(unittest.TestCase):
    def test_migrates_nested_conflicts_and_keeps_legacy_aliases(self):
        with tempfile.TemporaryDirectory(prefix="alleycat-fakefs-test-") as base:
            root = Path(base) / "root"
            old = root / ".litter"
            canonical = root / ".alleycat"
            write(old / "builds" / "job" / "status.txt", "legacy result")
            write(old / "builds" / "job" / "log.txt", "legacy log")
            write(old / "builds" / "another-job" / "status.txt", "other job")
            write(old / "attachments" / "report.txt", "report data")
            write(old / "z-after-nested.txt", "must remain at root")
            write(canonical / "builds" / "job" / "status.txt", "canonical result")
            write(canonical / "builds" / "job" / "new.txt", "canonical sibling")
            write(root / ".cache" / "litter" / "state.txt", "cache")
            write(root / "litter" / "my-project" / "main.swift", "project")
            write(root / "unrelated" / "keep.txt", "untouched")
            script = migration_script(root)

            run = subprocess.run(["/bin/sh", "-c", script], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertEqual((canonical / "builds" / "job" / "status.txt").read_text(), "canonical result")
            self.assertEqual((canonical / "builds" / "job" / "log.txt").read_text(), "legacy log")
            self.assertEqual((canonical / "builds" / "job" / "new.txt").read_text(), "canonical sibling")
            self.assertEqual((canonical / "builds" / "another-job" / "status.txt").read_text(), "other job")
            self.assertEqual((canonical / "attachments" / "report.txt").read_text(), "report data")
            self.assertEqual((canonical / "z-after-nested.txt").read_text(), "must remain at root")
            self.assertEqual((root / ".cache" / "alleycat" / "state.txt").read_text(), "cache")
            self.assertEqual((root / "alley-cat" / "my-project" / "main.swift").read_text(), "project")
            self.assertEqual((root / "unrelated" / "keep.txt").read_text(), "untouched")

            backups = sorted(root.glob(".alleycat-migration-backup-*"))
            self.assertEqual(len(backups), 1, run.stdout)
            self.assertEqual(
                (backups[0] / ".litter" / "builds" / "job" / "status.txt").read_text(),
                "legacy result",
            )
            for legacy, target in [
                (old, canonical),
                (root / ".cache" / "litter", root / ".cache" / "alleycat"),
                (root / "litter", root / "alley-cat"),
            ]:
                self.assertTrue(legacy.is_symlink(), f"{legacy} must remain an alias")
                self.assertEqual(legacy.resolve(), target.resolve())

            again = subprocess.run(["/bin/sh", "-c", script], capture_output=True, text=True)
            self.assertEqual(again.returncode, 0, again.stdout + again.stderr)
            self.assertEqual((canonical / "builds" / "job" / "log.txt").read_text(), "legacy log")
            self.assertEqual((root / "unrelated" / "keep.txt").read_text(), "untouched")

    def test_rejects_unrelated_legacy_symlink_without_following_it(self):
        with tempfile.TemporaryDirectory(prefix="alleycat-fakefs-test-") as base:
            root = Path(base) / "root"
            root.mkdir()
            unrelated = root / "external"
            write(unrelated / "keep.txt", "do not follow")
            (root / ".litter").symlink_to(unrelated)
            run = subprocess.run(
                ["/bin/sh", "-c", migration_script(root)], capture_output=True, text=True
            )
            self.assertNotEqual(run.returncode, 0)
            self.assertTrue((root / ".litter").is_symlink())
            self.assertEqual((unrelated / "keep.txt").read_text(), "do not follow")


if __name__ == "__main__":
    unittest.main()
