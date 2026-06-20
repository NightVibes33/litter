import Foundation

// MARK: - PerplexityLocalProvider
//
// Perplexity runs as its own custom brain through the alley cat local runtime.
// This provider talks to the OpenAI-compatible endpoint the runtime exposes
// on 127.0.0.1:8001 and handles the full tool-calling agentic loop natively
// inside the app — no ChatGPT account, no OpenAI Codex, no external API.
//
// Tool call flow:
//   1. Send chat/completions with tools[] to 127.0.0.1:8001
//   2. Runtime returns finish_reason = "tool_calls" with one or more calls
//   3. We dispatch each call through dispatchToolCall(_:)
//   4. Results are appended as role=tool messages
//   5. We loop back to step 1 until finish_reason = "stop"

@MainActor
final class PerplexityLocalProvider: ObservableObject {
    static let shared = PerplexityLocalProvider()

    private let baseURL = URL(string: "http://127.0.0.1:8001/v1")!
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config)
    }

    // MARK: - Health

    func healthReport() async -> AIProviderHealthReport {
        let url = URL(string: "http://127.0.0.1:8001/health")!
        do {
            let (_, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return AIProviderHealthReport(status: .failed("Local runtime returned non-2xx"), models: [])
            }
            let models = await fetchAvailableModels()
            return AIProviderHealthReport(status: .healthy, models: models)
        } catch {
            return AIProviderHealthReport(
                status: .failed("Integrated Perplexity runtime not running on :8001 — start Alley Cat first"),
                models: []
            )
        }
    }

    private func fetchAvailableModels() async -> [String] {
        let url = baseURL.appendingPathComponent("models")
        guard let (data, _) = try? await session.data(from: url),
              let decoded = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
            return ["reasoning"]
        }
        return decoded.data.map(\.id)
    }

    // MARK: - Agentic Completion Loop

    /// Run a full agentic completion, handling tool calls until the model stops.
    /// Messages is a standard OpenAI-format array. Returns the final assistant text.
    func complete(
        messages: [[String: Any]],
        model: String = "reasoning",
        onChunk: ((String) -> Void)? = nil
    ) async throws -> String {
        var history = messages
        var finalText = ""
        var iterations = 0
        let maxIterations = 12

        while iterations < maxIterations {
            iterations += 1
            let response = try await chatCompletion(messages: history, model: model, stream: false)

            guard let choice = response.choices.first else { break }

            // Append assistant message to history
            var assistantMsg: [String: Any] = ["role": "assistant"]
            if let content = choice.message.content {
                assistantMsg["content"] = content
            }
            if let toolCalls = choice.message.toolCalls, !toolCalls.isEmpty {
                assistantMsg["tool_calls"] = toolCalls.map { tc in
                    [
                        "id": tc.id,
                        "type": tc.type,
                        "function": [
                            "name": tc.function.name,
                            "arguments": tc.function.arguments
                        ] as [String: Any]
                    ] as [String: Any]
                }
            }
            history.append(assistantMsg)

            if choice.finishReason == "tool_calls", let toolCalls = choice.message.toolCalls {
                // Dispatch each tool call and collect results
                for toolCall in toolCalls {
                    let result = await dispatchToolCall(toolCall)
                    history.append([
                        "role": "tool",
                        "tool_call_id": toolCall.id,
                        "content": result
                    ])
                }
                // Loop — feed tool results back to model
                continue
            }

            // Model stopped — we have the final answer
            finalText = choice.message.content ?? ""
            onChunk?(finalText)
            break
        }

        return finalText
    }

    // MARK: - Tool Dispatch

    /// Dispatch a single tool call and return the result as a string.
    /// Add new tool handlers here — they run natively in the app, no ChatGPT needed.
    func dispatchToolCall(_ toolCall: ToolCall) async -> String {
        guard let args = try? JSONSerialization.jsonObject(
            with: Data(toolCall.function.arguments.utf8)
        ) as? [String: Any] else {
            return "{\"error\": \"invalid arguments JSON\"}"
        }

        switch toolCall.function.name {

        case "web_search":
            let query = args["query"] as? String ?? ""
            // Delegate to the local runtime's search capability
            return await runLocalRuntimeTool(name: "web_search", args: args)

        case "run_code":
            return await runLocalRuntimeTool(name: "run_code", args: args)

        case "read_file":
            let path = args["path"] as? String ?? ""
            do {
                let content = try String(contentsOfFile: path, encoding: .utf8)
                return "\"\(content.prefix(8000))\""
            } catch {
                return "{\"error\": \"\(error.localizedDescription)\"}"
            }

        case "write_file":
            let path = args["path"] as? String ?? ""
            let content = args["content"] as? String ?? ""
            do {
                try content.write(toFile: path, atomically: true, encoding: .utf8)
                return "{\"success\": true}"
            } catch {
                return "{\"error\": \"\(error.localizedDescription)\"}"
            }

        case "list_servers":
            return await runLocalRuntimeTool(name: "list_servers", args: args)

        case "list_sessions":
            return await runLocalRuntimeTool(name: "list_sessions", args: args)

        case "install_app":
            return await runLocalRuntimeTool(name: "install_app", args: args)

        default:
            // Forward unknown tools to the local runtime — it may handle them
            return await runLocalRuntimeTool(name: toolCall.function.name, args: args)
        }
    }

    /// Forward a tool call to the local alley cat runtime's tool execution endpoint.
    private func runLocalRuntimeTool(name: String, args: [String: Any]) async -> String {
        let url = URL(string: "http://127.0.0.1:8001/tools/call")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        let body: [String: Any] = ["name": name, "arguments": args]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return "{\"error\": \"failed to encode tool call\"}"
        }
        request.httpBody = bodyData
        do {
            let (data, _) = try await session.data(for: request)
            return String(data: data, encoding: .utf8) ?? "{\"error\": \"empty response\"}"
        } catch {
            return "{\"error\": \"\(error.localizedDescription)\"}"
        }
    }

    // MARK: - Available Tools

    /// Tool definitions sent to the model so it knows what it can call.
    static let availableTools: [[String: Any]] = [
        [
            "type": "function",
            "function": [
                "name": "web_search",
                "description": "Search the web for current, real-time information.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "The search query."]
                    ] as [String: Any],
                    "required": ["query"]
                ] as [String: Any]
            ] as [String: Any]
        ],
        [
            "type": "function",
            "function": [
                "name": "run_code",
                "description": "Execute code in the local runtime sandbox.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "language": ["type": "string", "description": "Programming language (python, shell, etc.)"],
                        "code": ["type": "string", "description": "The code to execute."]
                    ] as [String: Any],
                    "required": ["language", "code"]
                ] as [String: Any]
            ] as [String: Any]
        ],
        [
            "type": "function",
            "function": [
                "name": "read_file",
                "description": "Read a file from the local filesystem.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Absolute path to the file."]
                    ] as [String: Any],
                    "required": ["path"]
                ] as [String: Any]
            ] as [String: Any]
        ],
        [
            "type": "function",
            "function": [
                "name": "write_file",
                "description": "Write content to a file on the local filesystem.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Absolute path to write."],
                        "content": ["type": "string", "description": "Content to write."]
                    ] as [String: Any],
                    "required": ["path", "content"]
                ] as [String: Any]
            ] as [String: Any]
        ],
        [
            "type": "function",
            "function": [
                "name": "list_servers",
                "description": "List all connected alley cat servers and their status.",
                "parameters": [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ] as [String: Any]
            ] as [String: Any]
        ],
        [
            "type": "function",
            "function": [
                "name": "list_sessions",
                "description": "List recent sessions on a connected server.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "server": ["type": "string", "description": "Server name. Omit for all."]
                    ] as [String: Any],
                    "required": [] as [String]
                ] as [String: Any]
            ] as [String: Any]
        ],
        [
            "type": "function",
            "function": [
                "name": "install_app",
                "description": "Install an IPA or app on the device through the local signing pipeline.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "source": ["type": "string", "description": "URL or local path to the IPA."]
                    ] as [String: Any],
                    "required": ["source"]
                ] as [String: Any]
            ] as [String: Any]
        ]
    ]

    // MARK: - HTTP

    private func chatCompletion(
        messages: [[String: Any]],
        model: String,
        stream: Bool
    ) async throws -> ChatCompletionResponse {
        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "tools": PerplexityLocalProvider.availableTools,
            "tool_choice": "auto",
            "stream": stream
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "(empty)"
            throw PerplexityError.httpError(http.statusCode, body)
        }
        return try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
    }

    // MARK: - Response Models

    struct ChatCompletionResponse: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let message: Message
            let finishReason: String?
            enum CodingKeys: String, CodingKey {
                case message
                case finishReason = "finish_reason"
            }
        }

        struct Message: Decodable {
            let role: String
            let content: String?
            let toolCalls: [ToolCall]?
            enum CodingKeys: String, CodingKey {
                case role, content
                case toolCalls = "tool_calls"
            }
        }
    }

    struct ToolCall: Decodable {
        let id: String
        let type: String
        let function: FunctionCall

        struct FunctionCall: Decodable {
            let name: String
            let arguments: String
        }
    }

    private struct ModelsResponse: Decodable {
        struct Model: Decodable { let id: String }
        let data: [Model]
    }

    enum PerplexityError: LocalizedError {
        case httpError(Int, String)
        var errorDescription: String? {
            switch self {
            case .httpError(let code, let body):
                return "Perplexity local runtime HTTP \(code): \(body)"
            }
        }
    }
}
