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

    def test_file_alerts_capture_presented_target(self):
        source = (IOS / 'Views/LocalFileWorkspaceView.swift').read_text()
        for target in ('deleteTarget', 'renameTarget', 'moveTarget'):
            self.assertIn(f'presenting: {target}) {{ target in', source)
            self.assertNotIn(f'guard let target = {target} else', source)

    def test_delete_shell_removes_files_folders_and_dangling_links(self):
        source = (IOS / 'Models/IshFS.swift').read_text()
        section = source.split('static func delete(path: String)', 1)[1]
        template = section.split('await run("""', 1)[1].split('""")', 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            file = root / "quote's file"
            file.write_text('data')
            folder = root / 'nonempty folder'
            folder.mkdir()
            (folder / 'child').write_text('data')
            link = root / 'broken link'
            link.symlink_to(root / 'absent')
            for target in (file, folder, link, root / 'already absent'):
                command = template.replace('\\(shellQuote(path))', shlex.quote(str(target)))
                command = command.replace('\\(nativeContainerMountPath)', '/mnt/container')
                result = subprocess.run(['sh', '-c', command], capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(target.exists())
                self.assertFalse(target.is_symlink())

    def test_duplicate_preserves_dangling_destination(self):
        source = (IOS / 'Models/IshFS.swift').read_text()
        section = source.split('static func duplicate(path: String, destination: String)', 1)[1]
        command = re.search(r'let result = await run\("(.*)"\)', section).group(1).replace('\\\"', '"')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            src = root / 'source'
            src.write_text('original')
            dest = root / 'destination'
            dest.symlink_to(root / 'missing')
            command = command.replace('\\(shellQuote(path))', shlex.quote(str(src)))
            command = command.replace('\\(shellQuote(destination))', shlex.quote(str(dest)))
            result = subprocess.run(['sh', '-c', command], capture_output=True)
            self.assertEqual(result.returncode, 17)
            self.assertTrue(dest.is_symlink())
            self.assertEqual(src.read_text(), 'original')

    def test_import_commit_rejects_dangling_destination(self):
        source = (IOS / 'Models/IshFS.swift').read_text()
        section = source.split('if replaceExisting {', 1)[1].split('let move =', 1)[0]
        command = re.findall(r'moveCommand = "(.*)"', section)[1].replace('\\\"', '"')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            temp = root / 'incoming'
            temp.write_text('imported')
            target = root / 'existing link'
            target.symlink_to(root / 'absent')
            command = command.replace('\\(target)', shlex.quote(str(target)))
            command = command.replace('\\(temp)', shlex.quote(str(temp)))
            result = subprocess.run(['sh', '-c', command], capture_output=True)
            self.assertEqual(result.returncode, 17)
            self.assertTrue(target.is_symlink())
            self.assertEqual(temp.read_text(), 'imported')

    def test_export_and_editor_failure_guards(self):
        source = (IOS / 'Models/IshFS.swift').read_text()
        export = source.split('static func copyFileToTemporaryURL', 1)[1]
        self.assertIn('.appendingPathComponent(UUID().uuidString', export)
        self.assertIn('Int64(data.count) == expectedBytes', export)
        self.assertIn('if !completed', export)
        view = (IOS / 'Views/LocalFileWorkspaceView.swift').read_text()
        editor = view.split('private struct LocalTextFileEditorView', 1)[1].split('private struct LocalFilePreviewSheet', 1)[0]
        self.assertIn('.disabled(!didLoad || isSaving)', editor)
        self.assertIn('guard didLoad, !isSaving', editor)
        self.assertIn('.interactiveDismissDisabled(hasUnsavedChanges || isSaving)', editor)

    def test_listing_round_trips_delimiter_filenames_and_directory_links(self):
        import base64
        source = (IOS / 'Models/IshFS.swift').read_text()
        section = source.split('static func listDirectory', 1)[1]
        template = section.split('let command = """', 1)[1].split('"""', 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            names = ['plain', 'tabs\there', 'line\nbreak', '.hidden', "quote's file"]
            for name in names:
                (root / name).write_text('sample')
            (root / 'broken').symlink_to(root / 'absent')
            folder = root / 'folder'
            folder.mkdir()
            (root / 'folder-link').symlink_to(folder)
            for include_hidden in (True, False):
                command = template.replace('\\(quoted)', shlex.quote(str(root)))
                command = command.replace('\\(hiddenGuard)', '' if include_hidden else 'case "$name" in .*) continue ;; esac;')
                result = subprocess.run(['sh', '-c', command], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                rows = [line.strip().split('\t') for line in result.stdout.splitlines() if line.strip()]
                decoded = {base64.b64decode(row[4]).decode(): base64.b64decode(row[5]).decode() for row in rows}
                expected = set(names + ['broken', 'folder', 'folder-link'])
                if not include_hidden:
                    expected.remove('.hidden')
                self.assertEqual(set(decoded), expected)
                for name, path in decoded.items():
                    self.assertEqual(path, str(root / name))

    def test_gzip_extract_uses_requested_destination_and_preserves_source(self):
        import gzip
        source = (IOS / 'Models/IshFS.swift').read_text()
        section = source.split('static func extractArchive', 1)[1]
        template = section.split('await run("""', 1)[1].split('""")', 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "file's data.gz"
            archive.write_bytes(gzip.compress(b'content'))
            dest = root / 'extracted folder'
            command = template.replace('\\(archive)', shlex.quote(str(archive))).replace('\\(output)', shlex.quote(str(dest)))
            result = subprocess.run(['sh', '-c', command], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((dest / "file's data").read_bytes(), b'content')
            self.assertTrue(archive.exists())
            result = subprocess.run(['sh', '-c', command], capture_output=True)
            self.assertEqual(result.returncode, 17)
