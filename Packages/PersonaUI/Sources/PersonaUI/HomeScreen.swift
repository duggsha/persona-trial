import Combine
import PersonaCore
import PersonaDesign
import PersonaService
import SwiftUI
import UIKit

/// The Home page: greeting, chat starters and the card feed in a single
/// scrolling column, fed live by `HomeStore`. Sections without data are omitted
/// rather than shown empty.
/// What a sent reply's "Replying to …" tap asks Home to bring into view.
enum HomeRevealTarget: Equatable {
    case suggestion(UUID)
}

struct HomeScreen: View, Equatable {
    // Only closures are passed in; all real content comes from @Environment
    // stores (Observation drives updates). So a parent re-render — e.g. opening a
    // sheet — never needs to rebuild Home: equal but for the measured values the
    // root hands down.
    nonisolated static func == (lhs: HomeScreen, rhs: HomeScreen) -> Bool {
        lhs.extraBottomInset == rhs.extraBottomInset
    }

    let onStartChat: (String) -> Void
    /// Open a delegated deep-task's thread by id (tasks that are real background
    /// work open their thread instead of seeding a chat).
    var onOpenTask: (String) -> Void = { _ in }
    /// Open Settings → Connected apps (the suggestions empty state's CTA).
    var onOpenConnectedApps: () -> Void = {}
    /// Open Settings → Automations (kept for the temporarily-off create tiles).
    var onOpenAutomations: () -> Void = {}
    /// The task card currently showing its Stop Task menu (one at a time).
    /// Owned by the root so the pager can be gated while one is up (a horizontal
    /// drag then dismisses the menu instead of paging to Chat).
    var revealedDeleteTaskId: Binding<AnyHashable?> = .constant(nil)
    /// True once the page has scrolled off its resting top — the root feeds
    /// this to the header, which glasses the wordmark only while content can
    /// actually pass under it.
    var scrolledUnderHeader: Binding<Bool> = .constant(false)
    /// A suggestion card's keyboard affordance: compose a typed reply on the
    /// chat page (reply-to-suggestion mode) instead of the card's chat sheet.
    var onReplyToSuggestion: (Suggestion) -> Void = { _ in }
    /// A Home element the root wants scrolled into view (tapping a sent reply's
    /// "Replying to …" line lands back here). Consumed + cleared once the
    /// scroll fires; a source that no longer exists is a no-op.
    var revealTarget: Binding<HomeRevealTarget?> = .constant(nil)
    /// An Updates card tap: the root pushes the update's detail page (source
    /// email + the update line + optional reply) — a slide-in drill-in, not a
    /// sheet. Code rows never route here (their tap copies).
    var onOpenUpdate: (Suggestion) -> Void = { _ in }
    /// A tap on the feed's background drops the root composer's keyboard —
    /// the composer is one shared bar across both pages, so it can be focused
    /// while Home is showing and Home owes the same tap-off escape the chat
    /// transcript gives. A no-op when nothing is focused.
    var onDismissKeyboard: () -> Void = {}
    /// Height the task tray adds above the composer (0 when nothing's running)
    /// — Home's cards and the undo toast clear it the same way chat's
    /// transcript does.
    var extraBottomInset: CGFloat = 0

    @Environment(\.capabilities) private var capabilities
    /// The root pager's latched-horizontal drag — the feed freezes its own
    /// vertical scrolling for exactly that gesture (see PersonaRootView).
    @Environment(\.pagerHorizontalDragActive) private var pagerHorizontalDragActive
    @Environment(HomeStore.self) private var home
    @Environment(SettingsStore.self) private var settings
    @Environment(DeepTaskStore.self) private var deepTasks
    @Environment(ProfileStore.self) private var profile
    @Environment(\.openURL) private var openURL
    // (Home's `\.keyboardOverlap` read + `keyboardOnScreen` gate are retired —
    // Phase 4. They inset the scroll surface for a suggestion-draft keyboard,
    // but drafts edit in a modal sheet (SuggestionDraftTextView is read-only
    // in place), so Home never raised a keyboard in its own ScrollView and the
    // inset was always 0. Home now mounts native; any future in-tree keyboard
    // is handled by the system safe-area inset, no measured overlap.)
    /// A tapped `suggestion` notification asks Home to open a card's chat sheet; the
    /// card id is handed over here (the shell pages to Home, Home owns the sheet).
    @ObservedObject private var notifRouter = NotificationRouter.shared
    /// The composer's + menu asks Home to present a create sheet (mail compose /
    /// reminder) — the sheets, sender accounts and undo-send queue live here.
    @ObservedObject private var createRouter = ComposerCreateRouter.shared
    /// A universal card's mic hold in flight (claimed on touch-down): the feed
    /// must hold perfectly still — a finger sliding up toward release-to-delete
    /// must not scroll the page under the card.
    @ObservedObject private var voiceHoldClaim = VoiceHoldClaim.shared
    @State private var listSheet: HomeListKind?
    @State private var detailSuggestion: Suggestion?
    /// The expand reveal the spill trigger already glided to, with when it
    /// fired: the card's settled-frame pass ~0.35s later either corrects it
    /// (different anchor) or repeats it verbatim, and a verbatim repeat is a
    /// second spring retargeting a live one. See `revealExpandedCard`.
    /// Time-bounded rather than paired: a card collapsed before its settled
    /// pass never sends one, so a pairing latch would strand and swallow the
    /// NEXT expand's reveal.
    @State private var lastExpandReveal: ExpandReveal?

    /// An allocation-free stand-in for "this exact sequence of card ids", for
    /// animation `value:` comparisons that would otherwise materialize an
    /// `[UUID]` on every body evaluation.
    private static func idSequenceKey(_ sequences: any Sequence<UUID>...) -> Int {
        var hasher = Hasher()
        for sequence in sequences {
            for id in sequence { hasher.combine(id) }
            // Boundary marker: two decks whose ids merely SHIFT between them
            // must not hash alike.
            hasher.combine(0)
        }
        return hasher.finalize()
    }

    /// One expand-reveal decision: which card, the anchor its geometry chose,
    /// and when it was acted on.
    private struct ExpandReveal {
        let id: UUID
        let anchor: UnitPoint
        let at: TimeInterval

        /// The correction window — the card's settled pass lands ~0.35s after
        /// the spill trigger; anything later is a NEW interaction.
        func repeats(_ other: ExpandReveal) -> Bool {
            id == other.id && anchor == other.anchor && other.at - at < 0.75
        }
    }
    /// The pending notification card id a refresh was already kicked for, so an
    /// unresolvable (stale/dismissed) card triggers exactly one re-pull.
    @State private var suggestionRefreshKickId: String?
    /// The card currently pulsing after a notification-tap reveal — Home's
    /// sibling of the chat transcript's `flashedMessageID`, so a revealed card
    /// visibly announces itself instead of just sitting centered.
    @State private var flashedCardID: UUID?
    /// The update whose SOURCE EMAIL the "See email" chip asked for — the one
    /// sheet left on the Updates card (the card tap itself pushes the page).
    @State private var seeEmailTarget: Suggestion?
    @State private var showCompose = false
    @State private var showReminder = false
    /// The user's real connected sender addresses (excludes Iris's agent mailbox),
    /// used to populate the compose sheet's "From:" selector.
    @State private var senderAccounts: [String] = []
    /// The live "… · Undo?" toast after a suggestion swipe. The card is removed
    /// locally at once, but the server call is deferred to this toast's lifetime,
    /// so Undo is a pure local restore (nothing to reverse server-side).
    @State private var undoToast: UndoToastState?
    @State private var undoDismissTask: Task<Void, Never>?

    /// Pull-to-refresh timestamps inside the last 30s — three are free;
    /// the fourth starts the sass (see the .refreshable easter egg).
    @State private var recentRefreshPulls: [Date] = []

    /// Armed at pull time so the landed haptic fires ONLY for a refresh the
    /// user asked for — never for launch restores, the half-hour staleness
    /// ticker, or a background page-return refresh.
    @State private var refreshHapticArmed = false

    /// How long the pull-to-refresh control may stay up. It acknowledges the
    /// gesture; it does not track the work (see the `.refreshable` note).
    private static let refreshSpinnerCap: TimeInterval = 1.0

    /// One tick per pull, on whatever lands first — the rewritten greeting or
    /// the feed. Disarms itself, so a pull never rings twice.
    private func ringRefreshLanded() {
        guard refreshHapticArmed else { return }
        refreshHapticArmed = false
        DSHaptics.selection()
    }

    /// OFFLINE fallback for the refresh-spam protest — normally Iris writes a
    /// fresh line server-side (see regenerateSassGreeting); these only paint
    /// when that request fails. Everyday headache humor, no em dashes.
    /// Indexed by how far past the free pulls the user is; the last line
    /// holds for every pull after.
    private static let refreshSassLines: [String] = [
        String(localized: "okay, that's a lot of refreshing"),
        String(localized: "easy, i'm getting dizzy"),
        String(localized: "ow. you're giving me a headache"),
        String(localized: "i need a minute and some aspirin"),
        String(localized: "nothing has changed in the last four seconds. promise"),
        String(localized: "i'm just going to show this line until you stop"),
    ]

