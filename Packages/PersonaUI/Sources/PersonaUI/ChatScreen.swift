import os
import PersonaCore
import PersonaDesign
import PersonaService
import QuickLook
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// The Chat page: an intrinsically-sized bubble transcript that sticks to the
/// bottom. Long-press a bubble for Copy / Reply; swipe a bubble left to reveal
/// each message's timestamp.
struct ChatScreen: View, Equatable {
    // Gate re-renders on the real inputs only: when the parent (PersonaRootView)
    // re-runs for unrelated reasons — opening a sheet, toggling reply — the
    // freshly-allocated closures below would otherwise force a full transcript
    // rebuild. Observation still updates this view when `messages` etc. change.
    nonisolated static func == (lhs: ChatScreen, rhs: ChatScreen) -> Bool {
        lhs.messages == rhs.messages
            && lhs.toolTrails == rhs.toolTrails
            && lhs.scrollTick == rhs.scrollTick
            && lhs.isStreaming == rhs.isStreaming
            && lhs.liveStatus == rhs.liveStatus
            && lhs.isLoadingHistory == rhs.isLoadingHistory
            && lhs.extraBottomInset == rhs.extraBottomInset
            && lhs.extraTopInset == rhs.extraTopInset
            && lhs.restGapAdjust == rhs.restGapAdjust
            && lhs.revealMessageID == rhs.revealMessageID
    }

    let messages: [ChatMessage]
    /// Tool trails, keyed by the assistant message they produced. Rendered as
    /// a collapsed "Worked …" box directly above that reply.
    var toolTrails: [UUID: ChatToolTrail] = [:]
    let scrollTick: Int
    /// Bumped once after the keyboard's focus transition has settled. Kept
    /// True while a history fetch is in flight. With an EMPTY transcript this
    /// renders the shimmer skeleton (first run / evicted snapshot / notification
    /// cold-start); with cached content on screen it renders nothing extra.
    var isLoadingHistory = false
    /// True while a reply turn is in flight (awaiting tokens, streaming them,
    /// or running a tool). Drives the loading row and the token-append fast
    /// path — distinct from `liveStatus`, which is only the tool-phase label.
    var isStreaming = false
    /// Extra transcript bottom clearance while chrome (the quick-chips row)
    /// rides in the composer bar above the capsule.
    var extraBottomInset: CGFloat = 0
    /// Extra transcript TOP clearance when the surface stacks something under
    /// the header (the private chat's "Nothing is saved" capsule), which would
    /// otherwise sit on top of the first message.
    var extraTopInset: CGFloat = 0
    /// Rest-state trim on the clearance spacer, per mount. Surfaces whose bar
    /// is the plain SwiftUI composer resting at the safe-area bottom — the main
    /// chat, the history overlay, and the private chat — pass −34: it lands the
    /// last message the same ~24pt above the bar focused and at rest (rest gap
    /// = inset + clearance − barHeight; typing gap = inset + clearance −
    /// 28-trim − barHeight; see `keyboardGapAdjust`). The param stays live (not
    /// collapsed to a constant): the reply-thread overlay and the bar-less
    /// preview rigs mount ChatScreen with no resting composer and keep the 0
    /// default.
    var restGapAdjust: CGFloat = 0
    /// Starts a composer reply to a message. Nil where the surface has no
    /// reply wiring (history threads) — the context menu then omits Reply
    /// instead of showing a dead button.
    var onReply: ((ChatMessage) -> Void)?
    /// Latest-reply preview for a message's thread, if it has one.
    var threadPreview: ((UUID) -> String?)?
    /// Open the thread for a message.
    var onThreadSelected: ((UUID) -> Void)?
    /// Transient "currently doing X" state shown under the streaming bubble —
    /// the narrator phrase plus optional tool icon identity.
    var liveStatus: LiveToolStatus?
    /// Tapping the transcript closes the keyboard.
    var onDismissKeyboard: () -> Void = {}
    /// Tapping a "Replying to Suggestion" line — return to that card on Home.
    /// The shell decides whether the card still exists (a gone card is a no-op).
    var onOpenSuggestion: ((UUID) -> Void)?
    /// Tapping a "Replying to Event" line — return to the Up Next card on Home
    /// (a no-op once the meeting has passed off the card).
    var onOpenMeeting: (() -> Void)?
    /// Tapping Retry on a failed turn's error row — re-runs that send.
    var onRetry: (() -> Void)?
    /// The bubble a tapped notification announced: once a message with this id
    /// is in the transcript, glide it to center and pulse it (same treatment as
    /// a "Replying to …" jump). Stays armed while the row is missing — a cold
    /// start loads the transcript AFTER the route lands — and the shell owns
    /// the give-up timeout.
    var revealMessageID: UUID?
    /// The reveal landed — the shell clears its pending id (and its timeout).
    var onRevealConsumed: (() -> Void)?

    #if DEBUG
        /// Native keyboard-inset trace: one line per inset change on
        /// this surface. `log show --predicate 'category == "kbprobe"'`.
        static let kbProbeLog = Logger(subsystem: "persona.chatheal", category: "kbprobe")
    #endif

    /// The long message open in the full-screen reader — "Read more" ALWAYS
    /// presents there (never expands inline: a multi-screen bubble inside the
    /// LazyVStack re-layouts on every scroll frame and the transcript chugs).
    /// A tapped "Pasted" attachment tile opens here too (a synthetic message
    /// carrying the pasted text).
    @State private var readerMessage: ChatMessage?
    /// A tapped user-attached DOCUMENT (picked PDF/CSV, not a paste), fetched
    /// to a temp file for QuickLook.
    @State private var fileQuickLookURL: URL?
    /// The quoted message currently pulsing after a "Replying to" jump.
    @State private var flashedMessageID: UUID?
    /// Shared left-swipe reveal: dragging the transcript left slides every
    /// bubble over to expose each message's timestamp on the right. An
    /// @Observable box this body only PASSES ALONG, never reads — the pan's
    /// per-frame writes reach each row's leaf reveal modifier directly,
    /// skipping the transcript (see ChatTimestampRevealModel).
    @State private var timestampReveal = ChatTimestampRevealModel()
    /// In a page-style TabView, `onAppear` re-fires on every swipe back to this
    /// page — the cold-start bottom pin must run once, not on each revisit
    /// (returning to Chat keeps the position the transcript was left at).
    @State private var didInitialBottomPin = false
    /// The surface's live bottom inset — the mount's OWN safe area (Phase 2
    /// mount flip: every ChatScreen surface is a live-safe-area mount now),
    /// measured by the geometry probe below. A VALUE READ for the gap
    /// constants, never a mover.
    @State private var nativeBottomInset: CGFloat = 0
    /// Non-observed scratch for the geometry probe: mutating a plain class
    /// doesn't invalidate this view — the point. The probe fires on every
    /// frame of the keyboard ride; only the SETTLED value commits to
    /// `nativeBottomInset` (see the probe site), so the ride itself no longer
    /// re-runs this body per frame.
    private final class InsetProbeBox {
        var pending: CGFloat = 0
        var commit: Task<Void, Never>?
    }

    @State private var insetProbe = InsetProbeBox()

    /// The keyboard is in this surface's bottom inset. 100 is a plausibility
    /// floor between the two real resting insets: the home-indicator strip
    /// reads ~34, the smallest keyboard ~216.
    private var keyboardInWindow: Bool { nativeBottomInset > 100 }

    /// The root pager's latched-horizontal drag — the transcript freezes its
    /// own vertical scrolling for exactly that gesture (see PersonaRootView).
    @Environment(\.pagerHorizontalDragActive) private var pagerHorizontalDragActive

    /// API access for tapped attachment tiles (fetching a reloaded bubble's
    /// asset). Optional: preview rigs don't inject it — taps fall back to the
    /// message's local bytes or no-op.
    @Environment(SettingsStore.self) private var settings: SettingsStore?

    /// True while the transcript is scrolled meaningfully away from its
    /// resting bottom — drives the floating jump-to-latest chevron, and lets
    /// the reader's position win over the forced scroll-to-bottom.
    @State private var scrolledAwayFromBottom = false
    /// True while a programmatic reveal (reply-quote jump / notification
    /// landing) is gliding the transcript. The away-flip below is gated on
    /// `isUserScrolling` (content growing under a resting reader must not
    /// strand the chevron), but a reveal is the READER moving with intent —
    /// its geometry crossing must arm the chevron too, or a tapped
    /// "Replying to" jump lands deep in history with no way back down
    ///.
    @State private var revealJumpInFlight = false
    /// True while the content is taller than the VISIBLE viewport (container
    /// minus insets — the keyboard's safe-area share included). This is the
    /// live geometric truth behind every explicit scroll's edge choice:
    /// "short thread reads top-down" applies exactly while the content FITS,
    /// and flips the moment it doesn't — including when the keyboard shrinks
    /// the viewport. The old `isLongTranscript` char-count heuristic called
    /// a five-message CARD deck "short" while it overflowed two screens, so
    /// the focus-settle pin scrolled it to the TOP and buried the newest
    /// cards under the keys (field report: text tails rode the
    /// keyboard, card decks didn't — the decks just never hit 1800 chars).
    ///
    /// Starts TRUE deliberately: geometry only lands after the first scroll
    /// pass, and the two error modes are asymmetric — a bottom-edge scroll
    /// on content that actually fits is a visual NO-OP (the .alignment
    /// anchor owns undersized placement), while a top-edge scroll on content
    /// that actually overflows yanks the transcript to its top (the card
    /// deck parked at its first card).
    @State private var contentOverflows = true
    /// True while a finger (or its fling) is driving the transcript — forced
    /// scrolls yield to it even before the 240pt "away" slack is crossed.
    @State private var isUserScrolling = false
    /// The newest message at the moment the reader scrolled up into history.
    /// The chevron badge DERIVES its count from this anchor (assistant messages
    /// with content that sit after it) instead of counting append events —
    /// a streamed reply is appended EMPTY at send time and only fills in later,
    /// so an event counter misses it. Nil whenever the transcript is anchored
    /// at the bottom.
    @State private var lastSeenOnScrollUp: UUID?
    // (ScrollPosition is GONE from this surface,: with the binding
    // attached, every programmatic scroll was inert on the dead-safe-area
    // mount — see the note at the old .scrollPosition call site. The
    // proxy.scrollTo(id) lands-short-on-lazy-estimates weakness it was
    // brought in for is covered by scrollToBottom's settle corrective.)
    /// Bumped when TranscriptHealView reports the transcript's content layers
    /// died and its scroll-nudge couldn't revive them — the new identity
    /// forces a full content rebuild (see TranscriptHealView.rebuildNote).
    @State private var transcriptRebuildTick = 0

    #if canImport(UIKit)
        /// The two UIKit attachments riding over the transcript. Extracted from
        /// the `.overlay` at the call site purely so the surrounding modifier
        /// chain stays inside the type checker's budget.
        private var transcriptGestureLayer: some View {
            ZStack {
                // Watches the transcript's real CALayer tree and repairs the
                // "blank chat after a long send" state the moment it appears.
                TranscriptHealAttachment()
                HorizontalSwipeGestureAttachment(
                    axisRatio: 1.08,
                    edgeSwipeWidth: 0,
                    allowsRightward: false,
                    onChanged: { timestampReveal.dragChanged(translationX: $0.width) },
                    onEnded: { _ in timestampReveal.settle() }
                )
            }
        }
    #endif

    private static let bottomID = "persona-chat-bottom"
    /// Bounded eager tail (root-canvas normalization, Phase 2): how many
    /// trailing rows the plain VStack renders. Bounded so eager layout stays
    /// amortized by the render-cache warmer (≤80 rows — the codex bound);
    /// history above mounts through the "Show earlier" seam in `earlierChunk`
    /// slabs.
    private static let eagerTailCount = 60
    private static let earlierChunk = 60
    /// The oldest RENDERED row — the pagination seam. Latched by ID, not
    /// index: an index-relative window would drop its top row on every
    /// append, shifting everything above the viewport under a reader.
    /// Nil (or an ID a reload dropped) falls back to the newest
    /// `eagerTailCount` rows and re-latches (`latchTailSeam`).
    @State private var earliestRenderedID: UUID?
    /// QA (CHAT_QA_ANCHOR_PROBE=1, AnchorAliveProbe): every explicit at-bottom
    /// mover stands down so the declarative `.sizeChanges` anchor is the ONLY
    /// candidate mover — the canary measures the anchor itself, not the
    /// compensations layered over its inertness (; root-canvas
    /// normalization Phase 0). Unset = production behavior, untouched.
    private static let anchorProbeIsolation =
        ProcessInfo.processInfo.environment["CHAT_QA_ANCHOR_PROBE"] == "1"
    /// QA (CHAT_QA_ANCHOR_OFF=1, AnchorAliveProbe): withhold the `.sizeChanges`
    /// anchor entirely — the probe's attribution arm (see the anchor site).
    private static let anchorProbeAnchorOff =
        ProcessInfo.processInfo.environment["CHAT_QA_ANCHOR_OFF"] == "1"
    // (The `isLongTranscript` char-count regime heuristic is GONE,:
    // every consumer now reads `contentOverflows` — the scroll view's own
    // geometry — instead. The heuristic existed because the old measured-
    // overflow latch consumed the lazy stack's garbage first-frame height
    // ESTIMATES; `onScrollGeometryChange` reports settled truth, first
    // placement is owned declaratively by `.initialOffset`, and a heuristic
    // that called a two-screen card deck "short" buried its newest cards
    // under the keyboard.)

    /// The transcript actually rendered: while a turn is in flight, the
    /// trailing run of EMPTY pending assistant bubbles is dropped — the
    /// loading row (mark + shimmering status) is the one "working" signal,
    /// never an empty bubble. The RUN matters: a burst split appends ALL of
    /// its waiting bubbles at once (BurstReveal.present), so dropping only
    /// the last left the middle ones on screen as empty bubbles between
    /// reveals. Each bubble reappears the moment its text lands.
    private var visibleMessages: [ChatMessage] {
        guard isStreaming else { return messages }
        var end = messages.count
        while end > 0 {
            let message = messages[end - 1]
            guard !message.isUser, message.text.isEmpty, message.cards.isEmpty,
                  message.imageData == nil, message.imageRemotePaths.isEmpty,
                  !message.isVoiceMessage
            else { break }
            end -= 1
        }
        return end == messages.count ? messages : Array(messages[..<end])
    }

    /// How close (in visible messages) two cards for the SAME task must be for
    /// the later one to fold away.
    private static let taskCardRepeatWindow = 5

    /// Task ids per message whose task card (a `delegation` card or the
    /// finished-task reference) repeats one the transcript already shows within
    /// the previous `taskCardRepeatWindow` messages. The backend re-surfaces a
    /// task's card on EVERY touch — the hand-off, a steer/status/resume, the
    /// result posting back — which stacked identical cards almost back-to-back
    ///. The FIRST card stays (it's live and upgrades in
    /// place); near repeats fold. Anchored to the last card actually SHOWN, so
    /// a long-running task that keeps reporting still re-surfaces a card at
    /// least every `taskCardRepeatWindow` messages.
    /// Memo for the O(n) fold below. Body re-evals far outnumber transcript
    /// changes (scroll state, keyboard, streaming flags all re-run body), so
    /// the fold recomputes only when a fingerprint over exactly the fields it
    /// reads — card/task identity and the per-message has-content bits —
    /// changes. Streaming text growth doesn't move the fingerprint (the fold
    /// reads `text.isEmpty`, which flips once on the first token), so a
    /// streaming reply no longer rebuilds the fold per token.
    @MainActor
    private enum TaskRepeatsMemo {
        static var fingerprint = 0
        static var output: [UUID: Set<String>] = [:]
    }

    private static func taskCardRepeatsMemoized(in messages: [ChatMessage]) -> [UUID: Set<String>] {
        var hasher = Hasher()
        for message in messages {
            hasher.combine(message.id)
            hasher.combine(message.taskReferenceId)
            hasher.combine(message.text.isEmpty)
            hasher.combine(message.isVoiceMessage)
            hasher.combine(message.imageData == nil)
            hasher.combine(message.imageRemotePaths.isEmpty)
            for card in message.cards {
                if case let .delegation(taskId, _, _) = card { hasher.combine(taskId) } else { hasher.combine(0) }
            }
        }
        let fingerprint = hasher.finalize()
        if fingerprint != TaskRepeatsMemo.fingerprint {
            TaskRepeatsMemo.output = taskCardRepeats(in: messages)
            TaskRepeatsMemo.fingerprint = fingerprint
        }
        return TaskRepeatsMemo.output
    }

    private static func taskCardRepeats(in messages: [ChatMessage]) -> [UUID: Set<String>] {
        var lastShown: [String: Int] = [:]
        var repeats: [UUID: Set<String>] = [:]
        for (index, message) in messages.enumerated() {
            // Only the finished-task RECEIPT can repeat now: a message's own
            // delegation card no longer draws (it moved to the composer tray —
            // see ChatRow.renderableCards), so it can't be the anchor a later
            // card folds against. Counting it was what hid the completion
            // message's receipt when the hand-off sat a row or two above.
            var ids: [String] = []
            if let ref = message.taskReferenceId { ids.append(ref) }
            guard !ids.isEmpty else { continue }
            var suppressed: Set<String> = []
            for id in Set(ids) {
                if let shown = lastShown[id], index - shown < taskCardRepeatWindow {
                    suppressed.insert(id)
                } else {
                    lastShown[id] = index
                }
            }
            // Never fold a row to nothing: a message whose only visible content
            // is the task card keeps it (and becomes the new anchor).
            if !suppressed.isEmpty, !hasContentBesidesTaskCards(message, suppressed: suppressed) {
                for id in suppressed {
                    lastShown[id] = index
                }
                suppressed = []
            }
            if !suppressed.isEmpty { repeats[message.id] = suppressed }
        }
        return repeats
    }

    /// Whether the message still renders something once the given task cards
    /// fold away — text, a voice clip, an image, or any other card.
    private static func hasContentBesidesTaskCards(_ message: ChatMessage, suppressed _: Set<String>) -> Bool {
        if !message.text.isEmpty || message.isVoiceMessage { return true }
        if message.imageData != nil || !message.imageRemotePaths.isEmpty { return true }
        // Delegation cards never draw from the payload any more, so they can't
        // be what keeps a folded row from rendering empty.
        return message.cards.contains { card in
            if case .delegation = card { return false }
            return true
        }
    }

    /// The loading row shows while the in-flight turn has nothing visible yet
    /// (waiting on the first token — the pending bubble is being dropped
    /// above) or a tool is running mid-turn (`liveStatus`). It never lingers
    /// under a reply that is already streaming plain text: there, the text is
    /// the signal.
    private func showsLoadingIndicator(in rows: [ChatMessage]) -> Bool {
        isStreaming && (liveStatus != nil || rows.count != messages.count)
    }

    /// The trailing assistant bubble's identity and whether it has said
    /// anything yet — streamed text or an inline card (a cards-only reply
    /// never fills `text`). Watched at the transcript level, NOT on the lazy
    /// row: with the transcript scrolled up into history the new row may
    /// never be instantiated, and the received-message buzz must land
    /// regardless of scroll position. The bubble is born empty (hidden behind
    /// the loading row), so the empty→content flip fires exactly once per
    /// message and never on a history load or thread switch (those rows
    /// arrive with content).
    private var assistantContentFlip: AssistantContentFlip {
        guard let last = messages.last, !last.isUser else { return AssistantContentFlip() }
        return AssistantContentFlip(id: last.id, hasContent: !last.text.isEmpty || !last.cards.isEmpty)
    }

    private struct AssistantContentFlip: Equatable {
        var id: UUID?
        var hasContent = false
    }

    /// A bubble the user can actually READ — streamed text, a card, an image,
    /// or a voice clip. The trailing assistant bubble is born with none of
    /// these (hidden behind the loading row), so it doesn't count as "said"
    /// until it fills.
    private func hasSaidSomething(_ message: ChatMessage) -> Bool {
        !message.text.isEmpty || !message.cards.isEmpty || message.imageData != nil || message.isVoiceMessage
    }

