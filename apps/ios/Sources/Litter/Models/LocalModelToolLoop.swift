import Foundation

struct LocalModelToolSpec: Equatable {
    var name: String
    var description: String
    var inputSchemaJSON: String
}

struct LocalModelToolCall: Equatable, Identifiable {
    var id: String
    var name: String
    var arguments: [String: String]
}

struct LocalModelToolResult: Equatable {
    var callId: String
    var toolName: String
    var success: Bool
    var output: String
}

enum LocalModelToolRisk: String, Equatable {
    case safeRead
    case shell
    case write
    case build
    case unknown

    var requiresUserApproval: Bool {
        self != .safeRead
    }
}

struct LocalModelToolApprovalRequest: Equatable, Identifiable {
    var id: String { call.id }
    var call: LocalModelToolCall
    var risk: LocalModelToolRisk
    var reason: String

    var requiresUserApproval: Bool { risk.requiresUserApproval }
}

struct LocalModelToolApprovalDecision: Equatable {
    var isApproved: Bool
    var policy: LocalModelToolPolicy

    static let denied = LocalModelToolApprovalDecision(isApproved: false, policy: .readOnly)
    static let approveShellReadOnly = LocalModelToolApprovalDecision(isApproved: true, policy: .approvedShellReadOnly)
    static let approveWrite = LocalModelToolApprovalDecision(isApproved: true, policy: .approvedWrite)
}

struct LocalModelToolPolicy: Equatable {
    var allowsShell: Bool
    var allowsWrites: Bool
    var maxReadBytes: Int64
    var maxShellOutputBytes: Int

    static let readOnly = LocalModelToolPolicy(
        allowsShell: false,
        allowsWrites: false,
        maxReadBytes: 32_000,
        maxShellOutputBytes: 24_000
    )

    static let approvedShellReadOnly = LocalModelToolPolicy(
        allowsShell: true,
        allowsWrites: false,
        maxReadBytes: 64_000,
        maxShellOutputBytes: 48_000
    )

    static let approvedWrite = LocalModelToolPolicy(
        allowsShell: true,
        allowsWrites: true,
        maxReadBytes: 64_000,
        maxShellOutputBytes: 48_000
    )
}

enum LocalModelToolLoopError: LocalizedError {
    case unknownTool(String)
    case blocked(String)
    case missingArgument(String)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            return "Unknown local tool: \(name)"
        case .blocked(let message):
            return message
        case .missingArgument(let name):
            return "Missing required tool argument: \(name)"
        }
    }
}

