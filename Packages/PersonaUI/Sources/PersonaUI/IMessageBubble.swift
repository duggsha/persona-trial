import Foundation
import PersonaDesign
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

// MARK: - iMessage bubble, traced 1:1 from iPhone reference captures
//
// Geometry was extracted from real iMessage screenshots (sub-pixel marching-
// squares trace at 4×, corner circle-fit, scales reconciled via the
// radius-to-line-pitch ratio). The canonical unit system is iOS POINTS at
// 17pt body type, so every constant here is used as-is — no scale factor.
//
// radius 22.57 (⇒ a one-line bubble is a perfect pill)
// tail: no side overhang — the spike dips 7.46pt BELOW the body line;
// small (pill) bubbles use their own traced tail, re-projected onto the
// actual body boundary so the attachment hugs the curve at any size
// ink insets 15.5 side / 13.7 top / 10.8 below the descender
// outgoing fill: screen-position gradient
// incoming fill: solid white plate (Figma spec shadow: black 4%, y 3, σ2)
//
// Colors are Persona's monochrome scheme (user = charcoal gradient, assistant
// = white plate), not iMessage's blue/grey — only the geometry is traced from
// iMessage.

/// The traced bubble outline. `width`/`height` stretch the straight edges;
/// corners and tail stay fixed-size, exactly like the real thing.
public struct IMessageBubbleShape: Shape {
    public enum Side: Sendable {
        case incoming // tail bottom-left
        case outgoing // tail bottom-right
    }

    public var side: Side
    /// Only the last bubble of a sender run carries the tail.
    public var tail: Bool

    public init(side: Side, tail: Bool = true) {
        self.side = side
        self.tail = tail
    }

    public static let cornerRadius: CGFloat = 22.57
    /// The tail's drop below the bubble's body bottom line. A tailed bubble's
    /// frame must include this (bottom padding accounts for it).
    public static let tailDip: CGFloat = 7.46

    /// SwiftUI may ask a scrolling shape for its path repeatedly as the row is
    /// composited. A finished message's geometry is immutable, so retain the
    /// exact path instead of rebuilding the traced spline on every request.
    /// The key uses the unrounded floating-point bit patterns: caching never
    /// changes geometry, even at fractional layout sizes.
    private final class CachedPath: NSObject {
        let value: Path
        init(_ value: Path) { self.value = value }
    }

    nonisolated(unsafe) private static let pathCache: NSCache<NSString, CachedPath> = {
        let cache = NSCache<NSString, CachedPath>()
        cache.countLimit = 512
        return cache
    }()

