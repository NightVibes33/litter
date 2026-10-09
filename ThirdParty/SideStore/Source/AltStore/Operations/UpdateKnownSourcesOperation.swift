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
        /// SideStore's upstream catalog publishes its recommendations under "default".
        /// Alley Cat's supplemental catalog uses "sources" and "trusted".
        var defaultSources: [KnownSource]?
        var sources: [KnownSource]?
        var trusted: [KnownSource]?
        var blocked: [KnownSource]?

        private enum CodingKeys: String, CodingKey {
            case version, sources, trusted, blocked
            case defaultSources = "default"
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
        let lock = NSLock()
        var responses: [URL: Response] = [:]
        var lastError: Error?

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
                    lock.lock()
                    responses[url] = parsed
                    lock.unlock()
                } catch {
                    NSLog("[SideStoreSources] %@: %@", url.host ?? "unknown", error.localizedDescription)
                    lock.lock()
                    lastError = error
                    lock.unlock()
                }
            }.resume()
        }

        group.notify(queue: .main) {
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