    /// A question typed into a card's sheet, wrapped in the card's own context so
    /// the answer comes back grounded in it. Lifted verbatim from
    /// `SuggestionChatSheet.seededMessage`, which this trial doesn't include.
    static func seededMessage(for suggestion: Suggestion, userText: String) -> String {
        var context = "[Context — a suggestion I'm showing the user in their home feed: \"\(suggestion.message)\""
        let detail = suggestion.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty { context += " — \(detail)" }
        context += ". The user is replying to that suggestion.]"
        return context + "\n\n" + userText
    }

    /// The hero's Start: spawn a REAL deep task from its goal and open its thread
    /// directly — progress runs there and anything it's missing (a login, a
    /// choice) is asked for in-thread. No main-chat detour. Falls back to chat
    /// where deep tasks aren't a capability.
    private func startHeroTask(_ task: SuggestedTask) {
        guard capabilities.deepTasks else {
            onStartChat(task.seedPrompt)
            return
        }
        Task { @MainActor in
            if let id = await home.startTask(task) { onOpenTask(id) }
        }
    }

    /// Tapping the hero card's context chip opens the card's SOURCE (not the
    /// task): a referenced deep-task opens its thread, and anything without a
    /// dedicated screen (mail thread/message, calendar event) opens a chat
    /// grounded in the context snippet. The Start button is unaffected — it still
    /// spawns the task.
    private func openHeroContext(_ task: SuggestedTask) {
        guard let kind = task.referenceKind, let id = task.referenceId, !id.isEmpty else { return }
        switch kind {
        case "deep-task" where capabilities.deepTasks:
            onOpenTask(id)
        default:
            // mail-thread / mail-message / calendar_event: no dedicated surface —
            // open a chat grounded in the context so the user can dig in.
            onStartChat(task.contextSnippet ?? task.seedPrompt)
        }
    }

    /// A task card opens its delegated deep-task's tool timeline.
    private func openTask(_ task: ActiveTask) {
        if capabilities.deepTasks, let id = task.deepTaskID {
            onOpenTask(id)
        } else {
            onStartChat(task.title)
        }
    }

    /// A needs-help option chip: send the label as the ask_user answer, then
    /// pull fresh state so the card leaves its parked look (the chip shows a
    /// spinner meanwhile — see TaskNeedsHelpPanel.answering).
    private func respondToTask(_ task: ActiveTask, answer: String) {
        guard let id = task.deepTaskID else { return }
        Task {
            await deepTasks.respond(id, answer: answer)
            await deepTasks.refreshTask(id)
            await home.refresh()
        }
    }

    /// The needs-help keyboard affordance: open the task thread with the
    /// composer already focused, for a free-text answer.
    private func openTaskComposer(_ task: ActiveTask) {
        deepTasks.requestComposerFocus()
        openTask(task)
    }

    /// How many cards the secondary decks (Location, Other) show inline before
    /// "All". The primary Suggestions deck is uncapped (it was stuck at a
    /// few cards — show them all and let Home scroll); these lighter sections
    /// keep the cap and surface the rest behind their "All" pill.
    private let inlineSuggestionLimit = 6

    /// The proactive-suggestions deck. `home.suggestions` keeps EVERY card (so a
    /// tapped-notification cardId still resolves against it); the split is only
    /// here, at render time — proactive picks vs. informational mail.
    private var deckSuggestions: [Suggestion] {
        home.suggestions.filter { $0.section == .suggestions }
    }

    /// Location-based proactive cards (place tips, nearby events, travel) — their
    /// own section between Suggestions and Other.
    private var locationCards: [Suggestion] {
        home.suggestions.filter { $0.section == .location }
    }

    /// Informational mail cards (important mail, sign-in codes, verify links) —
    /// the "Other" section below Suggestions.
    private var otherCards: [Suggestion] {
        home.suggestions.filter { $0.section == .other }
    }

    /// The Updates feed: see-only notice cards (codes, heads-ups, fired
    /// reminders), useful-right-now kinds first then newest. The backend
    /// already filters expiry; the split is render-time like every section.
    private var deckUpdates: [Suggestion] {
        UpdateCard.sectionSort(home.suggestions.filter { $0.section == .updates })
    }

    /// Every card that reaches a rendered section this pass — the impression
    /// denominator. Deliberately NOT `home.suggestions`: that array also holds
    /// cards kept only so a notification tap can resolve its id, which the user
    /// never sees.
    private var renderedCards: [Suggestion] {
        deckSuggestions + locationCards + otherCards + deckUpdates
    }