    /// Standard tail, traced from the wide reference plates — relative to the
    /// body's bottom-right corner (x ≤ 0; the iPhone tail never extends past
    /// the bubble's side).
    static let tailPoints: [CGPoint] = [
        CGPoint(x: -0.06, y: -29.09), CGPoint(x: -0.06, y: -28.04), CGPoint(x: -0.12, y: -26.98),
        CGPoint(x: -0.12, y: -25.92), CGPoint(x: -0.24, y: -24.86), CGPoint(x: -0.29, y: -23.8),
        CGPoint(x: -0.35, y: -22.75), CGPoint(x: -0.41, y: -21.69), CGPoint(x: -0.53, y: -20.63),
        CGPoint(x: -0.65, y: -19.57), CGPoint(x: -0.82, y: -18.51), CGPoint(x: -1.0, y: -17.46),
        CGPoint(x: -1.18, y: -16.4), CGPoint(x: -1.47, y: -15.34), CGPoint(x: -1.88, y: -13.93),
        CGPoint(x: -2.23, y: -12.87), CGPoint(x: -2.7, y: -11.81), CGPoint(x: -3.23, y: -10.76),
        CGPoint(x: -3.94, y: -9.7), CGPoint(x: -4.7, y: -8.64), CGPoint(x: -5.58, y: -7.58),
        CGPoint(x: -6.64, y: -6.52), CGPoint(x: -7.29, y: -5.88), CGPoint(x: -8.35, y: -5.0),
        CGPoint(x: -9.4, y: -4.11), CGPoint(x: -10.29, y: -3.06), CGPoint(x: -10.99, y: -2.0),
        CGPoint(x: -11.4, y: -0.94), CGPoint(x: -11.52, y: 0.12), CGPoint(x: -11.52, y: 1.18),
        CGPoint(x: -11.4, y: 1.88), CGPoint(x: -11.23, y: 2.59), CGPoint(x: -10.93, y: 3.29),
        CGPoint(x: -10.52, y: 4.0), CGPoint(x: -10.05, y: 4.7), CGPoint(x: -9.58, y: 5.41),
        CGPoint(x: -9.17, y: 6.11), CGPoint(x: -9.11, y: 6.47), CGPoint(x: -9.17, y: 6.82),
        CGPoint(x: -9.35, y: 7.11), CGPoint(x: -9.7, y: 7.41), CGPoint(x: -10.05, y: 7.46),
        CGPoint(x: -10.76, y: 7.41), CGPoint(x: -11.46, y: 7.17), CGPoint(x: -12.17, y: 6.82),
        CGPoint(x: -12.87, y: 6.52), CGPoint(x: -13.58, y: 6.17), CGPoint(x: -14.28, y: 5.76),
        CGPoint(x: -14.99, y: 5.41), CGPoint(x: -15.69, y: 5.0), CGPoint(x: -16.4, y: 4.58),
        CGPoint(x: -17.1, y: 4.11), CGPoint(x: -17.81, y: 3.64), CGPoint(x: -18.51, y: 3.17),
        CGPoint(x: -19.22, y: 2.7), CGPoint(x: -19.93, y: 2.17), CGPoint(x: -20.63, y: 1.65),
        CGPoint(x: -21.34, y: 1.18), CGPoint(x: -22.04, y: 0.71), CGPoint(x: -22.75, y: 0.35),
        CGPoint(x: -23.45, y: 0.12), CGPoint(x: -24.16, y: 0.06), CGPoint(x: -24.86, y: 0.0),
        CGPoint(x: -31.92, y: 0.0),
    ]

    /// The SMALL-bubble tail, traced from the "Hi" reference capture — a
    /// genuinely different construction: it hugs the pill's arc, departs
    /// tangentially, dips less and its sweep-back follows the pill's curved
    /// bottom. Relative to its source pill (45.5×40.7, r 20.35).
    static let tailPointsSmall: [CGPoint] = [
        CGPoint(x: -3.58, y: -31.9), CGPoint(x: -2.61, y: -30.39), CGPoint(x: -1.86, y: -28.87),
        CGPoint(x: -1.23, y: -27.36), CGPoint(x: -0.75, y: -25.84), CGPoint(x: -0.38, y: -24.33),
        CGPoint(x: -0.17, y: -22.81), CGPoint(x: -0.01, y: -21.3), CGPoint(x: -0.0, y: -19.78),
        CGPoint(x: -0.13, y: -18.27), CGPoint(x: -0.32, y: -16.75), CGPoint(x: -0.7, y: -15.24),
        CGPoint(x: -1.17, y: -13.72), CGPoint(x: -1.78, y: -12.21), CGPoint(x: -2.52, y: -10.69),
        CGPoint(x: -3.47, y: -9.18), CGPoint(x: -4.59, y: -7.67), CGPoint(x: -5.89, y: -6.25),
        CGPoint(x: -7.28, y: -4.97), CGPoint(x: -8.79, y: -3.64), CGPoint(x: -9.91, y: -2.15),
        CGPoint(x: -10.44, y: -0.63), CGPoint(x: -10.55, y: 0.88), CGPoint(x: -10.19, y: 2.4),
        CGPoint(x: -9.4, y: 3.91), CGPoint(x: -8.48, y: 5.43), CGPoint(x: -9.05, y: 6.64),
        CGPoint(x: -10.56, y: 6.42), CGPoint(x: -12.08, y: 5.72), CGPoint(x: -13.59, y: 4.92),
        CGPoint(x: -15.11, y: 4.02), CGPoint(x: -16.63, y: 3.04), CGPoint(x: -18.14, y: 1.96),
        CGPoint(x: -19.66, y: 0.89), CGPoint(x: -21.17, y: 0.13), CGPoint(x: -22.69, y: -0.08),
        CGPoint(x: -24.2, y: -0.08), CGPoint(x: -25.72, y: -0.11), CGPoint(x: -27.23, y: -0.17),
        CGPoint(x: -28.75, y: -0.24), CGPoint(x: -30.26, y: -0.37), CGPoint(x: -31.78, y: -0.59),
        CGPoint(x: -33.29, y: -0.89), CGPoint(x: -34.81, y: -1.31), CGPoint(x: -36.32, y: -1.86),
        CGPoint(x: -37.84, y: -2.61), CGPoint(x: -39.35, y: -3.5), CGPoint(x: -40.86, y: -4.59),
        CGPoint(x: -42.3, y: -5.87), CGPoint(x: -43.62, y: -7.3), CGPoint(x: -44.66, y: -8.63),
        CGPoint(x: -44.74, y: -8.75),
    ]

