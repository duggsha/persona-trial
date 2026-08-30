import PersonaDesign
import SwiftUI

// The deck's motion, transcribed. Every curve and duration below is written
// down in the prototype (persona-tokens.css + the flow-* sheets) — none of it
// is invented here, which is the same standard the geometry was held to.
//
// Reduce Motion is honoured at the source: the prototype guards each of these
// with `@media (prefers-reduced-motion: reduce)`, so every helper resolves to
// `nil` under the accessibility setting rather than to a faster animation.

enum GrammarMotion {
    /// `--press-ease` · cubic-bezier(0.23, 1, 0.32, 1). The finger's curve:
    /// leaves immediately, settles long. Presses, pops-in, trash.
    static func press(_ duration: TimeInterval = 0.14) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }

    /// `--ease-smooth` · cubic-bezier(0.32, 0.72, 0, 1) — the bezier stand-in
    /// for `Animation.smooth(extraBounce: 0)`, which a spring cannot be
    /// exactly. Rows closing, sheets, toasts, the pop-out.
    static func smooth(_ duration: TimeInterval) -> Animation {
        .timingCurve(0.32, 0.72, 0, 1, duration: duration)
    }

    /// `--press-dur` 140ms · `--motion-gentle` 220ms · `--motion-standard` 320ms.
    static let pressDuration: TimeInterval = 0.14
    static let gentle: TimeInterval = 0.22
    static let standard: TimeInterval = 0.32

    /// The clear, in the two movements flow-cleared.html insists on.
    enum Clear {
        /// The card leaves its own space first: 340ms, and it inflates to
        /// 1.035 at 30% before falling to 0.85 — it excuses itself rather than
        /// being deleted. Scale floors at 0.85 because nothing real vanishes
        /// to a point.
        static let popDuration: TimeInterval = 0.34
        static let popPeakFraction: Double = 0.30
        static let popPeakScale: CGFloat = 1.035
        static let popEndScale: CGFloat = 0.85
        /// Only THEN does the row close — and that is the shuffle. The cards
        /// below never animate themselves; the gap animates and they ride it.
        static let rowDuration: TimeInterval = 0.30
        static let rowDelay: TimeInterval = 0.06
        /// Undo's return is the pop reversed in spirit, not in tape: no
        /// inflate on the way in, just up from 0.94 as the row reopens.
        static let returnDuration: TimeInterval = 0.36
        static let returnDelay: TimeInterval = 0.12
        static let returnStartScale: CGFloat = 0.94
    }
}

// MARK: - Press

/// `.pressable` / `.pill:active` — scale, 140ms, on the press curve. The one
/// specified press in the deck, and the reason a day tile takes 0.97 rather
/// than 0.98: every pressable object answers the finger, and 0.98 on a 78pt
/// tile is invisible next to a full-width pill dipping the same amount.
struct GrammarPressStyle: ButtonStyle {
    var scale: CGFloat = 0.98
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(reduceMotion ? nil : GrammarMotion.press(), value: configuration.isPressed)
    }
}

extension View {
    /// Wraps a decorative element in the deck's press feedback. The action is
    /// empty on purpose — this branch is the design build, so the press is a
    /// visual answer to the finger and nothing else.
    func grammarPressable(scale: CGFloat = 0.98) -> some View {
        Button(action: {}) { self }
            .buttonStyle(GrammarPressStyle(scale: scale))
    }

    /// Reduce-Motion-aware animation, matching the prototype's guards.
    func grammarAnimation(_ animation: Animation, value: some Equatable) -> some View {
        modifier(GrammarReduceMotion(animation: animation, value: value))
    }
}

private struct GrammarReduceMotion<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

// MARK: - Entrance

/// `.draft-card` · `card-in` 260ms on the press curve, from 8pt down and
/// transparent. The drafted reply LANDS in the conversation rather than being
/// there all along — it is the one card in the deck the user watches arrive.
private struct GrammarCardIn: ViewModifier {
    @State private var arrived = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(arrived ? 1 : 0)
            .offset(y: arrived ? 0 : 8)
            .onAppear {
                guard !reduceMotion else { arrived = true; return }
                withAnimation(GrammarMotion.press(0.26)) { arrived = true }
            }
    }
}

extension View {
    func grammarCardIn() -> some View {
        modifier(GrammarCardIn())
    }
}
