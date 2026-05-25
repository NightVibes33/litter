import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Coarse-grained Apple Watch size buckets. Used to scale fonts and spacing
/// so the same layout looks right from the 40mm SE up to the 49mm Ultra.
///
/// Bucket reference (screen width in points):
/// - 40mm SE/S6      → 162
/// - 41mm S7/S8/S9   → 176
/// - 42mm S10        → 176
/// - 44mm SE/S6      → 184
/// - 45mm S7/S8/S9   → 198
/// - 46mm S10        → 200
/// - 49mm Ultra      → 205
enum WatchSize: String, CaseIterable, Hashable {
    case compact   // ≤ 165pt — 40/41/42mm
    case regular   // ≤ 195pt — 44/45/46mm
    case expanded  // > 195pt — 49mm Ultra

    /// Pure mapping from screen width → bucket. Exposed for tests.
    static func from(width: CGFloat) -> WatchSize {
        if width <= 165 { return .compact }
        if width <= 195 { return .regular }
        return .expanded
    }

    /// Multiplier applied to base font sizes via `WatchTheme.scaled(_:for:)`.
    var fontScale: CGFloat {
        switch self {
        case .compact:  return 0.9
        case .regular:  return 1.0
        case .expanded: return 1.1
        }
    }
}
