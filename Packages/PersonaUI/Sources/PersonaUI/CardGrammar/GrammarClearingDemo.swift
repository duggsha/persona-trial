import PersonaDesign
import SwiftUI

// Clearing, and the shuffle behind it (flow-cleared.html).
//
// The invite page proved a card can file itself on a feed of ONE, which is the
// case that cannot fail. This is the same card over a real stack, because the
// question that decides whether auto-clearing ships is not how the card
// leaves — it is what the cards below do the moment it is gone.
//
// A card-shaped hole that snaps shut is a glitch, and so is a card that waits
// too long: past about a second the exit stops reading as a consequence of the
// tap. So the exit is TWO MOVEMENTS, NOT ONE — the card pops out of the plane
// (340ms, its own space), and only then does the row it stood in close
// (300ms), which is the motion the cards below read as moving up.
//
// The cards below never animate themselves. **The gap animates and they ride
// it**, so the shuffle cannot disagree with itself no matter how many are
// stacked — which here is simply what a VStack does when one child's height
// goes to zero.

struct GrammarClearingDemo: View {
    /// The stack under the invite: four cards that never move on their own.
    private let below: [GrammarCase] = [.ride, .orderProgress, .signInCode, .packageWaiting]

    @State private var answered = false
    @State private var collapsed = false
    @State private var popScale: CGFloat = 1
    @State private var popOpacity: CGFloat = 1
    @State private var toastShown = false
    @State private var naturalHeight: CGFloat?
    @State private var run: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let toast = UndoToastState(message: "Accepted", restore: {}, commit: {})

    private var invite: GrammarT1Model {
        guard case let .t1(model) = GrammarCase.invite.drawing else { fatalError("invite is T1") }
        return model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            controls
            ZStack(alignment: .bottom) {
                feed
                if toastShown {
                    // UndoToast fills whatever it is given (its capsule is
                    // maxWidth/maxHeight .infinity) — the caller owns the
                    // frame, and `toastWidth` is the value it expects: 184,
                    // or 208 once the copy passes ~16 characters.
                    UndoToast(message: toast.message, onUndo: { start(undo) }, onDismiss: { toastShown = false })
                        .frame(width: toast.toastWidth, height: 42)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .frame(width: GrammarChrome.feedWidth)
        // QA hook: motion cannot be screenshotted by hand, so the sequence can
        // be fired on appear and caught frame by frame.
        .task {
            guard ProcessInfo.processInfo.environment["GRAMMAR_CLEAR_AUTOPLAY"] == "1" else { return }
            try? await Task.sleep(for: .milliseconds(1200))
            await clear()
        }
    }

    private var feed: some View {
        VStack(spacing: 10) {
            GrammarT1Card(model: invite, settled: answered ? "Accepted — Thursday, 6:30 PM" : nil)
                .scaleEffect(popScale)
                .opacity(popOpacity)
                // Measure ONCE, unconstrained: the frame below feeds its own
                // height back in, so only the first reading is the real one.
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if naturalHeight == nil, height > 0 { naturalHeight = height }
                }
                .frame(height: naturalHeight.map { collapsed ? 0 : $0 }, alignment: .top)
                .clipped()
                // The row's own gap goes with it. A collapsed row still sits
                // between two 10pt gaps, so without this the stack lands one
                // gap too low — and the correction belongs to the card that is
                // leaving, not to the feed every card shares.
                .padding(.bottom, collapsed ? -10 : 0)
            ForEach(below) { card in
                GrammarCaseView(grammarCase: card)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            demoButton(answered ? "Answered" : "Accept") { start(clear) }
                .disabled(answered)
            demoButton("Reset") { start(reset) }
        }
    }

    private func demoButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Palette.ink)
                .padding(.horizontal, 15)
                .frame(height: 34)
                .background(DS.Palette.card, in: Capsule())
                .overlay { Capsule().strokeBorder(DS.Palette.hairline, lineWidth: 1) }
        }
        .buttonStyle(GrammarPressStyle())
    }

    // MARK: - The two movements

    private func start(_ body: @escaping () async -> Void) {
        run?.cancel()
        run = Task { await body() }
    }

    private func clear() async {
        guard !answered else { return }
        let clock = GrammarMotion.Clear.self

        // 1 · The answer lands at the speed of the tap — pills out, chip in —
        // and the toast rises with it, because the swap IS the feedback.
        animate(GrammarMotion.smooth(0.2)) { answered = true }
        animate(GrammarMotion.smooth(0.28)) { toastShown = true }
        await pause(0.22)

        // 2 · The card pops OUT OF THE PLANE: up a touch, then down through
        // 0.85 and gone. It leaves its own space first, so nothing below has
        // to move yet — and it floors at 0.85 because nothing real vanishes to
        // a point.
        let peak = clock.popDuration * clock.popPeakFraction
        animate(GrammarMotion.smooth(peak)) { popScale = clock.popPeakScale }
        await pause(peak)
        animate(GrammarMotion.smooth(clock.popDuration - peak)) {
            popScale = clock.popEndScale
            popOpacity = 0
        }
        await pause(clock.popDuration - peak + clock.rowDelay)

        // 3 · Only THEN does the row close, and that is the shuffle. The four
        // cards below ride the gap up together; not one of them is animated.
        animate(GrammarMotion.smooth(clock.rowDuration)) { collapsed = true }
    }

    /// The toast holds the door. Tapping it reopens the row, the stack rides
    /// back down, and the card comes back UNANSWERED — the RSVP was never sent.
    private func undo() async {
        let clock = GrammarMotion.Clear.self
        animate(GrammarMotion.smooth(0.22)) { toastShown = false }
        animate(GrammarMotion.smooth(clock.rowDuration)) { collapsed = false }
        await pause(clock.returnDelay)

        // No inflate on the way in, just up from 0.94 as the row reopens: the
        // card comes back, it does not bounce back.
        popScale = clock.returnStartScale
        animate(GrammarMotion.press(clock.returnDuration)) {
            popScale = 1
            popOpacity = 1
        }
        animate(GrammarMotion.smooth(0.2)) { answered = false }
    }

    private func reset() async {
        toastShown = false
        collapsed = false
        answered = false
        popScale = 1
        popOpacity = 1
    }

    private func animate(_ animation: Animation, _ changes: () -> Void) {
        withAnimation(reduceMotion ? nil : animation, changes)
    }

    /// Reduce Motion collapses the choreography to its end state rather than
    /// replaying it faster — the prototype's `prefers-reduced-motion` guards.
    private func pause(_ seconds: TimeInterval) async {
        guard !reduceMotion else { return }
        try? await Task.sleep(for: .seconds(seconds))
    }
}
