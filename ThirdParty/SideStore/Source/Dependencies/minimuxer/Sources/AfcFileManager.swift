//
//  AfcFileManager.swift
//  Minimuxer
//
//  Original Rust Implementation by @jkcoxson
//  Swift Port created by Magesh K on 02/03/26.
//

import Foundation
import RustBridge

public struct RustDirectoryEntry {
    public let path: String
    public let parent: String
    public let isFile: Bool
    public let size: UInt32?
    public let children: [RustDirectoryEntry]
}

public class AfcFileManager {
    private static func getClient() throws -> RustAfc {
        let device = try Device.getFirstDevice()
        guard let afc = RustAfc.connect(device: device.internalInstance, label: "minimuxer") else {
            throw MinimuxerError.CreateAfc
        }
        return afc
    }

    public static func remove(path: String) throws {
        let client = try getClient()
        if !client.remove(path: path) {
            throw MinimuxerError.RwAfc
        }
    }

    public static func createDirectory(path: String) throws {
        let client = try getClient()
        if !client.mkdir(path: path) {
            throw MinimuxerError.RwAfc
        }
    }

    public static func writeFile(to path: String, bytes: Data) throws {
        let client = try getClient()
        if !client.writeFile(path: path, data: bytes) {
            throw MinimuxerError.RwAfc
        }
    }

    public static func copyFileOutsideAfc(from sourcePath: String, to destPath: String) throws {
        let client = try getClient()
        let dest = destPath.hasPrefix("file://") ? String(destPath.dropFirst(7)) : destPath

        let handle = client.fileOpen(path: sourcePath, mode: "r")
        guard handle != 0 else {
            throw MinimuxerError.RwAfc
        }
        defer { client.fileClose(handle: handle) }

        // Get file size
        guard let info = client.getFileInfo(path: sourcePath),
              let sizeStr = info["st_size"],
              let size = UInt32(sizeStr) else {
            throw MinimuxerError.RwAfc
        }

        guard let data = client.fileRead(handle: handle, size: size) else {
            throw MinimuxerError.RwAfc
        }

        try data.write(to: URL(fileURLWithPath: dest))
    }

    public static func contents() -> [RustDirectoryEntry] {
        guard let client = try? getClient() else { return [] }
        return _contents(client: client, directoryPath: "/", depth: 0)
    }

    private static func _contents(client: RustAfc, directoryPath: String, depth: UInt8) -> [RustDirectoryEntry] {
        var entries: [RustDirectoryEntry] = []
        guard let dirContents = client.readDirectory(path: directoryPath) else { return entries }

        for entry in dirContents {
            if entry == "." || entry == ".." { continue }

            let fullPath = "\(directoryPath)\(entry)"
            let info = client.getFileInfo(path: fullPath)
            let isDirectory = info?["st_ifmt"] == "S_IFDIR"
            let size: UInt32? = info?["st_size"].flatMap { UInt32($0) }

            entries.append(RustDirectoryEntry(
                path: isDirectory ? "\(fullPath)/" : fullPath,
                parent: directoryPath,
                isFile: !isDirectory,
                size: size,
                children: isDirectory && depth < 3
                    ? _contents(client: client, directoryPath: fullPath, depth: depth + 1)
                    : []
            ))
        }
        return entries
    }
}
