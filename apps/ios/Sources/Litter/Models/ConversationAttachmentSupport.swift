import Foundation
import ImageIO
import UIKit

struct PreparedImageAttachment {
    let data: Data
    let mimeType: String

    var userInput: AppUserInput {
        .image(url: dataURI)
    }

    var chatImage: ChatImage {
        ChatImage(data: data, mimeType: mimeType)
    }

    private var dataURI: String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }
}

enum ConversationAttachmentSupport {
    private static let attachmentMaxPixelSize = 2_048

    static func prepareImage(_ image: UIImage) -> PreparedImageAttachment? {
        let imageForUpload = resizedImageIfNeeded(image, maxPixelSize: attachmentMaxPixelSize) ?? image
        guard let encodedImage = encodedImageData(for: imageForUpload) else { return nil }
        return PreparedImageAttachment(data: encodedImage.data, mimeType: encodedImage.mimeType)
    }

    static func loadImageFile(at url: URL) -> UIImage? {
        downsampledImage(source: CGImageSourceCreateWithURL(url as CFURL, nil), maxPixelSize: attachmentMaxPixelSize)
    }

    static func loadImageData(_ data: Data) -> UIImage? {
        downsampledImage(source: CGImageSourceCreateWithData(data as CFData, nil), maxPixelSize: attachmentMaxPixelSize)
    }

    static func buildTurnInputs(text: String, additionalInput: [AppUserInput]) -> [AppUserInput] {
        var inputs: [AppUserInput] = []
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inputs.append(.text(text: text, textElements: []))
        }
        inputs.append(contentsOf: additionalInput)
        return inputs
    }

    private static func downsampledImage(source: CGImageSource?, maxPixelSize: Int) -> UIImage? {
        guard let source else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: UIScreen.main.scale, orientation: .up)
    }

    private static func resizedImageIfNeeded(_ image: UIImage, maxPixelSize: Int) -> UIImage? {
        let maxCurrentPixels = max(image.size.width * image.scale, image.size.height * image.scale)
        guard maxCurrentPixels > CGFloat(maxPixelSize), maxCurrentPixels > 0 else { return image }

        let ratio = CGFloat(maxPixelSize) / maxCurrentPixels
        let targetSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = !image.litterHasAlpha
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private static func encodedImageData(for image: UIImage) -> (data: Data, mimeType: String)? {
        if image.litterHasAlpha, let pngData = image.pngData() {
            return (pngData, "image/png")
        }
        if let jpegData = image.jpegData(compressionQuality: 0.82) {
            return (jpegData, "image/jpeg")
        }
        if let pngData = image.pngData() {
            return (pngData, "image/png")
        }
        return nil
    }
}

private extension UIImage {
    var litterHasAlpha: Bool {
        guard let alphaInfo = cgImage?.alphaInfo else { return false }
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        default:
            return false
        }
    }
}
