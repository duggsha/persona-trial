import PersonaDesign
import SwiftUI

// The deck's hand-drawn glyphs, ported coordinate-for-coordinate from the
// SVGs in grammar.html. Each shape draws in its source viewBox and scales to
// the frame it is given; stroke widths scale with it, exactly as an SVG's do.
// Ported rather than mapped to SF Symbols because several were settled on a
// decisions page (the sheet glyph, the agent burst) and the drawing is the
// decision.

// MARK: - Scaling

/// A glyph authored in a square `unit` viewBox. `paths(in:)` returns
/// (path, strokeWidth, filled) layers in unit space; the view scales them.
protocol GrammarGlyph {
    static var unit: CGFloat { get }
    static func layers() -> [GrammarGlyphLayer]
}

struct GrammarGlyphLayer {
    var path: Path
    /// Stroke width in unit space; nil = filled.
    var stroke: CGFloat?
    var lineCap: CGLineCap = .round
    var lineJoin: CGLineJoin = .round
}

/// Draws a `GrammarGlyph` at any point size in `currentColor`.
struct GrammarGlyphView<G: GrammarGlyph>: View {
    let glyph: G.Type
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / G.unit
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            for layer in G.layers() {
                let path = layer.path.applying(transform)
                if let stroke = layer.stroke {
                    context.stroke(
                        path,
                        with: .style(.foreground),
                        style: StrokeStyle(lineWidth: stroke * scale, lineCap: layer.lineCap, lineJoin: layer.lineJoin)
                    )
                } else {
                    context.fill(path, with: .style(.foreground))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Path helpers

private extension Path {
    /// A quarter-corner as SVG's `a r r 0 0 1` draws it: line into the corner
    /// is already made; this curves to `end` with the corner point as control.
    mutating func corner(to end: CGPoint, control: CGPoint) {
        addQuadCurve(to: end, control: control)
    }

    mutating func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }
}

// MARK: - Card marks (stroke 1.4 in a 16 box, drawn at 15pt)

/// Opportunity: the location pin.
enum GlyphPin: GrammarGlyph {
    static let unit: CGFloat = 16
    static func layers() -> [GrammarGlyphLayer] {
        var p = Path()
        // M8 14.5 s5-4.2 5-8 — smooth cubic; the semicircle cap is drawn as
        // two cubics (k = 0.5523 · r) so no arc-direction guessing.
        p.move(to: CGPoint(x: 8, y: 14.5))
        p.addCurve(to: CGPoint(x: 13, y: 6.5), control1: CGPoint(x: 8, y: 14.5), control2: CGPoint(x: 13, y: 10.3))
        let k: CGFloat = 5 * 0.5523
        p.addCurve(to: CGPoint(x: 8, y: 1.5), control1: CGPoint(x: 13, y: 6.5 - k), control2: CGPoint(x: 8 + k, y: 1.5))
        p.addCurve(to: CGPoint(x: 3, y: 6.5), control1: CGPoint(x: 8 - k, y: 1.5), control2: CGPoint(x: 3, y: 6.5 - k))
        p.addCurve(to: CGPoint(x: 8, y: 14.5), control1: CGPoint(x: 3, y: 10.3), control2: CGPoint(x: 8, y: 14.5))
        p.closeSubpath()
        var dot = Path()
        dot.circle(8, 6.5, 1.8)
        return [.init(path: p, stroke: 1.4), .init(path: dot, stroke: 1.4)]
    }
}

/// Money: the credit card.
enum GlyphCreditCard: GrammarGlyph {
    static let unit: CGFloat = 16
    static func layers() -> [GrammarGlyphLayer] {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 1.5, y: 3, width: 13, height: 10), cornerSize: CGSize(width: 2, height: 2))
        var line = Path()
        line.move(to: CGPoint(x: 1.5, y: 6.2))
        line.addLine(to: CGPoint(x: 14.5, y: 6.2))
        return [.init(path: p, stroke: 1.4), .init(path: line, stroke: 1.4)]
    }
}

