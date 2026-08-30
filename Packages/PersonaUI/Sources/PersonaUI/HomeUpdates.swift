import Foundation
import PersonaCore
import PersonaDesign
import PersonaService
import SwiftUI
import UIKit

/// One Home "Updates" card: a see-only notice (sign-in code, mail heads-up,
/// fired reminder, schedule change) — content that used to spam the main chat
/// as proactive bubbles. Each update is its OWN compact white plate, same
/// language as the Task/Suggestion cards, just shorter: avatar, one title
/// line, a detail line, the age stamp.
///
/// Interactions mirror SuggestionCard exactly:
/// - swipe LEFT to dismiss (same rubber-band + commit haptic + fling; the
/// caller funnels into the shared undo toast + backend dismiss),
/// - tap pushes the update's detail page (source email + the update line),
/// - the "See email" chip opens the source email as a sheet,
/// - sign-in codes are the exception: the code renders big with a Copy chip
/// and the tap copies instead of opening anything.
struct UpdateCard: View, Equatable {
    /// Same value-input gate as SuggestionCard — Home re-evaluates its body on
    /// every task poll and hands each row new closures; nothing about this
    /// card changes unless one of these does.
    nonisolated static func == (lhs: UpdateCard, rhs: UpdateCard) -> Bool {
        lhs.suggestion == rhs.suggestion
            && lhs.isUnread == rhs.isUnread
            && lhs.showsKindTag == rhs.showsKindTag
            && (lhs.onRemind == nil) == (rhs.onRemind == nil)
            && (lhs.onComposeReply == nil) == (rhs.onComposeReply == nil)
    }

    let suggestion: Suggestion
    let isUnread: Bool
    /// Open the update's detail page (non-code rows).
    let onTap: () -> Void
    /// The code was copied (mark seen upstream).
    let onCopyCode: () -> Void
    /// Swipe-dismiss committed — same contract as SuggestionCard.onDelete.
    let onDelete: (Suggestion) -> Void
    /// The "See email" chip: open the source email as a sheet (the one sheet
    /// left on this card). Only offered when the row references a mail.
    var onSeeEmail: () -> Void = {}
    /// "See more" expanded the folded header — reading the full text IS
    /// reading the update, so the caller marks it seen (drops the unread
    /// weight) without navigating anywhere.
    var onMarkRead: () -> Void = {}
    /// Wear the quiet "UPDATE" kind tag above the title — on in the merged
    /// For-you deck (mixed with Suggestions), off on single-kind surfaces.
    var showsKindTag = false
    /// The code's countdown hit zero — the parent retires the row. Fired
    /// once, from a timer armed at the code's stated expiry.
    var onExpired: () -> Void = {}
    /// Wallet-pass rows: fetch the parked .pkpass bytes and present PassKit's
    /// add sheet (the parent owns the download + presentation).
    var onAddToWallet: () -> Void = {}
    /// The row's `open_link` chip: the parent runs the card's backend action
    /// (the server validates the URL and returns it) and opens the link.
    var onOpenLink: (SuggestionActionItem) -> Void = { _ in }
    /// The long-press menu's Snooze pick — same contract as
    /// SuggestionCard.onRemind (hide behind the undo window + server snooze).
    /// nil where the surface can't act; the menu attaches only when wired.
    var onRemind: ((Suggestion, SnoozePreset) -> Void)?
    /// The long-press menu's Reply — reply-to-this-card on the chat page
    /// (SuggestionCard.onComposeReply's contract).
    var onComposeReply: ((Suggestion) -> Void)?

    // Swipe state machine, same numbers as SuggestionCard (design-app port):
    // rubber-banded leftward drag, 74pt commit with a rigid haptic, fling off.
    @State private var dragOffset: CGFloat = 0
    @State private var isSwipeActive = false
    @State private var isCompletingSwipe = false
    @State private var wasPastCommitThreshold = false
    @State private var copied = false
    /// "See more" expanded the folded header text inline (session-local).
    @State private var textExpanded = false

    private let maxDrag: CGFloat = 104
    private let commitDistance: CGFloat = 74

    private var isCode: Bool { suggestion.kind == "signin-code" && suggestion.code != nil }

    /// An Apple Wallet pass parked by the backend — the row's whole point is
    /// the one-tap add, so the tap and the chip both hand over to PassKit.
    private var isWalletPass: Bool {
        suggestion.kind == "wallet-pass" && !(suggestion.walletPasses ?? []).isEmpty
    }

