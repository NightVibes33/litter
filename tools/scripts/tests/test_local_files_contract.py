from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
VIEW = (ROOT / "apps/ios/Sources/Litter/Views/LocalFileWorkspaceView.swift").read_text()
FS = (ROOT / "apps/ios/Sources/Litter/Models/IshFS.swift").read_text()

class LocalFilesContractTests(unittest.TestCase):
    def test_move_destination_is_real_fakefs_folder_browser(self):
        self.assertIn("private struct LocalFileMoveDestinationSheet: View", VIEW)
        self.assertIn("IshFS.listDirectory(path: path, includeHidden: showHidden)", VIEW)
        self.assertIn("onMove: { destination in try await model.move(file, toDirectory: destination) }", VIEW)
        self.assertNotIn('.alert("Move Item"', VIEW)
        self.assertIn("This item is already in that folder.", VIEW)

    def test_inspector_and_preview_route_actions_after_sheet_dismissal(self):
        self.assertIn(".sheet(item: $previewTarget, onDismiss: completePreviewAction)", VIEW)
        self.assertIn(".sheet(item: $inspectorTarget, onDismiss: completeInspectorAction)", VIEW)
        self.assertIn("private func performDeferredFileAction", VIEW)
        self.assertNotIn("DispatchQueue.main.asyncAfter(deadline: .now() + 0.18)", VIEW)

    def test_branding_is_alley_cat_and_legacy_manifest_is_preserved(self):
        self.assertIn('hostTitle: String = "alleycat.local"', VIEW)
        self.assertNotIn('hostTitle: String = "litter.local"', VIEW)
        self.assertIn('entry.name == "LitterBuild.json"', VIEW)
        self.assertIn("JSONSerialization.data(withJSONObject:", VIEW)

    def test_file_actions_handle_symlinks_and_import_batching(self):
        self.assertIn("exportAsDirectory = await IshFS.isDirectory(path: entry.path)", VIEW)
        self.assertIn("func importFiles(from urls: [URL]", VIEW)
        self.assertIn("await model.importFiles(from: urls, toDirectory: destination)", VIEW)
        self.assertIn('archivePath = "/tmp/alleycat-share-', VIEW)
        self.assertIn("relocateStoredPaths(from: entry.path, to: target)", VIEW)

    def test_archive_extracts_safely_to_unique_folder(self):
        self.assertIn('".tar.gz", ".tar.xz"', VIEW)
        self.assertIn("firstAvailableName(candidates: candidates, directory: directory)", VIEW)
        self.assertIn("Extraction folder already exists", FS)
        self.assertIn("unzip -n", FS)
        self.assertNotIn("unzip -o", FS)

    def test_name_validation_and_root_navigation(self):
        self.assertIn("CharacterSet.controlCharacters.contains($0)", VIEW)
        self.assertIn('!currentPath.isEmpty && currentPath != "/"', VIEW)
        self.assertIn("if entry.kind == .file {\n            Button(\"Make Executable\"", VIEW)

if __name__ == "__main__":
    unittest.main()