    /// Assistant messages that SAID something after the scroll-up anchor — the
    /// chevron badge's count. Recomputes as streaming fills the trailing
    /// bubble, so a reply born empty starts counting the moment it has content.
    /// 0 while anchored at the bottom.
    private var unseenWhileAway: Int {
        guard scrolledAwayFromBottom, let anchor = lastSeenOnScrollUp,
              let anchorIndex = messages.firstIndex(where: { $0.id == anchor })
        else { return 0 }
        return messages[messages.index(after: anchorIndex)...]
            .count { !$0.isUser && hasSaidSomething($0) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                transcriptContent(proxy)
            }
            // Rest at the bottom and STAY pinned to it as content grows / the
            // keyboard inset changes. Without this the manual `scrollTo(bottom)`
            // races layout on open/send (it scrolls before the new content's
            // height settles), leaving the transcript resting above the true
            // bottom — so the bottom clearance shows up as scrollable empty space
            // under the last message. The declarative bottom anchor removes that
            // race; the explicit `scrollTo` calls below stay only for the soft
            // animated settle on focus / page / thread changes.
            //
            // Role-separated anchors (the DeepTaskThreadView recipe, which
            // replaced this screen's measured-overflow latch): each scroll
            // behavior is declared for its own trigger, so no live measurement
            // ever decides the regime and nothing can flip after first paint.
            // - .alignment: content SHORTER than the viewport top-aligns — a
            // fresh/short conversation reads top-down like a document
            //.
            // Native undersized-content alignment replaces the old
            // fill-the-viewport minHeight frame.
            // - .initialOffset: the FIRST layout of an overflowing transcript
            // starts at the bottom — the cold open lands on the newest
            // message with no post-entry flip and no scripted scroll.
            // - .sizeChanges: content growth (streaming tokens) AND container
            // shrink (the keyboard's safe-area inset,) re-pin the
            // bottom while the reader is at the bottom. A reader up in
            // history is never yanked down (the chevron is the way back).
            // NOT gated on isLongTranscript anymore: that gate predates the
            // native keyboard inset — with the keyboard-sized clearance
            // spacer gone, a short thread can no longer be "dragged to the
            // composer" by its own spacer, but an ungated keyboard inset
            // WOULD bury a card-tailed short thread under the keys (field
            // report: text tails rode, card decks didn't — long
            // vs short, not text vs cards). Undersized content still
            // top-aligns via the .alignment anchor, which wins while the
            // content fits.
            .defaultScrollAnchor(.top, for: .alignment)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            // CHAT_QA_ANCHOR_OFF (AnchorAliveProbe attribution arm): with the
            // anchor withheld the same stimulus must FREEZE the tail — proof
            // that a re-pin measured under CHAT_QA_ANCHOR_PROBE isolation was
            // the anchor itself, not a mover the isolation missed.
            .defaultScrollAnchor(
                !scrolledAwayFromBottom && !Self.anchorProbeAnchorOff ? .bottom : nil,
                for: .sizeChanges
            )
            // The root pager owns a latched-horizontal page drag — the
            // transcript must not also creep vertically under it (the finger
            // always arcs a little). Freezes exactly for that drag.
            .scrollDisabled(pagerHorizontalDragActive)
            // QA hook (CHAT_QA_AUTOSCROLL=1): drive the transcript top⇄bottom
            // programmatically so a headless harness can reproduce (and
            // `sample`) the scroll-back main-thread stall without XCUITest
            // synthesized swipes (which starve on this transcript).
            .task {
                guard ProcessInfo.processInfo.environment["CHAT_QA_AUTOSCROLL"] == "1" else { return }
                try? await Task.sleep(for: .seconds(4))
                for _ in 0 ..< 4 {
                    // Top of the RENDERED window (the seam) — an unmounted
                    // row above it is not a scroll target (scrollTo no-ops).
                    let rows = visibleMessages
                    let start = tailStart
                    if start < rows.count {
                        withAnimation(.smooth(duration: 1.0)) { proxy.scrollTo(rows[start].id, anchor: .top) }
                    }
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation(.smooth(duration: 1.0)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                    try? await Task.sleep(for: .seconds(3))
                }
            }
            // NO .scrollPosition binding — deliberately.
            // With the binding attached, EVERY programmatic scroll on this
            // mount was inert: the geometry trace () showed the
            // offset frozen through proxy pins, edge latches, and an active
            // sizeChanges anchor — the binding owns positioning and swallows
            // the proxy's ID-targeted scrolls. The ScrollViewReader proxy +
            // bottom marker is the ONE scroll authority on this surface.
            .onReceive(NotificationCenter.default.publisher(for: TranscriptHealView.rebuildNote)) { _ in
                transcriptRebuildTick += 1
            }
            // iOS 26 injects an automatic scroll-edge effect (progressive
            // white-ish wash) where the transcript runs under the status bar —
            // the "white bar behind the Dynamic Island". The old solid header
            // hid it; with the whisper glass ramp it reads as a stray white
            // band, so hide the system effect and let the ramp be the only
            // top treatment.
            .modifier(TopScrollEdgeEffectHidden())
            // ONE presentation host for the whole transcript (not per-row —
            // same rationale as the photo viewer's `enabled` gate).
            .fullScreenCover(item: $readerMessage) { message in
                ChatMessageReader(message: message)
            }
            // Tapped user-attached document (non-pasted): fetched to a temp
            // file and previewed in place, same hand-off as FileCardView.
            .quickLookPreview($fileQuickLookURL)
            // Floating jump-to-latest: reading history far from the bottom
            // shows a glass chevron above the composer (the Telegram/WhatsApp
            // convention); tap glides back down. 240pt of slack keeps it from
            // flickering during ordinary near-bottom bounces.
            // The live overflow read (see `contentOverflows`): content height
            // against the viewport that remains after insets — the keyboard's
            // safe-area share arrives in contentInsets.bottom, so this flips
            // exactly when focusing shrinks a fitting thread into overflow.
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentSize.height > geo.containerSize.height
                    - geo.contentInsets.top - geo.contentInsets.bottom
            } action: { _, overflows in
                if contentOverflows != overflows { contentOverflows = overflows }
            }
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentSize.height - geo.visibleRect.maxY > 240
            } action: { _, away in
                guard scrolledAwayFromBottom != away else { return }
                // Only a READER can strand the transcript away from the bottom.
                // Content growing underneath them — history landing on open,
                // proactive reminders arriving, a card row re-measuring — moves
                // `contentSize` without the reader moving at all, and that geometry
                // alone would flip this true. The flip is self-sealing: the auto-pin
                // on `messages.count` below is gated on this flag, so once it sticks
                // nothing re-pins the transcript, and the chevron sits there over a
                // transcript that is visually AT the bottom. Coming BACK to the
                // bottom always clears, however it happened.
                if away, !isUserScrolling, !revealJumpInFlight { return }
                withAnimation(.snappy(duration: 0.22)) { scrolledAwayFromBottom = away }
                // Scrolling up drops the badge anchor at the newest message the
                // user could actually have READ — skipping a trailing assistant
                // bubble that hasn't said anything yet (scrolling up mid-stream
                // is the common case, and that bubble's content is still unseen).
                // Re-anchoring to the bottom (however it happened) clears it.
                lastSeenOnScrollUp = away ? messages.last(where: hasSaidSomething)?.id : nil
            }
            .onScrollPhaseChange { _, phase in
                isUserScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
            }
            // A horizontal page swipe freezes the transcript mid-scroll
            // (`scrollDisabled` above). If a vertical phase was live when the
            // freeze hit, `onScrollPhaseChange` never gets its `.idle` and
            // `isUserScrolling` strands TRUE — which then gates off the auto-pin
            // for new replies AND lets the next content-growth poison
            // `scrolledAwayFromBottom` (its `!isUserScrolling` guard passes),
            // so an assistant reply lands below the fold and only shows after a
            // page round-trip re-anchors the transcript. Clearing
            // it on every pager-drag transition keeps the flag honest.
            .onChange(of: pagerHorizontalDragActive) { _, _ in
                if isUserScrolling { isUserScrolling = false }
            }
            .overlay(alignment: .bottomTrailing) { jumpToLatestOverlay(proxy) }
            .onGeometryChange(for: [CGFloat].self) { proxy in
                [
                    proxy.safeAreaInsets.bottom,
                    proxy.frame(in: .global).maxY,
                    proxy.size.height
                ]
            } action: { values in
                // This fires on EVERY frame of the keyboard ride (all three
                // components sweep with the system curve). The @State commit
                // is debounced into the scratch box: `nativeBottomInset` is a
                // VALUE READ for the gap constants, never a mover (see its
                // doc), so nothing needs the mid-flight values — and an
                // immediate write here re-ran this whole body on every frame
                // of the ride, exactly when frames are most expensive. One
                // commit lands once the geometry has been quiet for ~80ms.
                insetProbe.pending = values[0]
                insetProbe.commit?.cancel()
                insetProbe.commit = Task { @MainActor [insetProbe] in
                    try? await Task.sleep(for: .milliseconds(80))
                    guard !Task.isCancelled else { return }
                    if nativeBottomInset != insetProbe.pending {
                        nativeBottomInset = insetProbe.pending
                    }
                }
                // EXCEPT a keyboard-regime flip, which commits mid-ride: the
                // debounce alone landed `keyboardInWindow`'s 6pt gap trim
                // ~80ms AFTER the ride settled — a bare un-animated nudge on
                // an otherwise resting transcript, once per focus/dismiss
                // (the transcript "adjusting itself", design report
                //). Committing at the crossing folds the trim into
                // the system's animated resize, where it always lived before
                // the debounce. One extra body eval per transition, not per
                // frame — and only DEEP in the new regime (< 50 / > 150, vs
                // the ~34 rest and ~216-min keyboard resting points), so a
                // guide hovering AT the 100 threshold can't saw the gap (the
                // "possessed transcript" class); hover values take the
                // debounced path and land once, quiet.
                let regimeFlipped = (values[0] > 100) != (nativeBottomInset > 100)
                if regimeFlipped, values[0] < 50 || values[0] > 150 {
                    nativeBottomInset = values[0]
                }
                #if DEBUG
                    Self.kbProbeLog
                        .log(
                            "chat inset bottom=\(values[0], format: .fixed(precision: 1)) frameMaxY=\(values[1], format: .fixed(precision: 1)) h=\(values[2], format: .fixed(precision: 1))"
                        )
                #endif
            }
            .scrollDismissesKeyboard(.interactively)
            // iOS 26 paints an automatic scroll-edge wash (a systemBackground
            // capture) over content near the scroll view's edges. On the
            // full-bleed main chat it hides under the island, but the history/
            // private overlays mount LOWER, so the band lands mid-transcript
            // and reads as a "weird glass gradient" washing out bubbles
            //. The design's own
            // top fade below is the only edge treatment this surface wants.
            .transcriptEdgeEffectHidden()
            // Soft top-fade so the transcript dissolves into the background under
            // the Dynamic Island instead of clipping with a hard edge (matches the
            // design; same treatment as the Settings / Iris-menu scroll surfaces).
            .topScrollFade()
            .onTapGesture {
                onDismissKeyboard()
            }
            .onAppear {
                // QA hook (shot tests): pin the left-swipe timestamp reveal
                // open — XCUITest can't hold a drag mid-screenshot, and the
                // reveal springs back on release. "1" pins it fully open; any
                // other number pins that many points, which is the only way to
                // sample a PARTIAL swipe — where the labels' entrance actually
                // plays out (every pin lands on the same fully-open frame).
                if let raw = ProcessInfo.processInfo.environment["CHAT_QA_TIMESTAMP_REVEAL"] {
                    let pinned = raw == "1"
                        ? ChatTimestampRevealModel.maxReveal
                        : (Double(raw).map { CGFloat($0) } ?? 0)
                    if pinned > 0 {
                        timestampReveal.pin(pinned)
                    }
                }
                // QA hook (settle-stability shot): cycle the reveal open →
                // settle forever, so a headless test can sample frames through
                // every drag start and settle end (XCUITest synthesized pans
                // starve on this transcript). The 5s lead-in lets the test
                // grab a fully-resolved rest reference first.
                if ProcessInfo.processInfo.environment["CHAT_QA_TIMESTAMP_CYCLE"] == "1" {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(5))
                        while !Task.isCancelled {
                            timestampReveal.pin(ChatTimestampRevealModel.maxReveal)
                            try? await Task.sleep(for: .milliseconds(700))
                            timestampReveal.settle()
                            try? await Task.sleep(for: .milliseconds(1300))
                        }
                    }
                }
                latchTailSeam()
                guard !didInitialBottomPin else { return }
                didInitialBottomPin = true
                // Entry pin, proxy-based with the settle corrective:
                // `.initialOffset` places against the lazy stack's EARLY
                // height estimates and goes stale as rows measure in — the
                // geometry trace () caught a card deck parked
                // 1400pt above its true bottom with the offset frozen, every
                // declarative re-anchor (edge latch, sizeChanges) inert on
                // this mount. The corrective pin lands the real bottom once
                // measuring settles; a transcript that fits does nothing
                // (scrollToBottom's overflow guard).
                scrollToBottom(proxy, animated: false)
                // Warm the render caches for the whole painted transcript in
                // the background: the visible tail parses on the first frame
                // regardless, but history above the fold stays cold until
                // scrolled — each cold bubble then parsed on the render loop
                // (the history-scroll stutter). One pass per process; utility
                // QoS so it yields to the launch storm. Plain Sendable tuples
                // cross the isolation boundary, not messages.
                let lastID = visibleMessages.last?.id
                let rows = visibleMessages.map { (text: $0.text, isUser: $0.isUser, collapsible: $0.id != lastID && !$0.isVoiceMessage) }
                Task.detached(priority: .utility) {
                    ChatBubbleContent.warmRenderCaches(rows: rows)
                }
            }
            .onChange(of: messages.count) {
                // A new turn animates softly to the bottom — unless the user
                // is reading history (scrolled away, or a finger down): their
                // position wins and the chevron is the way back. Their OWN
                // send always re-pins, like iMessage. The explicit scroll is
                // the ONLY at-bottom mover here — the sizeChanges anchor is
                // empirically inert on this mount (geometry trace,
                //), so a briefly-tried "let the anchor own
                // arrivals" gate left assistant messages below the fold.
                // An armed notification reveal also wins: the same count
                // change that delivers the announced bubble would otherwise
                // race this pin (its corrective scroll lands mid-glide and
                // strands the flash off-screen).
                latchTailSeam()
                guard revealMessageID == nil else { return }
                if messages.last?.isUser == true {
                    // The user's OWN send: ALWAYS to the very bottom from ANY
                    // depth, whole sent message visible. ONE animated pin
                    // (with scrollToBottom's staged correctives) — it
                    // replaces the followNote display-link follower, whose
                    // observer was never registered (dead code since its
                    // introduction; the send ride silently fell to the
                    // streaming pins). The eager tail's settled heights make
                    // a one-shot pin land exactly; the shimmer + first
                    // tokens that follow ride the streaming pins + the
                    // `.sizeChanges` anchor, re-armed by clearing the
                    // away-latch here.
                    scrolledAwayFromBottom = false
                    lastSeenOnScrollUp = nil
                    scrollToBottom(proxy, animated: true)
                } else if !(scrolledAwayFromBottom || isUserScrolling) {
                    // An assistant arrival follows the reader to the bottom
                    // only while they're near it — chevron-deep readers keep
                    // their place (the badge is the signal).
                    scrollToBottom(proxy, animated: true)
                }
            }
            // …but token-by-token streaming just pins instantly (no settle delay,
            // no competing 0.28s animations) so the transcript glides up smoothly.
            // Watches the COUNT, not the text: comparing the accumulated string
            // itself re-scans the whole reply on every token (O(n²) over a long
            // stream), and streaming only ever appends.
            .onChange(of: messages.last?.text.count) {
                guard !Self.anchorProbeIsolation else { return }
                guard !scrolledAwayFromBottom, !isUserScrolling else { return }
                scrollToBottom(proxy, animated: false, settle: false)
            }
            .onChange(of: liveStatus) {
                guard !scrolledAwayFromBottom, !isUserScrolling else { return }
                scrollToBottom(proxy, animated: false, settle: false)
            }
            // The bar chrome above the composer grew or shrank (task-tray
            // pills landing/leaving, attachment tiles staged/cleared): the
            // clearance spacer resizes, but the sizeChanges anchor is inert
            // on this mount (see the messages.count pin above) — so without
            // an explicit pin the new clearance stays below the fold and the
            // tray covers the last bubble (or the shimmer, which sits above
            // the same spacer). Only bites when the chrome changes WITHOUT a
            // coincident transcript mutation — a card-started task, a task
            // arriving from another surface — the chat-started path already
            // rides the arrival pin. The settle corrective matters here: the
            // spacer's growth animates (trayHeight's easeOut), so the first
            // pin lands short by whatever height hadn't landed yet.
            .onChange(of: extraBottomInset) {
                guard !scrolledAwayFromBottom, !isUserScrolling else { return }
                scrollToBottom(proxy, animated: true)
            }
            // NO explicit keyboard-ride pin — deliberately (Phase 2 mount
            // flip). The keyboard ride is the system's safe-area resize +
            // the `.sizeChanges` bottom anchor, one mover (L8): they replace
            // the `onChange(bottomInset)` animated rise pin that rode the
            // dead-safe-area mount's grown clearance spacer. Any scrollTo
            // layered over the anchor's per-frame ride is a visible
            // double-teleport. (A raw-UIKit setContentOffset ride was tried
            // for the close-side text artifact and REVERTED — worse;
            // ~2am. That artifact was never the ride: the
            // outgoing bubble FILL's positional visualEffect rendered at
            // model-final geometry, fixed at the fill — see
            // IMessageBubblePalette.outgoingFill.)
            // iMessage's received-message double tap the moment the assistant
            // SAYS something — fires whether or not the reader is at the bottom
            // (see `assistantContentFlip` for why it lives here, not the row).
            .onChange(of: assistantContentFlip) { had, has in
                if had.id == has.id, has.id != nil, !had.hasContent, has.hasContent {
                    DSHaptics.messageReceived()
                }
            }
            // External triggers (focus, starting a chat, opening a thread)
            // animate — a plain page switch back to Chat deliberately does NOT
            // tick, so the transcript stays where it was left. A tick also
            // settles any leftover reveal.
            .onChange(of: scrollTick) {
                guard !Self.anchorProbeIsolation else { return }
                if timestampReveal.active { timestampReveal.settle() }
                scrollToBottom(proxy, animated: true)
            }
            // Notification-tap reveal: try when the target arrives, when the
            // transcript (re)loads, and once on mount (cold start sets the id
            // before this view exists). Grouped into one modifier — three more
            // chained onChanges here pushed the body past the type-check budget.
            .modifier(NotificationRevealTriggers(
                revealMessageID: revealMessageID,
                messageCount: messages.count,
                attempt: { attemptNotificationReveal(proxy) }
            ))
            // Focus used to enter through `scrollTick` immediately, starting a
            // 0.28s animated scroll plus its delayed correction WHILE the
            // keyboard overlap was animating the transcript's bottom spacer.
            // Those two offset owners alternated anchors (the visible bounce in
            // design's recording). The root coalesces focus and bumps this only
            // after the keyboard curve settles; finish with one atomic pin.
        }
    }

    /// The scroll content's trailing clearance — bar chrome only, a CONSTANT
    /// (Phase 2 mount flip). The keyboard's share is the mount's own
    /// safe-area inset, which the ScrollView absorbs natively: the system's
    /// animated resize + the `.sizeChanges` bottom anchor are the whole
    /// keyboard ride (L8 — they replace the `bottomInset`-grown spacer and
    /// the `onChange(bottomInset)` rise pin this spacer used to pair with).
    /// This spacer must never animate: a spacer riding alongside a LIVE
    /// safe-area inset is a double count (the blank-screen
    /// mechanism).
    private var bottomClearance: CGFloat {
        PersonaLayout.contentBottomInset + keyboardGapAdjust + extraBottomInset
    }

    /// Keeps the last message's visual gap above the bar IDENTICAL focused
    /// and at rest, matched to the TYPING gap (~24pt) — design's reference
    /// (): the focused distance was right, the rest distance too
    /// airy. Typing keeps the classic −28 on every mount; the rest trim is
    /// per-mount (`restGapAdjust`: −34 on every shipping plain-SwiftUI-bar
    /// mount — main chat, history overlay, private chat — 0 only in bar-less
    /// preview rigs). The inset itself is the system's; this only trims the
    /// constant clearance.
    private var keyboardGapAdjust: CGFloat {
        keyboardInWindow ? -28 : restGapAdjust
    }

    // MARK: - Bounded eager tail (pagination seam)

    /// Index of the oldest rendered row in `visibleMessages`. Resolves the
    /// ID latch; without a valid latch (first content, a reload that dropped
    /// the anchored row) the window is the newest `eagerTailCount` rows.
    private var tailStart: Int { tailStart(in: visibleMessages) }

    private func tailStart(in rows: [ChatMessage]) -> Int {
        if let id = earliestRenderedID, let index = rows.firstIndex(where: { $0.id == id }) {
            return index
        }
        return max(0, rows.count - Self.eagerTailCount)
    }

    /// (Re)latch the seam when it has no valid anchor. Idempotent while the
    /// anchored row exists — appends never move a latched seam (the boundary
    /// must hold still under a reader; only "Show earlier" and reveal
    /// expansion move it, always toward older rows).
    private func latchTailSeam() {
        let rows = visibleMessages
        guard !rows.isEmpty else { return }
        if let id = earliestRenderedID, rows.contains(where: { $0.id == id }) { return }
        earliestRenderedID = rows[max(0, rows.count - Self.eagerTailCount)].id
    }

    /// Mount the previous `earlierChunk` rows above the seam, keeping the
    /// pre-tap seam row where the reader left it: content mounted ABOVE the
    /// viewport otherwise shifts every visible row down by its full height
    /// (the offset is content-top-relative, and the `.sizeChanges` anchor is
    /// nil while scrolled away). The mounted rows are eager, so one layout
    /// pass settles their real heights before the unanimated pin lands.
    /// The transcript's scrolling content.
    ///
    /// Extracted from the `ScrollView` closure at the call site: as one
    /// expression the row builder plus its modifier chain overran the type
    /// checker's budget. Pure move — nothing about the layout changed.
    @ViewBuilder
    private func transcriptContent(_ proxy: ScrollViewProxy) -> some View {
            // Spacing is per-pair like the design app: consecutive messages
            // from the same sender sit close (4pt); a sender change opens a
            // full turn gap (20pt).
            // ONE materialization of the rendered transcript per body eval.
            // `visibleMessages` copies the array while streaming
            // (`Array(messages.dropLast())`), and the per-row helpers below
            // used to re-derive it ~5× per row — ~300 full-array copies per
            // eval on a streaming keyboard ride. Every helper now takes
            // this snapshot instead.
            let rows = visibleMessages
            let newestUserID = rows.last(where: \.isUser)?.id
            let lastRowID = rows.last?.id
            // Near-repeat task cards, folded per message (see taskCardRepeats).
            let taskCardRepeats = ChatPerf.measure("taskCardRepeats", "\(rows.count) msgs") {
                Self.taskCardRepeatsMemoized(in: rows)
            }
            let tailStart = self.tailStart(in: rows)
            // A plain VStack over a BOUNDED tail, not a LazyVStack over
            // the whole history (root-canvas normalization, Phase 2):
            // lazy height ESTIMATES re-measure every animation frame
            // whenever the container resizes — native keyboard delivery
            // resizes it (safe area shrinks layout proposals), which is
            // the "text bounces" artifact. Eager rows have settled
            // heights, so a resize is one cheap re-layout
            // (DeepTaskThreadView's shipped recipe; bubble parses are
            // amortized by warmRenderCaches). Rendered rows never
            // unmount, so `proxy.scrollTo(id)` cannot hit a dropped id
            // inside the window — only above the seam.
            VStack(spacing: 0) {
                // Blank transcript with a fetch in flight: shimmer a
                // bubble-shaped placeholder conversation instead of an empty
                // page. Cached cold starts never hit this (the snapshot
                // paints real messages before the first frame); it covers
                // the first run, an evicted snapshot, and a notification
                // cold-start racing the history load.
                if isLoadingHistory, rows.isEmpty {
                    ChatHistorySkeleton()
                        .transition(.opacity)
                }
                if tailStart > 0 {
                    ChatShowEarlierButton { showEarlier(proxy) }
                }
                ForEach(Array(rows.enumerated())[tailStart...], id: \.element.id) { index, message in
                    // iMessage timestamp rule: a centered "Today 9:41 AM"
                    // separator (bold day-part) after a silence gap or a
                    // day change (see IMessageTimestampRule)
                    // or at the conversation start. When one is shown the
                    // row skips its own turn gap.
                    let separator = timestampLabel(before: index, in: rows)
                    VStack(spacing: 0) {
                        if let separator {
                            IMessageDateSeparator(day: separator.day, time: separator.time)
                                .padding(.top, index == 0 ? 0 : 14)
                                .padding(.bottom, 8)
                        }
                        if message.isSendError {
                            // A failed turn's local-only notice: no bubble, no
                            // menu, no receipts — just the reason and a Retry
                            // that re-runs the send. Gone the moment the user
                            // retries, sends anything new, or reloads.
                            ChatSendErrorRow(
                                text: message.text,
                                // While a queued turn is already streaming,
                                // retrying would interleave two replies —
                                // the button waits the turn out.
                                isRetryEnabled: !isStreaming,
                                onRetry: onRetry
                            )
                            .padding(.top, separator != nil ? 0 : gapAbove(index, in: rows))
                        } else {
                            if let trail = toolTrails[message.id] {
                                ChatWorkedBox(trail: trail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, DS.Spacing.gutter)
                            }
                            ChatRow(
                                message: message,
                                // The one bubble whose text grows token-by-token: the
                                // trailing assistant message while a reply streams.
                                isStreaming: isStreaming && !message.isUser && message.id == messages.last?.id,
                                isLastInGroup: isLastInGroup(index, in: rows),
                                isFlashed: flashedMessageID == message.id,
                                threadPreview: threadPreviewText(for: message),
                                suppressedTaskIds: taskCardRepeats[message.id] ?? [],
                                receipt: receiptLabel(at: index, message, in: rows, newestUserID: newestUserID),
                                hasReceiptSlot: message.isUser && message.id == newestUserID,
                                timestampReveal: timestampReveal,
                                collapse: collapseState(for: message, lastRowID: lastRowID),
                                onToggleCollapse: { toggleCollapse(for: message) },
                                onTapFile: { openFileAttachment(message) },
                                onShareFile: { shareFileAttachment(message) },
                                onReply: onReply.map { reply in { reply(message) } },
                                onReplyToCards: onReply,
                                onOpenThread: { openThread(for: message) },
                                onTapReplyReference: {
                                    switch message.replyTo?.kind {
                                    case let .suggestion(id):
                                        onOpenSuggestion?(id)
                                    case .meeting:
                                        onOpenMeeting?()
                                    default:
                                        jumpToReplySource(of: message, proxy: proxy)
                                    }
                                }
                            )
                            .equatable()
                            .padding(.top, separator != nil ? 0 : gapAbove(index, in: rows))
                            // One geometric unit per row: on
                            // keyboard DISMISS the transcript descends by
                            // ANIMATED LAYOUT (the clearance spacer
                            // shrinking), not by a scroll — geometryGroup
                            // keeps a layout-moved row moving as one rigid
                            // piece instead of animating each subview's
                            // frame independently. (It did NOT fix the
                            // close-side "text detaches from its bubble"
                            // artifact — that was the outgoing fill's
                            // positional visualEffect rendering at
                            // model-final geometry, fixed in
                            // IMessageBubblePalette.outgoingFill.)
                            .geometryGroup()
                        }
                    }
                }
                if showsLoadingIndicator(in: rows) {
                    HStack {
                        ChatLoadingIndicator(label: liveStatus?.label ?? "Thinking", icon: liveStatus)
                        Spacer(minLength: 0)
                    }
                    // The shimmer stands in for the assistant's next
                    // element, so it keeps the transcript's rhythm: a
                    // 20pt turn gap under the user's message it answers,
                    // a 4pt run gap when a tool status shows under
                    // assistant content already on screen (with the same
                    // bare-chip clearance a real follow-up row gets).
                    .padding(.top, loadingIndicatorGap(in: rows))
                    .transition(.opacity)
                }
                // Bottom clearance lives ABOVE the scroll anchor so scrolling to
                // it keeps the last message (and its thread chip) above the
                // composer. Bar chrome only — the keyboard's share of the
                // inset is the SYSTEM safe-area inset now, which
                // the ScrollView absorbs natively; this spacer never
                // animates. While typing, the bar sits 28pt lower relative
                // to the keyboard than it does to the physical bottom at
                // rest (8pt keyboard gap vs 36pt rest gap — the bar's
                // altitudes), so shave that delta off the clearance — the
                // last message keeps the SAME visual gap above the bar in
                // both states instead of floating 28pt higher ("messages
                // too high above" report).
                Color.clear
                    .frame(height: bottomClearance)
                bottomMarker
            }
            .padding(.horizontal, DS.Spacing.gutter)
            // chatTranscriptTopInset, not contentTopInset: a tall card
            // scrolled to the transcript top must land its header row
            // clear of the floating chrome (see PersonaLayout).
            .padding(.top, PersonaLayout.chatTranscriptTopInset + extraTopInset)
            .id(transcriptRebuildTick)
            // Timestamp reveal, design-app semantics (ChatViews.swift): a
            // LEFT swipe anywhere on the transcript slides all bubbles over
            // and fades each message's time in; release springs back. It's a
            // UIKit pan on the transcript's scroll view (leftward-only, so
            // every rightward swipe stays with the Home⇄Chat pager) because
            // SwiftUI drag gestures here would starve the pager's pan.
            #if canImport(UIKit)
                .overlay { transcriptGestureLayer }
            #endif
    }

    /// The jump-to-latest chevron that floats over the transcript's bottom
    /// right once the reader has scrolled away from the newest message.
    ///
    /// Extracted from the `.overlay` at the call site to keep the scroll
    /// view's modifier chain inside the type checker's budget. Pure move.
    @ViewBuilder
    private func jumpToLatestOverlay(_ proxy: ScrollViewProxy) -> some View {
            if scrolledAwayFromBottom {
                Button {
                    guard DSInteractionGate.allowsTap else { return }
                    scrollToBottom(proxy, animated: true)
                } label: {
                    // Glass + hit shape live INSIDE the label so the whole
                    // circle is tappable, not just the chevron glyph — and
                    // an invisible 10pt halo pads the 40pt visual out to a
                    // finger-sized target (its soft shadow reads bigger
                    // than the circle, so rim-adjacent taps must land too).
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Palette.ink.opacity(0.55))
                        .frame(width: 40, height: 40)
                        .smallGlassCircle()
                        // Messages that arrived while reading history,
                        // iMessage-red, pinned to the circle's top-right
                        // corner (inside the halo so it hugs the visual).
                        .overlay(alignment: .topTrailing) {
                            if unseenWhileAway > 0 {
                                Text("\(unseenWhileAway)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .frame(minWidth: 17, minHeight: 17)
                                    .background(Color(hex: 0xFF3B30), in: Capsule())
                                    .offset(x: 5, y: -5)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(10)
                        .contentShape(Circle())
                }
                .buttonStyle(.hapticTap)
                // The count is derived (no state write to animate), so bind
                // the pop-in/tick animation to its value here.
                .animation(.snappy(duration: 0.18), value: unseenWhileAway)
                // Hover just above the composer on the right edge (the
                // Telegram/WhatsApp corner); ride the keyboard lift. The
                // paddings shave the halo's 10pt so the VISUAL circle keeps
                // the approved position. While typing, the composer sits
                // 28pt lower relative to the keyboard than it does to the
                // physical bottom at rest (8pt keyboard gap vs 36pt rest
                // gap) — shave that too, so the chevron keeps the SAME
                // visual gap above the bar in both states (mirrors the
                // transcript clearance above).
                .padding(.trailing, DS.Spacing.gutter - 10)
                // Distance above the bar, both states, every mount (the
                // overlay surfaces' long-standing pair — the main mount
                // joined their geometry at the Phase 2 flip): typing
                // −28 mirrors the clearance trim; at rest the mount's
                // own static inset is absorbed so the visual gap holds.
                .padding(
                    .bottom,
                    PersonaLayout.contentBottomInset
                        + (keyboardInWindow ? -28 : -nativeBottomInset)
                        - 10 + 8 + extraBottomInset
                )
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                .accessibilityLabel(
                    unseenWhileAway > 0
                        ? "Scroll to latest, \(unseenWhileAway) new"
                        : "Scroll to latest"
                )
            }
    }

    private func showEarlier(_ proxy: ScrollViewProxy) {
        let rows = visibleMessages
        let start = tailStart
        guard start > 0 else { return }
        let seamID = rows[start].id
        earliestRenderedID = rows[max(0, start - Self.earlierChunk)].id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            proxy.scrollTo(seamID, anchor: .top)
        }
    }

    /// A reveal target above the seam must be RENDERED before `scrollTo` can
    /// land (an unmounted id no-ops silently). Expands the window to a couple
    /// of rows above the target; returns whether it did — the caller then
    /// waits one layout pass before the glide.
    private func ensureRendered(_ id: UUID) -> Bool {
        let rows = visibleMessages
        guard let index = rows.firstIndex(where: { $0.id == id }), index < tailStart else { return false }
        earliestRenderedID = rows[max(0, index - 2)].id
        return true
    }

    /// The end-of-content marker: the transcript's scroll anchor, and the ground
    /// truth for "is the reader at the bottom" (see `bottomMarkerVisibilityChanged`).
    private var bottomMarker: some View {
        Color.clear
            .frame(height: 1)
            .id(Self.bottomID)
            .onScrollVisibilityChange(threshold: 0.01, bottomMarkerVisibilityChanged)
    }

    /// The end-of-content marker came on/off screen. Its visibility is the only
    /// unambiguous answer to "is the reader at the bottom" — which is what
    /// `scrolledAwayFromBottom` is supposed to encode, but that flag is a LATCH fed
    /// by scroll-geometry samples, and no sample reliably arrives after a
    /// PROGRAMMATIC pin (the notification route pins the transcript, then the new
    /// messages land). So the latch can sit at `true` over a transcript resting at
    /// the bottom: the chevron strands there, and its badge keeps counting every
    /// message that arrives after the anchor it froze. Seeing this marker means we
    /// are at the bottom, so retire both. Clear-only by construction — a reader
    /// genuinely parked up in history never sees this marker, so this can never take
    /// away the chevron that is their way back.
    private func bottomMarkerVisibilityChanged(_ visible: Bool) {
        guard visible, scrolledAwayFromBottom || lastSeenOnScrollUp != nil else { return }
        withAnimation(.snappy(duration: 0.22)) { scrolledAwayFromBottom = false }
        lastSeenOnScrollUp = nil
    }

    /// Pin to the latest message — via `proxy.scrollTo(bottomMarker)`, the
    /// mechanism DeepTaskThreadView ships on. One path for EVERY depth
    /// (Phase 2 mount flip): the bounded eager tail never unmounts a
    /// rendered row, so the bottom marker is always materialized and the
    /// ID-targeted pin cannot hit a dropped id — which retires the UIKit
    /// content-edge deep jump (TranscriptHealView.jumpNote) that existed
    /// for the lazy stack's dropped-row no-ops (L7). `settle` adds a
    /// corrective pin after rows finish measuring; streaming skips it for
    /// an immediate, jank-free pin.
    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool, settle: Bool = true) {
        Task { @MainActor in
            if settle { try? await Task.sleep(for: .milliseconds(60)) }
            // A top-filled short conversation reads top-DOWN: leave it be (a
            // bottom pin on undersized content is a no-op anyway, and the
            // .alignment anchor owns that placement). The regime reads live
            // geometry (`contentOverflows`, keyboard included, seeded TRUE):
            // the char-count heuristic called a two-screen card deck "short"
            // and sent this pin to the TOP, burying the newest cards under
            // the keyboard ().
            guard contentOverflows else { return }
            if animated {
                withAnimation(.easeInOut(duration: 0.28)) {
                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                }
                // A long jump from deep history re-measures lazy rows (image /
                // card bubbles) while the glide is in flight, and a
                // `proxy.scrollTo(id)` computes its offset from ESTIMATED
                // heights — the chevron's jump landed visibly short of the
                // bottom, or apparently nowhere at all when the estimate
                // error swallowed the whole glide (parity report,
                //). Staged correctives converge it: each pin
                // re-targets against the heights the previous move forced to
                // measure. No-ops once landed; a finger taking over wins.
                for delay in [340, 700, 1200] {
                    try? await Task.sleep(for: .milliseconds(delay))
                    if isUserScrolling { break }
                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
                // The settle-flavored instant pin serves inset/padding changes
                // whose height ANIMATES (the keyboard clearance ride): a pin
                // taken mid-animation lands short by whatever growth hadn't
                // landed yet. One corrective after the curve completes makes
                // the gap exact for every bubble size — a no-op when the
                // first pin already landed, skipped if a finger took over.
                if settle {
                    try? await Task.sleep(for: .milliseconds(420))
                    if !isUserScrolling {
                        proxy.scrollTo(Self.bottomID, anchor: .bottom)
                    }
                }
            }
        }
    }

    /// Long-history cap: a message past the length threshold renders collapsed
    /// ("Read more") — EXCEPT the transcript's last message, so a long reply
    /// that just streamed in (or a long text just sent) never truncates itself
    /// mid-read; it collapses once the conversation moves past it. Voice
    /// bubbles are exempt: their text is the transcription, rendered outside
    /// the bubble.
    private func collapseState(for message: ChatMessage, lastRowID: UUID?) -> ChatBubbleCollapse {
        guard message.id != lastRowID,
              !message.isVoiceMessage,
              Self.needsCollapseMemoized(message)
        else { return .none }
        return .collapsed
    }

    /// Per-message memo over `ChatBubbleContent.needsCollapse` — the body asks
    /// for every rendered row on EVERY re-eval (keyboard frames, streaming
    /// ticks), and the newline scan is O(text). Keyed by id + UTF-8 length:
    /// a message's text only ever changes by streaming appends, which change
    /// the length (`utf8.count` is O(1) on native strings).
    @MainActor
    private enum CollapseMemo {
        static var cache: [UUID: (utf8Count: Int, needs: Bool)] = [:]
    }

    private static func needsCollapseMemoized(_ message: ChatMessage) -> Bool {
        let count = message.text.utf8.count
        if let hit = CollapseMemo.cache[message.id], hit.utf8Count == count { return hit.needs }
        // Ids churn across thread switches over a long session — reset rather
        // than grow forever (recomputing the 60 rendered rows once is cheap).
        if CollapseMemo.cache.count > 4096 { CollapseMemo.cache.removeAll(keepingCapacity: true) }
        let needs = ChatBubbleContent.needsCollapse(message.text)
        CollapseMemo.cache[message.id] = (count, needs)
        return needs
    }

    private func toggleCollapse(for message: ChatMessage) {
        // ALWAYS the reader, never inline: even a couple-screens bubble
        // expanded inside the LazyVStack re-layouts and composites whole on
        // every scroll frame, and the transcript visibly chugs.
        readerMessage = message
    }

    /// Tapping a user-attached document tile opens its content: pasted text in
    /// the full-screen reader (it IS a message the user wrote — read it like
    /// one), any other document in QuickLook. Fresh sends open from the bytes
    /// still in memory; reloaded bubbles fetch the persisted asset.
    private func openFileAttachment(_ message: ChatMessage) {
        guard let filename = message.fileAttachmentName else { return }
        DSHaptics.tap(.light)
        if filename == ChatMessage.pastedAttachmentName {
            if let data = message.fileAttachmentData {
                presentPastedText(data, from: message)
            } else if let path = message.fileAttachmentPath {
                Task {
                    guard let data = try? await settings?.apiClient.data(path) else { return }
                    presentPastedText(data, from: message)
                }
            }
        } else if let data = message.fileAttachmentData {
            fileQuickLookURL = Self.tempFileURL(for: filename, data: data)
        } else if let path = message.fileAttachmentPath {
            Task {
                guard let data = try? await settings?.apiClient.data(path) else { return }
                fileQuickLookURL = Self.tempFileURL(for: filename, data: data)
            }
        }
    }

    /// Long-press Share on the document tile: the native share sheet — the
    /// download path for a file on iOS (Save to Files, AirDrop, another app).
    /// Pasted text shares as text; real documents as a temp file that keeps
    /// the filename, fetched exactly like the QuickLook tap above.
    private func shareFileAttachment(_ message: ChatMessage) {
        guard let filename = message.fileAttachmentName else { return }
        DSHaptics.tap(.light)
        let present: (Data) -> Void = { data in
            if filename == ChatMessage.pastedAttachmentName {
                guard let text = String(bytes: data, encoding: .utf8), !text.isEmpty else { return }
                ChatMediaActions.presentShareSheet([text])
            } else if let url = Self.tempFileURL(for: filename, data: data) {
                ChatMediaActions.presentShareSheet([url])
            }
        }
        if let data = message.fileAttachmentData {
            present(data)
        } else if let path = message.fileAttachmentPath {
            Task {
                guard let data = try? await settings?.apiClient.data(path) else { return }
                present(data)
            }
        }
    }

    private func presentPastedText(_ data: Data, from message: ChatMessage) {
        let text = String(decoding: data, as: UTF8.self)
        guard !text.isEmpty else { return }
        readerMessage = ChatMessage(text: text, isUser: true, time: message.time, date: message.date)
    }

    /// Write the attachment bytes to a temp file that keeps the real filename
    /// (QuickLook titles + Share-sheet export), namespaced to avoid collisions
    /// — FileCardView's convention. Internal: the composer's staged-attachment
    /// preview (PersonaRootView) hands QuickLook files the same way.
    static func tempFileURL(for filename: String, data: Data) -> URL? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("user-attachments", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(filename.isEmpty ? "file" : filename)
        do {
            try data.write(to: dest, options: .atomic)
            return dest
        } catch {
            return nil
        }
    }

    /// Tapping a reply's "Replying to …" line: glide the transcript to the
    /// quoted message and pulse it on arrival. The source id resolves the
    /// target directly; a text match covers references without one.
    private func jumpToReplySource(of message: ChatMessage, proxy: ScrollViewProxy) {
        guard let replyTo = message.replyTo else { return }
        let candidates = visibleMessages
        let target = candidates.first { $0.id == replyTo.sourceID }
            ?? candidates.last { $0.id != message.id && $0.isUser == replyTo.isUser && $0.text == replyTo.text }
        guard let target else { return }
        DSHaptics.tap(.light)
        reveal(target.id, proxy: proxy)
    }

    /// A tapped notification's exact-bubble landing: resolve `revealMessageID`
    /// against the loaded transcript; a hit consumes the pending id and glides
    /// there. A miss keeps waiting — the count onChange retries as history
    /// loads, and the shell's timeout falls back to the bottom.
    private func attemptNotificationReveal(_ proxy: ScrollViewProxy) {
        guard let id = revealMessageID,
              visibleMessages.contains(where: { $0.id == id }) else { return }
        onRevealConsumed?()
        reveal(id, proxy: proxy)
    }

    /// Shared scroll-to-center + pulse (reply-quote jumps and notification
    /// reveals land identically). A target above the pagination seam mounts
    /// its window slab first, then glides one layout pass later.
    private func reveal(_ id: UUID, proxy: ScrollViewProxy) {
        if ensureRendered(id) {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                glideAndFlash(id, proxy: proxy)
            }
        } else {
            glideAndFlash(id, proxy: proxy)
        }
    }

    private func glideAndFlash(_ id: UUID, proxy: ScrollViewProxy) {
        // Windowed so the glide's own geometry crossings can arm the
        // jump-to-latest chevron (see revealJumpInFlight) — cleared once the
        // scroll has certainly settled.
        revealJumpInFlight = true
        withAnimation(.smooth(duration: 0.45, extraBounce: 0)) {
            proxy.scrollTo(id, anchor: .center)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(430))
            withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) { flashedMessageID = id }
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.easeOut(duration: 0.3)) { flashedMessageID = nil }
            revealJumpInFlight = false
        }
    }

    /// Design-app message rhythm: 20pt between turns, 4pt within a sender run.
    /// Inline cards are bubble-styled app-messages, so they keep the SAME
    /// rhythm as text bubbles — a reminder fire or a places card sits exactly
    /// as far from its neighbours as a burst-split text message does.
    /// Indexes into the body's `rows` snapshot — the array the transcript
    /// renders (`visibleMessages`, materialized once per body eval).
    private func gapAbove(_ index: Int, in messages: [ChatMessage]) -> CGFloat {
        guard index > 0 else { return 0 }
        let previous = messages[index - 1]
        // A reminder fire is an interruption, not part of the running
        // conversation: the card, its companion nudge, and the first message
        // after them each open with the timestamp-separator's full break
        // instead of the run
        // rhythm.
        if reminderBreakApplies(at: index, in: messages) { return Self.reminderBreakGap }
        let base = ChatBubbleGrouping.gapAbove(
            previousIsUser: previous.isUser, currentIsUser: messages[index].isUser
        )
        // The one exception: a row whose BOTTOM element is a bare floating
        // chip (status/mail capsules on a textless row, thread-preview chips
        // under the bubble). The chip hangs 4pt under its own bubble,
        // so a 4pt follow-up gap would visually glue it to the NEXT message.
        return endsInBareChip(previous) ? max(base, 14) : base
    }

    /// The timestamp separator's WHITESPACE (14 above the label + 8 below) —
    /// not its edge-to-edge distance: the label fills the middle there, so
    /// matching the full 35pt with empty air read bigger than the 6-hour
    /// break it's meant to echo.
    private static let reminderBreakGap: CGFloat = 22

    /// True when `messages[index]` sits on a reminder-group boundary: it IS
    /// the reminder-card message, it FOLLOWS one (the companion nudge), or it
    /// is the first message after that nudge.
    private func reminderBreakApplies(at index: Int, in messages: [ChatMessage]) -> Bool {
        if carriesReminderCard(messages[index]) || carriesReminderCard(messages[index - 1]) {
            return true
        }
        // After the nudge: the assistant bubble directly under the card closes
        // the group, so the next row re-opens normal conversation with the
        // same break above it.
        return index >= 2 && carriesReminderCard(messages[index - 2]) && !messages[index - 1].isUser
    }

    private func carriesReminderCard(_ message: ChatMessage) -> Bool {
        message.cards.contains { if case .reminder = $0 { true } else { false } }
    }

    /// The loading row's gap above — the same rhythm a real assistant row
    /// would get in its place (see gapAbove).
    private func loadingIndicatorGap(in rows: [ChatMessage]) -> CGFloat {
        guard let last = rows.last else { return 0 }
        if last.isUser { return ChatBubbleGrouping.runGap }
        return endsInBareChip(last) ? 14 : ChatBubbleGrouping.intraRunGap
    }

    /// Whether a row's bottom-most rendered element is a bare chip rather
    /// than a bubble-shaped surface (text bubble, bubble-styled card, photo
    /// tile). Mirrors ChatRow's layout order: below-text cards close the row
    /// when present; otherwise the text bubble / assistant photo tiles;
    /// otherwise the above-text cards (a cards-only message). Thread-preview
    /// chips hang under everything. (A finished deep-task's reference renders
    /// as a bubble-styled delegation card now, so it's NOT a bare chip.)
    private func endsInBareChip(_ message: ChatMessage) -> Bool {
        if threadPreviewText(for: message) != nil { return true }
        if let lastBelow = message.cards.last(where: \.rendersBelowText) {
            return lastBelow.rendersAsChip
        }
        if !message.text.isEmpty || message.isVoiceMessage { return false }
        if !message.isUser, message.imageData != nil || !message.imageRemotePaths.isEmpty { return false }
        if let lastAbove = message.cards.last(where: { !$0.rendersBelowText }) {
            return lastAbove.rendersAsChip
        }
        return false
    }

    /// The iMessage-style separator to show above `messages[index]`, or nil.
    /// Shown before the first dated message, after a silence gap, and on a
    /// calendar-day change from the previous DATED message. Messages without
    /// a real `date` (e.g. a live bubble that hasn't round-tripped) never
    /// trigger a separator and don't reset the clock — a dateless transcript
    /// is simply separator-free (no crash, no "1970").
    private func timestampLabel(before index: Int, in messages: [ChatMessage]) -> (day: String, time: String)? {
        guard let date = messages[index].date else { return nil }
        var previous: Date?
        var scan = index - 1
        while scan >= 0 {
            if let earlier = messages[scan].date {
                previous = earlier
                break
            }
            scan -= 1
        }
        return IMessageTimestampRule.label(for: date, previous: previous)
    }

    /// Tail ownership: the last bubble of a same-sender run carries the tail.
    /// A run ends on a sender change, a timestamp separator, a quiet gap of
    /// more than 5 minutes, or the end of the transcript. The gap rule covers
    /// silences too short for the 30-minute separator: two messages that far
    /// apart read as separate moments, so each closes its own run. A dateless
    /// side never breaks the run — a live bubble mid-round-trip belongs to it.
    private static let tailGap: TimeInterval = 5 * 60

    private func isLastInGroup(_ index: Int, in messages: [ChatMessage]) -> Bool {
        guard index < messages.count - 1 else { return true }
        if messages[index + 1].isUser != messages[index].isUser { return true }
        if timestampLabel(before: index + 1, in: messages) != nil { return true }
        guard let sent = messages[index].date, let next = messages[index + 1].date else { return false }
        return next.timeIntervalSince(sent) > Self.tailGap
    }

    private func threadPreviewText(for message: ChatMessage) -> String? {
        guard let threadID = message.threadID else { return nil }
        return threadPreview?(threadID)
    }

    /// The iMessage receipt line — only under the NEWEST user message. "Read
    /// <time>" from the live receipt (or, on reload, derived from any assistant
    /// message with content that follows — a reply proves the read); else
    /// "Delivered" once the backend confirmed persistence; nothing while a
    /// fresh send is still on the wire.
    /// Same "h:mm a" wall-clock label the bubbles use (ChatTime lives in
    /// PersonaService, which this UI module doesn't import).
    private static let receiptTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private func receiptLabel(
        at index: Int, _ message: ChatMessage, in messages: [ChatMessage], newestUserID: UUID?
    ) -> String? {
        guard message.isUser, message.id == newestUserID else { return nil }
        if let readAt = message.readAt {
            return "Read \(Self.receiptTime.string(from: readAt))"
        }
        if let reply = messages[(index + 1)...].first(where: { !$0.isUser && hasSaidSomething($0) }) {
            return reply.date.map { "Read \(Self.receiptTime.string(from: $0))" } ?? "Read"
        }
        // iMessage semantics: the persona is IN the chat, so the first visible
        // state is "Read" (a beat after delivery). "Delivered" surfaces only
        // when something is actually broken — the turn ENDED with the message
        // delivered but never read (backend took it, no model consumed it).
        return message.deliveredAt != nil && !isStreaming ? "Delivered" : nil
    }

    private func openThread(for message: ChatMessage) {
        guard let threadID = message.threadID else { return }
        onThreadSelected?(threadID)
    }
}

