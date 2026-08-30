import PersonaDesign
import SwiftUI

// The two standing-object primitives every notification-family chat card is
// built from. The reminder card and the meeting card each hand-rolled these
// twice, in accent blue — a drift the standardization pass
// "standardize the components wherever possible so moving forward we can reuse
// them") collapses into one home. NEW cards in this family (a fired alarm, a
// timer, a "your ride is here" ping) should reach for these instead of
// re-deriving the metrics — that is the whole point of them living here.
//
// Visual doctrine (design brief): these render MONOCHROME. Content
// accent blue is retired, so the interactive text/glyphs are ink, not
// `DS.Palette.accent`. Semantic status tint (success green, failure red) is the
// caller's to pass on the settled row; the action row is always ink.

/// Chrome shared by the notification-family cards, centralized so every card's
/// hairline matches to the pixel.
enum CardChrome {
    /// A hairline that reads on the incoming bubble's WHITE plate — the app-wide
    /// `DS.Palette.hairlineSoft` is near-white and vanishes there, so these cards
    /// (which sit as their bubble's content, no plate of their own) need a
    /// slightly darker rule. Both the reminder and meeting cards had defined this
    /// exact value privately; it lives here now.
    static let bubbleHairline = DS.Palette.ink.opacity(0.09)
}

/// The label content for ONE slot of a `CardActionRow`: a centered icon + text,
/// ink-weighted. Handed to the caller so the slot's TRIGGER stays theirs — wrap
/// it in a `Button` for a direct action (meeting's Leave, reminder's Done) or a
/// `Menu` for a picker (reminder's Snooze). Keeping the trigger at the call site
/// is what lets one row mix a Button and a Menu without any `AnyView` erasure.
///
/// `emphasized` promotes the text to semibold — the affirmative action in a
/// two-action row (Done) leads over the deferring one (Snooze).
struct CardActionLabel: View {
    let icon: String
    let text: LocalizedStringKey
    var emphasized = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 15, weight: emphasized ? .semibold : .medium))
                .tracking(-0.2)
        }
        // INK, never accent — this is the line that kills the content blue in
        // both cards. The row is monochrome; status color lives on the settled
        // row, not here.
        .foregroundStyle(DS.Palette.ink)
        // Fill the slot so the whole half (or full width) is the tap target,
        // and stamp a hit shape over the empty space around the label.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

/// The notification-style action row: a hairline-topped 40pt strip of one or two
/// equal-width action slots, a vertical hairline splitting a pair. The row owns
/// the LAYOUT (top rule, equal halves, divider); the caller owns each slot's
/// content — a `Button`- or `Menu`-wrapped `CardActionLabel`. This is the "what
/// can I do about this" surface at the foot of a live card.
///
/// Single action (meeting: Cancel / Leave):
/// CardActionRow { Button { leave() } label: { CardActionLabel(icon:, text:) } }
/// Two actions (reminder: Snooze | Done):
/// CardActionRow {
/// Menu { … } label: { CardActionLabel(icon:, text:) }
/// } trailing: {
/// Button { … } label: { CardActionLabel(icon:, text:, emphasized: true) }
/// }
struct CardActionRow<Primary: View, Secondary: View>: View {
    private let primary: Primary
    private let secondary: Secondary?

    /// One full-width action.
    init(@ViewBuilder action: () -> Primary) where Secondary == EmptyView {
        primary = action()
        secondary = nil
    }

    /// Two equal-width actions split by a vertical hairline.
    init(
        @ViewBuilder leading: () -> Primary,
        @ViewBuilder trailing: () -> Secondary
    ) {
        primary = leading()
        secondary = trailing()
    }

