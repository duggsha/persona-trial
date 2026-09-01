import PersonaCore
import PersonaDesign
import PersonaService
import SwiftUI
import UIKit
// Required to assign `state` inside HoldTouchRecognizer (the UIKit
// subclassing contract exposes the setter through this submodule).
import UIKit.UIGestureRecognizerSubclass

/// Low-latency composer haptics with pre-warmed generators, so the listening
/// cue / mode-switch ticks fire without the first-tap delay. Mirrors Persona.
@MainActor
final class ComposerHapticModel: ObservableObject {
    private let tapGenerator = UIImpactFeedbackGenerator(style: .light)
    private let listeningGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let modeGenerator = UIImpactFeedbackGenerator(style: .light)
    private let deleteGenerator = UIImpactFeedbackGenerator(style: .light)
    private let selectionGenerator = UISelectionFeedbackGenerator()

    func prepare() {
        tapGenerator.prepare()
        listeningGenerator.prepare()
        modeGenerator.prepare()
        deleteGenerator.prepare()
        selectionGenerator.prepare()
    }

    func tap() {
        tapGenerator.impactOccurred(intensity: 0.85)
        tapGenerator.prepare()
    }

    func listeningStart() {
        listeningGenerator.prepare()
        listeningGenerator.impactOccurred(intensity: 0.68)
        listeningGenerator.prepare()
    }

    func modeChange() {
        selectionGenerator.selectionChanged()
        modeGenerator.impactOccurred(intensity: 0.42)
        selectionGenerator.prepare()
        modeGenerator.prepare()
    }

    func deleteRelease() {
        deleteGenerator.impactOccurred(intensity: 0.58)
        deleteGenerator.prepare()
    }
}

/// Live while a finger is down on any hold-to-record surface. Overlay chrome
/// (InteractiveEdgeDismiss) reads this to stand its drag gesture down for the
/// duration of the press: a recognized ancestor SwiftUI drag CANCELS the
/// surface's raw UIKit touches, and the surface maps cancellation to delete —
/// in a task thread, slide-up-to-cancel killed the memo the instant the finger
/// moved ~10pt instead of arming the red cancel state. (The main chat bar
/// never hit this: it sits OUTSIDE the edge-dismiss subtree.) A shared
/// observable carries the state up to the edge-dismiss gesture out-of-band,
/// so the two gestures arbitrate without a preference round-trip. Claimed on
/// touch-down — before the 10pt recognition
/// threshold any drag needs — not on hold-start, so even a fast slide can't
/// beat the mask flip.
@MainActor
final class VoiceHoldClaim: ObservableObject {
    static let shared = VoiceHoldClaim()
    @Published private(set) var isActive = false

    func claim() { if !isActive { isActive = true } }
    func release() { if isActive { isActive = false } }
}

/// UIKit touch surface that distinguishes a quick tap (focus the field) from a
/// hold (begin a voice memo) and tracks slide-up-to-cancel while listening.
/// Exact port of the design app's ComposerTouchInteractionView.
final class ComposerTouchInteractionView: UIView {
    var onTap: (() -> Void)?
    var onListeningBegan: (() -> Void)?
    var onReleaseModeChanged: ((VoiceReleaseMode) -> Void)?
    var onFinished: (() -> Void)?
    /// Touch-down / touch-up for the whole press, BEFORE the tap-vs-hold
    /// classification. The bar's press swell rides this: the system's
    /// interactive-glass swell cancels itself when voice mode re-renders the
    /// capsule 0.1s into the hold (the expand-then-snap-back), so the composer
    /// owns the swell off the raw press instead.
    var onPressChanged: ((Bool) -> Void)?
    /// The press entered voice mode but was released quickly enough to still be
    /// a tap — abort the memo silently and focus the field instead. Without
    /// this rescue, a 0.1s trigger makes ordinary taps (80–150ms+) land in
    /// voice mode and the keyboard "sometimes" never opens.
    var onAbortedToTap: (() -> Void)?
    /// Card-hosted surfaces (the universal card's mic) live INSIDE a scroll
    /// view — sliding up toward release-to-delete makes the scroll gesture
    /// recognize and CANCEL our raw touches, which reads as an instant silent
    /// discard (`scrollDisabled` stops the scrolling, not the recognition —
    /// and on iOS 26 the SwiftUI scroll gesture isn't even a UIScrollView
    /// pan we could disable). Hosted-in-scroll surfaces therefore track the
    /// press through a GESTURE RECOGNIZER that enters `.began` at touch-down:
    /// a began recognizer keeps its touch stream when a sibling scroller
    /// fires `cancelsTouchesInView`, so the hold survives any amount of
    /// finger travel and release/slide-back stays live. Ancestor UIScrollView
    /// pans are also stood down for the press as a belt. Off for the composer
    /// (no scroll ancestors — raw-touch transport, bit-identical behavior).
    var isHostedInScrollView = false {
        didSet {
            guard isHostedInScrollView, holdRecognizer == nil else { return }
            let recognizer = HoldTouchRecognizer(surface: self)
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            addGestureRecognizer(recognizer)
            holdRecognizer = recognizer
        }
    }

    private var holdRecognizer: HoldTouchRecognizer?

    // Voice mode shows itself after a barely-perceptible 0.1s hold (the mic
    // spins up behind the already-visible UI). Releases under
    // `tapRescueMaximumDuration` are re-classified as taps via `onAbortedToTap`,
    // so THAT is the only real tap/record boundary — 0.1s is just a head start.
    private let holdDelay: TimeInterval = 0.10
    /// Settable per surface: the bar raises it to `focusedTapRescueMaximum`
    /// while the keyboard is up. See the call site.
    var tapRescueMaximumDuration: TimeInterval = ComposerTouchInteractionView.defaultTapRescueMaximum
    /// 0.32s — snappy enough that push-to-talk never feels like it's waiting.
    static let defaultTapRescueMaximum: TimeInterval = 0.32
    /// 0.5s — Apple's own `UILongPressGestureRecognizer` default, used on the
    /// BAR while focused: there a slow press is ambiguous between "hold to
    /// speak" and "tap for the Paste menu", and the wrong answer sends a voice
    /// message. The mic surfaces keep the snappy value — a slow press there
    /// picks between hold-record and hands-free record, never paste, and
    /// stretching their window makes a released hold keep recording instead.
    static let focusedTapRescueMaximum: TimeInterval = 0.50
    private let tapMaximumMovement: CGFloat = 8
    private var startPoint: CGPoint = .zero
    private var latestPoint: CGPoint = .zero
    private var startTime: TimeInterval = 0
    private var holdWorkItem: DispatchWorkItem?
    private var isTrackingTouch = false
    private var isListening = false
    private var releaseMode: VoiceReleaseMode = .send
    /// Ancestor pans stood down for the current press (pan, its prior
    /// isEnabled) — scroll views' pans AND any other vertical drags above the
    /// surface, notably a SHEET's drag pan: allowed to ride along (the
    /// simultaneous-recognition delegate keeps our touch stream alive), it
    /// visibly drags the sheet under a finger that's recording a memo.
    private var suppressedAncestorPans: [(UIPanGestureRecognizer, Bool)] = []
    /// Scroll views whose right to cancel content touches is parked (scroll,
    /// its prior canCancelContentTouches).
    private var suppressedScrollTouchCancels: [(UIScrollView, Bool)] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = false
        isExclusiveTouch = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Raw-touch transport (composer surfaces). Scroll-hosted surfaces receive
    // the same stream through HoldTouchRecognizer instead — the guards keep
    // the two transports from double-driving the state machine.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isHostedInScrollView else { return }
        handleTouchesBegan(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isHostedInScrollView else { return }
        handleTouchesMoved(touches)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isHostedInScrollView else { return }
        handleTouchesEnded(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isHostedInScrollView else { return }
        handleTouchesCancelled()
    }

    func handleTouchesBegan(_ touches: Set<UITouch>) {
        guard let touch = touches.first, !isTrackingTouch else { return }

        startPoint = touch.location(in: self)
        latestPoint = startPoint
        startTime = CACurrentMediaTime()
        isTrackingTouch = true
        isListening = false
        releaseMode = .send
        onPressChanged?(true)
        VoiceHoldClaim.shared.claim()
        if isHostedInScrollView { suppressAncestorScrollPans() }

        let workItem = DispatchWorkItem { [weak self] in
            self?.beginListeningIfNeeded()
        }
        holdWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDelay, execute: workItem)
    }

    func handleTouchesMoved(_ touches: Set<UITouch>) {
        guard isTrackingTouch, let touch = touches.first else { return }
        latestPoint = touch.location(in: self)
        if isListening { updateReleaseMode(for: latestPoint) }
    }

    func handleTouchesEnded(_ touches: Set<UITouch>) {
        guard isTrackingTouch else {
            reset()
            return
        }

        if let touch = touches.first { latestPoint = touch.location(in: self) }
        holdWorkItem?.cancel()

        let duration = CACurrentMediaTime() - startTime
        let movement = hypot(latestPoint.x - startPoint.x, latestPoint.y - startPoint.y)

        if isListening {
            // A short, still press that slipped past the 0.1s trigger is a tap.
            if duration <= tapRescueMaximumDuration, movement <= tapMaximumMovement {
                onAbortedToTap?()
            } else {
                // Released while listening → finish the voice memo.
                updateReleaseMode(for: latestPoint)
                onFinished?()
            }
            reset()
            return
        }

        // Released before the hold delay fired → it's a tap: focus the field.
        if movement <= tapMaximumMovement {
            onTap?()
        }

        reset()
    }

    func handleTouchesCancelled() {
        holdWorkItem?.cancel()
        if isListening {
            releaseMode = .delete
            onReleaseModeChanged?(.delete)
            onFinished?()
        }
        reset()
    }

    private func beginListeningIfNeeded() {
        guard isTrackingTouch, !isListening else { return }
        isListening = true
        releaseMode = .send
        onListeningBegan?()
        updateReleaseMode(for: latestPoint)
    }

    private func updateReleaseMode(for point: CGPoint) {
        let upwardTranslation = point.y - startPoint.y
        let nextMode: VoiceReleaseMode = (upwardTranslation < -42 || point.y < -8) ? .delete : .send
        guard nextMode != releaseMode else { return }
        releaseMode = nextMode
        onReleaseModeChanged?(nextMode)
    }

    private func reset() {
        holdWorkItem?.cancel()
        holdWorkItem = nil
        // Only a live press sends the up — reset() also runs from the
        // not-tracking guard in touchesEnded, and a spurious `false` would
        // re-render the composer on every stray touch.
        if isTrackingTouch { onPressChanged?(false) }
        isTrackingTouch = false
        isListening = false
        releaseMode = .send
        startPoint = .zero
        latestPoint = .zero
        startTime = 0
        restoreAncestorScrollPans()
        VoiceHoldClaim.shared.release()
    }

    /// Disable every ancestor pan (and every scroll view's right to cancel
    /// our touches) for the life of this press. Deliberately ALL pans, not
    /// just scroll views': the sheet presentation's drag recognizer lives on
    /// the presented container between us and the window, and left enabled it
    /// tracks the hold's slide — the sheet follows the finger mid-memo.
    /// Stops short of the window itself (system edge gestures stay live).
    /// Idempotent per press.
    private func suppressAncestorScrollPans() {
        guard suppressedAncestorPans.isEmpty, suppressedScrollTouchCancels.isEmpty else { return }
        var ancestor = superview
        while let view = ancestor, !(view is UIWindow) {
            for recognizer in view.gestureRecognizers ?? [] {
                guard let pan = recognizer as? UIPanGestureRecognizer else { continue }
                suppressedAncestorPans.append((pan, pan.isEnabled))
                pan.isEnabled = false
            }
            if let scroll = view as? UIScrollView {
                suppressedScrollTouchCancels.append((scroll, scroll.canCancelContentTouches))
                scroll.canCancelContentTouches = false
            }
            ancestor = view.superview
        }
    }

    private func restoreAncestorScrollPans() {
        for (pan, wasEnabled) in suppressedAncestorPans {
            pan.isEnabled = wasEnabled
        }
        suppressedAncestorPans.removeAll()
        for (scroll, couldCancel) in suppressedScrollTouchCancels {
            scroll.canCancelContentTouches = couldCancel
        }
        suppressedScrollTouchCancels.removeAll()
    }

    // A surface torn down mid-press (mode flip, host unmount) gets no
    // touchesEnded — release the claim so the edge-dismiss drag isn't
    // masked off forever.
    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { reset() }
    }
}