enum LocalModelToolLoop {
    static let defaultToolSpecs: [LocalModelToolSpec] = [
        LocalModelToolSpec(
            name: "list_dir",
            description: "List files in the iSH fakefs. Use this before reading unknown paths.",
            inputSchemaJSON: """
            {"type":"object","properties":{"path":{"type":"string"},"include_hidden":{"type":"boolean"}},"required":["path"]}
            """
        ),
        LocalModelToolSpec(
            name: "read_file",
            description: "Read a UTF-8 text file from the iSH fakefs. Large files are rejected.",
            inputSchemaJSON: """
            {"type":"object","properties":{"path":{"type":"string"},"max_bytes":{"type":"number"}},"required":["path"]}
            """
        ),
        LocalModelToolSpec(
            name: "search_files",
            description: "Search file names under a fakefs directory using a literal query.",
            inputSchemaJSON: """
            {"type":"object","properties":{"path":{"type":"string"},"query":{"type":"string"},"max_results":{"type":"number"}},"required":["path","query"]}
            """
        ),
        LocalModelToolSpec(
            name: "grep_text",
            description: "Search text content under a fakefs directory or file. Use literal search, not regex.",
            inputSchemaJSON: """
            {"type":"object","properties":{"path":{"type":"string"},"query":{"type":"string"},"max_results":{"type":"number"}},"required":["path","query"]}
            """
        ),
        LocalModelToolSpec(
            name: "repo_map",
            description: "Build a compact file tree map for a fakefs folder before planning edits.",
            inputSchemaJSON: """
            {"type":"object","properties":{"path":{"type":"string"},"max_entries":{"type":"number"}},"required":["path"]}
            """
        ),
        LocalModelToolSpec(
            name: "shell",
            description: "Run a shell command in iSH. Disabled unless the user explicitly allows local shell tools.",
            inputSchemaJSON: """
            {"type":"object","properties":{"command":{"type":"string"},"cwd":{"type":"string"}},"required":["command"]}
            """
        ),
        LocalModelToolSpec(
            name: "write_file",
            description: "Write a UTF-8 file in iSH. Disabled until the approval UI shows the diff.",
            inputSchemaJSON: """
            {"type":"object","properties":{"path":{"type":"string"},"text":{"type":"string"}},"required":["path","text"]}
            """
        ),
        LocalModelToolSpec(
            name: "replace_text",
            description: "Replace exactly one UTF-8 text range in a fakefs file. Safer than full-file writes for edits.",
            inputSchemaJSON: """
            {"type":"object","properties":{"path":{"type":"string"},"old_text":{"type":"string"},"new_text":{"type":"string"}},"required":["path","old_text","new_text"]}
            """
        ),
        LocalModelToolSpec(
            name: "buildkit_status",
            description: "Show whether private CoreCompiler, Swift support libraries, native driver, and iPhoneOS SDK assets are installed.",
            inputSchemaJSON: """
            {"type":"object","properties":{}}
            """
        ),
        LocalModelToolSpec(
            name: "fs_doctor",
            description: "Repair and validate important iSH fakefs paths such as /dev/random, /dev/urandom, /tmp, and /usr/local/bin.",
            inputSchemaJSON: """
            {"type":"object","properties":{}}
            """
        ),
        LocalModelToolSpec(
            name: "swift_check",
            description: "Run Litter BuildKit Swift diagnostics for a fakefs Swift file.",
            inputSchemaJSON: """
            {"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}
            """
        ),
        LocalModelToolSpec(
            name: "swift_build",
            description: "Build a fakefs Swift project through Litter BuildKit. Requires approval because it writes build outputs.",
            inputSchemaJSON: """
            {"type":"object","properties":{"project_path":{"type":"string"}},"required":["project_path"]}
            """
        ),
        LocalModelToolSpec(
            name: "ipa_build",
            description: "Build an unsigned IPA from a fakefs LitterBuild.json project. Requires approval because it writes artifacts.",
            inputSchemaJSON: """
            {"type":"object","properties":{"project_path":{"type":"string"}},"required":["project_path"]}
            """
        ),
        LocalModelToolSpec(
            name: "swift_test",
            description: "Run BuildKit tests for a fakefs Swift project. Requires approval because it writes build outputs.",
            inputSchemaJSON: """
            {"type":"object","properties":{"project_path":{"type":"string"}},"required":["project_path"]}
            """
        ),
        LocalModelToolSpec(
            name: "ipa_package",
            description: "Package a previously built fakefs app bundle as an unsigned IPA. Requires approval because it writes artifacts.",
            inputSchemaJSON: """
            {"type":"object","properties":{"project_path":{"type":"string"}},"required":["project_path"]}
            """
        ),
        LocalModelToolSpec(
            name: "build_cancel",
            description: "Cancel an active BuildKit job by id.",
            inputSchemaJSON: """
            {"type":"object","properties":{"job_id":{"type":"string"}},"required":["job_id"]}
            """
        ),
        LocalModelToolSpec(
            name: "build_status",
            description: "Read status and logs for a Litter BuildKit job id.",
            inputSchemaJSON: """
            {"type":"object","properties":{"job_id":{"type":"string"}},"required":["job_id"]}
            """
        )
    ]

    static func systemInstructions(for tools: [LocalModelToolSpec] = defaultToolSpecs) -> String {
        let specs = tools.map { tool in
            "- \(tool.name): \(tool.description) schema=\(tool.inputSchemaJSON)"
        }.joined(separator: "\n")
        return """
        You can request local app tools by replying with a single JSON object and no markdown.
        Use this exact shape: {"tool":"tool_name","arguments":{"key":"value"}}
        Read-only fakefs tools can run automatically. Shell, build, and write tools require explicit user approval.
        Prefer repo_map, search_files, grep_text, and read_file before editing. Prefer replace_text for small edits and write_file only when replacing the full file is safer.
        After a tool result is returned, answer normally or request another tool.
        Available local tools:
        \(specs)
        """
    }

