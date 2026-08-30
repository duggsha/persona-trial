import Foundation
import PersonaCore
import PersonaDesign
import PersonaService
import SwiftUI
import UIKit

/// The universal Home card (design settled): updates and
/// suggestions share ONE grammar — kind tag, title, Iris's context line, the
/// source-email row, quiet reply chips, and a keyboard + mic rail. The only
/// difference between the two kinds is whether chips are present.
///
/// Interaction contract:
/// - HOLD the mic → the card grows a pastel conic rim (the one color moment
/// in the monochrome system) and meters the voice; release sends the words
/// as a reply on the card's side thread; slide up cancels.
/// - Tap the KEYBOARD → the reply sheet (CardReplySheet: a half-height face /
/// title / body + the focused home bar, nothing else) — the card itself
/// never grows a text field, and it does not collapse behind the sheet.
/// - A reply that is an ORDER is carried out, and it is not limited to the
/// card's buttons ("it needs to be extremely flexible
/// and listen to what the user wants" — "decline this and then email him
/// 'I can't make it, but thank you'"). The reply turn lists the card's
/// buttons and asks for a `[[do:{…}]]` directive instead of doing the work:
/// a button index for what a button covers, freeform `agent` work for
/// everything else, chains included. The app runs the button locally and
/// hands the rest back to the agent a turn later. Running it client-side is
/// what keeps Undo honest — the card leaves Home at once and NOTHING
/// reaches the server until the toast lapses, the agent's half included. A
/// QUESTION about an action is still answered in words.
/// - Either way the ANSWER comes back ON THE CARD: Iris's
/// reply streams into a block under the chips and rail, folded at six
/// lines, and is restored there when the card is reopened. The reply used
/// to disappear onto the side thread behind a "Reply sent." receipt, which
/// only a trip to chat history could redeem. The user's own words are NOT
/// reprinted — the seed asks Iris to name what was asked, so the answer
/// stands alone.
/// - Tap the SOURCE ROW → the mail sheet (MailThreadSheet: every email in
/// the thread, full previews) with a reply bar riding its bottom edge.
/// - Chips: generated actions settle IN PLACE (working shimmer → bare
/// receipt line); legacy stored actions keep the existing undo-window
/// contract (the card leaves Home, the toast offers Undo).
/// - Swipe LEFT to dismiss — UpdateCard's mechanics verbatim.
struct UniversalCard: View {
    let suggestion: Suggestion
    let isUnread: Bool
    /// Swipe-dismiss committed — same contract as SuggestionCard.onDelete.
    var onDelete: (Suggestion) -> Void = { _ in }
    /// A legacy stored-action chip (undo-window path — the card leaves Home).
    var onRunAction: (Suggestion, SuggestionActionItem, String?) -> Void = { _, _, _ in }
    /// A generated-action chip — the typed outcome drives the in-card settle.
    var onGeneratedAction: (Suggestion, GeneratedAction, String?) async -> HomeStore.GeneratedActionOutcome = { _, _, _ in .failed("") }
    var onMarkRead: () -> Void = {}
    /// A spoken/typed reply turned out to be an ORDER that a chip alone can't
    /// serve — Home takes the card off the feed, shows the order's toast, and
    /// runs it (button first, then the agent's half) when the undo lapses.
    var onRunOrder: (Suggestion, CardReplyOrder) -> Void = { _, _ in }
    /// Open the card's sheet. Under the grammar the card no longer grows in
    /// place — a tap anywhere that is not a pill opens this instead (Alan,
    ///). Unset leaves the disclosure behaviour untouched, so a
    /// surface that has no sheet to show still opens the card the old way.
    var onOpenSheet: ((Suggestion) -> Void)?

    @Environment(HomeStore.self) private var home
    @Environment(SettingsStore.self) private var settings
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    // Optional: preview rigs mount cards without ProfileStore.
    @Environment(ProfileStore.self) private var profile: ProfileStore?
    /// What the user named their assistant. Every line on this card that speaks
    /// ABOUT the assistant says this, never a literal.
    private var assistantName: String { profile?.assistantName ?? ProfileStore.defaultAssistantName }
    @ObservedObject private var ledger = CardActivityLedger.shared
    @StateObject private var recorder = VoiceMemoRecorder()

    // Swipe state machine — UpdateCard's numbers, verbatim.
    @State private var dragOffset: CGFloat = 0
    @State private var isSwipeActive = false
    @State private var isCompletingSwipe = false
    @State private var wasPastCommitThreshold = false

    /// Hold-to-talk is card-local (the finger is on this card right now);
    /// working/settled live in the shared ledger so they survive the
    /// LazyVStack recycling a scrolled-away row.
    @State private var isHoldingVoice = false
    @State private var releaseMode: VoiceReleaseMode = .send
    @State private var showsHoldHint = false

    @State private var showMailSheet = false
    @State private var showReplySheet = false
    /// When a press last landed on the reply rail. The rail's touch surface
    /// does not consume the touch, so the plate's tap gesture would otherwise
    /// collapse the card under the sheet the same tap just opened — see
    /// `plateTapped()`. Time-windowed, so it needs no reset.
    @State private var replyRailPressedAt: Date?
    /// The card opened its working parts (source email, chips, reply rail)
    /// and lifted the collapsed three-line clamp.
    @State private var isExpanded = false
    /// The answer block's own fold: it rests at six lines and opens on tap.
    @State private var isAnswerExpanded = false
    /// The answer's full ideal height, measured unclamped. Taller than the
    /// fold means the fold is hiding something, which is the only honest way
    /// to know whether to offer "More".
    @State private var answerFullHeight: CGFloat = 0
    /// This answer overran the fold at least once while it was CLOSED — the
    /// only state that survives opening it. Once open the drawn text and its
    /// ideal height agree by definition, so without the latch an unfoldable
    /// answer would still offer "Less" the moment it was tapped.
    @State private var answerHasOverflowed = false
    /// A restore fetch already ran for this card's thread — one per open, even
    /// if it came back empty.
    @State private var restoredThreadId: String?
    /// Prefetched thread meta: the sender label the mail sheet opens with.
    @State private var mailSender: String?
    /// The thread's senders, newest first, deduped — the faces riding inside
    /// the tile (max 3 render).
    @State private var mailFaces: [MailFace] = []
    /// The face the HEADER avatar wears when the feed pinned no contact: the
    /// newest sender in the thread who isn't the user. Excluding our own
    /// addresses matters because `mailFaces` is newest-first — on a thread the
    /// user replied to last, `.first` is them.
    @State private var mailBrandEmail: String?
    /// The thread's openable files, deduped across its messages — the rows
    /// under "View email". Comes from the same prefetched thread the source
    /// row uses, so the card asks the server nothing extra for them.
    @State private var mailAttachments: [CardAttachment] = []
    /// Every conversation the card offers, primary first.
    @State private var mailThreads: [CardMailThread] = []
    /// The mail / attachment groups are open. Only ever consulted when the
    /// card offers more than one of that kind; both shut again when the card
    /// closes, so reopening it never starts on a wall of rows.
    @State private var showsAllThreads = false
    @State private var showsAllAttachments = false
    /// The attachment whose sheet is open.
    @State private var openAttachment: CardAttachment?
    /// The conversation whose mail sheet is open (nil = the primary one).
    @State private var openThread: CardMailThread?
    /// The reply the user is about to look over before it goes anywhere.
    @State private var composeTarget: CardComposeTarget?
    /// The user's connected sender addresses, fetched when the compose sheet
    /// opens so its "From:" row can tell the truth (same list Home's New
    /// email loads; agent mailboxes excluded).
    @State private var senderAccounts: [String] = []

    /// One sender of the referenced thread.
    struct MailFace: Identifiable, Hashable {
        let id: String
        let name: String
        let email: String?
    }

    private let maxDrag: CGFloat = 104
    private let commitDistance: CGFloat = 74

    /// QA-only answer copy. `CARD_QA_ANSWER=1` seeds the real-world BURST
    /// shape (two short utterances, the case we's screenshot
    /// caught); `CARD_QA_ANSWER=long` seeds one that overruns the six-line
    /// clamp, so the fold and its "More" can be shot too.
    private static let qaAnswerBurst = """
    pacific time bc you're in sf

    unless you left the time zone in your sleep
    """

    private static let qaAnswerLong = """
    On whether the 5pm review still works with your flight: it's tight but doable. \
    The invite runs 5:00–5:45 and your car is booked for 6:10, so you'd be leaving \
    right as it ends. Jordan has moved this twice already, so pushing it again would \
    land it past Thursday — I'd keep the slot and tell them you have a hard stop at 5:45.
    """

    // MARK: - Content derivation

    private var isUpdate: Bool { suggestion.section == .updates }

    private var titleLine: String {
        isUpdate ? suggestion.updateHeaderLine : suggestion.proposalLine
    }

    // MARK: Headline

    /// Title and description as ONE run so the collapsed card can hold them
    /// to a shared three-line budget — two separate
    /// clamps would spend the budget on whichever text happened to be first.
    /// Opening the card lifts the clamp entirely.
    private var headlineText: AttributedString {
        Self.headline(title: titleLine, context: contextText)
    }

    /// The one headline grammar, shared with the history list rows
    /// (HomeListSheet) so the Updates page and the inline card can never
    /// drift apart.
    static func headline(title: String, context: String?) -> AttributedString {
        var out = AttributedString(title)
        out.font = .system(size: 15, weight: .semibold)
        out.foregroundColor = DS.Palette.ink
        out.tracking = -0.24
        if let context {
            var body = AttributedString("\n" + context)
            body.font = .system(size: 13, weight: .regular)
            body.foregroundColor = DS.Palette.inkMuted
            body.tracking = -0.10
            out += body
        }
        return out
    }

    private var contextText: String? {
        Self.contextText(title: titleLine, raw: suggestion.contextLine)
    }

    /// Iris's added context under the title — hidden when it would just
    /// repeat the title (two server clamps of the same line differ only by a
    /// "…" cut, so a prefix either way counts as a repeat).
    static func contextText(title: String, raw: String) -> String? {
        let line = oneParagraph(raw)
        guard !line.isEmpty else { return nil }
        func stem(_ s: String) -> String {
            s.hasSuffix("…") ? String(s.dropLast()).trimmingCharacters(in: .whitespaces) : s
        }
        let a = stem(line)
        let b = stem(title)
        guard !a.isEmpty, !b.isEmpty else { return line }
        if a.hasPrefix(b) || b.hasPrefix(a) { return nil }
        return line
    }

    /// The context arrives as several short facts, each on its own line
    /// ("invoice #1146547 from andrew glickman" / "debi is on the thread").
    /// Those hard breaks are why opening a card threw its words around: the
    /// COLLAPSED clamp flows them into one truncated line, so the words sat
    /// out at the card's right edge, and expanding snapped them back to
    /// wherever the server had put a newline — half a line of text jumping
    /// left for no reason the reader can see.
    ///
    /// Flattened to one paragraph, both states wrap at exactly the same
    /// places. Opening a card then only ever ADDS lines below; not one word
    /// already on screen moves.
    ///
    /// Joined on the header's own "San Francisco · 59°" separator, not a bare
    /// space: the facts still have to read as separate facts once the line
    /// break holding them apart is gone. A plain space gave us "…from andrew
    /// glickman debi is on the thread", where "glickman debi" reads as one
    /// person's name.
    private static func oneParagraph(_ text: String) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var chipActions: [CardChipAction] {
        CardChipAction.actions(for: suggestion)
    }



    private var activity: CardActivityLedger.Activity? {
        ledger.activity(for: suggestion.id)
    }

    private var isWorking: Bool {
        if case .working = activity { return true }
        return false
    }

    /// Iris's reply to the last thing the user asked this card, streaming or
    /// settled — the block at the card's bottom edge.
    private var answer: CardActivityLedger.Answer? {
        ledger.answer(for: suggestion.id)
    }

