import SwiftUI
import HairballUI

private enum LitterStreamingEffectSupport {
    static func trailLength(_ requested: Int, revealedCount: Int) -> Int {
        max(1, min(max(requested, 1), max(revealedCount, 1)))
    }

    static func isInTrail(index: Int, revealedCount: Int, trailLength: Int) -> Bool {
        index >= max(0, revealedCount - trailLength) && index < revealedCount
    }

    static func progress(index: Int, revealedCount: Int, trailLength: Int) -> Double {
        let distance = max(0, revealedCount - 1 - index)
        let denominator = max(1, trailLength - 1)
        return min(1, max(0, 1 - Double(distance) / Double(denominator)))
    }

    static func rect(origin: CGPoint, width: CGFloat, ascent: CGFloat, descent: CGFloat) -> CGRect {
        CGRect(
            x: origin.x,
            y: origin.y - ascent,
            width: max(width, 1),
            height: max(ascent + descent, 1)
        )
    }
}

struct LitterTypewriterEffect: StreamingTextEffect {
    let cursorColor: Color

    init(cursorColor: Color = Color(red: 0.0, green: 1.0, blue: 0.612)) {
        self.cursorColor = cursorColor
    }

    func draw(layout: Text.Layout, revealedCount: Int, settledCount: Int, time: Double, in ctx: inout GraphicsContext) {
        var cursorRect: CGRect?
        forEachSlice(in: layout, { index, slice, context in
            guard index < revealedCount else { return false }
            let bounds = slice.typographicBounds
            cursorRect = LitterStreamingEffectSupport.rect(
                origin: bounds.origin,
                width: bounds.width,
                ascent: bounds.ascent,
                descent: bounds.descent
            )
            context.draw(slice)
            return true
        }, context: &ctx)

        guard let cursorRect, Int(time * 2.5).isMultiple(of: 2) else { return }
        let cursor = CGRect(
            x: cursorRect.maxX + 2,
            y: cursorRect.minY,
            width: 2,
            height: cursorRect.height
        )
        ctx.drawLayer { layer in
            layer.fill(Path(cursor), with: .color(cursorColor.opacity(0.95)))
            layer.addFilter(.blur(radius: 0.35))
        }
    }
}

struct LitterTerminalScanEffect: StreamingTextEffect {
    let scanColor: Color
    let trailLength: Int

    init(scanColor: Color = Color(red: 0.0, green: 1.0, blue: 0.612), trailLength: Int = 18) {
        self.scanColor = scanColor
        self.trailLength = trailLength
    }

    func draw(layout: Text.Layout, revealedCount: Int, settledCount: Int, time: Double, in ctx: inout GraphicsContext) {
        let trail = LitterStreamingEffectSupport.trailLength(trailLength, revealedCount: revealedCount)
        var activeBounds: CGRect?
        var cursorRect: CGRect?

        forEachSlice(in: layout, { index, slice, context in
            guard index < revealedCount else { return false }
            let bounds = slice.typographicBounds
            let rect = LitterStreamingEffectSupport.rect(origin: bounds.origin, width: bounds.width, ascent: bounds.ascent, descent: bounds.descent)
            let active = LitterStreamingEffectSupport.isInTrail(index: index, revealedCount: revealedCount, trailLength: trail)

            if active {
                let strength = LitterStreamingEffectSupport.progress(index: index, revealedCount: revealedCount, trailLength: trail)
                activeBounds = activeBounds.map { $0.union(rect) } ?? rect
                cursorRect = rect
                context.drawLayer { layer in
                    layer.opacity = 0.35 + strength * 0.65
                    layer.addFilter(.colorMultiply(scanColor))
                    layer.draw(slice)
                }
            } else {
                context.draw(slice)
            }
            return true
        }, context: &ctx)

        guard let activeBounds, let cursorRect else { return }
        let scanY = cursorRect.midY + CGFloat(sin(time * 18.0)) * 2
        ctx.drawLayer { layer in
            layer.fill(Path(CGRect(x: activeBounds.minX - 3, y: scanY, width: activeBounds.width + 8, height: 2)), with: .color(scanColor.opacity(0.8)))
            layer.fill(Path(CGRect(x: cursorRect.maxX + 1, y: cursorRect.minY - 2, width: 2, height: cursorRect.height + 4)), with: .color(scanColor.opacity(0.95)))
            layer.addFilter(.blur(radius: 1.0))
        }
    }
}