/// Account review: the shield with a check.
enum GlyphShieldCheck: GrammarGlyph {
    static let unit: CGFloat = 16
    static func layers() -> [GrammarGlyphLayer] {
        var p = Path()
        p.move(to: CGPoint(x: 8, y: 1.5))
        p.addLine(to: CGPoint(x: 3.2, y: 3.3))
        p.addLine(to: CGPoint(x: 3.2, y: 7.5))
        p.addCurve(to: CGPoint(x: 8, y: 14.4), control1: CGPoint(x: 3.2, y: 10.5), control2: CGPoint(x: 5.2, y: 13.2))
        p.addCurve(to: CGPoint(x: 12.8, y: 7.5), control1: CGPoint(x: 10.8, y: 13.2), control2: CGPoint(x: 12.8, y: 10.5))
        p.addLine(to: CGPoint(x: 12.8, y: 3.3))
        p.closeSubpath()
        var check = Path()
        check.move(to: CGPoint(x: 5.9, y: 7.9))
        check.addLine(to: CGPoint(x: 7.4, y: 9.4))
        check.addLine(to: CGPoint(x: 10.2, y: 6.3))
        return [.init(path: p, stroke: 1.4), .init(path: check, stroke: 1.4)]
    }
}

/// FYI: the envelope.
enum GlyphEnvelope: GrammarGlyph {
    static let unit: CGFloat = 16
    static func layers() -> [GrammarGlyphLayer] {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 1.5, y: 3.4, width: 13, height: 9.2), cornerSize: CGSize(width: 2.2, height: 2.2))
        var flap = Path()
        flap.move(to: CGPoint(x: 2.3, y: 4.7))
        flap.addLine(to: CGPoint(x: 8, y: 8.8))
        flap.addLine(to: CGPoint(x: 13.7, y: 4.7))
        return [.init(path: p, stroke: 1.4), .init(path: flap, stroke: 1.4)]
    }
}

// MARK: - Pill icons (14pt in a 16 box)

/// The agent burst: Persona goes and does it out of band. 19 filled dots —
/// the app's own background-agent mark (decisions-agent-icon.html).
enum GlyphAgentBurst: GrammarGlyph {
    static let unit: CGFloat = 16
    static func layers() -> [GrammarGlyphLayer] {
        let dots: [(CGFloat, CGFloat, CGFloat)] = [
            (8, 1.6, 0.72), (8, 4.75, 0.98), (8, 7.95, 1.2), (8, 11.15, 0.98), (8, 14.3, 0.72),
            (5.15, 3.2, 0.72), (5.15, 6.5, 0.92), (5.15, 9.5, 0.92), (5.15, 12.8, 0.72),
            (10.85, 3.2, 0.72), (10.85, 6.5, 0.92), (10.85, 9.5, 0.92), (10.85, 12.8, 0.72),
            (2.6, 4.95, 0.72), (2.6, 8, 0.76), (2.6, 11.1, 0.72),
            (13.4, 4.95, 0.72), (13.4, 8, 0.76), (13.4, 11.1, 0.72),
        ]
        var p = Path()
        for (x, y, r) in dots { p.circle(x, y, r) }
        return [.init(path: p, stroke: nil)]
    }
}

/// Opens a mail sheet: the envelope, tighter cropped than the card mark's.
enum GlyphPillMail: GrammarGlyph {
    static let unit: CGFloat = 16
    static func layers() -> [GrammarGlyphLayer] {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 1.9, y: 3.6, width: 12.2, height: 8.8), cornerSize: CGSize(width: 2.2, height: 2.2))
        var flap = Path()
        flap.move(to: CGPoint(x: 2.7, y: 5.2))
        flap.addLine(to: CGPoint(x: 8, y: 8.9))
        flap.addLine(to: CGPoint(x: 13.3, y: 5.2))
        return [.init(path: p, stroke: 1.5), .init(path: flap, stroke: 1.5)]
    }
}