extension ComposerTouchInteractionView: UIGestureRecognizerDelegate {
    /// Ride along with everything (scrolling is separately frozen via
    /// VoiceHoldClaim → scrollDisabled) — the recognizer's job is only to
    /// keep OWNING its touch stream, never to win arbitration fights.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

/// The scroll-hosted hold transport: a recognizer that enters `.began` at
/// touch-down and forwards its touch stream to the surface's state machine.
/// Unlike the view's raw `touches*` methods, an active recognizer is NOT
/// silenced by a sibling scroll gesture's `cancelsTouchesInView` — the press
/// keeps tracking through slide-up, slide-back, and release.
private final class HoldTouchRecognizer: UIGestureRecognizer {
    private weak var surface: ComposerTouchInteractionView?

    init(surface: ComposerTouchInteractionView) {
        self.surface = surface
        super.init(target: nil, action: nil)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if state == .possible { state = .began }
        surface?.handleTouchesBegan(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        state = .changed
        surface?.handleTouchesMoved(touches)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        surface?.handleTouchesEnded(touches)
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        surface?.handleTouchesCancelled()
        state = .cancelled
    }
}

struct ComposerTouchInteractionSurface: UIViewRepresentable {
    let onTap: () -> Void
    let onListeningBegan: () -> Void
    let onReleaseModeChanged: (VoiceReleaseMode) -> Void
    let onFinished: () -> Void
    let onAbortedToTap: () -> Void
    /// Raw press lifecycle (see ComposerTouchInteractionView.onPressChanged).
    var onPressChanged: ((Bool) -> Void)? = nil
    /// How long a press may last and still be rescued into a tap. Defaults to
    /// the snappy 0.32s; the bar passes the 0.5s focused value.
    var tapRescueMaximumDuration: TimeInterval = ComposerTouchInteractionView.defaultTapRescueMaximum
    /// See ComposerTouchInteractionView.isHostedInScrollView — on for
    /// surfaces hosted inside a scroll view (the universal card's mic).
    var isHostedInScrollView = false

    func makeUIView(context: Context) -> ComposerTouchInteractionView {
        let view = ComposerTouchInteractionView()
        updateHandlers(for: view)
        return view
    }

    func updateUIView(_ uiView: ComposerTouchInteractionView, context: Context) {
        updateHandlers(for: uiView)
    }

    private func updateHandlers(for view: ComposerTouchInteractionView) {
        view.onTap = onTap
        view.onListeningBegan = onListeningBegan
        view.onReleaseModeChanged = onReleaseModeChanged
        view.onFinished = onFinished
        view.onAbortedToTap = onAbortedToTap
        view.onPressChanged = onPressChanged
        view.tapRescueMaximumDuration = tapRescueMaximumDuration
        view.isHostedInScrollView = isHostedInScrollView
    }
}

/// Widens the focused field's touch target from the glyphs to the whole
/// capsule row.
///
/// The bar is 54pt tall and the text line inside it is 20 of them: two thirds
/// of what reads as "the message" is padding, and UIKit's text interactions
/// (caret placement, the loupe, drag-select, the selection menu) live on the
/// text view alone. So a press 10pt above the words — visibly inside the bar,
/// on the message the user is aiming at — did nothing whatsoever
/// "it only works when I'm doing it directly over the text".
///
/// This is a hit-test shim, not a gesture. It owns no recognizers and adds no
/// behaviour of its own; it answers `hitTest` with the live text view, so a
/// press anywhere on the row drives exactly the interaction it would over the
/// glyphs. Nothing to keep in sync with UIKit's text stack, and no second
/// implementation of selection to drift from Apple's.
///
/// Mounted only while the field is focused AND holds a draft — precisely the
/// complement of the hold-to-speak surfaces' `!hasText` gate, so exactly one
/// of the two owns the capsule at any moment and neither can eat the other's
/// touches.
struct ComposerTextHitExpander: UIViewRepresentable {
    func makeUIView(context _: Context) -> ComposerTextHitExpanderView {
        ComposerTextHitExpanderView()
    }

    func updateUIView(_: ComposerTextHitExpanderView, context _: Context) {}
}

final class ComposerTextHitExpanderView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01,
              self.point(inside: point, with: event),
              let field = forwardingTarget()
        else { return nil }
        // Deliberately NOT `super.hitTest`: this view has no subviews and must
        // never answer for itself — a touch it can't forward belongs to
        // whatever is underneath (the field's own glyphs, the bar's tap).
        return field
    }

    /// The focused text view — but only when it is genuinely the field this
    /// shim is laid over. A sheet's own field can be first responder while the
    /// composer is still mounted underneath it, and steering a press into a
    /// view the user cannot see is worse than the dead zone. Overlapping
    /// frames is the honest test: this shim IS the capsule row the field
    /// sits in.
    private func forwardingTarget() -> UIView? {
        guard let window,
              let field = PersonaFirstResponder.current() as? UIView & UITextInput,
              field.window === window
        else { return nil }
        return convert(bounds, to: window).intersects(field.convert(field.bounds, to: window))
            ? field : nil
    }
}

/// idle ⇄ hold (press-and-hold) and idle ⇄ manualRecording ⇄ manualReady
/// (tap-to-record). `isManual` hides the hold touch-surface so the stop/send
/// buttons take over.
private enum VoiceMemoMode: Equatable {
    case idle
    case hold
    case manualRecording
    case manualReady

    var isActive: Bool {
        self != .idle
    }

    var isManual: Bool {
        switch self {
        case .manualRecording, .manualReady: true
        case .idle, .hold: false
        }
    }
}

/// The staged-document tile in the composer's attachment row — the file
/// counterpart of the 70×70 photo thumbnail, same size, same corner language.
/// A folded paste previews its own first lines in miniature (so the tile reads
/// as "your text, now an attachment"); a picked document shows a doc glyph and
/// its filename.
struct ComposerFileTile: View {
    let file: ChatFileAttachment

    private var isPasted: Bool {
        file.filename == ChatMessage.pastedAttachmentName && file.mimeType == "text/plain"
    }

    /// First lines of the pasted text for the miniature. Decoded off a byte
    /// prefix — plenty for a 70pt tile, never the whole multi-kB attachment.
    private var snippet: String {
        String(decoding: file.data.prefix(600), as: UTF8.self)
    }