struct LitterSoftBlurEffect: StreamingTextEffect {
    let trailLength: Int

    init(trailLength: Int = 12) {
        self.trailLength = trailLength
    }

    func draw(layout: Text.Layout, revealedCount: Int, settledCount: Int, time: Double, in ctx: inout GraphicsContext) {
        let trail = LitterStreamingEffectSupport.trailLength(trailLength, revealedCount: revealedCount)
        forEachSlice(in: layout, { index, slice, context in
            guard index < revealedCount else { return false }
            guard LitterStreamingEffectSupport.isInTrail(index: index, revealedCount: revealedCount, trailLength: trail) else {
                context.draw(slice)
                return true
            }

            let progress = LitterStreamingEffectSupport.progress(index: index, revealedCount: revealedCount, trailLength: trail)
            context.drawLayer { layer in
                layer.opacity = 0.45 + progress * 0.55
                layer.addFilter(.blur(radius: CGFloat((1 - progress) * 5.5)))
                layer.draw(slice)
            }
            return true
        }, context: &ctx)
    }
}

struct LitterNeonPulseEffect: StreamingTextEffect {
    let color: Color
    let trailLength: Int

    init(color: Color = Color(red: 0.0, green: 0.95, blue: 1.0), trailLength: Int = 14) {
        self.color = color
        self.trailLength = trailLength
    }

    func draw(layout: Text.Layout, revealedCount: Int, settledCount: Int, time: Double, in ctx: inout GraphicsContext) {
        let trail = LitterStreamingEffectSupport.trailLength(trailLength, revealedCount: revealedCount)
        let pulse = 0.65 + 0.35 * sin(time * 8.0)
        forEachSlice(in: layout, { index, slice, context in
            guard index < revealedCount else { return false }
            guard LitterStreamingEffectSupport.isInTrail(index: index, revealedCount: revealedCount, trailLength: trail) else {
                context.draw(slice)
                return true
            }

            let strength = LitterStreamingEffectSupport.progress(index: index, revealedCount: revealedCount, trailLength: trail) * pulse
            context.drawLayer { layer in
                layer.opacity = 0.35 + strength * 0.45
                layer.addFilter(.colorMultiply(color))
                layer.addFilter(.blur(radius: CGFloat(3 + strength * 5)))
                layer.draw(slice)
            }
            context.drawLayer { layer in
                layer.opacity = 0.75 + strength * 0.25
                layer.addFilter(.colorMultiply(color))
                layer.draw(slice)
            }
            return true
        }, context: &ctx)
    }
}

struct LitterGhostTrailEffect: StreamingTextEffect {
    let trailLength: Int
    let color: Color

    init(trailLength: Int = 16, color: Color = Color(red: 0.68, green: 0.88, blue: 1.0)) {
        self.trailLength = trailLength
        self.color = color
    }

    func draw(layout: Text.Layout, revealedCount: Int, settledCount: Int, time: Double, in ctx: inout GraphicsContext) {
        let trail = LitterStreamingEffectSupport.trailLength(trailLength, revealedCount: revealedCount)
        forEachSlice(in: layout, { index, slice, context in
            guard index < revealedCount else { return false }
            guard LitterStreamingEffectSupport.isInTrail(index: index, revealedCount: revealedCount, trailLength: trail) else {
                context.draw(slice)
                return true
            }

            let strength = LitterStreamingEffectSupport.progress(index: index, revealedCount: revealedCount, trailLength: trail)
            for step in 1...3 {
                var ghost = context
                ghost.opacity = (0.32 / Double(step)) * strength
                ghost.translateBy(x: CGFloat(-step * 4), y: CGFloat(step) * 1.2)
                ghost.addFilter(.colorMultiply(color))
                ghost.draw(slice)
            }
            context.draw(slice)
            return true
        }, context: &ctx)
    }
}

