import Foundation

enum AIProviderKind: String, Codable, CaseIterable, Identifiable {
    case openAI
    case openAICompatible
    case perplexity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .openAICompatible: return "OpenAI-Compatible Server"
        case .perplexity: return "Perplexity"
        }
    }

    /// Suggested model IDs shown in the model selector for each provider kind.
    /// For providers that expose a /v1/models endpoint, return [] here and let
    /// AIProviderStore fetch the live list at runtime — that way the UI always
    /// reflects exactly what the running proxy serves, with no hardcoded stale list.
    var suggestedModels: [String] {
        switch self {
        case .openAI:
            return [
                "gpt-4.1",
                "gpt-4.1-mini",
                "gpt-4o",
                "gpt-4o-mini",
                "o3",
                "o4-mini",
            ]
        case .openAICompatible:
            // Populated dynamically from the /v1/models endpoint at runtime.
            return []
        case .perplexity:
            // Populated dynamically from the alley-cat proxy /v1/models endpoint
            // at runtime (127.0.0.1:8001). Perplexity runs its own custom brain —
            // NOT ChatGPT/OpenAI. The proxy serves whatever models the local
            // runtime supports, so hardcoding here would always be stale.
            // supportsModelsEndpoint = true ensures AIProviderStore fetches live.
            return []
        }
    }
}

struct AIProviderCapabilities: Codable, Equatable {
    var supportsModelsEndpoint: Bool
    var supportsChatCompletions: Bool
    var supportsStreaming: Bool
    var requiresNetwork: Bool

    static let openAI = AIProviderCapabilities(
        supportsModelsEndpoint: true,
        supportsChatCompletions: true,
        supportsStreaming: true,
        requiresNetwork: true
    )

    static let openAICompatible = AIProviderCapabilities(
        supportsModelsEndpoint: true,
        supportsChatCompletions: true,
        supportsStreaming: true,
        requiresNetwork: true
    )

    // Perplexity runs via the local alley cat runtime on 127.0.0.1:8001.
    // supportsModelsEndpoint = true so AIProviderStore fetches the live
    // model list from the proxy rather than relying on a hardcoded array.
    // requiresNetwork = false — the runtime is on-device / local LAN.
    static let perplexity = AIProviderCapabilities(
        supportsModelsEndpoint: true,
        supportsChatCompletions: true,
        supportsStreaming: true,
        requiresNetwork: false
    )
}

struct AIProviderProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var kind: AIProviderKind
    var displayName: String
    var baseURL: String
    var defaultModel: String
    var isEnabled: Bool
    var capabilities: AIProviderCapabilities
    var createdAt: Date
    var updatedAt: Date

    var normalizedBaseURL: URL? {
        AIProviderProfile.normalizedBaseURL(baseURL)
    }

    static func normalizedBaseURL(_ raw: String) -> URL? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") {
            value = "http://" + value
        }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        if value.hasSuffix("/v1") {
            return URL(string: value)
        }
        return URL(string: value + "/v1")
    }

    static func openAI(defaultModel: String = "gpt-4.1") -> AIProviderProfile {
        let now = Date()
        return AIProviderProfile(
            id: UUID(),
            kind: .openAI,
            displayName: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            defaultModel: defaultModel,
            isEnabled: true,
            capabilities: .openAI,
            createdAt: now,
            updatedAt: now
        )
    }

    // Perplexity's custom brain runs locally through the alley cat runtime.
    // The proxy at 127.0.0.1:8001 exposes an OpenAI-compatible endpoint so
    // the rest of the chat stack needs zero changes to talk to it.
    // Models are fetched live from /v1/models — never hardcoded.
    // NEVER route Perplexity through api.openai.com — it has its own inference stack.
    static func perplexity(defaultModel: String = "sonar-pro") -> AIProviderProfile {
        let now = Date()
        return AIProviderProfile(
            id: UUID(),
            kind: .perplexity,
            displayName: "Perplexity (Local)",
            baseURL: "http://127.0.0.1:8001",
            defaultModel: defaultModel,
            isEnabled: true,
            capabilities: .perplexity,
            createdAt: now,
            updatedAt: now
        )
    }

    static func ollama(name: String, baseURL: String, defaultModel: String) -> AIProviderProfile {
        let now = Date()
        return AIProviderProfile(
            id: UUID(),
            kind: .openAICompatible,
            displayName: name,
            baseURL: baseURL,
            defaultModel: defaultModel,
            isEnabled: true,
            capabilities: .openAICompatible,
            createdAt: now,
            updatedAt: now
        )
    }
}

struct AIProviderModel: Codable, Identifiable, Equatable {
    var id: String
    var displayName: String
    var providerId: UUID
    var providerKind: AIProviderKind
}

struct AIProviderHealthReport: Equatable {
    enum Status: Equatable {
        case unknown
        case healthy
        case warning(String)
        case failed(String)
    }

    var status: Status
    var models: [String]

    var summary: String {
        switch status {
        case .unknown: return "Not tested"
        case .healthy: return models.isEmpty ? "Reachable" : "Reachable · \(models.count) models"
        case .warning(let message): return message
        case .failed(let message): return message
        }
    }
}

enum AIModelRoutingMode: String, CaseIterable, Identifiable {
    case automatic
    case openAI
    case openAICompatible
    case perplexity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .openAI: return "OpenAI"
        case .openAICompatible: return "Ollama / OpenAI-Compatible"
        case .perplexity: return "Perplexity (Local)"
        }
    }
}

extension AIModelRoutingMode: Codable {
    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        switch rawValue {
        case Self.openAI.rawValue:
            self = .openAI
        case Self.openAICompatible.rawValue:
            self = .openAICompatible
        case Self.perplexity.rawValue:
            self = .perplexity
        default:
            self = .automatic
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct GlobalModelSettings: Codable, Equatable {
    var routingMode: AIModelRoutingMode
    var preferredProviderId: UUID?

    static let defaults = GlobalModelSettings(
        routingMode: .automatic,
        preferredProviderId: nil
    )
}