    var body: some View {
        Group {
            if isPasted {
                VStack(alignment: .leading, spacing: 0) {
                    Text(snippet)
                        .font(.system(size: 6, weight: .regular))
                        .foregroundStyle(DS.Palette.ink.opacity(0.55))
                        .lineSpacing(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 7)
                        .padding(.top, 6)
                        .clipped()
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.clipboard.fill")
                            .font(.system(size: 7, weight: .semibold))
                        Text("Pasted")
                            .font(.system(size: 8.5, weight: .semibold))
                    }
                    .foregroundStyle(DS.Palette.ink.opacity(0.65))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(DS.Palette.ink.opacity(0.05))
                }
            } else {
                let badge = FileTypeBadge(filename: file.filename, mimeType: file.mimeType)
                VStack(spacing: 5) {
                    Image(systemName: badge.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(badge.tint)
                    Text(file.filename)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(DS.Palette.ink.opacity(0.65))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                }
            }
        }
        .frame(width: 70, height: 70)
        .background(DS.Palette.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(DS.Palette.ink.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// The floating "Ask Iris anything" bar. Tap to type; hold the bar to record a
/// voice memo (slide up to cancel); tap the mic to record hands-free, then stop
/// and send. A released memo is ALWAYS handed off as audio — every surface
/// transcribes server-side (or sends a real voice message). On-device Apple
/// speech recognition is gone: it was permission-gated and silently produced
/// nothing when the grant was missing.
struct PersonaComposer: View {
    @Binding var draft: String
    @FocusState.Binding var isFocused: Bool
    let onSend: () -> Void
    /// Called with the recorded clip + its duration once a memo is released/sent.
    /// Ownership of the file passes to the caller (it uploads, then may delete it).
    let onVoiceMessage: (URL, TimeInterval) -> Void
    /// Fired the instant the hold takes and recording starts — BEFORE any audio
    /// exists. Voice mode hangs off this, not off the release, because the HUD
    /// belongs on screen while you're still talking.
    var onListeningBegan: (() -> Void)?
    /// When something else owns the hold (voice mode), the memo recorder stands
    /// down entirely instead of racing it — otherwise the bar reports "didn't
    /// catch that" underneath a voice flow that plainly worked.
    var voiceHandledExternally = false
    var hasAttachment = false
    /// Staged photos rendered INSIDE the input capsule (iMessage-style), each
    /// with its remove control — up to 5; the row scrolls when they overflow.
    /// The bar grows to hold them.
    var pendingImages: [Data] = []
    /// Remove the staged photo at this index.
    var onRemoveImage: (Int) -> Void = { _ in }
    /// A staged document — a picked file or a long paste folded into a
    /// "Pasted" attachment. Rendered inside the capsule's grown top region as
    /// a tile next to the photo, same size, same remove control.
    var pendingFile: ChatFileAttachment? = nil
    var onRemoveFile: () -> Void = {}
    /// Tap on the staged document tile — previews its content before sending
    /// (the host presents; the composer lives in its own hosting controller).
    var onTapFile: () -> Void = {}
    /// An image pasted from the clipboard, normalized to JPEG — stage it as a
    /// photo (see `ComposerImagePaste`). nil on purpose for hosts with nowhere
    /// to put a picture: they keep the plain-text paste rather than swallowing
    /// the image into nothing.
    var onPasteImage: ((Data) -> Void)? = nil
    /// The media strip's three handlers. NIL (the default) means the host does
    /// not accept that kind of attachment, and the row is omitted rather than
    /// rendered dead: a Camera / Photos / Files tap that silently does nothing
    /// is how the task thread read as broken for months (every host but the
    /// main chat inherited a no-op closure and showed the full menu anyway).
    /// A host wires what it can actually send; the menu shows exactly that.
    var onCamera: (() -> Void)? = nil
    /// "Photos" in the attach menu: pick from the photo library directly
    /// (onCamera opens the capture sheet; this skips straight to the picker).
    var onPhotoLibrary: (() -> Void)? = nil
    /// "Files" in the attach menu: attach a document.
    var onAttachFile: (() -> Void)? = nil
    /// The + menu's upper shelf: create/start actions (reminder, email,
    /// automations, seed-chat starts) as rows above the pinned Camera /
    /// Photos / Files media strip. Empty (every host but the main chat) →
    /// the menu is the media strip alone. The composer wraps each action so
    /// a tap collapses the bloom before the host's handler fires.
    var quickActions: [ComposerAttachMenuItem] = []
    var isReplyActive = false
    /// Hard OFF switch for the floating attach button (the + LEFT of the
    /// capsule, with its bloom menu): the capsule takes the full bar width — for
    /// contexts that only accept text. Typography, focus and keyboard-follow
    /// stay identical. Leaving it true is not enough to show the +: the host
    /// must also wire at least one attach handler or quick action (see
    /// hasAttachMenu), so the menu can never offer a row that does nothing.
    var showsCamera = true
    /// Holds the + in its recording-mode look for the bar's whole life: 0.35
    /// opacity, no hits, still occupying its slot so the capsule keeps the home
    /// bar's exact width. For surfaces that want the home bar's geometry without
    /// offering attachments (the card reply sheet). The handlers stay wired, so
    /// lifting this restores a working menu rather than dead rows.
    var attachDimmed = false
    /// The bar is mounted over a FLAT sheet background rather than over the
    /// feed. The capsule and the + are a 5%-white tint carried by glass, which
    /// needs content behind it to refract — over a flat sheet it has none, so
    /// the bar dissolves into the background and the dimmed + loses its plate
    /// entirely. This is the trap `solidListPlate` was written for. On, the two
    /// surfaces take a real fill and a hairline instead, so the bar keeps a
    /// visible edge and the + still reads a plate when it's stepped back.
    var onFlatSurface = false
    /// When false, the mic and hold-to-record surface are omitted; the trailing
    /// button is always Send (dimmed until there's text). For text-only contexts.
    var showsVoice = true
    /// Overrides the cycling placeholder prompts. A single entry disables cycling.
    var placeholderPrompts: [String]? = nil
    /// See ComposerTouchInteractionView.isHostedInScrollView — required for
    /// composers mounted where an ancestor gesture can cancel raw touches: a
    /// scroll view, or a SHEET (its vertical pan tracks every drag, and a
    /// hold-to-record slide-up otherwise dies as touchesCancelled — an
    /// instant silent delete instead of the red release-to-delete state).
    var isHostedInScrollView = false
    /// The assistant's per-user name for the default placeholder. Passed in as a
    /// value (not read via @Environment) so preview/QA rigs that mount the
    /// composer without a ProfileStore still render.
    var assistantName: String = ProfileStore.defaultAssistantName
    /// Coach-mark over the composer (the reusable DSTooltip) — hosts opt
    /// in by passing a binding (first-run tip, QA rigs). The presenting host
    /// applies `.dsTooltipHost()` above the composer so the tooltip anchor
    /// resolves against it.
    var voiceTipPresented: Binding<Bool> = .constant(false)
    /// One-shot "start tap-to-record now" request — the quick-voice triggers
    /// (Action Button control / Back Tap / Siri) land here after routing to the
    /// chat page. Consumed (reset to false) the moment capture starts; checked
    /// on appear AND on change so the request survives arriving before or after
    /// the composer mounts. Starts the exact mode the trailing mic tap starts;
    /// the begin guard (idle, no draft text) applies the same.
    var voiceCaptureRequested: Binding<Bool> = .constant(false)
    /// One-shot stop-and-send for a running tap-to-record (the band button's
    /// second press). No-ops unless a manual recording is live or parked in
    /// its ready pill — see `consumeVoiceSendRequest`.
    var voiceSendRequested: Binding<Bool> = .constant(false)

    @State private var promptIndex = 0
    /// The + button's window-space frame — the bloom menu's anchor, and the
    /// overlay's pass-through rect so the button's own toggle never races the
    /// outside-tap dismissal.
    @State private var attachButtonRect: CGRect = .zero
    /// Owns the window-attached bloom menu (quick-action shelf + Camera /
    /// Photos / Files strip). An
    /// OVERLAY, not in-flow chrome: the bar lives in a bottom-pinned,
    /// intrinsically-sized hosting view, and growing that tree to hold the
    /// menu makes the intrinsic-size animation lag the hosting frame — the
    /// bar visibly shifts (same wobble the task thread's overview panel hit,
    ///). The composer must not move a point when the menu opens.
    @StateObject private var attachMenu = ComposerAttachMenuPresenter()
    /// QA-only, armed via the env-gated button below: the next send re-marks a
    /// composition right after the pre-send commit (the prediction-keyboard
    /// race that drops the programmatic clear). One-shot.
    @State private var qaRearmComposition = false
    @State private var qaLateTeardownArmed = false
    @State private var qaLateTeardownFired = false
    @State private var qaWedgeArmed = false
    @State private var qaWedgeInFlight = false
    @State private var voiceMemoMode: VoiceMemoMode = .idle
    @State private var voiceReleaseMode: VoiceReleaseMode = .send
    /// A finger is down on one of the capsule's hold-to-record surfaces. Drives
    /// the bar's press swell for the WHOLE press — the system interactive-glass
    /// swell cancels when voice mode re-renders the capsule mid-hold (the bar
    /// visibly snapped back while the finger was still down), so the capsule's
    /// glass is non-interactive and the swell is owned here instead.
    @State private var isHoldSurfacePressed = false
    @State private var voiceMemoStartedAt: Date?
    @State private var voiceMemoStoppedDuration: TimeInterval = 0
    @State private var pendingMemoURL: URL?
    /// Transient note in the placeholder slot after a voice memo was dropped
    /// (too short / silent / recorder not ready). The only cue used to be the
    /// delete haptic, which beta testers read as "my recording just vanished".
    @State private var voiceDiscardHint: String?
    /// Set while the voice coach mark is PARKED for a system edit menu, so it
    /// can be put back when the menu closes. Parking is not dismissal — the
    /// user still owes the tip an answer — so the flag has to be remembered
    /// separately rather than inferred from the tip being absent.
    @State private var editMenuSuppressedTip = false
    /// Whether the system edit menu is on screen right now, tracked off the
    /// interaction's own presentation callbacks. The re-tap that summons the
    /// pill is the same tap the user reaches for to put it away, so the bar has
    /// to know which of the two it is holding.
    @State private var editMenuVisible = false
    /// When the pill last went away. UIKit's own outside-tap dismissal can land
    /// BEFORE the tap gesture that caused it ends — without this the flag reads
    /// false by then and the "close" tap re-presents, which is exactly the
    /// menu-looks-stuck symptom.
    @State private var editMenuClosedAt: Date?
    @State private var voiceDiscardHintClearTask: Task<Void, Never>?
    @StateObject private var voiceMeter = VoiceMemoRecorder()
    @StateObject private var composerHaptics = ComposerHapticModel()

    private var prompts: [String] {
        if let placeholderPrompts { return placeholderPrompts }
        var defaults = [String(localized: "Ask \(assistantName) to do anything")]
        // Never when voice is off. Held back while FOCUSED even though the
        // hold surface now survives focus: half the line ("Tap to type") is
        // nonsense with the keyboard already up, and a rotating prompt under a
        // live caret reads as text the user typed.
        if showsVoice, !isFocused {
            defaults.append(String(localized: "Tap to type, hold to speak"))
        }
        return defaults
    }

    private var hasText: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True while the hold-to-record touch surfaces own the capsule's bottom
    /// row — they cover it edge to edge and route every tap themselves. The
    /// bar surface's own gate is the loosest of the three (`!hasText` implies
    /// the mic surfaces' `!hasMessage` / attachment gates), so this IS the
    /// union. Read by the ancestor tap gesture, which must stand down while
    /// they're up.
    private var isHoldSurfaceMounted: Bool {
        showsVoice && !hasText && !voiceMemoMode.isManual
    }

    /// Screen-relative bar width: fixed 16pt gutters each side — the traced
    /// 362pt design on its 393pt base canvas, generalized. The bar used to BE
    /// a literal 362pt on every device, which read near-full-width on a mini
    /// but left ~39pt of dead margin per side on a Max. Every internal
    /// x-position below derives from this via its designed distance from the
    /// bar's edges, so the chrome keeps its traced spacing at any width.
    /// (Screen-derived, not GeometryReader: the composer is absolute-
    /// positioned around a rigid frame, and every host is a full-screen-width
    /// surface — the hosts' own horizontal padding centers rigid frames
    /// symmetrically either way.)
    private var barWidth: CGFloat {
        max(UIScreen.main.bounds.width, 320) - 32
    }

    /// The floating attach button's diameter and its gap to the capsule.
    /// 44 (not the capsule's 54) reads as a satellite of the bar, not a second
    /// bar; the (54−44)/2 bottom padding centers it on the single-line row.
    static let attachButtonSize: CGFloat = 44
    static let attachButtonGap: CGFloat = 10

    /// The input capsule's width: the attach button + gap carve their slot out
    /// of the fixed-gutter bar, so button + capsule together keep the 16pt
    /// screen gutters every host aligns to.
    private var capsuleWidth: CGFloat {
        hasAttachMenu ? barWidth - Self.attachButtonSize - Self.attachButtonGap : barWidth
    }

    var body: some View {
        // NOT a Capsule: the radius is frozen at the single-line capsule value
        // (54/2) so the collapsed bar looks identical, but as the field grows
        // with wrapped lines the corners read progressively straighter instead
        // of ballooning into a giant pill.
        let surface = RoundedRectangle(cornerRadius: 27, style: .continuous)
        // An attached image alone is a valid message (image-only send), so the
        // trailing button becomes Send even with an empty text field.
        let hasMessage = hasText || hasAttachment
        let isVoiceMemoActive = voiceMemoMode.isActive
        let promptText = prompts.indices.contains(promptIndex) ? prompts[promptIndex] : (prompts.first ?? "")
        // The attach affordance floats OUTSIDE the capsule (iMessage's +), so
        // the text region starts at the capsule's own leading edge everywhere.
        // Widths are edge-relative: the text region absorbs whatever a wider
        // screen adds; the chrome does not.
        let textLeading: CGFloat = 22
        let textWidth: CGFloat = capsuleWidth - 87

        // Bottom-anchored so a growing text field extends the bar UPWARD while
        // the send / voice chrome stays pinned to the bottom row. Staged
        // attachments (photo / document) add a row INSIDE the capsule above
        // the text line, like iMessage's composer.
        let attachmentRowHeight: CGFloat = (!pendingImages.isEmpty || pendingFile != nil) ? 86 : 0
        HStack(alignment: .bottom, spacing: Self.attachButtonGap) {
            if hasAttachMenu {
                attachButton
                    .padding(.bottom, (54 - Self.attachButtonSize) / 2)
            }
            capsuleBody(
                surface: surface,
                hasMessage: hasMessage,
                isVoiceMemoActive: isVoiceMemoActive,
                promptText: promptText,
                textLeading: textLeading,
                textWidth: textWidth,
                attachmentRowHeight: attachmentRowHeight
            )
        }
        .frame(width: barWidth, alignment: .leading)
        .onAppear {
            composerHaptics.prepare()
            consumeVoiceCaptureRequest()
        }
        .onChange(of: voiceCaptureRequested.wrappedValue) { _, requested in
            if requested { consumeVoiceCaptureRequest() }
        }
        // Deliberately no onAppear consume (unlike capture): a send request
        // with no recording on screen is stale by definition and must die,
        // not fire against the next recording.
        .onChange(of: voiceSendRequested.wrappedValue) { _, requested in
            if requested { consumeVoiceSendRequest() }
        }
        // The system edit menu anchors at the CARET, which puts it in the same
        // strip above the capsule as the coach mark — they drew on top of each
        // other, the menu's material eating the bubble's first word. Park the
        // tip for the menu's lifetime and restore it after.
        //
        // This drives `voiceTipPresented` (the tip's REAL state, owned by the
        // root) rather than hiding the bubble locally. That is load-bearing:
        // the anchor preference only reaches DSTooltipHostLayer when the view
        // that owns the state re-renders, so a composer-local "hidden" flag
        // leaves the transform reporting false while the bubble paints on.
        .onReceive(NotificationCenter.default.publisher(for: .personaComposerEditMenuVisibility)) {
            let menuUp = $0.userInfo?["visible"] as? Bool ?? false
            noteEditMenu(visible: menuUp)
            // Composers with no tip binding (.constant(false)) no-op on both
            // branches — the restore is gated on having parked it here.
            if menuUp, voiceTipPresented.wrappedValue {
                editMenuSuppressedTip = true
                voiceTipPresented.wrappedValue = false
            } else if !menuUp {
                restoreTipAfterEditMenu()
            }
        }
        // `willDismissMenuFor` is not guaranteed: typing dismisses the menu
        // without UIKit reporting it, which used to strand the parked tip
        // off-screen for good — and would now strand the toggle believing a
        // long-gone pill is still up, eating the next tap. Anything that
        // certainly means "the menu is gone" clears both.
        .onChange(of: draft) { _, _ in forgetEditMenu() }
        .onChange(of: isFocused) { _, _ in forgetEditMenu() }
        // NOTE: the coach mark deliberately does NOT step aside for focus,
        // typing, or more sends. It survives until
        // the user either DOES the thing — a voice memo actually sent, see
        // finishVoiceMemoMode — or dismisses it outright with the bubble's ✕.
        // A tip that vanishes on the next keystroke is a tip nobody reads.
        // Belt-and-braces after a programmatic clear (send): with iOS's inline
        // predictions the field can hold MARKED text, and UIKit drops a
        // programmatic `text = ""` that lands mid-composition — the old words
        // stay visible while the binding (and so the placeholder) say empty,
        // overlapping. If the cleared binding and the live field still disagree
        // a beat later, unmark and clear the field directly.
        .onChange(of: draft) { _, newValue in
            // Typing (or a programmatic draft) means the menu's moment passed.
            if !newValue.isEmpty { closeAttachMenu() }
            guard newValue.isEmpty, isFocused else { return }
            // QA-only escape: the standing-wedge manufacture needs this
            // repair to stay out of the way, same as the reconcile ladder —
            // the wedge is defined as "every send-scoped repair retired".
            guard !qaWedgeInFlight else { return }
            DispatchQueue.main.async {
                guard draft.isEmpty else { return }
                forceFieldClear()
            }
        }
        // QA-only (env-gated): rig triggers ride TYPED SENTINELS, never
        // tappable buttons. ROOT_PREVIEW mounts a composer per pager page,
        // every instance renders the same env-gated chrome, and
        // `app.buttons[id]` taps the FIRST a11y match — which can be the
        // offscreen page's, silently arming a composer the test isn't
        // driving (found live: the wedge test's button tap landed on the
        // home composer and did nothing). A sentinel suffix runs in the one
        // instance that owns the focused field, by construction.
        .onChange(of: draft) { _, newValue in
            let env = ProcessInfo.processInfo.environment
            if env["COMPOSER_QA_WEDGE"] == "1", newValue.hasSuffix("@@wedge") {
                // Arms the NEXT send to manufacture the standing desync —
                // see `performTextSend`.
                qaWedgeArmed = true
            }
            if env["COMPOSER_QA_DROP_CLEAR"] == "1", newValue.hasSuffix("@@late") {
                // The LATE flavor of the race: text lands in the field well
                // after the send — beyond the retired two-pass reconcile,
                // inside the extended ladder's reach. Armed here, injected
                // from `performTextSend`.
                qaLateTeardownArmed = true
            }
        }
        .onChange(of: isFocused) { _, focused in
            guard focused else { return }
            closeAttachMenu()
            // The backing text view only exists once the field is focused, and
            // it is SwiftUI's to replace — so the image-paste hook is asserted
            // on every focus, once the responder is live and again a beat
            // later (the keyboard's own animation can outrun the first pass).
            DispatchQueue.main.async { installImagePasteHandling() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { installImagePasteHandling() }
            // A wedged bar (empty draft, field frozen at multi-line height)
            // can outlive the post-send reconcile ladder — the document
            // emptying behind SwiftUI's back fires no change SwiftUI can
            // observe, so no event ever repairs it. Refocusing is the next
            // thing a user does to a bar that looks broken, and it is the
            // first moment the responder is reachable again — repair here
            // too, once the responder is live and again a beat later.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { repairWedgedField() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { repairWedgedField() }
        }
        .onDisappear {
            attachMenu.dismiss()
            voiceMemoStartedAt = nil
            voiceMemoStoppedDuration = 0
            if let pendingMemoURL { try? FileManager.default.removeItem(at: pendingMemoURL) }
            pendingMemoURL = nil
            voiceMeter.stop()
            voiceMemoMode = .idle
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { return }
                promptIndex = (promptIndex + 1) % prompts.count
            }
        }
    }

    /// The input capsule — everything the bar was before the attach button
    /// moved out beside it. All chrome x-positions derive from
    /// `capsuleWidth` via their designed distance from the capsule's edges.
    private func capsuleBody(
        surface: RoundedRectangle,
        hasMessage: Bool,
        isVoiceMemoActive: Bool,
        promptText: String,
        textLeading: CGFloat,
        textWidth: CGFloat,
        attachmentRowHeight: CGFloat
    ) -> some View {
        ZStack(alignment: .bottomLeading) {
            surface
                .fill(.white.opacity(0.01))
                .frame(width: capsuleWidth, height: 54 + attachmentRowHeight)

            if !pendingImages.isEmpty || pendingFile != nil {
                // A horizontal scroller, not a fixed row: five 70pt tiles
                // outgrow the capsule, and the overflow should pan instead of
                // squeezing the tiles.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(pendingImages.enumerated()), id: \.offset) { index, imageData in
                            ZStack(alignment: .topTrailing) {
                                ChatImageData(data: imageData)
                                    .scaledToFill()
                                    .frame(width: 70, height: 70)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    // On the tile itself, not the ZStack: a
                                    // container identifier would stamp the ×
                                    // button too. QA's handle on "a photo is
                                    // staged" (image paste, camera, picker).
                                    .accessibilityIdentifier("composer-image-tile")
                                attachmentRemoveButton { onRemoveImage(index) }
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottomLeading)))
                        }
                        if let pendingFile {
                            ZStack(alignment: .topTrailing) {
                                Button(action: onTapFile) {
                                    ComposerFileTile(file: pendingFile)
                                }
                                .buttonStyle(.plain)
                                // On the BUTTON, not the tile: a container
                                // identifier stamps every descendant (and the
                                // button itself would carry none).
                                .accessibilityIdentifier("composer-file-tile")
                                attachmentRemoveButton(onRemoveFile)
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottomLeading)))
                        }
                    }
                    .padding(.horizontal, 14)
                    // Headroom INSIDE the scroller's clip bounds for the ×
                    // controls' 6pt overhang past each tile's top-trailing
                    // corner — a ScrollView clips at its content edge, and
                    // without this the ×s render decapitated.
                    .padding(.top, 8)
                }
                // Pin the initial position to the FIRST tile — without an
                // explicit anchor, a row staged before the bar's first layout
                // (the QA rig, a multi-pick) can settle scrolled to its end.
                .defaultScrollAnchor(.leading)
                .frame(width: capsuleWidth, alignment: .leading)
                // Clip with the capsule's OWN top corners (the scroller's top
                // edge is flush with the surface's): overflowing tiles run all
                // the way to the bar's edge and are cut by the field's curve
                // itself — not by an early hard line inset from it.
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 27, bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0, topTrailingRadius: 27,
                    style: .continuous
                ))
                .offset(y: -62) // sits in the capsule's grown top region
            }

            if isVoiceMemoActive {
                VoiceMemoListeningDisplay(
                    releaseMode: voiceReleaseMode,
                    copy: voiceMemoCopy,
                    isCompact: voiceMemoMode == .manualReady,
                    availableWidth: voiceDisplayWidth,
                    levels: voiceMeter.levels,
                    isListening: voiceMeter.isListening
                )
                .frame(width: voiceDisplayWidth, height: 40, alignment: .leading)
                .offset(x: 18, y: -7)
                .transition(.opacity)
            }

            ZStack(alignment: .bottomLeading) {
                if draft.isEmpty, !isVoiceMemoActive {
                    // The discard hint borrows the placeholder slot (slightly
                    // stronger ink so the change registers) and auto-clears.
                    Text(voiceDiscardHint ?? promptText)
                        .font(.system(size: 18, weight: .regular))
                        .tracking(-0.27)
                        .foregroundStyle(voiceDiscardHint == nil ? DS.Palette.placeholder : DS.Palette.ink.opacity(0.62))
                        .minimumScaleFactor(0.8)
                        .frame(width: textWidth, height: 22, alignment: .leading)
                        .id(voiceDiscardHint ?? promptText)
                        .transition(.opacity)
                }

                // Grows line by line as text wraps (or on Return) up to 8
                // lines; past that the field scrolls internally. The bar's
                // height rides this — see the vertical padding below.
                TextField("", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .regular))
                    .tracking(-0.24)
                    .foregroundStyle(DS.Palette.inkBlack)
                    .tint(DS.Palette.accent)
                    .lineLimit(1 ... 8)
                    // Return inserts a line break (vertical-axis behaviour) —
                    // sending stays on the arrow button.
                    .submitLabel(.return)
                    .frame(minHeight: 22)
                    .focused($isFocused)
                    .allowsHitTesting(!isVoiceMemoActive && isFocused)
                    .opacity(isVoiceMemoActive ? 0 : 1)
            }
            .frame(width: textWidth, alignment: .leading)
            .contentShape(Rectangle())
            .allowsHitTesting(!isVoiceMemoActive)
            // First tap focuses the field. A tap on the ALREADY-focused field
            // summons the system edit menu (Paste et al.): the field's own
            // native tap handling only covers the ~22pt text line, so re-taps
            // on the rest of the bar would otherwise die in the padding.
            .onTapGesture {
                guard !isVoiceMemoActive else { return }
                if isFocused {
                    toggleEditMenuOnFocusedField()
                } else {
                    isFocused = true
                }
            }
            // 16pt above and below the text drives the bar's height: one line
            // (22pt) reproduces the design's 54pt bar exactly; each wrapped
            // line grows the bar upward from its bottom-anchored edge.
            .padding(.vertical, 16)
            // Those same 16pt bands are why a press had to land on the glyphs
            // to place a caret or select anything. Layered here, AFTER the
            // padding, so the shim is the whole text ROW — the 54pt capsule on
            // one line, and exactly as tall as the field on eight — rather
            // than a hardcoded height that would drift as the bar grows.
            // Horizontally it stretches to the capsule's leading edge and out
            // to the trailing control's 60pt slot, the same boundary the hold
            // surface stops at, so Send is never swallowed.
            .overlay {
                if isFocused, hasText, !isVoiceMemoActive {
                    // The text region runs textLeading → capsuleWidth−65; the
                    // shim runs 0 → capsuleWidth−60, so it picks up the leading
                    // gutter and the strip between the words and the mic slot.
                    ComposerTextHitExpander()
                        .padding(.leading, -textLeading)
                        .padding(.trailing, -(capsuleWidth - 60 - (textLeading + textWidth)))
                }
            }
            .offset(x: textLeading)

            if voiceMemoMode == .manualReady {
                Button {
                    discardManualVoiceMemo()
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color(hex: 0xFF3B30), in: Circle())
                }
                .accessibilityIdentifier("composer-voice-discard")
                .buttonStyle(.plain)
                .transaction { $0.animation = nil }
                .offset(x: capsuleWidth - 89, y: -10)
            }

            // A staged photo alone keeps the trailing arrow as Send (image-only
            // send stays one tap), which costs the mic its usual slot — so
            // tap-to-record gets its own mic beside the arrow. A memo recorded
            // here rides along WITH the photo on the same turn (the
            // onVoiceMessage handlers consume the staged image).
            if showsVoice, hasAttachment, !hasText, !isVoiceMemoActive {
                Button {
                    // beginManualVoiceMemoMode resigns focus itself.
                    beginManualVoiceMemoMode()
                } label: {
                    Image(systemName: "microphone")
                        .font(.system(size: 20, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(DS.Palette.inkBlack)
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel("Record voice memo")
                .accessibilityIdentifier("composer-attachment-mic")
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.86)))
                .offset(x: capsuleWidth - 89, y: -10)
            }

            Button {
                if !showsVoice {
                    guard hasMessage else { return }
                    performTextSend()
                } else if hasMessage, !isVoiceMemoActive {
                    performTextSend()
                } else if voiceMemoMode == .manualRecording {
                    stopManualVoiceMemo()
                } else if voiceMemoMode == .manualReady {
                    sendManualVoiceMemo()
                } else if !isVoiceMemoActive, !hasMessage {
                    beginManualVoiceMemoMode()
                }
            } label: {
                ZStack {
                    if !showsVoice {
                        // Text-only: always Send, dimmed until there's something to send.
                        Circle()
                            .fill(IMessageBubblePalette.outgoingComponentFill)
                            .frame(width: 34, height: 34)
                            .opacity(hasMessage ? 1 : 0.35)

                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .opacity(hasMessage ? 1 : 0.5)
                    } else if hasMessage && !isVoiceMemoActive || voiceMemoMode == .manualReady {
                        Circle()
                            .fill(IMessageBubblePalette.outgoingComponentFill)
                            .frame(width: 34, height: 34)
                            .transition(.opacity.combined(with: .scale(scale: 0.86)))

                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .transition(.opacity.combined(with: .scale(scale: 0.86)))
                    } else if voiceMemoMode == .manualRecording {
                        Circle()
                            .fill(IMessageBubblePalette.outgoingComponentFill)
                            .frame(width: 34, height: 34)

                        Image(systemName: "stop.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                    } else {
                        Image(systemName: "microphone")
                            .font(.system(size: 20, weight: .regular))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(microphoneColor)
                            .frame(width: 34, height: 34)
                    }
                }
                .frame(width: 34, height: 34)
            }
            .accessibilityLabel("Send")
            .accessibilityIdentifier("composer-send")
            .buttonStyle(.plain)
            // NO `.transaction { $0.animation = nil }` here (or inside the
            // label): SwiftUI interpolates every node's frame, so nil-ing the
            // transaction anywhere in this chain snaps the button out of the
            // bar-growth animation — a visible dip on each new line while the
            // camera stays put. Voice-mode swaps already suppress animation at
            // the state change (setVoiceMemoModeImmediately), and the
            // mic ⇄ arrow swap keeps its designed opacity/scale transition.
            .offset(x: capsuleWidth - 47, y: -10)

            // QA-only (env-gated): arm the inline-prediction send race on
            // demand — the NEXT send re-marks a composition right after the
            // pre-send commit, so the programmatic clear lands mid-composition
            // and UIKit drops it. Headless sims run a hardware keyboard with
            // no predictive text, so the real trigger is unreachable from a
            // UITest.
            if ProcessInfo.processInfo.environment["COMPOSER_QA_DROP_CLEAR"] == "1" {
                Button("qa-arm-recompose") { qaRearmComposition = true }
                    .accessibilityIdentifier("composer-qa-arm-recompose")
                    .font(.system(size: 10))
                    .frame(width: 90, height: 40)
                    .offset(x: 20, y: -140)
                // Receipt that the LATE-teardown hook actually injected text
                // (see the `@@late` sentinel) — a UITest that only asserts
                // the final field state would pass vacuously if the arming
                // itself had silently failed.
                if qaLateTeardownFired {
                    Text("late-fired")
                        .font(.system(size: 4))
                        .accessibilityIdentifier("composer-qa-late-fired")
                        .offset(x: 20, y: -180)
                }
            }

            // Gate the hold-to-record surface on TEXT only, not hasMessage: with
            // a photo staged but no typed text the user can still press-and-hold
            // to record a voice message that carries the image (the Send arrow
            // stays available at the trailing edge to fire the picture alone).
            //
            // This surface stays up while the field is FOCUSED
            // "even if the chat bar is focused you can hold to.
            // speak" — the whole bar, not just the mic freed).
            //
            // kept the `!isFocused` gate here because the surface sits ON
            // TOP of the text field and swallows its touches, so a re-tap could
            // never reach the native text interaction. What that misses is the
            // `!hasText` gate directly above: this surface only EXISTS over an
            // empty field, which has no caret to place, nothing to select and
            // no loupe to summon. The one affordance that matters there is
            // Paste, and taps route to it explicitly — `handleComposerSurfaceTap`
            // summons the same system edit menu the ancestor gesture used to.
            // The instant a character exists (typed, pasted or dictated) every
            // surface unmounts and the field is natively editable again.
            //
            // Full-width (0 → the mic's slot) rather than the old 52 → −112
            // band: with the surfaces owning every tap on a focused empty
            // capsule, any strip they DON'T cover is a dead zone where the
            // padding-band paste menu used to live.
            if showsVoice, !hasText, !voiceMemoMode.isManual {
                ComposerTouchInteractionSurface(
                    onTap: handleComposerSurfaceTap,
                    onListeningBegan: beginVoiceMemoMode,
                    onReleaseModeChanged: setVoiceReleaseMode,
                    onFinished: finishVoiceMemoMode,
                    onAbortedToTap: abortVoiceMemoToTap,
                    onPressChanged: { isHoldSurfacePressed = $0 },
                    // Half a second to commit while the keyboard is up, against
                    // 0.32s with it down. Focused, a slow press is genuinely
                    // ambiguous — hold to speak, or tap for Paste? — and
                    // guessing wrong SENDS a voice message, so this side gets
                    // Apple's own long-press duration. Unfocused there is no
                    // paste to compete with and push-to-talk stays snappy.
                    tapRescueMaximumDuration: isFocused
                        ? ComposerTouchInteractionView.focusedTapRescueMaximum
                        : ComposerTouchInteractionView.defaultTapRescueMaximum,
                    isHostedInScrollView: isHostedInScrollView
                )
                .frame(width: capsuleWidth - 60, height: 54)
                .offset(x: 0, y: 0)
            }

            // The trailing mic sits OUTSIDE the bar's hold surface, so
            // press-and-hold over the mic itself never reached hold-to-record —
            // the touch fell through to the Button, which only fires on release
            // (into tap-to-record). Give the mic its own hold surface: hold
            // records exactly like the bar, a quick tap keeps hands-free
            // tap-to-record via the rescue path.
            //
            // Not gated on `!isFocused`: hold-to-speak used to
            // disappear the moment the keyboard came up, so "tap the bar, then
            // decide to speak instead" meant dismissing the keyboard first.
            // This surface spans capsuleWidth−60 → capsuleWidth while the text
            // field ends at capsuleWidth−65, so it overlaps the field by
            // nothing at all.
            // Still gated on `!hasMessage`: with text typed the trailing
            // control IS the Send arrow, and holding it must never eat a send.
            if showsVoice, !hasMessage, !voiceMemoMode.isManual {
                ComposerTouchInteractionSurface(
                    onTap: beginManualVoiceMemoMode,
                    onListeningBegan: beginVoiceMemoMode,
                    onReleaseModeChanged: setVoiceReleaseMode,
                    onFinished: finishVoiceMemoMode,
                    onAbortedToTap: abortVoiceMemoToMicTap,
                    onPressChanged: { isHoldSurfacePressed = $0 },
                    isHostedInScrollView: isHostedInScrollView
                )
                .frame(width: 60, height: 54)
                .offset(x: capsuleWidth - 60, y: 0)
            }

            // Same treatment for the attachment-row mic (photo staged, no
            // text). Placed AFTER the bar surface on purpose: the bar surface
            // runs to capsuleWidth−60 and was swallowing most of this
            // 34pt button at capsuleWidth−89 — taps on the visible mic were
            // focusing the field instead.
            //
            // kept `!isFocused` here on the grounds that this surface
            // (capsuleWidth−96 → −52) covers ~31pt of a field that runs to
            // capsuleWidth−65, so while focused it would eat taps meant for
            // paste. That held while the BAR surface stepped aside — it no
            // longer does: the bar surface now covers 0 → capsuleWidth−60 and
            // answers those taps with the edit menu itself. What's left to this
            // one is a 44pt box over the 34pt mic glyph the user can SEE, plus
            // hit-slop. A tap on a drawn mic meaning "record" is right, so it
            // holds like every other mic.
            if showsVoice, hasAttachment, !hasText, !voiceMemoMode.isManual {
                ComposerTouchInteractionSurface(
                    onTap: beginManualVoiceMemoMode,
                    onListeningBegan: beginVoiceMemoMode,
                    onReleaseModeChanged: setVoiceReleaseMode,
                    onFinished: finishVoiceMemoMode,
                    onAbortedToTap: abortVoiceMemoToMicTap,
                    onPressChanged: { isHoldSurfacePressed = $0 },
                    isHostedInScrollView: isHostedInScrollView
                )
                .frame(width: 44, height: 54)
                .offset(x: capsuleWidth - 96, y: 0)
            }
        }
        .frame(width: capsuleWidth)
        // Anchored to the whole bar (pointer at its center), not the mic —
        // hold-to-record works anywhere on the capsule.
        .dsTooltip(
            "Hold to record a voice memo",
            isPresented: voiceTipPresented,
            id: "composer-voice-tip"
        )
        .background(DS.Palette.card.opacity(isReplyActive ? 0.78 : onFlatSurface ? 1 : 0.05), in: surface)
        // interactive: false — the system's press swell cancels itself when
        // voice mode re-renders the capsule 0.1s into a hold, snapping the bar
        // back under a still-down finger. The swell below (isHoldSurfacePressed)
        // replaces it and holds for the whole press.
        .composerGlassSurface(in: surface, interactive: false)
        // The flat-sheet edge: an opaque capsule alone still reads as a smudge
        // against a near-white sheet, so the hairline is what actually draws the
        // bar's boundary — the same pairing every card plate uses.
        .overlay {
            if onFlatSurface {
                surface.stroke(DS.Palette.hairline, lineWidth: 1)
            }
        }
        .shadow(color: DS.Palette.shadow.opacity(onFlatSurface ? 0.08 : 0), radius: 10, y: 3)
        // NO ListeningGlowRim here (tried, rejected): the capsule is
        // near-transparent glass, so the cards' rim halo washes color through
        // the whole bar — and its fade-in at the 0.1s hold mark read as the bar
        // expanding a second time on top of the press swell.
        .shadow(color: DS.Palette.shadow.opacity(isReplyActive ? 0 : 0.10), radius: 4, y: 1)
        .contentShape(surface)
        // Re-taps on the focused bar OUTSIDE the text region (its own tap
        // gesture above wins inside it) — the leading/trailing chrome and the
        // 16pt padding bands, where most "tap the bar again" presses actually
        // land. Same summon; buttons (camera/mic) still take their taps first.
        // The `.subviews` mask is load-bearing WHENEVER a hold surface is
        // mounted (not just while unfocused, as it was before hold-to-speak
        // survived focus): an active ancestor TapGesture recognizes-and-cancels
        // the UIKit touches of those surfaces, killing tap-to-focus AND
        // hold-to-record. With them mounted they cover the whole capsule and
        // summon this same menu themselves, so nothing is lost.
        .gesture(
            TapGesture().onEnded {
                guard isFocused, !isVoiceMemoActive else { return }
                toggleEditMenuOnFocusedField()
            },
            including: isFocused && !isHoldSurfaceMounted ? .all : .subviews
        )
        // Wrapping onto a new line grows the bar — ease it instead of snapping.
        .animation(.smooth(duration: 0.16, extraBounce: 0), value: draft)
        .animation(.easeInOut(duration: 0.18), value: hasMessage)
        .animation(.easeInOut(duration: 0.32), value: promptIndex)
        // ENTERING voice mode snaps (nil) — the waveform UI must appear the
        // instant the hold fires; only the way back out gets the soft fade.
        .animation(isVoiceMemoActive ? nil : .easeInOut(duration: 0.24), value: isVoiceMemoActive)
        // The press swell: up on touch-down, held for the entire press
        // (through the voice-mode flip that used to snap the system's
        // interactive-glass swell back), released with the finger. OUTSIDE the
        // voice-mode animation modifiers on purpose: keyed on its own value,
        // it animates the scale without re-timing the waveform swap above.
        //
        // easeOut, and DONE before the 0.1s hold delay fires: an easeInOut
        // here put its steepest growth exactly on the waveform swap, so one
        // press read as TWO expansions — a small rise, then a second surge as
        // recording started. Front-loaded, the swell is a
        // single immediate pop and the bar is already still when the mic
        // chrome lands.
        .scaleEffect(isHoldSurfacePressed ? 1.015 : 1)
        .animation(.easeOut(duration: 0.09), value: isHoldSurfacePressed)
    }

    // MARK: - Attach menu

    /// The floating attach affordance LEFT of the capsule — iMessage's +
    /// button. Same glass treatment as the bar so the pair reads as one
    /// composer; the plus rotates into an × while the menu is open.
    private var attachButton: some View {
        Button {
            toggleAttachMenu()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(DS.Palette.inkBlack)
                .rotationEffect(.degrees(attachMenu.isOpen ? 45 : 0))
                .animation(.spring(response: 0.3, dampingFraction: 0.72), value: attachMenu.isOpen)
                .frame(width: Self.attachButtonSize, height: Self.attachButtonSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background(DS.Palette.card.opacity(isReplyActive ? 0.78 : onFlatSurface ? 1 : 0.05), in: Circle())
        .composerGlassSurface(in: Circle())
        .overlay {
            if onFlatSurface {
                Circle().stroke(DS.Palette.hairline, lineWidth: 1)
            }
        }
        .shadow(color: DS.Palette.shadow.opacity(isReplyActive ? 0 : 0.10), radius: 4, y: 1)
        .captureWindowFrame(into: $attachButtonRect)
        // Recording owns the bar: the + steps back instead of vanishing (the
        // capsule must not widen mid-memo). A host can hold it in that same
        // stepped-back state for its whole life (see `attachDimmed`).
        .opacity(voiceMemoMode.isActive || attachDimmed ? 0.35 : 1)
        .allowsHitTesting(!voiceMemoMode.isActive && !attachDimmed)
        .accessibilityLabel("Attach")
        .accessibilityIdentifier("composer-attach")
    }

    /// The pinned media strip — Camera / Photos / Files, always one tap and
    /// never scrolled away, whatever the action shelf holds. Only the kinds the
    /// host actually handles appear (see onCamera).
    private var attachMediaItems: [ComposerAttachMenuItem] {
        var items: [ComposerAttachMenuItem] = []
        if let onCamera {
            items.append(ComposerAttachMenuItem(id: "camera", icon: "camera.fill", label: String(localized: "Camera")) {
                fireAttachAction(onCamera)
            })
        }
        if let onPhotoLibrary {
            items.append(ComposerAttachMenuItem(id: "photos", icon: "photo.on.rectangle.angled", label: String(localized: "Photos")) {
                fireAttachAction(onPhotoLibrary)
            })
        }
        if let onAttachFile {
            items.append(ComposerAttachMenuItem(id: "files", icon: "folder.fill", label: String(localized: "Files")) {
                fireAttachAction(onAttachFile)
            })
        }
        return items
    }

    /// Whether the + is worth showing at all: something to attach, or something
    /// to create. A host that wired neither gets the full-width capsule — the
    /// same layout `showsCamera: false` produces, arrived at from the handlers
    /// instead of a second flag that can disagree with them.
    private var hasAttachMenu: Bool {
        showsCamera && !(attachMediaItems.isEmpty && quickActions.isEmpty)
    }

    /// The host's quick actions, each wrapped so the tap collapses the bloom
    /// before the handler runs (sheet presentation fights the close spring).
    private var attachActionItems: [ComposerAttachMenuItem] {
        quickActions.map { item in
            ComposerAttachMenuItem(id: item.id, icon: item.icon, label: item.label) {
                fireAttachAction(item.action)
            }
        }
    }

    private func toggleAttachMenu() {
        DSHaptics.tap(.light)
        attachMenu.toggle(actions: attachActionItems, media: attachMediaItems, anchor: attachButtonRect)
    }

    private func closeAttachMenu() {
        attachMenu.dismiss()
    }

    /// Row tap: collapse the bloom first, then fire — presenting a sheet in
    /// the same beat fights the close spring and reads as a stutter.
    private func fireAttachAction(_ action: @escaping () -> Void) {
        DSHaptics.tap(.light)
        closeAttachMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { action() }
    }

    private var microphoneColor: Color {
        guard voiceMemoMode.isActive else { return DS.Palette.inkBlack }
        return voiceReleaseMode == .delete ? Color(hex: 0xFF3B30) : DS.Palette.accent
    }

    private var voiceMemoCopy: String? {
        switch voiceMemoMode {
        case .idle, .hold:
            nil
        case .manualRecording:
            formattedVoiceDuration(currentVoiceDuration)
        case .manualReady:
            formattedVoiceDuration(voiceMemoStoppedDuration)
        }
    }

    private var voiceDisplayWidth: CGFloat {
        // Edge-relative off the CAPSULE: ends 15pt clear of the trash slot in
        // manualReady, 11pt clear of the send slot otherwise.
        capsuleWidth - (voiceMemoMode == .manualReady ? 122 : 76)
    }

    /// The shared x control on a staged attachment tile (photo or document).
    private func attachmentRemoveButton(_ onRemove: @escaping () -> Void) -> some View {
        Button {
            DSHaptics.tap(.light)
            withAnimation(.snappy(duration: 0.2)) { onRemove() }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.55))
        }
        .buttonStyle(.plain)
        .offset(x: 6, y: -6)
    }

    // MARK: - Hold to record

    private func beginVoiceMemoMode() {
        guard voiceMemoMode == .idle, !hasText else { return }
        onListeningBegan?()
        if voiceHandledExternally { return }
        closeAttachMenu()
        // A hold can start with the keyboard — and so the Paste pill — still
        // up: recording is the answer to "what do I do with this bar", so the
        // menu the previous tap left open stands down.
        dismissEditMenu()
        voiceMemoStartedAt = Date()
        voiceMemoStoppedDuration = 0
        composerHaptics.listeningStart()
        // Deliberately does NOT resign focus, and must not start: a hold can
        // now begin with the keyboard UP (both the bar and the mic surfaces
        // stay alive while focused). Dropping the keyboard here would slide the
        // whole bar ~300pt down WITH THE FINGER STILL ON THE SURFACE, and
        // slide-up-to-cancel measures the touch in the SURFACE's coordinate
        // space — a stationary finger over a bar that moved down reads as a
        // ~300pt slide up, so `touchesEnded` would re-evaluate to .delete and
        // silently bin every memo recorded from a focused composer. A view
        // yanked out from under a live touch can get touchesCancelled outright,
        // which this surface ALSO maps to delete.
        // Keeping focus keeps the bar still under the finger, and leaves the
        // user back in their text field when the memo is sent.
        setVoiceMemoModeImmediately(.hold)
        voiceReleaseMode = .send

        // The waveform UI is already on screen (animated placeholder meter);
        // the mic session spins up behind it and takes over when ready.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.045) {
            guard voiceMemoMode == .hold else { return }
            voiceMeter.start()
        }
    }

    /// A press that entered voice mode but released fast enough to be a tap:
    /// tear the memo down silently (no delete haptic) and open the keyboard —
    /// what the user was actually asking for.
    private func abortVoiceMemoToTap() {
        guard voiceMemoMode == .hold else { return }
        voiceMemoStartedAt = nil
        voiceMemoStoppedDuration = 0
        voiceReleaseMode = .send
        voiceMeter.discard()
        setVoiceMemoModeImmediately(.idle)
        handleComposerSurfaceTap()
    }

    /// Mic-surface counterpart of `abortVoiceMemoToTap`: a press on the mic
    /// that entered hold mode but released tap-fast meant "tap the mic" —
    /// start hands-free recording, not the keyboard.
    private func abortVoiceMemoToMicTap() {
        guard voiceMemoMode == .hold else { return }
        voiceMemoStartedAt = nil
        voiceMemoStoppedDuration = 0
        voiceReleaseMode = .send
        voiceMeter.discard()
        setVoiceMemoModeImmediately(.idle)
        beginManualVoiceMemoMode()
    }

    // MARK: - Paste shortcut

    /// The one entry point for a re-tap on the focused bar: it TOGGLES the
    /// system edit menu. A tap that finds the pill already up puts it away
    /// — re-presenting on top of a live menu is invisible,
    /// so the pill read as stuck and there was no way to dismiss it from the
    /// bar at all.
    private func toggleEditMenuOnFocusedField() {
        // The pill is usually already gone by the time this runs — UIKit
        // dismisses it on the touch DOWN, and the hold surface starts a memo
        // (which dismisses it too) a tenth of a second into every press, while
        // this fires on the release. So "not visible right now" would present
        // all over again and bounce it straight back up. `editMenuClosedAt`
        // says a close just happened; a tap this close behind one IS that
        // close's tap.
        guard !editMenuVisible, !closedWithinThisGesture else {
            dismissEditMenu()
            return
        }
        presentEditMenuOnFocusedField()
    }

    /// Teach the focused field that a pasted image is a photo, not a filename.
    /// No-op for hosts that can't stage one — see `onPasteImage`.
    private func installImagePasteHandling() {
        guard let onPasteImage else { return }
        ComposerImagePaste.install(onImage: onPasteImage)
    }

    /// How long after a close a tap still reads as THAT close's tap. Sized to
    /// the whole tap-rescue window: on the focused bar a press up to
    /// `focusedTapRescueMaximum` is re-classified as a tap on RELEASE, so the
    /// gesture that closed the pill can arrive here half a second later.
    private static let editMenuCloseSwallow: TimeInterval =
        ComposerTouchInteractionView.focusedTapRescueMaximum + 0.1

    private var closedWithinThisGesture: Bool {
        guard let editMenuClosedAt else { return false }
        return Date().timeIntervalSince(editMenuClosedAt) < Self.editMenuCloseSwallow
    }

    /// Re-tapping the focused bar summons the SYSTEM edit menu (Paste, and
    /// Select All etc. when applicable) at the caret — the same black pill the
    /// field shows natively, so a paste via it never triggers the "Allow
    /// Paste?" alert. Needed because the field's own tap handling only covers
    /// the text line, not the rest of the 54pt capsule.
    private func presentEditMenuOnFocusedField() {
        guard let responder = PersonaFirstResponder.current(),
              let field = responder as? UIView & UITextInput
        else { return }
        // This pill is where Paste gets tapped, so it is the last honest moment
        // to make sure the field will take a pasted image as a picture.
        installImagePasteHandling()
        // The text view carries its OWN internal UIEditMenuInteraction (its
        // delegate declines foreign configurations, presenting nothing), so
        // reuse only the interaction WE added — matched by delegate identity.
        let interaction = field.interactions
            .compactMap { $0 as? UIEditMenuInteraction }
            .first { $0.delegate === PersonaEditMenuDelegate.shared } ?? {
                let created = UIEditMenuInteraction(delegate: PersonaEditMenuDelegate.shared)
                field.addInteraction(created)
                return created
            }()
        // Anchor at the caret so the pill sits where the native one would.
        let caret = field.selectedTextRange.map { field.caretRect(for: $0.start) } ?? .zero
        ComposerEditMenu.remember(interaction)
        interaction.presentEditMenu(
            with: UIEditMenuConfiguration(
                identifier: nil,
                sourcePoint: CGPoint(x: caret.midX, y: caret.minY)
            )
        )
    }

    /// Put the pill away. Safe to call blind — it no-ops when nothing is up —
    /// and it works off a weak handle on the interaction rather than the first
    /// responder, because the one caller that most needs it (a hands-free voice
    /// memo) hands the keyboard down in the same breath.
    private func dismissEditMenu() {
        ComposerEditMenu.dismiss()
        noteEditMenu(visible: false)
        restoreTipAfterEditMenu()
    }

    /// The pill going in or out, from UIKit or from us — one rule for both.
    ///
    /// The stamp is conditional on it having BEEN up, and that condition is
    /// load-bearing: `beginVoiceMemoMode` dismisses blind 0.1s into every
    /// press, and a press under the rescue window comes back as a tap. Stamping
    /// a close that never happened would make every tap slower than a tenth of
    /// a second read as "this tap closed the menu" — and the Paste pill would
    /// stop opening at all.
    private func noteEditMenu(visible: Bool) {
        if !visible, editMenuVisible { editMenuClosedAt = Date() }
        editMenuVisible = visible
    }

    /// The pill is certainly gone but UIKit never said so (typing dismisses it
    /// silently). Deliberately does NOT stamp `editMenuClosedAt`: no tap of the
    /// user's closed it, so no following tap should be swallowed as the close.
    private func forgetEditMenu() {
        editMenuVisible = false
        restoreTipAfterEditMenu()
    }

    /// A tap (or a press rescued back into one) on the bar's hold surface.
    /// Unfocused that means "open the keyboard"; ALREADY focused it means the
    /// same thing the ancestor gesture does when no surface is mounted —
    /// summon the system edit menu, which is how Paste reaches an empty
    /// focused field now that the surface sits over it.
    ///
    /// Falls back to `handleComposerTap` when focus reads true but no text
    /// responder is actually live: presenting a menu on nothing would be a
    /// dead tap, whereas the tap path re-asserts focus (stale-@FocusState
    /// wedge).
    private func handleComposerSurfaceTap() {
        guard !hasText else { return }
        guard isFocused, hasLiveTextResponder else {
            handleComposerTap()
            return
        }
        composerHaptics.tap()
        toggleEditMenuOnFocusedField()
    }

    private var hasLiveTextResponder: Bool {
        PersonaFirstResponder.current() is UIView & UITextInput
    }

    private func handleComposerTap() {
        guard !hasText else { return }
        composerHaptics.tap()
        if isFocused {
            // Re-assert against a stale-true FocusState: when the field
            // actually lost focus while the state still reads true, a plain
            // `= true` is a silent no-op — the "tap the composer and nothing
            // happens" wedge (field). Blip false now, true next
            // runloop turn — a genuinely-focused field refocuses fast enough
            // that the keyboard never visibly dips.
            isFocused = false
            Task { @MainActor in isFocused = true }
        } else {
            isFocused = true
        }
    }

    private func setVoiceReleaseMode(_ next: VoiceReleaseMode) {
        guard next != voiceReleaseMode else { return }
        composerHaptics.modeChange()
        voiceReleaseMode = next
    }

    private func finishVoiceMemoMode() {
        guard voiceMemoMode == .hold else { return }
        let finishedMode = voiceReleaseMode
        let duration = voiceMemoStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        voiceMemoStartedAt = nil
        voiceMemoStoppedDuration = 0
        voiceMemoMode = .idle
        voiceReleaseMode = .send

        // Anything past the tap-rescue window (0.32s unfocused, 0.5s on the
        // focused bar) is a real attempt: hand it to transcribeAndSend, whose
        // MEASURED-length gate is the one that matters. The old 0.6s wall-clock
        // gate here double-counted the mic spin-up and dropped genuine short
        // holds without a word. The 0.35s floor below is therefore only live
        // for the unfocused window; the focused one already clears it.
        if finishedMode == .send, duration >= 0.35 {
            // A nil URL (recorder still spinning up on release) is discarded by
            // transcribeAndSend: a send requires a REAL recording behind it.
            let url = voiceMeter.finishRecording()
            transcribeAndSend(url, duration: duration)
        } else {
            composerHaptics.deleteRelease()
            voiceMeter.discard()
            // A send-intent release that still lands here was a dropped
            // recording, not a cancel: say so instead of vanishing.
            if finishedMode == .send { showVoiceDiscardHint() }
        }
    }

    // MARK: - Tap to record

    /// Act on a pending quick-voice request (see `voiceCaptureRequested`).
    private func consumeVoiceCaptureRequest() {
        guard voiceCaptureRequested.wrappedValue else { return }
        voiceCaptureRequested.wrappedValue = false
        beginManualVoiceMemoMode()
    }

    /// Act on a pending stop-and-send request (the band button's second
    /// press). Recording live → stop it, then send; already parked in the
    /// ready pill → just send. Anything else is a no-op: the guards inside
    /// both calls make a stale request incapable of sending. The too-short /
    /// silent clip gates in `stopManualVoiceMemo` still apply — a bounced
    /// recording lands in `.idle` and the send call quietly does nothing.
    private func consumeVoiceSendRequest() {
        guard voiceSendRequested.wrappedValue else { return }
        voiceSendRequested.wrappedValue = false
        if voiceMemoMode == .manualRecording { stopManualVoiceMemo() }
        sendManualVoiceMemo()
    }

    private func beginManualVoiceMemoMode() {
        guard voiceMemoMode == .idle, !hasText else { return }
        closeAttachMenu()
        // BEFORE the keyboard goes down two lines below: the pill is anchored
        // to the field's caret, and a menu left up while its field resigns can
        // hang over a bar that has already moved on.
        dismissEditMenu()
        // Hand the keyboard down here rather than at each call site. The
        // attachment mic already did this on its own; the trailing mic did not,
        // so tapping it with the field focused started recording with the
        // keyboard still up. Now that the mic's hold surface stays alive while
        // focused, every tap-to-record path arrives here focused-or-not, and
        // one design beats three call sites remembering.
        //
        // The exact OPPOSITE of `beginVoiceMemoMode`, on purpose: this path is
        // hands-free (nobody is about to type, and no finger is resting on a
        // touch surface), while a HOLD must keep the keyboard so the bar can't
        // move out from under the press. Don't reconcile the two.
        isFocused = false
        voiceMemoStartedAt = Date()
        voiceMemoStoppedDuration = 0
        voiceReleaseMode = .send
        setVoiceMemoModeImmediately(.manualRecording)
        voiceMeter.start()
        composerHaptics.listeningStart()
    }

    private func stopManualVoiceMemo() {
        guard voiceMemoMode == .manualRecording else { return }
        let duration = currentVoiceDuration
        guard duration >= 0.35 else {
            voiceMemoStartedAt = nil
            voiceMemoStoppedDuration = 0
            voiceReleaseMode = .send
            voiceMeter.discard()
            setVoiceMemoModeImmediately(.idle)
            composerHaptics.deleteRelease()
            showVoiceDiscardHint()
            return
        }

        voiceMemoStoppedDuration = duration
        pendingMemoURL = voiceMeter.pauseKeepingLevels()
        setVoiceMemoModeImmediately(.manualReady)
        composerHaptics.tap()
    }

    private func sendManualVoiceMemo() {
        guard voiceMemoMode == .manualReady else { return }
        let url = pendingMemoURL
        let duration = voiceMemoStoppedDuration
        pendingMemoURL = nil
        voiceMemoStartedAt = nil
        voiceMemoStoppedDuration = 0
        voiceReleaseMode = .send
        setVoiceMemoModeImmediately(.idle)
        composerHaptics.tap()
        transcribeAndSend(url, duration: duration)
    }

    private func discardManualVoiceMemo() {
        guard voiceMemoMode == .manualReady else { return }
        if let url = pendingMemoURL { try? FileManager.default.removeItem(at: url) }
        pendingMemoURL = nil
        voiceMemoStartedAt = nil
        voiceMemoStoppedDuration = 0
        voiceReleaseMode = .send
        voiceMeter.discard()
        setVoiceMemoModeImmediately(.idle)
        composerHaptics.deleteRelease()
    }

    private func transcribeAndSend(_ url: URL?, duration: TimeInterval) {
        guard let url else {
            voiceMeter.discard()
            showVoiceDiscardHint()
            return
        }
        // The single choke point for EMPTY clips. The wall-clock `duration` is
        // stamped before the recorder is even live, so it can pass while the
        // mic captured almost nothing — gate on what was actually recorded:
        // the measured clip length AND a non-silent peak. 0.3s of real audio
        // is plenty for the server-side transcriber; the old 0.6s bar ate
        // one-word replies whose clip came up short of the wall clock (mic
        // spin-up, first-run permission hop). Rejection now SAYS so via the
        // placeholder hint instead of only the delete haptic.
        let recordedDuration = voiceMeter.lastFinishedDuration
        let peak = voiceMeter.lastFinishedPeak
        guard recordedDuration >= 0.3, peak >= VoiceMemoRecorder.silencePeakThreshold else {
            try? FileManager.default.removeItem(at: url)
            voiceMeter.discard()
            composerHaptics.deleteRelease()
            showVoiceDiscardHint()
            return
        }
        // Hand the clip off as audio — the caller transcribes server-side or
        // sends a real voice message. Keep the file: the caller owns its
        // lifecycle now (upload + playback).
        VoiceMemoTipGate.recordVoiceMemoSend()
        // The coach mark's ONE non-explicit exit: they just did the thing it
        // was teaching. A recording that gets discarded (too short, silent)
        // never reaches here, so the tip correctly outlives a failed attempt.
        voiceTipPresented.wrappedValue = false
        onVoiceMessage(url, recordedDuration)
    }

    /// Put back a coach mark parked for the system edit menu. No-op unless
    /// THIS composer parked it, so it can never resurrect a tip the user
    /// dismissed or spend a showing that was never offered.
    private func restoreTipAfterEditMenu() {
        guard editMenuSuppressedTip else { return }
        editMenuSuppressedTip = false
        voiceTipPresented.wrappedValue = true
    }

    /// Surface the drop in the placeholder slot for a beat. Kept short and
    /// plain; clears itself so the rotating prompts come back.
    private func showVoiceDiscardHint() {
        withAnimation(.easeInOut(duration: 0.18)) {
            voiceDiscardHint = String(localized: "Didn't catch that. Hold, speak, then release.")
        }
        voiceDiscardHintClearTask?.cancel()
        voiceDiscardHintClearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) { voiceDiscardHint = nil }
        }
    }

    private var currentVoiceDuration: TimeInterval {
        guard let voiceMemoStartedAt else { return 0 }
        return max(0, Date().timeIntervalSince(voiceMemoStartedAt))
    }

    private func formattedVoiceDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }

    private func setVoiceMemoModeImmediately(_ mode: VoiceMemoMode) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) { voiceMemoMode = mode }
    }

    /// Finalize any in-progress IME composition / pending autocorrection on the
    /// focused text view BEFORE the bound `draft` is cleared by the send path. A
    /// SwiftUI `TextField` won't empty while its underlying text view still holds
    /// marked text (multi-stage input) or an uncommitted autocorrection — the
    /// composition re-commits its text a beat after `draft = ""`, so the just-sent
    /// message stays visible in the field. Unmarking commits it first, so the
    /// subsequent clear actually sticks. No-op when nothing is being composed.
    private func commitPendingTextInput() {
        guard let responder = PersonaFirstResponder.current(),
              let textInput = responder as? UITextInput,
              textInput.markedTextRange != nil
        else { return }
        (responder as? UITextView)?.unmarkText()
        (responder as? UITextField)?.unmarkText()
    }

    /// The one text-send path: commit any live composition, hand off to the
    /// caller (which clears `draft`), keep the keyboard, then verify a beat
    /// later that the clear actually stuck — see `reconcileAfterSend`.
    private func performTextSend() {
        closeAttachMenu()
        let sent = draft
        let keepKeyboard = isFocused
        commitPendingTextInput()
        qaRearmCompositionIfRequested()
        VoiceMemoTipGate.recordTextSend()
        onSend()
        isFocused = keepKeyboard
        if qaWedgeArmed {
            // QA-only: manufacture the STANDING desync — "every send-scoped
            // repair already retired, then a teardown re-committed into the
            // document behind SwiftUI's back". No ladder is scheduled, and
            // at +0.5s stale text lands via direct `.text =` (no pipeline
            // edit, binding untouched and empty). On the old code this text
            // is stuck until an app restart; only the focus-time repair can
            // save it. (The tall-EMPTY flavor of the same desync cannot be
            // manufactured deterministically — three attempts on the rig
            // all re-measured healthily; its height lie only forms under
            // real IME teardown timing. Its repair shares this trigger and
            // these guards, and is live-verified — see 8153c15d3.)
            qaWedgeArmed = false
            qaWedgeInFlight = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                qaWedgeInFlight = false
                guard let responder = PersonaFirstResponder.current() else { return }
                (responder as? UITextView)?.text = "wedged leftovers"
                (responder as? UITextField)?.text = "wedged leftovers"
            }
            return
        }
        // A ladder, not a pair: the near passes catch the common drop fast;
        // the far ones catch what lands late — a prediction/dictation
        // teardown can touch the field SECONDS after the send (design hit
        // the wedge on TF 253, a build with the +0.35s pass — it formed
        // after the last pass and nothing was left to repair it). Every pass
        // is idempotent and, against a healthy field, costs a few property
        // reads; past ~6s a teardown tied to THIS send no longer arrives,
        // and the focus-time repair covers anything slower.
        for delay in [0.05, 0.35, 1.0, 2.5, 6.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                reconcileAfterSend(expecting: sent)
            }
        }
        qaScheduleLateTeardownIfRequested(sent: sent)
    }

    /// With iOS's inline predictions a fresh composition can re-mark the field
    /// between `commitPendingTextInput` and the binding write landing — UIKit
    /// then drops the programmatic clear, and a beat later the composition
    /// re-commits the old words (sometimes resurrecting the binding too). A
    /// send means BOTH sides end empty, so scrub whatever survived — through
    /// the editing pipeline (`replace`), never by assigning `.text` directly:
    /// a direct assignment empties the view behind SwiftUI's back, and the
    /// field keeps its multi-line height around an empty document (caret on
    /// the top line, placeholder a line below). If the user already typed a
    /// NEW draft in the gap, it won't equal the sent text and stays untouched.
    private func reconcileAfterSend(expecting sent: String) {
        if !sent.isEmpty, draft == sent { draft = "" }
        guard draft.isEmpty,
              let responder = PersonaFirstResponder.current(),
              let field = responder as? UIView & UITextInput
        else { return }
        field.unmarkText()
        if let all = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument),
           !all.isEmpty {
            field.replace(all, withText: "")
            return
        }
        collapseStaleEmptyField(field)
    }

    /// The reconcile ladder is send-scoped, so a wedge that forms after its
    /// last pass has no send left to repair it and persists until the next
    /// pipeline edit — indefinitely, for a user staring at a broken bar
    ///. This is the same repair keyed off the STATE
    /// instead: an empty binding over a field holding text SwiftUI can't
    /// see, or laid out taller than empty needs. Unlike the post-send
    /// reconcile it can run against a field the user is actively composing
    /// into, and CJK multi-stage input holds MARKED text the binding may
    /// not reflect — a live composition is left strictly alone, never
    /// unmarked, never nudged.
    private func repairWedgedField() {
        guard draft.isEmpty,
              let responder = PersonaFirstResponder.current(),
              let field = responder as? UIView & UITextInput,
              field.markedTextRange == nil
        else { return }
        if let all = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument),
           !all.isEmpty {
            // Committed text the binding can't see is unsendable (the send
            // button keys off `draft`) — scrub it through the pipeline, the
            // same doctrine as the post-send reconcile.
            field.replace(all, withText: "")
            return
        }
        collapseStaleEmptyField(field)
    }

    /// The other way the race resolves: the field ends up EMPTY yet still
    /// TALL — something emptied the document through a path SwiftUI never
    /// observed (a dictation session or inline-prediction composition tearing
    /// down after the send), so the vertical-axis field keeps its multi-line
    /// measurement around nothing: caret on the top line, placeholder a line
    /// below, a bar three lines high with no text in it. An empty document
    /// gives `replace` nothing to push through the editing pipeline, so nudge
    /// it instead — insert one character and delete it, two pipeline edits
    /// SwiftUI DOES observe, and the field re-measures down to one line.
    /// Gated on a real mismatch between the laid-out height and what the
    /// empty view says it needs, so a healthy send never feels it. Lives on
    /// the reconcile passes and the focus-time `repairWedgedField` (one-shot
    /// each), never in `forceFieldClear` —
    /// the nudge itself echoes through the `draft` onChange that schedules
    /// forceFieldClear, and a nudge THERE could self-retrigger forever if the
    /// height ever failed to settle.
    private func collapseStaleEmptyField(_ field: UIView & UITextInput) {
        guard let key = field as? UIView & UIKeyInput else { return }
        let needed = field.sizeThatFits(
            CGSize(width: field.bounds.width, height: .greatestFiniteMagnitude)
        ).height
        guard field.bounds.height > needed + 8 else { return }
        key.insertText(" ")
        key.deleteBackward()
    }

    /// QA-only: simulate the LATE teardown — a prediction/dictation session
    /// pushing text back into the field well after the send, when the old
    /// two-pass reconcile had already retired. Scheduled from
    /// `performTextSend` so it races the real ladder exactly as prod does.
    private func qaScheduleLateTeardownIfRequested(sent: String) {
        guard qaLateTeardownArmed else { return }
        qaLateTeardownArmed = false
        // 1.2s: after the old code's last pass (0.35s) and between the
        // ladder's 1.0s and 2.5s — the 2.5s pass must scrub it. The
        // injection is the SENT text, as a prod re-commit's would be: the
        // insertion resurrects the binding too, and the reconcile only
        // scrubs a binding it can prove is the sent message (a variant
        // string is indistinguishable from fresh typing and stays).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard let responder = PersonaFirstResponder.current(),
                  let field = responder as? UIView & UITextInput
            else { return }
            field.setMarkedText(sent, selectedRange: NSRange(location: (sent as NSString).length, length: 0))
            qaLateTeardownFired = true
        }
    }

    /// QA-only (see the env-gated button in `body`): simulate the prediction
    /// keyboard winning the race — a composition re-marks the field right
    /// after the pre-send commit, so the programmatic clear lands mid-
    /// composition and gets dropped.
    private func qaRearmCompositionIfRequested() {
        guard qaRearmComposition else { return }
        qaRearmComposition = false
        guard let responder = PersonaFirstResponder.current(),
              let field = responder as? UIView & UITextInput
        else { return }
        field.setMarkedText("ing", selectedRange: NSRange(location: 3, length: 0))
    }

    /// Force the focused field's text back in line with an emptied `draft` —
    /// only called when the two are known to disagree (see the `draft` onChange).
    /// Clears through the editing pipeline so the SwiftUI field re-measures;
    /// see `reconcileAfterSend` for why a direct `.text = ""` is wrong here.
    private func forceFieldClear() {
        guard let responder = PersonaFirstResponder.current(),
              let field = responder as? UIView & UITextInput
        else { return }
        field.unmarkText()
        guard let all = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument),
              !all.isEmpty
        else { return }
        field.replace(all, withText: "")
    }
}

