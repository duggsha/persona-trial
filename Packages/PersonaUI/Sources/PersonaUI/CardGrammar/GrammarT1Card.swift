import PersonaDesign
import SwiftUI

// T1 · the led card: mark · title · subtitle · body · verdict · actions.
// Slots are omitted, never reordered and never renamed (R5) — which is the
// whole reason a column of cards can be checked at a glance.

/// The trailing meta slot: an age stamp with an optional unread dot, or the
/// invite's up-chevron.
enum GrammarMeta: Hashable {
    case age(String, unread: Bool = false)
    case chevronUp
}

/// `.verdict`: the dotted line — **an AI observation that bears on the
/// decision**. That sentence is the whole test for
/// whether a line earns the dot, and it has two halves:
///
/// · **AI observation.** The source is NOT the thing that arrived. Every
/// other slot is a field of the email, the invite, the bill; this one is
/// read out of the user's OWN connected data and stated as a finding
/// already made — the calendar (`Nothing booked Friday Sep 4`,
/// `Thursday 10 AM is your only free 45 minutes`), their mail history
/// (`a news trial you haven’t opened since June`), their past statements
/// (`Nothing unusual — same as last month, ±$40`).
/// · **Bears on the decision.** It answers the one question the primary
/// button raises: can I press this? A finding that changes no button is a
/// `body`, however true it is.
///
/// This is where the connectors pay off, and it is why the dot is worth a
/// slot of its own: the card arrives from ONE source and the dot is the
/// place a second one gets to speak. An invite is a calendar event and the
/// dot is your calendar answering it; a bill is mail and the dot is a year
/// of statements answering it. Cross-referencing is the product, and the
/// green dot is the mark that says a cross-reference happened.
///
/// Green = the finding clears the way. The clash is amber, not red: the
/// thing is still doable, it just costs something.
struct GrammarVerdict: Hashable {
    var text: String
    var clash = false
}

struct GrammarT1Model: Hashable {
    var mark: GrammarMark
    var title: String
    var subtitle: String
    var meta: GrammarMeta?
    var body: String?
    var verdict: GrammarVerdict?
    var pills: [GrammarPill] = []
}

struct GrammarT1Card: View {
    let model: GrammarT1Model
    /// Once answered, the pills give way to this chip and the card is on its
    /// way out. Every kind ends the same way.
    var settled: String?
    /// Tap on the pill at this index. Nil in the gallery: a drawing has no
    /// behaviour. The feed passes one, which is what makes the collapsed card
    /// answerable without opening it (R3).
    var onPillTap: ((Int) -> Void)?

    var body: some View {
        content.grammarCardPlate()
    }

    /// The drawing WITHOUT its plate. The gallery wants the plate; the live
    /// feed already owns one (it tints during a reject swipe and animates its
    /// own height), so it renders this and keeps that plate. Splitting here
    /// rather than re-laying-out the slots at the call site is what stops the
    /// two surfaces drifting apart (R0).
    @ViewBuilder
    var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            GrammarT1Header(mark: model.mark, title: model.title, subtitle: model.subtitle, meta: model.meta)
            if let bodyText = model.body {
                Text(bodyText)
                    .font(.system(size: 14))
                    .foregroundStyle(DS.Palette.inkMuted)
                    .grammarLeading(size: 14, weight: .regular, lineHeight: 1.45)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 9)
            }
            if let verdict = model.verdict {
                GrammarVerdictLine(verdict: verdict)
                    .padding(.top, 9)
            }
            // The answer lands at the speed of the tap — pills out, chip in —
            // because the swap IS the button's feedback (flow-cleared.html).
            if let settled {
                GrammarSettledChip(text: settled)
                    .padding(.top, 12)
                    .transition(.opacity)
            } else if !model.pills.isEmpty {
                GrammarPillRow(pills: model.pills, onTap: onPillTap)
                    .padding(.top, 13)
                    .transition(.opacity)
            }
        }
    }
}

/// `.t1-head`: [34 mark] title + subtitle [meta], the mark's top edge on the
/// title's cap line — one geometry, no exceptions (R2).
struct GrammarT1Header: View {
    var mark: GrammarMark
    var title: String
    var subtitle: String
    var meta: GrammarMeta?

    var body: some View {
        HStack(alignment: .top, spacing: GrammarChrome.headerGap) {
            GrammarMarkView(mark: mark)
                .padding(.top, GrammarCapline.titleTrim)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(-0.25)
                    .foregroundStyle(DS.Palette.ink)
                    .grammarLeading(size: 16, weight: .semibold, lineHeight: 1.28)
                    .lineLimit(2)
                    // Without this the title settles at ONE line and
                    // ellipsizes whenever the header shares the card with a
                    // body — see GrammarCapline's note.
                    .fixedSize(horizontal: false, vertical: true)
                // R5: a card OMITS a slot, it never draws it blank. Every
                // drawing in the deck happens to carry a subtitle, so this
                // never fired there — but a live card whose sender resolves to
                // nothing has none, and an unguarded Text still takes its
                // line, which reads as a mis-set title rather than a card
                // without a subtitle.
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13.5))
                        .foregroundStyle(DS.Palette.placeholder)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            switch meta {
            case let .age(age, unread):
                HStack(spacing: 5) {
                    if unread {
                        Circle().fill(DS.Palette.accent).frame(width: 7, height: 7)
                    }
                    Text(age)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Palette.placeholder)
                .padding(.top, GrammarCapline.metaInset)
            case .chevronUp:
                GrammarGlyphView(glyph: GlyphChevronUp.self, size: 11)
                    .foregroundStyle(DS.Palette.placeholder)
                    .padding(.top, GrammarCapline.titleTrim + 2)
            case nil:
                EmptyView()
            }
        }
    }
}

struct GrammarVerdictLine: View {
    let verdict: GrammarVerdict

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(verdict.clash ? GrammarPalette.verdictClash : DS.TaskState.green)
                .frame(width: 7, height: 7)
                // Baseline-aligned boxes ignore a dot's optical centre; nudge
                // it onto the x-height so it reads as punctuation.
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
            Text(verdict.text)
                .font(.system(size: 14))
                .foregroundStyle(DS.Palette.inkMuted)
                .grammarLeading(size: 14, weight: .regular, lineHeight: 1.45)
                // A verdict that wraps is a body (grammar.html) — but if a
                // string ever runs long it should wrap, not ellipsize.
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// `.settled`: the chip that replaces the pills after the undo window, before
/// the card leaves. Every kind ends this same way.
struct GrammarSettledChip: View {
    var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Palette.success)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Palette.inkMuted)
        }
        .padding(.horizontal, 6)
        .frame(height: 26)
    }
}
