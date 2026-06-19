import Foundation

struct PerplexityModelSelection: Equatable, Sendable {
    let mode: String
    let model: String?

    static let defaultId = "perplexity:auto"
    static let `default` = PerplexityModelSelection(mode: "auto", model: nil)
    static let availableModelNames = [
        "Best",
        "Sonar 2",
        "GPT-5.4",
        "GPT-5.5 (Max sub)",
        "Gemini 3.1 Pro",
        "Claude Sonnet 4.6",
        "Claude Opus 4.8",
        "Kimi K2.6 New (Max sub)",
        "Nemotron 3 Ultra (New)"
    ]

    init(mode: String, model: String?) {
        self.mode = mode
        self.model = model
    }

    init(modelId: String?) {
        let raw = modelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard raw.hasPrefix("perplexity:") else {
            self = .default
            return
        }
        let payload = String(raw.dropFirst("perplexity:".count))
        let pieces = payload.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let mode = pieces.first.map(String.init)?.replacingOccurrences(of: "-", with: " ") ?? "auto"
        let model = pieces.count > 1 ? String(pieces[1]) : ""
        self.mode = mode.isEmpty ? "auto" : mode
        self.model = model.isEmpty || model == "default" ? nil : model
    }
}

@MainActor
final class PerplexityFakefsInstaller: ObservableObject {
    static let shared = PerplexityFakefsInstaller()

    @Published private(set) var isInstalling = false
    @Published private(set) var lastStatus = "Not installed"
    @Published private(set) var isProxyRunning = false

    private let installRoot = "/root/alley-cat/perplexity-ai"
    private let binRoot = "/usr/local/bin"

    private init() {}

    func healthReport() async -> AIProviderHealthReport {
        guard !AppDistributionCapabilities.isAppStoreSafe else {
            return AIProviderHealthReport(status: .failed("Perplexity chat runtime is not included in TestFlight builds."), models: [])
        }
        let packageCheck = await IshFS.run("test -f /root/alley-cat/perplexity-ai/upstream/perplexity/client.py && test -x /usr/local/bin/perplexity-chat")
        if packageCheck.exitCode == 0 {
            return AIProviderHealthReport(status: .healthy, models: PerplexityModelSelection.availableModelNames)
        }
        return AIProviderHealthReport(status: .warning("Tap Install Perplexity Runtime to copy the Perplexity bundle into iSH."), models: [])
    }

