import Foundation

/// Thin Swift wrapper over UniFFI `ishRun` for filesystem operations that
/// the iOS-side `FileManager` can't do — the iSH fakefs is invisible to
/// host iOS APIs, so anything that needs to enumerate or mutate paths
/// inside the kernel's view (e.g. `/root`, `/etc`, `/usr`) has to go
/// through the persistent shell.
///
/// Keep this surface tiny. Most product logic should still happen Rust-side
/// via the exec hook — this is only for UI that has to read fakefs state
/// directly (the directory picker, primarily).
enum IshFS {
    struct Result {
        let exitCode: Int32
        let output: String
    }

    /// POSIX single-quote a string for safe interpolation into a shell
    /// command: `'x'` stays `'x'`, `x's` becomes `'x'\''s'`.
    static func shellQuote(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    /// Run `cmd` through the persistent iSH shell. `ishRun` is thread-safe
    /// but serializes internally, so we hop to a background task to avoid
    /// blocking the caller (typically a SwiftUI MainActor path).
    static func run(_ cmd: String, cwd: String? = nil) async -> Result {
        await Task.detached(priority: .userInitiated) {
            let res = ishRun(cmd: cmd, cwd: cwd ?? "")
            let output = String(data: res.output, encoding: .utf8) ?? ""
            return Result(exitCode: res.exitCode, output: output)
        }.value
    }

    static func listDirectory(path: String, includeHidden: Bool) async throws -> [LocalFileEntry] {
        let quoted = shellQuote(path)
        let hiddenGuard = includeHidden ? "" : "case \"$name\" in .*) continue ;; esac;"
        let command = """
        dir=\(quoted); [ -d "$dir" ] || exit 2; for p in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do [ -e "$p" ] || continue; name=${p##*/}; \(hiddenGuard) if [ -d "$p" ]; then printf 'd\t0\t%s\t%s\n' "$name" "$p"; else size=$(wc -c < "$p" 2>/dev/null || echo 0); printf 'f\t%s\t%s\t%s\n' "$size" "$name" "$p"; fi; done | sort -f -k3
        """
        let result = await run(command)
        guard result.exitCode == 0 else { throw error("Could not list \(path)", result: result) }
        return result.output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 4 else { return nil }
            return LocalFileEntry(
                kind: parts[0] == "d" ? .directory : .file,
                name: parts[2],
                path: parts[3],
                size: Int64(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            )
        }
    }

    static func readTextFile(path: String, maxBytes: Int64) async throws -> String {
        let sizeResult = await run("wc -c < \(shellQuote(path)) 2>/dev/null || exit 2")
        guard sizeResult.exitCode == 0 else { throw error("Could not read \(path)", result: sizeResult) }
        let size = Int64(sizeResult.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        guard size <= maxBytes else {
            throw NSError(domain: "IshFS", code: 1, userInfo: [NSLocalizedDescriptionKey: "File is too large for the built-in text editor."])
        }
        let result = await run("cat \(shellQuote(path))")
        guard result.exitCode == 0 else { throw error("Could not read \(path)", result: result) }
        return result.output
    }

    static func writeTextFile(path: String, text: String) async throws {
        try await writeFile(path: path, data: Data(text.utf8), replaceExisting: true)
    }

    static func writeFile(path: String, data: Data, replaceExisting: Bool = true) async throws {
        try await writeChunks(path: path, replaceExisting: replaceExisting) { appendChunk in
            let encoded = data.base64EncodedString()
            let chunkSize = 48_000
            var index = encoded.startIndex
            while index < encoded.endIndex {
                let next = encoded.index(index, offsetBy: chunkSize, limitedBy: encoded.endIndex) ?? encoded.endIndex
                try await appendChunk(String(encoded[index..<next]))
                index = next
            }
        }
    }

    static func writeFile(path: String, sourceURL: URL, replaceExisting: Bool = true) async throws {
        try await writeChunks(path: path, replaceExisting: replaceExisting) { appendChunk in
            let handle = try FileHandle(forReadingFrom: sourceURL)
            defer { try? handle.close() }

            while true {
                let chunk = try handle.read(upToCount: 36_000) ?? Data()
                guard !chunk.isEmpty else { break }
                try await appendChunk(chunk.base64EncodedString())
            }
        }
    }

    private static func writeChunks(
        path: String,
        replaceExisting: Bool,
        body: ((String) async throws -> Void) async throws -> Void
    ) async throws {
        let target = shellQuote(path)
        let tempPath = "\(path).litter-write-\(UUID().uuidString).tmp"
        let temp = shellQuote(tempPath)
        let create = await run(": > \(temp)")
        guard create.exitCode == 0 else { throw error("Could not write \(path)", result: create) }

        do {
            try await body { chunk in
                let result = await run("printf %s \(shellQuote(chunk)) | base64 -d >> \(temp)")
                guard result.exitCode == 0 else { throw error("Could not write \(path)", result: result) }
            }
            let moveCommand: String
            if replaceExisting {
                moveCommand = "mv \(temp) \(target)"
            } else {
                moveCommand = "[ ! -e \(target) ] || exit 17; mv \(temp) \(target)"
            }
            let move = await run(moveCommand)
            guard move.exitCode == 0 else { throw error("Could not replace \(path)", result: move) }
        } catch {
            _ = await run("rm -f \(temp)")
            throw error
        }
    }

    static func createEmptyFile(path: String) async throws {
        let result = await run("set -C; : > \(shellQuote(path))")
        guard result.exitCode == 0 else { throw error("Could not create file. An item with that name may already exist.", result: result) }
    }

    static func exists(path: String) async -> Bool {
        let result = await run("[ -e \(shellQuote(path)) ]")
        return result.exitCode == 0
    }

    static func createDirectory(path: String) async throws {
        let result = await run("mkdir \(shellQuote(path))")
        guard result.exitCode == 0 else { throw error("Could not create folder. An item with that name may already exist.", result: result) }
    }

    static func rename(path: String, to destination: String) async throws {
        let result = await run("dest=\(shellQuote(destination)); [ ! -e \"$dest\" ] || exit 17; mv \(shellQuote(path)) \"$dest\"")
        guard result.exitCode == 0 else { throw error("Could not rename item. An item with that name may already exist.", result: result) }
    }

    static func delete(path: String) async throws {
        let result = await run("rm -rf \(shellQuote(path))")
        guard result.exitCode == 0 else { throw error("Could not delete item", result: result) }
    }

    private static func error(_ fallback: String, result: Result) -> NSError {
        let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return NSError(
            domain: "IshFS",
            code: Int(result.exitCode),
            userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? fallback : message]
        )
    }

}