    public func path(in rect: CGRect) -> Path {
        let keyParts: [UInt64] = [
            Double(rect.origin.x).bitPattern,
            Double(rect.origin.y).bitPattern,
            Double(rect.width).bitPattern,
            Double(rect.height).bitPattern,
            side == .incoming ? 0 : 1,
            tail ? 1 : 0,
        ]
        let key = NSString(string: keyParts.map { String($0) }.joined(separator: ":"))
        if let cached = Self.pathCache.object(forKey: key) {
            return cached.value
        }

        let result = makePath(in: rect)
        Self.pathCache.setObject(CachedPath(result), forKey: key)
        return result
    }

    private func makePath(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        // Body bottom sits above the tail's dip; an untailed bubble uses the
        // full rect.
        let hb = tail ? rect.height - Self.tailDip : rect.height
        let r = min(Self.cornerRadius, w / 2, hb / 2)

        if !tail {
            // Plain rounded rect — circular corners (the trace fit a true
            // circle at 0.087px RMSE, not a continuous/squircle corner).
            p.move(to: CGPoint(x: r, y: 0))
            p.addLine(to: CGPoint(x: w - r, y: 0))
            p.addArc(center: CGPoint(x: w - r, y: r), radius: r,
                     startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: CGPoint(x: w, y: hb - r))
            p.addArc(center: CGPoint(x: w - r, y: hb - r), radius: r,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            p.addLine(to: CGPoint(x: r, y: hb))
            p.addArc(center: CGPoint(x: r, y: hb - r), radius: r,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            p.addLine(to: CGPoint(x: 0, y: r))
            p.addArc(center: CGPoint(x: r, y: r), radius: r,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            p.closeSubpath()
            if side == .incoming {
                p = p.applying(CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -w, y: 0))
            }
            return p
        }

        // ── Tailed bubble: ONE continuous outline ─────────────────────────
        // The reference junction is a concave notch carved INTO the body — a
        // union can only add, so it read as a docked blob. Instead: walk the
        // body boundary from the tail's exit junction the long way round to
        // its entry junction, then follow the traced tail curve (notch, tip,
        // sweep) back. Templates are re-projected onto THIS body first
        // (closest-boundary-point + normal-offset against their source body).
        let small = w < 78
        let template = small ? Self.tailPointsSmall : Self.tailPoints
        let srcW: CGFloat = small ? 45.5 : 278.1
        let srcH: CGFloat = small ? 40.7 : 132.7
        let srcR: CGFloat = small ? 20.35 : 22.57
        let sc = CGPoint(x: max(srcW / 2 - srcR, 0), y: max(srcH / 2 - srcR, 0))
        let tc = CGPoint(x: max(w / 2 - r, 0), y: max(hb / 2 - r, 0))
        let dScale = r / srcR

        struct Decomp { let kx, ky, nx, ny, d: CGFloat }
        var dec: [Decomp] = []
        for rel in template {
            let px = srcW + rel.x - srcW / 2
            let py = srcH + rel.y - srcH / 2
            let k = CGPoint(x: min(max(px, -sc.x), sc.x), y: min(max(py, -sc.y), sc.y))
            var nx = px - k.x, ny = py - k.y
            let len = sqrt(nx * nx + ny * ny)
            if len < 0.001 { nx = 0; ny = 1 } else { nx /= len; ny /= len }
            dec.append(Decomp(
                kx: max(tc.x - (sc.x - k.x), -tc.x),
                ky: max(tc.y - (sc.y - k.y), -tc.y),
                nx: nx, ny: ny, d: len - srcR
            ))
        }
        func rebuild(_ q: Decomp, dOverride: CGFloat? = nil) -> CGPoint {
            let rr = r + (dOverride ?? q.d) * dScale
            return CGPoint(x: w / 2 + q.kx + q.nx * rr, y: hb / 2 + q.ky + q.ny * rr)
        }
        // The tail's span: contiguous region around the peak, INCLUDING the
        // slightly-inside (d < 0) blend zones at both ends — that concavity
        // is the junction's character.
        var peak = 0
        for i in dec.indices where dec[i].d > dec[peak].d { peak = i }
        // Span the contiguous protruding arc around the peak, then anchor
        // both ends EXACTLY on the boundary (d = 0) so the splice with the
        // body walk is tangent-clean.
        var visStart = peak, visEnd = peak
        while visStart > 0, dec[visStart - 1].d >= 0.05 { visStart -= 1 }
        while visEnd < dec.count - 1, dec[visEnd + 1].d >= 0.05 { visEnd += 1 }
        var tailPts = [rebuild(dec[visStart], dOverride: 0)]
        if visEnd > visStart + 1 {
            for i in (visStart + 1) ... (visEnd - 1) { tailPts.append(rebuild(dec[i])) }
        }
        tailPts.append(rebuild(dec[visEnd], dOverride: 0))
        let ja = tailPts.first! // entry junction (upper, right side)
        let jb = tailPts.last!  // exit junction (bottom, left of tail)

        // Body boundary samples, clockwise from the top-left corner's end.
        var bnd: [CGPoint] = []
        let steps = 30 // ~1.2pt arc spacing: any splice gap stays sub-pixel
        func arc(_ cx: CGFloat, _ cy: CGFloat, _ a0: CGFloat, _ a1: CGFloat) {
            for i in 0 ... steps {
                let a = a0 + (a1 - a0) * CGFloat(i) / CGFloat(steps)
                bnd.append(CGPoint(x: cx + r * cos(a), y: cy + r * sin(a)))
            }
        }
        func seg(_ p0: CGPoint, _ p1: CGPoint) {
            let len = hypot(p1.x - p0.x, p1.y - p0.y)
            // Long straight runs (the sides of a tall bubble) don't need 4pt
            // sampling end to end: every sample is collinear, and a
            // Catmull-Rom segment whose four control points are collinear IS
            // the straight line — so only the ends keep the dense spacing
            // (they set the tangents into the corner arcs and carry the
            // tail's junction anchors; both live within ~32pt of a corner).
            // Node count becomes O(1) in bubble height instead of height/4 —
            // a 2000pt streaming bubble was ~1000 cubic segments, rebuilt and
            // re-rasterized as a clip mask on EVERY token.
            let dense: CGFloat = 48
            func lerp(_ d: CGFloat) -> CGPoint {
                let t = d / len
                return CGPoint(x: p0.x + (p1.x - p0.x) * t, y: p0.y + (p1.y - p0.y) * t)
            }
            if len > 2 * dense + 32 {
                var d: CGFloat = 4
                while d <= dense { bnd.append(lerp(d)); d += 4 }
                // Every point between these two is collinear. Catmull-Rom
                // therefore produces the identical straight segment with two
                // support points, regardless of whether the bubble is 200pt or
                // 20,000pt tall. The previous 64pt loop still made path size
                // grow linearly with giant messages despite calling it O(1).
                let bridge = len - 2 * dense
                bnd.append(lerp(dense + bridge / 3))
                bnd.append(lerp(dense + 2 * bridge / 3))
                d = len - dense
                while d < len { bnd.append(lerp(d)); d += 4 }
                bnd.append(p1)
            } else {
                let n = max(Int(len / 4), 1)
                for i in 1 ... n {
                    let t = CGFloat(i) / CGFloat(n)
                    bnd.append(CGPoint(x: p0.x + (p1.x - p0.x) * t, y: p0.y + (p1.y - p0.y) * t))
                }
            }
        }
        bnd.append(CGPoint(x: r, y: 0))
        seg(CGPoint(x: r, y: 0), CGPoint(x: w - r, y: 0))
        arc(w - r, r, -.pi / 2, 0)
        if hb - r > r { seg(CGPoint(x: w, y: r), CGPoint(x: w, y: hb - r)) }
        arc(w - r, hb - r, 0, .pi / 2)
        if w - r > r { seg(CGPoint(x: w - r, y: hb), CGPoint(x: r, y: hb)) }
        arc(r, hb - r, .pi / 2, .pi)
        if hb - r > r { seg(CGPoint(x: 0, y: hb - r), CGPoint(x: 0, y: r)) }
        arc(r, r, .pi, 3 * .pi / 2)

        func nearest(_ q: CGPoint) -> Int {
            var bi = 0; var bd = CGFloat.greatestFiniteMagnitude
            for (i, b) in bnd.enumerated() {
                let d = hypot(b.x - q.x, b.y - q.y)
                if d < bd { bd = d; bi = i }
            }
            return bi
        }
        let iA = nearest(ja), iB = nearest(jb)
        // Walk clockwise from B's sample around the far side to A's, then
        // DROP anything within 1.2pt of a junction anchor: overlapping or
        // crowding the anchors makes the spline backtrack (nub) or kink
        // (wart). With ~1.2pt sampling the remaining gap is sub-pixel — no
        // visible chord.
        let n0 = bnd.count
        var outline: [CGPoint] = []
        var i = (iB + 1) % n0
        while i != iA {
            let b = bnd[i]
            if hypot(b.x - ja.x, b.y - ja.y) > 1.2, hypot(b.x - jb.x, b.y - jb.y) > 1.2 {
                outline.append(b)
            }
            i = (i + 1) % n0
        }
        // Same de-crowding for the template's own points beside the anchors.
        outline.append(ja)
        for t in tailPts.dropFirst().dropLast()
        where hypot(t.x - ja.x, t.y - ja.y) > 1.0 && hypot(t.x - jb.x, t.y - jb.y) > 1.0 {
            outline.append(t)
        }
        outline.append(jb)

        // Closed Catmull-Rom spline over the whole outline: one continuous
        // silhouette, no unions, no seams. (A raw polyline facets at 3×.)
        let n = outline.count
        p.move(to: outline[0])
        for i in 0 ..< n {
            let p0 = outline[(i - 1 + n) % n]
            let p1 = outline[i]
            let p2 = outline[(i + 1) % n]
            let p3 = outline[(i + 2) % n]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            p.addCurve(to: p2, control1: c1, control2: c2)
        }
        p.closeSubpath()

        if side == .incoming {
            // Mirror so the tail lands bottom-left.
            p = p.applying(CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -w, y: 0))
        }
        return p
    }
}

/// Fill + text colors: Persona's monochrome bubbles on iMessage's geometry.
public enum IMessageBubblePalette {
    /// Screen-position gradient endpoints for the OUTGOING charcoal: iOS
    /// paints one vertical gradient across the viewport and each bubble
    /// reveals its slice. Endpoints are the Figma bubble spec verbatim —
    /// #272727 first stop (top) to #444444 (bottom) — so bubbles pick up a
    /// touch of lift lower on screen.
    public static let outgoingTop = Color(red: 0x27 / 255, green: 0x27 / 255, blue: 0x27 / 255)
    public static let outgoingBottom = Color(red: 0x44 / 255, green: 0x44 / 255, blue: 0x44 / 255)

