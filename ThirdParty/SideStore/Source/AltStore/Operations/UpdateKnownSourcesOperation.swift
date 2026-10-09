//
//  UpdateKnownSourcesOperation.swift
//  AltStore
//
//  Embedded SideStore: preserve upstream recommendations and Alley Cat additions.
//

import Foundation
import AltStoreCore

private enum CatalogURLs {
    static let upstream = URL(string: "https://raw.githubusercontent.com/SideStore/default-sources/main/sources.json")!
    static let existing = URL(string: "https://raw.githubusercontent.com/NightVibes33/litter/main/ThirdParty/SideStore/Source/trustedapps.json")!
}

extension UpdateKnownSourcesOperation {
    private struct Response: Decodable {
        var version: Int
        /// SideStore publishes recommendations under "default"; the existing
        /// Alley Cat catalog also publishes "sources" and "trusted".
        var defaultSources: [KnownSource]?
        var sources: [KnownSource]?
        var trusted: [KnownSource]?
        var blocked: [KnownSource]?

        private enum CodingKeys: String, CodingKey {
            case version, sources, trusted, blocked
            case defaultSources = "default"
        }
    }

    /// URLSession callbacks are concurrent. A lock around shared captured
    /// local vars is not sufficient for Swift 6 sendability analysis.
    private final class CatalogCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var responseMap: [URL: Response] = [:]
        private var latestError: Error?

        func record(_ response: Response, for url: URL) {
            lock.lock()
            responseMap[url] = response
            lock.unlock()
        }

        func record(_ error: Error) {
            lock.lock()
            latestError = error
            lock.unlock()
        }

        func snapshot() -> ([URL: Response], Error?) {
            lock.lock()
            defer { lock.unlock() }
            return (responseMap, latestError)
        }
    }
}

class UpdateKnownSourcesOperation: ResultOperation<([KnownSource], [KnownSource])> {
    private let session: URLSession

    override init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        if UserDefaults.standard.responseCachingDisabled {
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
        }
        session = URLSession(configuration: configuration)
    }

    override func main() {
        super.main()

        // Catalog entries are suggestions only, never silently installed.
        // The Add Source screen still needs an explicit plus/confirmation.
        let urls = [CatalogURLs.upstream, CatalogURLs.existing]
        let group = DispatchGroup()
        let collector = CatalogCollector()

        for url in urls {
            group.enter()
            session.dataTask(with: url) { data, response, error in
                defer { group.leave() }
                do {
                    if let error { throw error }
                    guard let http = response as? HTTPURLResponse,
                          (200...299).contains(http.statusCode) else {
                        throw URLError(.badServerResponse)
                    }
                    guard let data else { throw URLError(.zeroByteResource) }
                    let parsed = try JSONDecoder().decode(Response.self, from: data)
                    collector.record(parsed, for: url)
                } catch {
                    NSLog("[SideStoreSources] %@: %@", url.host ?? "unknown", error.localizedDescription)
                    collector.record(error)
                }
            }.resume()
        }

        group.notify(queue: .main) {
            let (responses, lastError) = collector.snapshot()
            var result = [KnownSource]()
            var seen = Set<String>()
            for url in urls {
                guard let response = responses[url] else { continue }
                // Keep all entries: the official "default" array is distinct
                // from the legacy "sources" array and from custom trusted feeds.
                for source in (response.defaultSources ?? [])
                    + (response.sources ?? [])
                    + (response.trusted ?? []) {
                    guard let sourceURL = source.sourceURL,
                          sourceURL.scheme?.lowercased() == "https",
                          sourceURL.host != nil else { continue }
                    let key = sourceURL.absoluteString.lowercased()
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    if seen.insert(key).inserted { result.append(source) }
                }
            }
            // Preserve both upstream and Alley Cat blocking rules, rather
            // than dropping the upstream list when the supplemental feed loads.
            var blocked: [KnownSource] = []
            var blockedIDs = Set<String>()
            for url in urls {
                for source in responses[url]?.blocked ?? [] {
                    if blockedIDs.insert(source.identifier).inserted {
                        blocked.append(source)
                    }
                }
            }
            if result.isEmpty {
                if let cached = UserDefaults.shared.recommendedSources, !cached.isEmpty {
                    self.finish(.success((cached, UserDefaults.shared.blockedSources ?? blocked)))
                } else {
                    self.finish(.failure(lastError ?? URLError(.cannotParseResponse)))
                }
                return
            }

            UserDefaults.shared.recommendedSources = result
            UserDefaults.shared.blockedSources = blocked
            UserDefaults.shared.trustedSourceIDs = result.map { $0.identifier }
            NSLog("[SideStoreSources] available recommendations: %ld", result.count)
            self.finish(.success((result, blocked)))
        }
    }
}
