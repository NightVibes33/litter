import Foundation
import Observation
import HairballUI
import SwiftUI

enum StreamingEffectKind: String, CaseIterable, Identifiable {
    case fadeEdge = "Fade Edge"
    case sparkle = "Sparkle"
    case glowCursor = "Glow Cursor"
    case wave = "Wave"
    case scalePop = "Scale Pop"
    case rainbow = "Rainbow"
    case fireTrail = "Fire Trail"
    case explosion = "Explosion"
    case nyanCat = "Nyan Cat"
    case matrixDecode = "Matrix Decode"
    case phosphorCRT = "Phosphor CRT"
    case shockwave = "Shockwave"
    case typewriter = "Typewriter"
    case terminalScan = "Terminal Scan"
    case softBlur = "Soft Blur"
    case neonPulse = "Neon Pulse"
    case ghostTrail = "Ghost Trail"
    case pixelDecode = "Pixel Decode"
    case inkSpread = "Ink Spread"
    case slideUp = "Slide Up"
    case glitch = "Glitch"
    case focusBeam = "Focus Beam"

    var id: String { rawValue }

    var effect: any StreamingTextEffect {
        let accent = Color(red: 0, green: 1, blue: 0.612)
        switch self {
        case .fadeEdge: return FadeEdgeEffect(edgeWidth: 4)
        case .sparkle: return SparkleEffect(sparkleCount: 8, color: accent)
        case .glowCursor: return GlowCursorEffect(glowColor: accent, glowRadius: 8)
        case .wave: return WaveRevealEffect(amplitude: 4, wavelength: 8)
        case .scalePop: return ScalePopEffect(popWidth: 3)
        case .rainbow: return RainbowEffect(trailLength: 12)
        case .fireTrail: return FireTrailEffect(trailLength: 15)
        case .explosion: return ExplosionEffect()
        case .nyanCat: return NyanCatEffect()
        case .matrixDecode: return MatrixDecodeEffect()
        case .phosphorCRT: return PhosphorCRTEffect()
        case .shockwave: return ShockwaveEffect()
        case .typewriter: return FadeEdgeEffect(edgeWidth: 1)
        case .terminalScan: return GlowCursorEffect(glowColor: accent, glowRadius: 3)
        case .softBlur: return FadeEdgeEffect(edgeWidth: 10)
        case .neonPulse: return GlowCursorEffect(glowColor: accent, glowRadius: 16)
        case .ghostTrail: return SparkleEffect(sparkleCount: 3, color: accent.opacity(0.55))
        case .pixelDecode: return MatrixDecodeEffect()
        case .inkSpread: return ScalePopEffect(popWidth: 1)
        case .slideUp: return WaveRevealEffect(amplitude: 2, wavelength: 18)
        case .glitch: return ShockwaveEffect()
        case .focusBeam: return RainbowEffect(trailLength: 4)
        }
    }
}

@Observable
final class DebugSettings {
    static let shared = DebugSettings()

    @ObservationIgnored private let key = "litter.debugSettings"
    private var overrides: [String: Bool]

    private init() {
        overrides = UserDefaults.standard.dictionary(forKey: key) as? [String: Bool] ?? [:]
    }

    private func persist() {
        UserDefaults.standard.set(overrides, forKey: key)
    }

    var enabled: Bool {
        get { overrides["enabled"] ?? false }
        set { overrides["enabled"] = newValue; persist() }
    }

    var showTurnMetrics: Bool {
        get { overrides["showTurnMetrics"] ?? false }
        set { overrides["showTurnMetrics"] = newValue; persist() }
    }

    var disableMarkdown: Bool {
        get { overrides["disableMarkdown"] ?? false }
        set { overrides["disableMarkdown"] = newValue; persist() }
    }
}
