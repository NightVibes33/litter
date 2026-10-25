import UIKit
import XCTest
@testable import Litter

final class ConversationAttachmentSupportTests: XCTestCase {
    func testBuildTurnInputsOmitsWhitespaceOnlyTextAndKeepsAttachmentInput() {
        let attachment = AppUserInput.image(url: "data:image/png;base64,abc")

        let inputs = ConversationAttachmentSupport.buildTurnInputs(
            text: "   \n",
            additionalInput: [attachment]
        )

        XCTAssertEqual(inputs.count, 1)
        guard case .image(let url)? = inputs.first else {
            return XCTFail("Expected image input")
        }
        XCTAssertEqual(url, "data:image/png;base64,abc")
    }

    func testLinkedFakefsPathsParsesMarkdownAndRawLinks() {
        let text = "Open [IPA](litter-file:///root/.litter/builds/App%20One.ipa), see /root/litter/main.swift and <ish-file://root/projects/Demo/README.md>."

        let paths = ConversationAttachmentSupport.linkedFakefsPaths(in: text)

        XCTAssertEqual(paths, [
            "/root/.litter/builds/App One.ipa",
            "/root/projects/Demo/README.md",
            "/root/litter/main.swift"
        ])
    }

    func testNormalizeLinkedFakefsPathSupportsTildeAndCustomHostForm() {
        XCTAssertEqual(ConversationAttachmentSupport.normalizeLinkedFakefsPath("~/hello.swift"), "/root/hello.swift")
        XCTAssertEqual(ConversationAttachmentSupport.normalizeLinkedFakefsPath("litter-file://root/tmp/test.png"), "/root/tmp/test.png")
        XCTAssertEqual(ConversationAttachmentSupport.normalizeLinkedFakefsPath("alleycat-file://root/tmp/test.png"), "/root/tmp/test.png")
        XCTAssertEqual(ConversationAttachmentSupport.linkedFakefsPaths(in: "[App](alleycat-file:///root/alley-cat/My%20App.ipa)"), ["/root/alley-cat/My App.ipa"])
    }

    func testOversizedPasteDetectionUsesCharacterAndByteLimits() {
        XCTAssertFalse(ConversationAttachmentSupport.shouldExternalizeComposerText("short paste"))

        let characterHeavy = String(repeating: "a", count: ConversationAttachmentSupport.oversizedPasteCharacterLimit + 1)
        XCTAssertTrue(ConversationAttachmentSupport.shouldExternalizeComposerText(characterHeavy))

        let byteHeavy = String(repeating: "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}", count: 2_000)
        XCTAssertLessThan(byteHeavy.count, ConversationAttachmentSupport.oversizedPasteCharacterLimit)
        XCTAssertTrue(ConversationAttachmentSupport.shouldExternalizeComposerText(byteHeavy))
    }

    func testOversizedPastePlaceholderKeepsPreviewShort() {
        let paste = String(repeating: "0123456789", count: 1_300)

        let placeholder = ConversationAttachmentSupport.oversizedPastePlaceholder(
            fileName: "pasted-text-1.txt",
            originalCharacterCount: paste.count,
            text: paste
        )

        XCTAssertTrue(placeholder.contains("pasted-text-1.txt"))
        XCTAssertTrue(placeholder.contains("Original length: \(paste.count) characters."))
        XCTAssertLessThan(placeholder.count, 1_200)
    }

