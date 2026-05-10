import Foundation
import ImageIO
import UIKit


struct ConversationAttachment: Identifiable {
    enum Kind: String {
        case image
        case file
        case folder
        case archive

        var iconName: String {
            switch self {
            case .image: return "photo"
            case .file: return "doc.text"
            case .folder: return "folder.fill"
            case .archive: return "archivebox.fill"
            }
        }

        var displayName: String {
            switch self {
            case .image: return "Image"
            case .file: return "File"
            case .folder: return "Folder"
            case .archive: return "Archive"
            }
        }
    }

    let id: UUID
    var kind: Kind
    var displayName: String
    var detail: String
    var image: UIImage?
    var fakefsPath: String?

    init(
        id: UUID = UUID(),
        kind: Kind,
        displayName: String,
        detail: String,
        image: UIImage? = nil,
        fakefsPath: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.detail = detail
        self.image = image
        self.fakefsPath = fakefsPath
    }
}

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


    static func imageAttachment(_ image: UIImage, name: String = "Image") -> ConversationAttachment? {
        guard let prepared = prepareImage(image),
              let preview = loadImageData(prepared.data) ?? UIImage(data: prepared.data) else { return nil }
        return ConversationAttachment(
            kind: .image,
            displayName: name,
            detail: prepared.mimeType,
            image: preview
        )
    }

    static func buildTurnInputs(attachments: [ConversationAttachment]) -> [AppUserInput] {
        attachments.compactMap { attachment in
            if let image = attachment.image {
                return prepareImage(image)?.userInput
            }
            guard let path = attachment.fakefsPath?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty else { return nil }
            return .mention(name: attachment.displayName, path: path)
        }
    }

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


    static func importURLToFakeFS(url: URL, destinationDirectory: String, treatImagesAsFiles: Bool = false) async throws -> ConversationAttachment {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing { url.stopAccessingSecurityScopedResource() }
        }

        if !treatImagesAsFiles, isLikelyImage(url), let image = loadImageFile(at: url),
           let attachment = imageAttachment(image, name: url.lastPathComponent) {
            return attachment
        }

        let directory = normalizedFakefsDirectory(destinationDirectory)
        try await IshFS.createDirectoryIfNeeded(path: directory)
        let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        let isDirectory = resourceValues.isDirectory == true
        let targetName = try await availableImportName(preferredName: url.lastPathComponent, directory: directory)
        let targetPath = fakefsJoin(directory, targetName)

        if isDirectory {
            try await copyDirectoryToFakeFS(from: url, to: targetPath)
            return ConversationAttachment(
                kind: .folder,
                displayName: targetName,
                detail: "folder imported to \(targetPath)",
                fakefsPath: targetPath
            )
        }

        try await IshFS.writeFile(path: targetPath, sourceURL: url, replaceExisting: false)
        let size = Int64(resourceValues.fileSize ?? 0)
        let kind: ConversationAttachment.Kind = isArchiveName(targetName) ? .archive : .file
        return ConversationAttachment(
            kind: kind,
            displayName: targetName,
            detail: size > 0 ? ByteCountFormatter.string(fromByteCount: size, countStyle: .file) : "imported to \(targetPath)",
            fakefsPath: targetPath
        )
    }

    private static func normalizedFakefsDirectory(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostPrefixes = ["/var/", "/private/", "/Users/", "/Library/", "/System/", "/Applications/"]
        guard trimmed.hasPrefix("/"), !hostPrefixes.contains(where: { trimmed.hasPrefix($0) }) else {
            return HomeAnchor.path
        }
        return trimmed == "/" ? HomeAnchor.path : trimmed
    }

    private static func availableImportName(preferredName: String, directory: String) async throws -> String {
        let cleaned = sanitizedFileName(preferredName)
        let nsName = cleaned as NSString
        let stem = nsName.deletingPathExtension.isEmpty ? cleaned : nsName.deletingPathExtension
        let ext = nsName.pathExtension
        for index in 0..<100 {
            let candidate: String
            if index == 0 {
                candidate = cleaned
            } else if ext.isEmpty {
                candidate = "\(stem) \(index + 1)"
            } else {
                candidate = "\(stem) \(index + 1).\(ext)"
            }
            if !(await IshFS.exists(path: fakefsJoin(directory, candidate))) {
                return candidate
            }
        }
        throw NSError(domain: "ConversationAttachmentSupport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not find a free import name in \(directory)."])
    }

    private static func copyDirectoryToFakeFS(from sourceURL: URL, to targetPath: String) async throws {
        try await IshFS.createDirectoryIfNeeded(path: targetPath)
        guard let enumerator = FileManager.default.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [],
            errorHandler: nil
        ) else {
            throw NSError(domain: "ConversationAttachmentSupport", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not enumerate \(sourceURL.lastPathComponent)."])
        }

        for case let itemURL as URL in enumerator {
            let relative = relativePath(for: itemURL, root: sourceURL)
            guard !relative.isEmpty else { continue }
            let destination = fakefsJoin(targetPath, relative)
            let values = try itemURL.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                try await IshFS.createDirectoryIfNeeded(path: destination)
            } else {
                try await IshFS.createDirectoryIfNeeded(path: parentFakefsPath(destination))
                try await IshFS.writeFile(path: destination, sourceURL: itemURL, replaceExisting: false)
            }
        }
    }

    private static func relativePath(for itemURL: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let itemPath = itemURL.standardizedFileURL.path
        guard itemPath.hasPrefix(rootPath) else { return itemURL.lastPathComponent }
        let dropCount = rootPath.hasSuffix("/") ? rootPath.count : rootPath.count + 1
        guard itemPath.count >= dropCount else { return "" }
        return String(itemPath.dropFirst(dropCount))
            .split(separator: "/")
            .map { sanitizedFileName(String($0)) }
            .joined(separator: "/")
    }

    private static func fakefsJoin(_ directory: String, _ name: String) -> String {
        let dir = directory.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = name.split(separator: "/").map { sanitizedFileName(String($0)) }.joined(separator: "/")
        return "/\(dir)/\(suffix)"
    }

    private static func parentFakefsPath(_ path: String) -> String {
        let nsPath = path as NSString
        let parent = nsPath.deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }

    private static func sanitizedFileName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "Imported Item" : trimmed
        let replaced = fallback
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        return (replaced == "." || replaced == "..") ? "Imported Item" : replaced
    }

    static func isArchiveName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".zip")
            || lower.hasSuffix(".rar")
            || lower.hasSuffix(".7z")
            || lower.hasSuffix(".tar")
            || lower.hasSuffix(".tar.gz")
            || lower.hasSuffix(".tgz")
            || lower.hasSuffix(".tar.xz")
            || lower.hasSuffix(".txz")
            || lower.hasSuffix(".gz")
            || lower.hasSuffix(".xz")
    }

    static func isLikelyImage(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tiff", "bmp":
            return true
        default:
            return false
        }
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