    /// The row's stored `open_link` action, if any. A card the engine demoted
    /// to see-only (its buttons were all user-owned) still carries the link it
    /// was demoted FOR — without this chip that button exists in the data but
    /// has no rendering path anywhere on the Updates surface.
    private var openLinkAction: SuggestionActionItem? {
        guard !isCode, !isWalletPass else { return nil }
        return suggestion.actions.first { $0.type == "open_link" }
    }

    /// "Anthropic" out of "Anthropic · sign-in code" — the tag names the
    /// service now that the tagged code row drops its header line.
    private var codeServiceName: String {
        let lead = suggestion.message.components(separatedBy: "·").first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return lead.isEmpty ? suggestion.message : lead
    }

    /// ~3 header lines at 15pt across the card's text column (~30 chars a
    /// line) — the fold point for "see more" (char heuristic,
    /// VoiceTranscriptCaption's pattern).
    private static let foldThreshold = 100
    /// The folded preview cut — well short of the threshold so "… see more"
    /// still lands ON the third line instead of pushing a fourth (a word may
    /// get dropped that 3 bare lines would have fit; that's the trade).
    private static let previewChars = 90

    /// Whether the header text runs long enough to fold behind "See more".
    private var needsFold: Bool {
        !isCode && suggestion.updateHeaderLine.count > Self.foldThreshold
    }

    /// Preview cut backwards to a whitespace so a word is never split, then
    /// shorn of trailing punctuation so the appended ellipsis never doubles
    /// up ("updated.…").
    private var headerPreview: String {
        var cut = String(suggestion.updateHeaderLine.prefix(Self.previewChars))
        if let lastBreak = cut.lastIndex(where: \.isWhitespace),
           cut.distance(from: lastBreak, to: cut.endIndex) < 30 {
            cut = String(cut[..<lastBreak])
        }
        cut = cut.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = cut.last, [".", ",", ";", ":"].contains(String(last)) {
            cut.removeLast()
        }
        return cut
    }

    /// The header with the fold toggle INLINE — "… See more" riding the third
    /// line (or " See less" trailing the full text), a tappable link run so
    /// the rest of the card keeps its open-the-page tap.
    private var foldableHeaderText: AttributedString {
        let headerLine = suggestion.updateHeaderLine
        guard needsFold else { return AttributedString(headerLine) }
        var out = AttributedString(textExpanded ? headerLine + " " : headerPreview + "… ")
        var toggle = AttributedString(
            textExpanded ? String(localized: "see less") : String(localized: "see more")
        )
        toggle.link = URL(string: "persona-card://toggle-fold")
        toggle.font = .system(size: 15, weight: .semibold)
        out += toggle
        return out
    }

    var body: some View {
        ZStack {
            swipeAffordance
            cardButton.offset(x: dragOffset)
        }
        // A dead code has no row: sleep out the code's stated life, then hand
        // the removal to the parent (the countdown label never needs to say
        // "Expired" on this surface — the row is gone at zero).
        .task(id: suggestion.id) {
            guard isCode, let until = suggestion.codeValidUntil ?? suggestion.expiresAt else { return }
            let interval = until.timeIntervalSinceNow
            if interval > 0 { try? await Task.sleep(for: .seconds(interval)) }
            guard !Task.isCancelled else { return }
            onExpired()
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
        // Same pager contract as SuggestionCard: a drag that starts on this
        // card never pages Home⇄Chat.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            SuggestionSwipeZones.update(suggestion.id, frame: frame)
        }
        .onDisappear { SuggestionSwipeZones.update(suggestion.id, frame: nil) }
    }

    // MARK: - Plate