    /// Active sign-in codes ride PINNED at the very top of the feed, newest
    /// code first: the Updates row itself wears the pin
    /// instead of a second big card. A code leaves the moment its countdown
    /// runs out (live, via the row's `onExpired`) or it's dismissed;
    /// everything new lands below the pinned group.
    private var pinnedUpdates: [Suggestion] {
        deckUpdates
            .filter {
                ($0.kind == "signin-code" && $0.isOpen && !($0.code ?? "").isEmpty && !isCodeExpired($0))
                    // A wallet pass whose event is imminent ("your flight is
                    // today") earns the pin too; far-out passes ride the feed.
                    || ($0.kind == "wallet-pass" && $0.isOpen && isWalletPassImminent($0))
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// The newest running order — the big progress card pinned above even the
    /// codes: a code can be read from its row seconds later, an order that just
    /// turned "ready for pickup" is the reason the app is open at all. Requires
    /// the structural payload; without it the bar would draw empty, and an
    /// empty bar reads as "nothing is happening" — the opposite of the truth.
    /// (SurfacedItemSlot used to own this card but was benched with the hero on
    ///; the feed's pinned group is that slot's successor.)
    private var liveOrderCard: Suggestion? {
        deckUpdates
            .filter { $0.kind == "order-progress" && $0.isOpen && $0.orderProgress != nil }
            .max(by: { $0.createdAt < $1.createdAt })
    }

    /// The pass's own relevantDate is within the next 24h (or the event is
    /// underway, up to 6h past) — the moment it must not be missed.
    private func isWalletPassImminent(_ card: Suggestion) -> Bool {
        guard let at = card.walletRelevantAt else { return false }
        let untilEvent = at.timeIntervalSinceNow
        return untilEvent < 24 * 3600 && untilEvent > -6 * 3600
    }

    /// The code's stated life has run out (mail-stated window first, card
    /// expiry second) — or its countdown hit zero live this session.
    private func isCodeExpired(_ card: Suggestion) -> Bool {
        if home.expiredCodeIds.contains(card.id) { return true }
        guard let until = card.codeValidUntil ?? card.expiresAt else { return false }
        return until <= Date()
    }

    /// The merged For-you deck: Suggestions and Updates as ONE list, each card wearing its kind tag. Live codes ride the
    /// pinned group above instead; action links keep their front-of-line
    /// urgency; everything else runs newest-first. Suggestions stay uncapped
    /// (the deck scrolls); non-urgent updates keep their old inline cap —
    /// "All" carries the rest.
    private var deckFeed: [Suggestion] {
        let pinnedIds = Set(pinnedUpdates.map(\.id))
        let unpinned = deckUpdates.filter {
            !pinnedIds.contains($0.id) && !($0.kind == "signin-code" && isCodeExpired($0))
                // The running order renders as the big pinned bar instead —
                // a second, static row saying the same thing is just noise.
                && $0.id != liveOrderCard?.id
        }
        let urgent = unpinned.filter { $0.kind == "signin-code" || $0.kind == "action-link" }
        let calmUpdates = Array(
            unpinned.filter { !($0.kind == "signin-code" || $0.kind == "action-link") }
                .prefix(inlineSuggestionLimit)
        )
        // Pending cards sink to the very bottom, THEN newest-first within each
        // group. The server orders the same way, but this line re-sorts the
        // merged deck from scratch and would throw that away — a card created
        // seconds ago with nothing in it yet won "newest" outright and landed
        // at the top of the feed.
        let rest = (deckSuggestions + calmUpdates).sorted { a, b in
            if a.isPending != b.isPending { return !a.isPending }
            return a.createdAt > b.createdAt
        }
        return urgent + rest
    }

    /// Whether any backend-driven content is present (tasks or suggestions).
    private var hasData: Bool {
        !home.tasks.isEmpty || !home.suggestions.isEmpty
    }

    /// The launch skeleton covers Home whenever a refresh is in flight and there
    /// is NOTHING to show yet. `hasData` already guarantees it never sits beside
    /// real content, so a cached launch with content still paints instantly and
    /// refreshes silently. It deliberately does NOT check `restoredFromSnapshot`:
    /// an EMPTY restored snapshot used to skip the skeleton and drop straight to
    /// HomeStatusView, i.e. a definitive "you're all caught up" while the fetch
    /// was still running, with the real content popping in a moment later
    /// ("this ugly loading", design).
    private var showsLaunchSkeleton: Bool {
        home.isLoading && !hasData
    }

    /// The dismissed/acted history for one section — the Closed rows of its
    /// All sheet.
    private func resolvedCards(in section: Suggestion.HomeSection) -> [Suggestion] {
        home.resolvedSuggestions.filter { $0.section == section }
    }

    var body: some View {
        // The redesign owns the whole surface: a full-screen decision pager,
        // not a scrolling page of sections. The shipped page stays reachable
        // at -LEGACY_HOME for comparison.
        if ProcessInfo.processInfo.arguments.contains("-LEGACY_HOME") {
            legacyBody
        } else {
            DeckScreen()
        }
    }

    private var legacyBody: some View {
        ZStack(alignment: .bottom) {
            homeScroll
            if let undoToast {
                UndoToast(
                    message: undoToast.message,
                    showsUndo: undoToast.showsUndo,
                    actionLabel: undoToast.actionLabel,
                    onUndo: { undoAction() },
                    // Swipe-down = "don't need the undo": commit now, toast gone.
                    onDismiss: { withAnimation(.smooth(duration: 0.22, extraBounce: 0)) { flushPendingUndo() } }
                )
                .frame(width: undoToast.toastWidth, height: 42)
                .padding(.bottom, PersonaLayout.contentBottomInset + 6 + extraBottomInset)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // The shared gradient is owned by PersonaRootView, outside the pager,
        // so this page stays transparent while it swipes over the static image.
        .onDisappear { flushPendingUndo() }
    }

    private var homeScroll: some View {
        scrollBody
            // Same as the chat transcript: iOS 26's automatic top scroll-edge
            // effect paints a white wash under the Dynamic Island that fights
            // the header's glass ramp — the ramp is the only top treatment.
            .modifier(TopScrollEdgeEffectHidden())
            // The header's wordmark-glass signal. The 4pt slack keeps the
            // resting bounce from flickering the capsule; the animation lives
            // in the header (WordmarkGlass), not here.
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top > 4
            } action: { _, scrolled in
                guard scrolledUnderHeader.wrappedValue != scrolled else { return }
                scrolledUnderHeader.wrappedValue = scrolled
            }
    }

    private var scrollBody: some View {
        ScrollViewReader { proxy in
            scrollContent(proxy)
                // The root pager owns a latched-horizontal page drag — the feed
                // must not also creep vertically under it (the finger always
                // arcs a little). Freezes exactly for that drag — and for a
                // card mic's hold-to-talk (the slide-up-to-cancel gesture must
                // move the release mode, never the page).
                .scrollDisabled(pagerHorizontalDragActive || voiceHoldClaim.isActive)
        }
    }

    /// One suggestion card wired to Home's shared handlers. Extracted so the
    /// scroll body stays type-checkable: the inline 10-argument init repeated
    /// at three sites pushed `scrollContent` past the compiler's budget
    /// ("unable to type-check this expression in reasonable time").
    private func suggestionRow(
        _ suggestion: Suggestion,
        _ proxy: ScrollViewProxy,
        tagged: Bool = false,
        onTap: @escaping () -> Void
    ) -> some View {
        SuggestionCard(
            suggestion: suggestion,
            onTap: onTap,
            onDelete: dismissSuggestion,
            onExecute: executeSuggestion,
            onRunAction: { suggestion, action, editedBody in
                runInviteAction(suggestion, action, editedBody: editedBody)
            },
            onRemind: remindSuggestion,
            onGeneratedAction: runGeneratedAction,
            onComposeReply: onReplyToSuggestion,
            onDraftFocus: { target in liftDraftClearOfKeyboard(target, proxy) },
            onExpanded: { revealExpandedCard($0, frame: $1, proxy: proxy) },
            showsKindTag: tagged,
            isUnread: home.isUpdateUnread(suggestion),
            onMarkRead: { home.markUpdateSeen(suggestion) }
        )
        // Value-input gate (see SuggestionCard.==): a task poll re-runs this
        // page's body every few seconds and hands every card new closures —
        // without this, each pass re-ran every visible card's heavy body.
        // Applied to the CARD, not the row: the flash pulse below is Home's
        // own state and must keep animating.
        .equatable()
        // The arrival pulse after a notification-tap reveal (the transcript's
        // reply-jump breathe, card-sized).
        .scaleEffect(flashedCardID == suggestion.id ? 1.03 : 1)
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    /// Whether a card renders with the universal grammar (kind tag / title /
    /// context / source row / chips / keyboard + mic rail — design settled
    ///). Bespoke surfaces keep their legacy cards: sign-in codes
    /// and wallet passes (tap-to-copy / PassKit), calendar invites and daily
    /// syncs (structured panels), and permission asks (native dialog flow).
    /// Internal (not private): the Updates history list renders the SAME
    /// real cards for its Open section, through the same gate.
    static func usesUniversalCard(_ suggestion: Suggestion) -> Bool {
        if suggestion.section == .updates {
            return suggestion.kind != "signin-code" && suggestion.kind != "wallet-pass"
        }
        // Calendar invites ride the universal card too:
        // the opened card shows the event's facts (when / where) and the RSVP
        // buttons arrive as ordinary chips, so the bespoke invite panel bought
        // nothing the shared grammar can't say.
        if suggestion.kind.lowercased().hasPrefix("daily") { return false }
        if suggestion.actions.contains(where: { $0.type == "request_permission" }) { return false }
        return true
    }

    /// One universal card wired to Home's shared handlers — replaces both
    /// `updateRow` and `suggestionRow` for every card the gate admits.
    private func universalRow(_ item: Suggestion) -> some View {
        UniversalCard(
            suggestion: item,
            isUnread: home.isUpdateUnread(item),
            onDelete: dismissSuggestion,
            onRunAction: { suggestion, action, editedBody in
                runInviteAction(suggestion, action, editedBody: editedBody)
            },
            onGeneratedAction: runGeneratedAction,
            // The card's own tap is its disclosure (expand / collapse), so it
            // no longer routes to the update detail page or the chat sheet —
            // the opened card carries the source email and the reply controls
            // itself, and a chip-less card is cleared by its swipe.
            onMarkRead: { home.markUpdateSeen(item) },
            onRunOrder: runReplyOrder,
            // Under the grammar the card's tap is its sheet, not its
            // disclosure. Same sheet the suggestion rows already open, so the
            // card gains a door rather than a second detail surface.
            onOpenSheet: { detailSuggestion = $0 }
        )
        .scaleEffect(flashedCardID == item.id ? 1.03 : 1)
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    /// One Updates card wired to Home's shared handlers — the merged deck's
    /// sibling of `suggestionRow`, kind tag on.
    private func updateRow(_ update: Suggestion) -> some View {
        UpdateCard(
            suggestion: update,
            isUnread: home.isUpdateUnread(update),
            onTap: {
                home.markUpdateSeen(update)
                onOpenUpdate(update)
            },
            onCopyCode: {
                home.markUpdateSeen(update)
                home.markCodeConsumed(update)
            },
            onDelete: dismissSuggestion,
            onSeeEmail: {
                home.markUpdateSeen(update)
                seeEmailTarget = update
            },
            onMarkRead: { home.markUpdateSeen(update) },
            showsKindTag: true,
            // The countdown hit zero — the code is dead, the row just leaves
            // (pinned or not; the next refresh drops it server-side too).
            onExpired: {
                withAnimation(.smooth(duration: 0.32, extraBounce: 0)) { home.markCodeExpired(update) }
            },
            onAddToWallet: {
                home.markUpdateSeen(update)
                addPassesToWallet(update)
            },
            // open_link is an immediate action type: runs the backend action
            // (which consumes the card server-side) and opens the returned URL.
            onOpenLink: { action in
                home.markUpdateSeen(update)
                runInviteAction(update, action)
            },
            // Long-press context menu — same handlers as the suggestion cards
            // (updates are Suggestions under the hood, so snooze/reply flow
            // through the identical paths).
            onRemind: remindSuggestion,
            onComposeReply: onReplyToSuggestion
        )
        // See suggestionRow — same value-input gate, same reason.
        .equatable()
        .scaleEffect(flashedCardID == update.id ? 1.03 : 1)
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    /// The real card downloads its parked .pkpass bytes and stages PassKit's
    /// add sheet. Both the download and the sheet are gone from this trial, so
    /// the row's "Add to Wallet" chip is inert.
    private func addPassesToWallet(_ update: Suggestion) {}

    /// An inline expand grows the card DOWNWARD — a low card's panel opens
    /// below the fold (often straight under the floating composer). Called by
    /// the card the moment its growing plate first spills past the composer
    /// (so the glide starts with the expansion) and again once the height
    /// animation settles (correcting against the final frame): glide the card
    /// into view only when the panel actually spilled past the composer, so
    /// an already-visible card never moves.
    /// (`scrollTo(anchor: nil)` is NOT an option here — it no-ops on views
    /// that are already partially visible, live-verified.)
    private func revealExpandedCard(_ suggestion: Suggestion, frame: CGRect, proxy: ScrollViewProxy) {
        let screen = UIScreen.main.bounds
        // A card ending above the composer fold is fully readable — leave it
        // alone. (Same line the card's spill trigger watches.)
        guard frame.maxY > screen.height - SuggestionCard.composerFoldInset else { return }
        // Tall panels center poorly (header AND actions both clipped) —
        // pin those near the top instead.
        let anchor: UnitPoint = frame.height > screen.height * 0.7 ? .top : .center
        // The settled pass exists to CORRECT a glide the spill trigger
        // launched against mid-flight geometry (a tall panel picks its anchor
        // from the final height). When it would re-target the identical
        // anchor, it is not a correction — it's a second 0.35s spring
        // retargeting a live one, which reads as the card moving twice. Fire
        // the correction only when the verdict actually changed.
        let verdict = ExpandReveal(id: suggestion.id, anchor: anchor, at: CACurrentMediaTime())
        if let last = lastExpandReveal, last.repeats(verdict) { return }
        lastExpandReveal = verdict
        withAnimation(.smooth(duration: 0.35, extraBounce: 0)) {
            proxy.scrollTo(suggestion.id, anchor: anchor)
        }
    }

    /// Tapping a draft raises the keyboard. The viewport's keyboard inset is
    /// OURS to provide (the `safeAreaInset` spacer on the scroll view — system
    /// keyboard avoidance never reaches inside the root canvas), so scrolling
    /// the draft's anchor to the inset viewport bottom lands the whole box in
    /// view, clear of the keyboard AND the lifted composer bar. The hop waits
    /// out the keyboard's rise so the measured overlap (and with it the inset)
    /// is already settled when we scroll.
    private func liftDraftClearOfKeyboard(_ target: SuggestionDraftTarget, _ proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            withAnimation(.smooth(duration: 0.28, extraBounce: 0)) {
                proxy.scrollTo(target, anchor: .bottom)
            }
        }
    }

    private func scrollContent(_ proxy: ScrollViewProxy) -> some View {
        // Derive the merged feed ONCE per render. `deckFeed` is a computed
        // property that was read four times in this body — the guard, the
        // empty-check, the ForEach, and the .animation value — and each read
        // re-runs UpdateCard.sectionSort twice plus a merge sort (~12 full-feed
        // sorts on the main thread per invalidation). A poll landing mid-swipe
        // then hitched the pager. Compute here, reuse below.
        let feed = deckFeed
        let feedIDs = feed.map(\.id)
        // The deck's removal animation keys on "did the visible id sequence
        // change" — as a HASH, not as a freshly built `[UUID]`. The old
        // `pinnedUpdates.map(\.id) + feedIDs` allocated two arrays plus their
        // concatenation on every body evaluation (and this body re-runs on
        // every 3s task poll), to compare a value that changes only when a
        // card lands or leaves.
        let feedAnimationKey = Self.idSequenceKey(
            [liveOrderCard?.id].compactMap { $0 }, pinnedUpdates.lazy.map(\.id), feedIDs
        )
        return ScrollView(.vertical, showsIndicators: false) {
            // Lazy so off-screen sections/suggestion cards aren't built or
            // re-measured until scrolled near — the heavy SuggestionCard bodies
            // otherwise all render up front and re-layout on every scroll frame.
            // Behaviour is identical: the page's `.task` side-effects live on the
            // container (not per card), and nothing depends on total content size.
            LazyVStack(alignment: .leading, spacing: 0) {
                GreetingBlock(
                    location: home.location,
                    greeting: home.greeting,
                    isWriting: home.greetingPending,
                    // Tap the line for a fresh one. Pull-to-
                    // refresh still regenerates too; only the pull escalates to
                    // the protest line when spammed, a tap always writes plain.
                    onTap: { home.regenerateGreeting() },
                    locationUnavailable: home.locationUnavailable,
                    onLocationTap: {
                        // Denied = iOS will never re-show the prompt; the app's
                        // Settings page is the only door. Otherwise a retry
                        // raises the native request itself (not-determined).
                        if home.locationNeedsSettings {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        } else {
                            Task { await home.retryLocation() }
                        }
                    }
                )

                // One-tap chat starters right under the greeting: a scrolling
                // rail of prompts (a ride, dinner, the inbox, …) that seed a
                // chat turn verbatim. Iris-written pills
                // for this moment lead the rail — shimmering ghosts while the
                // writer works, scrolling in when they land; a pull-to-refresh
                // regenerates them for wherever the moment has moved.
                // The shortcut rail sat between the greeting and the deck —
                // three more pills of soft chrome on a surface whose job is
                // now decisions. The starters still exist in the composer's
                // + menu; the rail returns with -LEGACY_HOME.
                if ProcessInfo.processInfo.arguments.contains("-LEGACY_HOME") {
                    HomeChatShortcuts(
                        onTap: handleQuickAction,
                        personalized: home.chatShortcuts,
                        isWriting: home.chatShortcutsPending
                    )
                    .padding(.top, 14)
                }

                // (The live-ride tracker, the sign-in park cards and the
                // payment park cards all sat here in the real app. Each is
                // driven by live backend state that this trial has none of, and
                // each dragged in a whole subsystem — the ride tracker, the
                // in-app browser, the payment sheets — so they were cut with
                // the rest of the backend. The feed below is unchanged.)

                // Create tiles (Set reminder / New email / Automations): the
                // sheet-backed creators as boxed tiles right under the hero
                // cluster. TEMPORARILY OFF — the
                // quick actions now ALSO live in the composer's + menu (the
                // durable home); restore the tiles by uncommenting:
                // QuickActionCreateTiles
                // actions: home.quickActions.filter { $0.kind != .seedChat },
                // onTap: handleQuickAction
                //)
                // .padding(.top, 26)

                // The feed: ONE headerless list — no "For
                // you" label, no All pill — in strict order:
                // 1. a running order's progress bar,
                // 2. pinned items: live sign-in codes, newest first
                //,
                // 3. the merged Suggestions + Updates deck, each card wearing
                // its kind tag.
                // Interaction language unchanged per kind: suggestions
                // expand/chat-sheet, updates tap to their detail page (codes
                // tap-to-copy), both swipe-left to dismiss. When the deck is
                // empty the "all caught up" panel replaces the cards (only when
                // Home has OTHER content; a fully empty Home keeps the global
                // HomeStatusView instead).
                // Gate on what can actually DRAW: the pinned codes and the deck
                // are the only rows this section has.
                if !pinnedUpdates.isEmpty || !feed.isEmpty || hasData {
                    // Figma Home_Suggestions Horizontal: 10pt between cards.
                    // Lazy so the uncapped deck's off-screen cards (each a heavy
                    // SuggestionCard/UpdateCard with a swipe state machine) aren't
                    // built or re-laid-out until scrolled near — the same reason
                    // the outer stack is a LazyVStack. A plain VStack here forced
                    // the whole feed to build eagerly, taxing the pager swipe.
                    LazyVStack(spacing: 10) {
                        // A running order's progress bar, pinned above
                        // everything. The 1s heartbeat is scoped to this
                        // subtree — it only drives the bar's travelling
                        // sheen, so the rest of Home never re-renders on
                        // the tick (same idiom as the code countdowns).
                        if let order = liveOrderCard {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                SurfacedOrderCard(suggestion: order, now: context.date)
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                        }
                        ForEach(pinnedUpdates) { update in
                            updateRow(update)
                        }
                        ForEach(feed) { item in
                            if Self.usesUniversalCard(item) {
                                universalRow(item)
                            } else if item.section == .updates {
                                updateRow(item)
                            } else {
                                suggestionRow(item, proxy, tagged: true) { detailSuggestion = item }
                            }
                        }
                    }
                    // Acting on a card consumes it (HomeStore drops it) —
                    // animate its removal off Home.
                    .animation(.smooth(duration: 0.32, extraBounce: 0), value: feedAnimationKey)
                    // 21, not the sections' usual 26: the feed sits right
                    // under the shortcut rail, which reads as part of the
                    // header cluster — slightly tighter air keeps them one
                    // unit without crowding (26 → 16 → 21, design-tuned).
                    .padding(.top, 21)
                }

                // Informational mail cards — same section chrome and card component
                // as Suggestions, just a separate deck below it. Hidden when empty,
                // and off entirely on products where this flows through the
                // persistent main chat instead (capabilities.otherMailSection).
                if capabilities.otherMailSection, !otherCards.isEmpty {
                    section("Other", topPadding: 26, onShowAll: { listSheet = .other }) {
                        VStack(spacing: 12) {
                            ForEach(otherCards.prefix(inlineSuggestionLimit)) { card in
                                suggestionRow(card, proxy) { openOtherCard(card) }
                            }
                        }
                        .animation(
                            .smooth(duration: 0.32, extraBounce: 0),
                            value: Self.idSequenceKey(otherCards.lazy.map(\.id))
                        )
                    }
                }


                if showsLaunchSkeleton {
                    // Shimmer section rows where the decks will land. A cached
                    // launch WITH content never sees this — it painted above and
                    // refreshes silently; an empty one shimmers instead of
                    // asserting "all caught up" before the fetch has answered.
                    HomeSkeletonSections()
                        .padding(.top, 26)
                } else if !hasData, home.errorText != nil {
                    HomeStatusView(error: home.errorText, errorKind: home.errorKind) {
                        Task { await home.refresh() }
                    }
                    .padding(.top, 40)
                }
                // (The empty-deck "connect an app" panel lived here. It only
                // renders when the feed is empty — which the trial's fixed deck
                // never is — and it reached into the whole connect ecosystem
                // (Gmail/IMAP/WhatsApp/Telegram/Uber sheets, the onboarding
                // icon set), so it went with the backend.)
            }
            .padding(.horizontal, DS.Spacing.gutter)
            // Home needs more top clearance than Chat/Around because its
            // greeting sits beneath the complete centred wordmark row. This
            // measures from the PHYSICAL top (the pager strips the container
            // top inset), and the header row bottoms out at ~111pt physical
            // (59 safe-top + 10 + 42 controls) — 76 and 102 both left the
            // location line clipped behind the header; 128 clears it by ~17pt.
            // A content MARGIN (not inner padding): the pull-to-refresh
            // spinner anchors to the content's top edge, so a margin drops it
            // below the floating header where it can be seen — inner padding
            // left it spinning invisibly behind the island.
            .padding(.bottom, PersonaLayout.contentBottomInset + extraBottomInset)
        }
        .contentMargins(.top, 128, for: .scrollContent)
        // The 128pt above measures from the scroll view's PHYSICAL top: shed the
        // automatic safe-area content inset the scroll view picks up from
        // sitting under the status bar, and shed it deterministically — left to
        // resolve on its own it applied on the first frames after a cold open
        // and vanished on the first content re-layout, which read as "Home
        // paints ~47pt too low, then snaps up when the greeting lands".
        .ignoresSafeArea(.container, edges: .top)
        .scrollDismissesKeyboard(.interactively)
        // Tap the background to drop the keyboard, exactly as the chat
        // transcript does. Home hosts no field of its own, but the ROOT
        // composer is shared across both pages and can be focused here, and a
        // tap that landed on a card or the empty feed left it up with no way
        // out but a scroll. An ancestor tap: every card's own tap/press
        // gesture is inner, so it still wins its own touches.
        .onTapGesture { onDismissKeyboard() }
        // (Phase 4: the measured-`keyboardOverlap` bottom `safeAreaInset` and
        // its `keyboardWill{Show,Hide}` gate are gone. They reserved a
        // keyboard-sized viewport inset for a suggestion draft taking focus in
        // place, but drafts edit in a modal sheet now, so Home never raised a
        // keyboard in its own ScrollView and that inset was always 0. Home
        // mounts native, so a future in-tree keyboard would ride the system
        // safe-area inset directly — no root probe.)
        // Pull down to refetch the whole page (feed, tasks, meeting) AND have
        // Iris write a fresh greeting line every time.
        // The fetch runs in an UNSTRUCTURED task: .refreshable cancels its own
        // task the moment the scroll view's content re-renders under the
        // gesture, which killed the in-flight request and painted the
        // "cancelled" error screen. The detached hop is immune to that.
        //
        // The control is a RECEIPT FOR THE PULL, not a progress bar. Home paints from its snapshot before any fetch starts,
        // so there is nothing to hold the screen hostage for — this is the
        // "check for new" gesture every feed app treats the same way. It lets
        // go at `refreshSpinnerCap` and the refresh finishes underneath;
        // arriving content animates in on the feed's own 0.32s curve and rings
        // the haptic below. Measured against staging, the five Home fetches
        // land in ~0.7s, so the cap only bites on a bad network — which is
        // exactly when a spinner that will not quit is worst.
        //
        // Easter egg: the first three back-to-back pulls
        // behave; from the fourth on, Iris skips the writer and complains —
        // escalating through `Self.refreshSassLines`. The counter forgets
        // pulls older than 30s, so once the user lets her breathe that long,
        // the next pull is a normal refresh with a real line again.
        .refreshable {
            await Task {
                // Feel the trigger: one medium tap the moment the pull
                // commits to a refresh.
                DSHaptics.tap(.medium)
                refreshHapticArmed = true
                let now = Date()
                recentRefreshPulls = recentRefreshPulls.filter { now.timeIntervalSince($0) < 30 } + [now]
                let spamCount = recentRefreshPulls.count
                if spamCount > 3 {
                    // Iris WRITES the protest (annoyance = pulls past the
                    // free three) — fresh wording every time, so the joke
                    // doesn't wear out on the second discovery. The canned
                    // line only paints if the request fails. Shimmer starts
                    // immediately inside the regenerate, exactly like a real
                    // rewrite.
                    home.regenerateSassGreeting(
                        annoyance: spamCount - 3,
                        fallbackLine: Self.refreshSassLines[
                            min(spamCount - 4, Self.refreshSassLines.count - 1)
                        ]
                    )
                } else {
                    home.regenerateGreeting()
                }
                // Every pull rewrites the rail's personalized pills for the
                // new moment (sass pulls included — the pills don't joke).
                // Fire-and-forget: shimmer ghosts front the rail while the
                // writer works; the spinner below is never held by this.
                home.regenerateChatShortcuts()
                // A pull that changes NOTHING (same cards, same line) never
                // rings, so the arm has to expire on its own — otherwise it
                // sits waiting and fires on whatever background refresh
                // happens to change something minutes later. Long enough to
                // cover a written greeting (~2.5s), short of the next landing.
                Task {
                    try? await Task.sleep(for: .seconds(6))
                    refreshHapticArmed = false
                }
                let work = Task { await home.refresh() }
                // Whichever comes first: the refresh, or the cap. Cancelling
                // the group only cancels the WAIT — `work` is unstructured, so
                // a refresh that outlives the spinner still lands.
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await work.value }
                    group.addTask { try? await Task.sleep(for: .seconds(Self.refreshSpinnerCap)) }
                    _ = await group.next()
                    group.cancelAll()
                }
            }.value
        }
        // Something the pull asked for landed — one quiet tick, whichever
        // arrives first. This is what carries "it worked" once the control can
        // let go before the data does: the greeting rewrite (real or sass)...
        .onChange(of: home.greeting) { _, _ in ringRefreshLanded() }
        // ...or the feed itself changing under it.
        .onChange(of: home.suggestions.map(\.id) + home.tasks.map(\.id)) { _, _ in ringRefreshLanded() }
        // A vertical scroll dismisses any open Stop Task menu.
        .onScrollPhaseChange { _, phase in
            if phase == .interacting, revealedDeleteTaskId.wrappedValue != nil {
                withAnimation(.smooth(duration: 0.25, extraBounce: 0)) { revealedDeleteTaskId.wrappedValue = nil }
            }
        }
        // Same soft top-fade as Chat / Settings / Iris-menu, so Home content
        // dissolves under the header/island instead of clipping — one consistent
        // behaviour across every scroll surface (matches the DesignOnly).
        .topScrollFade()
        .task { await loadSenderAccounts() }
        // Live task rows: while an agent works, the backend rewrites the task's
        // status line mid-step — keep the Tasks section polling so the row's
        // subtitle shows what it's doing right now.
        .task { await home.pollTasksWhileActive() }
        // A sent reply's "Replying to …" line landed us here: glide its source
        // into view if it still exists, then clear the handoff. A consumed card
        // / passed meeting is a silent no-op (the line deliberately goes nowhere).
        .onChange(of: revealTarget.wrappedValue) { _, target in
            guard let target else { return }
            revealTarget.wrappedValue = nil
            switch target {
            case let .suggestion(id):
                guard home.suggestions.contains(where: { $0.id == id }) else { return }
                withAnimation(.smooth(duration: 0.45, extraBounce: 0)) {
                    proxy.scrollTo(id, anchor: .center)
                }
                flashCard(id)
            }
        }
        // A tapped suggestion notification: open the card's chat sheet. Re-checked
        // when the id arrives AND when suggestions load (cold start races the tap).
        // Keyed on the id SET, not the count — a refresh that swaps one card for
        // the target (count unchanged) must still resolve the pending tap.
        .task { openPendingSuggestion() }
        .onChange(of: notifRouter.openSuggestionCardId) { _, _ in openPendingSuggestion() }
        .onChange(of: home.suggestions.map(\.id)) { _, _ in openPendingSuggestion() }
        // Attention funnel, denominator half. Only cards in a section we
        // actually RENDER count — `home.suggestions` also carries rows held for
        // notification-tap resolution that never reach the screen. Keyed on the
        // id set like the tap-resolver above, and `initial: true` so a deck
        // that was already loaded when Home mounted still reports.
        .task { home.noteSuggestionsSeen(renderedCards) }
        .onChange(of: home.suggestions.map(\.id)) { _, _ in
            home.noteSuggestionsSeen(renderedCards)
        }
        // The composer's + menu picked a create action — present its sheet.
        // Home is mounted under the pager on both pages, so this works from
        // Chat too; the sheet covers whichever page is showing.
        .onChange(of: createRouter.pending) { _, request in
            guard let request else { return }
            createRouter.pending = nil
            switch request {
            case .email: showCompose = true
            case .reminder: showReminder = true
            }
        }
        .sheet(item: $listSheet) {
            HomeListSheet(
                kind: $0,
                tasks: home.tasks,
                // Each All list carries its open deck PLUS the resolved history
                // for its section — the sheet splits them into Open / Closed.
                suggestions: deckSuggestions + resolvedCards(in: .suggestions),
                location: capabilities.locationSuggestions ? locationCards + resolvedCards(in: .location) : [],
                other: otherCards + resolvedCards(in: .other),
                updates: deckUpdates + resolvedCards(in: .updates),
                onTask: { task in
                    listSheet = nil
                    openTask(task)
                },
                onDeleteTask: { task in
                    Task { await home.closeTask(task) }
                },
                // The Open sections render REAL UniversalCards — the same
                // handlers the inline deck gets, undo windows included (the
                // toast rides Home, behind the sheet, and lapses the same).
                cardHandlers: SuggestionCardHandlers(
                    onDelete: dismissSuggestion,
                    onRunAction: { runInviteAction($0, $1, editedBody: $2) },
                    onGeneratedAction: runGeneratedAction,
                    onRunOrder: runReplyOrder,
                    onMarkRead: { home.markUpdateSeen($0) }
                )
            )
            // The "Closed" groups are fetched HERE, not on every Home landing
            // — this sheet is the only place they draw. Fills in behind the
            // open rows on the first open of a session; warm after that.
            .task { await home.loadResolvedSuggestions() }
        }
        .sheet(item: $detailSuggestion) { suggestion in
            if CardGrammar.isOn {
                // R8: the sheet is what the card opens to, and R7 says it shows
                // the artifact. The old chat sheet restated the card and put a
                // one-shot chat under it; this one leads with the counterpart's
                // own words and the draft that is waiting.
                GrammarCardSheet(
                    suggestion: suggestion,
                    onClose: { detailSuggestion = nil },
                    // A question or an instruction about the card goes where the
                    // old sheet's reply went: a chat turn seeded with the card,
                    // so the answer comes back grounded in it.
                    onAsk: { card, text in
                        detailSuggestion = nil
                        onStartChat(Self.seededMessage(for: card, userText: text))
                    }
                )
            } else {
                // The legacy branch opened `SuggestionChatSheet` — a one-shot
                // chat about the card. It is a CHAT surface whose whole job is
                // reaching the backend, so it was cut from this trial along with
                // the rest; the card's own expand/collapse and swipe are
                // untouched. Set CARD_GRAMMAR=1 for the grammar sheet above.
                SuggestionDetailSheet(suggestion: suggestion)
            }
        }
        // (Four sheets lived here and were cut with the backend: the source
        // email viewer, PassKit's wallet-pass add sheet, and the mail-compose
        // and reminder-compose creators behind the composer's + menu. Each is a
        // send / fetch surface rather than part of this screen.)
    }

    /// Resolve the notification-tapped suggestion once its card is in the loaded
    /// list. No-op (keeps the pending id) until then, so a cold-start tap resolves
    /// as soon as suggestions arrive. The tap lands ON the card — scrolled to
    /// center with the arrival pulse — never auto-opening its sheet/detail
    ///. A
    /// sign-in-code card still copies (a code is to copy, not read), and an
    /// Updates row is marked read the moment the tap lands on it.
    private func openPendingSuggestion() {
        guard let cardId = notifRouter.openSuggestionCardId else { return }
        guard let match = home.suggestions.first(where: {
            $0.id.uuidString.caseInsensitiveCompare(cardId) == .orderedSame
        }) else {
            // The card is newer than the loaded list (a warm tap on a card
            // minted while Home sat backgrounded, or a cold-start race). Pull
            // once per pending id; the suggestions onChange retries the reveal.
            // A pull that still doesn't produce the card means it's GONE
            // (resolved/expired/dismissed) — clear the pending id, or it lingers
            // armed forever and hijacks a later visit to Home (live bug: taps
            // "did nothing" now and then yanked the feed minutes later).
            if suggestionRefreshKickId != cardId {
                suggestionRefreshKickId = cardId
                Task {
                    await home.refresh()
                    if notifRouter.openSuggestionCardId == cardId,
                       !home.suggestions.contains(where: {
                           $0.id.uuidString.caseInsensitiveCompare(cardId) == .orderedSame
                       }) {
                        notifRouter.openSuggestionCardId = nil
                    }
                }
            }
            return
        }
        if let code = match.code, !code.isEmpty {
            // The tap lands with the code's Updates row (and its countdown) in
            // view — copying is the one thing left to do.
            home.markUpdateSeen(match)
            copyCode(code)
        } else if match.section == .updates {
            home.markUpdateSeen(match)
        }
        // Drive the shared reveal leg (scroll-to-center + pulse) — the same
        // path a sent reply's "Replying to …" tap uses.
        revealTarget.wrappedValue = HomeRevealTarget.suggestion(match.id)
        notifRouter.openSuggestionCardId = nil
    }

    /// The revealed card's arrival pulse — timed like the transcript's
    /// reply-jump flash: breathe in after the glide lands, ease back out.
    private func flashCard(_ id: UUID) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(430))
            withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) { flashedCardID = id }
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.easeOut(duration: 0.3)) { flashedCardID = nil }
        }
    }

    /// Route a create-tile tap (the temporarily-off tiles above; the composer's
    /// + menu routes through ComposerCreateRouter instead).
    private func handleQuickAction(_ action: QuickAction) {
        switch action.kind {
        case .composeEmail:
            showCompose = true
        case .composeReminder:
            showReminder = true
        case .automations:
            onOpenAutomations()
        case .seedChat:
            onStartChat(action.seedPrompt)
        }
    }

    /// Load the user's connected mailboxes for the compose "From:" selector,
    /// excluding Iris's own agent mailbox so we never default to a non-user address.
    private func loadSenderAccounts() async {
        let accounts = await (try? settings.connect.mailAccounts()) ?? []
        senderAccounts = accounts.filter { !$0.isAgentMailbox }.map(\.email)
    }

    /// Tapping an "Other" card: a direct-action card runs its action right away
    /// (same path as the swipe-execute — no sheet); a conversational card opens its
    /// chat sheet. The split is structural, not text-based:
    /// - a card with a structured sign-in `code` → copy it + confirm (no sheet);
    /// - a card whose PRIMARY action is a self-contained `open_link` (an action-link
    /// card) → run it and open the referenced link;
    /// - otherwise (mail-info `send_draft` → draft) → the chat sheet.
    private func openOtherCard(_ suggestion: Suggestion) {
        if let code = suggestion.code, !code.isEmpty {
            copyCode(code)
            home.markCodeConsumed(suggestion)
        } else if suggestion.actions.first?.type == "open_link" {
            executeSuggestion(suggestion)
        } else {
            detailSuggestion = suggestion
        }
    }

    /// Copy a sign-in code to the clipboard and confirm — the direct action for a
    /// sign-in-code card. The code is a structured field, so nothing is scraped.
    /// Grouping spaces are stripped ("583 201" → "583201") — display grouping is
    /// for the eye; OTP fields routinely reject a pasted space (and the inline
    /// UpdateCard tap already strips, so every copy path lands the same string).
    private func copyCode(_ code: String) {
        UIPasteboard.general.string = code.replacingOccurrences(of: " ", with: "")
        DSHaptics.tap(.light)
        presentConfirmation("Code copied")
    }

    /// Action types that run IMMEDIATELY, outside the deferred-undo window:
    /// opening a link is neither destructive nor sensibly deferrable, a
    /// permission ask's feedback IS the native dialog (deferring it reads as a
    /// haunted prompt), and the intro call should ring the instant it's asked.
    private static let immediateActionTypes: Set<String> = ["open_link", "request_permission", "place_intro_call"]

    /// Run ONE specific button action from a card ("Let Iris handle it", a reply
    /// draft, an RSVP, acknowledge) inside the SAME undo window as the swipes:
    /// the card leaves Home at once, the toast offers Undo, and the server call
    /// waits out the toast's lifetime — so a mis-tap is a pure local restore.
    /// `immediateActionTypes` skip the window, with no toast.
    private func runInviteAction(_ suggestion: Suggestion, _ action: SuggestionActionItem, editedBody: String? = nil) {
        guard !Self.immediateActionTypes.contains(action.type) else {
            Task {
                switch await home.performAction(suggestion, action, editedBody: editedBody) {
                case let .openLink(url):
                    openURL(url)
                case let .permissionRequested(scope):
                    // The server consumed the card; now raise the right native
                    // dialog — or hand off to Settings when iOS won't show one.
                    if await home.requestPermission(scope: scope) == .openSettings,
                       let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                case .introCallPlaced:
                    presentConfirmation("Calling you now — pick up!")
                default:
                    break
                }
            }
            return
        }
        flushPendingUndo()
        guard let index = home.takeSuggestion(suggestion) else { return }
        // A start_task chip puts its tray pill up NOW, in the same beat as the
        // "Agent started." toast — the create POST is deferred behind the undo
        // window, and a pill that trails its own toast by those seconds reads
        // as "nothing happened". noteStarted claims the stub when the real id
        // lands; the trailing cancel retracts it on any other outcome.
        let pendingStart = action.type == "start_task"
            ? deepTasks.notePendingStart(goal: suggestion.message)
            : nil
        presentUndo(
            message: executeToastMessage(for: action),
            restore: {
                home.restoreSuggestion(suggestion, at: index)
                if let pendingStart { deepTasks.cancelPendingStart(pendingStart) }
            },
            commit: {
                switch await home.performAction(suggestion, action, editedBody: editedBody) {
                case let .openLink(url):
                    openURL(url)
                case let .taskStarted(taskId):
                    home.noteTaskStarted(taskId: taskId, goal: suggestion.message)
                case .sent, .acknowledged, .permissionRequested, .introCallPlaced, .failed:
                    break // success consumes the card in HomeStore; failure surfaces its error
                }
                if let pendingStart { deepTasks.cancelPendingStart(pendingStart) }
            }
        )
    }

    /// A spoken or typed reply that turned out to be an ORDER the card's chips
    /// can't serve alone — "reply that I'll get back to him soon", or "decline
    /// this and then email him that I can't make it but thanks".
    ///
    /// Deliberately the SAME finish state a chip tap gets:
    /// the card leaves Home at once, the toast names what's happening, and
    /// nothing reaches the server until the undo window lapses — which is what
    /// makes Undo honest for the agent's half too. The button runs first, then
    /// the freeform half, so a chain keeps the order it was spoken in.
    private func runReplyOrder(_ suggestion: Suggestion, _ order: CardReplyOrder) {
        flushPendingUndo()
        guard let index = home.takeSuggestion(suggestion) else { return }
        presentUndo(
            message: order.toast,
            restore: { home.restoreSuggestion(suggestion, at: index) },
            commit: {
                if let chip = order.chip {
                    switch chip {
                    case let .stored(item):
                        // Acting CONSUMES the card server-side (HomeStore
                        // .performAction) — nothing more to resolve.
                        _ = await home.performAction(suggestion, item)
                    case let .generated(action):
                        _ = await home.performGeneratedAction(suggestion, action, editedBody: nil)
                    }
                } else {
                    // No button ran, so nothing told the SERVER this card is
                    // finished — and a card that only left the local feed
                    // walks straight back in on the next refresh. The agent's work IS the resolution here, so
                    // resolve it the way the swipe's commit does.
                    await home.commitDismiss(suggestion)
                }
                if let instruction = order.instruction {
                    await CardActivityLedger.shared.carryOut(
                        instruction, suggestion: suggestion, home: home
                    )
                }
            }
        )
    }

    /// Execute a generated card action for the card's panel, returning the typed
    /// outcome it morphs on. A set reminder additionally offers a Home-level Undo
    /// (the reminder already exists, so Undo DELETEs it — the deferred "commit" is
    /// a no-op that just lets the toast lapse).
    private func runGeneratedAction(_ suggestion: Suggestion, _ action: GeneratedAction, _ editedBody: String?) async -> HomeStore.GeneratedActionOutcome {
        let outcome = await home.performGeneratedAction(suggestion, action, editedBody: editedBody)
        if case let .reminded(reminderId, _) = outcome, !reminderId.isEmpty {
            presentUndo(
                message: "Reminder set",
                restore: { Task { await home.cancelReminder(id: reminderId) } },
                commit: {}
            )
        }
        return outcome
    }

    /// Execute the card's primary action (the expanded panel's dismiss-chip
    /// fallback — the old right-swipe accept is gone). Same deferred-undo window:
    /// the action doesn't hit the server until the toast lapses, so a mis-tap is
    /// recoverable. `open_link` hands back a URL to open when it finally runs.
    private func executeSuggestion(_ suggestion: Suggestion) {
        let action = suggestion.actions.first ?? SuggestionActionItem(type: "acknowledge", label: "Got it")
        // No one-click mail sends anywhere: a send_draft
        // primary opens the card's sheet, where "See draft" holds the words —
        // the only path that mails them is Send inside the composer.
        if action.type == "send_draft" {
            detailSuggestion = suggestion
            return
        }
        // Immediate types (permission asks, the intro call, links) never defer —
        // same routing whichever surface triggered the primary action.
        if Self.immediateActionTypes.contains(action.type) {
            runInviteAction(suggestion, action)
            return
        }
        flushPendingUndo()
        guard let index = home.takeSuggestion(suggestion) else { return }
        // Same tap-time tray pill as runInviteAction — see the note there.
        let pendingStart = action.type == "start_task"
            ? deepTasks.notePendingStart(goal: suggestion.message)
            : nil
        presentUndo(
            message: executeToastMessage(for: action),
            restore: {
                home.restoreSuggestion(suggestion, at: index)
                if let pendingStart { deepTasks.cancelPendingStart(pendingStart) }
            },
            commit: {
                switch await home.performAction(suggestion, action) {
                case let .openLink(url):
                    openURL(url)
                case let .taskStarted(taskId):
                    // Swipe-started a task → show it on Home right away.
                    home.noteTaskStarted(taskId: taskId, goal: suggestion.message)
                default:
                    break
                }
                if let pendingStart { deepTasks.cancelPendingStart(pendingStart) }
            }
        )
    }

    /// Type-driven (language-neutral) confirmation copy for an executed card.
    private func executeToastMessage(for action: SuggestionActionItem) -> String {
        switch action.type {
        case "send_draft": return "Reply sent."
        case "start_task": return "Agent started."
        case "open_link": return "Opening…"
        case "rsvp_accept": return "You're going — RSVP sent."
        case "rsvp_decline": return "Declined — RSVP sent."
        case "acknowledge": return "Done."
        default: return "Suggestion done."
        }
    }

    /// The card's long-press Snooze: the user picked a shared preset. Same
    /// undo window as a swipe — the card leaves Home at once, the toast offers
    /// Undo, and only when the window lapses does the server snooze fire (the
    /// card then resurfaces on its own once the picked time passes). The
    /// preset's return time resolves at COMMIT, so the undo window never eats
    /// into the snooze.
    private func remindSuggestion(_ suggestion: Suggestion, preset: SnoozePreset) {
        flushPendingUndo()
        guard let index = home.takeSuggestion(suggestion) else { return }
        presentUndo(
            message: preset.toast,
            restore: { home.restoreSuggestion(suggestion, at: index) },
            commit: { await home.snoozeSuggestion(suggestion, until: preset.until()) }
        )
    }

    // MARK: - Undo window (suggestion swipe + task delete)

    /// Dismiss a suggestion (left swipe): take it locally, show the toast, defer
    /// the server dismiss to the window.
    private func dismissSuggestion(_ suggestion: Suggestion) {
        flushPendingUndo()
        guard let index = home.takeSuggestion(suggestion) else { return }
        presentUndo(
            message: suggestion.section == .updates ? "Update dismissed." : "Suggestion dismissed.",
            restore: { home.restoreSuggestion(suggestion, at: index) },
            commit: { await home.commitDismiss(suggestion) }
        )
    }

    /// Delete a task (right swipe / long-press): take it locally, show the toast,
    /// defer the real cancel/delete to the window.
    /// Stop a task = CLOSE it (never delete): it leaves Home but stays in the All
    /// list as a stopped entry. No undo toast — a closed task isn't gone.
    /// The long-press menu's pause/resume for a live deep task — nil for rows
    /// without one (nothing to pause) so the menu stays stop-only there.
    private func pauseAction(_ task: ActiveTask) -> (() -> Void)? {
        guard let deepTaskID = task.deepTaskID else { return nil }
        let resume = task.status == "paused"
        return {
            Task {
                if resume { await deepTasks.resume(deepTaskID) } else { await deepTasks.pause(deepTaskID) }
                await home.refresh()
            }
        }
    }

    private func closeTask(_ task: ActiveTask) {
        flushPendingUndo()
        // Flip to STOPPED right here, animated — waiting for the server round trip
        // plus the next refresh is what made a stopped task take ~2s to look
        // stopped. The commit + refresh then reconcile behind it.
        withAnimation(.smooth(duration: 0.3)) {
            home.markTaskStoppedLocally(task)
            // Both stores in the same transaction: the composer tray rides
            // Home too, so the pill leaves with the card. Only the LOCAL flip
            // here — `commitTaskClose` below is the one cancel POST, and
            // firing DeepTaskStore's as well would let the loser's 404 undo
            // it.
            if let deepTaskID = task.deepTaskID { deepTasks.markStoppedLocally(deepTaskID) }
        }
        Task {
            await home.commitTaskClose(task)
            await home.refresh()
            // Reconcile the tray as well: the flip above was a promise, and a
            // cancel that didn't land must put the pill back rather than hide
            // work that's still running.
            if task.deepTaskID != nil { await deepTasks.refresh() }
        }
    }

    /// "Got it" on a terminal task's outcome panel — the pin animates off Home
    /// (the row survives in the All list); the server stamp rides along.
    private func acknowledgeTask(_ task: ActiveTask) {
        DSHaptics.tap()
        withAnimation(.smooth(duration: 0.3)) {
            home.dismissOutcomeLocally(task)
        }
        Task { await home.commitAcknowledge(task) }
    }

    /// Show the "<message> · Undo?" toast and defer `commit` (the real server
    /// call) to the toast's 4s lifetime; `restore` undoes the local removal.
    private func presentUndo(
        message: String,
        seconds: Double = 4,
        actionLabel: String = "Undo?",
        restore: @escaping () -> Void,
        commit: @escaping () async -> Void
    ) {
        let state = UndoToastState(message: message, restore: restore, commit: commit, actionLabel: actionLabel)
        undoDismissTask?.cancel()
        withAnimation(.smooth(duration: 0.28, extraBounce: 0)) { undoToast = state }
        undoDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if Task.isCancelled { return }
            await state.commit()
            // A commit may present its own follow-up toast (send failure →
            // "Couldn't send · Edit?") — only clear when this one still owns
            // the slot.
            if undoToast?.id == state.id {
                withAnimation(.smooth(duration: 0.22, extraBounce: 0)) { undoToast = nil }
            }
            undoDismissTask = nil
        }
    }

    /// A plain, self-dismissing confirmation toast (no Undo, no deferred commit) —
    /// e.g. after copying a sign-in code.
    private func presentConfirmation(_ message: String) {
        let state = UndoToastState(message: message, restore: {}, commit: {}, showsUndo: false)
        undoDismissTask?.cancel()
        withAnimation(.smooth(duration: 0.28, extraBounce: 0)) { undoToast = state }
        undoDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if Task.isCancelled { return }
            if undoToast?.id == state.id {
                withAnimation(.smooth(duration: 0.22, extraBounce: 0)) { undoToast = nil }
            }
            undoDismissTask = nil
        }
    }

    // MARK: - Compose send (undo window → real send → visible failure)

    /// Tap the toast → cancel the pending server call and restore what was taken.
    /// Nothing was sent to the backend, so this is a real restore.
    private func undoAction() {
        guard let toast = undoToast else { return }
        undoDismissTask?.cancel()
        undoDismissTask = nil
        DSHaptics.tap(.light)
        withAnimation(.smooth(duration: 0.28, extraBounce: 0)) {
            toast.restore()
            undoToast = nil
        }
    }

    /// Commit any still-pending removal immediately (leaving Home, or a new
    /// swipe/delete) so its server call isn't dropped.
    private func flushPendingUndo() {
        guard let toast = undoToast else { return }
        undoDismissTask?.cancel()
        undoDismissTask = nil
        Task { await toast.commit() }
        undoToast = nil
    }

    private func section(
        _ title: String,
        topPadding: CGFloat,
        onShowAll: (() -> Void)? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 0) {
                SectionHeader(title, style: .compact)
                if let onShowAll {
                    SectionListButton(title: "All", action: onShowAll)
                }
            }
            content()
        }
        .padding(.top, topPadding)
    }
}