/// The pagination seam's affordance: history above the eager tail mounts in
/// `earlierChunk` slabs on demand. Quiet transcript chrome in the capsule
/// family (the retry chip's recipe), never a message.
private struct ChatShowEarlierButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            guard DSInteractionGate.allowsTap else { return }
            action()
            DSHaptics.tap(.light)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Palette.inkSoft)
                Text("Show earlier messages")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Palette.ink)
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .incomingBubblePlate(in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 18)
        .accessibilityIdentifier("chat-show-earlier")
    }
}

// MARK: - Row (bubble + long-press menu + left-swipe timestamp)

/// THE shared transcript row — one message rendered with the full chat
/// treatment: reply label, photo tiles (+ fullscreen viewer), card stacks with
/// bubble-side tails, voice transcription, long-press Copy/Reply menu,
/// left-swipe timestamp reveal, "Read more" collapse. The main chat AND the
/// task thread both render conversation messages through this row, so a new
/// message element (places, pictures, …) lands on every chat surface at once —
/// don't rebuild a private copy per page.
/// The failed-turn notice: sits where Iris's reply would have been, styled as
/// quiet system chrome rather than a message — the same 14pt warm-muted phrase
/// the loading row uses, a small warning glyph, and a Retry chip in the
/// transcript's capsule family (mail chips). Local-only; the store drops it on
/// retry, on the next send, and on any reload. Shared: every chat surface that
/// can fail a send shows THIS row (main chat, lightweight thread via
/// ChatScreen, the suggestion sheet directly) — never a silent drop.
struct ChatSendErrorRow: View {
    let text: String
    /// False while another turn is streaming — retrying mid-turn would
    /// interleave two replies, so the chip waits it out.
    var isRetryEnabled = true
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange.opacity(0.85))
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .tracking(-0.14)
                .foregroundStyle(DS.Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let onRetry {
                retryChip(onRetry)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Message failed. \(text)"))
    }

    /// Same capsule recipe as the transcript's mail chips (ChatCardView):
    /// 26pt white-plate capsule (the ThreadPreviewChip family), tap haptic.
    private func retryChip(_ action: @escaping () -> Void) -> some View {
        let shape = Capsule(style: .continuous)
        return Button {
            guard DSInteractionGate.allowsTap else { return }
            action()
            DSHaptics.tap()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Palette.inkSoft)
                Text("Retry")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Palette.ink)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .incomingBubblePlate(in: shape)
        }
        .buttonStyle(.plain)
        .disabled(!isRetryEnabled)
        .opacity(isRetryEnabled ? 1 : 0.45)
        // The chip hangs off the phrase's baseline row; without this it would
        // stretch the line height when the message wraps.
        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
    }
}

