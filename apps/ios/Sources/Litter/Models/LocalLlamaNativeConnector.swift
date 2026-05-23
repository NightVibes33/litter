import Foundation

/// The on-device llama.cpp bridge is intentionally disabled in Litter builds.
/// Use ChatGPT or a PC-hosted OpenAI-compatible server for local/private models.
enum LocalLlamaNativeConnector {
    static func installIfAvailable() {
        Task.detached(priority: .utility) {
            await LocalLlamaRuntime.shared.configureCapabilities(.unavailable)
            await LocalLlamaRuntime.shared.configureCancellationHandler(nil)
            await LocalLlamaRuntime.shared.configureTokenGenerator(nil)
        }
    }
}