/// Shown when Home resolved to no backend content: an error with Retry when a
/// load failed, or a gentle "all caught up" otherwise. The in-flight first-run
/// state is the launch skeleton's (HomeSkeleton.swift), not this view's.
private struct HomeStatusView: View {
    let error: String?
    var errorKind: APIError.Kind = .unknown
    let onRetry: () -> Void

    // Optional: some QA preview hosts render without the root stores.
    @Environment(ProfileStore.self) private var profile: ProfileStore?
    private var assistantName: String { profile?.assistantName ?? ProfileStore.defaultAssistantName }

    // "Couldn't reach" is reserved for a genuine transport failure. Every other
    // cause gets its own headline so a server error (500) or a rejected sign-in
    // never masquerades as "no connection". The real detail rides underneath.
    private var errorHeadline: String {
        switch errorKind {
        case .transport: return "Couldn’t reach \(assistantName)."
        case .auth: return "\(assistantName) rejected this app’s sign-in."
        case .server: return "\(assistantName) ran into a problem on our end."
        case .client: return "\(assistantName) couldn’t handle that request."
        case .unknown: return "Something went wrong."
        }
    }
    private var errorSymbol: String {
        switch errorKind {
        case .transport: return "wifi.exclamationmark"
        case .auth: return "key.slash"
        case .server: return "exclamationmark.icloud"
        case .client: return "exclamationmark.bubble"
        case .unknown: return "exclamationmark.triangle"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            if let error {
                Image(systemName: errorSymbol)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(DS.Palette.placeholder)
                Text(errorHeadline)
                    .font(DS.Typography.label)
                    .foregroundStyle(DS.Palette.ink)
                Text(error)
                    .font(DS.Typography.micro)
                    .foregroundStyle(DS.Palette.placeholder)
                    .multilineTextAlignment(.center)
                Button {
                    guard DSInteractionGate.allowsTap else { return }
                    onRetry()
                } label: {
                    Text("Retry")
                        .font(DS.Typography.label)
                        .foregroundStyle(DS.Palette.inkBlack)
                        .padding(.horizontal, 20)
                        .frame(height: 38)
                        .background(DS.Palette.card, in: Capsule(style: .continuous))
                        .overlay { Capsule(style: .continuous).stroke(DS.Palette.hairlineSoft, lineWidth: 1) }
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(DS.Palette.placeholder)
                Text("You’re all caught up.")
                    .font(DS.Typography.label)
                    .foregroundStyle(DS.Palette.placeholder)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct GreetingBlock: View {
    let location: String
    let greeting: String
    /// Iris's personalized greeting is still being written — shimmer where the
    /// line will land instead of showing the template as if it were real.
    var isWriting = false
    /// Tapping the greeting asks Iris for a fresh line (regenerate).
    var onTap: () -> Void = {}
    /// A location attempt finished with NO fix — the line reads "No location
    /// found" (tap = request access) instead of silently vanishing. False
    /// while the first attempt is still resolving, so nothing flashes.
    var locationUnavailable = false
    /// Tap on the "No location found" line: request access (native prompt when
    /// possible, else the app's Settings page — the shell decides which).
    var onLocationTap: () -> Void = {}

    /// The line shows "No location found" only for a FINISHED empty attempt.
    private var showsNoLocation: Bool { location.isEmpty && locationUnavailable }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Always occupies its line (a space when empty) so the greeting never
            // jumps when the city/temperature resolves a moment after launch.
            HStack(spacing: 4) {
                // Icon only on the "No location found" state — a resolved city
                // stands on its own.
                if showsNoLocation {
                    Image(systemName: "location.slash")
                }
                Text(location.isEmpty ? (showsNoLocation ? String(localized: "No location found") : " ") : location)
                    .tracking(-0.14)
            }
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(Color(light: 0x1C1C1C, dark: 0xD6D6DB).opacity(0.40))
            .opacity(location.isEmpty && !showsNoLocation ? 0 : 1)
            .contentShape(Rectangle())
            .onTapGesture {
                guard DSInteractionGate.allowsTap, showsNoLocation else { return }
                onLocationTap()
            }

            // A ZStack slot so the outgoing and incoming greeting overlap
            // during their crossfade instead of stacking.
            ZStack(alignment: .leading) {
                if isWriting {
                    // Invisible template text keeps the exact line height; the
                    // shimmer bar draws over it so nothing shifts when copy lands.
                    Text(greeting)
                        .font(DS.Typography.greeting)
                        .tracking(-0.24)
                        .opacity(0)
                        .overlay(alignment: .leading) {
                            ShimmerBar(height: 20).frame(maxWidth: 215)
                        }
                        .transition(.opacity)
                } else {
                    Text(greeting)
                        .font(DS.Typography.greeting)
                        .tracking(-0.24)
                        .foregroundStyle(Color(light: 0x1C1C1C, dark: 0xECECEF))
                        // New greeting copy = new identity → the change FADES
                        // (template → personalized, daypart rollovers) instead
                        // of the text snapping in place.
                        .id(greeting)
                        .transition(.opacity)
                        // Tap the line → shimmer → Iris writes a fresh one.
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard DSInteractionGate.allowsTap else { return }
                            DSHaptics.tap(.light)
                            onTap()
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.22), value: isWriting)
        .animation(.easeInOut(duration: 0.28), value: greeting)
    }
}