struct ChatRow: View, Equatable {
    // Gate re-renders on the VALUE inputs; the closures are recreated on every
    // parent eval but behaviorally identical (they call through to ChatScreen
    // with the captured message). Without this every visible row re-runs its
    // body — bubble render included — on every streamed token of an unrelated
    // reply. (@Environment changes still invalidate through their own
    // dependency tracking; the gate only stops parent-driven re-evaluation.)
    nonisolated static func == (lhs: ChatRow, rhs: ChatRow) -> Bool {
        lhs.message == rhs.message
            && lhs.isStreaming == rhs.isStreaming
            && lhs.isLastInGroup == rhs.isLastInGroup
            && lhs.isFlashed == rhs.isFlashed
            && lhs.threadPreview == rhs.threadPreview
            && lhs.suppressedTaskIds == rhs.suppressedTaskIds
            && lhs.receipt == rhs.receipt
            && lhs.hasReceiptSlot == rhs.hasReceiptSlot
            && lhs.timestampReveal === rhs.timestampReveal
            && lhs.collapse == rhs.collapse
    }

    @Environment(\.capabilities) private var capabilities
    let message: ChatMessage
    /// True only for the trailing assistant bubble while its reply streams — lets
    /// the bubble skip the O(n²) whole-text markdown re-parse per token.
    var isStreaming = false
    /// The last bubble of a same-sender run carries the iMessage tail.
    var isLastInGroup = true
    /// Pulses the bubble after a "Replying to" jump lands on this message.
    let isFlashed: Bool
    let threadPreview: String?
    /// Task ids whose card on THIS message duplicates one the transcript
    /// already shows a few rows up (ChatScreen.taskCardRepeats) — the row
    /// folds those away instead of stacking identical task cards.
    var suppressedTaskIds: Set<String> = []
    /// The iMessage receipt line ("Delivered" / "Read 5:12 PM") — non-nil only
    /// on the newest user message; nil everywhere else.
    var receipt: String? = nil
    /// True on the newest user message: the receipt SLOT renders (space always
    /// reserved) even while `receipt` is still nil, so the line's arrival is a
    /// pure fade with zero layout shift.
    var hasReceiptSlot = false
    /// Shared reveal state, driven by the transcript-level UIKit pan. The row
    /// only passes the box to its leaf reveal modifier — never reads it — so
    /// the drag's per-frame writes bypass this body entirely (one stable
    /// instance per screen; identity-compared in `==`).
    let timestampReveal: ChatTimestampRevealModel
    /// Long-history cap state for this bubble (see ChatBubbleCollapse).
    var collapse: ChatBubbleCollapse = .none
    var onToggleCollapse: () -> Void = {}
    /// Tap on the user-attached document tile — opens the content (pasted
    /// text in the reader, picked docs in QuickLook; ChatScreen resolves it).
    var onTapFile: () -> Void = {}
    /// Long-press Share on that tile — the native share sheet with the
    /// document as a real named file (ChatScreen fetches the bytes). Nil
    /// hides the item (preview rigs, surfaces without an API client).
    var onShareFile: (() -> Void)?
    /// Nil where the surface can't start a reply (history threads): the
    /// context menu then shows Copy alone.
    let onReply: (() -> Void)?
    /// Reply wiring for the row's CARD stacks: called with a card-only proxy
    /// of this message, so the armed reply quotes the held component itself —
    /// not whatever text rides the same turn. Nil falls back to `onReply`
    /// (whole-message reply).
    var onReplyToCards: ((ChatMessage) -> Void)? = nil
    let onOpenThread: () -> Void
    let onTapReplyReference: () -> Void

    /// A tapped photo tile — drives the fullscreen zoom/reply viewer.
    @State private var photoViewer: PhotoViewerTarget?
    /// Which of a multi-photo deck's photos sits on top (the swipe-to-flip
    /// scrub) — tap-to-open and the zoom transition follow it.
    @State private var deckTopIndex = 0
    @Namespace private var photoZoom

    /// Which visual element carries the iMessage tail: the BOTTOM-MOST
    /// bubble-like element of a last-in-group message (below-cards > text
    /// bubble > above-cards > image). Exactly one tail per sender run — a
    /// card mid-run stays tailless just like a mid-run text bubble.
    private var tailOwner: TailOwner {
        guard isLastInGroup else { return .none }
        // Only a stack with a BUBBLED card can wear the tail. A chip-only
        // stack (the settled task receipt) can't — the run's tail stays on
        // the text bubble and the receipt hugs it (design; before
        // this, a run ending in a settled chip lost its tail entirely).
        if cardsBelowText.contains(where: { !$0.rendersAsChip }) { return .cardsBelow }
        // Assistant photos render BELOW the text (see body), so when present
        // they are the bottom-most element and carry the tail.
        if !message.isUser, hasImages { return .image }
        if showsBubble { return .bubble }
        if cardsAboveText.contains(where: { !$0.rendersAsChip }) { return .cardsAbove }
        if hasUserFile { return .file }
        if hasImages { return .image }
        return .none
    }

    private var hasImages: Bool {
        message.imageData != nil || !message.imageRemotePaths.isEmpty
    }

    /// A document the user attached to this message (picked file or an
    /// oversized paste folded into a "Pasted" attachment) — renders as its own
    /// tile, so a file-only send is never an invisible turn.
    private var hasUserFile: Bool {
        message.isUser && message.fileAttachmentName != nil
    }

    private enum TailOwner { case none, image, file, cardsAbove, bubble, cardsBelow }

    /// How far a chip-only below-stack (the settled task receipt) pulls up to
    /// hug the bubble BODY: -6 eats the slack of the chip's 32pt tap frame
    /// around ~16pt of content (the reminder-actions pull). Under the run's
    /// tail most — not all — of the dip comes out too: the gap reads from
    /// the bubble body, but the receipt still clears the tail's tip by a
    /// couple of points instead of touching it.
    private var chipStackHug: CGFloat {
        guard showsBubble, cardsBelowText.allSatisfy(\.rendersAsChip) else { return 0 }
        return tailOwner == .bubble ? -9 : -6
    }

    private var side: IMessageBubbleShape.Side { message.isUser ? .outgoing : .incoming }

    private var renderableCards: [ChatCard] {
        // DELEGATION is the exception that renders NOWHERE from a message's own
        // payload. A live task now rides the composer's tray (`ChatTaskTray`)
        // instead of a card pinned to the message that spawned it; what comes
        // back to the transcript is the completion message the backend posts,
        // with the settled task card under it (synthesized from
        // `taskReferenceId` in `cardsBelowText` — that one still draws). The
        // hand-off card stays in the payload — history, seeding DeepTaskStore
        // (PersonaRootView.delegatedTasks) and the per-taskId dedupe all still
        // depend on it — it just doesn't draw.
        var cards = productCards.filter { card in
            if case .delegation = card { return false }
            return true
        }
        // A near-repeat task card (same task shown a few rows up) folds away —
        // the earlier card is live and upgrades in place, so a second copy is
        // pure noise (ChatScreen.taskCardRepeats).
        if !suppressedTaskIds.isEmpty {
            cards = cards.filter { card in
                guard case let .delegation(taskId, _, _) = card else { return true }
                return !suppressedTaskIds.contains(taskId)
            }
        }
        // An embedded reminder card renders as part of the text bubble's turn
        // (see embeddedReminderCard) — never as a second bubble too.
        if embeddedReminderCard != nil {
            cards = cards.filter { card in
                if case .reminder(_, _, _, _, true) = card { return false }
                return true
            }
        }
        // A SET-confirmation turn folds its scheduled card away entirely —
        // the "Reminder set" kicker above the prose is the whole receipt
        //. The prose-less fallback keeps the bare
        // standalone line.
        if hasScheduledReminderTurn {
            cards = cards.filter { card in
                if case let .reminder(_, _, status, _, _) = card, status == "scheduled" { return false }
                return true
            }
        }
        return cards
    }

    /// The set-confirmation turn: assistant prose carrying a freshly
    /// scheduled reminder's card. Wears the "Reminder set" kicker; the card
    /// itself never draws (changes go through chat).
    private var hasScheduledReminderTurn: Bool {
        guard !message.isUser, !message.text.isEmpty else { return false }
        return productCards.contains { card in
            if case let .reminder(_, _, status, _, _) = card { return status == "scheduled" }
            return false
        }
    }

    /// A reminder delivery's card (initial fire or escalation nudge), folded
    /// into the text bubble's TURN: a small "Reminder" kicker above the
    /// bubble, the delivery prose as the bubble, and the card collapsed to
    /// bare Snooze/Done actions hanging under it. Nil on every other row —
    /// including the (defensive) prose-less delivery, which falls back to the
    /// standalone full card.
    private var embeddedReminderCard: ChatCard? {
        guard !message.isUser, !message.text.isEmpty else { return nil }
        return productCards.first { card in
            if case .reminder(_, _, _, _, true) = card { return true }
            return false
        }
    }

    /// The "task started" hand-off turn: the assistant's confirmation prose
    /// with the delegation card in its payload. Wears the tappable "Started a
    /// background task ›" kicker above the bubble (same rail as the reminder
    /// kicker). Completion turns are excluded — they reference the task via
    /// `taskReferenceId` (and may re-carry the card inline), but the task
    /// started rows earlier, so the kicker would be a lie there.
    private var agentHandoffTaskId: String? {
        guard !message.isUser, !message.text.isEmpty, message.taskReferenceId == nil else { return nil }
        for card in productCards {
            if case let .delegation(taskId, _, _) = card { return taskId }
        }
        return nil
    }

    /// Cards this product renders: everything with the chatCards capability;
    /// mail chips (the production mail surface), delegation cards (the "task
    /// started" hand-off, which needs its tappable open-the-task affordance in
    /// chat) and reminder cards (Snooze/Done act on the reminder — without the
    /// card a fired reminder is unactionable) always survive, even on lean
    /// where other inline cards are dev-only.
    private var productCards: [ChatCard] {
        capabilities.chatCards
            ? message.cards
            : message.cards.filter {
                switch $0 {
                // Always survive on lean: the FUNCTIONAL / tap-to-act cards. Mail
                // chips, the task hand-off and reminders (existing) — PLUS the
                // agentic-commerce action cards (payment / checkout / confirm),
                // connect and live-call. Without these the user can't complete the
                // action the agent just set up (pay for the DoorDash order, confirm
                // a checkout, link an integration) — the whole point of the product
                // on the prod app. Only the decorative RESULT cards
                // (collection / profile / agenda / gallery / places …) stay dev-only.
                // Delivered files are functional too: the completion message says
                // "your PDF is ready" and the card IS the hand-off — dropping it
                // on lean left prod users a claim with nothing to tap.
                // The displayed email card is functional, not decorative: it IS
                // the answer to "pull up that email" — dropping it on lean
                // leaves a bare "here it is" with nothing to tap.
                case .mailRef, .email, .delegation, .reminder,
                     .payment, .doordashPayment, .agentcardPayment, .soarBookingPayment,
                     .amazonOrderConfirm, .uberEatsCheckout, .uberRideConfirm, .lyftRideConfirm,
                     .lyftRideOptions, .connect, .voiceCall, .file:
                    true
                default:
                    false
                }
            }
    }

    /// Owner rule: custom cards render ABOVE the assistant's text by default (the
    /// card is the substance). The exception — confirmation-gated action-concluders
    /// (payment/checkout confirms, approve/deny) — stays BELOW, so the text's
    /// consequence is read before the commit control. `rendersBelowText` (on
    /// ChatCard) is the single, documented source of that split. The two groups
    /// partition `renderableCards`, so no card renders twice.
    private var cardsAboveText: [ChatCard] { renderableCards.filter { !$0.rendersBelowText } }
    private var cardsBelowText: [ChatCard] {
        var cards = renderableCards.filter(\.rendersBelowText)
        // A finished deep-task's result links back to its activity thread with
        // the SAME live delegation card its hand-off rendered — ONE task-card
        // design app-wide (the old compact reference pill is gone; design,
        //). Below the text like the pill was: the result text is the
        // substance, the card its footer. Skipped when the card would repeat
        // one shown just above, or the message already carries it inline.
        if capabilities.deepTasks,
           let taskId = message.taskReferenceId,
           !suppressedTaskIds.contains(taskId),
           !renderableCards.contains(where: { card in
               guard case let .delegation(id, _, _) = card else { return false }
               return id == taskId
           }) {
            cards.append(.delegation(taskId: taskId, goal: "Agent", status: "succeeded"))
        }
        return cards
    }

    /// The hold-to-reply menu for a card stack. A passthrough on chip-only
    /// stacks — see CardStackContextMenu. Reply arms with a card-only PROXY of
    /// this message (same id, so jump-to-source still lands here): the quote
    /// above the composer and the wire reference then carry the held component,
    /// not the caption text riding the same turn.
    private func cardStackMenu(for cards: [ChatCard]) -> CardStackContextMenu {
        CardStackContextMenu(
            cards: cards,
            message: message,
            side: side,
            onReply: onReplyToCards.map { reply in
                { reply(cardReplyProxy(for: cards)) }
            } ?? onReply
        )
    }

    /// The card-only stand-in a card-stack reply targets: the pressed stack's
    /// bubbled cards, none of the turn's text/photos/attachments.
    private func cardReplyProxy(for cards: [ChatCard]) -> ChatMessage {
        ChatMessage(
            id: message.id,
            text: "",
            isUser: message.isUser,
            time: message.time,
            cards: cards.filter { !$0.rendersAsChip },
            date: message.date
        )
    }

    /// Reply wiring for a card that owns its OWN context menu (link previews —
    /// chips, so the stack-level menu passes them by): the armed reply quotes
    /// exactly the held card. Same proxy-message contract as cardStackMenu,
    /// same whole-message fallback when card-reply wiring is absent.
    private var onReplySingleCard: ((ChatCard) -> Void)? {
        if let replyToCards = onReplyToCards {
            return { card in
                replyToCards(ChatMessage(
                    id: message.id,
                    text: "",
                    isUser: message.isUser,
                    time: message.time,
                    cards: [card],
                    date: message.date
                ))
            }
        }
        if let onReply {
            return { _ in onReply() }
        }
        return nil
    }

    /// Whether the text bubble itself should render. False for an image-only
    /// message (just the photo tile, no empty bubble) and for an EMPTY
    /// assistant bubble: the in-flight turn's one life-sign is the loading row
    /// (`ChatLoadingIndicator` — the PersonaMark shimmer), never an iMessage
    /// typing-dots bubble, so a pending bubble that slips past a surface's
    /// drop (see `visibleMessages`) renders nothing rather than dots.
    private var showsBubble: Bool {
        if !message.text.isEmpty { return true }
        if message.isVoiceMessage { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 0) {
            if message.isUser { Spacer(minLength: 70) }
            // 4pt element spacing — the SAME gap the transcript puts between
            // consecutive same-sender messages (gapAbove), so a card above its
            // caption bubble reads exactly like two burst-split bubbles.
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                // A reply wears a small "Replying to …" line ABOVE its bubble
                // (not a quote strip inside it); tapping it jumps to the quoted
                // message. Applies to text and voice-memo replies alike.
                if let replyTo = message.replyTo {
                    ReplyingToLabel(
                        reference: replyTo,
                        alignsTrailing: message.isUser,
                        onTap: onTapReplyReference
                    )
                }
                // A USER-attached photo rides ABOVE the text bubble as its own
                // rounded tile (iMessage attach semantics: photo first, caption
                // under it). Assistant photos render BELOW the text instead —
                // the text is the reply and the photos support it.
                if message.isUser {
                    imageTiles
                }
                // A USER-attached document rides ABOVE the text bubble as its
                // own compact tile (same attach semantics as a photo): doc
                // glyph + filename on the outgoing bubble fill.
                if message.isUser, let filename = message.fileAttachmentName {
                    ChatFileTile(filename: filename, tail: tailOwner == .file, onTap: onTapFile)
                        .modifier(ChatMediaContextMenu(
                            side: .outgoing,
                            tail: tailOwner == .file,
                            // A "Pasted" tile's payload is text — Copy puts it
                            // on the pasteboard whole. Picked documents have no
                            // sensible copy payload; they get Share + Reply.
                            copy: pastedTextToCopy.map { text in { Self.copyText(text) } },
                            share: onShareFile,
                            onReply: onReply
                        ))
                }
                // DEFAULT rule: cards render ABOVE the assistant's text (rich
                // inline cards are a per-product capability, dev-only for now;
                // EXCEPT mail chips + delegation, which survive on lean where the
                // main chat IS the mail/task surface).
                if !cardsAboveText.isEmpty {
                    ChatCardStack(
                        cards: cardsAboveText,
                        bubbleSide: side,
                        bubbleTail: tailOwner == .cardsAbove,
                        messageDate: message.date,
                        onReplyCard: onReplySingleCard
                    )
                    // Hold-to-reply on a card works like holding its text.
                    // ONLY when the stack has a bubbled (non-chip) card:
                    // a lifted rounded-plate preview on a bare chip reads
                    // wrong, and a long press mustn't fight a receipt's
                    // tap-to-expand — chips keep their bare interactions.
                    .modifier(cardStackMenu(for: cardsAboveText))
                }
                if showsBubble {
                    // A reminder delivery names its provenance in a small line
                    // above the bubble — the card no longer rides separately,
                    // so this is the only "this is a reminder" signal. On a
                    // follow-up it also names the chased task.
                    if embeddedReminderCard != nil {
                        ReminderBubbleKicker(title: message.reminderFollowUpTitle)
                    } else if hasScheduledReminderTurn {
                        // The set-confirmation wears the same kicker dress,
                        // one word different — the whole receipt.
                        ReminderBubbleKicker(label: "Reminder set")
                    } else if let handoffTaskId = agentHandoffTaskId {
                        // The task hand-off names its provenance the same way —
                        // the live card moved to the composer tray, so this line
                        // is what marks the confirmation prose as a spawn. Tap
                        // opens the task's thread, like tapping the card would.
                        TaskHandoffKicker(taskId: handoffTaskId)
                    }
                    bubble
                    // …and carries its bare Snooze/Done actions UNDER the
                    // bubble — the prose stays a clean bubble, the actions
                    // hang off it. Indented to the bubble's own text inset so
                    // they read as the message's continuation, not new chrome.
                    if case let .reminder(reminderId, title, status, snoozedUntil, _)? = embeddedReminderCard {
                        ReminderChatCard(
                            reminderId: reminderId, title: title, serverStatus: status,
                            serverUntilISO: snoozedUntil, embedded: true
                        )
                        // Same 6pt inset as the kicker's bell above the bubble
                        // — bell and moon share one rail;
                        // flush-with-bubble read as too far left.
                        .padding(.leading, 6)
                        // Hug the bubble (same trick as the receipt line): pull
                        // back most of the tail-dip allowance in the bubble's
                        // frame + the action row's own hit-target slack, so the
                        // labels sit a beat under the bubble BODY, not ~20
                        // below. (-10 sat too tight; design.)
                        .padding(.top, -6)
                    }
                }
                if !message.isUser {
                    imageTiles
                }
                // EXCEPTION: confirmation-gated action-concluders (payment/checkout
                // confirms, approve/deny) stay BELOW the text — the consequence is
                // read before the commit control.
                if !cardsBelowText.isEmpty {
                    ChatCardStack(
                        cards: cardsBelowText,
                        bubbleSide: side,
                        bubbleTail: tailOwner == .cardsBelow,
                        messageDate: message.date,
                        onReplyCard: onReplySingleCard
                    )
                    .modifier(cardStackMenu(for: cardsBelowText))
                    .padding(.top, chipStackHug)
                }
                if let threadPreview {
                    ThreadPreviewChip(text: threadPreview, onTap: onOpenThread)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
                // iMessage receipt line — "Delivered" / "Read 5:12 PM", small and
                // muted under the newest outgoing bubble. The SLOT is always
                // rendered there (placeholder text sized, opacity 0 until a
                // receipt lands) so appearing/upgrading NEVER changes the row's
                // height — inserting the line used to shove the whole
                // transcript up and back (jank).
                if hasReceiptSlot {
                    Text(receipt ?? String(localized: "Delivered"))
                        .font(.system(size: 11, weight: .medium))
                        .tracking(-0.1)
                        .foregroundStyle(DS.Palette.placeholder)
                        .padding(.trailing, 4)
                        // Hug the bubble like iMessage: pull back most of the
                        // column's 4pt element spacing (net ~2pt gap).
                        .padding(.top, -2)
                        .opacity(receipt == nil ? 0 : 1)
                        // Fade in on first appearance (Delivered) and CROSS-FADE
                        // the text itself when it upgrades to Read.
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: receipt)
                }
            }
            if !message.isUser { Spacer(minLength: 70) }
        }
        // At rest the timestamp is fully hidden and the offset is zero. The
        // modifier's label layer renders NOTHING at rest (no transparent
        // row-sized layer for Core Animation to composite on multi-screen
        // messages) — but the row subtree itself stays at one structural
        // position for both states, so a reveal starting/settling never resets
        // row state (the waveform/icon flash bug — see
        // ChatTimestampRevealModifier).
        .modifier(ChatTimestampRevealModifier(
            model: timestampReveal,
            // iMessage semantics: only OUTGOING bubbles slide over — they sit
            // flush against the trailing edge where the time appears. Incoming
            // rows already end ≥70pt short of that edge (their trailing
            // spacer), so the 58pt label fits without them.
            slides: message.isUser,
            time: message.time
        ))
        // (The received-message buzz moved up to the transcript level — a lazy
        // row that's scrolled out of view is never instantiated, so it can't
        // be the one listening for the empty→content flip.)
        // Text-only rows can never set `photoViewer`. Avoid installing a
        // presentation host on every message (including multi-screen text
        // rows); image rows retain the exact viewer path.
        .modifier(ChatPhotoViewerModifier(
            enabled: !message.imageDatas.isEmpty || !message.imageRemotePaths.isEmpty,
            target: $photoViewer,
            namespace: photoZoom,
            onReply: onReply
        ))
    }

    /// The message's photos as viewer photos — in-memory bytes on a fresh
    /// local send, asset paths on a reloaded/assistant bubble.
    private var photoSet: [ChatViewerPhoto] {
        if !message.imageDatas.isEmpty {
            return message.imageDatas.map { .local(data: $0) }
        }
        return message.imageRemotePaths.map { .remote(path: $0) }
    }

    /// The message's photo tiles (not inside the bubble). An image-only message
    /// shows just the tile — no empty bubble alongside it (see `showsBubble`).
    /// One photo is a plain tile; two or more collapse into a single
    /// iMessage-style deck (`ChatPhotoStackTile`) with an "N Photos" pill.
    /// Tap → fullscreen zoom/reply viewer; sibling photos page horizontally
    /// inside it, so the deck never needs per-photo tap targets.
    @ViewBuilder
    private var imageTiles: some View {
        let photos = photoSet
        Group {
            if photos.count >= 2 {
                // The scrub's live top photo — folded the same way the tile's
                // `safeTop` folds it (the deck can rebuild with fewer photos
                // than the index the scrub left behind; clamping differently
                // here would show one photo and open another).
                let top: Int = (deckTopIndex % photos.count + photos.count) % photos.count
                let a11yValue = "Photo \(top + 1) of \(photos.count)"
                ChatPhotoStackTile(
                    photos: photos,
                    side: side,
                    tail: tailOwner == .image,
                    topIndex: $deckTopIndex
                )
                .matchedTransitionSource(id: photos[top].id, in: photoZoom)
                .onTapGesture {
                    guard DSInteractionGate.allowsTap else { return }
                    photoViewer = PhotoViewerTarget(photos: photos, initialIndex: top)
                }
                .modifier(ChatMediaContextMenu(
                    side: side,
                    tail: tailOwner == .image,
                    copy: { Self.copyPhoto(photos[top]) },
                    photo: photos[top],
                    previewPhoto: photos[top],
                    onReply: onReply
                ))
                // ONE a11y element (the images and pill text inside would
                // otherwise fragment it); the count rides the identifier
                // so tests can address a specific deck.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(photos.count) photos")
                .accessibilityValue(a11yValue)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("chat-image-stack-\(photos.count)")
                // VoiceOver's swipe-up/down mirrors the scrub.
                .accessibilityAdjustableAction { direction in
                    let step: Int = direction == .increment ? 1 : -1
                    let shifted: Int = top + step + photos.count
                    deckTopIndex = shifted % photos.count
                }
                .transition(
                    .scale(scale: 0.92, anchor: message.isUser ? .bottomTrailing : .bottomLeading)
                        .combined(with: .opacity)
                )
            } else if let photo = photos.first {
                singlePhotoTile(photo)
                    .matchedTransitionSource(id: photo.id, in: photoZoom)
                    .onTapGesture {
                        guard DSInteractionGate.allowsTap else { return }
                        photoViewer = PhotoViewerTarget(photos: photos, initialIndex: 0)
                    }
                    .modifier(ChatMediaContextMenu(
                        side: side,
                        tail: tailOwner == .image,
                        copy: { Self.copyPhoto(photo) },
                        photo: photo,
                        onReply: onReply
                    ))
                    .accessibilityIdentifier("chat-image-tile-0")
                    .transition(
                        .scale(scale: 0.92, anchor: message.isUser ? .bottomTrailing : .bottomLeading)
                            .combined(with: .opacity)
                    )
            }
        }
        // A photo arriving mid-turn (send_photo's live asset event) eases in
        // instead of popping — including the single-tile → deck flip when a
        // sibling lands on the same bubble.
        .animation(.smooth(duration: 0.35), value: message.imageRemotePaths)
    }

    @ViewBuilder
    private func singlePhotoTile(_ photo: ChatViewerPhoto) -> some View {
        switch photo {
        case let .local(data):
            ChatImageTile(data: data, side: side, tail: tailOwner == .image)
        case let .remote(path):
            ChatRemoteImageTile(path: path, side: side, tail: tailOwner == .image)
        }
    }

    private static func copyPhoto(_ photo: ChatViewerPhoto) {
        switch photo {
        case let .local(data): copyImage(data: data)
        case let .remote(path): copyImage(remotePath: path)
        }
    }

    /// The text a "Pasted" attachment tile would put on the pasteboard, when
    /// its bytes are still in memory (a reloaded bubble's data lives behind an
    /// asset fetch — no synchronous copy there, so the item is omitted).
    private var pastedTextToCopy: String? {
        guard message.fileAttachmentName == ChatMessage.pastedAttachmentName,
              let data = message.fileAttachmentData else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        return text.isEmpty ? nil : text
    }

    static func copyText(_ text: String) {
        #if canImport(UIKit)
            UIPasteboard.general.string = text
        #endif
    }

    /// Copy a photo tile's IMAGE to the pasteboard. Remote tiles copy the
    /// decoded image the tile is showing (CachedRemoteImage's cache) — a tile
    /// still shimmering has nothing to copy, and silently doing nothing beats
    /// copying a stale pasteboard's surprise.
    static func copyImage(data: Data? = nil, remotePath: String? = nil) {
        #if canImport(UIKit)
            if let data, let image = UIImage(data: data) {
                UIPasteboard.general.image = image
            } else if let remotePath,
                      let cached = cachedChatPhotoPixels(forRemotePath: remotePath) {
                UIPasteboard.general.image = cached
            }
        #endif
    }

    private var bubble: some View {
        ChatBubbleContent(
            message: message,
            isStreaming: isStreaming,
            tail: tailOwner == .bubble,
            collapse: collapse,
            onToggleCollapse: onToggleCollapse
        )
        #if canImport(UIKit)
        // Publishes this bubble's REAL frame so the send morph can snap
        // its flight onto the actual landing bubble — see
        // ChatBubbleAnchorRegistry. Never hit-tests.
        .overlay {
            ChatBubbleAnchorAttachment(id: message.id)
        }
        #endif
        .modifier(ChatMessageContextMenu(
            message: message,
            side: side,
            tail: tailOwner == .bubble,
            onReply: onReply
        ))
        // The arrival pulse for a "Replying to" jump — a quick breathe from
        // the bubble's anchored side, so the eye lands on the right quote.
        // A unit scale is visually a no-op but still leaves a transform
        // node spanning the full bubble. On giant text that layer is
        // thousands of points tall and gets walked every scroll frame.
        .modifier(ChatReplyFlashModifier(
            active: isFlashed,
            anchor: message.isUser ? .trailing : .leading
        ))
    }
}