    /// The card's saved side thread, if a reply ever started one. The backend
    /// copy wins (it crosses devices); the local map covers the beat before
    /// the link posts.
    private var savedThreadId: String? {
        suggestion.chatThreadId ?? home.sideThreadId(for: suggestion.id)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            swipeAffordance
            cardPlate.offset(x: dragOffset)
        }
        .overlay {
            HorizontalSwipeGestureAttachment(
                edgeSwipeWidth: 16,
                usesPageEdgeStripes: true,
                locksVerticalScroll: true,
                allowsRightward: false,
                onChanged: handleSwipeChanged(translation:),
                onEnded: handleSwipeEnded(translation:)
            )
        }
        // Same pager contract as the sibling cards: a drag that starts on this
        // card never pages Home⇄Chat.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            SuggestionSwipeZones.update(suggestion.id, frame: frame)
        }
        .onDisappear {
            SuggestionSwipeZones.update(suggestion.id, frame: nil)
            if isHoldingVoice {
                recorder.discard()
                isHoldingVoice = false
            }
        }
        .task(id: suggestion.id) { await loadMailMeta() }
        // Pull the opened card's files into memory while the user is reading
        // it, so "See invoice" opens on the tap instead of spinning. Keyed on
        // the file list AND the open state: collapsed cards key to "" and
        // fetch nothing, and the attachments arriving late (they come from
        // the thread prefetch) re-runs this rather than missing the window.
        .task(id: attachmentWarmKey) { await warmAttachments() }
        // An answered card that's been reopened (a Home refresh, a relaunch,
        // another device) shows its last answer again. Keyed to the OPEN, not
        // the mount: the collapsed feed asks the server nothing, and one card
        // in hand costs one request.
        .task(id: isExpanded) { await restoreAnswerIfNeeded() }
        // A new ask cleared the block (the ledger drops the old answer the
        // moment the next one starts). Two things reset with it: the fold —
        // an unfolded long answer must not leave the next, shorter one
        // sitting open under a "Less" — and the restore latch, so a reply
        // that fails outright can still get the card's last saved answer back
        // on the next open instead of stranding it blank.
        .onChange(of: answer == nil) { _, cleared in
            guard cleared else { return }
            isAnswerExpanded = false
            // The next answer measures itself from scratch — a short one must
            // not inherit the last one's fold.
            answerHasOverflowed = false
            answerFullHeight = 0
            restoredThreadId = nil
        }
        .sheet(isPresented: $showReplySheet) {
            CardReplySheet(
                suggestion: suggestion,
                resolvedSenderEmail: mailBrandEmail,
                onSendText: { text, images, file in sendCardReply(text, images: images, file: file) },
                onVoiceClip: { url, duration in
                    CardActivityLedger.shared.beginVoiceReply(
                        clip: url, duration: duration,
                        suggestion: suggestion, home: home, api: settings.apiClient,
                        onOrder: { runOrder($0) }
                    )
                }
            )
            .environment(settings)
        }
    }

    /// Route one typed/transcribed reply through the shared pipeline — the
    /// card shimmers until the first token, then Iris's answer streams into
    /// the block at its bottom edge. A reply that turns out to be an ORDER
    /// ("accept the invite") presses the card's own button instead, by the
    /// same path the chip takes — so it leaves Home with the undo toast, not
    /// with a sentence explaining that it can't.
    private func sendCardReply(
        _ text: String,
        images: [Data] = [],
        file: ChatFileAttachment? = nil
    ) {
        onMarkRead()
        let suggestion = suggestion
        let home = home
        Task {
            await CardActivityLedger.shared.sendReply(
                text, suggestion: suggestion, home: home,
                images: images, file: file,
                onOrder: { runOrder($0) }
            )
        }
    }

    /// One order off a reply. A bare button is routed through `handleChip`, so
    /// speaking "accept the invite" lands in EXACTLY the state tapping Accept
    /// does — same removal, same toast copy, same deferred commit. Anything
    /// with work beyond the buttons goes to Home's order path instead, which
    /// wraps the whole chain in one undo window.
    private func runOrder(_ order: CardDirective.Order) {
        let chip = order.button.flatMap { button -> CardChipAction? in
            let chips = chipActions
            guard chips.indices.contains(button - 1) else { return nil }
            return chips[button - 1]
        }
        let instruction = (order.agent ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // The model WROTE the reply: it belongs in the composer, not in an
        // errand handed to the agent — this is the path a card with no reply
        // button takes ("reply to connor saying hi").
        // A written reply opens the sheet, and NOTHING ELSE RUNS. The first cut also fired the chip and handed the
        // remainder to the agent — the agent re-sent the mail the sheet was
        // showing, and the card leaving the feed tore the sheet down a second
        // after it opened ("agents started"). The user decides in the sheet;
        // work the model bundled alongside is surfaced on the card as words,
        // never run behind their back.
        if let written = order.replyBody {
            if !instruction.isEmpty {
                CardActivityLedger.shared.restoreAnswer(
                    suggestion.id,
                    text: String(localized: "You also asked me to: \(instruction). Say the word once the draft is settled and I'll do it.")
                )
            }
            // The directive model's words are WHAT to say, never the final
            // copy. The mail
            // the user actually sees comes out of the compose assist — the
            // same prompt the New-email bar uses, which matches their real
            // sent style and carries the "Sent by Persona" line.
            draftInVoice(written)
            return
        }
        // "reply saying monday works" on a card that HAS a reply button: the
        // words refine that button's draft, and the user still decides.
        if case let .generated(action) = chip, action.kind == .replySend {
            onMarkRead()
            runGenerated(action, instruction: instruction)
            return
        }
        if let chip, instruction.isEmpty {
            handleChip(chip)
            return
        }
        // SAFETY NET, and the arbiter is a MODEL, not a word list. The directive model is TOLD to put a written reply in
        // `reply` and has still handed back "reply to X asking when he's free"
        // as an `agent` errand — and letting that through means the agent
        // writes and SENDS mail the user never saw, the one outcome this path
        // exists to prevent. So every errand on a card with a mail thread goes
        // to compose-assist first, which either WRITES the mail (proof the
        // errand was a reply — the composer opens on it) or returns the draft
        // untouched (proof it wasn't — the errand runs exactly as before).
        // "Did a competent mail-writer produce a body" is a judgment no
        // keyword list makes and the assist makes for free.
        if !instruction.isEmpty {
            routeErrand(instruction, order: order, chip: chip)
            return
        }
        guard !instruction.isEmpty || chip != nil else { return }
        onRunOrder(suggestion, CardReplyOrder(
            chip: chip,
            instruction: instruction.isEmpty ? nil : instruction,
            toast: Self.orderToast(order, chip: chip)
        ))
    }

    /// The toast the order names for itself, or a plain fallback — never
    /// silence, since this toast is the only thing the user sees.
    private static func orderToast(_ order: CardDirective.Order, chip: CardChipAction?) -> String {
        let named = (order.toast ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !named.isEmpty { return named }
        if let chip { return chip.label }
        return String(localized: "On it")
    }

    // MARK: - Plate

    @ViewBuilder
    private var cardPlate: some View {
        Group {
            if case let .settled(receipt) = activity {
                receiptRow(receipt)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
            } else {
                cardBody
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card)
                .fill(cardFill)
        )
        // The listening/working rim sits BEHIND the opaque plate: only its
        // 3pt overhang (blurred) reads, exactly the settled mock.
        .background {
            // The rim stays lit while the answer streams: the shimmer handed
            // off at the first token, and a card writing an answer is still
            // working.
            if isHoldingVoice || isWorking || answer?.isStreaming == true {
                ListeningGlowRim(
                    cornerRadius: DS.Radius.card + 3,
                    dimmed: isWorking || answer?.isStreaming == true,
                    reduceMotion: reduceMotion
                )
                .padding(-3)
                .transition(.opacity)
            }
        }
        // The shared solid-plate shadow pair (Glass.solidCardPlate — painted
        // manually so the swipe tint can mix into the fill).
        .shadow(color: Color(light: 0x000000, dark: 0x000000, lightOpacity: 0.08, darkOpacity: 0), radius: 18, y: 8)
        .shadow(color: Color(light: 0x000000, dark: 0x000000, lightOpacity: 0.05, darkOpacity: 0), radius: 3, y: 1.5)
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card))
        .scaleEffect(isHoldingVoice ? 1.012 : 1)
        .animation(DS.Motion.gentle, value: isHoldingVoice)
        .onTapGesture { plateTapped() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("universal-card-\(suggestion.kind)")
    }

    /// The mark indents ONLY the title and Iris's context:
    /// the source row + action row run full width below, so the avatar reads
    /// as a mark ON the headline, not a gutter the whole card hangs off.
    /// No kind tag (design — a card announces itself by its
    /// content, and "SUGGESTION" bought a whole row for nothing): the age
    /// rides the title's first line instead, right-aligned, so the card opens
    /// on the news.
    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch CardGrammar.isOn ? suggestion.grammarDrawing(isUnread: isUnread) : nil {
            case let .t1(model):
                // The deck's T1 led card replaces the universal card's resting
                // drawing. Everything below the header — the facts block, the
                // source row, the chips, the mic and keyboard rail, the reply
                // block — is untouched and still opens on tap, so the flag
                // swaps the drawing without forking the card's behaviour.
                GrammarT1Card(model: model, onPillTap: grammarPillTapped).content
            case let .t2(model):
                // A tracker is a view over a poll, not a suggestion: no pills,
                // no rail, and nothing to open. The expansion is suppressed
                // below for the same reason.
                GrammarT2Tracker(model: model).content
            default:
                collapsedHeader
            }
            // A T2 tracker has no expanded state in the deck — it says
            // everything it has on its face.
            if !isGrammarTracker { grammarLegacyExpansion }
        }
    }

    /// This card draws as a T2 tracker: no expansion, no sheet, no pills. A
    /// view over a poll, not a suggestion.
    private var isGrammarTracker: Bool {
        guard CardGrammar.isOn, case .t2 = suggestion.grammarDrawing(isUnread: isUnread) else { return false }
        return true
    }

    /// The pre-grammar resting drawing: avatar, headline, age stamp, chevron.
    private var collapsedHeader: some View {
        Group {
            HStack(alignment: .top, spacing: 12) {
                SuggestionEntryAvatar(suggestion: suggestion, size: 38, resolvedSenderEmail: mailBrandEmail)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        // The title keeps its weight whether or not the card
                        // has been opened: unread is told
                        // by the blue dot, never by dimming the headline.
                        // Collapsed, title + description share three lines and
                        // truncate; opening the card shows all of it.
                        Text(headlineText)
                            .lineSpacing(1.5)
                            .lineLimit(isExpanded ? nil : 3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            // The clamp lifting is a CROSSFADE, not a reflow.
                            // The default interpolation tries to carry each
                            // glyph to its new home, so the truncated line's
                            // tail visibly slides as "…" resolves into words —
                            // a lot of motion for a card that only got taller.
                            // Opacity says the same thing quietly.
                            .contentTransition(.opacity)
                        Spacer(minLength: 6)
                        // Unread dot + compact age ("now", "12m", "3d"),
                        // pinned to the title's first baseline. Any real
                        // interaction marks the card seen and the dot goes.
                        HStack(spacing: 5) {
                            if isUnread {
                                Circle()
                                    .fill(DS.Palette.accent)
                                    .frame(width: 7, height: 7)
                                    .transition(.opacity.combined(with: .scale))
                                    .accessibilityLabel("Unread")
                            }
                            Text(suggestion.ageLabel)
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Palette.placeholder)
                            // The one cue that a resting card has more behind
                            // it. Every card qualifies — even one with no
                            // chips opens to its reply controls.
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(DS.Palette.placeholder)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        }
                        .fixedSize()
                        .animation(DS.Motion.gentle, value: isUnread)
                        .animation(DS.Motion.standard, value: isExpanded)
                    }

                }
            }

        }
    }

    /// Everything the card opens to. Unchanged by the grammar for now: the
    /// resting drawing migrates first, and this panel goes when the card's tap
    /// becomes a sheet rather than a disclosure.
    @ViewBuilder
    private var grammarLegacyExpansion: some View {
        Group {
            // The card rests as a headline and opens on tap: the keyboard+mic pair on every row read as noise
            // once the feed got long, so the machinery lives one tap in.
            if isExpanded {
                // When / where / how much — an invite's decisive facts, and
                // the reason a calendar card can live on this grammar at all.
                if let facts = suggestion.facts, !facts.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        // The source leads, on its own line above the facts
                        // — where a mail card's source row
                        // sits, so both kinds of card open the same way: what
                        // this came from, then what it says. A link glyph, not
                        // a second calendar: the WHEN line right below already
                        // carries that one.
                        if let url = eventURL { viewEventLink(url) }
                        if let date = facts.date, !date.isEmpty {
                            factRow("calendar", EventDate.format(date))
                        }
                        if let venue = facts.venue, !venue.isEmpty {
                            factRow("mappin", venue)
                        }
                        if let price = facts.price, !price.isEmpty {
                            factRow("tag", price)
                        }
                    }
                    .padding(.top, 10)
                }

                // The mail, then what came attached to it — one stack, because
                // the files are things INSIDE the thread the row above points
                // at, and both open in the app.
                if suggestion.mailReference != nil {
                    VStack(alignment: .leading, spacing: 2) {
                        // One row when the card is about one conversation —
                        // the plain "View email". When a matter spans several,
                        // they FOLD behind a count: a
                        // long matter stacked five mail rows and two file rows
                        // above the chips, and the card became a directory.
                        // The mails and the files keep their own groups, since
                        // "three emails" and "two attachments" are different
                        // questions.
                        if mailThreads.count > 1 {
                            HStack(spacing: 0) {
                                groupTile(
                                    icon: "envelope",
                                    label: String(localized: "View emails (\(mailThreads.count))"),
                                    isOpen: showsAllThreads,
                                    identifier: "universal-card-source-group"
                                ) { showsAllThreads.toggle() }
                                Spacer(minLength: 0)
                            }
                            if showsAllThreads {
                                ForEach(mailThreads) { thread in
                                    HStack(spacing: 0) {
                                        sourceTile(thread)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.leading, Self.groupIndent)
                                }
                            }
                        } else {
                            HStack(spacing: 0) {
                                sourceTile(nil)
                                // Content width, never full bleed — a
                                // reference on the card, not another surface
                                // across it.
                                Spacer(minLength: 0)
                            }
                        }

                        if mailAttachments.count > 1 {
                            HStack(spacing: 0) {
                                groupTile(
                                    icon: "paperclip",
                                    label: String(localized: "See attachments (\(mailAttachments.count))"),
                                    isOpen: showsAllAttachments,
                                    identifier: "universal-card-attachment-group"
                                ) { showsAllAttachments.toggle() }
                                Spacer(minLength: 0)
                            }
                            if showsAllAttachments {
                                ForEach(mailAttachments) { file in
                                    HStack(spacing: 0) {
                                        attachmentTile(file)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.leading, Self.groupIndent)
                                }
                            }
                        } else {
                            ForEach(mailAttachments) { file in
                                HStack(spacing: 0) {
                                    attachmentTile(file)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                    .padding(.top, 10)
                }

                footer
                    .padding(.top, 12)

                // Iris's answer to the last reply, at the card's bottom edge —
                // the reply is part of the card, not something that happened
                // somewhere else. Below the rail, so the
                // reply controls stay where the hand already knows them and
                // the answer grows downward off the card's foot.
                // A waiting draft REPLACES the answer prose: a paragraph narrating that a draft exists is
                // noise next to the button that opens it. The block keeps the
                // answer's own header — rule, mark, "Iris" — so who made the
                // draft is never in question; the button IS the message.
                if let draft = ledger.draft(for: suggestion.id) {
                    draftNotice(draft)
                        .padding(.top, 14)
                        .transition(.opacity)
                } else if let answer, !answer.text.isEmpty {
                    answerBlock(answer)
                        .padding(.top, 14)
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Answer block

    /// The streamed reply, held to six lines. Tapping it opens the rest in
    /// place (the block owns the tap, so it never reaches the plate's collapse
    /// gesture); the whole exchange stays in the sheet.
    ///
    /// Three moves, settled off we's four-way mock:
    /// - A HAIRLINE above it, and air under the rule. The answer's real fault
    /// was that it began on the same ground, the same left edge and nearly
    /// the same size as the card's own copy, so nothing said a second voice
    /// had started. The rule is the threshold — a line, never a box.
    /// - The mark and Iris's NAME ride their own line above the prose, so who
    /// is talking is stated rather than implied by a glyph floating beside a
    /// column it doesn't align with.
    /// - The prose is the card's LOUDEST voice (15pt, full ink): you asked a
    /// question, so the answer outranks the headline that prompted it.
    ///
    /// (Candidate treatments tried and dropped: bare prose under a full-width
    /// rule, an uppercase kicker, a filled inset plate, a quoted hairline rail,
    /// and a tinted foot bleeding to the plate's bottom corners — the last one
    /// fights the swipe-dismiss tint, which mixes into the same fill.)
    private func answerBlock(_ answer: CardActivityLedger.Answer) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(DS.Palette.hairlineSoft)
                .frame(height: 1)
                .padding(.bottom, 12)
            HStack(spacing: 7) {
                irisMark
                Text(assistantName)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(-0.05)
                    .foregroundStyle(DS.Palette.placeholder)
            }
            .padding(.bottom, 7)
            answerProse(answer)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // An answer that fits is not a control: no fold, no haptic, and
            // the tap falls through to nothing rather than flashing a "Less"
            // over text that was never cut.
            guard answerHasOverflowed, DSInteractionGate.allowsTap else { return }
            DSHaptics.tap(.light)
            withAnimation(DS.Motion.standard) { isAnswerExpanded.toggle() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("universal-card-answer")
    }

    /// The words themselves plus the fold control.
    private func answerProse(_ answer: CardActivityLedger.Answer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.answerParagraphs(answer.text))
                .font(.system(size: 15, weight: .regular))
                .tracking(-0.17)
                .lineSpacing(3)
                .foregroundStyle(DS.Palette.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                // CLIPPED to six lines, never truncated:
                // `lineLimit` would cut the tail and set an ellipsis, and an
                // ellipsis under a fade says the same thing twice — worse,
                // it says it in a hard dot-dot-dot the fade is there to avoid.
                // With no line limit there is nothing for SwiftUI to elide;
                // the text simply runs past the frame and the frame clips it.
                .frame(maxHeight: isAnswerExpanded ? nil : Self.answerFoldHeight, alignment: .top)
                .clipped()
                // The last lines then FADE into the plate: a fold is words
                // continuing behind an edge, and a hard cut reads as broken
                // text. The mask is also the stream's own shape, so arriving
                // tokens stop popping. Applied before the probe so the
                // measurement below is of unfaded, undrawn text.
                .mask { answerFade }
                // Latched here rather than read live: the comparison is only
                // meaningful while the text is folded.
                .onChange(of: isAnswerClamped) { _, clamped in
                    if clamped { answerHasOverflowed = true }
                }
                // The clamp holds THROUGH the stream (a long answer must not
                // shove the feed down and snap back when it settles): the
                // block fills to six lines, then "More" appears and the tail
                // waits behind it.
                .background { answerHeightProbe(Self.answerParagraphs(answer.text)) }

            if answerHasOverflowed {
                HStack(spacing: 4) {
                    Text(isAnswerExpanded ? "Less" : "More")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .rotationEffect(.degrees(isAnswerExpanded ? 180 : 0))
                }
                .foregroundStyle(DS.Palette.placeholder)
                // Drawn where it was, tapped 30pt tall — the block owns the
                // gesture, so the reach is padding nobody can see.
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
        }
    }

    /// The gradient the clamped answer is drawn through: opaque for the first
    /// 62%, then down to a trace at the foot. Fully opaque once the fold is
    /// open — the gradient is always applied so opening the answer doesn't
    /// change the view's identity mid-animation.
    private var answerFade: some View {
        LinearGradient(
            stops: isAnswerClamped
                ? [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.62),
                    .init(color: .black.opacity(0.06), location: 1),
                ]
                : [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 1),
                ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The waiting draft: the answer block's hairline, then ONE ink-filled
    /// capsule — no header line, no prose (the mark +
    /// "Iris" row went too; the button carries the mark itself). The mark
    /// renders TEMPLATED white on the ink fill — the artwork's painted
    /// interior reads as a black blob on black otherwise.
    private func draftNotice(_ draft: CardComposeTarget) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(DS.Palette.hairlineSoft)
                .frame(height: 1)
                .padding(.bottom, 12)
            Button {
                guard !isCompletingSwipe, DSInteractionGate.allowsTap else { return }
                DSHaptics.tap(.light)
                composeTarget = draft
            } label: {
                HStack(spacing: 6) {
                    PersonaAsset.image("PersonaMark")
                        .renderingMode(.template)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 17, height: 15)
                    Text("See draft")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(DS.Palette.onInk)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(Capsule().fill(DS.Palette.ink))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("universal-card-open-draft")
        }
    }

    /// Iris's own mark, on the name line. Light mode keeps the artwork; dark
    /// templates it near-white (PersonaHeader's caveat — the mark's interior
    /// paths are painted, so templating light mode fills the logo into a
    /// silhouette).
    private var irisMark: some View {
        PersonaAsset.image("PersonaMark")
            .renderingMode(colorScheme == .dark ? .template : .original)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 15, height: 13)
            .foregroundStyle(Color(light: 0x030303, dark: 0xF2F2F4))
    }


    /// A burst reply arrives as several short utterances. Rendered with the
    /// blank line the backend pads them with, they read as a chasm mid-card
    /// — so the gap collapses to a single
    /// line break and the burst reads as consecutive lines.
    private static func answerParagraphs(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// The same text laid out unclamped at the same width, drawn nowhere: its
    /// height is what the answer WOULD take, so a disagreement with the drawn
    /// height means the clamp is hiding something. `.fixedSize` is what makes
    /// it work — the probe ignores the clamped height it's proposed.
    private func answerHeightProbe(_ text: String) -> some View {
        GeometryReader { geo in
            Text(text)
                .font(.system(size: 15, weight: .regular))
                .tracking(-0.17)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: geo.size.width, alignment: .topLeading)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { answerFullHeight = $0 }
                .hidden()
        }
        .allowsHitTesting(false)
    }

    /// Six lines of the answer's own type. Computed from the font rather than
    /// measured off a drawn clamp: the frame is then right on the FIRST layout
    /// pass, so a streaming answer clips from the start instead of flashing
    /// full-height for a frame and snapping back.
    private static let answerFoldHeight: CGFloat = {
        let lines: CGFloat = 6
        return lines * UIFont.systemFont(ofSize: 15).lineHeight + (lines - 1) * 3
    }()

    /// True when six lines aren't the whole answer (1pt of slack for
    /// rounding). Drives both the fold control and the fade — nothing fades
    /// when nothing is hidden.
    private var isAnswerClamped: Bool {
        !isAnswerExpanded && answerFullHeight > Self.answerFoldHeight + 1
    }

    /// Re-read the card's side thread and paint its last assistant turn back
    /// into the answer block. Runs on OPEN only, at most once per thread, and
    /// stands down if anything is already on the card (a live stream, or a
    /// restore that already ran) — the ledger is the authority mid-flight.
    private func restoreAnswerIfNeeded() async {
        guard isExpanded, answer == nil, !isWorking else { return }
        // QA hook (shot tests): a canned answer on every card opened, so the
        // block can be shot without driving a real reply through STT + the
        // stream. The product path is the stream itself.
        switch ProcessInfo.processInfo.environment["CARD_QA_ANSWER"] {
        case "1":
            CardActivityLedger.shared.restoreAnswer(suggestion.id, text: Self.qaAnswerBurst)
            return
        case "long":
            CardActivityLedger.shared.restoreAnswer(suggestion.id, text: Self.qaAnswerLong)
            return
        default:
            break
        }
        guard let threadId = savedThreadId, restoredThreadId != threadId else { return }
        restoredThreadId = threadId
        guard let messages = try? await home.fetchSideThreadMessages(threadId) else { return }
        guard let last = messages.last(where: { !$0.isUser }) else { return }
        // Strip the directive, exactly as the STREAM does (the scrubber at the
        // stream's tail never ran on this path). An order's turn is stored in
        // the thread as its raw `[[do:…]]` markup, so restoring it verbatim
        // printed the JSON onto the card as if Iris had said it. A turn that
        // was ONLY a directive has no words to restore at all.
        let restored = CardDirective.stripped(last.text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !restored.isEmpty else { return }
        CardActivityLedger.shared.restoreAnswer(suggestion.id, text: restored)
    }

    /// The event's own page — an invite's source, since no email thread is
    /// recorded behind it and guessing one by subject could attach the wrong
    /// person's mail.
    /// "Mon, Jul 27" — the sheet's header day.
    private var eventDayLabel: String {
        guard let raw = suggestion.facts?.date, let day = EventDate.parse(raw) else { return "" }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private var eventURL: URL? {
        guard let raw = suggestion.facts?.url, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    /// The event opens IN the app — the same sheet the
    /// calendar browser uses, with its RSVP / attendees / notetaker controls —
    /// rather than throwing the user out to the provider's web page. The web
    /// link stays the fallback for an event the calendar fetch can't produce
    /// (a device-only row, or one outside the day we look at).
    /// "View event" on a calendar card. The real app resolves the event against
    /// the calendar and opens it in the app's own detail sheet; that sheet and
    /// its fetch are backend surfaces this trial doesn't carry, so the link just
    /// opens the provider URL — the fallback the real path already used when an
    /// event couldn't be resolved.
    private func openEvent(_ url: URL) {
        guard !isCompletingSwipe, DSInteractionGate.allowsTap else { return }
        DSHaptics.tap(.light)
        onMarkRead()
        openURL(url)
    }

    private func viewEventLink(_ url: URL) -> some View {
        Button {
            openEvent(url)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "link")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(DS.Palette.placeholder)
                    .frame(width: 14)
                Text("View event")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(DS.Palette.ink)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(DS.Palette.placeholder)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("universal-card-view-event")
    }

    /// One decisive fact, in the source row's quiet weight so the opened
    /// card's meta reads as one family.
    private func factRow(_ icon: String, _ value: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Palette.placeholder)
                .frame(width: 14)
            Text(value)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(DS.Palette.inkSoft)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Source email tile

    /// One attached file, in the source row's exact grammar so the pair reads
    /// as one family: what this card points at. The chevron is deliberate —
    /// the sheet opens IN the app, same as "View email", and an out-of-app
    /// arrow here would be a lie.
    private func attachmentTile(_ file: CardAttachment) -> some View {
        Button {
            guard !isCompletingSwipe, DSInteractionGate.allowsTap else { return }
            DSHaptics.tap(.light)
            onMarkRead()
            openAttachment = file
        } label: {
            CardAttachmentTile(file: file.file)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("universal-card-attachment-row")
    }

    /// Disclosed rows sit under their group's LABEL, not under its glyph —
    /// the glyph column (14) plus the row's own spacing (7).
    private static let groupIndent: CGFloat = 21

    /// The count row that hides a group. It toggles and nothing more: no
    /// `onMarkRead`, since uncovering rows is not reading the card.
    private func groupTile(
        icon: String,
        label: String,
        isOpen: Bool,
        identifier: String,
        toggle: @escaping () -> Void
    ) -> some View {
        Button {
            guard !isCompletingSwipe, DSInteractionGate.allowsTap else { return }
            DSHaptics.tap(.light)
            withAnimation(DS.Motion.standard) { toggle() }
        } label: {
            CardGroupTile(icon: icon, label: label, isOpen: isOpen)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    /// The thread behind the card, as one plain link row — the calendar
    /// card's "View event" with a mail glyph.
    private func sourceTile(_ thread: CardMailThread?) -> some View {
        Button {
            guard !isCompletingSwipe, DSInteractionGate.allowsTap else { return }
            DSHaptics.tap(.light)
            onMarkRead()
            openThread = thread
            showMailSheet = true
        } label: {
            CardSourceTile(label: thread?.label)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("universal-card-source-row")
    }

    /// Prefetch the referenced thread (the shared visibility-scoped cache) so
    /// the mail sheet opens instantly, and lift the sender out of it: the card
    /// header's face, and the label the sheets caption themselves with. The
    /// row itself just says "View email" now, so nothing here feeds it.
    private func loadMailMeta() async {
        // Backend surface, removed for this trial: the real card prefetches the
        // referenced mail thread and lifts the sender's faces out of it to dress
        // its header. There is no mail to fetch here, so the card falls back to
        // the contact fields the suggestion already carries — the same fallback
        // the real card uses before a thread lands.
        mailSender = suggestion.contactName ?? suggestion.contactEmail
        mailBrandEmail = suggestion.contactEmail ?? suggestion.avatarEmail
    }

    /// The real card lists every conversation and file behind the suggestion,
    /// read out of the prefetched mail threads. Without a mail backend there is
    /// nothing to collect, so the card draws without its thread and file rows.
    private func collectThreads(_ refs: [MailThreadRef]) {
        mailThreads = []
        mailAttachments = []
    }

    /// A thread's senders, newest first, deduped by address — "who is in this
    /// conversation", not "who happened to start it".
    private static func faces(in thread: MailThreadView) -> [MailFace] {
        let sorted = thread.messages.sorted { ($0.receivedAt ?? "") > ($1.receivedAt ?? "") }
        var seen = Set<String>()
        var faces: [MailFace] = []
        for message in sorted {
            let email = senderAddress(message.from)
            let name = displayName(message.from) ?? email ?? ""
            let key = (email ?? name).lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            faces.append(MailFace(id: key, name: firstName(name), email: email))
        }
        if faces.isEmpty, let participant = thread.participants.first {
            let email = senderAddress(participant)
            let name = displayName(participant) ?? email ?? ""
            if !name.isEmpty {
                return [MailFace(id: name.lowercased(), name: firstName(name), email: email)]
            }
        }
        return faces
    }

    /// Empty while the card is shut — `.task(id:)` then has nothing to do, so
    /// a feed of collapsed cards fetches no bytes at all.
    private var attachmentWarmKey: String {
        isExpanded ? mailAttachments.map(\.id).joined(separator: "|") : ""
    }

    /// The real card prewarms each thread's attachments so a tap opens
    /// instantly. No mail backend here, so there is nothing to warm.
    private func warmAttachments() async {}

    /// "Alice Example <alice@example.com>" → "Alice Example".
    private static func displayName(_ participant: String?) -> String? {
        guard let participant, !participant.isEmpty else { return nil }
        if let angle = participant.firstIndex(of: "<") {
            let display = participant[..<angle].trimmingCharacters(in: .whitespacesAndNewlines)
            if !display.isEmpty { return display.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        }
        return participant
    }

    private static func senderAddress(_ from: String?) -> String? {
        guard let from else { return nil }
        if let angle = from.firstIndex(of: "<"), let close = from.firstIndex(of: ">"), angle < close {
            return String(from[from.index(after: angle) ..< close])
        }
        return from.contains("@") ? from : nil
    }

    /// The tile has room for a name, not a full sender line — "Sam Rossi" is
    /// "Sam" next to two other faces.
    private static func firstName(_ name: String) -> String {
        let lead = name.split(separator: " ").first.map(String.init) ?? name
        return lead.contains("@") ? (lead.split(separator: "@").first.map(String.init) ?? lead) : lead
    }

    // MARK: - Footer (chips + rail / listening / working)

    /// The chips + rail stay MOUNTED through every state — the mic's UIKit
    /// touch surface must survive the listening re-render or the in-flight
    /// press loses its touchesEnded and the card wedges in the listening
    /// state (found by the release smoke test). Listening and
    /// working FADE the row to opacity 0 (never unmount, never an opaque
    /// cover: the plate's per-primitive `.shadow` gave a covering rect its
    /// own drop shadow — the "block around the meter") and draw the status
    /// row in an overlay. Opacity 0 also drops the hidden chips out of hit
    /// testing, while the mic's already-active press keeps delivering.
    private var footer: some View {
        let showsStatus = isWorking || isHoldingVoice
        // lineSpacing 0: every chip carries 4pt of invisible touch padding
        // above and below, which IS the 8pt gap the rows are drawn with.
        return RailFlowLayout(spacing: 7, lineSpacing: 0) {
            ForEach(chipActions) { chip in
                chipButton(chip)
            }
            replyRail
        }
        .opacity(showsStatus ? 0 : 1)
        .overlay {
            if case let .working(status) = activity {
                footerStatusRow { ShimmerText(text: status) }
            } else if isHoldingVoice {
                footerStatusRow {
                    VoiceMemoListeningDisplay(
                        releaseMode: releaseMode,
                        copy: nil,
                        isCompact: false,
                        availableWidth: nil,
                        levels: recorder.levels,
                        isListening: recorder.isListening
                    )
                }
            }
        }
    }

    private func footerStatusRow(@ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 0) {
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func chipButton(_ chip: CardChipAction) -> some View {
        Button {
            guard !isCompletingSwipe, DSInteractionGate.allowsTap else { return }
            DSHaptics.tap(.light)
            handleChip(chip)
        } label: {
            // DRAWN small, TAPPED big (34pt was too small
            // to click, 44pt "looked weird" against the card). Growing the
            // capsule to thumb size made it compete with the headline, so the
            // ink stays at a card-proportional ~32pt and the extra reach is
            // invisible padding below — a 40pt target on a 120pt-wide capsule,
            // which Fitts says is the easy direction anyway. The vertical 4
            // replaces the layout's line spacing rather than adding to it, so
            // rows keep their 8pt gap.
            CardChipLabel(chip: chip)
        }
        .buttonStyle(.plain)
    }

    /// The opened card's ONE reply control (picked from
    /// six candidates): a single quiet capsule — mic glyph, "Reply" — that
    /// TAPS to type and HOLDS to talk. Two outlined circles read as two pieces
    /// of chrome stapled to the corner; one object says "reply, two ways".
    ///
    /// The capsule stays MOUNTED through the listening state, fill and
    /// foreground swapping in place. Branching to a different view here eats
    /// the in-flight press's touchesEnded and wedges the card listening
    /// forever (found by the release smoke test).
    private var replyRail: some View {
        HStack(spacing: 7) {
            Image(systemName: "microphone")
                .font(.system(size: 14, weight: .medium))
            Text("Reply")
                .font(.system(size: 12.5, weight: .semibold))
        }
        .foregroundStyle(isHoldingVoice ? DS.Palette.onInk : DS.Palette.ink)
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background {
            if isHoldingVoice {
                Capsule().fill(DS.Palette.primaryActionGradient)
            } else {
                Capsule().fill(DS.Palette.card)
                    .overlay { Capsule().stroke(DS.Palette.hairline, lineWidth: 1) }
            }
        }
        // Drawn ~34pt, tapped 44 — the reach is padding nobody can see, and it
        // sits UNDER the touch surface below so the whole target is live.
        .padding(.vertical, 5)
        .contentShape(Capsule())
        .overlay {
            ComposerTouchInteractionSurface(
                // A tap is no longer a teaching moment — it opens the reply
                // sheet, which is the keyboard half of this one control.
                onTap: { openReplySheet() },
                onListeningBegan: { beginVoiceHold() },
                onReleaseModeChanged: { releaseMode = $0 },
                onFinished: { finishVoiceHold() },
                onAbortedToTap: { abortVoiceHold() },
                onPressChanged: { pressed in
                    // Claimed on touchesBegan — always before any tap can
                    // recognize, so the plate has the flag by the time its own
                    // gesture fires. See `replyRailPressedAt`.
                    if pressed { replyRailPressedAt = Date() }
                },
                isHostedInScrollView: true
            )
        }
        .accessibilityElement()
        .accessibilityLabel("Reply")
        .accessibilityHint("Tap to type, hold to talk")
        .accessibilityIdentifier("universal-card-reply")
    }

    /// The keyboard half of the reply control.
    private func openReplySheet() {
        guard !isCompletingSwipe, DSInteractionGate.allowsTap else { return }
        DSHaptics.tap(.light)
        onMarkRead()
        showReplySheet = true
    }

    /// "Hold to talk" — flashed when a hold produced no usable audio (too
    /// short, or silence). A TAP no longer needs teaching: it opens the
    /// keyboard.
    @ViewBuilder
    private var holdHint: some View {
        if showsHoldHint {
            Text("Hold to talk")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(DS.Palette.onInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(DS.Palette.ink))
                // Clear of the rail's top edge (the pill is ~24pt tall).
                .offset(x: -2, y: -32)
                .fixedSize()
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func flashHoldHint() {
        withAnimation(DS.Motion.gentle) { showsHoldHint = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(DS.Motion.gentle) { showsHoldHint = false }
        }
    }

    // MARK: - Voice hold

    private func beginVoiceHold() {
        guard activity == nil, !isCompletingSwipe else { return }
        DSHaptics.composerListeningStart()
        releaseMode = .send
        withAnimation(DS.Motion.gentle) { isHoldingVoice = true }
        recorder.start()
    }

    private func abortVoiceHold() {
        recorder.discard()
        withAnimation(DS.Motion.gentle) { isHoldingVoice = false }
        flashHoldHint()
    }


    private func finishVoiceHold() {
        let mode = releaseMode
        withAnimation(DS.Motion.gentle) { isHoldingVoice = false }
        guard mode == .send else {
            recorder.discard()
            return
        }
        guard let url = recorder.finishRecording() else { return }
        let duration = recorder.lastFinishedDuration
        // The composer's empty-clip gate: a too-short or silent hold is not a
        // reply — never send it.
        guard duration >= 0.3, recorder.lastFinishedPeak >= VoiceMemoRecorder.silencePeakThreshold else {
            try? FileManager.default.removeItem(at: url)
            flashHoldHint()
            return
        }
        onMarkRead()
        DSHaptics.tap(.medium)
        CardActivityLedger.shared.beginVoiceReply(
            clip: url,
            duration: duration,
            suggestion: suggestion,
            home: home,
            api: settings.apiClient,
            // A spoken ORDER acts — "accept the invite", or "decline and
            // email him" — which is the mic's most natural use, not a question.
            onOrder: { runOrder($0) }
        )
    }

    // MARK: - Chip dispatch

    /// One dispatch for card chips AND the reply sheet's chips: stored
    /// actions keep the undo-window contract, generated actions settle in
    /// place, the update's Done chip clears the notice.
    private func handleChip(_ chip: CardChipAction) {
        onMarkRead()
        switch chip {
        case let .stored(item):
            // A stored send_draft NEVER fires blind (no
            // one-click mail sends anywhere) — the chip opens the composer on
            // the draft and Send in the sheet is the only thing that mails
            // it. No exceptions: a card whose mail link went cold or whose
            // draft body is missing still gets the sheet — an empty composer
            // beats a mail the user never read.
            if item.type == "send_draft" {
                let draft = item.draftBody?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                composeTarget = storedTarget(item, body: draft)
                return
            }
            onRunAction(suggestion, item, nil)
        case let .generated(action):
            runGenerated(action)
        }
    }

    // MARK: - Generated actions (in-card settle)

    /// A reply is DRAFTED, never fired blind. Tapping the
    /// reply chip used to POST straight through and settle "Reply sent." — the
    /// user's own words left the building without them ever seeing the words.
    /// Now the card drafts, opens the composer with the whole mail filled in,
    /// and waits: Send sends it, dismissing throws it away.
    private func runGenerated(_ action: GeneratedAction, instruction: String? = nil) {
        // replyOption too: a canned option is still a mail
        // send, so it opens on the words in the composer like every other
        // reply — the option's text is the draft, Send is the user's.
        if action.kind == .replySend || action.kind == .replyOption {
            openComposer(for: action, instruction: instruction)
            return
        }
        CardActivityLedger.shared.setWorking(suggestion.id, Self.workingStatus(action, assistantName: assistantName))
        let suggestion = suggestion
        Task {
            let outcome = await onGeneratedAction(suggestion, action, nil)
            switch outcome {
            case .failed:
                CardActivityLedger.shared.clear(suggestion.id)
            case let .openLink(url):
                CardActivityLedger.shared.clear(suggestion.id)
                openURL(url)
            case .replied, .sent:
                CardActivityLedger.shared.settle(suggestion.id, String(localized: "Reply sent."))
            case .reminded:
                CardActivityLedger.shared.settle(suggestion.id, String(localized: "Reminder set."))
            case .meetingCreated:
                CardActivityLedger.shared.settle(suggestion.id, String(localized: "Added to your calendar."))
            case .taskStarted:
                CardActivityLedger.shared.settle(suggestion.id, String(localized: "\(assistantName) is on it."))
            case .acknowledged:
                CardActivityLedger.shared.settle(suggestion.id, String(localized: "Done."))
            }
        }
    }

    // MARK: - Reply composer

    /// Draft, then show. With an instruction from a typed/spoken reply
    /// ("tell her monday works") the card keeps its working shimmer while the
    /// assist rewrites the draft — that IS the loading state the user sees
    /// after typing. Without one the payload's draft is already the answer, so
    /// the composer opens immediately rather than faking a wait.
    private func openComposer(for action: GeneratedAction, instruction: String?) {
        // reply_option carries its words in `text`, reply_send in `body`.
        let base = action.payload.body ?? action.payload.text ?? ""
        let order = (instruction ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !order.isEmpty else {
            composeTarget = target(for: action, body: base)
            return
        }
        onMarkRead()
        CardActivityLedger.shared.setWorking(suggestion.id, String(localized: "Drafting your reply…"))
        let suggestionId = suggestion.id
        Task {
            let drafted = await draftBody(action: action, instruction: order, current: base)
            CardActivityLedger.shared.clear(suggestionId)
            composeTarget = target(for: action, body: drafted)
        }
    }

    /// The instruction folded into the draft by the compose assist — the one
    /// backend path that writes a mail WITHOUT sending it. A failure is not
    /// fatal: the user still gets the card's own draft to edit by hand.
    private func draftBody(action: GeneratedAction, instruction: String, current: String) async -> String {
        let request = ComposeEmailAssistRequest(
            instruction: instruction,
            draft: ComposeEmailDraft(
                to: composeRecipients(action),
                subject: composeSubject(action),
                body: current
            ),
            replyTo: composeReplyContext(action)
        )
        guard let response = try? await settings.compose.client.assistEmail(request) else { return current }
        let body = response.draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? current : response.draft.body
    }

    /// Rewrite a directive-written reply through the compose assist before
    /// the user sees it. The assist grounds the words in how the user REALLY
    /// writes (read_sent_style + their voice profile) and appends the
    /// "Sent by Persona" line — exactly what the New-email bar's drafts get.
    /// The substance is pinned; only the voice is the assist's to change.
    ///
    /// A failed assist falls back to the RAW words in the sheet — off-voice
    /// beats losing the reply, and the user is looking at it either way.
    private func draftInVoice(_ written: String) {
        onMarkRead()
        CardActivityLedger.shared.setWorking(suggestion.id, String(localized: "Drafting your reply…"))
        let suggestionId = suggestion.id
        let recipient = (suggestion.contactEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let recipients = recipient.isEmpty
            ? []
            : [ComposeRecipient(email: recipient, name: suggestion.contactName)]
        let replyTo = suggestion.mailReference.map {
            ComposeReplyContext(accountId: $0.accountId, threadId: $0.threadId)
        }
        Task {
            let request = ComposeEmailAssistRequest(
                instruction: "Write this reply in the user's own voice. Keep its substance exactly — every point, name and commitment — change only the wording to how the user actually writes:\n\n\(written)",
                draft: ComposeEmailDraft(to: recipients, subject: suggestion.message, body: ""),
                replyTo: replyTo
            )
            let response = try? await settings.compose.client.assistEmail(request)
            CardActivityLedger.shared.clear(suggestionId)
            let voiced = (response?.draft.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !voiced.isEmpty {
                openWrittenReply(response?.draft.body ?? voiced)
            } else {
                // Assistant-written mail carries the line even on the fallback.
                let signed = written.contains("Sent by Persona")
                    ? written : written + "\n\nSent by Persona"
                openWrittenReply(signed)
            }
        }
    }

    private func target(for action: GeneratedAction, body: String) -> CardComposeTarget {
        CardComposeTarget(
            route: .action(action),
            body: body,
            recipients: composeRecipients(action),
            subject: composeSubject(action),
            replyTo: composeReplyContext(action)
        )
    }

    /// The legacy rail's draft, in the same composer. Its send still goes
    /// through the card's own action path, so the undo window and the card's
    /// "acted" bookkeeping are untouched — only the blind firing is gone.
    private func storedTarget(_ item: SuggestionActionItem, body: String) -> CardComposeTarget {
        let recipient = (suggestion.contactEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let ref = suggestion.mailReference
        return CardComposeTarget(
            route: .stored(item),
            body: body,
            recipients: recipient.isEmpty
                ? []
                : [ComposeRecipient(email: recipient, name: suggestion.contactName)],
            subject: suggestion.message,
            replyTo: ref.map { ComposeReplyContext(accountId: $0.accountId, threadId: $0.threadId) }
        )
    }

    /// A reply the model WROTE for a card that has no reply button — the
    /// "reply to connor saying hi" case. A card that knows its thread opens
    /// the sheet in Reply mode; a card whose mail link went cold (pre-pinning
    /// cards, matter trails that aged out) opens it as a plain New email with
    /// whatever recipient the card knows. It NEVER silently drops the words —
    /// that was the "loads and goes away" bug: every
    /// route here guarded on the thread ref, so an old card ate the reply.
    private func openWrittenReply(_ body: String) {
        onMarkRead()
        let ref = suggestion.mailReference
        let recipient = (suggestion.contactEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let target = CardComposeTarget(
            route: .direct,
            body: body,
            recipients: recipient.isEmpty
                ? []
                : [ComposeRecipient(email: recipient, name: suggestion.contactName)],
            subject: suggestion.message,
            // A bare thread reference is enough — the composer fills the
            // Re: subject and the counterpart in from it. Nil = New email.
            replyTo: ref.map { ComposeReplyContext(accountId: $0.accountId, threadId: $0.threadId) }
        )
        // Stash FIRST: the sheet may be ✕-ed, and the words must survive it —
        // the card keeps an "Open draft" row until this is sent or discarded.
        CardActivityLedger.shared.stashDraft(suggestion.id, target)
        composeTarget = target
    }

    /// One errand, judged by the compose assist and routed by its verdict:
    /// a written body means "this was a reply" and the composer opens on it;
    /// an untouched draft means "this was other work" and the errand runs
    /// exactly as it did before this net existed — same single undo window,
    /// chip and instruction together. An assist FAILURE also runs the errand:
    /// a flaky classifier must never eat an order.
    ///
    /// The chip deliberately does NOT fire until the verdict is in — on the
    /// declined path it belongs inside the errand's undo window, and firing
    /// it early would commit half the order with no way back.
    private func routeErrand(_ instruction: String, order: CardDirective.Order, chip: CardChipAction?) {
        onMarkRead()
        CardActivityLedger.shared.setWorking(suggestion.id, String(localized: "On it…"))
        let suggestionId = suggestion.id
        let recipient = (suggestion.contactEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let recipients = recipient.isEmpty
            ? []
            : [ComposeRecipient(email: recipient, name: suggestion.contactName)]
        // A card whose mail link went cold still gets its errand judged — the
        // assist just writes without the thread behind it.
        let replyTo = suggestion.mailReference.map {
            ComposeReplyContext(accountId: $0.accountId, threadId: $0.threadId)
        }
        Task {
            // The empty body is the contract: the assist writes into it when
            // the instruction is a reply, and returns it untouched when not.
            let request = ComposeEmailAssistRequest(
                instruction: instruction,
                draft: ComposeEmailDraft(to: recipients, subject: suggestion.message, body: ""),
                replyTo: replyTo
            )
            let response = try? await settings.compose.client.assistEmail(request)
            CardActivityLedger.shared.clear(suggestionId)
            let written = (response?.draft.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !written.isEmpty else {
                onRunOrder(suggestion, CardReplyOrder(
                    chip: chip,
                    instruction: instruction,
                    toast: Self.orderToast(order, chip: chip)
                ))
                return
            }
            if let chip { handleChip(chip) }
            openWrittenReply(response?.draft.body ?? written)
        }
    }

    /// Same list Home's "New email" loads, fetched when the compose sheet
    /// opens — the sheet's From row shows the real account (pinned to the
    /// thread's, once the reply context resolves its accountEmail).
    private func loadSenderAccounts() async {
        guard senderAccounts.isEmpty else { return }
        let accounts = (try? await settings.connect.mailAccounts()) ?? []
        senderAccounts = accounts.filter { !$0.isAgentMailbox }.map(\.email)
    }

    /// Autocomplete and assist stay; the sheet's OWN send is removed, so the
    /// only way out is the card's reply rail (which owns the settle copy and
    /// the card's state) — never a second, parallel send path.
    private var composeClient: ComposeAssistClient {
        var client = settings.compose.client
        client.sendEmail = nil
        client.searchThreads = nil
        return client
    }

    private func composeRecipients(_ action: GeneratedAction) -> [ComposeRecipient] {
        if let to = action.payload.to, !to.isEmpty {
            let name = to.caseInsensitiveCompare(suggestion.contactEmail ?? "") == .orderedSame
                ? suggestion.contactName : nil
            return [ComposeRecipient(email: to, name: name)]
        }
        // A payload without routing (a reply_option from before the backend
        // stamped the reply channel on them) still has a counterpart on the
        // card itself — reply to them, never an empty To: field.
        let contact = (suggestion.contactEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !contact.isEmpty else { return [] }
        return [ComposeRecipient(email: contact, name: suggestion.contactName)]
    }

    private func composeSubject(_ action: GeneratedAction) -> String {
        let subject = (action.payload.subject ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return subject.isEmpty ? suggestion.message : subject
    }

    private func composeReplyContext(_ action: GeneratedAction) -> ComposeReplyContext? {
        let recipients = composeRecipients(action)
        if let accountId = action.payload.accountId, !accountId.isEmpty,
           let threadId = action.payload.inReplyToThreadId, !threadId.isEmpty {
            return ComposeReplyContext(
                accountId: accountId,
                threadId: threadId,
                subject: action.payload.subject,
                from: suggestion.contactName ?? action.payload.to,
                senderOnly: recipients.isEmpty ? nil : recipients
            )
        }
        // No routing in the payload — the card's own mail reference still knows
        // the thread, so the sheet opens in Reply mode (Re: subject, counterpart
        // filled) instead of a blank "New email" titled with the card header.
        guard let ref = suggestion.mailReference else { return nil }
        return ComposeReplyContext(
            accountId: ref.accountId,
            threadId: ref.threadId,
            subject: nil,
            from: suggestion.contactName ?? suggestion.contactEmail,
            senderOnly: recipients.isEmpty ? nil : recipients
        )
    }

    /// Send is the ONLY thing that puts mail on the wire, and it carries the
    /// draft as the user left it.
    private func sendComposed(_ target: CardComposeTarget, draft: ComposeEmailDraft, attachments: [ComposeAttachment]) {
        let body = draft.body
        CardActivityLedger.shared.clearDraft(suggestion.id)
        CardActivityLedger.shared.setWorking(suggestion.id, String(localized: "Sending your reply…"))
        let suggestion = suggestion
        Task {
            // Files can't ride the card rails (the suggestion-action send is
            // body-only), so a draft that staged any goes out the compose door
            // instead — the same threaded send Home's composer uses — and the
            // card is then dismissed by hand, since no rail consumed it.
            if !attachments.isEmpty {
                guard let send = settings.compose.client.sendEmail else {
                    CardActivityLedger.shared.clear(suggestion.id)
                    return
                }
                do {
                    try await send(ComposeEmailSendRequest(
                        draft: draft,
                        attachments: attachments,
                        replyTo: target.replyTo
                    ))
                    CardActivityLedger.shared.settle(suggestion.id, String(localized: "Reply sent."))
                    if case .direct = target.route {} else {
                        await home.dismissSuggestion(suggestion)
                    }
                } catch {
                    CardActivityLedger.shared.clear(suggestion.id)
                }
                return
            }
            switch target.route {
            case let .action(action):
                let outcome = await onGeneratedAction(suggestion, action, body)
                switch outcome {
                case .failed:
                    CardActivityLedger.shared.clear(suggestion.id)
                case .replied, .sent:
                    CardActivityLedger.shared.settle(suggestion.id, String(localized: "Reply sent."))
                default:
                    CardActivityLedger.shared.clear(suggestion.id)
                }
            case let .stored(item):
                // The legacy rail owns its own toast, undo window and settle —
                // hand the edited body to it and let it run, rather than
                // half-driving the card from here.
                CardActivityLedger.shared.clear(suggestion.id)
                onRunAction(suggestion, item, body)
            case .direct:
                // No card rail to ride — this reply goes out the same door the
                // "New email" composer uses.
                guard let send = settings.compose.client.sendEmail else {
                    CardActivityLedger.shared.clear(suggestion.id)
                    return
                }
                do {
                    try await send(ComposeEmailSendRequest(
                        draft: draft,
                        replyTo: target.replyTo
                    ))
                    CardActivityLedger.shared.settle(suggestion.id, String(localized: "Reply sent."))
                } catch {
                    CardActivityLedger.shared.clear(suggestion.id)
                }
            }
        }
    }

    private static func workingStatus(_ action: GeneratedAction, assistantName: String) -> String {
        switch action.kind {
        case .replySend, .replyOption: String(localized: "Sending your reply…")
        case .remind: String(localized: "Setting the reminder…")
        case .createMeeting: String(localized: "Adding to your calendar…")
        case .startTask: String(localized: "Handing this to \(assistantName)…")
        case .openLink: String(localized: "Opening…")
        case .acknowledge, .unknown: String(localized: "On it…")
        }
    }

    // MARK: - Receipt

    /// The settled card: a bare receipt line in the plate — tap to read the
    /// reply on the card's thread.
    private func receiptRow(_ receipt: String) -> some View {
        HStack(spacing: 12) {
            // The mark stays in its gutter so a settled card still lines up
            // with the live ones above it; the check rides its corner.
            SuggestionEntryAvatar(suggestion: suggestion, size: 26, resolvedSenderEmail: mailBrandEmail)
                .overlay(alignment: .bottomTrailing) {
                    ZStack {
                        Circle()
                            .fill(DS.TaskState.checkCircle)
                            .frame(width: 14, height: 14)
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(.white)
                    }
                    .overlay { Circle().stroke(DS.Palette.card, lineWidth: 1.5) }
                    .offset(x: 3, y: 2)
                }
            Text(receipt)
                .font(.system(size: 13, weight: .medium))
                .tracking(-0.13)
                .foregroundStyle(DS.Palette.ink)
                .lineLimit(2)
            Spacer(minLength: 8)
            Text(UpdateCard.timeLabel(suggestion.createdAt))
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.placeholder)
        }
        .accessibilityIdentifier("universal-card-receipt")
    }

    // MARK: - Taps

    /// A pill on the resting grammar card. Routed through `runGenerated`, so a
    /// reply still opens the composer rather than firing blind and every chip
    /// keeps its working/settle animation — the collapsed card gains the
    /// action, not a second way of running it.
    ///
    /// A legacy-action pill (index past `grammarPillActions`) opens the card
    /// instead: those payloads ride the undo-window path, which belongs to the
    /// chip row and not to a resting card.
    private func grammarPillTapped(_ index: Int) {
        guard !isCompletingSwipe, DSInteractionGate.allowsTap, !isHoldingVoice else { return }
        let runnable = suggestion.grammarPillActions
        guard index < runnable.count else {
            plateTapped()
            return
        }
        DSHaptics.tap()
        onMarkRead()
        runGenerated(runnable[index])
    }

    private func plateTapped() {
        guard !isCompletingSwipe, DSInteractionGate.allowsTap, !isHoldingVoice else { return }
        // The reply rail owns its own tap. Its touch surface rides along with
        // every other recognizer on purpose (cancelsTouchesInView = false, and
        // it recognizes simultaneously — it must never win an arbitration
        // fight), so this plate-wide gesture sees the SAME tap: the keyboard
        // tap used to open the reply sheet AND collapse the card behind it in
        // one frame. The plate stands down, the way the composer's ancestor tap
        // stands down while its hold surfaces are mounted.
        if let pressedAt = replyRailPressedAt, Date().timeIntervalSince(pressedAt) < 1 { return }
        if case .settled = activity {
            DSHaptics.tap(.light)
            showReplySheet = true
            return
        }
        guard !isWorking else { return }
        DSHaptics.tap()
        onMarkRead()
        // Under the grammar the tap OPENS THE CARD'S SHEET rather than growing
        // the plate. Leaving the disclosure in place put both card languages on
        // screen at once: the deck's pill row and, right under it, the old chip
        // row and reply rail saying the same thing twice.
        // R8 is universal: "there is no card whose plate is inert", including
        // the kinds nobody has drawn a sheet for yet. A tracker suppresses its
        // EXPANSION (it has no chips or rail to open) but still opens its
        // sheet, same as every other card.
        if CardGrammar.isOn, let onOpenSheet {
            onOpenSheet(suggestion)
            return
        }
        // The card's own tap IS the disclosure — open to the source email,
        // the chips and the reply controls; tap again to put it away.
        withAnimation(DS.Motion.standard) {
            isExpanded.toggle()
            // Closing the card resets its groups, so the next open starts on
            // the counts rather than on whatever was left uncovered.
            if !isExpanded {
                showsAllThreads = false
                showsAllAttachments = false
            }
        }
    }

    // MARK: - Swipe (UpdateCard's mechanics, verbatim numbers)

    private var swipeAffordance: some View {
        HStack {
            Spacer(minLength: 0)
            if dragOffset < 0 {
                Image(systemName: "trash")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xFF3B30))
                    .frame(width: 42, height: 42)
                    .background(Color(hex: 0xFF3B30).opacity(0.12), in: Circle())
                    .padding(.trailing, 28)
                    .transition(.opacity)
            }
        }
        .opacity(min(abs(dragOffset) / 48.0, 1.0))
    }

    private var cardFill: Color {
        guard dragOffset != 0 else { return DS.Palette.card }
        let intensity = min(abs(dragOffset) / commitDistance, 1)
        return DS.Palette.card.mix(with: Color(hex: 0xFF3B30).opacity(0.10 + 0.16 * intensity), by: 0.48)
    }

    private func handleSwipeChanged(translation: CGSize) {
        // A finger that is (or just was) on the mic never drags the card —
        // the hold claims the touch from touch-down (VoiceHoldClaim), before
        // the swipe's recognition threshold.
        guard !isCompletingSwipe, !isHoldingVoice, !VoiceHoldClaim.shared.isActive else { return }
        isSwipeActive = true
        DSInteractionGate.suppressTaps()
        dragOffset = min(0, rubberBand(translation.width, limit: maxDrag))
        let pastCommit = abs(dragOffset) > commitDistance
        if pastCommit, !wasPastCommitThreshold {
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.prepare()
            generator.impactOccurred(intensity: 0.82)
        }
        wasPastCommitThreshold = pastCommit
    }

    private func handleSwipeEnded(translation: CGSize) {
        defer {
            isSwipeActive = false
            wasPastCommitThreshold = false
        }
        guard !isCompletingSwipe, isSwipeActive, !isHoldingVoice else { return }
        DSInteractionGate.suppressTaps()
        if translation.width < -commitDistance {
            completeSwipe()
        } else {
            withAnimation(.smooth(duration: 0.2, extraBounce: 0)) { dragOffset = 0 }
        }
    }

    private func completeSwipe() {
        isCompletingSwipe = true
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 1)
        withAnimation(.smooth(duration: 0.12, extraBounce: 0)) { dragOffset = -430 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            CardActivityLedger.shared.forget(suggestion.id)
            onDelete(suggestion)
            isCompletingSwipe = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { dragOffset = 0 }
        }
    }

    private func rubberBand(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        let sign: CGFloat = value < 0 ? -1 : 1
        let magnitude = abs(value)
        guard magnitude > limit else { return value }
        return sign * (limit + (magnitude - limit) * 0.18)
    }
}

// MARK: - Source email tile

/// The card's (and reply sheet's) pointer at the source thread: one plain
/// link row — mail glyph, "View email", chevron — matching the calendar
/// card's "View event" exactly. It used to carry the
/// senders' faces, the subject and a meta line, which repeated the logo
/// already sitting on the card's own header and spent three elements saying
/// what one row says. Bare, so it sits directly on the card: a filled bar
/// competed with the plate and a raised tile popped off it.
struct CardSourceTile: View {
    /// Whose conversation this is — set only when the card offers SEVERAL, so
    /// the rows can be told apart. Nil keeps the plain "View email".
    var label: String?

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "envelope")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Palette.placeholder)
                .frame(width: 14)
            Text(label ?? String(localized: "View email"))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(DS.Palette.ink)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(DS.Palette.placeholder)
        }
        .padding(.vertical, 3)
        // A bare row has no plate to catch the tap — its own bounds are the
        // target.
        .contentShape(Rectangle())
    }
}

/// One row standing in for several: "View emails (3)", "See attachments (2)".
///
/// Its chevron points DOWN and flips, where `CardSourceTile` and
/// `CardAttachmentTile` point right: on this card a right chevron has always
/// meant "this opens a sheet", so a row that merely uncovers other rows must
/// not wear one. Same glyph column, weight and metrics as the rows it hides,
/// so the group reads as their heading rather than a control of its own kind.
struct CardGroupTile: View {
    let icon: String
    /// Already counted ("View emails (3)") — the caller localizes, since the
    /// noun and its number belong in one phrase for translators.
    let label: String
    let isOpen: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Palette.placeholder)
                .frame(width: 14)
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(DS.Palette.ink)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(DS.Palette.placeholder)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

// MARK: - Card mail models

/// A reply waiting to be looked over: the drafted body, plus how it goes out
/// if the user presses Send.
struct CardComposeTarget: Identifiable {
    /// Two ways a card can send. A card carrying a `reply_send` action has a
    /// rail already (server-side draft ids, the card's settle copy); a card
    /// that only knows which thread it came from has none, so its reply goes
    /// out through the ordinary compose send.
    enum Route {
        case action(GeneratedAction)
        case stored(SuggestionActionItem)
        /// No card rail — the ordinary compose send, in Reply mode when the
        /// target carries a `replyTo`, as a fresh mail when it doesn't.
        case direct
    }

    let route: Route
    let body: String
    let recipients: [ComposeRecipient]
    let subject: String
    let replyTo: ComposeReplyContext?

    var id: String {
        switch route {
        case let .action(action): action.id
        case let .stored(item): item.id.uuidString
        case .direct: "direct|\(subject)"
        }
    }
}


/// One conversation the card offers, with the name it wears when several are
/// shown side by side.
struct CardMailThread: Identifiable, Hashable {
    let ref: MailThreadRef
    let label: String?

    var id: String { ref.id }
}

/// One file, bound to the conversation it came off — a card spanning several
/// threads must know WHICH mailbox thread to fetch each attachment from.
struct CardAttachment: Identifiable, Hashable {
    let ref: MailThreadRef
    let file: MailAttachmentRef

    var id: String { "\(ref.id)|\(file.id)" }
}

// MARK: - Attachment tile

/// A file the mail carried, named rather than filed: "See invoice", not
/// "INV-8837_ACME_final_v2.pdf". The real filename is one
/// tap away in the sheet's header, where the user is actually asking "which
/// file is this" — on the card the question is "what IS it".
///
/// Same glyph/label/chevron metrics as `CardSourceTile`, so the mail and its
/// files stack as one block instead of two competing treatments.
struct CardAttachmentTile: View {
    let file: MailAttachmentRef

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "paperclip")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Palette.placeholder)
                .frame(width: 14)
            Text(MailAttachmentName.label(filename: file.filename, mimeType: file.mimeType))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(DS.Palette.ink)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(DS.Palette.placeholder)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

// MARK: - Chip label

/// One chip's ink, shared by the card and its reply sheet so the two can't
/// drift: the quiet capsule, plus `arrow.up.right` when the tap LEAVES the app
///. "Pay invoice" and "Reply" are both buttons on the same
/// rail, and only one of them hands you to Safari — the arrow is what says so
/// before the tap, not after.
struct CardChipLabel: View {
    let chip: CardChipAction

    var body: some View {
        HStack(spacing: 5) {
            Text(chip.label)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            if chip.isLink {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .foregroundStyle(DS.Palette.inkSoft)
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(Capsule().fill(DS.TaskState.chipFill))
        .padding(.vertical, 4)
        .contentShape(Capsule())
    }
}

// MARK: - Chip model

/// One chip model over both action families, shared by the card and its reply
/// sheet. Generated actions win when any renderable one exists (they carry
/// richer typed outcomes); legacy stored actions are the fallback; an update
/// with no actions gets the synthesized "Done" clear chip. Capped at 4 —
/// past that, the reply field carries it (design rule, round 3).
enum CardChipAction: Identifiable {
    case stored(SuggestionActionItem)
    case generated(GeneratedAction)

    var id: String {
        switch self {
        case let .stored(item): item.id.uuidString
        case let .generated(action): "g-\(action.id)"
        }
    }

    var label: String {
        // Labels are the BACKEND's to write and are shown verbatim
        // No client hardcoding — future per-user customization.
        // lives server-side; a chip may well SAY "Send reply"). The client's
        // guarantee is behavioral only: a draft chip ROUTES to the composer,
        // never a blind send.
        switch self {
        case let .stored(item): Self.displayLabel(item.label)
        case let .generated(action): Self.displayLabel(action.label)
        }
    }

    /// Whether tapping this hands the user to a browser. Both action families
    /// spell the same thing differently, and both end at `openURL` — the chip
    /// wears an arrow so leaving the app is never a surprise.
    var isLink: Bool {
        switch self {
        case let .stored(item): item.type == "open_link"
        case let .generated(action): action.kind == .openLink
        }
    }

    /// The clear affordance reads "Done" everywhere — a backend-authored
    /// "Got it" is the same act under the retired wording.
    private static func displayLabel(_ label: String) -> String {
        label.compare("Got it", options: [.caseInsensitive]) == .orderedSame
            ? String(localized: "Done") : label
    }

    static func actions(for suggestion: Suggestion) -> [CardChipAction] {
        let renderable = suggestion.generatedActions.filter { action in
            switch action.kind {
            case .replySend, .replyOption, .createMeeting, .remind, .startTask, .openLink: true
            case .acknowledge, .unknown: false
            }
        }
        if !renderable.isEmpty { return renderable.prefix(4).map(CardChipAction.generated) }

        var stored = suggestion.actions
        // An invite is answered by its RSVP, and the RSVP is the one that
        // actually moves the calendar — so a drafted "Reply accepting" next to
        // "Accept invite" asks the same question twice.
        // The RSVP pair leads, accept before decline, and the drafts step
        // aside; replying in words is still a keyboard tap away.
        let rsvp = stored
            .filter { $0.type == "rsvp_accept" || $0.type == "rsvp_decline" }
            .sorted { ($0.type == "rsvp_accept" ? 0 : 1) < ($1.type == "rsvp_accept" ? 0 : 1) }
        if !rsvp.isEmpty {
            stored = rsvp + stored.filter {
                $0.type != "rsvp_accept" && $0.type != "rsvp_decline" && $0.type != "send_draft"
            }
        }
        // "Got it" is a button for nothing beside real choices — it survives
        // only when it IS the only choice.
        let decisions = stored.filter { $0.type != "acknowledge" }
        if !decisions.isEmpty { stored = decisions }

        // No synthesized "Done": a card with nothing to
        // act on is cleared by the swipe it already has — a chip that only
        // repeats the swipe is a button for nothing.
        return stored.prefix(4).map(CardChipAction.stored)
    }
}

// MARK: - Reply order

/// An order a reply asked for, resolved against the card: the card button it
/// presses (if any), the work the buttons don't cover, and the words the toast
/// shows while both wait out the undo window.
struct CardReplyOrder {
    var chip: CardChipAction?
    /// Freeform work for the agent, run AFTER the button — "decline this and
    /// then email him" is one order in one undo window, in that order.
    var instruction: String?
    var toast: String
}

// MARK: - Activity ledger

/// Working/settled state for universal cards, keyed by card id and held OFF
/// the view so a LazyVStack recycling a row (or a long reply stream outliving
/// it) never loses the state. Also owns the voice-reply pipeline: transcribe
/// the held clip server-side, then stream the words onto the card's side
/// thread — the exact typed path the reply sheet uses.
@MainActor
final class CardActivityLedger: ObservableObject {
    static let shared = CardActivityLedger()

    enum Activity: Equatable {
        case working(String)
        case settled(String)
    }

    /// Iris's answer to a free-text reply, rendered at the BOTTOM OF THE CARD
    /// instead of vanishing onto the side thread behind a
    /// "Reply sent." receipt. Held here, not in the view, for the ledger's
    /// usual reason — a scrolled-away row is recycled and a long stream
    /// outlives it.
    struct Answer: Equatable {
        var text: String
        /// Tokens still arriving: the card keeps its rim lit.
        var isStreaming: Bool
    }

    @Published private(set) var activities: [UUID: Activity] = [:]
    @Published private(set) var answers: [UUID: Answer] = [:]
    /// Drafted replies waiting on the user, keyed by card — held HERE so an
    /// ✕-ed composer doesn't evaporate the words. The card renders an "Open
    /// draft" row while one exists; sending clears it
    /// dismissing the sheet must never lose the draft, and nothing else may
    /// run while it waits).
    @Published private(set) var drafts: [UUID: CardComposeTarget] = [:]

    // ── Draft persistence ────────────────────────────────────────────────
    // The ledger dies with the process, but a waiting draft must not — the
    // ✕-ed-composer doctrine extends to relaunch (quitting
    // the app replaced "See draft" with the side thread's restored prose).
    // Only the `.direct` route persists: it's the only route stashDraft ever
    // receives (a model-written reply), and the only one that's plain data.

    private struct PersistedDraft: Codable, Sendable {
        var body: String
        var recipients: [ComposeRecipient]
        var subject: String
        var replyTo: ComposeReplyContext?
        var savedAt: Date
    }

    private static let draftsKey = "universal-card.drafts"
    /// Entries older than this drop on load — a draft untouched for a week
    /// belongs to a card that's long since left Home.
    private static let draftLifetime: TimeInterval = 7 * 24 * 3600

    /// When each draft was stashed — carried through saves so a draft's age
    /// is measured from its stash, not from the last unrelated persist.
    private var draftSavedAt: [UUID: Date] = [:]

    private init() {
        let stored: [String: PersistedDraft] = SnapshotCache.load(Self.draftsKey) ?? [:]
        let cutoff = Date().addingTimeInterval(-Self.draftLifetime)
        for (key, draft) in stored {
            guard let id = UUID(uuidString: key), draft.savedAt > cutoff else { continue }
            drafts[id] = CardComposeTarget(
                route: .direct,
                body: draft.body,
                recipients: draft.recipients,
                subject: draft.subject,
                replyTo: draft.replyTo
            )
            draftSavedAt[id] = draft.savedAt
        }
    }

    private func persistDrafts() {
        var stored: [String: PersistedDraft] = [:]
        for (id, target) in drafts {
            guard case .direct = target.route else { continue }
            stored[id.uuidString] = PersistedDraft(
                body: target.body,
                recipients: target.recipients,
                subject: target.subject,
                replyTo: target.replyTo,
                savedAt: draftSavedAt[id] ?? Date()
            )
        }
        SnapshotCache.save(stored, to: Self.draftsKey)
    }

    func activity(for id: UUID) -> Activity? { activities[id] }
    func setWorking(_ id: UUID, _ status: String) { activities[id] = .working(status) }
    func settle(_ id: UUID, _ receipt: String) { activities[id] = .settled(receipt) }
    func clear(_ id: UUID) { activities[id] = nil }

    func answer(for id: UUID) -> Answer? { answers[id] }

    func draft(for id: UUID) -> CardComposeTarget? { drafts[id] }

    func stashDraft(_ id: UUID, _ target: CardComposeTarget) {
        drafts[id] = target
        draftSavedAt[id] = Date()
        persistDrafts()
    }

    func clearDraft(_ id: UUID) {
        drafts[id] = nil
        draftSavedAt[id] = nil
        persistDrafts()
    }

    /// Paint a saved answer back onto a reopened card (the card's side thread,
    /// re-read from the server). Never overwrites a live one — a restore fetch
    /// that lands mid-stream must not clobber the tokens already on screen.
    func restoreAnswer(_ id: UUID, text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, answers[id] == nil else { return }
        answers[id] = Answer(text: text, isStreaming: false)
    }

    /// Drop everything held for a card — the swipe-dismiss path.
    func forget(_ id: UUID) {
        activities[id] = nil
        answers[id] = nil
    }

    /// Transcribe a finished hold (server STT — there is no on-device path)
    /// and send the words as the card's reply. A clip that transcribes to
    /// nothing quietly returns the card to idle.
    func beginVoiceReply(
        clip: URL,
        duration: TimeInterval,
        suggestion: Suggestion,
        home: HomeStore,
        api: APIClient,
        onOrder: @escaping @MainActor (CardDirective.Order) -> Void
    ) {
        setWorking(suggestion.id, String(localized: "On it…"))
        // Drop the previous answer at the START of the hold's round trip, not
        // when the stream finally opens: transcription takes a beat, and
        // leaving the last answer sitting under an "On it…" shimmer reads as
        // if Iris were answering the OLD question again.
        answers[suggestion.id] = nil
        Task {
            let transcript = (try? await api.transcribeVoice(
                fileURL: clip, durationMs: Int(duration * 1000)
            ))?.transcript
            try? FileManager.default.removeItem(at: clip)
            let text = (transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                self.clear(suggestion.id)
                return
            }
            await self.sendReply(text, suggestion: suggestion, home: home, onOrder: onOrder)
        }
    }

    /// Stream one reply onto the card's side thread (created on first use,
    /// resumed forever after — SuggestionChatSheet's exact contract, including
    /// the context seed on the first turn). The working shimmer holds the
    /// footer until the FIRST TOKEN; from there the words land in the card's
    /// own answer block and stream in place.
    ///
    /// If the reply turns out to be an ORDER, `onOrder` takes over and this
    /// turn leaves nothing on the card: the order's own finish state (card off
    /// Home, toast, Undo) is the receipt.
    func sendReply(
        _ text: String,
        suggestion: Suggestion,
        home: HomeStore,
        /// Photos and the one document staged on the reply bar. The transport
        /// has always carried them; only the card path never passed any.
        images: [Data] = [],
        file: ChatFileAttachment? = nil,
        onOrder: @escaping @MainActor (CardDirective.Order) -> Void
    ) async {
        let id = suggestion.id
        setWorking(id, Self.workingLabel(for: text))
        // A new ask replaces the previous answer: the card shows the LATEST
        // exchange, and the whole conversation stays readable in the sheet.
        answers[id] = nil
        let savedThread = suggestion.chatThreadId ?? home.sideThreadId(for: id)
        let chips = CardChipAction.actions(for: suggestion)
        let outbound = Self.outbound(text, suggestion: suggestion, chips: chips, isFirstTurn: savedThread == nil)
        // "Accept it", or "decline and email him" — an ORDER, not a question.
        // The reply may open with a directive; the head of the stream is held
        // back until that's ruled in or out, so markup never flashes as text.
        let scan = DirectiveScan()
        let (newThread, streamError) = await home.streamSuggestionReply(
            outbound, threadId: savedThread, images: images, file: file
        ) { [weak self] event in
            guard let self else { return }
            switch event {
            case let .delta(chunk):
                guard !scan.fired else { return }
                if !scan.settled {
                    scan.head += chunk
                    switch CardDirective.read(scan.head) {
                    case .pending:
                        return // still ambiguous — hold the words back
                    case let .order(order):
                        // A button number that doesn't exist is dropped rather
                        // than guessed — a card must never run an action the
                        // user didn't ask for because a model miscounted. What
                        // it said in words still stands.
                        var order = order
                        if let button = order.button, !chips.indices.contains(button - 1) {
                            order.button = nil
                        }
                        guard !order.isEmpty else {
                            scan.settled = true
                            scan.head = ""
                            return
                        }
                        // The card is about to leave Home with an undo toast
                        // of its own — no shimmer, no answer block, nothing
                        // left behind on a row that's animating out.
                        scan.fired = true
                        self.forget(id)
                        onOrder(order)
                        return
                    case .plain:
                        scan.settled = true
                    }
                }
                let words = scan.head.isEmpty ? chunk : scan.head
                scan.head = ""
                if self.answers[id] == nil {
                    // First token: the answer block takes over from the
                    // shimmer, so the chips and rail come back while Iris
                    // keeps talking underneath them.
                    self.answers[id] = Answer(text: words, isStreaming: true)
                    self.clear(id)
                } else {
                    self.answers[id]?.text += words
                }
            case let .thread(threadId):
                // The user turn just persisted server-side — record the
                // card→thread link now, so closing the app mid-reply doesn't
                // orphan it.
                if savedThread == nil { home.recordSideThread(threadId, for: id) }
            default:
                break
            }
        }
        if let newThread { home.recordSideThread(newThread, for: id) }
        // The order was handed off: its own finish state (card off Home, toast,
        // Undo) is the receipt, so this turn leaves no trace on the card.
        if scan.fired { return }
        // A reply that ended still looking like a half-typed directive was
        // never one — release the held head rather than swallowing it.
        if !scan.head.isEmpty {
            answers[id] = Answer(text: (answers[id]?.text ?? "") + scan.head, isStreaming: false)
            clear(id)
        }
        answers[id]?.isStreaming = false
        // A model that NARRATED a directive instead of issuing one leaves
        // markup in the prose. Only a leading directive presses anything, so
        // scrub the rest before it settles on the card.
        if let text = answers[id]?.text, text.contains(CardDirective.open) {
            answers[id]?.text = CardDirective.stripped(text)
        }
        let spoke = !(answers[id]?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // Words on the card ARE the receipt; keep the card whole so the answer
        // can be read (and replied to) in place. A turn that produced NO words
        // leaves the card exactly as it was — the old "Reply sent." receipt is
        // retired: it collapsed the card to a dead line
        // that claimed something had been sent, on a turn that either did
        // nothing or handed real work to an order that shows its own toast.
        clear(id)
        if !spoke { answers[id] = nil }
        _ = streamError // the failure toast is HomeStore.errorText's job
    }

    /// Carry out the freeform half of an order, once its undo window has
    /// lapsed: one more turn on the card's own thread, this time telling the
    /// agent to actually use its tools. Nothing is rendered — the card is gone
    /// and the toast already said what was happening; a transport failure
    /// surfaces through `HomeStore.errorText` like every other call.
    func carryOut(_ instruction: String, suggestion: Suggestion, home: HomeStore) async {
        let threadId = suggestion.chatThreadId ?? home.sideThreadId(for: suggestion.id)
        let outbound = Self.carryOutMessage(instruction)
        let (newThread, _) = await home.streamSuggestionReply(outbound, threadId: threadId) { event in
            if case let .thread(id) = event, threadId == nil {
                home.recordSideThread(id, for: suggestion.id)
            }
        }
        if let newThread { home.recordSideThread(newThread, for: suggestion.id) }
    }

    /// `On it — "book the 7am flight…"` — the working line quotes the ask.
    private static func workingLabel(for text: String) -> String {
        let clipped = text.count > 42 ? text.prefix(42) + "…" : text[...]
        return String(localized: "On it — \u{201C}\(String(clipped))\u{201D}")
    }

    /// What actually goes over the wire for one card reply.
    ///
    /// The FIRST turn carries SuggestionChatSheet's context seed — the backend
    /// has no dedicated suggestion→chat endpoint, so the seed is the card's
    /// only grounding — plus the card's rendering contract, which matters here
    /// and not in the sheet: on the card the answer lands alone under the
    /// chips with the user's question nowhere in sight (design —
    /// "make sure it references the question"), so a bare "Yes, 5pm works"
    /// would read as a non sequitur three cards down the feed.
    ///
    /// EVERY turn carries the button list, first or fifth: "accept it" is just
    /// as likely to be the second thing said as the first.
    /// `HomeStore.strippingContextSeed` hides the whole bracket from restored
    /// transcripts, and it strips per message, so later turns stay clean too.
    private static func outbound(
        _ userText: String,
        suggestion: Suggestion,
        chips: [CardChipAction],
        isFirstTurn: Bool
    ) -> String {
        var context = ""
        if isFirstTurn {
            context += "a suggestion I'm showing the user in their home feed: \"\(suggestion.message)\""
            let detail = suggestion.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            if !detail.isEmpty { context += " — \(detail)" }
            context += ". The user is replying to that suggestion."
            context += " Your reply is rendered inline at the bottom of that card and the user's question is NOT"
            context += " shown beside it, so make the answer stand on its own: name what they asked about in your"
            context += " first sentence, then answer it. Two or three sentences, no greeting, no sign-off."
        }
        if !context.isEmpty { context += " " }
        if chips.isEmpty {
            context += "This card has no buttons of its own."
        } else {
            let list = chips.enumerated()
                .map { "\($0.offset + 1) = \"\($0.element.label)\"" }
                .joined(separator: ", ")
            context += "The card's own buttons are: \(list)."
        }
        context += " Do NOT use your tools on this turn. If the user is TELLING you to do something rather than"
        context += " asking, reply with exactly one directive and nothing else:"
        context += " \(CardDirective.open){\"button\":N,\"reply\":\"…\",\"agent\":\"…\",\"toast\":\"…\"}\(CardDirective.close)."
        context += " \"button\" is one of the numbers above when a button does part of the job — omit it otherwise."
        context += " \"reply\" is the answer to THIS EMAIL, written out. Any order to write back — \"reply saying"
        context += " yes\", \"tell her monday works\", \"send a reply saying I'm not interested\", \"reply to"
        context += " connor saying hi\" — is a \"reply\", never an \"agent\" errand. Put the MAIL ITSELF there:"
        context += " the full body, first person, in the user's voice, ready to send, no subject line, no greeting"
        context += " placeholder, no sign-off. \"reply to connor saying hi\" is the instruction; \"Hi Connor —"
        context += " hi back!\" is the reply, and the reply is what goes in the field. The app opens it in the"
        context += " mail composer so the user reads it and decides — writing it here is what STOPS it being"
        context += " sent behind their back."
        context += " \"agent\" is work that is NOT writing back on this email and NOT covered by a button,"
        context += " written as an instruction to yourself, in order — chasing someone in three days, finding"
        context += " another restaurant, looking up a failing run. NEVER put a reply to this email here, in any"
        context += " form: if the job includes writing back, the words go in \"reply\" and only the REST goes"
        context += " here. A whole chain still belongs in one directive (button 2 to decline, \"reply\" carrying"
        context += " the note that goes with it). Omit it when a button or the reply is the entire job."
        context += " \"toast\" is 2–5 words, present tense, naming what is about to happen (\"Declining\")."
        context += " The app shows the user that toast with an Undo and only then carries the whole order out —"
        context += " which is exactly why you must not do any of it yourself."
        context += " Anything you can't do, say so in words instead of ordering it."
        context += " If they are ASKING something, even a question that mentions an action, answer in words and"
        context += " issue no directive."
        return "[Context — " + context + "]\n\n" + userText
    }

    /// The follow-up turn that actually does the work, sent once the undo
    /// window lapses. The answering turn was told to keep its hands off the
    /// tools; this one is the opposite instruction.
    private static func carryOutMessage(_ instruction: String) -> String {
        "[Context — the user confirmed this from a card in their home feed and the undo window has passed."
            + " Carry it out now with your tools, in the order given. Don't ask for confirmation and don't"
            + " reply with an explanation — just do it: \(instruction)]"
    }

    // MARK: Directive

    /// Mutable scan state for one stream: the held-back head of the reply, and
    /// whether the directive question has been answered yet.
    final class DirectiveScan {
        var head = ""
        /// The head is known to be ordinary words — stop holding it back.
        var settled = false
        /// A button was pressed; this turn is over as far as the card cares.
        var fired = false
    }
}

// MARK: - Listening glow rim

/// The pastel conic sweep behind a listening card — blurred so only a soft
/// 3pt halo escapes the plate. Dimmed + slowed while working; reduce-motion
/// renders it static.
struct ListeningGlowRim: View {
    let cornerRadius: CGFloat
    let dimmed: Bool
    let reduceMotion: Bool

    private var period: TimeInterval { dimmed ? 4.5 : 2.6 }

    var body: some View {
        Group {
            if reduceMotion {
                rim(angle: .degrees(0))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: period) / period
                    rim(angle: .degrees(360 * t))
                }
            }
        }
        .opacity(dimmed ? 0.55 : 0.95)
        .allowsHitTesting(false)
    }

    private func rim(angle: Angle) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                AngularGradient(
                    colors: DS.Palette.listeningGlow,
                    center: .center,
                    angle: angle
                )
            )
            .blur(radius: 7)
    }
}

// MARK: - Rail flow layout

/// The universal card's footer layout: chips flow left-to-right and wrap; the
/// LAST subview (the keyboard + mic rail) rides the final chip line, pinned
/// trailing — dropping to its own trailing line only when that line is full
/// (design rule, round 3: "the rail shares the last chip line").
struct RailFlowLayout: Layout {
    var spacing: CGFloat = 7
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let frames = arrange(subviews: subviews, maxWidth: maxWidth)
        let height = frames.map(\.maxY).max() ?? 0
        let width = maxWidth == .infinity ? (frames.map(\.maxX).max() ?? 0) : maxWidth
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let frames = arrange(subviews: subviews, maxWidth: bounds.width)
        for (index, frame) in frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [CGRect] {
        guard !subviews.isEmpty else { return [] }
        var frames = [CGRect](repeating: .zero, count: subviews.count)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        let railIndex = subviews.count - 1
        for index in 0 ..< railIndex {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            frames[index] = CGRect(origin: CGPoint(x: x, y: y), size: size)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        let railSize = subviews[railIndex].sizeThatFits(.unspecified)
        if railIndex > 0, x + railSize.width > maxWidth {
            // The last chip line is full — the rail takes a fresh line,
            // still pinned trailing.
            y += rowHeight + lineSpacing
            rowHeight = 0
        }
        let lineHeight = max(rowHeight, railSize.height)
        frames[railIndex] = CGRect(
            x: max(0, maxWidth == .infinity ? x : maxWidth - railSize.width),
            y: y + (lineHeight - railSize.height) / 2,
            width: railSize.width,
            height: railSize.height
        )
        // Center the line's chips against the (taller) rail sharing it.
        for index in 0 ..< railIndex where frames[index].minY == y {
            frames[index].origin.y = y + (lineHeight - frames[index].height) / 2
        }
        return frames
    }
}

// MARK: - Reply sheet (keyboard affordance)

/// The keyboard button's sheet — a SMALL half-height surface: the face, the title, the body, and the bar. Nothing else. No
/// source row, no chips — you came here to type, and every one of those lives
/// on the card you opened it from, one tap away.
///
/// The bar is the REAL home bar on a bottom safeAreaInset — same "Ask Iris
/// anything" capsule, same floating "+" over the same media strip, same rigid
/// width, riding the sheet's bottom edge at the screen's bottom, so it never
/// reads as a second bar swapped in for the one the hand was already on. Same
/// construction as "View email".
///
/// Anything done here closes the sheet and the card behind it animates
/// working → receipt. The card does NOT collapse when the sheet opens.
struct CardReplySheet: View {
    let suggestion: Suggestion
    /// The header face the card settled on — passed down so the sheet's header
    /// doesn't disagree with the card it opened from.
    var resolvedSenderEmail: String?
    /// Words plus whatever the bar staged — the reply bar is the HOME bar, so
    /// it can send the photo or the document the card is asking about.
    let onSendText: (String, [Data], ChatFileAttachment?) -> Void
    /// A released voice memo.
    let onVoiceClip: (URL, TimeInterval) -> Void

    // Optional: preview rigs may present this sheet without ProfileStore.
    @Environment(ProfileStore.self) private var profile: ProfileStore?
    private var assistantName: String { profile?.assistantName ?? ProfileStore.defaultAssistantName }
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    /// The shared staging object — the same one the mail sheet and the main
    /// chat use, so the cap, the JPEG normalization and the QuickLook preview
    /// are the ones already written rather than another copy.
    @State private var staging = ComposerAttachmentStaging()
    @FocusState private var composerFocused: Bool

    /// The sheet HUGS its content: a face, a title and a
    /// body do not earn half the screen, and the gap under them read as a
    /// layout bug rather than as air. Measured, not summed — the title wraps to
    /// two or three lines and the body has no clamp here, so there is no
    /// constant to add up.
    @State private var headHeight: CGFloat = 0
    @State private var barHeight: CGFloat = 0
    /// The home indicator's strip. A `.height()` detent is measured from the
    /// screen's bottom edge, so it has to carry this or the bar rides too low.
    @State private var bottomInset: CGFloat = 0

    /// Air between the body's last line and the bar.
    private static let headToBar: CGFloat = 20

    private var sheetHeight: CGFloat {
        // The floor covers the first layout pass, which reports nothing: a
        // detent of ~0 would present a sliver and then grow it.
        max(headHeight + Self.headToBar + barHeight + bottomInset, 190)
    }

    private var isUpdate: Bool { suggestion.section == .updates }

    private var titleLine: String {
        isUpdate ? suggestion.updateHeaderLine : suggestion.proposalLine
    }

    private var contextText: String? {
        let line = suggestion.contextLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !titleLine.hasPrefix(line), !line.hasPrefix(titleLine) else { return nil }
        return line
    }

    var body: some View {
        ZStack(alignment: .top) {
            DS.Palette.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                // The card's own head, and only its head: the mark indenting
                // the title + body, the age on the title's first line. The body
                // is unclamped here — the card's three-line squeeze is what you
                // opened this to get past.
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        SuggestionEntryAvatar(suggestion: suggestion, size: 38, resolvedSenderEmail: resolvedSenderEmail)
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(titleLine)
                                    .font(.system(size: 17, weight: .semibold))
                                    .tracking(-0.3)
                                    .foregroundStyle(DS.Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 6)
                                Text(suggestion.ageLabel)
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Palette.placeholder)
                                    .fixedSize()
                            }

                            if let context = contextText {
                                Text(context)
                                    .font(.system(size: 13, weight: .regular))
                                    .tracking(-0.10)
                                    .foregroundStyle(DS.Palette.inkMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 6)
                            }
                        }
                    }

                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                // 22, the mail sheet's own header offset — the two sheets a
                // card opens start their first line on the same rule, and it
                // clears the system drag indicator that replaced the
                // hand-drawn grabber.
                .padding(.top, 22)
                // Measured WITH the top padding, so `sheetHeight` adds only the
                // gap and the bar to it.
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { headHeight = $0 }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // Read BEFORE the bar's inset consumes it (modifier order matters here).
        // CLAMPED: the keyboard is a bottom safe area too, and this sheet raises
        // it on appear — an unclamped read would add ~336pt to the detent and
        // the "fitted" sheet would spring to nearly full height the moment the
        // field focused. Nothing but the home indicator belongs in this number.
        .onGeometryChange(for: CGFloat.self, of: { min($0.safeAreaInsets.bottom, 44) }) { bottomInset = $0 }
        // The HOME bar, not a bar of this sheet's own: same
        // capsule, same floating "+", same mic, same placeholder, same rigid
        // width — and riding a safeAreaInset on the sheet's bottom edge, which
        // IS the screen's bottom edge, so it lands where the bar the hand was
        // already on sits. Exactly what "View email" does.
        .safeAreaInset(edge: .bottom) {
            PersonaComposer(
                draft: $draft,
                isFocused: $composerFocused,
                onSend: sendTyped,
                onVoiceMessage: { url, duration in
                    dismiss()
                    onVoiceClip(url, duration)
                },
                hasAttachment: !staging.isEmpty,
                pendingImages: staging.images,
                onRemoveImage: staging.removeImage,
                pendingFile: staging.file,
                onRemoveFile: staging.clearFile,
                onTapFile: staging.previewFile,
                // Wired, so the "+" is real: the menu offers exactly what this
                // bar can actually send, which is the rule that keeps it from
                // rendering rows that swallow the tap.
                onCamera: { composerFocused = false; staging.openCamera() },
                onPhotoLibrary: { composerFocused = false; staging.openLibrary() },
                onAttachFile: { composerFocused = false; staging.openFiles() },
                // The + keeps its slot (so the capsule keeps the home bar's
                // width) but stays stepped back: a card reply is words, voice or
                // nothing, and the handlers below are wired only so lifting this
                // gives a working menu instead of dead rows.
                attachDimmed: true,
                // Flat sheet, not the feed: the glass has nothing to refract
                // here, so the capsule and the + take a real fill + hairline or
                // they dissolve into the background.
                onFlatSurface: true,
                // One entry, so the home bar's cycling prompts don't run here:
                // this bar has one job — hand the card to Iris — and says so.
                placeholderPrompts: [String(localized: "How should I handle this?")],
                // A SHEET tracks every vertical drag, so a hold-to-record
                // slide-up dies as touchesCancelled without this — an instant
                // silent delete instead of release-to-delete.
                isHostedInScrollView: true,
                assistantName: assistantName
            )
            .padding(.bottom, 10)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { barHeight = $0 }
            .composerAttachments(staging) { composerFocused = true }
        }
        // Fitted, not half: the sheet is exactly its content
        // plus its bar. One detent, so it can't be dragged taller either.
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .dsAppearance()
        .onAppear {
            // The keyboard button means "I want to type" — focus the field.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { composerFocused = true }
        }
    }

    /// A staged photo or document is a message on its own — the send stays live
    /// with an empty field, same rule as the mail sheet's bar.
    private func sendTyped() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !staging.isEmpty else { return }
        DSHaptics.tap()
        draft = ""
        let taken = staging.take()
        dismiss()
        onSendText(text, taken.images, taken.file)
    }
}