struct LitterPixelDecodeEffect: StreamingTextEffect {
    let trailLength: Int
    let color: Color

    init(trailLength: Int = 12, color: Color = Color(red: 0.3, green: 0.9, blue: 1.0)) {
        self.trailLength = trailLength
        self.color = color
    }

    func draw(layout: Text.Layout, revealedCount: Int, settledCount: Int, time: Double, in ctx: inout GraphicsContext) {
        let trail = LitterStreamingEffectSupport.trailLength(trailLength, revealedCount: revealedCount)
        let frame = Int(time * 24.0)
        forEachSlice(in: layout, { index, slice, context in
            guard index < revealedCount else { return false }
            guard LitterStreamingEffectSupport.isInTrail(index: index, revealedCount: revealedCount, trailLength: trail) else {
                context.draw(slice)
                return true
            }

            let bounds = slice.typographicBounds
            let rect = LitterStreamingEffectSupport.rect(origin: bounds.origin, width: bounds.width, ascent: bounds.ascent, descent: bounds.descent)
            let progress = LitterStreamingEffectSupport.progress(index: index, revealedCount: revealedCount, trailLength: trail)
            let blockSize = max(CGFloat(1.4), CGFloat(5.0 - progress * 3.0))
            context.drawLayer { layer in
                var y = rect.minY
                var row = 0
                while y < rect.maxY {
                    var x = rect.minX
                    var col = 0
                    while x < rect.maxX {
                        let seed = abs((index + 1) * 31 + row * 17 + col * 13 + frame)
                        if seed % 4 != 0 {
                            layer.fill(
                                Path(CGRect(x: x, y: y, width: blockSize, height: blockSize)),
                                with: .color(color.opacity(0.25 + progress * 0.55))
                            )
                        }
                        x += blockSize + 1
                        col += 1
                    }
                    y += blockSize + 1
                    row += 1
                }
                layer.addFilter(.blur(radius: CGFloat(max(0, 1.3 - progress))))
            }
            context.drawLayer { layer in
                layer.opacity = 0.25 + progress * 0.75
                layer.draw(slice)
            }
            return true
        }, context: &ctx)
    }
}

struct LitterInkSpreadEffect: StreamingTextEffect {
    let trailLength: Int

    init(trailLength: Int = 10) {
        self.trailLength = trailLength
    }

    func draw(layout: Text.Layout, revealedCount: Int, settledCount: Int, time: Double, in ctx: inout GraphicsContext) {
        let trail = LitterStreamingEffectSupport.trailLength(trailLength, revealedCount: revealedCount)
        forEachSlice(in: layout, { index, slice, context in
            guard index < revealedCount else { return false }
            guard LitterStreamingEffectSupport.isInTrail(index: index, revealedCount: revealedCount, trailLength: trail) else {
                context.draw(slice)
                return true
            }

            let bounds = slice.typographicBounds
            let progress = LitterStreamingEffectSupport.progress(index: index, revealedCount: revealedCount, trailLength: trail)
            let scale = CGFloat(1.16 - progress * 0.16)
            let centerX = bounds.origin.x + bounds.width / 2
            let centerY = bounds.origin.y
            var ink = context
            ink.opacity = 0.42 + progress * 0.58
            ink.translateBy(x: centerX, y: centerY)
            ink.scaleBy(x: scale, y: scale)
            ink.translateBy(x: -centerX, y: -centerY)
            ink.addFilter(.blur(radius: CGFloat((1 - progress) * 3.5)))
            ink.draw(slice)
            return true
        }, context: &ctx)
    }
}

struct LitterSlideUpEffect: StreamingTextEffect {
    let trailLength: Int
    let distance: CGFloat

    init(trailLength: Int = 10, distance: CGFloat = 11) {
        self.trailLength = trailLength
        self.distance = distance
    }

