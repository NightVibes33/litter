import Foundation

@MainActor
final class PerplexityFakefsInstaller: ObservableObject {
    static let shared = PerplexityFakefsInstaller()

    @Published private(set) var isInstalling = false
    @Published private(set) var lastStatus = "Not installed"

    private let installRoot = "/root/alley-cat/perplexity-ai"
    private let binRoot = "/usr/local/bin"

    private init() {}

    func healthReport() async -> AIProviderHealthReport {
        guard !AppDistributionCapabilities.isAppStoreSafe else {
            return AIProviderHealthReport(status: .failed("Perplexity fakefs support is not included in TestFlight builds."), models: [])
        }
        let packageCheck = await IshFS.run("test -f /root/alley-cat/perplexity-ai/upstream/perplexity/client.py && test -x /usr/local/bin/perplexity-chat")
        if packageCheck.exitCode == 0 {
            return AIProviderHealthReport(status: .healthy, models: ["auto", "pro", "reasoning", "deep research"])
        }
        return AIProviderHealthReport(status: .warning("Tap Install FakeFS Helper to copy the Perplexity bundle into iSH."), models: [])
    }

    func install() async {
        guard !AppDistributionCapabilities.isAppStoreSafe else {
            lastStatus = "Perplexity fakefs support is sideload-only."
            return
        }
        guard !isInstalling else { return }
        isInstalling = true
        defer { isInstalling = false }

        do {
            guard let source = Bundle.main.url(forResource: "PerplexityAI", withExtension: nil) else {
                throw NSError(domain: "PerplexityFakefsInstaller", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bundled PerplexityAI resource was not found."])
            }
            try await IshFS.createDirectoryIfNeeded(path: installRoot)
            try await copyDirectory(source, toFakefsRoot: installRoot)
            try await installCommandShims()
            lastStatus = "Installed to \(installRoot)"
        } catch {
            lastStatus = error.localizedDescription
        }
    }

    private func copyDirectory(_ source: URL, toFakefsRoot root: String) async throws {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            throw NSError(domain: "PerplexityFakefsInstaller", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not enumerate PerplexityAI bundle."])
        }

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            let relative = fileURL.path.replacingOccurrences(of: source.path + "/", with: "")
            guard !relative.isEmpty else { continue }
            let target = root + "/" + relative
            if values.isDirectory == true {
                try await IshFS.createDirectoryIfNeeded(path: target)
            } else {
                try await IshFS.createDirectoryIfNeeded(path: (target as NSString).deletingLastPathComponent)
                let data = try Data(contentsOf: fileURL)
                try await IshFS.writeFile(path: target, data: data, replaceExisting: true)
            }
        }
    }

    private func installCommandShims() async throws {
        try await IshFS.createDirectoryIfNeeded(path: binRoot)
        let chat = "\(installRoot)/bin/perplexity-chat"
        let mcp = "\(installRoot)/bin/perplexity-mcp"
        let setup = "\(installRoot)/bin/perplexity-setup"
        try await IshFS.writeTextFile(path: setup, text: Self.setupScript)
        _ = await IshFS.run("chmod +x \(IshFS.shellQuote(chat)) \(IshFS.shellQuote(mcp)) \(IshFS.shellQuote(setup))")
        try await IshFS.writeTextFile(path: "\(binRoot)/perplexity-chat", text: shim(target: chat))
        try await IshFS.writeTextFile(path: "\(binRoot)/perplexity-mcp", text: shim(target: mcp))
        try await IshFS.writeTextFile(path: "\(binRoot)/perplexity-setup", text: shim(target: setup))
        _ = await IshFS.run("chmod +x /usr/local/bin/perplexity-chat /usr/local/bin/perplexity-mcp /usr/local/bin/perplexity-setup")
    }

    private func shim(target: String) -> String {
        """
        #!/bin/sh
        exec \(IshFS.shellQuote(target)) "$@"
        """
    }

    private static let setupScript = """
    #!/bin/sh
    set -eu
    if ! command -v python3 >/dev/null 2>&1; then
      echo "python3 is required. Install it in the fakefs first." >&2
      exit 1
    fi
    if ! python3 -c 'import curl_cffi' >/dev/null 2>&1; then
      python3 -m pip install --user curl_cffi websocket-client
    fi
    if [ "${1:-}" = "--mcp" ] && ! python3 -c 'import mcp' >/dev/null 2>&1; then
      python3 -m pip install --user mcp
    fi
    echo "Perplexity fakefs dependencies are ready."
    """
}
