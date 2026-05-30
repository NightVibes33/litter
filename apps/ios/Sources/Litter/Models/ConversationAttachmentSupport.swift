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
    static let oversizedPasteCharacterLimit = 12_000
    static let oversizedPasteByteLimit = 48_000
    private static let oversizedPastePreviewLimit = 900

    static func shouldExternalizeComposerText(_ text: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return text.count > oversizedPasteCharacterLimit || Data(text.utf8).count > oversizedPasteByteLimit
    }

    static func oversizedPastePlaceholder(fileName: String, originalCharacterCount: Int, text: String) -> String {
        """
        Attached oversized paste as `\(fileName)`.

        Preview:
        \(previewText(text))

        Original length: \(originalCharacterCount) characters.
        """
    }

    static func truncatedComposerPlaceholder(for text: String) -> String {
        """
        [Oversized paste truncated from \(text.count) characters]

        \(previewText(text))
        """
    }

    static func importPastedTextToFakeFS(text: String, destinationDirectory: String) async throws -> ConversationAttachment {
        let directory = normalizedFakefsDirectory(destinationDirectory)
        try await IshFS.createDirectoryIfNeeded(path: directory)
        let preferredName = "pasted-text-\(Int(Date().timeIntervalSince1970)).txt"
        let targetName = try await availableImportName(preferredName: preferredName, directory: directory)
        let targetPath = fakefsJoin(directory, targetName)
        try await IshFS.writeTextFile(path: targetPath, text: text)
        let byteCount = Int64(Data(text.utf8).count)
        return ConversationAttachment(
            kind: .file,
            displayName: targetName,
            detail: "pasted text / \(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))",
            fakefsPath: targetPath
        )
    }

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

    static func attachment(from searchResult: FileSearchResult) -> ConversationAttachment? {
        let isDirectory: Bool
        switch searchResult.matchType {
        case .directory:
            isDirectory = true
        case .file:
            isDirectory = false
        }
        return attachmentForLinkedFile(
            path: searchResult.path,
            displayName: searchResult.fileName,
            isDirectory: isDirectory,
            sourceRoot: searchResult.root
        )
    }

    static func attachmentForLinkedFile(
        path rawPath: String,
        displayName rawDisplayName: String? = nil,
        isDirectory: Bool = false,
        sourceRoot rawSourceRoot: String? = nil
    ) -> ConversationAttachment? {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }

        let trimmedDisplayName = rawDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = nonEmptyString(trimmedDisplayName) ?? displayName(forPath: path)
        let kind: ConversationAttachment.Kind
        if isDirectory {
            kind = .folder
        } else {
            kind = isArchiveName(displayName) || isArchiveName(path) ? .archive : .file
        }
        let trimmedSourceRoot = rawSourceRoot?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceRoot = nonEmptyString(trimmedSourceRoot)
        return ConversationAttachment(
            kind: kind,
            displayName: displayName,
            detail: sourceRoot.map { "linked from \($0)" } ?? "linked computer file",
            fakefsPath: path
        )
    }

    static func buildLinkedTurnInputs(text: String) async -> [AppUserInput] {
        var inputs: [AppUserInput] = []
        for path in linkedFakefsPaths(in: text) {
            if isLikelyImagePath(path), let imageInput = await linkedImageInput(path: path) {
                inputs.append(imageInput)
            } else {
                inputs.append(.mention(name: displayName(for: path), path: path))
            }
        }
        return inputs
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func previewText(_ text: String, maxCharacters: Int = oversizedPastePreviewLimit) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxCharacters)
        return String(trimmed[..<end]) + "\n..."
    }

    static func linkedFakefsPaths(in text: String) -> [String] {
        var paths: [String] = []
        var seen = Set<String>()

        func appendCandidate(_ raw: String) {
            guard let path = normalizeLinkedFakefsPath(raw), !seen.contains(path) else { return }
            seen.insert(path)
            paths.append(path)
        }

        regexMatches(in: text, pattern: #"\[[^\]\n]{0,180}\]\(([^)\n]+)\)"#, captureGroup: 1)
            .forEach(appendCandidate)
        regexMatches(in: text, pattern: #"(?:litter-file|ish-file|file)://[^\s<>)\]]+"#, captureGroup: 0)
            .forEach(appendCandidate)
        regexMatches(in: text, pattern: #"(^|[\s(])((?:~/[^\s<>)\]]+)|/(?:root|mnt|tmp|etc|usr/local/bin)(?:/[^\s<>)\]]*)?)"#, captureGroup: 2)
            .forEach(appendCandidate)

        return paths
    }

    static func normalizeLinkedFakefsPath(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        while let last = value.last, ".,;:".contains(last) {
            value.removeLast()
        }

        if let url = URL(string: value), let scheme = url.scheme?.lowercased() {
            switch scheme {
            case "litter-file", "ish-file":
                value = pathForCustomFileScheme(url)
            case "file":
                value = url.path
            default:
                return nil
            }
        } else if value.hasPrefix("file://") {
            value = String(value.dropFirst("file://".count))
        }

        value = value.removingPercentEncoding ?? value
        if value == "~" {
            value = HomeAnchor.path
        } else if value.hasPrefix("~/") {
            value = HomeAnchor.path + String(value.dropFirst())
        }
        guard value.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: value).standardizedFileURL.path
    }

    private static func linkedImageInput(path: String) async -> AppUserInput? {
        let data: Data?
        if FileManager.default.fileExists(atPath: path) {
            data = try? Data(contentsOf: URL(fileURLWithPath: path))
        } else {
            data = try? await IshFS.readFileData(path: path, maxBytes: 32_000_000)
        }
        guard let data,
              let image = loadImageData(data),
              let prepared = prepareImage(image) else { return nil }
        return prepared.userInput
    }

    private static func isLikelyImagePath(_ path: String) -> Bool {
        isLikelyImage(URL(fileURLWithPath: path))
    }

    private static func displayName(for path: String) -> String {
        displayName(forPath: path)
    }

    private static func displayName(forPath path: String) -> String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let name = normalized.split(separator: "/").last.map(String.init) ?? ""
        return name.isEmpty ? path : name
    }

    private static func pathForCustomFileScheme(_ url: URL) -> String {
        let path = url.path
        guard let host = url.host, !host.isEmpty else { return path }
        if path.isEmpty || path == "/" { return "/\(host)" }
        return "/\(host)\(path)"
    }

    private static func regexMatches(in text: String, pattern: String, captureGroup: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > captureGroup,
                  let matchRange = Range(match.range(at: captureGroup), in: text) else { return nil }
            return String(text[matchRange])
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

    static func loadPickedFile(at url: URL) -> PickedComposerFile? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        if isSupportedImageFile(url),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            return .image(image)
        }

        return .file(
            ComposerFileAttachment(
                label: fileLabel(for: url),
                path: url.path
            )
        )
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
        let itemURLs = try enumeratedFileURLs(in: sourceURL)

        for itemURL in itemURLs {
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

    private static func enumeratedFileURLs(in sourceURL: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [],
            errorHandler: nil
        ) else {
            throw NSError(domain: "ConversationAttachmentSupport", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not enumerate \(sourceURL.lastPathComponent)."])
        }
        return enumerator.compactMap { $0 as? URL }
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

    private static func isSupportedImageFile(_ url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "webp"].contains(pathExtension)
    }

    private static func fileLabel(for url: URL) -> String {
        let baseName = url.deletingPathExtension().lastPathComponent
        if !baseName.isEmpty {
            return baseName
        }
        return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }
}

enum PickedComposerFile {
    case image(UIImage)
    case file(ComposerFileAttachment)
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
