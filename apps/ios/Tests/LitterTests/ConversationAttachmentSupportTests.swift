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
}