    private var cardButton: some View {
        Group {
            if CardGrammar.isOn {
                grammarContent
            } else {
                legacyRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card)
                .fill(cardFill)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card))
        // The shared solid-plate shadow pair (Glass.solidCardPlate — painted
        // manually so the swipe tint can mix into the fill).
        .shadow(color: Color(light: 0x000000, dark: 0x000000, lightOpacity: 0.08, darkOpacity: 0), radius: 18, y: 8)
        .shadow(color: Color(light: 0x000000, dark: 0x000000, lightOpacity: 0.05, darkOpacity: 0), radius: 3, y: 1.5)
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card))
        .onTapGesture { headerTapped() }
        // A CONTAINER (SuggestionCard's pattern), not a stamped leaf id — a
        // bare identifier propagates onto every child and clobbers the "See
        // email" chip's own handle.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("update-card-\(suggestion.kind)")
        // Long-press → the same native context menu as a chat bubble
        // (SuggestionCard's treatment). Not on code/wallet rows: a sign-in
        // code expires on its own and a pass row's whole point is the
        // one-tap add — snoozing either is noise.
        .cardContextMenu(
            isEnabled: !isCode && !isWalletPass && (onRemind != nil || onComposeReply != nil),
            onReply: { onComposeReply?(suggestion) },
            onSnooze: onRemind == nil ? nil : { preset in onRemind?(suggestion, preset) }
        )
    }

    /// The deck's drawing for this row. A sign-in code is T3 (R14 — the one
    /// card allowed to be shaped like nothing else); everything else is the
    /// T1 led card, including the wallet pass.
    ///
    /// The code's countdown is rebuilt every second inside the TimelineView so
    /// it stays live. The tick is scoped to this subtree, exactly like the
    /// label it replaces, so the rest of Home never re-renders on it.
    @ViewBuilder
    private var grammarContent: some View {
        if isCode, let until = suggestion.codeValidUntil ?? suggestion.expiresAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = until.timeIntervalSince(context.date)
                let label = remaining > 0 ? Self.countdownLabel(remaining) : String(localized: "Expired")
                if case let .t3(model)? = suggestion.grammarDrawing(isUnread: isUnread, codeCountdown: label) {
                    GrammarT3Code(model: model, copied: copied).content
                }
            }
        } else if case let .t1(model)? = suggestion.grammarDrawing(isUnread: isUnread) {
            GrammarT1Card(model: model, onPillTap: grammarPillTapped).content
        } else {
            legacyRow
        }
    }

    /// The row's one pill. A pass hands over to PassKit, a stored `open_link`
    /// runs the backend action; anything else falls through to the plate's own
    /// tap, which is the card's door either way (R8).
    private func grammarPillTapped(_ index: Int) {
        guard !isCompletingSwipe, DSInteractionGate.allowsTap else { return }
        if isWalletPass {
            DSHaptics.tap()
            onAddToWallet()
        } else if let action = openLinkAction {
            DSHaptics.tap()
            onOpenLink(action)
        } else {
            headerTapped()
        }
    }

    private var legacyRow: some View {
        HStack(alignment: isCode ? .center : .top, spacing: 12) {
            // Same identity resolution as a suggestion's avatar: photo →
            // contact → brand mark → the kind's glyph badge (HomeMapper
            // guarantees a per-kind `systemIcon` fallback at map time).
            SuggestionEntryAvatar(suggestion: suggestion, size: 38)
            VStack(alignment: .leading, spacing: isCode ? 2.5 : 10) {
                VStack(alignment: .leading, spacing: 3) {
                    if showsKindTag {
                        // "UPDATE · 3m ago" — the age rides the tag line
                        // (the trailing stamp ate a column
                        // of card width for three words a line already fits).
                        // A code row's tag NAMES the service ("ANTHROPIC OTP")
                        // with the LIVE countdown to its expiry riding right
                        // of it — the header line is gone
                        // (the tag + code say everything), the trailing column
                        // keeps only the Copy chip.
                        HStack(spacing: 5) {
                            if isCode {
                                CardKindTag(label: "\(codeServiceName) OTP")
                                if let until = suggestion.codeValidUntil ?? suggestion.expiresAt {
                                    Text("·")
                                    codeCountdown(until: until)
                                }
                            } else {
                                CardKindTag(label: isWalletPass ? "Wallet" : "Update")
                                Text("·")
                                Text(Self.timeLabel(suggestion.createdAt))
                            }
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Palette.placeholder)
                    }
                    // HEADER ONLY: the one line
                    // the chat delivery used to carry (`updateHeaderLine`),
                    // full-bleed, no subtext. Long text folds at 3 lines
                    // behind "See more"; the toggle
                    // expands inline, everything else on the card still opens
                    // the detail page. Unread wears the weight (mail-app
                    // grammar) — no dot. A TAGGED code row skips the header
                    // entirely (the "ANTHROPIC OTP" tag carries the identity);
                    // tagless surfaces keep the one-line title.
                    if !(isCode && showsKindTag) {
                        Text(isCode ? AttributedString(suggestion.message) : foldableHeaderText)
                            .font(.system(size: 15, weight: isUnread ? .semibold : .regular))
                            .tracking(-0.24)
                            .foregroundStyle(DS.Palette.ink)
                            // The inline See more/less link renders in the tint.
                            .tint(DS.Palette.inkSoft)
                            .lineLimit(isCode ? 1 : nil)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .environment(\.openURL, OpenURLAction { _ in
                                guard !isCompletingSwipe, DSInteractionGate.allowsTap else { return .handled }
                                DSHaptics.tap(.light)
                                if !textExpanded { onMarkRead() }
                                withAnimation(.smooth(duration: 0.25, extraBounce: 0)) { textExpanded.toggle() }
                                return .handled
                            })
                    }
                }
                if let code = suggestion.code, isCode {
                    Text(SurfacedCodeCard.displayCode(code))
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(DS.Palette.ink)
                } else if isWalletPass {
                    addToWalletChip
                } else if openLinkAction != nil || suggestion.mailReference != nil {
                    HStack(spacing: 8) {
                        if let action = openLinkAction { openLinkChip(action) }
                        if suggestion.mailReference != nil { seeEmailChip }
                    }
                }
            }
            Spacer(minLength: 8)
            if isCode {
                VStack(alignment: .trailing, spacing: 7) {
                    if !showsKindTag {
                        // Tagless surfaces keep the trailing countdown/stamp;
                        // with the tag on it rides the tag line instead
                        //.
                        if let validUntil = suggestion.codeValidUntil ?? suggestion.expiresAt {
                            codeCountdown(until: validUntil)
                        } else {
                            ageStamp
                        }
                    }
                    copyChip
                }
            } else if !showsKindTag {
                // Tagless surfaces keep the trailing stamp, centered on the
                // card's height — no chevron (the whole plate is the tap
                // target; it doesn't need a cue). With the tag on, the age
                // rides the tag line instead.
                ageStamp
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
    }

    /// The "5 hours ago" age stamp, one line, quiet ink.
    private var ageStamp: some View {
        Text(Self.timeLabel(suggestion.createdAt))
            .font(DS.Typography.caption)
            .foregroundStyle(DS.Palette.placeholder)
            .fixedSize()
    }

    /// Live mm:ss (or "Nh Mm") until the code dies, ticking once a second,
    /// "Expired" once it's gone. The tick is scoped to this one label; the
    /// rest of the card never re-renders. Bare digits, no timer glyph, in the
    /// tag line's own quiet ink — the countdown reads as
    /// part of the "ANTHROPIC OTP · 7:58" line, not a second voice.
    private func codeCountdown(until expiresAt: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = expiresAt.timeIntervalSince(context.date)
            Text(remaining > 0 ? Self.countdownLabel(remaining) : String(localized: "Expired"))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(DS.Palette.placeholder)
                // "9:32" reads as a clock time to VoiceOver — say what it means.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    remaining <= 0
                        ? Text("Code expired")
                        : Text("Code expires in \(Self.spokenCountdown(remaining))")
                )
        }
    }

    /// "See email" — the card's one button, bottom-left under the header line:
    /// opens the source email as a SHEET (the card tap itself pushes the detail
    /// page). Quiet chip in the copy chip's grammar, monochrome.
    private var seeEmailChip: some View {
        Button {
            guard !isCompletingSwipe, DSInteractionGate.allowsTap else { return }
            DSHaptics.tap(.light)
            onSeeEmail()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "envelope")
                    .font(.system(size: 11, weight: .semibold))
                Text("See email")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(DS.Palette.inkSoft)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(DS.TaskState.chipFill))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("update-card-see-email")
    }

    /// The stored `open_link` action ("Open App Store") — ink chip weight (it
    /// IS the row's action, like Add to Wallet), label authored by the backend.
    private func openLinkChip(_ action: SuggestionActionItem) -> some View {
        Button {
            guard !isCompletingSwipe, DSInteractionGate.allowsTap else { return }
            DSHaptics.tap(.light)
            onOpenLink(action)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                Text(action.label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(DS.Palette.onInk)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(DS.Palette.ink))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("update-card-open-link")
    }

    /// "Add to Wallet" — the wallet row's one button, in the ink chip weight
    /// (it IS the row's action, unlike the quiet "See email").
    private var addToWalletChip: some View {
        Button {
            guard !isCompletingSwipe, DSInteractionGate.allowsTap else { return }
            DSHaptics.tap(.light)
            onAddToWallet()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "wallet.pass.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Add to Wallet")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(DS.Palette.onInk)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(DS.Palette.ink))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("update-card-add-to-wallet")
    }

    private var copyChip: some View {
        HStack(spacing: 4) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10, weight: .semibold))
            Text(copied ? "Copied" : "Copy")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(copied ? DS.Palette.onInk : DS.Palette.inkSoft)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(copied ? DS.Palette.ink : DS.TaskState.chipFill))
    }

    private func headerTapped() {
        guard !isCompletingSwipe, DSInteractionGate.allowsTap else { return }
        if isCode, let code = suggestion.code {
            UIPasteboard.general.string = code.replacingOccurrences(of: " ", with: "")
            DSHaptics.selection()
            withAnimation(.smooth(duration: 0.2, extraBounce: 0)) { copied = true }
            // Settle back to "Copy" so the chip stays honest about a SECOND
            // copy (a re-requested paste after the clipboard moved on).
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.smooth(duration: 0.3, extraBounce: 0)) { copied = false }
            }
            onCopyCode()
        } else if isWalletPass {
            // The whole plate is the add affordance — same grammar as a code
            // row's tap-to-copy.
            DSHaptics.tap()
            onAddToWallet()
        } else {
            DSHaptics.tap()
            onTap()
        }
    }

    // MARK: - Swipe (SuggestionCard's mechanics, verbatim numbers)

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
        guard !isCompletingSwipe else { return }
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
        guard !isCompletingSwipe, isSwipeActive else { return }
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

    // MARK: - Labels

    /// Compact time-left stamp: "9:32" under an hour, "1h 12m" above it.
    /// Rounds UP so a fresh 10-minute code first reads "10:00", not "9:59".
    static func countdownLabel(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        if total >= 3600 { return "\(total / 3600)h \((total % 3600) / 60)m" }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// The countdown for ears instead of eyes: whole minutes rounded up
    /// ("about 10 minutes", "1 hour 12 minutes", "under a minute").
    static func spokenCountdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        if total < 60 { return String(localized: "under a minute") }
        let minutes = Int((Double(total) / 60).rounded(.up))
        if minutes >= 60 {
            let rest = minutes % 60
            let hours = minutes / 60
            return rest == 0
                ? String(localized: "\(hours) hours")
                : String(localized: "\(hours) hours \(rest) minutes")
        }
        return String(localized: "\(minutes) minutes")
    }

    /// Compact "ago" stamp: "just now" / "12m ago" / "5h ago" / "3d ago" —
    /// single-letter units, sized for the tag line.
    static func timeLabel(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return String(localized: "just now") }
        if seconds < 3600 { return String(localized: "\(Int(seconds / 60))m ago") }
        if seconds < 86400 { return String(localized: "\(Int(seconds / 3600))h ago") }
        return String(localized: "\(Int(seconds / 86400))d ago")
    }

    /// Section order: useful-right-now kinds (codes, links) outrank everything,
    /// then newest first — a 10-minute-old code still beats a fresher recap.
    /// One live code per service: the backend supersedes stale codes at create
    /// time, but two rapid re-requests can race a sync — when both rows are
    /// live, show only the NEWEST (the older code died the moment the new one
    /// was issued).
    static func sectionSort(_ updates: [Suggestion]) -> [Suggestion] {
        var newestCodeByTitle: [String: Date] = [:]
        for update in updates where update.kind == "signin-code" {
            newestCodeByTitle[update.message] = max(newestCodeByTitle[update.message] ?? .distantPast, update.createdAt)
        }
        return updates.filter { update in
            update.kind != "signin-code" || update.createdAt == newestCodeByTitle[update.message]
        }
        .sorted {
            let a = urgencyBand($0.kind)
            let b = urgencyBand($1.kind)
            if a != b { return a < b }
            return $0.createdAt > $1.createdAt
        }
    }

    private static func urgencyBand(_ kind: String) -> Int {
        switch kind {
        case "signin-code", "action-link": 0
        case "mail-watch", "wallet-pass": 1
        default: 2
        }
    }
}

