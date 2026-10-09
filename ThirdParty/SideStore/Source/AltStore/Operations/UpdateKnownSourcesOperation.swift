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
        var sources: [KnownSource]?
        var trusted: [KnownSource]?
        var blocked: [KnownSource]?
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
                for source in response.sources ?? response.trusted ?? [] {
                    guard let sourceURL = source.sourceURL,
                          sourceURL.scheme?.lowercased() == "https",
                          sourceURL.host != nil else { continue }
                    let key = sourceURL.absoluteString.lowercased()
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    if seen.insert(key).inserted { result.append(source) }
                }
            }
            let blocked = responses[CatalogURLs.existing]?.blocked ?? []
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