    /// The user-bubble charcoal as a SELF-CONTAINED fill for chat components
    /// (composer send button, compose-sheet CTAs): the same #272727 → #444444
    /// ramp as the transcript bubbles, painted per element top→bottom — small
    /// controls don't join the bubbles' screen-position mechanic.
    public static var outgoingComponentFill: LinearGradient {
        LinearGradient(
            colors: [outgoingTop, outgoingBottom],
            startPoint: .top, endPoint: .bottom
        )
    }

    public static func incomingText(_ scheme: ColorScheme) -> Color {
        // Light ink is the design's #161616 (Figma bubble spec), not pure black.
        scheme == .dark ? .white : DS.Palette.ink
    }

    /// The outgoing screen-position fill for an arbitrary bubble: the bubble's
    /// charcoal is keyed to its GLOBAL position (exactly iOS's viewport
    /// gradient — darker high on screen, lighter low), tracked render-phase by
    /// a `visualEffect`, so scrolling never re-evaluates a body (the old
    /// GeometryReader version rebuilt a LinearGradient for every visible
    /// outgoing bubble on every scroll frame).
    ///
    /// The effect must stay COLOR-ONLY (`brightness`), never positional. The
    /// previous implementation slid a 2.7-screen-tall gradient plate with a
    /// `visualEffect` `offset` compensating the bubble's global minY — and a
    /// visualEffect proxy reads MODEL geometry. During the keyboard-close
    /// transaction the scroll clamp's model offset lands at its final value on
    /// the first frame, so the plate + clip rendered parked at the bubble's
    /// final screen position for the whole ~250ms ride while the text glyphs
    /// rode the presentation path — the "empty bubble descends, text detaches"
    /// artifact (60fps captures; only user bubbles showed it
    /// because incoming plates are plain layout). A brightness mismatch under
    /// the same model/presentation split is a ≤0x1D/255 shade lag for 250ms —
    /// invisible; a positional mismatch is the whole bubble elsewhere.
    /// (Uniform per-bubble shade replaces the old within-bubble ramp; across
    /// one bubble's height that ramp spanned single grey steps.)
    public static func outgoingFill() -> some View {
        #if canImport(UIKit)
            let screenH = max(UIScreen.main.bounds.height, 1)
        #else
            let screenH: CGFloat = 900
        #endif
        // outgoingTop 0x27 → outgoingBottom 0x44 across the screen height,
        // clamped for bubbles poking offscreen (the old plate's end pads).
        let span = Double(0x44 - 0x27) / 255.0
        return outgoingTop
            .visualEffect { content, proxy in
                let t = min(max(proxy.frame(in: .global).midY / screenH, 0), 1)
                return content.brightness(span * t)
            }
            // A fill never needs touches — a hittable fill's layout frame eats
            // taps meant for cards/links it overlaps.
            .allowsHitTesting(false)
    }

}

public extension View {
    /// The assistant (incoming) bubble surface: a solid white plate wearing
    /// exactly the Figma bubble spec's shadow — black 4%, y 3, blur σ2
    /// (match the mock; the old card depth pair's 18pt
    /// halo pooled between bubbles stacked 4pt apart). ONE recipe for every
    /// assistant-side surface — transcript bubbles, chat-card bubbles, thread
    /// reference chips, onboarding persona bubbles, task-thread panels.
    /// `enabled: false` is a pass-through, for call sites that pick the fill
    /// per message side.
    @ViewBuilder
    func incomingBubblePlate(in shape: some Shape, enabled: Bool = true) -> some View {
        if !enabled {
            self
        } else {
            // Light: the card white, unchanged. Dark: a clearly LIFTED gray
            // (iMessage-dark's incoming tone) — the shared card charcoal
            // (0x1E1F25) sat too close to the canvas and incoming bubbles
            // were barely readable.
            background(Color(light: 0xFFFFFF, dark: 0x2C2C2E), in: shape)
                .compositingGroup()
                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 3)
        }
    }
}