/// The message long-press menu is the SYSTEM context menu — one native
/// interaction shared by every transcript surface (main chat, history threads,
/// task threads all render through ChatRow). The system owns everything the
/// old custom pill approximated: the lift-and-scale preview, the glass
/// platter, above/below placement by available space, background dimming, the
/// open haptic, and touch cancellation (a press that opens the menu can't
/// also fire a link or button under the finger on release).
private struct ChatMessageContextMenu: ViewModifier {
    let message: ChatMessage
    let side: IMessageBubbleShape.Side
    let tail: Bool
    /// Nil hides Reply (surfaces with no composer reply wiring).
    let onReply: (() -> Void)?
    /// A card stack, not a text bubble. Two things change: the lift preview
    /// is a plain rounded plate (a stack can hold several already-traced
    /// bubbled cards, so one tailed outline across the whole VStack misfits),
    /// and the over-tall text collapse is irrelevant (the caption bubble owns
    /// that; here we lift the cards).
    var isCardStack = false

    /// True while the UIKit jumbo-emoji lift owns the glyphs. The lifted
    /// preview is a separate render — leaving the resting Text visible under
    /// it doubles the emoji, so the original hides for
    /// the duration and reappears exactly when the drop-back lands.
    @State private var jumboLifted = false

    @ViewBuilder
    func body(content: Content) -> some View {
        // Nothing to offer — a card stack or card-only message (no Copy
        // either way) in a thread with no reply wiring. An empty system
        // platter is worse than no menu (same rule as ChatMediaContextMenu).
        if onReply == nil, isCardStack || message.text.isEmpty {
            content
        } else if !isCardStack, ChatBubbleContent.rendersJumbo(message) {
            // Jumbo emoji lift BARE — the SwiftUI menu can only clip its lift
            // to a shape, and the system still paints the platter shadow
            // around that shape, which on a transparent message reads as a
            // ghost box floating behind the glyphs. Only
            // UIKit's interaction can turn the platter off entirely.
            #if canImport(UIKit)
                content
                    // Not .hidden/if-else — the overlay (and the interaction
                    // inside it) must stay mounted while the menu is up.
                    .opacity(jumboLifted ? 0 : 1)
                    .overlay {
                        JumboEmojiContextMenu(
                            text: message.text,
                            onReply: onReply,
                            onLiftChanged: { jumboLifted = $0 }
                        )
                    }
            #else
                content.contextMenu { menuItems }
            #endif
        } else {
            // The lifted preview is clipped to the traced bubble outline —
            // without this the system lifts the bubble on a rounded-rect
            // white plate that doesn't match the tail.
            let shaped = content
                .contentShape(.contextMenuPreview, previewShape)
            if !isCardStack, ChatBubbleContent.needsCollapse(message.text) {
                // A bubble taller than the screen makes the DEFAULT lifted
                // preview (the bubble itself, scaled whole to fit) an
                // unreadable sliver — lift the same capped cut the
                // transcript's "Read more" collapse renders instead.
                shaped.contextMenu {
                    menuItems
                } preview: {
                    ChatBubbleContent(message: cappedMessage, tail: false)
                        .frame(maxWidth: 320, alignment: .leading)
                }
            } else {
                shaped.contextMenu { menuItems }
            }
        }
    }

    /// The bubble outline traces the tail; a card stack lifts on a plain
    /// rounded plate at the bubble corner radius. (Jumbo-emoji messages never
    /// reach this — they carry the UIKit bare-lift overlay above.)
    private var previewShape: AnyShape {
        isCardStack
            ? AnyShape(RoundedRectangle(cornerRadius: 22.57, style: .continuous))
            : AnyShape(IMessageBubbleShape(side: side, tail: tail))
    }

    @ViewBuilder
    private var menuItems: some View {
        // No Copy on a card stack (the text it would copy is the CAPTION's,
        // not the card's — holding the card must not offer another element's
        // payload) or on a card-only message (empty string); Reply stands
        // alone there.
        if !isCardStack, !message.text.isEmpty {
            Button {
                DSHaptics.tap(.light)
                copyText()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
        if let onReply {
            Button {
                DSHaptics.tap(.light)
                onReply()
            } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
        }
    }

    /// The preview stand-in for an over-tall message: same raw-string cut as
    /// the collapsed transcript bubble (never `lineLimit` — the phantom-frame
    /// and full-layout traps).
    private var cappedMessage: ChatMessage {
        ChatMessage(
            text: ChatBubbleContent.collapsedPreview(message.text),
            isUser: message.isUser,
            time: message.time
        )
    }

    private func copyText() {
        #if canImport(UIKit)
            UIPasteboard.general.string = message.text
        #endif
    }
}

#if canImport(UIKit)
    /// The jumbo-emoji long-press. SwiftUI's `.contextMenu` cannot lift a
    /// transparent message cleanly — its platter shadow follows the preview
    /// shape no matter what, so the bare glyphs rose inside a visible ghost
    /// box. This UIKit interaction supplies a UITargetedPreview with a clear
    /// platter and an EMPTY shadowPath: the emoji rise alone, exactly the way
    /// Messages lifts a jumbo emoji. Attached as a transparent overlay sized
    /// to the rendered glyphs; scroll/pan gestures pass through untouched.
    private struct JumboEmojiContextMenu: UIViewRepresentable {
        let text: String
        let onReply: (() -> Void)?
        /// Reports lift ownership so the SwiftUI side can hide the resting
        /// glyphs — true when the menu displays, false when the drop-back
        /// finishes.
        let onLiftChanged: (Bool) -> Void

        func makeUIView(context _: Context) -> JumboEmojiMenuHost {
            JumboEmojiMenuHost(
                text: text,
                onReply: onReply,
                onLiftChanged: onLiftChanged
            )
        }

        func updateUIView(_ view: JumboEmojiMenuHost, context _: Context) {
            view.text = text
            view.onReply = onReply
            view.onLiftChanged = onLiftChanged
        }
    }

    private final class JumboEmojiMenuHost: UIView, UIContextMenuInteractionDelegate {
        var text: String
        var onReply: (() -> Void)?
        var onLiftChanged: (Bool) -> Void
        /// Retains the lift renderer while UIKit animates its view — the
        /// preview only retains the view, and a hosting view whose
        /// controller died stops drawing.
        private var liftHost: UIHostingController<AnyView>?

        init(
            text: String,
            onReply: (() -> Void)?,
            onLiftChanged: @escaping (Bool) -> Void
        ) {
            self.text = text
            self.onReply = onReply
            self.onLiftChanged = onLiftChanged
            super.init(frame: .zero)
            backgroundColor = .clear
            addInteraction(UIContextMenuInteraction(delegate: self))
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) { fatalError("unused") }

        func contextMenuInteraction(
            _: UIContextMenuInteraction,
            configurationForMenuAtLocation _: CGPoint
        ) -> UIContextMenuConfiguration? {
            UIContextMenuConfiguration(actionProvider: { [weak self] _ in
                guard let self else { return nil }
                // Same items, order, glyphs, and haptic as the bubble menu.
                var actions = [
                    UIAction(
                        title: String(localized: "Copy"),
                        image: UIImage(systemName: "doc.on.doc")
                    ) { [text = self.text] _ in
                        DSHaptics.tap(.light)
                        UIPasteboard.general.string = text
                    }
                ]
                if let onReply = self.onReply {
                    actions.append(UIAction(
                        title: String(localized: "Reply"),
                        image: UIImage(systemName: "arrowshape.turn.up.left")
                    ) { _ in
                        DSHaptics.tap(.light)
                        onReply()
                    })
                }
                return UIMenu(children: actions)
            })
        }

        func contextMenuInteraction(
            _: UIContextMenuInteraction,
            previewForHighlightingMenuWithConfiguration _: UIContextMenuConfiguration
        ) -> UITargetedPreview? {
            barePreview()
        }

        func contextMenuInteraction(
            _: UIContextMenuInteraction,
            previewForDismissingMenuWithConfiguration _: UIContextMenuConfiguration
        ) -> UITargetedPreview? {
            barePreview() // the drop-back stays shadowless too
        }

        // The lifted preview is a SEPARATE render over the still-mounted
        // Text — leave the original visible and the glyphs double for the
        // whole menu. Hide it once the menu owns the screen (not at lift
        // start: a cancelled press never gets these callbacks, and by
        // display time the preview covers the original exactly), and bring
        // it back the instant the drop-back lands.
        func contextMenuInteraction(
            _: UIContextMenuInteraction,
            willDisplayMenuFor _: UIContextMenuConfiguration,
            animator _: (any UIContextMenuInteractionAnimating)?
        ) {
            onLiftChanged(true)
        }

        func contextMenuInteraction(
            _: UIContextMenuInteraction,
            willEndFor _: UIContextMenuConfiguration,
            animator: (any UIContextMenuInteractionAnimating)?
        ) {
            if let animator {
                animator.addCompletion { [weak self] in
                    self?.onLiftChanged(false)
                    self?.liftHost = nil
                }
            } else {
                onLiftChanged(false)
                liftHost = nil
            }
        }

        /// The lift: the SAME SwiftUI render as the resting glyphs — a
        /// hosted Text with the identical font, over the overlay's own
        /// footprint. A UILabel here is NOT equivalent: UIKit and SwiftUI
        /// box the same glyphs differently, so the lifted copy sat a few
        /// points off the original and read as a second emoji popping up.
        /// Clear platter + empty shadowPath stays the ghost-box fix —
        /// omit either and the shadow returns.
        ///
        /// Returns nil when the host has left the window: the dismissal
        /// preview can be requested after the row was recycled out of the
        /// transcript (new message, scroll) while the menu was up, and
        /// UIPreviewTarget asserts (crashes) on a windowless container.
        /// nil just means UIKit's default drop-back — fine, the glyphs are
        /// already off screen.
        private func barePreview() -> UITargetedPreview? {
            guard window != nil else { return nil }
            let host = UIHostingController(rootView: AnyView(
                Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: ChatBubbleContent.jumboEmojiPointSize))
            ))
            // No safe-area: UIKit hosts the preview in its own portal
            // window, and a hosting view that respects safe area would
            // shove the glyphs inside the frame near screen edges.
            host.safeAreaRegions = []
            host.view.backgroundColor = .clear
            host.view.frame = bounds
            liftHost = host

            let parameters = UIPreviewParameters()
            parameters.backgroundColor = .clear
            parameters.shadowPath = UIBezierPath()

            return UITargetedPreview(
                view: host.view,
                parameters: parameters,
                target: UIPreviewTarget(
                    container: self,
                    center: CGPoint(x: bounds.midX, y: bounds.midY)
                )
            )
        }
    }
#endif

/// Gates the hold-to-reply menu onto a card stack. Attaches
/// ChatMessageContextMenu ONLY when the stack carries a bubbled (non-chip)
/// card: a lifted rounded-plate preview on a bare status/mailRef/toolRun chip
/// reads as a glitch, and a long press there would fight the chip's own
/// tap-to-expand / tap-to-detail. Chip-only stacks stay bare, exactly as
/// before. The wrapper is always applied (stable view identity as the stack's
/// cards stream in); only the inner menu appears/disappears.
private struct CardStackContextMenu: ViewModifier {
    let cards: [ChatCard]
    let message: ChatMessage
    let side: IMessageBubbleShape.Side
    let onReply: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        // Self-bubbled cards (link previews) own a richer hold menu of their
        // own (live page preview) — the stack-level menu must not double up
        // on top of it.
        if cards.contains(where: { !$0.rendersAsChip && !$0.drawsOwnBubble }) {
            content.modifier(ChatMessageContextMenu(
                message: message,
                side: side,
                // The stack lifts on a plain rounded plate (isCardStack), so
                // there is no single tail to trace.
                tail: false,
                onReply: onReply,
                isCardStack: true
            ))
        } else {
            content
        }
    }
}

/// The same system context menu for a message's NON-text elements — photo
/// tiles and the user-file tile. Reply matches the bubble menu; Copy is
/// element-specific (the image bits, the pasted text) and omitted where there
/// is no sensible payload. With no items at all the menu isn't attached — an
/// empty system platter is worse than no menu.
private struct ChatMediaContextMenu: ViewModifier {
    let side: IMessageBubbleShape.Side
    /// Whether the element is drawn with the iMessage tail (the preview clip
    /// must match the tile's own clip exactly).
    let tail: Bool
    let copy: (() -> Void)?
    /// A photo tile's payload — enables Save Image (camera roll, add-only)
    /// and Share (native sheet). Nil on the file tile.
    var photo: ChatViewerPhoto?
    /// Set on the multi-photo deck: the lift shows this photo ALONE. The
    /// fanned siblings and the "N Photos" caption stay down on the transcript
    /// — lifting the whole splayed stack read as a mess.
    var previewPhoto: ChatViewerPhoto?
    /// Presents the native share sheet for a non-image element (the file
    /// tile hands its document over as a real named file).
    var share: (() -> Void)?
    let onReply: (() -> Void)?

    @Environment(\.authorizedImageLoader) private var imageLoader

    /// A `ph:` ref IS a camera-roll asset — the tile is drawing pixels
    /// straight out of the user's library. "Save Image" on one of those saves
    /// a photo to the place it already lives, so the item is omitted. Sending
    /// a photo doesn't make it a library photo (a paste, a screenshot handed
    /// over, a photo from a shared album) — only its `ph:` provenance does.
    private var canSave: Bool {
        guard case let .remote(path) = photo else { return true }
        return PhotoLibraryImageView.localIdentifier(fromAssetPath: path) == nil
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if copy == nil, photo == nil, share == nil, onReply == nil {
            content
        } else if let previewPhoto {
            content.contextMenu { menuItems } preview: { previewTile(previewPhoto) }
        } else {
            content
                .contentShape(.contextMenuPreview, IMessageBubbleShape(side: side, tail: tail))
                .contextMenu { menuItems }
        }
    }

    @ViewBuilder private var menuItems: some View {
        if let copy {
            Button {
                DSHaptics.tap(.light)
                copy()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
        if let photo {
            if canSave {
                if ChatMediaActions.isSavedToPhotos(photo) {
                    // Already written to the camera roll by this menu —
                    // say so instead of quietly stacking a duplicate.
                    Button {} label: {
                        Label("Saved to Photos", systemImage: "checkmark")
                    }
                    .disabled(true)
                } else {
                    Button {
                        DSHaptics.tap(.light)
                        Task { await ChatMediaActions.saveToPhotos(photo, loader: imageLoader) }
                    } label: {
                        Label("Save Image", systemImage: "square.and.arrow.down")
                    }
                }
            }
            Button {
                DSHaptics.tap(.light)
                ChatMediaActions.share(photo, loader: imageLoader)
            } label: {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
        }
        if let share {
            Button {
                DSHaptics.tap(.light)
                share()
            } label: {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
        }
        if let onReply {
            Button {
                DSHaptics.tap(.light)
                onReply()
            } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
        }
    }

    /// The deck's lift: the cover photo at its own tile size, no tail — a
    /// lifted card isn't attached to the bubble it came from.
    @ViewBuilder private func previewTile(_ photo: ChatViewerPhoto) -> some View {
        switch photo {
        case let .local(data):
            ChatImageTile(data: data, side: side)
        case let .remote(path):
            ChatRemoteImageTile(path: path, side: side)
        }
    }
}

/// The notification-tap reveal's re-check points, grouped so the transcript
/// body pays for ONE modifier instead of three chained onChanges (which tipped
/// it over the compiler's type-check budget).
private struct NotificationRevealTriggers: ViewModifier {
    let revealMessageID: UUID?
    let messageCount: Int
    let attempt: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: revealMessageID) { attempt() }
            .onChange(of: messageCount) { attempt() }
            .task { attempt() }
    }
}

private struct ChatReplyFlashModifier: ViewModifier {
    let active: Bool
    let anchor: UnitPoint

    @ViewBuilder
    func body(content: Content) -> some View {
        if active {
            content.scaleEffect(1.05, anchor: anchor)
        } else {
            content
        }
    }
}

private struct ChatPhotoViewerModifier: ViewModifier {
    let enabled: Bool
    @Binding var target: PhotoViewerTarget?
    let namespace: Namespace.ID
    let onReply: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.fullScreenCover(item: $target) { target in
                // Clear presentation background: the viewer draws its own black
                // backdrop, so the dismiss pull's dim reveals the chat behind
                // the photo instead of an opaque cover sheet.
                if target.photos.count > 1 {
                    // NO zoom morph on the multi-photo pager: the dismiss
                    // morph resizes the container, containerRelativeFrame
                    // re-sizes the pages, the paging scroll re-derives its
                    // position, and the feedback loop wedges the main thread
                    // — the viewer could never be closed.
                    ChatPhotoViewer(photos: target.photos, initialIndex: target.initialIndex, onReply: onReply)
                        .presentationBackground(.clear)
                } else {
                    ChatPhotoViewer(photos: target.photos, initialIndex: target.initialIndex, onReply: onReply)
                        .navigationTransition(.zoom(sourceID: target.photo.id, in: namespace))
                        .presentationBackground(.clear)
                }
            }
        } else {
            content
        }
    }
}