    static func parseToolCalls(from text: String) -> [LocalModelToolCall] {
        jsonObjects(in: text).flatMap { object -> [LocalModelToolCall] in
            if let calls = object["tool_calls"] as? [[String: Any]] {
                return calls.compactMap(toolCall(from:))
            }
            if let call = toolCall(from: object) {
                return [call]
            }
            return []
        }
    }

    static func looksLikeMalformedToolRequest(_ text: String) -> Bool {
        let lowered = text.lowercased()
        guard lowered.contains("tool") || lowered.contains("arguments") || lowered.contains("list_dir") || lowered.contains("read_file") || lowered.contains("write_file") || lowered.contains("shell") || lowered.contains("swift_check") || lowered.contains("ipa_build") || lowered.contains("buildkit") else {
            return false
        }
        return parseToolCalls(from: text).isEmpty
    }

    static func risk(for call: LocalModelToolCall) -> LocalModelToolRisk {
        switch call.name {
        case "list_dir", "read_file", "search_files", "grep_text", "repo_map":
            return .safeRead
        case "shell":
            return .shell
        case "write_file", "replace_text":
            return .write
        case "swift_build", "swift_test", "ipa_build", "ipa_package", "build_cancel":
            return .build
        default:
            return .unknown
        }
    }

    static func approvalRequest(for call: LocalModelToolCall) -> LocalModelToolApprovalRequest {
        let risk = risk(for: call)
        return LocalModelToolApprovalRequest(call: call, risk: risk, reason: approvalReason(for: call, risk: risk))
    }

    private static func approvalReason(for call: LocalModelToolCall, risk: LocalModelToolRisk) -> String {
        switch risk {
        case .safeRead:
            return "Read-only fakefs lookup."
        case .shell:
            return "The local model wants to run a shell command: \(call.arguments["command"] ?? call.name)"
        case .write:
            if call.name == "replace_text" {
                return "The local model wants to edit: \(call.arguments["path"] ?? "unknown path")"
            }
            return "The local model wants to write to: \(call.arguments["path"] ?? "unknown path")"
        case .build:
            return "The local model wants to run an on-device Swift/IPA BuildKit job."
        case .unknown:
            return "The local model requested an unknown tool: \(call.name)"
        }
    }

    static func execute(_ call: LocalModelToolCall, policy: LocalModelToolPolicy = .readOnly) async -> LocalModelToolResult {
        do {
            let output = try await executeThrowing(call, policy: policy)
            return LocalModelToolResult(callId: call.id, toolName: call.name, success: true, output: output)
        } catch {
            return LocalModelToolResult(callId: call.id, toolName: call.name, success: false, output: error.localizedDescription)
        }
    }

