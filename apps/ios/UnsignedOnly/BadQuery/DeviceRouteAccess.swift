import Darwin
import Foundation

enum DeviceRouteAccessError: LocalizedError {
    case invalidPath(String)
    case unavailable(Int64, String)
    case listFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            return "Device route must be an absolute iOS path: \(path)"
        case .unavailable(let code, let path):
            let reason: String
            switch code {
            case -255: reason = "path is not absolute"
            case -254: reason = "path does not exist"
            case -1: reason = "required container-manager or sandbox symbols could not be resolved"
            case -2: reason = "container query could not be created"
            case -3: reason = "path is outside the reachable container-manager route"
            case -4: reason = "the kernel refused the sandbox extension"
            case -5: reason = "path traversal query construction failed"
            default: reason = "sandbox extension request failed with code \(code)"
            }
            return "Device route access failed for \(path): \(reason)."
        case .listFailed(let path):
            return "Could not enumerate device route: \(path)"
        }
    }
}

enum DeviceRouteAccess {
    private static let defaultReadLimit = 256_000
    private static let defaultMaxInode: Int64 = 1_000_000
    private static let maxListedEntries = 2_000

    static func readText(path rawPath: String, maxBytes: Int = defaultReadLimit) throws -> String {
        let path = try normalizedAbsolutePath(rawPath)
        return try withExtension(path: path, create: false) {
            let url = URL(fileURLWithPath: path)
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            let data = try handle.read(upToCount: maxBytes + 1) ?? Data()
            let truncated = data.count > maxBytes
            let visible = truncated ? data.prefix(maxBytes) : data[...]
            var text = String(decoding: visible, as: UTF8.self)
            if truncated {
                text += "\n… device file truncated after \(maxBytes) bytes …"
            }
            return text
        }
    }

    static func writeText(path rawPath: String, text: String) throws -> Int {
        let path = try normalizedAbsolutePath(rawPath)
        let fileManager = FileManager.default
        let create = !fileManager.fileExists(atPath: path)
        let parent = (path as NSString).deletingLastPathComponent

        var parentHandle: Int64?
        if create, !parent.isEmpty, parent != path {
            parentHandle = try? acquire(path: parent, create: false)
        }
        defer {
            if let parentHandle { bad_query_release(parentHandle) }
        }

        return try withExtension(path: path, create: create) {
            let data = Data(text.utf8)
            try data.write(to: URL(fileURLWithPath: path), options: [])
            return data.count
        }
    }

    static func listDirectory(path rawPath: String, maxInode: Int64 = defaultMaxInode) throws -> String {
        let path = try normalizedAbsolutePath(rawPath)
        return try withExtension(path: path, create: false) {
            do {
                let names = try FileManager.default.contentsOfDirectory(atPath: path).sorted()
                let shown = names.prefix(maxListedEntries)
                var lines: [String] = []
                lines.reserveCapacity(shown.count + 1)

                for name in shown {
                    let child = (path as NSString).appendingPathComponent(name)
                    var isDirectory: ObjCBool = false
                    let exists = FileManager.default.fileExists(atPath: child, isDirectory: &isDirectory)
                    let suffix = exists && isDirectory.boolValue ? "/" : ""
                    lines.append(name + suffix)
                }

                if names.count > maxListedEntries {
                    lines.append("… \(names.count - maxListedEntries) more entries omitted …")
                }
                return lines.isEmpty ? "(empty directory)" : lines.joined(separator: "\n")
            } catch {
                var cPath = Array(path.utf8CString)
                guard let raw = cPath.withUnsafeMutableBufferPointer({ buffer in
                    bad_query_list(buffer.baseAddress, maxInode)
                }) else {
                    throw DeviceRouteAccessError.listFailed(path)
                }
                defer { free(raw) }

                let output = String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !output.isEmpty else {
                    throw DeviceRouteAccessError.listFailed(path)
                }
                return output
            }
        }
    }

    private static func normalizedAbsolutePath(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else {
            throw DeviceRouteAccessError.invalidPath(trimmed)
        }
        return (trimmed as NSString).standardizingPath
    }

    private static func acquire(path: String, create: Bool) throws -> Int64 {
        var cPath = Array(path.utf8CString)
        let handle = cPath.withUnsafeMutableBufferPointer { buffer in
            bad_query(buffer.baseAddress, create, nil, false)
        }
        guard handle >= 0 else {
            throw DeviceRouteAccessError.unavailable(handle, path)
        }
        return handle
    }

    private static func withExtension<T>(
        path: String,
        create: Bool,
        operation: () throws -> T
    ) throws -> T {
        let handle = try acquire(path: path, create: create)
        defer { bad_query_release(handle) }
        return try operation()
    }
}
