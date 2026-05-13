import SwiftUI
import HairballUI

struct LitterTypewriterEffect: StreamingTextEffect {
    let cursorColor: Color

    init(cursorColor: Color = Color(red: 0.0, green: 1.0, blue: 0.612)) {
        self.cursorColor = cursorColor
    }

    func draw(layout: Text.Layout, revealedCount: Int, settledCount: Int, time: Double, in ctx: inout GraphicsContext) {
        let cursorPoint = drawRevealedAndGetCursorPoint(in: layout, revealedCount: revealedCount, context: &ctx)
        guard let cursorPoint else { return }
        let visible = Int(time * 2).isMultiple(of: 2)
        guard visible else { return }
        ctx.fill(
            Path(CGRect(x: cursorPoint.x + 1, y: cursorPoint.y - 14, width: 2, height: 17)),
            with: .color(cursorColor.opacity(0.9))
        )
    }
}

struct LitterTerminalScanEffect: StreamingTextEffect {
    let scanColor: Color
    let trailLength: Int

    init(scanColor: Color = Color(red: 0.0, green: 1.0, blue: 0.612), trailLength: Int = 16) {
        self.scanColor = scanColor
        self.trailLength = trailLength
    }

    func draw(layout: Text.Layout, revealedCount: Int, settledCount: Int, time: Double, in ctx: inout GraphicsContext) {
        let trail = effectiveTrail(ownTrail: trailLength, revealedCount: revealedCount, settledCount: settledCount)
        var bounds: CGRect?
        var cursorRect: CGRect?

        forEachSlice(in: layout, { index, slice, context in
            guard index < revealedCount else { return false }
            let b = slice.typographicBounds
            let rect = CGRect(x: b.origin.x, y: b.origin.y - b.ascent, width: max(b.width, 1), height: b.ascent + b.descent)
            bounds = bounds.map { $0.union(rect) } ?? rect
            if index == revealedCount - 1 { cursorRect = rect }

            let dist = revealedCount - index
            if dist <= trail {
                let opacity = max(0.2, 1.0 - Double(dist) / Double(trail))
                context.drawLayer { layer in
                    layer.addFilter(.colorMultiply(scanColor.opacity(opacity)))
                    layer.draw(slice)
                }
            } else {
                context.draw(slice)
            }
            return true
        }, context: &ctx)

        guard let bounds, let cursorRect else { return }
        let y = cursorRect.midY + CGFloat(sin(time * 16.0)) * 2
        ctx.drawLayer { layer in
            layer.fill(
                Path(CGRect(x: bounds.minX, y: y, width: max(bounds.width, 6), height: 1.5)),
                with: .color(scanColor.opacity(0.45))
            )
            layer.addFilter(.blur(radius: 1.5))
        }
    }
}

struct LitterSoftBlurEffect: StreamingTextEffect {
    let trailLength: Int

    init(trailLength: Int = 10) {
        self.trailLength = trailLength
    }

    func draw(layout: Text.Layout, revealedCount: Int, settledCount: Int, time: Double, in ctx: inout GraphicsContext) {
        let trail = effectiveTrail(ownTrail: trailLength, revealedCount: revealedCount, settledCount: settledCount)
        forEachSlice(in: layout, { index, slice, context in
            guard index < revealedCount else { return false }
            let dist = revealedCount - index
            if dist <= trail {
                let t = Double(dist) / Double(trail)
                context.drawLayer { layer in
                    layer.opacity = max(0.25, 1.0 - t * 0.35)
                    layer.addFilter(.blur(radius: CGFloat(t * 5.0)))
                    layer.draw(slice)
                }
            } else {
                context.draw(slice)
            }
            return true
        }, context: &ctx)
    }
}

struct LitterNeonPulseEffect: StreamingTextEffect {
    let color: Color
    let trailLength: Int

    init(color: Color = Color(red: 0.0, green: 0.95, blue: 1.0), trailLength: Int = 12) {
        self.color = color
        self.trailLength = trailLength
    }

    func draw(layout: Text.Layout, revealedCount: Int, settledCount: Int, time: Double, in ctx: inout GraphicsContext) {
        let trail = effectiveTrail(ownTrail: trailLength, revealedCount: revealedCount, settledCount: settledCount)
        let pulse = 0.65 + 0.35 * sin(time * 8.0)
        forEachSlice(in: layout, { index, slice, context in
            guard index < revealedCount else { return false }
            let dist = revealedCount - index
            if dist <= trail {
                let strength = max(0, 1.0 - Double(dist) / Double(trail)) * pulse
                context.drawLayer { layer in
                    layer.addFilter(.colorMultiply(color.opacity(0.75)))
                    layer.addFilter(.blur(radius: CGFloat(2.0 + strength * 5.0)))
                    layer.opacity = strength * 0.85
                    layer.draw(slice)
                }
                context.drawLayer { layer in
                    layer.addFilter(.colorMultiply(color.opacity(0.9)))
                    layer.draw(slice)
                }
            } else {
                context.draw(slice)
            }
            return true
        }, context: &ctx)
    }
}

