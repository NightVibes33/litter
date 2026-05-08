import Foundation

/// Registers the native llama.cpp adapter with the Swift local-model runtime.
/// The adapter is intentionally iOS-only because the current project links
/// `llama.xcframework` only into the iOS application target.
enum LocalLlamaNativeConnector {
    static func installIfAvailable() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        guard LitterLlamaBridge.isAvailable() else { return }
        Task.detached(priority: .utility) {
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