/// One row of the composer's attach bloom menu.
struct ComposerAttachMenuItem: Identifiable {
    let id: String
    let icon: String
    let label: String
    let action: () -> Void
}

/// The bloom menu over the composer's floating + button — the app's create
/// surface. Two shelves in one liquid-glass card (the composer chrome's glass
/// — it floats OVER the transcript, so it has real content to refract;
/// Apple's layering rule and ours):
/// · an upper shelf of quick-action ROWS (Set reminder / New email /
/// Automations), and
/// · a media STRIP (Camera / Photos / Files as circular glyphs) nearest
/// the + button.
/// Ink glyphs keep it monochrome where iMessage goes full color; the motion
/// (scale-from-corner + blur, strip-then-rows cascade) is the iMessage
/// drawer's. Hosts with no quick actions get the strip alone.
struct ComposerAttachMenu: View {
    static let width: CGFloat = 236
    static let rowHeight: CGFloat = 50
    static let cardPadding: CGFloat = 8
    /// The media strip's block: 44pt glyph circles + 11pt labels, breathing room.
    static let mediaStripHeight: CGFloat = 76
    /// Divider row between the shelves: 1pt hairline + 5pt each side.
    static let dividerHeight: CGFloat = 11

    static func size(forActionCount count: Int) -> CGSize {
        let divider: CGFloat = count > 0 ? dividerHeight : 0
        return CGSize(
            width: width,
            height: cardPadding * 2 + CGFloat(count) * rowHeight + divider + mediaStripHeight
        )
    }

