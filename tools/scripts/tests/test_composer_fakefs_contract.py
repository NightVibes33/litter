from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3] / "apps/ios/Sources/Litter"
CONVERSATION = (ROOT / "Views/ConversationView.swift").read_text()
HOME = (ROOT / "Views/HomeComposerView.swift").read_text()
MODAL = (ROOT / "Views/ConversationComposerModalCoordinator.swift").read_text()
ATTACHMENT = (ROOT / "Models/ConversationAttachmentSupport.swift").read_text()
RPC = (ROOT / "Models/AppRpcParams.swift").read_text()
APP_MODEL = (ROOT / "Models/AppModel.swift").read_text()

class FakefsComposerContractTests(unittest.TestCase):
    def test_conversation_picker_imports(self):
        self.assertIn("onLoadSelectedFiles: importPickedURLs", CONVERSATION)
        self.assertIn("onLoadSelectedFiles(urls)", MODAL)
        self.assertIn("allowsMultipleSelection: true", MODAL)
    def test_conversation_drop_imports(self):
        self.assertIn(".dropDestination(for: URL.self)", CONVERSATION)
        self.assertIn("importPickedURLs(urls)", CONVERSATION)
    def test_home_picker_imports(self):
        self.assertIn("attach.importPickedURLs(urls, allowFileImport: allowFileImport, remoteServerId: remoteServerId, ssh: ssh)", HOME)
        self.assertIn("allowsMultipleSelection: true", HOME)
    def test_home_drop_imports(self):
        self.assertIn(".dropDestination(for: URL.self)", HOME)
        self.assertIn("remoteServerId: resolvedTranscriptionServerId, ssh: appModel.ssh", HOME)
    def test_both_send_paths_keep_real_fakefs_mentions(self):
        self.assertIn("buildTurnInputs(attachments: importedFiles)", CONVERSATION)
        self.assertIn("buildTurnInputs(attachments: importedFiles)", HOME)
        self.assertIn("localRuntimeFileAccessInput(attachments: importedFiles)", CONVERSATION)
        self.assertIn("localRuntimeFileAccessInput(attachments: importedFiles)", HOME)
        self.assertIn("available to your local shell tools", ATTACHMENT)
        self.assertIn("fileAttachments: fileReferences,", CONVERSATION)
        self.assertIn("fileAttachments: fileReferences,", HOME)
        self.assertIn("same iSH command service", ATTACHMENT)
        self.assertIn("IshFS.fileSize(path: path)", ATTACHMENT)
        self.assertIn("attachment, ssh: appModel.ssh, sshSessionId: sshSessionId", HOME)
        self.assertIn("attachment, ssh: appModel.ssh, sshSessionId: sshSessionId", CONVERSATION)
        self.assertIn("validateComposerAttachment(imported)", ATTACHMENT)
        self.assertIn("let result = await IshFS.run(probe)", ATTACHMENT)
        self.assertIn('composerImportDirectory = IshFS.composerAttachmentsRoot', ATTACHMENT)
        self.assertIn('path.hasPrefix("/root/.litter/attachments/")', ATTACHMENT)
        self.assertIn("private var composerFileChips", CONVERSATION)
        self.assertIn("var composerFileChips", HOME)
    def test_provider_urls_not_serialized_and_server_search_unchanged(self):
        self.assertNotIn("loadPickedFile(at:", CONVERSATION)
        self.assertNotIn("loadPickedFile(at:", HOME)
        self.assertNotIn("path: url.path", ATTACHMENT)
        self.assertIn("fileAttachments: fileReferences,", HOME)
        self.assertIn("fileAttachments: fileReferences,", CONVERSATION)
        self.assertIn("applyFileSuggestion(_ match: FileSearchResult)", CONVERSATION)
    def test_never_submit_untransferred_ios_or_fakefs_zip_to_remote(self):
        self.assertIn("validateAttachmentReferences(isLocal:", APP_MODEL)
        self.assertIn("The selected file is still in iPhone storage", RPC)
        self.assertIn("not the remote Linux workspace", RPC)
        self.assertIn("AppComposerPayload.attachmentPathIssue", CONVERSATION)
        self.assertIn("AppComposerPayload.attachmentPathIssue", HOME)
        self.assertIn("actualSize == expectedSize", ATTACHMENT)
        self.assertIn("File transfer to iSH was incomplete", ATTACHMENT)

    def test_ssh_zip_stream_is_verified_before_agent_receives_path(self):
        self.assertIn("importComposerSSHURL", CONVERSATION)
        self.assertIn("importComposerSSHURL", HOME)
        self.assertIn("ssh.sshAttachmentBegin", ATTACHMENT)
        self.assertIn("ssh.sshAttachmentAppend", ATTACHMENT)
        self.assertIn("ssh.sshAttachmentVerify", ATTACHMENT)
        self.assertIn("ssh.sshAttachmentCancel", ATTACHMENT)
        self.assertIn("chunk.base64EncodedString()", ATTACHMENT)
        self.assertIn("remoteByteCount", ATTACHMENT)
        self.assertIn("attachment.remotePath ?? attachment.fakefsPath", ATTACHMENT)
        self.assertIn("SshSessionStore.shared.sessionId", CONVERSATION)
        self.assertIn("SshSessionStore.shared.sessionId", HOME)

    def test_import_failure_keeps_draft_and_blocks_inflight_submission(self):
        self.assertIn("pendingFileImports += 1", CONVERSATION)
        self.assertIn("pendingFileImports += 1", HOME)
        self.assertIn("guard pendingFileImports == 0", CONVERSATION)
        self.assertIn("guard attach.pendingFileImports == 0", HOME)
        self.assertIn("slashErrorMessage = \"Could not attach", CONVERSATION)
        self.assertIn('importError = "Could not attach', HOME)
        self.assertIn("guard !preparingFileSend", CONVERSATION)
        self.assertIn("guard !isPreparingSend", HOME)
        self.assertIn("appModel.isLocalServer", CONVERSATION)
        self.assertIn("appModel.isLocalServer", HOME)
        self.assertIn("fileImportGeneration", CONVERSATION)
        self.assertIn("importing", HOME.lower())
        self.assertIn("importing", CONVERSATION.lower())

if __name__ == "__main__":
    unittest.main()