/// A single plain-text message bubble, 1:1 with iMessage at 17pt body type.
/// (The app's chat renders richer content through the same shape + palette.)
public struct IMessageBubble: View {
    @Environment(\.colorScheme) private var scheme

    let text: String
    let side: IMessageBubbleShape.Side
    var tail: Bool = true
    var maxWidth: CGFloat = 258

    public init(_ text: String, side: IMessageBubbleShape.Side, tail: Bool = true, maxWidth: CGFloat = 258) {
        self.text = text
        self.side = side
        self.tail = tail
        self.maxWidth = maxWidth
    }

    private var shape: IMessageBubbleShape { IMessageBubbleShape(side: side, tail: tail) }

    public var body: some View {
        Text(text)
            .font(.system(size: 17))
            .lineSpacing(22 - 20.29) // 22pt pitch, SF 17pt lineHeight 20.29
            .foregroundStyle(side == .outgoing ? .white : IMessageBubblePalette.incomingText(scheme))
            .padding(.top, 9.5)       // ink 13.7 − (ascender − capHeight)
            .padding(.bottom, tail ? 10.5 + IMessageBubbleShape.tailDip : 10.5)
            .padding(.horizontal, 14) // ink 15.5 − side bearing
            .background {
                if side == .outgoing {
                    IMessageBubblePalette.outgoingFill().clipShape(shape)
                }
            }
            .incomingBubblePlate(in: shape, enabled: side == .incoming)
            .frame(maxWidth: maxWidth, alignment: side == .outgoing ? .trailing : .leading)
    }
}

