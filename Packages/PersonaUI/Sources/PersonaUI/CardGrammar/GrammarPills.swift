import PersonaDesign
import SwiftUI

// The action row. Fill is a three-value enum (R13): tinted is the default,
// ink only for equal-weight opposites where the words alone must carry which
// one commits, brand only when the button hands off to that branded surface.
// A pill may carry ONE glyph, and it says what pressing it does to the world.

/// `.pill-ico`: the leading/trailing glyph enum. agent · mail · sheet LEAD
/// (they qualify the verb); external TRAILS (it marks the destination, the
/// same convention as the arrow after a link's text). No glyph is the
/// default — a row where every button is decorated says nothing (R6).
enum GrammarPillIcon: Hashable {
    /// Persona goes and does it out of band: Call Debi, Book it, Check this bill.
    case agent
    /// Opens a mail sheet: Read the emails, Read & reply, Read the draft.
    case mail
    /// Opens a sheet that is not mail: Others (the day grid).
    case sheet
    /// Puts you in another app: Reconnect Gmail, Join Meet.
    case external

    var leads: Bool { self != .external }

    /// The agent burst is 19 filled dots — much less ink at 14pt than the
    /// stroked glyphs beside it, so it gets its weight back via opacity
    /// rather than being drawn at a different size and breaking the row.
    var opacity: CGFloat {
        self == .agent ? 0.88 : 0.72
    }

    @ViewBuilder
    var view: some View {
        switch self {
        case .agent: GrammarGlyphView(glyph: GlyphAgentBurst.self, size: 14)
        case .mail: GrammarGlyphView(glyph: GlyphPillMail.self, size: 14)
        case .sheet: GrammarGlyphView(glyph: GlyphPillSheet.self, size: 14)
        case .external: GrammarGlyphView(glyph: GlyphExternal.self, size: 14)
        }
    }
}

/// R13's fill enum, plus the secondary that shares the tinted fill.
enum GrammarPillFill: Hashable {
    /// `.pill--primary`: chip fill, ink, 600 — rank carried by weight alone.
    case primary
    /// `.pill--secondary`: same fill, muted ink, 500.
    case secondary
    /// `.pill--commit`: flat ink. Only for two equal-weight opposites
    /// (Accept / Can't make it), never importance in the abstract.
    case commit
    /// `.pill--meet`: Meet's own blue — the handoff wears the brand.
    case meet
    /// `.pill--wallet`: Wallet's black. Not external — you stay here.
    case wallet
}

struct GrammarPill: Hashable {
    var label: String
    var fill: GrammarPillFill
    var icon: GrammarPillIcon?
    /// Flex weight. Equal widths assume labels of roughly equal length; a
    /// DATE primary ("Thursday, 10:00 AM") takes 1.55 so the one thing the
    /// card asks you to commit to never wraps (flow-times.css `.ts-pair`).
    var weight: CGFloat = 1
}

struct GrammarPillView: View {
    let pill: GrammarPill

    var body: some View {
        Button(action: {}) { label }
            .buttonStyle(PillPress(pill: pill))
    }

    /// Scale AND fill answer the press. The fill step is per-variant because
    /// #161616 has nowhere darker to go — the commit pill feeds back by going
    /// LIGHTER while the tinted pair goes darker.
    private struct PillPress: ButtonStyle {
        let pill: GrammarPill
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func makeBody(configuration: Configuration) -> some View {
            let pressed = configuration.isPressed
            return configuration.label
                .background(fill(pressed: pressed), in: Capsule())
                .scaleEffect(pressed ? 0.98 : 1)
                .animation(reduceMotion ? nil : GrammarMotion.press(), value: pressed)
        }

        private func fill(pressed: Bool) -> Color {
            switch pill.fill {
            case .primary, .secondary: pressed ? DS.Palette.track : DS.TaskState.chipFill
            case .commit: pressed ? Color(hex: 0x313131) : DS.Palette.ink
            case .meet: GrammarPalette.meetBlue
            case .wallet: .black
            }
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            if let icon = pill.icon, icon.leads {
                icon.view.opacity(icon.opacity)
            }
            Text(pill.label)
                .lineLimit(1)
            if let icon = pill.icon, !icon.leads {
                icon.view.opacity(icon.opacity)
            }
        }
        .font(.system(size: 15, weight: weight))
        .foregroundStyle(ink)
        // The glyph is 20pt of the label's width and the labels are tight:
        // the pill buys the space back out of its own padding (cards.css).
        .padding(.horizontal, pill.icon == nil ? 16 : 12)
        .frame(maxWidth: .infinity, minHeight: DS.Metrics.pillHeightMd)
    }

    private var weight: Font.Weight {
        pill.fill == .secondary ? .medium : .semibold
    }

    private var ink: Color {
        switch pill.fill {
        case .primary: DS.Palette.ink
        case .secondary: DS.Palette.inkMuted
        case .commit: DS.Palette.onInk
        case .meet, .wallet: .white
        }
    }

}

/// `.pill-pair`: 1–2 pills, weight-split widths (equal by default), 8pt gap.
///
/// `onTap` is by INDEX, not by a closure on the pill: GrammarPill is Hashable
/// (the model is diffed, and SwiftUI needs it for ForEach identity) and a
/// closure would cost that. Nil leaves the pills inert, which is what the
/// gallery wants — a drawing has no behaviour.
struct GrammarPillRow: View {
    let pills: [GrammarPill]
    var onTap: ((Int) -> Void)?

    var body: some View {
        GeometryReader { geo in
            let gaps = CGFloat(max(pills.count - 1, 0)) * 8
            let total = pills.reduce(0) { $0 + $1.weight }
            HStack(spacing: 8) {
                ForEach(Array(pills.enumerated()), id: \.offset) { index, pill in
                    let width = (geo.size.width - gaps) * pill.weight / total
                    if let onTap {
                        Button { onTap(index) } label: {
                            GrammarPillView(pill: pill).frame(width: width)
                        }
                        .buttonStyle(.plain)
                    } else {
                        GrammarPillView(pill: pill).frame(width: width)
                    }
                }
            }
        }
        .frame(height: DS.Metrics.pillHeightMd)
    }
}