    let actions: [ComposerAttachMenuItem]
    let media: [ComposerAttachMenuItem]
    /// Cascade: items start hidden and spring in with a per-item delay once
    /// the container blooms — the strip first (it's nearest the + the bloom
    /// grows from), then the rows climbing away. The container's own collapse
    /// covers the way out, so the stagger runs on entry only.
    @State private var revealed = false

    var body: some View {
        VStack(spacing: 0) {
            if !actions.isEmpty {
                actionShelf
                Rectangle()
                    .fill(DS.Palette.ink.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
            }
            mediaStrip
        }
        .padding(Self.cardPadding)
        .frame(width: Self.width)
        // The header capsule's glass recipe (white underlay + liquid glass):
        // the menu is floating chrome over the transcript, same family as the
        // bar and the + button beside it.
        .background(Color(light: 0xFFFFFF, dark: 0x1C1C1E, lightOpacity: 0.35, darkOpacity: 0.35), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .personaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: true)
        // Flatten before shadowing: without this every row (glyph circle,
        // label) casts its own smudge inside the card.
        .compositingGroup()
        .shadow(color: .black.opacity(0.12), radius: 30, y: 8)
        .onAppear { revealed = true }
    }

    private var actionShelf: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, item in
                Button(action: item.action) {
                    HStack(spacing: 12) {
                        Image(systemName: item.icon)
                            .font(.system(size: 15, weight: .medium))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(DS.Palette.ink)
                            .frame(width: 32, height: 32)
                            .background(DS.Palette.ink.opacity(0.05), in: Circle())
                        Text(item.label)
                            .font(.system(size: 16, weight: .medium))
                            .tracking(-0.2)
                            .foregroundStyle(DS.Palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: Self.rowHeight)
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(AttachMenuRowStyle())
                .accessibilityIdentifier("composer-attach-\(item.id)")
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 8)
                .animation(
                    .spring(response: 0.32, dampingFraction: 0.8).delay(0.1 + 0.04 * Double(index)),
                    value: revealed
                )
            }
        }
    }

    private var mediaStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(media.enumerated()), id: \.element.id) { index, item in
                Button(action: item.action) {
                    VStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.system(size: 17, weight: .medium))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(DS.Palette.ink)
                            .frame(width: 44, height: 44)
                            .background(DS.Palette.ink.opacity(0.05), in: Circle())
                        Text(item.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.Palette.ink.opacity(0.65))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(AttachMenuGlyphStyle())
                .accessibilityIdentifier("composer-attach-\(item.id)")
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 8)
                .animation(
                    .spring(response: 0.32, dampingFraction: 0.8).delay(0.04 + 0.03 * Double(index)),
                    value: revealed
                )
            }
        }
        .frame(height: Self.mediaStripHeight)
    }
}