    private static func executeThrowing(_ call: LocalModelToolCall, policy: LocalModelToolPolicy) async throws -> String {
        switch call.name {
        case "list_dir":
            let path = try argument("path", in: call)
            let includeHidden = boolArgument("include_hidden", in: call) ?? false
            let entries = try await IshFS.listDirectory(path: path, includeHidden: includeHidden)
            return entries.map { entry in
                let prefix = entry.kind == .directory ? "d" : "f"
                return "\(prefix)\t\(entry.size)\t\(entry.path)"
            }.joined(separator: "\n")
        case "read_file":
            let path = try argument("path", in: call)
            let requested = int64Argument("max_bytes", in: call) ?? policy.maxReadBytes
            return try await IshFS.readTextFile(path: path, maxBytes: min(requested, policy.maxReadBytes))
        case "search_files":
            let path = try argument("path", in: call)
            let query = try argument("query", in: call)
            let maxResults = max(1, min(intArgument("max_results", in: call) ?? 50, 200))
            let command = "find \(IshFS.shellQuote(path)) -iname \(IshFS.shellQuote("*\(query)*")) -print 2>/dev/null | head -n \(maxResults)"
            let result = await IshFS.run(command)
            guard result.exitCode == 0 else { throw LocalModelToolLoopError.blocked(result.output) }
            return result.output
        case "grep_text":
            let path = try argument("path", in: call)
            let query = try argument("query", in: call)
            let maxResults = max(1, min(intArgument("max_results", in: call) ?? 50, 200))
            let command = "grep -R -n -I -F -- \(IshFS.shellQuote(query)) \(IshFS.shellQuote(path)) 2>/dev/null | head -n \(maxResults)"
            let result = await IshFS.run(command)
            if result.exitCode == 1 { return "No matches." }
            guard result.exitCode == 0 else { throw LocalModelToolLoopError.blocked(result.output) }
            return result.output
        case "repo_map":
            let path = try argument("path", in: call)
            let maxEntries = max(10, min(intArgument("max_entries", in: call) ?? 120, 400))
            let command = "find \(IshFS.shellQuote(path)) -maxdepth 4 -print 2>/dev/null | sed 's#^#- #' | head -n \(maxEntries)"
            let result = await IshFS.run(command)
            guard result.exitCode == 0 else { throw LocalModelToolLoopError.blocked(result.output) }
            return result.output
        case "buildkit_status":
            let result = await IshFS.run("litter-buildkit --timeout 30")
            guard result.exitCode == 0 else { throw LocalModelToolLoopError.blocked(result.output) }
            return result.output
        case "fs_doctor":
            let result = await IshFS.run("litter-fs-doctor --timeout 60")
            guard result.exitCode == 0 else { throw LocalModelToolLoopError.blocked(result.output) }
            return result.output
        case "swift_check":
            let path = try argument("path", in: call)
            let result = await IshFS.run("litter-swift-check --timeout 120 \(IshFS.shellQuote(path))")
            guard result.exitCode == 0 else { throw LocalModelToolLoopError.blocked(result.output) }
            return result.output
        case "build_status":
            let jobId = try argument("job_id", in: call)
            let result = await IshFS.run("litter-build-status \(IshFS.shellQuote(jobId))")
            guard result.exitCode == 0 else { throw LocalModelToolLoopError.blocked(result.output) }
            return result.output
        case "swift_build":
            guard policy.allowsShell else { throw LocalModelToolLoopError.blocked("BuildKit build jobs require explicit user approval.") }
            let path = try argument("project_path", in: call)
            let result = await IshFS.run("litter-swift-build --timeout 600 \(IshFS.shellQuote(path))")
            guard result.exitCode == 0 else { throw LocalModelToolLoopError.blocked(result.output) }
            return result.output
        case "swift_test":
            guard policy.allowsShell else { throw LocalModelToolLoopError.blocked("BuildKit test jobs require explicit user approval.") }
            let path = try argument("project_path", in: call)
            let result = await IshFS.run("litter-swift-test --timeout 600 \(IshFS.shellQuote(path))")
            guard result.exitCode == 0 else { throw LocalModelToolLoopError.blocked(result.output) }
            return result.output
        case "ipa_build":
            guard policy.allowsShell else { throw LocalModelToolLoopError.blocked("IPA build jobs require explicit user approval.") }
            let path = try argument("project_path", in: call)
            let result = await IshFS.run("litter-ipa-build --timeout 900 \(IshFS.shellQuote(path))")
            guard result.exitCode == 0 else { throw LocalModelToolLoopError.blocked(result.output) }
            return result.output
        case "ipa_package":
            guard policy.allowsShell else { throw LocalModelToolLoopError.blocked("IPA packaging requires explicit user approval.") }
            let path = try argument("project_path", in: call)
            let result = await IshFS.run("litter-ipa-package --timeout 900 \(IshFS.shellQuote(path))")
            guard result.exitCode == 0 else { throw LocalModelToolLoopError.blocked(result.output) }
            return result.output
        case "build_cancel":
            let jobId = try argument("job_id", in: call)
            let result = await IshFS.run("litter-build-cancel \(IshFS.shellQuote(jobId))")
            guard result.exitCode == 0 else { throw LocalModelToolLoopError.blocked(result.output) }
            return result.output
        case "shell":
            guard policy.allowsShell else { throw LocalModelToolLoopError.blocked("Local shell tools require explicit user approval.") }
            let command = try argument("command", in: call)
            let cwd = call.arguments["cwd"]
            let result = await IshFS.run(command, cwd: cwd)
            return String(result.output.prefix(policy.maxShellOutputBytes))
        case "write_file":
            guard policy.allowsWrites else { throw LocalModelToolLoopError.blocked("Local write tools require an approval UI before execution.") }
            let path = try argument("path", in: call)
            let text = try argument("text", in: call)
            try await IshFS.writeTextFile(path: path, text: text)
            return "Wrote \(path)"
        case "replace_text":
            guard policy.allowsWrites else { throw LocalModelToolLoopError.blocked("Local edits require approval before execution.") }
            let path = try argument("path", in: call)
            let oldText = try argument("old_text", in: call)
            let newText = try argument("new_text", in: call)
            let current = try await IshFS.readTextFile(path: path, maxBytes: policy.maxReadBytes)
            let occurrences = current.components(separatedBy: oldText).count - 1
            guard occurrences == 1 else {
                throw LocalModelToolLoopError.blocked("replace_text expected exactly one match in \(path), found \(occurrences). Read the file again and produce a narrower edit.")
            }
            try await IshFS.writeTextFile(path: path, text: current.replacingOccurrences(of: oldText, with: newText))
            return "Edited \(path)"
        default:
            throw LocalModelToolLoopError.unknownTool(call.name)
        }
    }

