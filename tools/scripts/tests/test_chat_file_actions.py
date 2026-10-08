from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
IOS = ROOT / 'apps/ios/Sources/Litter'

class ChatFileActionTests(unittest.TestCase):
    def test_archive_does_not_read_archived_thread_or_swallow_errors(self):
        source = (IOS / 'LitterApp.swift').read_text()
        action = source.split('private func deleteThread(_ key: ThreadKey) async {', 1)[1].split('/// Long-press', 1)[0]
        self.assertNotIn('try?', action)
        self.assertNotIn('refreshThreadSnapshot', action)
        self.assertIn('homeDashboardModel.unpinThread(key)', action)
        self.assertIn('actionErrorMessage =', action)

    def test_empty_model_label_does_not_claim_app_name_is_model(self):
        source = (IOS / 'Views/ConversationView.swift').read_text()
        self.assertIn('return trimmed.isEmpty ? "Select Model" : trimmed', source)

    def test_rename_preserves_dangling_symlink(self):
        self.check_rename(existing_link=True)

    def test_rename_handles_spaces_and_quote_without_overwrite(self):
        self.check_rename(existing_link=False)

    def check_rename(self, existing_link):
        source = (IOS / 'Models/IshFS.swift').read_text()
        section = source.split('static func rename(path: String, to destination: String)', 1)[1]
        command = re.search(r'let result = await run\("(.*)"\)', section).group(1)
        command = command.replace('\\"', '"')
        with tempfile.TemporaryDirectory() as directory:
            src = Path(directory) / "source's file"
            dest = Path(directory) / 'target file'
            src.write_text('original')
            if existing_link:
                dest.symlink_to(Path(directory) / 'absent')
            command = command.replace('\\(shellQuote(path))', shlex.quote(str(src)))
            command = command.replace('\\(shellQuote(destination))', shlex.quote(str(dest)))
            result = subprocess.run(['sh', '-c', command], capture_output=True)
            if existing_link:
                self.assertEqual(result.returncode, 17)
                self.assertTrue(dest.is_symlink())
                self.assertEqual(src.read_text(), 'original')
            else:
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(dest.read_text(), 'original')
                self.assertFalse(src.exists())