    var body: some View {
        VStack(spacing: 0) {
            CardChrome.bubbleHairline.frame(height: 1)
            HStack(spacing: 0) {
                primary
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let secondary {
                    CardChrome.bubbleHairline.frame(width: 1)
                    secondary
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: 40)
        }
    }
}

/// A card's terminal-state row: a tinted icon + a 2-line title over a subtitle,
/// flat on the bubble gray (no nested plate). The compact shape a live card
/// collapses to once there's nothing more to do — "Meeting recorded", "Snoozed
/// until 4:00 PM", "Done". Also the shape a card is BORN in when it starts
/// settled-but-editable (a just-scheduled reminder), which is why it's happy as
/// a `Menu` label: `contentShape` makes the whole row the menu's hit target, and
/// the optional `trailing` slot carries the affordance that says so (a chevron).
///
/// `tint` defaults to the ink family; pass `DS.Palette.success` / a red for a
/// positive / failed terminal state — that semantic status color is the ONE
/// place color survives on these cards.
struct CardSettledRow<Trailing: View>: View {
    let icon: String
    var tint: Color = DS.Palette.inkMuted
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                // Two-line cap on BOTH lines (the union of what the two cards
                // capped): the title is the ask on a snoozed reminder — the only
                // surface still carrying it — and the subtitle is a meeting's
                // plain-language failure reason, either of which can wrap once.
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .tracking(-0.2)
                    .foregroundStyle(DS.Palette.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(DS.Palette.inkMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            trailing()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // Always hit-testable: the meeting rows are inert, but the reminder rows
        // wrap this in a Menu and need the full frame tappable.
        .contentShape(Rectangle())
        .chatCardPanel()
    }
}

extension CardSettledRow where Trailing == EmptyView {
    /// The no-affordance settled row (a meeting's completed / left / failed
    /// state — over, nothing to tap).
    init(icon: String, tint: Color = DS.Palette.inkMuted, title: String, subtitle: String) {
        self.init(icon: icon, tint: tint, title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Shimmering status text

/// A quiet in-card "working on it" line: resting grey glyphs lit by a passing
/// ink band — the ChatLoadingIndicator's phrase treatment, extracted so cards
/// never fall back to a bare spinner for their live states (the monochrome
/// doctrine retires content spinners; a shimmer on the words IS the loading
/// signal). Reduced motion renders static muted text.
struct ShimmerText: View {
    let text: String
    var size: CGFloat = 13

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Resting glyph color — dim enough that the sweeping ink band reads.
    private static let rest = DS.Palette.placeholder.opacity(0.55)

    var body: some View {
        // Not LPM-gated: shimmer is personality, and a
        // leaf-text redraw is pennies next to the real LPM standdowns.
        if reduceMotion {
            base.foregroundStyle(DS.Palette.inkMuted)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                base
                    .foregroundStyle(Self.rest)
                    .overlay {
                        GeometryReader { geo in
                            let band = max(geo.size.width * 0.55, 28)
                            LinearGradient(
                                colors: [.clear, DS.Palette.ink, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: band)
                            .offset(x: geo.size.width * (-0.5 + 1.8 * CGFloat(t)) - band / 2)
                        }
                        .mask { base }
                        .allowsHitTesting(false)
                    }
            }
        }
    }

    private var base: some View {
        Text(text)
            .font(.system(size: size, weight: .medium))
            .tracking(-0.14)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Chat-card v2 primitives (design audit)

// The shared vocabulary the v2 card restyle composes from. Phase 0 lands the
// primitives only; existing cards migrate onto them in later phases.

/// The v2 base card wrapper: content on the shared chatCardPanel plate at the




/// One trailing action in a CardHeaderRow: a 28pt line-icon button, or, when
/// `prominent`, THE solid charcoal send-circle (reference-1 idiom). A row
/// carries at most one prominent action, always last.
struct CardHeaderAction: Identifiable {
    let symbol: String
    var prominent = false
    let action: () -> Void
    var id: String { symbol }
}

/// One entry of a CardHeaderRow's overflow menu (the 28pt ellipsis button):
/// a titled, icon-led action ("Open in Mail app").
struct CardHeaderMenuItem: Identifiable {
    let title: String
    let symbol: String
    let action: () -> Void
    var id: String { title }
}

/// The v2 card header: an uppercase eyebrow ("EMAIL" / "CALL" / "APPROVAL"),
/// an optional leading icon tile, and the trailing action cluster. The cluster
/// orders itself: plain 28pt line icons first, the ellipsis overflow menu (when
/// `menuItems` exist), and any `prominent` action last, so the solid charcoal
/// circle always closes the row.
struct CardHeaderRow: View {
    let eyebrow: LocalizedStringKey
    /// SF symbol for the optional 34pt rounded-square leading tile.
    var iconTile: String? = nil
    /// Bundled brand slug ("gmail") for the leading tile. In the real app this
    /// draws the actual service mark; that badge carries a table of bundled
    /// brand assets and a remote logo fallback, neither of which this trial
    /// ships, so the tile always falls back to the SF glyph below.
    var brandTile: String? = nil
    var actions: [CardHeaderAction] = []
    var menuItems: [CardHeaderMenuItem] = []

    var body: some View {
        HStack(spacing: 10) {
            if let iconTile {
                Image(systemName: iconTile)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Palette.ink)
                    .frame(width: DS.Metrics.iconTile, height: DS.Metrics.iconTile)
                    .background(
                        DS.Palette.surfaceMuted,
                        in: RoundedRectangle(cornerRadius: DS.Radius.iconTile, style: .continuous)
                    )
            }
            Text(eyebrow)
                .font(DS.Typography.cardLabel)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(DS.Palette.subtle)
                .lineLimit(1)
            Spacer(minLength: 8)
            ForEach(actions.filter { !$0.prominent }) { entry in
                actionButton(entry)
            }
            if !menuItems.isEmpty {
                Menu {
                    ForEach(menuItems) { item in
                        Button {
                            item.action()
                        } label: {
                            Label(item.title, systemImage: item.symbol)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(DS.Palette.inkMuted)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            ForEach(actions.filter(\.prominent)) { entry in
                actionButton(entry)
            }
        }
    }

    private func actionButton(_ entry: CardHeaderAction) -> some View {
        Button {
            guard DSInteractionGate.allowsTap else { return }
            DSHaptics.tap()
            entry.action()
        } label: {
            if entry.prominent {
                Image(systemName: entry.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .primaryActionBackground(in: Circle())
                    .contentShape(Circle())
            } else {
                Image(systemName: entry.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DS.Palette.inkMuted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }
}

/// One row of a FieldStack: an optional subtle label over an ink value.
struct CardField: Identifiable {
    var label: String? = nil
    let value: String
    /// Render the value in the placeholder color (an empty slot's hint).
    var isPlaceholder = false
    /// Body-preview row: multi-line up to `previewLineLimit`, tail faded only
    /// when the text actually overran the cap.
    var isBodyPreview = false
    var previewLineLimit = 4
    /// Per-row cap on the VALUE's lines, overriding the stack's default (a
    /// subject-class row earns 3 where its siblings wrap at 2). Nil defers.
    var valueLineLimit: Int? = nil
    var id: String { (label ?? "·") + value }
}

/// Vertical field rows split by full-width hairlineSoft rules; the v2 grammar
/// for an email's To/Subject/body, a call's number/mission, and kin.
struct FieldStack: View {
    let fields: [CardField]
    /// Line cap for VALUE rows (body previews keep their own clamp+fade). The
    /// default keeps the original single-line truncation; adopters whose
    /// values carry real payload (addresses, subjects) pass 2 so "Fwd: Lease
    /// renewal, updated ter..." wraps instead of clipping. Label geometry is
    /// untouched: labels stay single-line above the value either way.
    var valueLineLimit: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                if index > 0 {
                    Rectangle().fill(DS.Palette.hairlineSoft).frame(height: 1)
                }
                row(field)
            }
        }
    }

    private func row(_ field: CardField) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let label = field.label {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.Palette.subtle)
            }
            if field.isBodyPreview {
                FadingPreviewText(text: field.value, lineLimit: field.previewLineLimit)
            } else {
                // fixedSize (vertical) lets a wrap-capable row actually take
                // its second/third line inside the card's VStack; word
                // wrapping is Text's default, and the tail still truncates
                // past the cap. A 1-line row lays out exactly as before.
                Text(field.value)
                    .font(.system(size: 15))
                    .foregroundStyle(field.isPlaceholder ? DS.Palette.placeholder : DS.Palette.ink)
                    .lineLimit(field.valueLineLimit ?? valueLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A body preview capped at `lineLimit` whose tail fades ONLY when the text
/// actually got cut (a hidden unclamped twin is measured against the clamped
/// render; a short body stays at full strength).
private struct FadingPreviewText: View {
    let text: String
    let lineLimit: Int

    @State private var clampedHeight = CGFloat.zero
    @State private var fullHeight = CGFloat.zero

    private var isTruncated: Bool { fullHeight > clampedHeight + 1 }

    private var base: some View {
        Text(text)
            .font(.system(size: 15))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        base
            .lineLimit(lineLimit)
            .foregroundStyle(DS.Palette.ink)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { clampedHeight = $0 }
            .background(alignment: .top) {
                base.hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
            }
            .mask(alignment: .top) {
                if isTruncated {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.62),
                            .init(color: .black.opacity(0.12), location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                } else {
                    Rectangle()
                }
            }
    }
}

/// The v2 action pills: an outlined secondary + a charcoal-gradient primary at
/// equal widths, or a single full-width primary. `destructive` colors the
/// outlined pill's label danger (the primary keeps the charcoal; color
/// encodes state, never emphasis).
struct PillPair: View {
    /// nil → the single-primary variant.
    var secondaryTitle: LocalizedStringKey? = nil
    var onSecondary: (() -> Void)? = nil
    var destructive = false
    let primaryTitle: LocalizedStringKey
    let onPrimary: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let secondaryTitle {
                Button {
                    guard DSInteractionGate.allowsTap else { return }
                    DSHaptics.tap()
                    onSecondary?()
                } label: {
                    Text(secondaryTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(destructive ? DS.Palette.danger : DS.Palette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: DS.Metrics.pillHeightMd)
                        .background(DS.Palette.card, in: Capsule(style: .continuous))
                        .overlay { Capsule(style: .continuous).stroke(DS.Palette.hairline, lineWidth: 1) }
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Button {
                guard DSInteractionGate.allowsTap else { return }
                DSHaptics.tap()
                onPrimary()
            } label: {
                Text(primaryTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: DS.Metrics.pillHeightMd)
                    .primaryActionBackground(in: Capsule(style: .continuous))
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

/// A card's live/settled progress states; every v2 card narrates through this
/// one row instead of a private spinner arrangement.
enum CardStatusState: Equatable {
    case pending
    case running
    case success
    case failure
    case cancelled
}

/// The 32pt status strip: leading glyph / pulsing live dot / spinner, a 13pt
/// muted line, and an optional trailing timestamp.
struct StatusRow: View {
    let state: CardStatusState
    let text: String
    var timestamp: String? = nil

    var body: some View {
        HStack(spacing: 7) {
            leading
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Palette.inkMuted)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let timestamp {
                Text(timestamp)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Palette.placeholder)
            }
        }
        .frame(height: 32)
    }

    @ViewBuilder private var leading: some View {
        switch state {
        case .pending:
            ProgressView().controlSize(.small).tint(DS.Palette.placeholder)
        case .running:
            PulseDot(color: DS.Palette.ink)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Palette.success)
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Palette.danger)
        case .cancelled:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Palette.placeholder)
        }
    }
}

/// THE collapsed-state chip: green check / amber triangle / grey xmark + a
/// short verb. Built to absorb the three duplicate implementations
/// (ChatCardView.resolvedChip, PaymentConfirmSheets.resolvedChip,
/// UberRideConfirmCardView.resolvedChip); they migrate in a later phase.
struct SettledChip: View {
    enum Outcome {
        case success
        case attention
        case cancelled
    }

    let outcome: Outcome
    let text: String

    var body: some View {
        // Flat on purpose: every place this renders is already a plated
        // surface (the transcript bubble, a card panel), and a filled capsule
        // there read as a pill inside a pill. The
        // surrounding plate IS the pill; this is just its settled line.
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Palette.inkMuted)
        }
        .padding(.horizontal, 6)
        .frame(height: 26)
    }

    private var symbol: String {
        switch outcome {
        case .success: "checkmark.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle.fill"
        }
    }

    private var tint: Color {
        switch outcome {
        case .success: DS.Palette.success
        case .attention: DS.Palette.attention
        case .cancelled: DS.Palette.placeholder
        }
    }
}

/// The mini two-sided transcript stack (13pt text, compact bubbles) extracted
/// from VoiceCallCardView's inline preview; any card previewing a short
/// exchange (a call, a relayed thread) renders through this.
struct TranscriptMiniBubbles: View {
    struct Line {
        let text: String
        /// Right-aligned dark bubble (our side); false = left grey bubble.
        let trailing: Bool
    }

    let lines: [Line]

    var body: some View {
        VStack(spacing: 7) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                bubble(line)
            }
        }
    }

    private func bubble(_ line: Line) -> some View {
        HStack(spacing: 0) {
            if line.trailing { Spacer(minLength: 36) }
            Text(line.text)
                .font(.system(size: 13))
                .foregroundStyle(line.trailing ? .white : DS.Palette.ink)
                .lineLimit(2)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    line.trailing ? DS.Palette.userBubble.opacity(0.92) : DS.Palette.surfaceMuted,
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
            if !line.trailing { Spacer(minLength: 36) }
        }
        .frame(maxWidth: .infinity, alignment: line.trailing ? .trailing : .leading)
    }
}

// MARK: - Undoable send

/// The pending-send ledger behind UndoableSendButton: schedules the real send
/// after a grace window and OUTLIVES the card view, so a transcript cell that
/// gets recycled mid-countdown can neither lose the send nor its Undo. One
/// shared instance; entries are keyed by the card's own stable id (draftId,
/// chat jid…). The action closure captures long-lived stores only.
@MainActor @Observable
final class UndoSendCenter {
    static let shared = UndoSendCenter()

    struct Pending {
        let fireAt: Date
        let task: Task<Void, Never>
    }

    private(set) var pending: [String: Pending] = [:]
    /// Ticks once a second while anything is pending so countdown labels
    /// re-render; idle otherwise.
    private(set) var now = Date()
    private var ticker: Task<Void, Never>?

    func schedule(id: String, delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        cancel(id: id)
        // Refresh the tick clock NOW: `now` only advances once a second, and a
        // stale value here inflates the first countdown label by up to 2s.
        now = Date()
        let fireAt = now.addingTimeInterval(delay)
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.pending[id] = nil
            self?.stopTickerIfIdle()
            action()
        }
        pending[id] = Pending(fireAt: fireAt, task: task)
        startTicker()
    }

    func cancel(id: String) {
        pending[id]?.task.cancel()
        pending[id] = nil
        stopTickerIfIdle()
    }

    func secondsRemaining(id: String) -> Int? {
        guard let entry = pending[id] else { return nil }
        return max(0, Int(entry.fireAt.timeIntervalSince(now).rounded(.up)))
    }

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.now = Date()
                if self.pending.isEmpty { break }
            }
            self?.ticker = nil
        }
    }

    private func stopTickerIfIdle() {
        if pending.isEmpty { ticker?.cancel(); ticker = nil }
    }
}

/// The standard card send control with a working undo window: tap Send and the
/// button flips to a quiet "Sending in Ns · Undo" row for `graceSeconds`
/// before the real send fires — tap again to cancel. Retries (`isRetry`) skip
/// the window: the user already waited once and explicitly wants it NOW.
/// Geometry is the ONE primary-action treatment (46pt, 14-radius,
/// primaryActionBackground) so every card's send looks and behaves the same.
struct UndoableSendButton: View {
    /// Stable identity for the pending send (draftId, chat jid…): countdown
    /// state survives cell recycling under this key.
    let id: String
    let label: LocalizedStringKey
    let icon: String
    var isRetry = false
    var isBusy = false
    var graceSeconds: TimeInterval = 5
    let onFire: @MainActor () -> Void

    @State private var center = UndoSendCenter.shared

    var body: some View {
        if center.secondsRemaining(id: id) != nil {
            UndoCountdownRow(id: id)
        } else {
            Button {
                // A page swipe releasing over the button is a touch-up
                // "inside" — without the gate it starts a REAL send (WhatsApp
                // fires straight from onFire after the grace window).
                guard DSInteractionGate.allowsTap else { return }
                DSHaptics.tap()
                if isRetry {
                    onFire()
                } else {
                    center.schedule(id: id, delay: graceSeconds, action: onFire)
                }
            } label: {
                HStack(spacing: 7) {
                    if isBusy {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                        Text(label).font(.system(size: 14, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .primaryActionBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
    }
}

/// The armed undo window as its own row: "Sending in Ns · Undo", tap to
/// cancel. UndoableSendButton renders this while its send is pending; cards
/// whose send lives in the HEADER (the v2 email card's charcoal circle) drop
/// this row under their fields instead, so the undo semantics are identical
/// wherever the trigger sits. Renders nothing when no send is armed under
/// `id`, so it can sit unconditionally in a card body.
struct UndoCountdownRow: View {
    /// The same stable identity the scheduling call used ("draft-<id>").
    let id: String

    @State private var center = UndoSendCenter.shared

    var body: some View {
        if let remaining = center.secondsRemaining(id: id) {
            Button {
                guard DSInteractionGate.allowsTap else { return }
                DSHaptics.tap()
                center.cancel(id: id)
            } label: {
                HStack(spacing: 7) {
                    Text("Sending in \(remaining)s")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Palette.inkMuted)
                        .monospacedDigit()
                    Spacer(minLength: 8)
                    Text("Undo")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Palette.ink)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(DS.Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Undo send, firing in \(remaining) seconds"))
        }
    }
}