struct LitterGhostTrailEffect: StreamingTextEffect {
    let trailLength: Int
    let color: Color

    init(trailLength: Int = 14, color: Color = Color(red: 0.68, green: 0.88, blue: 1.0)) {
        self.trailLength = trailLength
        self.color = color
    }

    func draw(layout: Text.Layout, revealedCount: Int, settledCount: Int, time: Double, in ctx: inout GraphicsContext) {
        let trail = effectiveTrail(ownTrail: trailLength, revealedCount: revealedCount, settledCount: settledCount)
        forEachSlice(in: layout, { index, slice, context in
            guard index < revealedCount else { return false }
            let dist = revealedCount - index
            if dist <= trail {
                let strength = max(0, 1.0 - Double(dist) / Double(trail))
                for step in 1...3 {
                    var ghost = context
                    ghost.opacity = strength * (0.18 / Double(step))
                    ghost.translateBy(x: CGFloat(-step * 3), y: CGFloat(step) * 0.7)
                    ghost.addFilter(.colorMultiply(color.opacity(0.7)))
                    ghost.draw(slice)
                }
                context.draw(slice)
            } else {
                context.draw(slice)
            }
            return true
        }, context: &ctx)
    }
}

struct LitterPixelDecodeEffect: StreamingTextEffect {
    let trailLength: Int
    let color: Color

    init(trailLength: Int = 10, color: Color = Color(red: 0.3, green: 0.9, blue: 1.0)) {
        self.trailLength = trailLength
        self.color = color
    }

    func draw(layout: Text.Layout, revealedCount: Int, settledCount: Int, time: Double, in ctx: inout GraphicsContext) {
        let trail = effectiveTrail(ownTrail: trailLength, revealedCount: revealedCount, settledCount: settledCount)
        let frame = Int(time * 20.0)
        forEachSlice(in: layout, { index, slice, context in
            guard index < revealedCount else { return false }
            let dist = revealedCount - index
            guard index >= settledCount, dist <= trail else {
                context.draw(slice)
                return true
            }

            let b = slice.typographicBounds
            let progress = 1.0 - Double(dist) / Double(trail)
            let blockSize = max(CGFloat(1.2), CGFloat(4.0 - progress * 2.5))
            let rect = CGRect(x: b.origin.x, y: b.origin.y - b.ascent, width: max(b.width, 2), height: b.ascent + b.descent)
            context.drawLayer { layer in
                var y = rect.minY
                var row = 0
                while y < rect.maxY {
                    var x = rect.minX
                    var col = 0
                    while x < rect.maxX {
                        let seed = abs((index + 1) * 31 + row * 17 + col * 13 + frame)
                        if seed % 3 != 0 {
                            let opacity = 0.12 + progress * 0.55
                            layer.fill(
                                Path(CGRect(x: x, y: y, width: blockSize, height: blockSize)),
                                with: .color(color.opacity(opacity))
                            )
                        }
                        x += blockSize + 1
                        col += 1
                    }
                    y += blockSize + 1
                    row += 1
                }
                layer.addFilter(.blur(radius: max(0, CGFloat(1.5 - progress))))
            }
            if progress > 0.45 {
                context.draw(slice)
            }
            return true
        }, context: &ctx)
    }
}

struct LitterInkSpreadEffect: StreamingTextEffect {
    let trailLength: Int

    init(trailLength: Int = 8) {
        self.trailLength = trailLength
    }

    func draw(layout: Text.Layout, revealedCount: Int, settledCount: Int, time: Double, in ctx: inout GraphicsContext) {
        let trail = effectiveTrail(ownTrail: trailLength, revealedCount: revealedCount, settledCount: settledCount)
        forEachSlice(in: layout, { index, slice, context in
            guard index < revealedCount else { return false }
            let dist = revealedCount - index
            if dist <= trail {
                let t = Double(dist) / Double(trail)
                let scale = 1.0 + CGFloat(t * 0.18)
                let b = slice.typographicBounds
                let cx = b.origin.x + b.width / 2
                let cy = b.origin.y
                var c = context
                c.opacity = max(0.35, 1.0 - t * 0.45)
                c.translateBy(x: cx, y: cy)
                c.scaleBy(x: scale, y: scale)
                c.translateBy(x: -cx, y: -cy)
                c.addFilter(.blur(radius: CGFloat(t * 2.8)))
                c.draw(slice)
            } else {
                context.draw(slice)
            }
            return true
        }, context: &ctx)
    }
}

