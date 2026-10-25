"""Execute the production shell probe against real ZIP bytes and failures."""
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest
import zipfile

SOURCE = Path(__file__).resolve().parents[3] / "apps/ios/Sources/Litter/Models/ConversationAttachmentSupport.swift"


def probe(path):
    source = SOURCE.read_text().split("static func verifiedLocalAttachmentContext", 1)[1]
    script = re.search(r'let result = await IshFS.run\("""\n(.*?)\n\s*"""\)', source, re.S).group(1)
    script = script.replace(r"\(quotedPath)", shlex.quote(str(path)))
    return subprocess.run(["sh", "-c", script], capture_output=True, text=True)


class LocalAttachmentProbeTests(unittest.TestCase):
    def test_zip_bytes_read_with_spaces_quotes_and_shell_characters(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Project ' $(exit 91);.zip"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("hello.txt", "Attachment bytes, not an iPhone URL")
            result = probe(path)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(int(result.stdout.strip()), path.stat().st_size)
            with zipfile.ZipFile(path) as archive:
                self.assertEqual(archive.read("hello.txt"), b"Attachment bytes, not an iPhone URL")

    def test_missing_file_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertNotEqual(probe(Path(directory) / "missing.zip").returncode, 0)

    def test_folder_remains_supported(self):
        with tempfile.TemporaryDirectory() as directory:
            result = probe(directory)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "directory")


if __name__ == "__main__":
    unittest.main()
