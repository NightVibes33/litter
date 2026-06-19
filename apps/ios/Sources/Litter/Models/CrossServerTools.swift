import Foundation

enum CrossServerTools {
    static let listServersToolName = "list_servers"
    static let listSessionsToolName = "list_sessions"

    // Perplexity-specific local tool names dispatched through PerplexityLocalProvider
    static let webSearchToolName = "web_search"
    static let runCodeToolName = "run_code"
    static let readFileToolName = "read_file"
    static let writeFileToolName = "write_file"
    static let installAppToolName = "install_app"

    /// All tool names that can be dispatched locally without any external API.
    static let perplexityLocalToolNames: Set<String> = [
        listServersToolName,
        listSessionsToolName,
        webSearchToolName,
        runCodeToolName,
        readFileToolName,
        writeFileToolName,
        installAppToolName
    ]

    /// Build the dynamic tool specs for cross-server operations.
    static func buildDynamicToolSpecs() -> [DynamicToolSpecParams] {
        [
            listServersSpec(),
            listSessionsSpec()
        ]
    }

    /// Returns true if the given tool name is a cross-server tool that
    /// should be rendered with rich formatting in the conversation timeline.
    static func isRichTool(_ toolName: String) -> Bool {
        switch toolName {
        case listServersToolName, listSessionsToolName:
            return true
        default:
            return false
        }
    }

    /// Returns true if the tool can be dispatched locally through
    /// PerplexityLocalProvider without hitting any external API.
    static func isPerplexityLocalTool(_ toolName: String) -> Bool {
        perplexityLocalToolNames.contains(toolName)
    }

    /// Dispatch a Perplexity tool_call result through the local provider.
    /// Call this from the chat engine when the Perplexity provider returns
    /// finish_reason = "tool_calls".
    @MainActor
    static func dispatchPerplexityToolCall(
        _ toolCall: PerplexityLocalProvider.ToolCall
    ) async -> String {
        await PerplexityLocalProvider.shared.dispatchToolCall(toolCall)
    }

    private static func listServersSpec() -> DynamicToolSpecParams {
        DynamicToolSpecParams(
            name: listServersToolName,
            description: "List all connected servers and their status. After calling this tool, briefly tell the user what you found.",
            inputSchema: AnyEncodable(JSONSchema.object([:], required: []))
        )
    }

    private static func listSessionsSpec() -> DynamicToolSpecParams {
        DynamicToolSpecParams(
            name: listSessionsToolName,
            description: "List recent sessions/threads on a specific server or all connected servers. After calling this tool, briefly tell the user what you found.",
            inputSchema: AnyEncodable(JSONSchema.object([
                "server": .string(description: "Server name to query. Omit to query all connected servers.")
            ], required: []))
        )
    }
}