    func testLinkedComputerFileAttachmentKeepsWindowsPathAsMentionPath() throws {
        let attachment = try XCTUnwrap(
            ConversationAttachmentSupport.attachmentForLinkedFile(
                path: #"C:\Users\bobby\Downloads\report.zip"#,
                sourceRoot: #"C:\Users\bobby\Downloads"#
            )
        )

        XCTAssertEqual(attachment.kind, .archive)
        XCTAssertEqual(attachment.displayName, "report.zip")
        XCTAssertEqual(attachment.fakefsPath, #"C:\Users\bobby\Downloads\report.zip"#)

        let inputs = ConversationAttachmentSupport.buildTurnInputs(attachments: [attachment])
        guard case .mention(let name, let path)? = inputs.first else {
            return XCTFail("Expected mention input")
        }
        XCTAssertEqual(name, "report.zip")
        XCTAssertEqual(path, #"C:\Users\bobby\Downloads\report.zip"#)
    }

    func testLinkedComputerFolderAttachmentUsesFolderKind() throws {
        let attachment = try XCTUnwrap(
            ConversationAttachmentSupport.attachmentForLinkedFile(
                path: "/Users/bobby/Projects/litter",
                displayName: "litter",
                isDirectory: true,
                sourceRoot: "/Users/bobby/Projects"
            )
        )

        XCTAssertEqual(attachment.kind, .folder)
        XCTAssertEqual(attachment.displayName, "litter")
        XCTAssertEqual(attachment.fakefsPath, "/Users/bobby/Projects/litter")
    }

    func testPreparedAttachmentCreatesImageUserInput() throws {
        let attachment = try XCTUnwrap(
            PreparedImageAttachment(
                data: Data([0x01, 0x02, 0x03]),
                mimeType: "image/png"
            ) as PreparedImageAttachment?
        )

        guard case .image(let url) = attachment.userInput else {
            return XCTFail("Expected image user input")
        }

        XCTAssertEqual(url, "data:image/png;base64,AQID")
    }

    func testPrepareImageUsesPNGWhenImageHasTransparency() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 1, y: 1, width: 2, height: 2))
        }

        let attachment = ConversationAttachmentSupport.prepareImage(image)

        XCTAssertEqual(attachment?.mimeType, "image/png")
        XCTAssertNotNil(attachment?.data)
    }

    func testPrepareImageUsesJPEGWhenImageIsOpaque() {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: format).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }

        let attachment = ConversationAttachmentSupport.prepareImage(image)

        XCTAssertEqual(attachment?.mimeType, "image/jpeg")
        XCTAssertNotNil(attachment?.data)
    }

    func testUnreadableImagePathDoesNotFallBackToFileAttachment() {
        let url = URL(fileURLWithPath: "/tmp/litter-missing-image.jpeg")

        let picked = ConversationAttachmentSupport.loadPickedFile(at: url)

        XCTAssertNil(picked)
    }

    func testPhotosLibraryInternalPathDoesNotBecomeFileAttachment() {
        let url = URL(
            fileURLWithPath: "/Users/example/Pictures/Photos Library.photoslibrary/resources/derivatives/4/photo.txt"
        )

        let picked = ConversationAttachmentSupport.loadPickedFile(at: url)

        XCTAssertNil(picked)
    }

    func testPhotosLibraryInternalPathDetection() {
        XCTAssertTrue(
            ConversationAttachmentSupport.isPhotosLibraryInternalPath(
                "/Users/example/Pictures/Photos Library.photoslibrary/resources/derivatives/4/photo.jpeg"
            )
        )
        XCTAssertFalse(
            ConversationAttachmentSupport.isPhotosLibraryInternalPath(
                "/Users/example/Desktop/photo.jpeg"
            )
        )
    }

    func testNonImageProviderURLIsNotTurnAttachment() {
        let url = URL(fileURLWithPath: "/private/var/mobile/Containers/Shared/AppGroup/provider-secret.txt")
        // The synchronous, image-only legacy helper must never expose
        // a File Provider URL as a ComposerFileAttachment.
        XCTAssertNil(ConversationAttachmentSupport.loadPickedFile(at: url))
    }

    func testCanonicalAttachmentFolderUsesAlleyCatFilesystem() {
        XCTAssertEqual(ConversationAttachmentSupport.composerImportDirectory, "/root/.alleycat/attachments")
    }

    func testImportedComposerChipUsesFakefsPath() {
        let imported = ConversationAttachment(
            kind: .file,
            displayName: "report.txt",
            detail: "imported",
            fakefsPath: "/root/.alleycat/attachments/report.txt"
        )
        let chip = ConversationAttachmentSupport.composerFileChip(for: imported)
        XCTAssertEqual(chip?.path, "/root/.alleycat/attachments/report.txt")
        XCTAssertEqual(chip?.label, "report.txt")
    }

    func testImportedFileUsesExactRuntimePathInSubmittedTurn() {
        let providerURL = "/private/var/mobile/Containers/Shared/AppGroup/report.txt"
        let imported = ConversationAttachment(
            kind: .file,
            displayName: "report.txt",
            detail: "imported",
            fakefsPath: "/root/.alleycat/attachments/report.txt"
        )
        let additional = ConversationAttachmentSupport.buildTurnInputs(attachments: [imported])
        let payload = AppComposerPayload(
            text: "Inspect the attachment",
            additionalInputs: additional,
            fileAttachments: [],
            approvalPolicy: nil,
            sandboxPolicy: nil,
            model: nil,
            effort: nil,
            serviceTier: nil
        )
        let request = payload.turnStartRequest(threadId: "test-thread")
        XCTAssertEqual(request.input.count, 2)
        guard case .mention(let name, let path) = request.input[1] else {
            return XCTFail("Expected an iSH file mention in the submitted request")
        }
        XCTAssertEqual(name, "report.txt")
        XCTAssertEqual(path, "/root/.alleycat/attachments/report.txt")
        XCTAssertNotEqual(path, providerURL)
        guard case .text(let prompt, _) = request.input[0] else {
            return XCTFail("Expected user draft as first request input")
        }
        XCTAssertEqual(prompt, "Inspect the attachment")
        XCTAssertFalse(prompt.contains(providerURL))
    }

    func testImportedZipHasVerifiedLinuxPathInVisibleRequest() {
        let imported = ConversationAttachment(
            kind: .archive,
            displayName: "Game Assets.zip",
            detail: "imported into iSH",
            fakefsPath: "/root/.alleycat/attachments/Game Assets.zip"
        )
        let chip = ConversationAttachmentSupport.composerFileChip(for: imported)
        XCTAssertNotNil(chip)
        let payload = AppComposerPayload(
            text: "Inspect the ZIP",
            additionalInputs: ConversationAttachmentSupport.buildTurnInputs(attachments: [imported]),
            fileAttachments: [chip!],
            approvalPolicy: nil, sandboxPolicy: nil, model: nil, effort: nil, serviceTier: nil
        )
        let request = payload.turnStartRequest(threadId: "local-thread")
        guard case .text(let text, _) = request.input.first else {
            return XCTFail("Expected the iSH file context in the text input")
        }
        XCTAssertTrue(text.contains("## Game Assets.zip: /root/.alleycat/attachments/Game Assets.zip"))
        XCTAssertFalse(text.contains("/private/var/mobile/"))
        guard case .mention(let name, let path) = request.input.last else {
            return XCTFail("Expected a file mention alongside the visible path")
        }
        XCTAssertEqual(name, "Game Assets.zip")
        XCTAssertEqual(path, "/root/.alleycat/attachments/Game Assets.zip")
    }

    func testImportedFolderAndArchiveKeepRuntimePaths() {
        let files = [
            ConversationAttachment(kind: .folder, displayName: "Project", detail: "", fakefsPath: "/root/.alleycat/attachments/Project"),
            ConversationAttachment(kind: .archive, displayName: "Project.zip", detail: "", fakefsPath: "/root/.alleycat/attachments/Project.zip")
        ]
        let inputs = ConversationAttachmentSupport.buildTurnInputs(attachments: files)
        XCTAssertEqual(inputs.count, 2)
        guard case .mention(_, let folderPath) = inputs[0],
              case .mention(_, let archivePath) = inputs[1] else {
            return XCTFail("Expected directory and archive file mentions")
        }
        XCTAssertEqual(folderPath, "/root/.alleycat/attachments/Project")
        XCTAssertEqual(archivePath, "/root/.alleycat/attachments/Project.zip")
    }

    func testProviderURLIsRejectedBeforeRemoteTurn() {
        let originalURL = "/private/var/mobile/Containers/Shared/AppGroup/sample.zip"
        let payload = AppComposerPayload(
            text: "Inspect this ZIP",
            additionalInputs: [],
            fileAttachments: [ComposerFileAttachment(label: "sample.zip", path: originalURL)],
            approvalPolicy: nil, sandboxPolicy: nil, model: nil, effort: nil, serviceTier: nil
        )
        XCTAssertThrowsError(try payload.validateAttachmentReferences(isLocal: false)) { error in
            XCTAssertTrue(error.localizedDescription.contains("iPhone storage"))
        }
    }

    func testDeviceFakefsPathIsRejectedForRemoteAgent() {
        let payload = AppComposerPayload(
            text: "Open ZIP",
            additionalInputs: [.mention(name: "sample.zip", path: "/root/.alleycat/attachments/sample.zip")],
            fileAttachments: [],
            approvalPolicy: nil, sandboxPolicy: nil, model: nil, effort: nil, serviceTier: nil
        )
        XCTAssertThrowsError(try payload.validateAttachmentReferences(isLocal: false)) { error in
            XCTAssertTrue(error.localizedDescription.contains("remote Linux workspace"))
        }
        XCTAssertNoThrow(try payload.validateAttachmentReferences(isLocal: true))
    }

    func testRemoteFileSearchPathStaysValid() {
        let payload = AppComposerPayload(
            text: "Read this file",
            additionalInputs: [],
            fileAttachments: [ComposerFileAttachment(label: "sample.zip", path: "/home/agent/work/project/sample.zip")],
            approvalPolicy: nil, sandboxPolicy: nil, model: nil, effort: nil, serviceTier: nil
        )
        XCTAssertNoThrow(try payload.validateAttachmentReferences(isLocal: false))
    }

    func testInvalidImportedPathIsRejectedBeforeSending() async {
        let sourceURLAttachment = ConversationAttachment(
            kind: .file,
            displayName: "secret.txt",
            detail: "",
            fakefsPath: "/private/var/mobile/Containers/Shared/secret.txt"
        )
        do {
            try await ConversationAttachmentSupport.validateComposerAttachment(sourceURLAttachment)
            XCTFail("Provider path was accepted as an iSH attachment")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("missing from iSH"))
        }
    }
}