/// Shelf-row press state: a soft ink wash under the row, the system-menu read.
private struct AttachMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(DS.Palette.ink.opacity(configuration.isPressed ? 0.06 : 0))
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Media-glyph press state: the circle dips instead of washing — a strip of
/// round buttons reads as buttons, not a row.
private struct AttachMenuGlyphStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}


/// Bloom animation state shared between the presenter (which drives the
/// collapse) and the overlay's hosted SwiftUI content (which animates it).
@MainActor
final class ComposerAttachMenuOverlayModel: ObservableObject {
    @Published var shown = false
}

/// The overlay's hosted content: the menu with its grow-from-the-corner bloom
/// — scale anchored at the + button's corner with a defocusing blur, the
/// iMessage drawer's motion.
struct ComposerAttachMenuOverlayContent: View {
    @ObservedObject var model: ComposerAttachMenuOverlayModel
    let actions: [ComposerAttachMenuItem]
    let media: [ComposerAttachMenuItem]

    var body: some View {
        ComposerAttachMenu(actions: actions, media: media)
            .scaleEffect(model.shown ? 1 : 0.3, anchor: .bottomLeading)
            .blur(radius: model.shown ? 0 : 6)
            .opacity(model.shown ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .onAppear {
                // A touch of overshoot on the way in — the bloom reads alive;
                // the collapse (presenter.dismiss) is tighter so dismissal
                // feels immediate.
                withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { model.shown = true }
            }
    }
}

/// Full-window passthrough container for the bloom menu. Only the menu's own
/// frame takes touches; anything else falls through to the app AND schedules
/// a dismissal — iMessage's "tap anywhere to put it away", without swallowing
/// the tap. The + button's rect passes through WITHOUT dismissing so the
/// button's own toggle never races the overlay.
@MainActor
final class ComposerAttachMenuOverlayView: UIView {
    private let host: UIHostingController<ComposerAttachMenuOverlayContent>
    private let excludedRect: CGRect
    private let onOutsideTap: () -> Void
    private var dismissScheduled = false

