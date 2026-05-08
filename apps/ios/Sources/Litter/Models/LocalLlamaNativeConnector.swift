import Foundation

/// Registers the native llama.cpp adapter with the Swift local-model runtime.
/// The adapter is intentionally iOS-only because the current project links
/// `llama.xcframework` only into the iOS application target.
enum LocalLlamaNativeConnector {
    static func installIfAvailable() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        guard LitterLlamaBridge.isAvailable() else { return }
        Task.detached(priority: .utility) {
            await LocalLlamaRuntime.shared.configureCapabilities(LocalLlamaRuntimeCapabilities(
                isAvailable: true,
                turboQuant: .unavailable("This build links the standard llama.cpp bridge. Rebuild with a TurboQuant-capable llama.cpp fork to enable TurboQuant KV cache modes."),
                supportedKVCacheModes: [.automatic, .f16, .q8, .q4]
            ))
            await LocalLlamaRuntime.shared.configureCancellationHandler {
                LitterLlamaBridge.unload()
            }
            await LocalLlamaRuntime.shared.configureTokenGenerator { request, messages, onToken in
                try await Task.detached(priority: .userInitiated) {
                    let objcMessages = messages.map { message in
                        ["role": message.role.rawValue, "text": message.text]
                    }
                    return try LitterLlamaBridge.generate(
                        withModelPath: request.model.fileURL.path,
                        contextTokens: request.options.contextTokens,
                        maxTokens: request.maxTokens,
                        temperature: request.temperature,
                        messages: objcMessages,
                        onToken: { token in onToken(token) }
                    )
                }.value
            }
        }
        #endif
    }
}
