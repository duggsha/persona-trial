import PersonaCore
import PersonaDesign
import SwiftUI
import UIKit

/// Home's "surfaced item" slot: the one useful-right-now artifact pinned
/// directly under the Up Next hero (the old sign-in button position, between
/// Up Next and Quick Actions). Today it surfaces the newest ACTIVE sign-in
/// code — the code big, an explicit Copy affordance — as a SECOND place beyond
/// its Updates row: a fresh code is usually THE reason the app was just
/// opened. The container is deliberately generic (boarding passes are
/// earmarked for this same slot next); it owns only "what's surfaced right
/// now", never card internals.
///
/// Lifecycle: the card leaves the slot the moment its code dies (the mail's
/// stated deadline, else the server row's TTL — checked live, not on the next
/// feed poll) or once the user copies it anywhere (slot, Updates row, All
/// sheet — session-local `consumedCodeIds`). Its Updates row stays either way.
struct SurfacedItemSlot: View {
    /// The Updates-section cards (unsorted — selection happens here).
    let updates: [Suggestion]
    /// Codes already copied this session (HomeStore.consumedCodeIds).
    let consumedCodeIds: Set<UUID>
    /// The slot's code was copied: mark it seen + consumed upstream.
    let onCopyCode: (Suggestion) -> Void

    var body: some View {
        // The 1s heartbeat is scoped to this subtree: it drives the countdown
        // AND re-evaluates expiry so a dead code leaves on time — the rest of
        // Home never re-renders (same idiom as the Updates row's countdown).
        // No live code at all → no TimelineView, no ticking.
        if hasCandidate {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let surfaced = Suggestion.surfacedCode(
                    in: updates,
                    consumed: consumedCodeIds,
                    now: context.date
                )
                ZStack(alignment: .top) {
                    // A live order outranks a code in this slot: a code can be
                    // read from its Updates row seconds later, an order that
                    // just turned "ready for pickup" is the reason the app is
                    // open at all. Codes keep the slot whenever no order runs.
                    if let order = liveOrder {
                        SurfacedOrderCard(suggestion: order, now: context.date)
                            .padding(.top, 26)
                            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                    } else if let surfaced {
                        SurfacedCodeCard(
                            suggestion: surfaced,
                            now: context.date,
                            onCopy: { onCopyCode(surfaced) }
                        )
                        .padding(.top, 26)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                    }
                }
                .animation(.smooth(duration: 0.32, extraBounce: 0), value: surfaced?.id)
            }
        }
    }

    /// Deliberately ignores `consumedCodeIds`: consuming the last code must
    /// leave the TimelineView MOUNTED so the inner ZStack can animate the
    /// card's exit — unmounting at this outer `if` (no animation attached)
    /// would blink it out. The idle tick lasts only until the row leaves the
    /// feed (next poll or expiry).
    private var hasCandidate: Bool {
        liveOrder != nil
            || updates.contains {
                $0.kind == "signin-code" && $0.isOpen && !($0.code ?? "").isEmpty
            }
    }

    /// The newest running order, if any. Requires the structural payload: a
    /// card without it would render an empty bar, and an empty bar reads as
    /// "nothing is happening" — the opposite of the truth.
    private var liveOrder: Suggestion? {
        updates
            .filter { $0.kind == "order-progress" && $0.isOpen && $0.orderProgress != nil }
            .max(by: { $0.createdAt < $1.createdAt })
    }
}

/// The slot's sign-in-code card: same identity language as an Updates row
/// (avatar, service title, white solid plate) but the CODE is the headline —
/// big and monospaced — with an explicit ink Copy pill. The whole plate is one
/// tap target; copying flips the pill to "Copied", then the card retires from
/// the slot (the parent consumes it after the confirmation beat lands).
struct SurfacedCodeCard: View {
    let suggestion: Suggestion
    /// The slot heartbeat's current instant — drives the countdown without a
    /// second TimelineView.
    let now: Date
    let onCopy: () -> Void

    @State private var copied = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SuggestionEntryAvatar(suggestion: suggestion, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.message)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.1)
                    .foregroundStyle(DS.Palette.subtle)
                    .lineLimit(1)
                Text(Self.displayCode(suggestion.code ?? ""))
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(DS.Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let validUntil = suggestion.codeValidUntil {
                    // Only a STATED window counts down (never the default TTL —
                    // no invented precision; an unstated code just leaves the
                    // slot quietly when the server row dies).
                    countdown(until: validUntil)
                }
            }
            Spacer(minLength: 10)
            copyPill
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .solidCardPlate(radius: DS.Radius.card)
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card))
        .onTapGesture { copyTapped() }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("surfaced-code-card")
    }

    private var copyPill: some View {
        // BOTH states stay in the layout (hidden one at opacity 0) so the pill
        // keeps the width of the wider label — flipping Copy → Copied must not
        // resize the pill and shove the code text around.
        ZStack {
            copyPillLabel(icon: "checkmark", text: "Copied").opacity(copied ? 1 : 0)
            copyPillLabel(icon: "doc.on.doc", text: "Copy").opacity(copied ? 0 : 1)
        }
        .foregroundStyle(DS.Palette.onInk)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule().fill(DS.Palette.ink))
    }

    private func copyPillLabel(icon: String, text: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 14, weight: .semibold))
        }
    }

    private func countdown(until validUntil: Date) -> some View {
        let remaining = validUntil.timeIntervalSince(now)
        return HStack(spacing: 3) {
            Image(systemName: "timer")
                .font(.system(size: 9, weight: .semibold))
            Text(UpdateCard.countdownLabel(remaining))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        }
        // Monochrome family, leaning darker inside the last minute — the same
        // urgency language as the Updates row's countdown.
        .foregroundStyle(remaining <= 60 ? DS.Palette.ink : DS.Palette.subtle)
    }

    private func copyTapped() {
        guard DSInteractionGate.allowsTap, !copied else { return }
        // Grouping spaces are display-only; OTP fields routinely reject them
        // (same strip as every other copy path, so pastes are identical).
        UIPasteboard.general.string = (suggestion.code ?? "").replacingOccurrences(of: " ", with: "")
        DSHaptics.selection()
        withAnimation(.smooth(duration: 0.2, extraBounce: 0)) { copied = true }
        // Let "Copied" land before the card retires from the slot. The consume
        // mutation is wrapped in withAnimation so the card's exit transition
        // actually plays and the feed below slides up — an unanimated mutation
        // blinked the card out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.smooth(duration: 0.32, extraBounce: 0)) { onCopy() }
        }
    }

    /// Display-only grouping: the detector strips separators, so live codes
    /// arrive as one dense run ("583201"). Even-length runs of 6/8 digits get
    /// a midpoint break for the eye — a code that already carries its own
    /// spacing keeps it verbatim. Copy always pastes the stripped string.
    static func displayCode(_ code: String) -> String {
        guard !code.contains(" ") else { return code }
        guard code.allSatisfy(\.isNumber), code.count == 6 || code.count == 8 else { return code }
        let mid = code.index(code.startIndex, offsetBy: code.count / 2)
        return "\(code[..<mid]) \(code[mid...])"
    }

    private var accessibilityText: Text {
        let digits = (suggestion.code ?? "")
            .replacingOccurrences(of: " ", with: "")
            .map(String.init)
            .joined(separator: " ")
        if let validUntil = suggestion.codeValidUntil, validUntil > now {
            let spoken = UpdateCard.spokenCountdown(validUntil.timeIntervalSince(now))
            return Text("\(suggestion.message): \(digits). Expires in \(spoken). Copies the code.")
        }
        return Text("\(suggestion.message): \(digits). Copies the code.")
    }
}