/// Opens a non-mail sheet: the panel rising off the bottom edge — the one
/// picture of "this button is a door" (decisions-sheet-icon.html).
enum GlyphPillSheet: GrammarGlyph {
    static let unit: CGFloat = 16
    static func layers() -> [GrammarGlyphLayer] {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 2, y: 2.4, width: 12, height: 11.2), cornerSize: CGSize(width: 2.6, height: 2.6))
        var rule = Path()
        rule.move(to: CGPoint(x: 2, y: 9.1))
        rule.addLine(to: CGPoint(x: 14, y: 9.1))
        var grab = Path()
        grab.move(to: CGPoint(x: 6.7, y: 11.4))
        grab.addLine(to: CGPoint(x: 9.3, y: 11.4))
        return [.init(path: p, stroke: 1.5), .init(path: rule, stroke: 1.5), .init(path: grab, stroke: 1.5)]
    }
}

/// Puts you in another app. TRAILS the label — it marks the destination, not
/// the kind of press (cards.css: "Join Meet ↗" is a sentence).
enum GlyphExternal: GrammarGlyph {
    static let unit: CGFloat = 16
    static func layers() -> [GrammarGlyphLayer] {
        var box = Path()
        box.move(to: CGPoint(x: 13.6, y: 9.3))
        box.addLine(to: CGPoint(x: 13.6, y: 12.3))
        box.corner(to: CGPoint(x: 11.6, y: 14.3), control: CGPoint(x: 13.6, y: 14.3))
        box.addLine(to: CGPoint(x: 3.8, y: 14.3))
        box.corner(to: CGPoint(x: 1.8, y: 12.3), control: CGPoint(x: 1.8, y: 14.3))
        box.addLine(to: CGPoint(x: 1.8, y: 4.5))
        box.corner(to: CGPoint(x: 3.8, y: 2.5), control: CGPoint(x: 1.8, y: 2.5))
        box.addLine(to: CGPoint(x: 6.8, y: 2.5))
        var arrow = Path()
        arrow.move(to: CGPoint(x: 10.1, y: 1.8))
        arrow.addLine(to: CGPoint(x: 14.2, y: 1.8))
        arrow.addLine(to: CGPoint(x: 14.2, y: 5.9))
        var diagonal = Path()
        diagonal.move(to: CGPoint(x: 6.7, y: 9.3))
        diagonal.addLine(to: CGPoint(x: 14.2, y: 1.8))
        return [.init(path: box, stroke: 1.5), .init(path: arrow, stroke: 1.5), .init(path: diagonal, stroke: 1.5)]
    }
}

/// The invite's meta chevron, pointing up (`.iv-chev` rotated 180°).
enum GlyphChevronUp: GrammarGlyph {
    static let unit: CGFloat = 12
    static func layers() -> [GrammarGlyphLayer] {
        var p = Path()
        p.move(to: CGPoint(x: 2.5, y: 7.5))
        p.addLine(to: CGPoint(x: 6, y: 4))
        p.addLine(to: CGPoint(x: 9.5, y: 7.5))
        return [.init(path: p, stroke: 1.9)]
    }
}

/// The copy chip's clipboard: two offset rounded squares.
enum GlyphCopy: GrammarGlyph {
    static let unit: CGFloat = 16
    static func layers() -> [GrammarGlyphLayer] {
        var front = Path()
        front.addRoundedRect(in: CGRect(x: 5.6, y: 5.6, width: 8.8, height: 8.8), cornerSize: CGSize(width: 2.4, height: 2.4))
        var back = Path()
        back.move(to: CGPoint(x: 10.4, y: 5.6))
        back.addLine(to: CGPoint(x: 10.4, y: 4))
        back.corner(to: CGPoint(x: 8, y: 1.6), control: CGPoint(x: 10.4, y: 1.6))
        back.addLine(to: CGPoint(x: 4, y: 1.6))
        back.corner(to: CGPoint(x: 1.6, y: 4), control: CGPoint(x: 1.6, y: 1.6))
        back.addLine(to: CGPoint(x: 1.6, y: 8))
        back.corner(to: CGPoint(x: 4, y: 10.4), control: CGPoint(x: 1.6, y: 10.4))
        back.addLine(to: CGPoint(x: 5.6, y: 10.4))
        return [.init(path: front, stroke: 1.5), .init(path: back, stroke: 1.5)]
    }
}
