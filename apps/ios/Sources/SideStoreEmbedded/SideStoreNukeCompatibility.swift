import Foundation
import Intents
import Nuke
import UIKit

struct ImageLoadingOptions {
    static let shared = ImageLoadingOptions()
}

extension ImagePipeline {
    @discardableResult
    func loadImage(
        with url: URL,
        progress: ((_ response: ImageResponse?, _ completed: Int64, _ total: Int64) -> Void)?,
        completion: @escaping (_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void
    ) -> ImageTask {
        loadImage(with: ImageRequest(url: url), queue: nil, progress: progress, completion: completion)
    }
}

extension ImageCache {
    subscript(url: URL) -> ImageContainer? {
        get { self[ImageCacheKey(request: ImageRequest(url: url))] }
        set { self[ImageCacheKey(request: ImageRequest(url: url))] = newValue }
    }
}

enum Nuke {
    @discardableResult
    static func loadImage(
        with url: URL?,
        options: ImageLoadingOptions? = nil,
        into view: UIImageView,
        progress: ((_ response: ImageResponse?, _ completed: Int64, _ total: Int64) -> Void)? = nil,
        completion: ((_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void)? = nil
    ) -> ImageTask? {
        guard let url else { return nil }
        return ImagePipeline.shared.loadImage(with: ImageRequest(url: url), queue: nil, progress: progress) { result in
            if case .success(let response) = result {
                DispatchQueue.main.async {
                    view.image = response.image
                }
            }
            completion?(result)
        }
    }
}

final class RefreshAllIntent: INIntent {}

extension INInteraction {
    static func refreshAllApps() -> INInteraction {
        let intent = RefreshAllIntent()
        intent.suggestedInvocationPhrase = NSString.deferredLocalizedIntentsString(with: "Refresh my apps") as String
        return INInteraction(intent: intent, response: nil)
    }
}