/// The left-swipe reveal's live state — an @Observable box instead of @State
/// CGFloats on the screen, because the UIKit pan writes `offset` on every
/// touch sample (up to 120Hz). Only ChatTimestampRevealModifier's leaf body
/// reads it, so a drag frame re-renders one offset + one 11pt label per
/// visible row. Routed through screen @State (the old shape) each sample
/// invalidated the whole transcript body AND failed every ChatRow's Equatable
/// gate — full bubble re-renders, markdown and card stacks included, at drag
/// rate (the reveal's jank; design).
@MainActor @Observable
final class ChatTimestampRevealModel {
    /// How far the reveal is pulled open, in points. Past `maxReveal` the
    /// drag keeps 15% of its rate — a stop with give, not a wall.
    private(set) var offset: CGFloat = 0
    /// Keeps the reveal layer installed through its spring return to zero. At
    /// rest it is false, so giant rows carry no dormant transform/overlay.
    private(set) var active = false

    static let maxReveal: CGFloat = 72

    /// Finger tracking: 0.92 of the drag (design-app feel, slightly
    /// under-finger), soft resistance past the stop.
    func dragChanged(translationX: CGFloat) {
        if !active { active = true }
        let tracked = max(-translationX, 0) * 0.92
        offset = tracked <= Self.maxReveal
            ? tracked
            : Self.maxReveal + (tracked - Self.maxReveal) * 0.15
    }

    /// Spring the reveal home, then drop its label layer once the spring is
    /// visually settled.
    func settle() {
        withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.86, blendDuration: 0.08)) {
            offset = 0
        }
        Task { @MainActor in
            // The prior implementation kept its overlay for the entire spring.
            // Drop it only after that animation is visually settled.
            try? await Task.sleep(for: .milliseconds(500))
            if offset == 0 { active = false }
        }
    }

    /// QA hook (shot tests): pin the reveal open — XCUITest can't hold a drag
    /// mid-screenshot, and the reveal springs back on release. Instant, like
    /// a finger drag (no animation).
    func pin(_ points: CGFloat) {
        active = true
        offset = min(points, Self.maxReveal)
    }
}

/// The left-swipe timestamp treatment. `offset == 0` is the overwhelmingly
/// common scrolling state, where the label layer renders NOTHING (no full-row
/// transparent layer for Core Animation to composite) and the offset is
/// identity.
///
/// IDENTITY RULE: the `active` conditional must live INSIDE the layer
/// builder, never AROUND `content`. An `if active { content.offset… } else
/// { content }` branch moves the whole row subtree between two structural
/// positions, so every drag start and settle end destroyed and rebuilt row
/// state — the voice bubble's computed waveform flashed back to its
/// placeholder and card icons flashed their fallback while their async
/// resolves re-ran.
private struct ChatTimestampRevealModifier: ViewModifier {
    /// Read HERE, at the leaf, and nowhere up the tree — this body is the
    /// only view that invalidates per drag sample.
    let model: ChatTimestampRevealModel
    /// Whether the row itself slides with the reveal (outgoing bubbles only,
    /// like iMessage). The label's own entrance is identical either way.
    let slides: Bool
    let time: String

    func body(content: Content) -> some View {
        content
            .offset(x: model.active && slides ? -model.offset : 0)
            // BACKGROUND, not overlay: the label enters from OFF the trailing
            // screen edge and tracks the pull 1:1 — iMessage's entrance, one
            // and the same for incoming and outgoing
            // labels used to materialize near their resting spot and drift in
            // from the LEFT, reading as from mid-screen).
            //
            // Parked `maxReveal` right of its resting spot, the label starts
            // clear of the row's trailing edge (its 58pt frame ends 14pt past
            // it) and slides home as the pull opens, staying just off the
            // sliding bubble's edge the whole way — so it never overlays grey
            // text across an outgoing bubble's fill. The clamp holds it at
            // rest through the over-pull past `maxReveal` (soft-resistance
            // region) instead of letting it drift left with the bubble.
            .background(alignment: .trailing) {
                if model.active {
                    Text(time)
                        .font(.system(size: 11, weight: .regular))
                        .tracking(-0.16)
                        .foregroundStyle(DS.Palette.placeholder)
                        .frame(width: 58, alignment: .trailing)
                        .offset(x: max(ChatTimestampRevealModel.maxReveal - model.offset, 0))
                        // Fade WITH the slide — materializing at full strength
                        // off the screen edge read as a hard pop (
                        //). Tracks the pull both ways, so the
                        // settle spring fades it back out along the same ramp.
                        .opacity(min(model.offset / ChatTimestampRevealModel.maxReveal, 1))
                        .allowsHitTesting(false)
                }
            }
    }
}

// `TopScrollEdgeEffectHidden` lives in TopScrollFade.swift — Home and the
// transcript both apply it, so it sits with the other shared edge treatments.

/// The small muted "Replying to …" line floated above a reply's bubble.
/// Tapping it asks the transcript to glide to the quoted message.
private struct ReplyingToLabel: View {
    let reference: ChatReplyReference
    /// True above an OUTGOING bubble: the label hugs the trailing edge so its
    /// text ends where the bubble ends. The snippet's width cap used to be a
    /// hard 150pt frame, and a SHORT quote left its dead space exactly there —
    /// a bare gap between "…July 23" and the bubble.
    var alignsTrailing = false
    let onTap: () -> Void

    private var title: String {
        switch reference.kind {
        case .message: "Replying to"
        case .suggestion: "Replying to Suggestion"
        case .meeting: "Replying to Event"
        }
    }

    /// The quoted text, flattened to one line; a voice memo that produced no
    /// transcription still reads as something.
    private var snippet: String {
        let flat = reference.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.isEmpty ? "a voice message" : flat
    }

    var body: some View {
        Button {
            guard DSInteractionGate.allowsTap else { return }
            onTap()
        } label: {
            // Hug-with-cap: a short quote renders at its natural width (first
            // candidate, fixedSize), a long one falls back to the capped frame
            // and truncates. A bare `.frame(maxWidth: 150)` alone EXPANDS to
            // 150 regardless of content — the dead space read as a stray gap
            // beside the bubble.
            ViewThatFits(in: .horizontal) {
                labelContent(cappedSnippet: false)
                    .fixedSize(horizontal: true, vertical: false)
                labelContent(cappedSnippet: true)
            }
            // The width cap for the fit decision; alignment keeps whatever
            // slack remains on the side AWAY from the bubble's edge.
            .frame(maxWidth: 270, alignment: alignsTrailing ? .trailing : .leading)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func labelContent(cappedSnippet: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 9, weight: .semibold))
            // A Home-surface reply names its source; the snippet after it
            // carries the card's context.
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .layoutPriority(1)
            if cappedSnippet {
                Text(snippet)
                    .font(.system(size: 11, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Cut the quote off early — a near-full-width snippet reads
                    // as its own message instead of a small reference.
                    .frame(maxWidth: 150, alignment: .leading)
            } else {
                Text(snippet)
                    .font(.system(size: 11, weight: .regular))
                    .lineLimit(1)
            }
        }
        .tracking(-0.11)
        .foregroundStyle(DS.Palette.placeholder)
    }
}

/// The small "🔔 REMINDER" provenance line above a reminder delivery's bubble —
/// the same kicker typography the standalone fired card wears inside itself,
/// moved above the bubble now that the delivery and its actions share one turn.
/// On a FOLLOW-UP the kicker also carries the task ("REMINDER · walk the dog"):
/// the nudge's prose is conversational and no card renders beside it, so this
/// line is the guaranteed context. Internal (not private):
/// ReminderCardPreviewHost renders it for QA shots.
struct ReminderBubbleKicker: View {
    /// The chased task, follow-up turns only — nil renders the plain kicker.
    var title: String? = nil
    /// The kicker's word: "Reminder" on deliveries, "Reminder set" on the
    /// set-confirmation turn — same dress either way.
    var label: LocalizedStringKey = "Reminder"

    /// The kicker is provenance, not a second title: a
    /// long reminder title running to a mid-sentence ellipsis ("Head to LAX —
    /// United flight UA372…") read worse than the short stub ("Head to LAX").
    /// The backend now authors a 2–3 word handle at set time and sends it as
    /// the card title, so a SHORT title passes through verbatim; the 3-word
    /// clamp remains only as the fallback for long titles (legacy rows, and
    /// sources that never wrote a handle). Punctuation-only tokens (a
    /// dangling "—") don't count as words and a trailing comma/dash is shed.
    private var clampedTitle: String? {
        guard let title else { return nil }
        let words = title.split(whereSeparator: \.isWhitespace)
            .filter { $0.contains { $0.isLetter || $0.isNumber } }
        guard !words.isEmpty else { return nil }
        guard words.count > 4 else { return title.trimmingCharacters(in: .whitespaces) }
        return words.prefix(3).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;:—–-"))
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bell.fill")
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .layoutPriority(1)
            if let title = clampedTitle {
                // Original casing, one truncating line — the task is context,
                // not a second title, so it never wraps the kicker.
                Text("· \(title)")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(-0.1)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .foregroundStyle(DS.Palette.inkMuted.opacity(0.8))
        .padding(.horizontal, 6)
    }
}

/// The "Created an agent ›" line (aqi.medium dot-swirl glyph) above a task
/// hand-off's bubble — the
/// delegation twin of ReminderBubbleKicker (same rail), worn by the
/// assistant's "I'm starting on it" confirmation now that the live task card
/// rides the composer tray instead of the message. Sentence case with a
/// trailing chevron rather than the uppercase stamp: it's a tappable link
/// into the task's page, not just provenance. (A LEGACY task with no
/// activity thread degrades to the page's goal-only fallback — new tasks
/// open the full timeline.)
struct TaskHandoffKicker: View {
    let taskId: String

    @Environment(DeepTaskStore.self) private var deepTasks

    var body: some View {
        Button {
            guard DSInteractionGate.allowsTap else { return }
            DSHaptics.tap()
            withAnimation(.smooth(duration: 0.34, extraBounce: 0)) { deepTasks.open(taskId) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "aqi.medium")
                    .font(.system(size: 11, weight: .semibold))
                Text("Created an agent")
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .opacity(0.7)
            }
            .foregroundStyle(DS.Palette.inkMuted.opacity(0.8))
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        // Same warm-up the delegation card does: fetch the task by id the
        // moment the kicker appears, so the tap opens an already-loaded page.
        .onAppear { deepTasks.ensureLoaded(taskId) }
    }
}

// MARK: - Bubble visual (reused by the reply overlay)

/// Whether a history bubble renders capped ("Read more") or fully. `none` for
/// bubbles that never collapse: short messages, the transcript's last message,
/// and every non-transcript surface (thread views, quotes, previews). There is
/// no expanded state — "Read more" opens the full-screen reader, so a capped
/// bubble never grows in place.
enum ChatBubbleCollapse {
    case none, collapsed
}

struct ChatBubbleContent: View {
    let message: ChatMessage
    /// While true (trailing bubble mid-stream), render markdown with a cheap
    /// inline-only pass; the full GFM-table + bare-URL render runs once at end.
    var isStreaming = false
    /// Last-in-run bubbles carry the traced iMessage tail.
    var tail = true
    /// Long-history cap (see ChatBubbleCollapse). The CUT is applied to the raw
    /// string before render, so layout, markdown parsing, and hit-testing all
    /// see only the preview — a `lineLimit` cap would still measure the full
    /// string (multi-screen layout cost, and its truncated Text hit-tests a
    /// PHANTOM frame far past the drawn glyphs; see quoteCapped).
    var collapse: ChatBubbleCollapse = .none
    var onToggleCollapse: () -> Void = {}

    /// Cache for `linkified` — the user-bubble twin of `markdownCache`. The
    /// NSDataDetector scan is O(text) and ran on EVERY body eval (measured
    /// 3.8ms at 7k chars on a Mac): every LazyVStack re-appearance, and — while
    /// a reply streams — every token for every visible row. A long SENT message
    /// made the whole transcript stutter. (`isUser` doesn't affect the output —
    /// the tint is applied by `bubbleText` — so the text alone is the key.)
    private nonisolated(unsafe) static let linkifiedCache: NSCache<NSString, MarkdownRenderBox> = {
        let cache = NSCache<NSString, MarkdownRenderBox>()
        cache.countLimit = 400
        return cache
    }()

    /// Bubble text with any URLs turned into tappable, underlined links. Only the
    /// link runs carry a `.link`; their colour comes from the Text's `.tint` (DS
    /// accent, or white on a user bubble for contrast). A link tap fires the
    /// environment `openURL` (→ Safari) and never competes with the long-press
    /// menu or the timestamp-reveal pan, which are separate recognizers.
    nonisolated static func linkified(_ text: String, isUser: Bool) -> AttributedString {
        let cacheKey = text as NSString
        if let cached = linkifiedCache.object(forKey: cacheKey) { return cached.value }
        let rendered = ChatPerf.measure("linkify.coldParse", "\(text.count) chars") { linkifiedUncached(text) }
        linkifiedCache.setObject(MarkdownRenderBox(rendered), forKey: cacheKey)
        return rendered
    }

    private nonisolated static func linkifiedUncached(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return attributed
        }
        let fullRange = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: fullRange) {
            guard let url = match.url, let stringRange = Range(match.range, in: text) else { continue }
            let lower = text.distance(from: text.startIndex, to: stringRange.lowerBound)
            let upper = text.distance(from: text.startIndex, to: stringRange.upperBound)
            let start = attributed.index(attributed.startIndex, offsetByCharacters: lower)
            let end = attributed.index(attributed.startIndex, offsetByCharacters: upper)
            attributed[start ..< end].link = url
            attributed[start ..< end].underlineStyle = .single
        }
        return attributed
    }

    /// Assistant bubble text with the markdown the model actually emits rendered
    /// instead of shown as source: inline **bold** / *italic* / `code` / [links],
    /// `#` headers as bold lines, and `- ` bullets as "• " — line by line, so
    /// plain text and line breaks pass through untouched. Bare URLs are then
    /// linkified on top (markdown links already carry theirs). Deep-task results
    /// are routinely markdown; raw asterisks read as noise. User bubbles keep the
    /// literal text — what someone typed is never reinterpreted.
    private final class MarkdownRenderBox {
        let value: AttributedString
        init(_ value: AttributedString) { self.value = value }
    }

    /// Cache of rendered assistant markdown, keyed by the raw text. Rendering runs
    /// per-line regex + AttributedString(markdown:) + an NSDataDetector link scan;
    /// without this, scrolling chat history re-parses every bubble each time it
    /// re-enters the LazyVStack viewport. NSCache is thread-safe and self-evicting;
    /// identical text → identical output, so results are safe to memoize.
    private nonisolated(unsafe) static let markdownCache: NSCache<NSString, MarkdownRenderBox> = {
        let cache = NSCache<NSString, MarkdownRenderBox>()
        cache.countLimit = 400
        return cache
    }()

    /// Streaming render caches. During streaming the bubble re-renders on every
    /// token, but only the line still being typed changes — everything before
    /// the last newline is immutable. Without these, each token re-ran the
    /// regexes and `AttributedString(markdown:)` over the WHOLE accumulated
    /// text, an O(n²) stall that visibly drops frames on long replies
    /// (measured ~14ms/token at 18k chars — a full 60fps frame budget on
    /// parsing alone; ~0.1ms with the caches).
    /// - `markdownLineCache`: one line's render, keyed by the line.
    /// - `markdownPrefixCache`: the concatenated render of everything before
    /// the in-flight trailing line, keyed by that prefix — refreshed once per
    /// COMPLETED line, so per-token work is one line parse + one concat
    /// instead of a 100-way concatenation.
    private nonisolated(unsafe) static let markdownLineCache: NSCache<NSString, MarkdownRenderBox> = {
        let cache = NSCache<NSString, MarkdownRenderBox>()
        cache.countLimit = 4000
        return cache
    }()

    private nonisolated(unsafe) static let markdownPrefixCache: NSCache<NSString, MarkdownRenderBox> = {
        let cache = NSCache<NSString, MarkdownRenderBox>()
        cache.countLimit = 32
        return cache
    }()

    /// Inline-only markdown (bold/italic/`code`/[links]/# headers/- bullets) plus
    /// underlining of inline-link runs. NO bare-URL NSDataDetector scan — the
    /// cheap per-token body shared by both `markdownRendered` (the cached/final
    /// path) and the streaming `markdownRenderedFast`.
    private nonisolated static func markdownInline(_ text: String, streaming: Bool = false) -> AttributedString {
        var out: AttributedString
        if streaming {
            if let lastBreak = text.lastIndex(of: "\n") {
                // Settled prefix from the prefix cache (one rebuild per
                // completed line); only the in-flight trailing line re-parses
                // per token. The trailing line touches NO cache — it's a new
                // string every token and would only churn the keys.
                let prefix = String(text[..<lastBreak])
                let trailing = String(text[text.index(after: lastBreak)...])
                let key = prefix as NSString
                if let cached = markdownPrefixCache.object(forKey: key) {
                    out = cached.value
                } else {
                    out = Self.renderedLines(prefix)
                    markdownPrefixCache.setObject(MarkdownRenderBox(out), forKey: key)
                }
                out += AttributedString("\n")
                out += markdownInlineLine(trailing)
            } else {
                // Reply still on its first line — parse it directly, uncached.
                out = markdownInlineLine(text)
            }
        } else {
            out = Self.renderedLines(text)
        }
        // Underline inline markdown links (cheap run iteration). Mutating `out`
        // copies-on-write; cached values above stay untouched.
        for run in out.runs where run.link != nil {
            out[run.range].underlineStyle = .single
        }
        return out
    }