// MARK: - Timestamp separators (silence gap or day change)

/// When a message follows a stretch of silence (or opens the conversation),
/// iMessage centers a small "Today 9:41 AM" label above it — bold day-part,
/// regular time; the day ages Today → Yesterday → weekday → full date.
///
/// iMessage's gap is an hour, but iris pings proactively every ~50 minutes,
/// so an hour rule almost never fired in a real transcript (design's report:
/// "I never see them" — 68 live messages held exactly 3 stamps, all a day's
/// scroll away). 30 minutes restores the session-break feel the hour gives a
/// human conversation. A calendar-day change ALWAYS stamps, even mid-run —
/// scrolling into yesterday must say "Yesterday", whatever the pace.
public enum IMessageTimestampRule {
    public static let silenceGap: TimeInterval = 1800

    public static func label(
        for date: Date, previous: Date?, now: Date = Date(), calendar: Calendar = .current
    ) -> (day: String, time: String)? {
        if let previous,
           date.timeIntervalSince(previous) <= silenceGap,
           calendar.isDate(date, inSameDayAs: previous) { return nil }
        let time = date.formatted(.dateTime.hour().minute())
        let day: String
        if calendar.isDate(date, inSameDayAs: now) {
            day = "Today"
        } else if let yd = calendar.date(byAdding: .day, value: -1, to: now),
                  calendar.isDate(date, inSameDayAs: yd) {
            day = "Yesterday"
        } else if let wk = calendar.date(byAdding: .day, value: -6, to: now), date > wk {
            day = date.formatted(.dateTime.weekday(.wide))
        } else {
            day = date.formatted(.dateTime.month(.abbreviated).day().year())
        }
        return (day, time)
    }
}

