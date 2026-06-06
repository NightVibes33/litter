import Foundation
import Network
import UIKit

final class FeatherSignedIPAInstallServer {
    private struct ServeState {
        var payloadURL: URL
        var manifestData: Data
        var iconSmallData: Data
        var iconLargeData: Data
        var installPageData: Data
    }

    private static let bindHost = "127.0.0.1"
    private let queue = DispatchQueue(label: "com.sigkitten.litter.feather-install-server")
    private let stateLock = NSLock()
    private var listener: NWListener?
    private var serveState: ServeState?
    private var shutdownWorkItem: DispatchWorkItem?

    deinit {
        stop()
    }

    func start(payloadURL: URL, bundleIdentifier: String, appName: String, appVersion: String, iconURL: URL?) throws -> URL {
        stop()

        guard FileManager.default.fileExists(atPath: payloadURL.path) else {
            throw NSError(domain: "FeatherInstallServer", code: 64, userInfo: [NSLocalizedDescriptionKey: "The signed IPA no longer exists at \(payloadURL.path)."])
        }

        let trimmedBundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBundleIdentifier.isEmpty else {
            throw NSError(domain: "FeatherInstallServer", code: 64, userInfo: [NSLocalizedDescriptionKey: "A bundle identifier is required before installing a signed IPA."])
        }

        let trimmedAppName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let installName = trimmedAppName.isEmpty ? payloadURL.deletingPathExtension().lastPathComponent : trimmedAppName
        let trimmedVersion = appVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let installVersion = trimmedVersion.isEmpty ? "1.0" : trimmedVersion

        let port = try Self.availablePort()
        let baseURL = "http://\(Self.bindHost):\(port)"
        let manifestURLString = "\(baseURL)/manifest.plist"
        let payloadURLString = "\(baseURL)/payload.ipa"
        let iconSmallURLString = "\(baseURL)/app57x57.png"
        let iconLargeURLString = "\(baseURL)/app512x512.png"
        let manifestData = try Self.makeManifestData(
            bundleIdentifier: trimmedBundleIdentifier,
            appName: installName,
            appVersion: installVersion,
            payloadURLString: payloadURLString,
            iconSmallURLString: iconSmallURLString,
            iconLargeURLString: iconLargeURLString
        )
        let encodedManifestURL = manifestURLString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? manifestURLString
        guard let installURL = URL(string: "itms-services://?action=download-manifest&url=\(encodedManifestURL)") else {
            throw NSError(domain: "FeatherInstallServer", code: 65, userInfo: [NSLocalizedDescriptionKey: "Could not build the itms-services install URL."])
        }

        let html = """
        <html><head><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"></head><body><script>window.location='\(installURL.absoluteString)'</script></body></html>
        """
        let state = ServeState(
            payloadURL: payloadURL,
            manifestData: manifestData,
            iconSmallData: Self.makeIconData(size: 57, iconURL: iconURL),
            iconLargeData: Self.makeIconData(size: 512, iconURL: iconURL),
            installPageData: Data(html.utf8)
        )

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "FeatherInstallServer", code: 65, userInfo: [NSLocalizedDescriptionKey: "Invalid local install server port."])
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(Self.bindHost), port: nwPort)
        let listener = try NWListener(using: parameters, on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.stop() }
            if case .cancelled = state { self?.clearListenerOnly() }
        }

        stateLock.lock()
        self.serveState = state
        self.listener = listener
        stateLock.unlock()

        listener.start(queue: queue)
        scheduleStop()
        return installURL
    }

    func stop() {
        let listenerToCancel: NWListener?
        stateLock.lock()
        shutdownWorkItem?.cancel()
        shutdownWorkItem = nil
        listenerToCancel = listener
        listener = nil
        serveState = nil
        stateLock.unlock()
        listenerToCancel?.cancel()
    }

    private func scheduleStop() {
        let item = DispatchWorkItem { [weak self] in self?.stop() }
        stateLock.lock()
        shutdownWorkItem = item
        stateLock.unlock()
        queue.asyncAfter(deadline: .now() + 180, execute: item)
    }

    private func clearListenerOnly() {
        stateLock.lock()
        listener = nil
        stateLock.unlock()
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
            if error != nil {
                connection.cancel()
                return
            }

            var nextBuffer = buffer
            if let data { nextBuffer.append(data) }
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
            sendData(status: 400, contentType: "text/plain; charset=UTF-8", body: Data("Bad request".utf8), on: connection)
            return
        }
        let method = parts[0].uppercased()
        let path = requestPath(from: parts[1])
        guard method == "GET" else {
            sendData(status: 405, contentType: "text/plain; charset=UTF-8", body: Data("Method not allowed".utf8), on: connection)
            return
        }
        guard let state = currentServeState() else {
            sendData(status: 503, contentType: "text/plain; charset=UTF-8", body: Data("Install server is not ready".utf8), on: connection)
            return
        }

        switch path {
        case "/manifest.plist":
            sendData(status: 200, contentType: "text/xml", body: state.manifestData, on: connection)
        case "/app57x57.png":
            sendData(status: 200, contentType: "image/png", body: state.iconSmallData, on: connection)
        case "/app512x512.png":
            sendData(status: 200, contentType: "image/png", body: state.iconLargeData, on: connection)
        case "/payload.ipa":
            sendFile(state.payloadURL, contentType: "application/octet-stream", on: connection)
        case "/install":
            sendData(status: 200, contentType: "text/html; charset=UTF-8", body: state.installPageData, on: connection)
        default:
            sendData(status: 404, contentType: "text/plain; charset=UTF-8", body: Data("Not found".utf8), on: connection)
        }
    }

    private func currentServeState() -> ServeState? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return serveState
    }

    private func requestPath(from target: String) -> String {
        if let url = URL(string: target), url.scheme != nil {
            return url.path.isEmpty ? "/" : url.path
        }
        guard let url = URL(string: "http://localhost\(target)") else { return target }
        return url.path.isEmpty ? "/" : url.path
    }

    private func sendData(status: Int, contentType: String, body: Data, on connection: NWConnection) {
        let header = Self.httpHeader(status: status, contentType: contentType, contentLength: body.count)
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendFile(_ url: URL, contentType: String, on connection: NWConnection) {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let length = (attributes[.size] as? NSNumber)?.intValue ?? 0
            let header = Self.httpHeader(status: 200, contentType: contentType, contentLength: length)
            connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] error in
                guard error == nil else {
                    try? handle.close()
                    connection.cancel()
                    return
                }
                self?.sendFileBody(handle, on: connection)
            })
        } catch {
            sendData(status: 404, contentType: "text/plain; charset=UTF-8", body: Data(error.localizedDescription.utf8), on: connection)
        }
    }

    private func sendFileBody(_ handle: FileHandle, on connection: NWConnection) {
        let chunk = handle.readData(ofLength: 512 * 1024)
        if chunk.isEmpty {
            try? handle.close()
            connection.cancel()
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard error == nil else {
                try? handle.close()
                connection.cancel()
                return
            }
            self?.sendFileBody(handle, on: connection)
        })
    }

    private static func httpHeader(status: Int, contentType: String, contentLength: Int) -> String {
        let statusLine: String
        switch status {
        case 200: statusLine = "HTTP/1.1 200 OK"
        case 400: statusLine = "HTTP/1.1 400 Bad Request"
        case 404: statusLine = "HTTP/1.1 404 Not Found"
        case 405: statusLine = "HTTP/1.1 405 Method Not Allowed"
        case 503: statusLine = "HTTP/1.1 503 Service Unavailable"
        default: statusLine = "HTTP/1.1 \(status) Error"
        }
        return [
            statusLine,
            "Content-Type: \(contentType)",
            "Cache-Control: no-store",
            "Connection: close",
            "Content-Length: \(contentLength)",
            "",
            ""
        ].joined(separator: "\r\n")
    }

    private static func makeManifestData(bundleIdentifier: String, appName: String, appVersion: String, payloadURLString: String, iconSmallURLString: String, iconLargeURLString: String) throws -> Data {
        let manifest: [String: Any] = [
            "items": [[
                "assets": [
                    ["kind": "software-package", "url": payloadURLString],
                    ["kind": "display-image", "url": iconSmallURLString],
                    ["kind": "full-size-image", "url": iconLargeURLString]
                ],
                "metadata": [
                    "bundle-identifier": bundleIdentifier,
                    "bundle-version": appVersion,
                    "kind": "software",
                    "title": appName
                ]
            ]]
        ]
        return try PropertyListSerialization.data(fromPropertyList: manifest, format: .xml, options: 0)
    }

    private static func makeIconData(size: CGFloat, iconURL: URL?) -> Data {
        let image = iconURL.flatMap { UIImage(contentsOfFile: $0.path) }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let rendered = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            if let image {
                image.draw(in: rect)
            } else {
                UIColor.systemBlue.setFill()
                context.fill(rect)
            }
        }
        return rendered.pngData() ?? Data()
    }

    private static func availablePort() throws -> UInt16 {
        for _ in 0..<20 {
            let value = UInt16(Int.random(in: 4000...8000))
            if NWEndpoint.Port(rawValue: value) != nil { return value }
        }
        throw NSError(domain: "FeatherInstallServer", code: 65, userInfo: [NSLocalizedDescriptionKey: "Could not allocate a local install server port."])
    }
}