    /// Concatenated per-line renders, each line memoized in `markdownLineCache`.
    private nonisolated static func renderedLines(_ text: String) -> AttributedString {
        var out = AttributedString()
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let key = line as NSString
            if let cached = markdownLineCache.object(forKey: key) {
                out += cached.value
            } else {
                let rendered = markdownInlineLine(line)
                markdownLineCache.setObject(MarkdownRenderBox(rendered), forKey: key)
                out += rendered
            }
            if index < lines.count - 1 { out += AttributedString("\n") }
        }
        return out
    }

    /// Render ONE line of inline markdown — the unit `markdownInline` memoizes.
    private nonisolated static func markdownInlineLine(_ line: String) -> AttributedString {
        var content = Substring(line)
        var isHeader = false
        if let marker = content.range(of: "^#{1,6}\\s+", options: .regularExpression) {
            content = content[marker.upperBound...]
            isHeader = true
        } else if let marker = content.range(of: "^\\s*[-*]\\s+", options: .regularExpression) {
            let indent = String(content.prefix(while: { $0 == " " }))
            content = Substring(indent + "•  " + String(content[marker.upperBound...]))
        }
        var rendered = (try? AttributedString(
            markdown: String(content),
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(String(content))
        if isHeader {
            rendered.inlinePresentationIntent = .stronglyEmphasized
        }
        return rendered
    }

    /// Streaming-only cheap render: inline markdown, skipping the whole-text
    /// bare-URL NSDataDetector scan and the whole-text cache (streaming text is
    /// ephemeral — a new string each token would only thrash it). Settled lines
    /// still hit the per-line cache, so a token costs one line's parse, not the
    /// whole reply's. GFM tables and bare-URL autolinks land in the single full
    /// `markdownRendered` pass the moment the stream ends.
    nonisolated static func markdownRenderedFast(_ text: String) -> AttributedString {
        markdownInline(text, streaming: true)
    }

    nonisolated static func markdownRendered(_ text: String) -> AttributedString {
        let cacheKey = text as NSString
        if let cached = markdownCache.object(forKey: cacheKey) { return cached.value }
        return ChatPerf.measure("markdown.coldParse", "\(text.count) chars") {
            markdownRenderedUncached(text, cacheKey: cacheKey)
        }
    }

    /// Pre-render a transcript's bubbles into the markdown/linkify caches OFF
    /// the main thread, so a cold launch doesn't pay the parse per bubble on
    /// the render loop — the first paint hit up to ~36ms for a single bubble
    /// (framework warm-up included), and every history scroll re-hit cold rows.
    /// Renders through the same entry points the rows use, mirroring the row's
    /// own decision (collapsed preview, markdown blocks vs linkify), so the
    /// warmed cache keys are exactly the ones the rows will ask for. Safe
    /// off-main: pure Foundation parsing into thread-safe NSCaches.
    nonisolated static func warmRenderCaches(rows: [(text: String, isUser: Bool, collapsible: Bool)]) {
        for row in rows where !row.text.isEmpty {
            let shown = row.collapsible && needsCollapse(row.text) ? collapsedPreview(row.text) : row.text
            if row.isUser {
                _ = linkified(shown, isUser: true)
            } else {
                for block in markdownBlocks(shown) {
                    if case let .text(t) = block { _ = markdownRendered(t) }
                }
            }
        }
    }

    private nonisolated static func markdownRenderedUncached(_ text: String, cacheKey: NSString) -> AttributedString {
        var out = markdownInline(text)
        // Bare-URL autolink — the expensive whole-text NSDataDetector scan, run
        // only on this cached/final path, never per streaming token.
        let plain = String(out.characters)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) {
                guard let url = match.url, let stringRange = Range(match.range, in: plain) else { continue }
                let lower = plain.distance(from: plain.startIndex, to: stringRange.lowerBound)
                let upper = plain.distance(from: plain.startIndex, to: stringRange.upperBound)
                let start = out.index(out.startIndex, offsetByCharacters: lower)
                let end = out.index(out.startIndex, offsetByCharacters: upper)
                guard out[start ..< end].runs.allSatisfy({ $0.link == nil }) else { continue }
                out[start ..< end].link = url
                out[start ..< end].underlineStyle = .single
            }
        }
        markdownCache.setObject(MarkdownRenderBox(out), forKey: cacheKey)
        return out
    }

    // MARK: Long-history collapse

    /// A message collapses when its FULL render would run well past a screen:
    /// ~1300 chars fill one screen at chat width (35 chars/line, 22pt pitch),
    /// so the cap only engages when meaningfully more than the preview would
    /// be hidden; the ~700-char preview reads as roughly 3/4 of a screen. The
    /// line trigger catches many-short-lines lists that are vertically huge
    /// at a low character count.
    private static let collapseCharThreshold = 1600
    private static let collapseLineThreshold = 40
    private static let previewChars = 700
    private static let previewLines = 18

    /// Whether a transcript bubble with this text renders capped by default.
    /// Hot: the transcript body asks this for every rendered row on every
    /// re-eval (keyboard frames, streaming ticks). Grapheme clusters ≤ UTF-8
    /// bytes and `utf8.count` is O(1) on native strings, so a byte count at
    /// or under the threshold rules the char arm out without the O(n)
    /// grapheme walk `.count` costs — the newline arm then only ever scans
    /// short-by-bytes text.
    nonisolated static func needsCollapse(_ text: String) -> Bool {
        if text.utf8.count > collapseCharThreshold, text.count > collapseCharThreshold {
            return true
        }
        return text.lazy.filter { $0 == "\n" }.count >= collapseLineThreshold
    }

    /// The capped RAW text a collapsed bubble renders (see `collapse` above for
    /// why the string is cut rather than the layout). When the character cap
    /// did the cutting, back up to the last whitespace so a word — or worse, a
    /// URL that `linkified` would turn into a broken link — is never split.
    nonisolated static func collapsedPreview(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var cut = String(lines.prefix(previewLines).joined(separator: "\n").prefix(previewChars))
        if cut.count == previewChars,
           let lastBreak = cut.lastIndex(where: \.isWhitespace),
           cut.distance(from: lastBreak, to: cut.endIndex) < 160 {
            cut = String(cut[..<lastBreak])
        }
        return cut.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    /// The "Read more" line under a capped message's preview — opens the
    /// full-screen reader. Inside the bubble so it reads as part of the
    /// message, tinted like the bubble's links.
    private var collapseToggle: some View {
        Button {
            guard DSInteractionGate.allowsTap else { return }
            onToggleCollapse()
        } label: {
            HStack(spacing: 4) {
                Text(String(localized: "Read more"))
                    .font(.system(size: 15, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(message.isUser ? Color.white : Color(light: 0x097FFF, dark: 0x409CFF))
            .padding(.top, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("read-more")
    }

    /// Apply the bubble's shared text treatment (font, colour, link tint) to a
    /// rendered attributed string. Factored so the plain-text path and each text
    /// block of a mixed table+text message style identically.
    @ViewBuilder
    private func bubbleText(_ attributed: AttributedString) -> some View {
        Text(attributed)
            .font(.system(size: 17, weight: .regular))
            .lineSpacing(22 - 20.29) // iMessage 22pt line pitch at 17pt type
            .foregroundStyle(message.isUser ? Color.white : DS.Palette.inkBlack)
            .tint(message.isUser ? Color.white : Color(light: 0x097FFF, dark: 0x409CFF))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// One block of assistant markdown: a run of ordinary text (inline markdown),
    /// or a GFM table parsed into a header + rows.
    enum MarkdownBlock {
        case text(String)
        case table(header: [String], rows: [[String]])
    }

    /// True for a GFM table separator row like `|---|:--:|---|` (the line under
    /// the header). At least one cell, every cell only dashes/colons/space/pipe.
    /// `nonisolated` is load-bearing: the table scan runs on the cache-warming
    /// path (`warmRenderCaches`), which `ChatScreen.body` fires on a DETACHED
    /// utility task. `ChatBubbleContent` is a View, so it's MainActor-isolated
    /// by default and every other function on that path is already marked —
    /// these two were the gap, and off-main entry trapped in
    /// `swift_task_checkIsolatedSwift` (EXC_BREAKPOINT) the moment a
    /// transcript contained a table (the TF 208/209/213 launch crash-loop on
    /// the iOS 27 runtime; device crash logs). Pure string work
    /// over a parameter, no shared state, so off-main is safe.
    private nonisolated static func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-"), t.contains("|") else { return false }
        return t.range(of: "^\\|?\\s*:?-+:?\\s*(\\|\\s*:?-+:?\\s*)*\\|?$", options: .regularExpression) != nil
    }

    /// Split one `| a | b |` row into trimmed cells, dropping the empty cells the
    /// outer pipes create.
    private nonisolated static func tableCells(_ line: String) -> [String] {
        var cells = line.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if cells.first == "" { cells.removeFirst() }
        if cells.last == "" { cells.removeLast() }
        return cells
    }

    /// Parse assistant text into blocks. A table is a `|`-delimited header line
    /// immediately followed by a separator row, then zero+ data rows; everything
    /// else accumulates as text. Pure + linear, so a message with no table is one
    /// `.text` block (the caller's fast path).
    /// Cache of parsed blocks, same rationale + idiom as `markdownCache` above:
    /// the per-line table scan runs on every assistant bubble body eval (each
    /// scroll re-appearance); the result is a pure function of the immutable text.
    private final class MarkdownBlocksBox {
        let value: [MarkdownBlock]
        init(_ value: [MarkdownBlock]) { self.value = value }
    }

    private nonisolated(unsafe) static let markdownBlocksCache: NSCache<NSString, MarkdownBlocksBox> = {
        let cache = NSCache<NSString, MarkdownBlocksBox>()
        cache.countLimit = 400
        return cache
    }()

    nonisolated static func markdownBlocks(_ text: String) -> [MarkdownBlock] {
        let cacheKey = text as NSString
        if let cached = markdownBlocksCache.object(forKey: cacheKey) { return cached.value }
        let blocks = markdownBlocksUncached(text)
        markdownBlocksCache.setObject(MarkdownBlocksBox(blocks), forKey: cacheKey)
        return blocks
    }

    private nonisolated static func markdownBlocksUncached(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var textBuf: [String] = []
        func flushText() {
            if !textBuf.isEmpty { blocks.append(.text(textBuf.joined(separator: "\n")))
                textBuf = []
            }
        }
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let looksLikeRow = line.contains("|") && line.trimmingCharacters(in: .whitespaces).contains("|")
            if looksLikeRow, i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                flushText()
                let header = tableCells(line)
                var rows: [[String]] = []
                var j = i + 2
                while j < lines.count, lines[j].contains("|"), !lines[j].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(tableCells(lines[j]))
                    j += 1
                }
                blocks.append(.table(header: header, rows: rows))
                i = j
            } else {
                textBuf.append(line)
                i += 1
            }
        }
        flushText()
        return blocks
    }

    /// iMessage's jumbo-emoji rule: a message that is ONLY emoji, three or
    /// fewer, renders as bare oversized glyphs with no bubble at all — any
    /// accompanying text or a fourth emoji reverts to a normal bubble.
    /// Whitespace is ignored the way Messages ignores it ("👍 👍" still
    /// qualifies); an all-whitespace message does not.
    nonisolated static func isJumboEmoji(_ text: String) -> Bool {
        var count = 0
        for char in text {
            if char.isWhitespace { continue }
            guard isEmojiGrapheme(char) else { return false }
            count += 1
            if count > 3 { return false }
        }
        return count > 0
    }

    /// One grapheme that DRAWS as an emoji glyph. `isEmojiPresentation` on the
    /// first scalar covers emoji-default clusters and their compound forms
    /// (skin tones, ZWJ families, flags); a text-default scalar that is still
    /// `isEmoji` (digits, ©, ♥, keycap bases) counts only when a U+FE0F
    /// variation selector forces the emoji glyph — without that gate "3" or
    /// "©" would go jumbo.
    private nonisolated static func isEmojiGrapheme(_ char: Character) -> Bool {
        guard let first = char.unicodeScalars.first else { return false }
        if first.properties.isEmojiPresentation { return true }
        return first.properties.isEmoji && char.unicodeScalars.contains { $0.value == 0xFE0F }
    }

    /// The render gate every surface shares (bubble body + context-menu lift):
    /// emoji-only ≤3 AND not a voice message — a memo whose transcription is
    /// "👍" still renders as a waveform bubble, transcript inside.
    nonisolated static func rendersJumbo(_ message: ChatMessage) -> Bool {
        !message.isVoiceMessage && isJumboEmoji(message.text)
    }

    /// 3× the 17pt body type — Apple's stated jumbo scale. Shared with the
    /// UIKit lift preview so the raised glyphs are pixel-identical to the
    /// resting ones.
    nonisolated static let jumboEmojiPointSize: CGFloat = 51

    var body: some View {
        if Self.rendersJumbo(message) {
            // Jumbo emoji sit bare on the canvas — no insets, no fill, no
            // plate, no tail (iMessage drops the whole bubble, not just its
            // colour). Alignment against the bubble edge comes free from the
            // row's own leading/trailing anchoring.
            Text(message.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: Self.jumboEmojiPointSize))
                .accessibilityIdentifier("jumbo-emoji")
        } else {
            textStack
                // iMessage metrics (traced): ink insets 15.5 side / 13.7 top /
                // 10.8 below the descender; a tailed bubble's box includes the
                // tail's 7.46pt dip below the body line.
                .padding(.horizontal, 14)
                .padding(.top, 9.7)
                .padding(.bottom, tail ? 8.8 + IMessageBubbleShape.tailDip : 8.8)
                .background {
                    if message.isUser {
                        IMessageBubblePalette.outgoingFill()
                            .clipShape(IMessageBubbleShape(side: .outgoing, tail: tail))
                    }
                }
                .incomingBubblePlate(
                    in: IMessageBubbleShape(side: .incoming, tail: tail),
                    enabled: !message.isUser
                )
        }
    }

    private var textStack: some View {
        // The reply reference is NOT rendered here: a reply wears a small
        // "Replying to …" line above the bubble instead (see ChatRow).
        VStack(alignment: .leading, spacing: 6) {
            if message.isVoiceMessage {
                ChatVoiceNoteView(
                    audioURL: message.audioURL,
                    audioRemotePath: message.audioRemotePath,
                    duration: message.audioDuration ?? 0,
                    isUser: message.isUser
                )
                // iMessage-style: the transcription lives INSIDE the bubble,
                // under the waveform, in a softened cast of the bubble's ink —
                // a step smaller than message text, folding when it runs long.
                if !message.text.isEmpty {
                    // Capped to the waveform row's own width (play disc + bars
                    // + duration ≈ 190pt) so a long transcript wraps there and
                    // the memo bubble stays compact instead of stretching to
                    // the full bubble cap.
                    VoiceTranscriptCaption(text: message.text, isUser: message.isUser)
                        .frame(maxWidth: 190, alignment: .leading)
                }
            }
            if !message.text.isEmpty, !message.isVoiceMessage {
                // A voice message's transcription renders above, inside the
                // same bubble as its waveform — never as plain bubble text.
                let shownText = collapse == .collapsed
                    ? Self.collapsedPreview(message.text)
                    : message.text
                if message.isUser {
                    // User text is never reinterpreted — show what they typed.
                    bubbleText(Self.linkified(shownText, isUser: true))
                } else if isStreaming {
                    // Streaming: skip the two whole-text O(n) scanners (GFM table
                    // split + NSDataDetector bare-URL scan) that would otherwise
                    // re-run every token → O(n²) over the reply. Inline markdown and
                    // [markdown](links) still render live; tables become grids and
                    // bare URLs autolink in the single full pass the moment the
                    // stream ends (isStreaming flips false and this re-renders).
                    bubbleText(Self.markdownRenderedFast(message.text))
                } else {
                    // Assistant text is markdown. Split into blocks so a GFM table
                    // (routine in deep-task comparison results) renders as a real
                    // grid instead of raw pipes; text blocks keep inline markdown.
                    let blocks = Self.markdownBlocks(shownText)
                    if blocks.count == 1, case let .text(only) = blocks[0] {
                        bubbleText(Self.markdownRendered(only)) // fast path: no table
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                                switch block {
                                case let .text(t):
                                    if !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        bubbleText(Self.markdownRendered(t))
                                    }
                                case let .table(header, rows):
                                    MarkdownTableView(header: header, rows: rows)
                                }
                            }
                        }
                    }
                }
                if collapse != .none {
                    collapseToggle
                }
            }
        }
    }
}

/// Renders a parsed GFM table as a real grid inside an assistant bubble. Header
/// row emphasized, hairline row dividers, and horizontal scroll when the table is
/// wider than the bubble (comparison tables routinely are) so it never forces the
/// bubble past the screen. Inline markdown inside cells (bold, links) is honored.
struct MarkdownTableView: View {
    let header: [String]
    let rows: [[String]]

    /// Column count is the widest row, so a ragged row still lays out.
    private var columnCount: Int {
        max(header.count, rows.map(\.count).max() ?? 0)
    }

    private func cell(_ cells: [String], _ col: Int) -> AttributedString {
        guard col < cells.count else { return AttributedString("") }
        return ChatBubbleContent.markdownRendered(cells[col])
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    ForEach(0 ..< columnCount, id: \.self) { col in
                        Text(cell(header, col))
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(DS.Palette.inkBlack)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider().gridCellColumns(columnCount)
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    GridRow {
                        ForEach(0 ..< columnCount, id: \.self) { col in
                            Text(cell(row, col))
                                .font(.system(size: 14.5, weight: .regular))
                                .foregroundStyle(DS.Palette.inkBlack.opacity(0.88))
                                .tint(Color(light: 0x097FFF, dark: 0x409CFF))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if idx < rows.count - 1 {
                        Divider().opacity(0.35).gridCellColumns(columnCount)
                    }
                }
            }
            .padding(.vertical, 2)
            .background(TableScrollPanClaim())
        }
    }
}

