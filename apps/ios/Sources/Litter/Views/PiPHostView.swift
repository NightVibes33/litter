import AVFoundation
import UIKit

/// `UIView` whose backing layer is an `AVSampleBufferDisplayLayer` — the
/// surface `AVPictureInPictureController` (custom content variant) renders.
///
/// The view is added to the key window at 1×1 off-screen; the PiP layer
/// must be hosted in a window for `startPictureInPicture()` to succeed, but
/// the host view itself never needs to be visible.
final class PiPHostView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    var displayLayer: AVSampleBufferDisplayLayer {
        // swiftlint:disable:next force_cast
        layer as! AVSampleBufferDisplayLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .black
        displayLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unused") }
}