// MARK: - Bubble run grouping (shared rhythm + tail rule)

/// The iMessage run rhythm the main chat transcript uses (ChatScreen.gapAbove /
/// isLastInGroup), factored out so the surfaces that render `ChatBubbleContent`
/// OUTSIDE ChatScreen — the suggestion sheet and the deep-task thread — share
/// the exact same constants and last-of-run tail rule.
///
/// ChatScreen keeps its own copies deliberately: its gap widens for inline
/// cards (`previous.cards`) and its runs break on timestamp separators too, so
/// folding it in here would tangle the extra cases. This type is the plain
/// two-sender core both simpler surfaces need.
public enum ChatBubbleGrouping {
    /// 4pt inside a same-sender run.
    public static let intraRunGap: CGFloat = 4
    /// 20pt across a sender change (a new run).
    public static let runGap: CGFloat = 20

    /// Vertical gap above a bubble given the sender of the BUBBLE immediately
    /// above it. `previousIsUser == nil` (transcript start, or a non-bubble row
    /// sat between them) opens a fresh run.
    public static func gapAbove(previousIsUser: Bool?, currentIsUser: Bool) -> CGFloat {
        guard let previousIsUser else { return runGap }
        return previousIsUser == currentIsUser ? intraRunGap : runGap
    }