#if canImport(UIKit)
    /// Sets `HorizontalSwipeClaim` while the table's own horizontal scroll pan owns
    /// the touch. The root Home⇄Chat pager is a SwiftUI drag attached with
    /// `.simultaneousGesture`, so this scroll view's UIKit pan can't exclude it the
    /// normal way — without the claim, scrubbing a wide table ALSO dragged the page
    /// (on Chat, any rightward pull pages back to Home). The flag is the same
    /// arbitration the reject swipe and timestamp reveal use; the pager reads it
    /// every drag tick and stands down for the rest of the touch.
    ///
    /// Re-landed from, whose original commit also reverted this file by
    /// accident (see). This is that PR's actual fix, on top of current main.
    private struct TableScrollPanClaim: UIViewRepresentable {
        final class ClaimView: UIView {
            private weak var observedPan: UIPanGestureRecognizer?

            override func didMoveToWindow() {
                super.didMoveToWindow()
                // Gesture recognizers retain their targets: detach on unmount or a
                // recycled table row would keep this view (and a stale claim path)
                // alive on the scroll view's pan.
                if window == nil {
                    observedPan?.removeTarget(self, action: nil)
                    observedPan = nil
                } else {
                    attachIfNeeded()
                }
            }

            override func layoutSubviews() {
                super.layoutSubviews()
                attachIfNeeded()
            }

            override func point(inside _: CGPoint, with _: UIEvent?) -> Bool {
                false
            }

            private func attachIfNeeded() {
                guard observedPan == nil else { return }
                // First UIScrollView ancestor is the table's own horizontal scroller
                // (this view lives inside its content), never the transcript.
                var ancestor = superview
                while let view = ancestor, !(view is UIScrollView) {
                    ancestor = view.superview
                }
                guard let scrollView = ancestor as? UIScrollView else { return }
                scrollView.panGestureRecognizer.addTarget(self, action: #selector(panChanged(_:)))
                observedPan = scrollView.panGestureRecognizer
            }

            @objc private func panChanged(_ pan: UIPanGestureRecognizer) {
                switch pan.state {
                case .began, .changed:
                    HorizontalSwipeClaim.isActive = true
                case .ended, .cancelled, .failed:
                    // Deferred a runloop turn: the pager's `onEnded` races this
                    // `.ended` on the same touch-up and must still see the claim.
                    DispatchQueue.main.async {
                        HorizontalSwipeClaim.isActive = false
                    }
                default:
                    break
                }
            }
        }

        func makeUIView(context _: Context) -> ClaimView {
            ClaimView()
        }

        func updateUIView(_: ClaimView, context _: Context) {}
    }
#endif

/// A photo attached to a chat message, rendered as its own rounded tile ABOVE the
/// text bubble (aligned to the bubble's side by the enclosing column). Matches the
/// bubble's corner language so it reads as one message, not a foreign element.
struct ChatImageTile: View {
    let data: Data
    var side: IMessageBubbleShape.Side = .outgoing
    var tail = false

    var body: some View {
        ChatImageData(data: data, targetSide: chatPhotoTileSide)
            .scaledToFill()
            // Tail carved from the photo itself, like an iMessage picture —
            // the tailed frame includes the dip below the body line.
            .frame(width: 210, height: 210 + (tail ? IMessageBubbleShape.tailDip : 0))
            .clipShape(IMessageBubbleShape(side: side, tail: tail))
            .compositingGroup()
            .shadow(color: DS.Palette.shadow.opacity(0.06), radius: 4, x: 0, y: 1)
    }
}

/// A document the user attached to a message (a picked PDF/CSV, or an oversized
/// paste the composer folded into a "Pasted" attachment), rendered as its own
/// compact tile ABOVE the text bubble — same attach semantics as a photo, same
/// outgoing bubble language, so it reads as part of the message.
struct ChatFileTile: View {
    let filename: String
    var tail = false
    /// Tap opens the attachment's content (reader for pasted text, QuickLook
    /// for picked docs). Default no-op keeps preview rigs tap-dead.
    /// `.onTapGesture`, NOT a Button: the transcript's ancestor tap gesture
    /// (menu/keyboard dismiss, ChatScreen ~:506) cancels child Button touches
    /// — the photo tiles' pattern, proven in this exact container.
    var onTap: () -> Void = {}

    private var isPastedText: Bool { filename == ChatMessage.pastedAttachmentName }

    var body: some View {
        tile
            .onTapGesture {
                guard DSInteractionGate.allowsTap else { return }
                onTap()
            }
            .accessibilityIdentifier("chat-file-tile")
    }

    private var tile: some View {
        HStack(spacing: 10) {
            fileGlyph
            VStack(alignment: .leading, spacing: 1) {
                Text(filename)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                // "Pasted" says it all on one line; real files get a quiet
                // kind label under the name.
                if !isPastedText {
                    Text(FileTypeBadge(filename: filename).kindLabel)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, tail ? 11 + IMessageBubbleShape.tailDip : 11)
        .background {
            IMessageBubblePalette.outgoingFill()
                .clipShape(IMessageBubbleShape(side: .outgoing, tail: tail))
        }
    }

    /// The type identity up front: pasted text keeps its clipboard glyph inline;
    /// a real file gets the shared extension badge — tinted glyph on a white
    /// rounded tile so PDF reads red, sheets green, exactly like the delivered
    /// FileCardView — instead of the old anonymous white doc.fill.
    @ViewBuilder private var fileGlyph: some View {
        if isPastedText {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
        } else {
            let badge = FileTypeBadge(filename: filename)
            Image(systemName: badge.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(badge.tint)
                .frame(width: 34, height: 34)
                .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}

/// Same tile as ChatImageTile, but for a photo the user uploaded earlier that is
/// now served from the backend (`/v1/assets/<id>`) — a reloaded bubble whose
/// local JPEG is gone. Loads through the authenticated, cached image pipeline.
struct ChatRemoteImageTile: View {
    let path: String
    var side: IMessageBubbleShape.Side = .outgoing
    var tail = false

    var body: some View {
        Group {
            if let localId = PhotoLibraryImageView.localIdentifier(fromAssetPath: path) {
                // A device-library match (search_photo_gallery `ph:` ref) —
                // pixels come straight from Photos, not the backend.
                PhotoLibraryImageView(localIdentifier: localId, targetSide: 210)
            } else {
                CachedRemoteImage(url: path, fadeIn: true, targetSide: chatPhotoTileSide) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    // A photo is landing here — shimmer, not a dead grey block.
                    ShimmerTile()
                }
            }
        }
        .frame(width: 210, height: 210 + (tail ? IMessageBubbleShape.tailDip : 0))
        .clipped()
        .clipShape(IMessageBubbleShape(side: side, tail: tail))
        .compositingGroup()
        .shadow(color: DS.Palette.shadow.opacity(0.06), radius: 4, x: 0, y: 1)
    }
}

/// Two or more photos on one message, collapsed into an iMessage-style deck:
/// the top photo full-size in the bubble language (tail and all), the next
/// one or two FANNED out behind it — rotated like a deck of cards spread with
/// a thumb, toward the transcript's open side — and an "N Photos" pill below.
/// ONE tap target — the fullscreen viewer pages through the whole set from
/// the photo on top.
///
/// iMessage-style scrub: a horizontal swipe on the deck flips through the
/// photos in place — the top card rides the finger and, past the commit
/// distance, tucks behind the pile while the next print surfaces (dragging
/// toward the fan advances; toward the screen edge goes back, wrapping like a
/// real deck). The swipe is the same UIKit pan the timestamp reveal and the
/// Home cards use, at a higher priority tier, so a scrub that starts on the
/// deck beats the transcript-wide reveal and never drags the Home⇄Chat pager.
struct ChatPhotoStackTile: View {
    let photos: [ChatViewerPhoto] // count >= 2 (single photos use the plain tiles)
    var side: IMessageBubbleShape.Side = .outgoing
    var tail = false
    /// Index of the photo on top — owned by the row, so tap-to-open, the
    /// zoom-transition source, and the context menu all follow the scrub.
    @Binding var topIndex: Int

    /// Live finger translation while a scrub owns the touch.
    @State private var dragX: CGFloat = 0
    /// Keys this deck's no-page zone (the root pager refuses to page from a
    /// touch that starts on a strip that owns its own horizontal drag).
    @State private var swipeZoneID = UUID()

    private static let tileSide: CGFloat = chatPhotoTileSide
    /// Finger travel that commits a flip; release short of it springs back.
    private static let commitDistance: CGFloat = 64

    private var count: Int { photos.count }
    private var peekCount: Int { min(count - 1, 2) }
    /// Fan away from the bubble's screen edge, into the transcript's open
    /// side: incoming decks (left-aligned) fan right, outgoing fan left.
    private var fanDirection: CGFloat { side == .incoming ? 1 : -1 }
    /// `topIndex` folded into the photo array — a mid-stream sibling arriving
    /// (or a row rebuilding with fewer photos) must never index out of range.
    private var safeTop: Int { photos.isEmpty ? 0 : ((topIndex % count) + count) % count }

    /// The rendered window of the deck: the top card plus the one or two
    /// peeking behind it, each tagged with its stable index into `photos` (the
    /// ForEach key — ids would collide if the same photo rode a message twice).
    private var window: [(index: Int, depth: Int)] {
        (0 ... peekCount).map { depth in ((safeTop + depth) % count, depth) }
    }

    var body: some View {
        // Count rides BELOW the deck as a quiet caption (nicer than
        // a pill on the photo), anchored to the deck's screen-edge side — the
        // fan spills toward the open side, so the label never sits under it.
        VStack(alignment: side == .incoming ? .leading : .trailing, spacing: 0) {
            deck
                // The fanned corners draw outside the top tile's frame;
                // reserve the vertical spill so neighboring rows never paint
                // over them. The sideways spill stays unreserved on purpose —
                // it reaches into the transcript's open side, like iMessage's
                // spread.
                .padding(.vertical, 14)
            Text(safeTop == 0 ? "\(count) Photos" : "\(safeTop + 1) of \(count)")
                .font(.system(size: 11, weight: .medium))
                .tracking(-0.1)
                .foregroundStyle(DS.Palette.placeholder)
                .padding(.horizontal, 4)
                // Hug the deck: pull back most of the spill headroom so the
                // caption reads as the stack's underline, not a stray row.
                .padding(.top, -8)
                .animation(nil, value: safeTop)
        }
        #if canImport(UIKit)
        .overlay {
            // Both directions are claimed (forward AND back), so the pan sits
            // above the timestamp reveal's tier; page-edge stripes still
            // belong to the pager per the shared contract.
            HorizontalSwipeGestureAttachment(
                edgeSwipeWidth: 0,
                usesPageEdgeStripes: true,
                locksVerticalScroll: true,
                priority: 1,
                onChanged: { value in
                    // Warm the Taptic Engine at pickup so the commit tick
                    // can't be dropped by a cold start.
                    if dragX == 0, value.width != 0 { DSHaptics.prepareTap(.light) }
                    dragX = value.width
                },
                onEndedVelocity: { translation, velocity in
                    settleScrub(translation: translation, velocityX: velocity.width)
                }
            )
        }
        // A slow or diagonal scrub never reaches the pan's recognition
        // velocity — the no-page zone keeps even those touches off the pager.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            SuggestionSwipeZones.update(swipeZoneID, frame: frame)
        }
        .onDisappear { SuggestionSwipeZones.update(swipeZoneID, frame: nil) }
        #endif
    }

    /// One ZStack, every card keyed by its photo's index — a committed flip
    /// re-slots the same identities, so SwiftUI slides each print between fan
    /// positions instead of cross-fading two unrelated trees.
    private var deck: some View {
        ZStack {
            ForEach(window, id: \.index) { entry in
                card(photoIndex: entry.index, depth: entry.depth)
                    .zIndex(Double(-entry.depth))
                    .transition(.opacity)
            }
        }
        .frame(
            width: Self.tileSide,
            height: Self.tileSide + (tail ? IMessageBubbleShape.tailDip : 0)
        )
    }

    @ViewBuilder
    private func card(photoIndex: Int, depth: Int) -> some View {
        if depth == 0 {
            // Card-table pickup: the moment a scrub owns the touch the top
            // card LIFTS — grows a touch, its shadow deepens and drops lower —
            // and it rides a slight upward arc as it travels, pivoting around
            // its bottom edge like a card held by its lower half. Flat
            // on-a-rail sliding read as UI, not as a card — "card and gambling apps are better").
            let lifted = dragX != 0
            photoContent(photos[photoIndex])
                .frame(
                    width: Self.tileSide,
                    height: Self.tileSide + (tail ? IMessageBubbleShape.tailDip : 0)
                )
                .clipped()
                .clipShape(IMessageBubbleShape(side: side, tail: tail))
                .compositingGroup()
                .shadow(
                    color: DS.Palette.shadow.opacity(lifted ? 0.22 : 0.12),
                    radius: lifted ? 13 : 6, x: 0, y: lifted ? 9 : 2
                )
                .scaleEffect(lifted ? 1.045 : 1)
                // The pickup/drop transition only — parked ABOVE the drag
                // transforms so the per-sample offset/rotation stay on the
                // gesture (and on settleScrub's thrown spring), not on this.
                .animation(.snappy(duration: 0.18), value: lifted)
                .offset(x: dragX, y: -min(abs(dragX) * 0.12, 14))
                .rotationEffect(.degrees(Double(dragX / Self.tileSide) * 12), anchor: .bottom)
        } else {
            let shape = RoundedRectangle(
                cornerRadius: IMessageBubbleShape.cornerRadius, style: .continuous
            )
            // A forward scrub walks each buried print toward the slot in
            // front of it, so the deck visibly deals as the finger moves.
            let seat = max(CGFloat(depth) - scrubProgress, 0)
            photoContent(photos[photoIndex])
                .frame(width: Self.tileSide, height: Self.tileSide)
                .clipped()
                .clipShape(shape)
                .compositingGroup()
                .shadow(color: DS.Palette.shadow.opacity(0.1), radius: 4, x: 0, y: 1)
                // Dim ABOVE the shadowed composite (same pixels — the photo is
                // opaque, so the shadow's alpha shape doesn't change): inside
                // the compositingGroup, its per-sample opacity change forced
                // the shadow's blur pass to re-render on every scrub frame.
                // Out here a drag frame is transforms + one overlay opacity.
                .overlay(shape.fill(.black.opacity(buriedDim(seat))))
                .scaleEffect(1 - 0.04 * seat)
                .rotationEffect(.degrees(Double(fanDirection) * buriedTilt(seat)))
                .offset(x: fanDirection * buriedShift(seat), y: -3 * seat)
        }
    }

    /// How far a forward scrub has dealt the deck, 0...1 — buried prints
    /// interpolate one slot forward as the top card rides out. A backward
    /// scrub leaves them seated (the previous photo wraps around on commit).
    private var scrubProgress: CGFloat {
        guard dragX * fanDirection > 0 else { return 0 }
        return min(abs(dragX) / Self.commitDistance, 1)
    }

    // Continuous fan-slot curves through the resting depths (0 → seated top,
    // 1 → first print at 22pt/7.5°/0.18, 2 → second at 34pt/12°/0.32) so a
    // print mid-deal is always on the path between its two slots.
    private func buriedShift(_ seat: CGFloat) -> CGFloat {
        seat <= 1 ? 22 * seat : 22 + 12 * (seat - 1)
    }

    private func buriedTilt(_ seat: CGFloat) -> Double {
        Double(seat <= 1 ? 7.5 * seat : 7.5 + 4.5 * (seat - 1))
    }

    private func buriedDim(_ seat: CGFloat) -> Double {
        Double(seat <= 1 ? 0.18 * seat : 0.18 + 0.14 * (seat - 1))
    }

    /// Touch-up: commit the flip when the finger traveled far enough OR threw
    /// the card — a fast short flick deals it, card-table style, where the
    /// old distance-only gate made every flip a full 64pt haul. Toward the
    /// fan is the next photo, toward the screen edge the previous (wrapping,
    /// like cycling a real deck); short slow releases spring the card home.
    private func settleScrub(translation: CGSize, velocityX: CGFloat) {
        let dx = translation.width
        let flicked = abs(velocityX) > 500 && velocityX * dx > 0 && abs(dx) > 16
        guard count >= 2, abs(dx) >= Self.commitDistance || flicked else {
            withAnimation(releaseSpring(velocityX: velocityX)) { dragX = 0 }
            return
        }
        let step = dx * fanDirection > 0 ? 1 : -1
        // The deal's click — same light tick a chip toss would earn.
        DSHaptics.tap(.light)
        withAnimation(releaseSpring(velocityX: velocityX)) {
            topIndex = ((safeTop + step) % count + count) % count
            dragX = 0
        }
    }

    /// The release animation, seeded with the finger's velocity: a thrown
    /// card KEEPS MOVING at finger speed — overshooting outward before the
    /// spring tucks it home — instead of restarting from rest on a rail.
    /// initialVelocity is in per-unit-distance terms (finger pts/s over the
    /// dragX → 0 delta). ~0.77 damping leaves the small bounce a dealt card
    /// deserves.
    private func releaseSpring(velocityX: CGFloat) -> Animation {
        guard abs(dragX) > 1 else { return .spring(response: 0.38, dampingFraction: 0.78) }
        return .interpolatingSpring(
            mass: 1, stiffness: 240, damping: 24,
            initialVelocity: velocityX / -dragX
        )
    }

    /// Raw photo pixels for one entry — same sources as the single tiles
    /// (in-memory bytes, device-library `ph:` refs, or the asset pipeline).
    @ViewBuilder
    private func photoContent(_ photo: ChatViewerPhoto) -> some View {
        switch photo {
        case let .local(data):
            ChatImageData(data: data, targetSide: Self.tileSide)
                .scaledToFill()
        case let .remote(path):
            if let localId = PhotoLibraryImageView.localIdentifier(fromAssetPath: path) {
                PhotoLibraryImageView(localIdentifier: localId, targetSide: Self.tileSide)
            } else {
                CachedRemoteImage(url: path, fadeIn: true, targetSide: Self.tileSide) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ShimmerTile()
                }
            }
        }
    }
}

/// Identifiable wrapper so a tapped photo can drive the fullscreen viewer via
/// `.fullScreenCover(item:)`. Carries the message's full photo set (remote
/// asset paths on a reloaded bubble, in-memory bytes on a fresh send) so the
/// viewer can page between siblings; the tapped photo keys both the cover
/// identity and the zoom-transition source.
struct PhotoViewerTarget: Identifiable {
    let photos: [ChatViewerPhoto]
    let initialIndex: Int
    var photo: ChatViewerPhoto { photos[initialIndex] }
    var id: String { photo.id }
}

#if canImport(UIKit)

    /// Live map of on-screen bubbles to their REAL (UIKit) frames, fed by one
    /// invisible anchor view per text bubble. The SEND MORPH reads it to
    /// retarget a flight onto the actual landing bubble mid-air — UIKit frames
    /// are maintained by the system (zero per-scroll cost) and don't inherit
    /// SwiftUI's layout-vs-drawn quirks. (The long-press menu no longer needs
    /// it: the system context menu hit-tests the pressed bubble itself.)
    @MainActor
    final class ChatBubbleAnchorRegistry {
        static let shared = ChatBubbleAnchorRegistry()

        private struct Anchor {
            weak var view: UIView?
        }

        private var anchors: [UUID: Anchor] = [:]

        func register(_ id: UUID, view: UIView) {
            anchors[id] = Anchor(view: view)
            // Rows the LazyVStack dropped unregister via didMoveToWindow; a
            // dead weak ref only survives if the view deallocated without
            // that callback, so sweep opportunistically to stay small.
            anchors = anchors.filter { $0.value.view != nil }
        }

        func unregister(_ id: UUID, view: UIView) {
            guard anchors[id]?.view === view || anchors[id]?.view == nil else { return }
            anchors[id] = nil
        }

        /// The registered bubble's live window-space frame — the send morph
        /// reads it to retarget a flight onto the REAL landing bubble (the
        /// computed destination can be a few points off per device width).
        func windowFrame(for id: UUID) -> CGRect? {
            guard let view = anchors[id]?.view, view.window != nil else { return nil }
            return view.convert(view.bounds, to: nil)
        }
    }

    /// The invisible per-bubble anchor: sized by SwiftUI to the bubble's frame,
    /// never hit-tests, and (un)registers itself as rows enter/leave the window.
    struct ChatBubbleAnchorAttachment: UIViewRepresentable {
        let id: UUID

        func makeUIView(context _: Context) -> AnchorView {
            let view = AnchorView()
            view.messageID = id
            return view
        }

        func updateUIView(_ view: AnchorView, context _: Context) {
            view.messageID = id
        }

        final class AnchorView: UIView {
            var messageID: UUID? {
                didSet {
                    guard oldValue != messageID else { return }
                    if let oldValue { ChatBubbleAnchorRegistry.shared.unregister(oldValue, view: self) }
                    registerIfNeeded()
                }
            }

            override func didMoveToWindow() {
                super.didMoveToWindow()
                if window == nil, let messageID {
                    ChatBubbleAnchorRegistry.shared.unregister(messageID, view: self)
                } else {
                    registerIfNeeded()
                }
            }

            override func point(inside _: CGPoint, with _: UIEvent?) -> Bool { false }

            private func registerIfNeeded() {
                guard window != nil, let messageID else { return }
                ChatBubbleAnchorRegistry.shared.register(messageID, view: self)
            }
        }
    }

    /// Watchdog for the "blank transcript after a long send" failure: on a
    /// long send, SwiftUI's scroll-content host sometimes loses its drawn
    /// content layers in the update's crossfade — geometry and offset stay
    /// correct, but nothing is on screen until a finger drag forces a redraw
    /// (observed ~40% of 20k-char sends with the keyboard up; every
    /// structural avoidance failed — see PR). This attachment does what the
    /// finger does: it watches the host's real CALayer tree and, when no
    /// visible content layer intersects the viewport, re-drives the scroll
    /// machinery — escalating to an identity rebuild — until content exists
    /// again. Same enclosing-scroll-view walk as the touch recorder. Under
    /// CHAT_QA_SCROLL_PROBE=1 it also publishes its census through an
    /// accessibility element for the ChatLongSendShot rig.
    struct TranscriptHealAttachment: UIViewRepresentable {
        func makeUIView(context _: Context) -> TranscriptHealView {
            TranscriptHealView()
        }

        func updateUIView(_ view: TranscriptHealView, context _: Context) {
            view.startIfNeeded()
        }
    }

    // (The UIKit deep-jump (`jumpNote`) and send-follower (`followNote`)
    // limbs are GONE — Phase 2 mount flip. The jump existed for the lazy
    // stack dropping bottom rows deep in history (proxy.scrollTo silently
    // no-ops on a dropped id, L7); the bounded eager tail never unmounts a
    // rendered row, so scrollToBottom's ID pin + staged correctives now
    // cover every depth (ChevronJump verifies). The follower's observer was
    // never registered — dead code since introduction; the send pin in
    // onChange(messages.count) is its working replacement.)
    final class TranscriptHealView: UIView {
        private var timer: Timer?

        private func enclosingScrollView() -> UIScrollView? {
            var candidate = superview
            while let view = candidate {
                if let scroll = view as? UIScrollView, !scroll.isPagingEnabled { return scroll }
                candidate = view.superview
            }
            return nil
        }

        static func layerCount(_ layer: CALayer) -> Int {
            1 + (layer.sublayers ?? []).reduce(0) { $0 + layerCount($1) }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                timer?.invalidate()
                timer = nil
            } else {
                startIfNeeded()
            }
        }

        override func point(inside _: CGPoint, with _: UIEvent?) -> Bool { false }

        /// Set when the chronic-false-positive cap trips — `startIfNeeded`
        /// re-arms the timer on every SwiftUI update cycle, so the disarm
        /// must latch here or the next body eval quietly resurrects the
        /// watchdog it just retired.
        private var disarmed = false

        func startIfNeeded() {
            guard window != nil, timer == nil, !disarmed else { return }
            // The census numbers are exposed through accessibility ONLY for
            // the QA rig — production keeps the a11y tree clean.
            if ProcessInfo.processInfo.environment["CHAT_QA_SCROLL_PROBE"] == "1" {
                isAccessibilityElement = true
                accessibilityIdentifier = "qa-scroll-probe"
                accessibilityLabel = "probe-pending"
            }
            let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }

        private var healAttempts = 0
        private var healsSucceeded = 0
        private var lastHealStage = 0
        /// True from the first heal of an episode until the census reads
        /// healthy again — one "ok" per episode, not per attempt.
        private var inEpisode = false
        /// Ticks to sit out after a rebuild: back-to-back rebuilds land while
        /// the previous one is still measuring (contentSize collapses to a
        /// fresh estimate under a stale offset) and thrash instead of healing.
        private var healGraceTicks = 0
        /// Consecutive dead census reads. A single dead read can be a page
        /// swipe or content update caught mid-frame; the real blank persists
        /// for seconds. Healing starts on the second read, never the first.
        private var deadStreak = 0
        /// Rebuild escalations in the current episode — the circuit breaker's
        /// counter. A blank three rebuilds couldn't fix won't yield to a
        /// fourth, and a census FALSE positive (content on screen the census
        /// can't see) would otherwise flick the transcript forever: the
        /// "possessed transcript" loop where the chat bobs up and down at
        /// rest until the app is killed.
        private var rebuildsThisEpisode = 0
        /// Ticks to sit out after the breaker trips before re-arming.
        private var backoffTicks = 0
        /// Breaker trips with NOTHING healed in between. The 30s backoff
        /// re-arms forever, so a CHRONIC census false positive (content the
        /// census can't see — a layer-tree shape it mispredicts) replays its
        /// flick + 3 rebuilds every half minute for the rest of the session:
        /// the "possessed transcript", just on a slower clock. Two straight
        /// tripped episodes with zero successes means the census is the
        /// disease, not the cure — disarm until next launch. A real blank
        /// that six rebuilds couldn't fix was never going to yield to the
        /// seventh; a HEALED episode resets the count, so a device where the
        /// watchdog genuinely works keeps it for life.
        private var trippedEpisodesRunning = 0
        /// The scroll view's bottom content inset at the last census tick —
        /// the keyboard's share arrives here, so a delta between ticks means
        /// a keyboard ride (or another safe-area move) is in flight.
        private var lastBottomInset: CGFloat = 0

        private static let healLog = Logger(subsystem: "persona.chatheal", category: "census")

        /// The blank's layer signature, both flavors: after a long send the
        /// content host either (A) holds ONLY the full-height attachment
        /// overlays — SwiftUI's drawn content layers were torn down in the
        /// send's crossfade and never rebuilt — or (B) still holds content
        /// layers but the visible-window layer is HIDDEN (opacity 0), left
        /// mid-crossfade. Either way: no visible content layer intersects the
        /// viewport while real content exists.
        private func contentLayersDead(_ sv: UIScrollView) -> Bool {
            guard let hostLayer = sv.subviews.first?.layer else { return false }
            guard sv.contentSize.height > 2000 else { return false }
            let visLo = sv.contentOffset.y
            let visHi = visLo + sv.bounds.height
            for sub in hostLayer.sublayers ?? [] {
                let f = sub.frame
                guard f.height > 100, f.height < sv.contentSize.height - 1 else { continue } // skip overlays
                if f.maxY > visLo, f.minY < visHi, !sub.isHidden, sub.opacity > 0.01 {
                    return false // a real content layer is visibly on screen
                }
            }
            return true
        }

        private var healLink: CADisplayLink?
        private var healFrame = 0
        private weak var healTarget: UIScrollView?

        /// OBSERVE-ONLY (): the census keeps walking and logging,
        /// but heals no longer touch the transcript unless CHAT_HEAL_ACT=1.
        /// The disease this watchdog was built for —'s blank transcript
        /// after a 20k-char send, ~40% per send on the old lazy-stack mount —
        /// did NOT reproduce under the post- eager-tail transcript
        /// (MAIN_CHAT_QA=longsends: 8 worst-case sends, keyboard up, zero
        /// blanks, zero census episodes). Meanwhile the heal's own actions
        /// (48pt flick, identity rebuild) ARE autonomous transcript motion —
        /// the standing suspect in every "possessed transcript" round. So the
        /// default flips: watch and report (`persona.chatheal` episode logs =
        /// field evidence either way), act only when QA asks. If a field
        /// blank ever surfaces again, the log shows the would-have-healed
        /// episode and the flag turns the cure back on for that repro.
        private static let actsEnabled =
            ProcessInfo.processInfo.environment["CHAT_HEAL_ACT"] == "1"

        /// Re-drive the scroll machinery the way a finger does. A single
        /// setContentOffset collapses to ONE rendered step (only the final
        /// value survives the transaction); a drag delivers many small offsets
        /// across many display-link frames — and a drag ALWAYS repairs the
        /// dead state — so the heal walks the offset frame by frame.
        private func heal(_ sv: UIScrollView, stage: Int) {
            guard Self.actsEnabled else {
                Self.healLog.log("observe-only: census dead, would heal at stage \(stage)")
                return
            }
            if stage == 1 {
                guard healLink == nil else { return }
                healTarget = sv
                healFrame = 0
                let link = CADisplayLink(target: self, selector: #selector(healStep))
                link.add(to: .main, forMode: .common)
                healLink = link
            } else {
                // Stepped scroll didn't bring the layers back: ask SwiftUI to
                // rebuild the content subtree by identity. The rebuild re-rolls
                // the same race, so the census keeps escalating until layers
                // actually exist.
                NotificationCenter.default.post(name: Self.rebuildNote, object: nil)
            }
        }

        @objc private func healStep() {
            guard let sv = healTarget, healFrame < 14 else {
                healLink?.invalidate()
                healLink = nil
                return
            }
            healFrame += 1
            // The resting bottom offset INCLUDING the keyboard's share of the
            // content inset. Without it, a heal fired with the keyboard up
            // "repaired" to a keyboard-less bottom — teleporting a reader who
            // was pinned at the true bottom ~a keyboard-height UP and parking
            // them there ("scrolled all the way down with
            // the keyboard focused, it randomly scrolls back up").
            let bottom = max(0, sv.contentSize.height - sv.bounds.height + sv.adjustedContentInset.bottom)
            // Ease 48pt up and back down over 14 frames, like a small flick.
            let phase = CGFloat(healFrame) / 14
            let lift = sin(phase * .pi) * 48
            sv.setContentOffset(CGPoint(x: 0, y: max(0, bottom - lift)), animated: false)
        }

        static let rebuildNote = Notification.Name("persona.chat.transcript.rebuild")

        private func sample() {
            var candidate = superview
            var sv: UIScrollView?
            while let view = candidate {
                if let scroll = view as? UIScrollView, !scroll.isPagingEnabled { sv = scroll
                    break
                }
                candidate = view.superview
            }
            guard let sv else {
                if isAccessibilityElement { accessibilityLabel = "probe-no-scrollview" }
                return
            }
            // QA (CHAT_QA_GEOMETRY_LOG=1): stream the raw scroll geometry so a
            // rig can see WHICH quantity oscillates (offset vs content height)
            // without a11y round-trips. Rides this tick; no prod cost.
            if ProcessInfo.processInfo.environment["CHAT_QA_GEOMETRY_LOG"] == "1" {
                Self.healLog
                    .log(
                        "geo off=\(sv.contentOffset.y, format: .fixed(precision: 1)) contentH=\(sv.contentSize.height, format: .fixed(precision: 1)) boundsH=\(sv.bounds.height, format: .fixed(precision: 1))"
                    )
            }
            // A keyboard ride is a live animated resize: the safe-area inset
            // sweeps for ~0.3-0.5s, layers legitimately churn, and a census
            // read mid-ride can call a healthy transcript dead for the two
            // consecutive ticks that arm a heal — whose scroll-nudge (or
            // worse, full rebuild) would then land INSIDE the transition.
            // Same standdown as a live finger: judge only settled geometry.
            let bottomInset = sv.adjustedContentInset.bottom
            let insetMoving = abs(bottomInset - lastBottomInset) > 0.5
            lastBottomInset = bottomInset

            // A finger on the transcript repairs the dead state by itself —
            // that is the whole premise of the flick — and a heal's offsets
            // would fight the touch. Judge only a resting transcript.
            if sv.isTracking || sv.isDragging || sv.isDecelerating || insetMoving {
                deadStreak = 0
            }
            // In the Home⇄Chat pager this view stays installed (window is
            // still set) while the chat page sits a full screen away — where
            // SwiftUI is free to cull the very layers the census counts.
            // Healing there is all cost: it scrolls and rebuilds a transcript
            // nobody can see, and strands the episode machine mid-escalation
            // for the swipe back. Judge only what is actually on screen.
            else if let window, !window.bounds.intersects(convert(bounds, to: window)) {
                deadStreak = 0
            } else if backoffTicks > 0 {
                backoffTicks -= 1
            } else if healGraceTicks > 0 {
                healGraceTicks -= 1
            } else if contentLayersDead(sv) {
                deadStreak += 1
                if deadStreak >= 2 {
                    // Flick once; if the next tick still reads dead, rebuild —
                    // then give the rebuild a settle window before judging it.
                    if !inEpisode { Self.healLog.log("episode start: census dead at rest") }
                    inEpisode = true
                    lastHealStage = lastHealStage == 0 ? 1 : 3
                    healAttempts += 1
                    heal(sv, stage: lastHealStage)
                    if lastHealStage == 3 {
                        healGraceTicks = 4
                        lastHealStage = 0
                        rebuildsThisEpisode += 1
                        if rebuildsThisEpisode >= 3 {
                            trippedEpisodesRunning += 1
                            if trippedEpisodesRunning >= 2 {
                                Self.healLog
                                    .error(
                                        "census dead through \(self.trippedEpisodesRunning) tripped episodes with zero heals — chronic false positive; watchdog disarmed for this session"
                                    )
                                disarmed = true
                                timer?.invalidate()
                                timer = nil
                                return
                            }
                            Self.healLog
                                .error(
                                    "census still dead after \(self.rebuildsThisEpisode) rebuilds — likely a census false positive; backing off 30s"
                                )
                            backoffTicks = 120
                            inEpisode = false
                            rebuildsThisEpisode = 0
                            deadStreak = 0
                        }
                    }
                }
            } else {
                if inEpisode {
                    healsSucceeded += 1
                    // A heal that WORKED is proof the census can see this
                    // transcript's layers — the chronic-false-positive count
                    // starts over.
                    trippedEpisodesRunning = 0
                    Self.healLog.log("episode healed after \(self.healAttempts) attempts total")
                }
                inEpisode = false
                lastHealStage = 0
                deadStreak = 0
                rebuildsThisEpisode = 0
            }
            guard isAccessibilityElement else { return }
            // QA rig only: the census, human-readable. SwiftUI draws rows into
            // the host's LAYER tree, not as subviews — blank vs healthy shows
            // up as which big layers exist and whether any is visibly inside
            // the window.
            let host = sv.subviews.first
            let hostLayers = host.map { Self.layerCount($0.layer) } ?? -1
            let visLo = sv.contentOffset.y, visHi = sv.contentOffset.y + sv.bounds.height
            var bigDesc = ""
            var bigTotal = 0, bigVisible = 0
            for sub in host?.layer.sublayers ?? [] where sub.frame.height > 100 {
                bigTotal += 1
                let visible = sub.frame.maxY > visLo && sub.frame.minY < visHi && !sub.isHidden && sub.opacity > 0.01
                if visible { bigVisible += 1 }
                if bigDesc.count < 120 {
                    bigDesc += String(format: "[y=%.0f..%.0f v=%d]", sub.frame.minY, sub.frame.maxY, visible ? 1 : 0)
                }
            }
            accessibilityLabel = String(
                format: "off=%.0f sizeH=%.0f lyr=%d big=%d vis=%d heals=%d ok=%d %@",
                sv.contentOffset.y, sv.contentSize.height, hostLayers, bigTotal, bigVisible,
                healAttempts, healsSucceeded, bigDesc
            )
        }
    }

#endif
