import PersonaDesign
import SwiftUI

// The card grammar's shared chrome: the feed geometry, the cap-line datum the
// whole header hangs off, and the handful of tints the deck defines that DS
// does not. Visual source of truth: docs/prototypes/notification-cards/
// (grammar.html + cards.css); rules in CARD-RULES.md (R0–R15).

enum GrammarChrome {
    /// Feed width: 402pt screen − 2 × 20pt gutter. Every drawing in the deck
    /// is made at this width and the gallery pins it so a shot lines up with
    /// grammar.html column-for-column.
    static let feedWidth: CGFloat = 362

    /// `.t1-head` gap: mark → lines → meta.
    static let headerGap: CGFloat = 10
}

/// Tints the deck defines outside DS.Palette. Light-only, like the prototype
/// page — the dark half lands with the dark-mode polish round, not here.
enum GrammarPalette {
    /// `.t1-mark--person`: a person's monogram disc.
    static let personFill = Color(hex: 0xE8ECF2)
    static let personInk = Color(hex: 0x4B5B6B)
    /// `.t1-mark--service`: a service's monogram disc (airline, robot).
    static let serviceFill = Color(hex: 0xEFE9E2)
    static let serviceInk = Color(hex: 0x8A7250)
    /// `.ev-face--warm` / `--cool`: the two parties of a cast pile.
    static let faceWarmFill = Color(hex: 0xEFE7D8)
    static let faceWarmInk = Color(hex: 0x8A6F45)
    static let faceCoolFill = DS.Palette.accent.opacity(0.14)
    static let faceCoolInk = DS.Palette.accent
    /// `.verdict--clash`: amber, not red — still doable, just costs something.
    static let verdictClash = Color(hex: 0xC99700)
    /// `.pill--meet`: flat Meet blue, no gradient.
    static let meetBlue = Color(hex: 0x0957D0)
    /// Brand constant, sampled off the artwork that ships (cards.css) — the
    /// one element DoorDash's own product tints is the order bar. Lyft's pink
    /// lives only in its wordmark asset; the ride's track stays ink.
    static let brandDoorDash = Color(hex: 0xEB1700)
}

// MARK: - The cap line is the datum (cards.css, design)

/// `.t1-head` aligns the mark's TOP EDGE to the title's CAP TOP. The CSS does
/// it with text-box-trim; here the header is a plain `.top` HStack and the
/// FIXED children sink by the title's trimmed ascent, derived from the font's
/// own metrics so it survives a type change (a hardcoded 5pt nudge is the
/// named failure mode). Deliberately NOT a custom VerticalAlignment: a guide
/// on the wrapping title column makes SwiftUI settle its width at one line
/// and ellipsize — the layout is order-dependent — so the corrections all
/// live on the rigid children instead, which is geometrically identical.
enum GrammarCapline {
    /// The dead space a text box carries above its capitals: half-leading is
    /// SwiftUI lineSpacing (below the line, not above the first), so the trim
    /// is ascender − capHeight.
    static func trim(size: CGFloat, weight: UIFont.Weight) -> CGFloat {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        return font.ascender - font.capHeight
    }

    /// The title's trim — what the mark beside a 16/600 title sinks by.
    static var titleTrim: CGFloat { trim(size: 16, weight: .semibold) }

    /// The meta stamp's top inset: its cap rides 2pt below the title's cap —
    /// 12pt type cap-aligned dead-on with 16pt type reads a touch high
    /// (cards.css `.t1-meta`).
    static var metaInset: CGFloat { titleTrim + 2 - trim(size: 12, weight: .medium) }
}

// MARK: - Line height

extension View {
    /// CSS line-height as SwiftUI lineSpacing: the deck's leadings are part of
    /// the drawing (a 3-line body at 1.45 is 20.3pt per line), and SF's
    /// default leading is tighter than all of them.
    func grammarLeading(size: CGFloat, weight: UIFont.Weight, lineHeight: CGFloat) -> some View {
        lineSpacing(size * lineHeight - UIFont.systemFont(ofSize: size, weight: weight).lineHeight)
    }
}

// MARK: - The plate

extension View {
    /// `.card`: the one card plate — white, 28pt continuous corner, the
    /// plate shadow pair, 14pt padding. R8 makes the whole plate the door,
    /// so the card itself is the tap target; nothing on it is outlined.
    func grammarCardPlate() -> some View {
        padding(DS.Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .solidCardPlate()
    }
}