    /// Whether this bubble owns the iMessage tail: only the LAST bubble of a
    /// consecutive same-sender run does. `nextIsUser` is the sender of the very
    /// next BUBBLE row, or nil when the next row is a non-bubble row (card,
    /// activity rail, …) or the transcript ends — each of which closes the run.
    public static func ownsTail(nextIsUser: Bool?, currentIsUser: Bool) -> Bool {
        guard let nextIsUser else { return true }
        return nextIsUser != currentIsUser
    }
}

/// The centered gray separator itself.
public struct IMessageDateSeparator: View {
    let day: String
    let time: String

    public init(day: String, time: String) {
        self.day = day
        self.time = time
    }

    public var body: some View {
        (Text(day).fontWeight(.semibold) + Text(" " + time))
            .font(.system(size: 11))
            .foregroundStyle(Color(red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255))
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 6)
    }
}

/// QA host (`BUBBLE_PREVIEW=1`): a scripted conversation exercising bubbles,
/// grouping/tails and the timestamp rule. No interactions.
public struct IMessageBubblePreviewHost: View {
    public init() {}

    public var body: some View {
        let cal = Calendar.current
        let now = cal.date(bySettingHour: 9, minute: 41, second: 0, of: Date()) ?? Date()
        let yesterday = cal.date(byAdding: .day, value: -1, to: now) ?? now
        let m1 = cal.date(bySettingHour: 21, minute: 12, second: 0, of: yesterday) ?? now
        let script: [(out: Bool, text: String, ts: Date)] = [
            (false, "Hi", m1),
            (false, "How is it going??", m1.addingTimeInterval(25)),
            (true, "yeah — traced it from the real captures", m1.addingTimeInterval(95)),
            (true, "ok", m1.addingTimeInterval(120)),
            (false, "morning. show me the timestamps", now),
            (true, "Ok, now we are going to do a test of border length, wrapping, etc", now.addingTimeInterval(60)),
        ]

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(script.enumerated()), id: \.offset) { idx, m in
                    let prev = idx > 0 ? script[idx - 1] : nil
                    if let sep = IMessageTimestampRule.label(for: m.ts, previous: prev?.ts, now: now) {
                        IMessageDateSeparator(day: sep.day, time: sep.time)
                    }
                    let next = idx < script.count - 1 ? script[idx + 1] : nil
                    let sepNext = next.map { IMessageTimestampRule.label(for: $0.ts, previous: m.ts, now: now) != nil } ?? false
                    let isLast = next == nil || next!.out != m.out || sepNext
                    let sameRun = prev != nil && prev!.out == m.out
                        && IMessageTimestampRule.label(for: m.ts, previous: prev!.ts, now: now) == nil
                    IMessageBubble(m.text, side: m.out ? .outgoing : .incoming, tail: isLast)
                        .frame(maxWidth: .infinity, alignment: m.out ? .trailing : .leading)
                        .padding(.top, sameRun ? 2 : 8)
                }
            }
            .padding(16)
        }
        // The app's canvas neutral (SharedAppBackground's base), so the
        // white assistant bubbles stay visible in the rig.
        .background(Color(red: 0xFD / 255, green: 0xFD / 255, blue: 0xFE / 255))
        .environment(\.colorScheme, .light)
    }
}