struct LitterSlideUpEffect: StreamingTextEffect {
    let trailLength: Int
    let distance: CGFloat

    init(trailLength: Int = 8, distance: CGFloat = 9) {
        self.trailLength = trailLength
        self.distance = distance
    }

    func draw(layout: Text.Layout, revealedCount: Int, settledCount: Int, time: Double, in ctx: inout GraphicsContext) {
        let trail = effectiveTrail(ownTrail: trailLength, revealedCount: revealedCount, settledCount: settledCount)
        forEachSlice(in: layout, { index, slice, context in
            guard index < revealedCount else { return false }
            let dist = revealedCount - index
            if dist <= trail {
                let progress = 1.0 - Double(dist) / Double(trail)
                let eased = 1.0 - pow(1.0 - progress, 2.0)
                var c = context
                c.opacity = max(0.25, eased)
                c.translateBy(x: 0, y: distance * CGFloat(1.0 - eased))
                c.draw(slice)
            } else {
                context.draw(slice)
            }
            return true
        }, context: &ctx)
    }
}

struct LitterGlitchEffect: StreamingTextEffect {
    let trailLength: Int

    init(trailLength: Int = 10) {
        self.trailLength = trailLength
    }

    func draw(layout: Text.Layout, revealedCount: Int, settledCount: Int, time: Double, in ctx: inout GraphicsContext) {
        let trail = effectiveTrail(ownTrail: trailLength, revealedCount: revealedCount, settledCount: settledCount)
        let frame = Int(time * 24.0)
        forEachSlice(in: layout, { index, slice, context in
            guard index < revealedCount else { return false }
            let dist = revealedCount - index
            if dist <= trail {
                let strength = max(0, 1.0 - Double(dist) / Double(trail))
                let jitter = CGFloat(((frame + index * 7) % 5) - 2) * CGFloat(strength)
                context.drawLayer { layer in
                    layer.opacity = 0.55 * strength
                    layer.translateBy(x: jitter - 1.5, y: 0)
                    layer.addFilter(.colorMultiply(Color.red.opacity(0.9)))
                    layer.draw(slice)
                }
                context.drawLayer { layer in
                    layer.opacity = 0.55 * strength
                    layer.translateBy(x: -jitter + 1.5, y: 0)
                    layer.addFilter(.colorMultiply(Color.cyan.opacity(0.9)))
                    layer.draw(slice)
                }
                var c = context
                c.translateBy(x: jitter * 0.35, y: 0)
                c.draw(slice)
            } else {
                context.draw(slice)
            }
            return true
        }, context: &ctx)
    }
}

struct LitterFocusBeamEffect: StreamingTextEffect {
    let color: Color
    let trailLength: Int

    init(color: Color = Color(red: 1.0, green: 0.95, blue: 0.55), trailLength: Int = 12) {
        self.color = color
        self.trailLength = trailLength
    }

    func draw(layout: Text.Layout, revealedCount: Int, settledCount: Int, time: Double, in ctx: inout GraphicsContext) {
        let trail = effectiveTrail(ownTrail: trailLength, revealedCount: revealedCount, settledCount: settledCount)
        var activeRects: [CGRect] = []

        forEachSlice(in: layout, { index, slice, context in
            guard index < revealedCount else { return false }
            let b = slice.typographicBounds
            let dist = revealedCount - index
            if dist <= trail {
                activeRects.append(CGRect(x: b.origin.x, y: b.origin.y - b.ascent, width: max(b.width, 1), height: b.ascent + b.descent))
            }
            context.draw(slice)
            return true
        }, context: &ctx)

        guard let bounds = activeRects.reduce(nil, { (current: CGRect?, rect: CGRect) in current.map { $0.union(rect) } ?? rect }) else { return }
        let beamX = bounds.maxX + CGFloat(sin(time * 7.0)) * 3
        ctx.drawLayer { layer in
            layer.fill(
                Path(CGRect(x: bounds.minX - 4, y: bounds.minY - 2, width: max(beamX - bounds.minX, 4), height: bounds.height + 4)),
                with: .color(color.opacity(0.10))
            )
            layer.fill(
                Path(CGRect(x: beamX - 1, y: bounds.minY - 4, width: 2, height: bounds.height + 8)),
                with: .color(color.opacity(0.65))
            )
            layer.addFilter(.blur(radius: 2.5))
        }
    }
}