    func ask(_ prompt: String, account: PerplexityAccount?, selection: PerplexityModelSelection = .default, onUpdate: ((String) -> Void)? = nil) async throws -> String {
        guard !AppDistributionCapabilities.isAppStoreSafe else {
            throw NSError(domain: "PerplexityFakefsInstaller", code: 3, userInfo: [NSLocalizedDescriptionKey: "Perplexity is not included in TestFlight builds."])
        }
        await install()
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "PerplexityFakefsInstaller", code: 4, userInfo: [NSLocalizedDescriptionKey: "Perplexity prompt was empty."])
        }
        let cookiesPath = "/root/.config/alley-cat/perplexity-cookies.json"
        if let account {
            try await IshFS.createDirectoryIfNeeded(path: "/root/.config/alley-cat")
            try await IshFS.writeTextFile(path: cookiesPath, text: account.cookiesJSON + "\n")
        }
        
        if let onUpdate {
            return try await askStreaming(trimmed: trimmed, cookiesPath: cookiesPath, selection: selection, onUpdate: onUpdate)
        }
        
        let command = "PERPLEXITY_COOKIES_FILE=\(IshFS.shellQuote(cookiesPath)) /usr/local/bin/perplexity-chat \(IshFS.shellQuote(trimmed)) \(IshFS.shellQuote(selection.mode)) \(IshFS.shellQuote(selection.model ?? "default"))"
        let result = await IshFS.run(command)
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0 else {
            throw NSError(domain: "PerplexityFakefsInstaller", code: Int(result.exitCode), userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? "Perplexity command failed." : output])
        }
        return output.isEmpty ? "Perplexity returned an empty response." : output
    }

    private func askStreaming(trimmed: String, cookiesPath: String, selection: PerplexityModelSelection, onUpdate: (String) -> Void) async throws -> String {
        let runId = UUID().uuidString
        let outPath = "/tmp/perplexity-\(runId).out"
        let donePath = "/tmp/perplexity-\(runId).done"
        
        let script = """
        rm -f \(IshFS.shellQuote(outPath)) \(IshFS.shellQuote(donePath))
        (
          PERPLEXITY_COOKIES_FILE=\(IshFS.shellQuote(cookiesPath)) /usr/local/bin/perplexity-chat \(IshFS.shellQuote(trimmed)) \(IshFS.shellQuote(selection.mode)) \(IshFS.shellQuote(selection.model ?? "default")) --stream > \(IshFS.shellQuote(outPath)) 2>&1
          echo $? > \(IshFS.shellQuote(donePath))
        ) &
        """
        _ = await IshFS.run(script)
        
        var finalAnswer = ""
        var isDone = false
        var failed = false
        var exitCode = 0
        var errorOutput = ""
        
        while !isDone && !Task.isCancelled {
            try await Task.sleep(nanoseconds: 300_000_000)
            
            let doneCheck = await IshFS.run("cat \(IshFS.shellQuote(donePath)) 2>/dev/null")
            if doneCheck.exitCode == 0 {
                isDone = true
                exitCode = Int(doneCheck.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                if exitCode != 0 { failed = true }
            }
            
            let readRes = await IshFS.run("cat \(IshFS.shellQuote(outPath)) 2>/dev/null")
            if readRes.exitCode == 0 {
                let newText = readRes.output
                let lines = newText.components(separatedBy: "\n")
                errorOutput = ""
                for line in lines {
                    let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedLine.isEmpty { continue }
                    if trimmedLine.hasPrefix("{") {
                        if let data = trimmedLine.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let answer = json["answer"] as? String {
                            finalAnswer = answer
                        }
                    } else {
                        errorOutput += trimmedLine + "\n"
                    }
                }
                if !finalAnswer.isEmpty {
                    onUpdate(finalAnswer)
                }
            }
        }
        
        _ = await IshFS.run("rm -f \(IshFS.shellQuote(outPath)) \(IshFS.shellQuote(donePath))")
        
        if failed {
            let err = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(domain: "PerplexityFakefsInstaller", code: exitCode, userInfo: [NSLocalizedDescriptionKey: err.isEmpty ? "Perplexity command failed." : err])
        }
        
        return finalAnswer.isEmpty ? "Perplexity returned an empty response." : finalAnswer
    }


    func configureMCP(account: PerplexityAccount?) async throws {
        guard !AppDistributionCapabilities.isAppStoreSafe else {
            throw NSError(domain: "PerplexityFakefsInstaller", code: 5, userInfo: [NSLocalizedDescriptionKey: "Perplexity MCP is not included in TestFlight builds."])
        }
        await install()
        let setupResult = await IshFS.run("/usr/local/bin/perplexity-setup --mcp")
        guard setupResult.exitCode == 0 else {
            let output = setupResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(domain: "PerplexityFakefsInstaller", code: Int(setupResult.exitCode), userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? "Could not install Perplexity MCP dependencies." : output])
        }
        let cookiesPath = "/root/.config/alley-cat/perplexity-cookies.json"
        try await IshFS.createDirectoryIfNeeded(path: "/root/.config/alley-cat")
        if let account {
            try await IshFS.writeTextFile(path: cookiesPath, text: account.cookiesJSON + "\n")
        }
        let configBlock = Self.mcpConfigBlock(cookiesPath: cookiesPath)
        let script = """
        set -eu
        mkdir -p /root/.codex
        config=/root/.codex/config.toml
        tmp="$config.tmp.$$"
        if [ -f "$config" ]; then
          awk '\n            /^# BEGIN ALLEY_CAT_PERPLEXITY_MCP$/ {skip=1; next}\n            /^# END ALLEY_CAT_PERPLEXITY_MCP$/ {skip=0; next}\n            skip != 1 {print}\n          ' "$config" > "$tmp"
        else
          : > "$tmp"
        fi
        cat >> "$tmp" <<'ALLEY_CAT_PERPLEXITY_MCP'
        \(configBlock)
        ALLEY_CAT_PERPLEXITY_MCP
        mv "$tmp" "$config"
        chmod 600 "$config" 2>/dev/null || true
        echo "Configured Perplexity MCP in $config"
        """
        let result = await IshFS.run(script)
        guard result.exitCode == 0 else {
            let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(domain: "PerplexityFakefsInstaller", code: Int(result.exitCode), userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? "Could not configure Perplexity MCP." : output])
        }
        lastStatus = "Perplexity MCP configured"
    }

    func install() async {
        guard !AppDistributionCapabilities.isAppStoreSafe else {
            lastStatus = "Perplexity chat runtime is sideload-only."
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


    private static func mcpConfigBlock(cookiesPath: String) -> String {
        """
        # BEGIN ALLEY_CAT_PERPLEXITY_MCP
        [mcp_servers.perplexity]
        command = "/usr/local/bin/perplexity-mcp"
        env = { PERPLEXITY_COOKIES_FILE = "\(cookiesPath)" }
        # END ALLEY_CAT_PERPLEXITY_MCP
        """
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
        let proxy = "\(installRoot)/bin/perplexity-openai-proxy"
        let setup = "\(installRoot)/bin/perplexity-setup"
        try await IshFS.writeTextFile(path: setup, text: Self.setupScript)
        _ = await IshFS.run("chmod +x \(IshFS.shellQuote(chat)) \(IshFS.shellQuote(mcp)) \(IshFS.shellQuote(proxy)) \(IshFS.shellQuote(setup))")
        try await IshFS.writeTextFile(path: "\(binRoot)/perplexity-chat", text: shim(target: chat))
        try await IshFS.writeTextFile(path: "\(binRoot)/perplexity-mcp", text: shim(target: mcp))
        try await IshFS.writeTextFile(path: "\(binRoot)/perplexity-openai-proxy", text: shim(target: proxy))
        try await IshFS.writeTextFile(path: "\(binRoot)/perplexity-setup", text: shim(target: setup))
        _ = await IshFS.run("chmod +x /usr/local/bin/perplexity-chat /usr/local/bin/perplexity-mcp /usr/local/bin/perplexity-openai-proxy /usr/local/bin/perplexity-setup")
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

    func startOpenAIProxy(account: PerplexityAccount?) async {
        let cookiesPath = "/root/.config/alley-cat/perplexity-cookies.json"
        if let account {
            try? await IshFS.createDirectoryIfNeeded(path: "/root/.config/alley-cat")
            try? await IshFS.writeTextFile(path: cookiesPath, text: account.cookiesJSON + "\n")
        }
        let script = """
        export PERPLEXITY_COOKIES_FILE=\(IshFS.shellQuote(cookiesPath))
        export PROXY_PORT=8001
        nohup /usr/local/bin/perplexity-openai-proxy >/tmp/perplexity-proxy.log 2>&1 &
        """
        _ = await IshFS.run(script)
        isProxyRunning = true
    }

    func stopOpenAIProxy() async {
        _ = await IshFS.run("pkill -f perplexity-openai-proxy")
        isProxyRunning = false
    }

    func checkProxyStatus() async {
        let res = await IshFS.run("pgrep -f perplexity-openai-proxy")
        isProxyRunning = (res.exitCode == 0)
    }
}