    init(
        model: ComposerAttachMenuOverlayModel,
        actions: [ComposerAttachMenuItem],
        media: [ComposerAttachMenuItem],
        anchor: CGRect,
        onOutsideTap: @escaping () -> Void
    ) {
        host = UIHostingController(
            rootView: ComposerAttachMenuOverlayContent(model: model, actions: actions, media: media)
        )
        excludedRect = anchor
        self.onOutsideTap = onOutsideTap
        super.init(frame: .zero)
        backgroundColor = .clear
        host.view.backgroundColor = .clear
        host.view.clipsToBounds = false
        addSubview(host.view)
        // The hosting view IS the menu's frame, its bottom-leading corner
        // 10pt above the + button — the bloom scales inside it (shadow/blur
        // spill draws fine, nothing clips).
        let size = ComposerAttachMenu.size(forActionCount: actions.count)
        host.view.frame = CGRect(
            x: anchor.minX,
            y: anchor.minY - 10 - size.height,
            width: size.width,
            height: size.height
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if host.view.frame.contains(point) { return super.hitTest(point, with: event) }
        if excludedRect.contains(point) { return nil }
        // Only a REAL touch dismisses. Accessibility and UI-automation
        // hit-probes (VoiceOver exploration, XCUITest hittability checks)
        // also run hitTest — with a nil or non-touch event — and must not
        // put the menu away under the user. Async and latched: hitTest runs
        // several times per touch and must stay side-effect-free within a
        // pass.
        if event?.type == .touches, !dismissScheduled {
            dismissScheduled = true
            DispatchQueue.main.async { self.onOutsideTap() }
        }
        return nil
    }
}

/// Presents the bloom menu in a window-attached overlay and owns its
/// lifecycle. The composer's hosted tree never changes size — the bar stays
/// bolted in place while the menu blooms over the transcript.
@MainActor
final class ComposerAttachMenuPresenter: ObservableObject {
    /// Drives the + → × rotation on the attach button.
    @Published private(set) var isOpen = false
    private var overlay: ComposerAttachMenuOverlayView?
    private var model: ComposerAttachMenuOverlayModel?

