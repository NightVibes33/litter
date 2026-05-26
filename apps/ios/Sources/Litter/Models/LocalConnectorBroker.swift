import Foundation
import Network
import Security

/// Local-only connector broker surface for the on-device Codex/iSH runtime.
/// This intentionally exposes connector metadata and broker routing, not raw
/// provider tokens. Provider tokens stay in Keychain/native stores.
final class LocalConnectorBroker: @unchecked Sendable {
    static let shared = LocalConnectorBroker()

    static let bindHost = "127.0.0.1"
    static let port: UInt16 = 1456
    static let manifestPath = "/root/.litter/connectors/broker.json"

    private let queue = DispatchQueue(label: "com.sigkitten.litter.connector-broker")
    private let stateLock = NSLock()
    private let bearerToken = LocalConnectorBroker.makeBearerToken()
    private var listener: NWListener?
    private var isRunning = false

    private init() {}

    var baseURLString: String {
        "http://\(Self.bindHost):\(Self.port)"
    }

    func start() {
        stateLock.lock()
        if isRunning {
            stateLock.unlock()
            return
        }
        isRunning = true
        stateLock.unlock()

        do {
            guard let nwPort = NWEndpoint.Port(rawValue: Self.port) else {
                throw NSError(domain: "LocalConnectorBroker", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid connector broker port"
                ])
            }
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(Self.bindHost), port: nwPort)
            let listener = try NWListener(using: parameters, on: nwPort)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    LLog.info("connectors", "local connector broker ready", fields: [
                        "baseURL": self.baseURLString,
                        "manifestPath": Self.manifestPath
                    ])
                    Task { await self.publishManifest() }
                case .failed(let error):
                    LLog.warn("connectors", "local connector broker failed", fields: [
                        "error": error.localizedDescription
                    ])
                    self.clearListener()
                case .cancelled:
                    self.clearListener()
                default:
                    break
                }
            }

            stateLock.lock()
            self.listener = listener
            stateLock.unlock()
            listener.start(queue: queue)
        } catch {
            LLog.warn("connectors", "local connector broker could not start", fields: [
                "error": error.localizedDescription
            ])
            clearListener()
        }
    }

    func stop() {
        let listener = withStateLock { () -> NWListener? in
            isRunning = false
            let listener = self.listener
            self.listener = nil
            return listener
        }
        listener?.cancel()
        Task { await self.unpublishManifest() }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if let error {
                LLog.warn("connectors", "connector broker receive failed", fields: [
                    "error": error.localizedDescription
                ])
                connection.cancel()
                return
            }

            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            if nextBuffer.range(of: Data("\r\n\r\n".utf8)) != nil || isComplete {
                self.processRequestData(nextBuffer, on: connection)
                return
            }

            self.receiveRequest(on: connection, buffer: nextBuffer)
        }
    }

    private func processRequestData(_ data: Data, on connection: NWConnection) {
        let requestText = String(decoding: data, as: UTF8.self)
        let requestLine = requestText.components(separatedBy: "\r\n").first ?? ""
        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else {
            sendJSON(status: 400, value: errorPayload("bad_request", "Invalid HTTP request."), on: connection)
            return
        }

        let method = parts[0].uppercased()
        let path = requestPath(from: parts[1])
        switch (method, path) {
        case ("GET", "/health"), ("GET", "/v1/health"):
            sendJSON(status: 200, value: healthPayload(), on: connection)
        case ("GET", "/connectors"), ("GET", "/v1/connectors"):
            sendJSON(status: 200, value: connectorsPayload(), on: connection)
        case ("GET", "/session"), ("GET", "/v1/session"):
            guard isAuthorized(requestText) else {
                sendJSON(status: 401, value: errorPayload("unauthorized", "Missing connector broker bearer token."), on: connection)
                return
            }
            sendJSON(status: 200, value: sessionPayload(), on: connection)
        case ("GET", "/tokens"), ("GET", "/v1/tokens"):
            sendJSON(status: 403, value: errorPayload("tokens_not_exposed", "Connector tokens are intentionally not exposed over HTTP."), on: connection)
        default:
            sendJSON(status: 404, value: errorPayload("not_found", "Unknown connector broker endpoint."), on: connection)
        }
    }

    private func healthPayload() -> LocalConnectorBrokerHealthResponse {
        LocalConnectorBrokerHealthResponse(
            ok: true,
            service: "litter-local-connector-broker",
            version: 1,
            baseURL: baseURLString,
            manifestPath: Self.manifestPath,
            tokenRequired: true
        )
    }

    private func connectorsPayload() -> LocalConnectorBrokerConnectorsResponse {
        LocalConnectorBrokerConnectorsResponse(
            ok: true,
            version: 1,
            relayMode: "local-native-broker",
            connectors: Self.connectorCatalog
        )
    }

    private func sessionPayload() -> LocalConnectorBrokerSessionResponse {
        LocalConnectorBrokerSessionResponse(
            ok: true,
            version: 1,
            baseURL: baseURLString,
            authorization: "Bearer <redacted>",
            connectorsURL: "\(baseURLString)/v1/connectors",
            healthURL: "\(baseURLString)/v1/health"
        )
    }

    private func errorPayload(_ code: String, _ message: String) -> LocalConnectorBrokerErrorResponse {
        LocalConnectorBrokerErrorResponse(ok: false, error: .init(code: code, message: message))
    }

    private func publishManifest() async {
        let manifest = LocalConnectorBrokerManifest(
            version: 1,
            service: "litter-local-connector-broker",
            baseURL: baseURLString,
            authorizationHeader: "Bearer \(bearerToken)",
            healthURL: "\(baseURLString)/v1/health",
            connectorsURL: "\(baseURLString)/v1/connectors",
            sessionURL: "\(baseURLString)/v1/session"
        )
        do {
            let data = try JSONEncoder.litterConnectorBroker.encode(manifest)
            guard let text = String(data: data, encoding: .utf8) else { return }
            _ = await IshFS.run("mkdir -p /root/.litter/connectors")
            try await IshFS.writeTextFile(path: Self.manifestPath, text: text + "\n")
        } catch {
            LLog.warn("connectors", "failed to publish connector broker manifest", fields: [
                "error": error.localizedDescription
            ])
        }
    }

    private func unpublishManifest() async {
        _ = await IshFS.run("rm -f \(IshFS.shellQuote(Self.manifestPath))")
    }

    private func requestPath(from target: String) -> String {
        if let url = URL(string: target), url.scheme != nil {
            return url.path.isEmpty ? "/" : url.path
        }
        guard let url = URL(string: "http://localhost\(target)") else { return target }
        return url.path.isEmpty ? "/" : url.path
    }

    private func isAuthorized(_ requestText: String) -> Bool {
        let expected = "bearer \(bearerToken)"
        for line in requestText.components(separatedBy: "\r\n") {
            let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized == "authorization: \(expected)" {
                return true
            }
        }
        return false
    }

    private func sendJSON<T: Encodable>(status: Int, value: T, on connection: NWConnection) {
        let body: Data
        do {
            body = try JSONEncoder.litterConnectorBroker.encode(value)
        } catch {
            body = Data("{\"ok\":false,\"error\":{\"code\":\"encoding_failed\",\"message\":\"Could not encode response.\"}}".utf8)
        }
        let statusLine: String
        switch status {
        case 200: statusLine = "HTTP/1.1 200 OK"
        case 400: statusLine = "HTTP/1.1 400 Bad Request"
        case 401: statusLine = "HTTP/1.1 401 Unauthorized"
        case 403: statusLine = "HTTP/1.1 403 Forbidden"
        case 404: statusLine = "HTTP/1.1 404 Not Found"
        default: statusLine = "HTTP/1.1 \(status) Error"
        }
        let header = [
            statusLine,
            "Content-Type: application/json; charset=UTF-8",
            "Cache-Control: no-store",
            "Connection: close",
            "Content-Length: \(body.count)",
            "",
            ""
        ].joined(separator: "\r\n")
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func clearListener() {
        let listener = withStateLock { () -> NWListener? in
            isRunning = false
            let listener = self.listener
            self.listener = nil
            return listener
        }
        listener?.cancel()
    }

    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    private static func makeBearerToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { rawBuffer in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, rawBuffer.baseAddress!)
        }
        if status != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static let connectorCatalog: [LocalConnectorBrokerConnector] = [
        .init(id: "github", name: "GitHub", provider: "github", authMode: "nativeOAuthOrRelay", status: "notConfigured"),
        .init(id: "gmail", name: "Gmail", provider: "google", authMode: "nativeOAuthOrRelay", status: "notConfigured"),
        .init(id: "google-drive", name: "Google Drive", provider: "google", authMode: "nativeOAuthOrRelay", status: "notConfigured"),
        .init(id: "slack", name: "Slack", provider: "slack", authMode: "vercelRelay", status: "relayRequired"),
        .init(id: "notion", name: "Notion", provider: "notion", authMode: "vercelRelay", status: "relayRequired"),
        .init(id: "linear", name: "Linear", provider: "linear", authMode: "nativeOAuthOrRelay", status: "notConfigured"),
        .init(id: "figma", name: "Figma", provider: "figma", authMode: "manualTokenOrRelay", status: "notConfigured"),
        .init(id: "canva", name: "Canva", provider: "canva", authMode: "vercelRelay", status: "relayRequired"),
        .init(id: "outlook", name: "Outlook", provider: "microsoft", authMode: "nativeOAuthOrRelay", status: "notConfigured"),
        .init(id: "teams", name: "Teams", provider: "microsoft", authMode: "nativeOAuthOrRelay", status: "notConfigured"),
        .init(id: "sharepoint", name: "SharePoint", provider: "microsoft", authMode: "nativeOAuthOrRelay", status: "notConfigured"),
        .init(id: "vercel", name: "Vercel", provider: "vercel", authMode: "manualToken", status: "notConfigured"),
        .init(id: "openai-developers", name: "OpenAI Developers", provider: "openai", authMode: "manualToken", status: "notConfigured")
    ]
}

private struct LocalConnectorBrokerManifest: Codable {
    let version: Int
    let service: String
    let baseURL: String
    let authorizationHeader: String
    let healthURL: String
    let connectorsURL: String
    let sessionURL: String
}

private struct LocalConnectorBrokerHealthResponse: Codable {
    let ok: Bool
    let service: String
    let version: Int
    let baseURL: String
    let manifestPath: String
    let tokenRequired: Bool
}

private struct LocalConnectorBrokerConnectorsResponse: Codable {
    let ok: Bool
    let version: Int
    let relayMode: String
    let connectors: [LocalConnectorBrokerConnector]
}

private struct LocalConnectorBrokerConnector: Codable {
    let id: String
    let name: String
    let provider: String
    let authMode: String
    let status: String
}

private struct LocalConnectorBrokerSessionResponse: Codable {
    let ok: Bool
    let version: Int
    let baseURL: String
    let authorization: String
    let connectorsURL: String
    let healthURL: String
}

private struct LocalConnectorBrokerErrorResponse: Codable {
    struct ErrorBody: Codable {
        let code: String
        let message: String
    }

    let ok: Bool
    let error: ErrorBody
}

private extension JSONEncoder {
    static var litterConnectorBroker: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