    private static func toolCall(from object: [String: Any]) -> LocalModelToolCall? {
        let name = (object["tool"] as? String) ?? (object["name"] as? String)
        guard let name, !name.isEmpty else { return nil }
        let rawArguments = object["arguments"] ?? object["args"] ?? [:]
        return LocalModelToolCall(
            id: (object["id"] as? String) ?? UUID().uuidString,
            name: name,
            arguments: stringifyDictionary(rawArguments)
        )
    }

    private static func jsonObjects(in text: String) -> [[String: Any]] {
        candidateJSONStrings(in: text).compactMap { candidate in
            guard let data = candidate.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return object
        }
    }

    private static func candidateJSONStrings(in text: String) -> [String] {
        var candidates: [String] = []
        var start: String.Index?
        var depth = 0
        var inString = false
        var escape = false

        for index in text.indices {
            let char = text[index]
            if inString {
                if escape {
                    escape = false
                } else if char == "\\" {
                    escape = true
                } else if char == "\"" {
                    inString = false
                }
                continue
            }
            if char == "\"" {
                inString = true
            } else if char == "{" {
                if depth == 0 { start = index }
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0, let objectStart = start {
                    candidates.append(String(text[objectStart...index]))
                    start = nil
                }
            }
        }
        return candidates
    }


    private static func stringifyDictionary(_ value: Any) -> [String: String] {
        guard let dict = value as? [String: Any] else { return [:] }
        var output: [String: String] = [:]
        for (key, rawValue) in dict {
            if let string = rawValue as? String {
                output[key] = string
            } else if let number = rawValue as? NSNumber {
                output[key] = number.stringValue
            } else if let data = try? JSONSerialization.data(withJSONObject: rawValue),
                      let string = String(data: data, encoding: .utf8) {
                output[key] = string
            }
        }
        return output
    }

    private static func argument(_ name: String, in call: LocalModelToolCall) throws -> String {
        guard let value = call.arguments[name], !value.isEmpty else {
            throw LocalModelToolLoopError.missingArgument(name)
        }
        return value
    }

    private static func boolArgument(_ name: String, in call: LocalModelToolCall) -> Bool? {
        guard let value = call.arguments[name]?.lowercased() else { return nil }
        return ["1", "true", "yes"].contains(value)
    }

    private static func intArgument(_ name: String, in call: LocalModelToolCall) -> Int? {
        guard let value = call.arguments[name] else { return nil }
        return Int(value)
    }

    private static func int64Argument(_ name: String, in call: LocalModelToolCall) -> Int64? {
        guard let value = call.arguments[name] else { return nil }
        return Int64(value)
    }
}