    func toggle(actions: [ComposerAttachMenuItem], media: [ComposerAttachMenuItem], anchor: CGRect) {
        if isOpen {
            dismiss()
        } else {
            present(actions: actions, media: media, anchor: anchor)
        }
    }

    func present(actions: [ComposerAttachMenuItem], media: [ComposerAttachMenuItem], anchor: CGRect) {
        guard overlay == nil, anchor != .zero,
              let window = UIApplication.shared.connectedScenes
              .compactMap({ $0 as? UIWindowScene })
              .flatMap(\.windows)
              .first(where: \.isKeyWindow)
        else { return }
        let model = ComposerAttachMenuOverlayModel()
        let view = ComposerAttachMenuOverlayView(
            model: model,
            actions: actions,
            media: media,
            anchor: anchor,
            onOutsideTap: { [weak self] in self?.dismiss() }
        )
        view.frame = window.bounds
        window.addSubview(view)
        overlay = view
        self.model = model
        isOpen = true
    }

    func dismiss() {
        guard let overlay else { return }
        isOpen = false
        self.overlay = nil
        // Collapse the bloom, then tear the overlay down once it has faded.
        if let model {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.92)) { model.shown = false }
        }
        model = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            overlay.removeFromSuperview()
        }
    }
}

/// Posted when the composer's system edit menu opens or closes, so chrome that
/// shares the strip above the capsule can step aside for it. A notification and
/// not a shared observable: the composer needs a REAL @State change to re-render
/// on, and `.onReceive` guarantees one.
extension Notification.Name {
    static let personaComposerEditMenuVisibility =
        Notification.Name("PersonaComposerEditMenuVisibility")
}

/// A weak handle on the interaction showing this app's edit menu, so the pill
/// can be put away without re-deriving it from the first responder — which the
/// caller that most needs the dismissal (a hands-free voice memo, which hands
/// the keyboard down as it starts) has already given up. Weak because the
/// interaction belongs to the text view, torn down on UIKit's schedule.
@MainActor
private enum ComposerEditMenu {
    private static weak var interaction: UIEditMenuInteraction?

    static func remember(_ next: UIEditMenuInteraction) { interaction = next }

    static func dismiss() { interaction?.dismissMenu() }
}

/// Hands the interaction the SYSTEM's suggested actions (Paste, Select All, …
/// — computed from the first responder) verbatim. Without a delegate the
/// interaction presents an EMPTY menu, i.e. nothing. Stateless, so the
/// unsafe-shared singleton is benign.
private final class PersonaEditMenuDelegate: NSObject, UIEditMenuInteractionDelegate {
    nonisolated(unsafe) static let shared = PersonaEditMenuDelegate()

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        UIMenu(children: suggestedActions)
    }

    // Both callbacks arrive on the main thread with the menu's presentation.
    // They fire for the menu this app presents (`presentEditMenuOnFocusedField`),
    // which is every route into it: the field's own re-tap handler and the
    // capsule-level tap both go through that one function.
    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        willPresentMenuFor configuration: UIEditMenuConfiguration,
        animator: any UIEditMenuInteractionAnimating
    ) {
        NotificationCenter.default.post(
            name: .personaComposerEditMenuVisibility, object: nil, userInfo: ["visible": true]
        )
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        willDismissMenuFor configuration: UIEditMenuConfiguration,
        animator: any UIEditMenuInteractionAnimating
    ) {
        NotificationCenter.default.post(
            name: .personaComposerEditMenuVisibility, object: nil, userInfo: ["visible": false]
        )
    }
}

/// Locates the current first responder (the focused text view) so the composer can
/// finalize a pending IME composition before clearing the draft. Uses the standard
/// `sendAction(nil target)` walk up the responder chain.
@MainActor
enum PersonaFirstResponder {
    private static weak var found: UIResponder?

    static func current() -> UIResponder? {
        found = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.persona_captureFirstResponder(_:)), to: nil, from: nil, for: nil
        )
        return found
    }

    static func store(_ responder: UIResponder) { found = responder }
}

private extension UIResponder {
    @objc func persona_captureFirstResponder(_ sender: Any) {
        MainActor.assumeIsolated { PersonaFirstResponder.store(self) }
    }
}