    func draw(layout: Text.Layout, revealedCount: Int, settledCount: Int, time: Double, in ctx: inout GraphicsContext) {
        let trail = LitterStreamingEffectSupport.trailLength(trailLength, revealedCount: revealedCount)
        forEachSlice(in: layout, { index, slice, context in
            guard index < revealedCount else { return false }
            guard LitterStreamingEffectSupport.isInTrail(index: index, revealedCount: revealedCount, trailLength: trail) else {
                context.draw(slice)
                return true
            }

            let progress = LitterStreamingEffectSupport.progress(index: index, revealedCount: revealedCount, trailLength: trail)
            let eased = 1 - pow(1 - progress, 2)
            var lifted = context
            lifted.opacity = 0.25 + eased * 0.75
            lifted.translateBy(x: 0, y: distance * CGFloat(1 - eased))
            lifted.draw(slice)
            return true
        }, context: &ctx)
    }
}

struct LitterGlitchEffect: StreamingTextEffect {
    let trailLength: Int

    init(trailLength: Int = 12) {
        self.trailLength = trailLength
    }

    func draw(layout: Text.Layout, revealedCount: Int, settledCount: Int, time: Double, in ctx: inout GraphicsContext) {
        let trail = LitterStreamingEffectSupport.trailLength(trailLength, revealedCount: revealedCount)
        let frame = Int(time * 28.0)
        forEachSlice(in: layout, { index, slice, context in
            guard index < revealedCount else { return false }
            guard LitterStreamingEffectSupport.isInTrail(index: index, revealedCount: revealedCount, trailLength: trail) else {
                context.draw(slice)
                return true
            }

            let strength = LitterStreamingEffectSupport.progress(index: index, revealedCount: revealedCount, trailLength: trail)
            let jitter = CGFloat(((frame + index * 7) % 7) - 3) * CGFloat(max(0.35, strength))
            context.drawLayer { layer in
                layer.opacity = 0.55 * strength
                layer.translateBy(x: jitter - 2.0, y: -0.5)
                layer.addFilter(.colorMultiply(Color.red))
                layer.draw(slice)
            }
            context.drawLayer { layer in
                layer.opacity = 0.55 * strength
                layer.translateBy(x: -jitter + 2.0, y: 0.5)
                layer.addFilter(.colorMultiply(Color.cyan))
                layer.draw(slice)
            }
            var body = context
            body.translateBy(x: jitter * 0.45, y: 0)
            body.draw(slice)
            return true
        }, context: &ctx)
    }
}

struct LitterFocusBeamEffect: StreamingTextEffect {
    let color: Color
    let trailLength: Int

    init(color: Color = Color(red: 1.0, green: 0.95, blue: 0.55), trailLength: Int = 14) {
        self.color = color
        self.trailLength = trailLength
    }

    func draw(layout: Text.Layout, revealedCount: Int, settledCount: Int, time: Double, in ctx: inout GraphicsContext) {
        let trail = LitterStreamingEffectSupport.trailLength(trailLength, revealedCount: revealedCount)
        var activeBounds: CGRect?

        forEachSlice(in: layout, { index, slice, context in
            guard index < revealedCount else { return false }
            let bounds = slice.typographicBounds
            let rect = LitterStreamingEffectSupport.rect(origin: bounds.origin, width: bounds.width, ascent: bounds.ascent, descent: bounds.descent)
            if LitterStreamingEffectSupport.isInTrail(index: index, revealedCount: revealedCount, trailLength: trail) {
                activeBounds = activeBounds.map { $0.union(rect) } ?? rect
                context.drawLayer { layer in
                    layer.opacity = 0.9
                    layer.addFilter(.colorMultiply(color))
                    layer.draw(slice)
                }
            } else {
                context.draw(slice)
            }
            return true
        }, context: &ctx)

        guard let activeBounds else { return }
        let phase = 0.5 + 0.5 * sin(time * 8.0)
        let beamX = activeBounds.minX + activeBounds.width * CGFloat(phase)
        ctx.drawLayer { layer in
            layer.fill(
                Path(CGRect(x: beamX - 12, y: activeBounds.minY - 4, width: 24, height: activeBounds.height + 8)),
                with: .color(color.opacity(0.20))
            )
            layer.fill(
                Path(CGRect(x: beamX - 1, y: activeBounds.minY - 5, width: 2, height: activeBounds.height + 10)),
                with: .color(color.opacity(0.75))
            )
            layer.addFilter(.blur(radius: 2.0))
        }
    }
}
