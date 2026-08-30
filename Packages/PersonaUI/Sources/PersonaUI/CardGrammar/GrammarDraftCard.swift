import PersonaDesign
import SwiftUI

// The email draft (flow-reply.css `.draft-card` + a-actionable's FieldStack):
// the drafted reply embedded in the sheet's conversation as an email — brand
// tile + EMAIL eyebrow, the address rows, the body in the user's voice, and
// the small Edit / Send pair. The real Send lives HERE, under the draft it
// commits you to (R7).

struct GrammarDraftCardModel {
    /// The flow draft leads with the Gmail tile; the sheet-quoted variant
    /// wears the bare EMAIL eyebrow (grammar.html's `.dc-head`).
    var showsBrand = true
    /// From is present on the send-capable draft; the card-quoted variant
    /// omits it (server stamps routing — the model never routes).
    var fields: [(key: String, value: String)]
    /// Paragraphs of the draft, in the user's voice.
    var paragraphs: [String]
}

struct GrammarDraftCard: View {
    let model: GrammarDraftCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if model.showsBrand {
                    // `.dc-brand`: the real Gmail artwork on the muted tile —
                    // CardHeaderRow's render for brandTile == "gmail".
                    ZStack {
                        RoundedRectangle(cornerRadius: DS.Radius.iconTile, style: .continuous)
                            .fill(DS.Palette.surfaceMuted)
                        PersonaAsset.image("LogoGmail")
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 18)
                    }
                    .frame(width: DS.Metrics.iconTile, height: DS.Metrics.iconTile)
                }
                Text("Email")
                    .font(.system(size: 12, weight: .medium))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(DS.Palette.subtle)
                Spacer(minLength: 0)
                Text("···")
                    .font(.system(size: 17))
                    .foregroundStyle(DS.Palette.placeholder)
                    .padding(4)
            }
            .padding(.bottom, 8)
            ForEach(Array(model.fields.enumerated()), id: \.offset) { index, field in
                VStack(alignment: .leading, spacing: 3) {
                    Text(field.key)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DS.Palette.subtle)
                    Text(field.value)
                        .font(.system(size: 15))
                        .foregroundStyle(DS.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) {
                    if index > 0 {
                        Rectangle().fill(DS.Palette.hairlineSoft).frame(height: 1)
                    }
                }
            }
            Rectangle().fill(DS.Palette.hairlineSoft).frame(height: 1)
            // pre-line paragraphs: a blank line apart, i.e. one line-height.
            VStack(alignment: .leading, spacing: 22) {
                ForEach(Array(model.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.system(size: 15))
                        .grammarLeading(size: 15, weight: .regular, lineHeight: 1.45)
                        .foregroundStyle(DS.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 2)
            // The two 30pt capsules, labels not glyph-riddles, in THAT order.
            HStack(spacing: 6) {
                capButton(label: "Edit", weight: .medium, ink: DS.Palette.inkMuted) {
                    GrammarGlyphView(glyph: GlyphPencil.self, size: 10)
                }
                capButton(label: "Send", weight: .semibold, ink: DS.Palette.ink) {
                    GrammarGlyphView(glyph: GlyphSendPlane.self, size: 10)
                }
            }
            .padding(.top, 12)
        }
        .grammarCardPlate()
        .grammarCardIn()
    }

    private func capButton(label: String, weight: Font.Weight, ink: Color, @ViewBuilder glyph: () -> some View) -> some View {
        HStack(spacing: 4) {
            glyph()
            Text(label)
        }
        .font(.system(size: 12, weight: weight))
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background(DS.TaskState.chipFill, in: Capsule())
        .grammarPressable()
    }
}

/// The Edit cap's pencil (draft-edit.html).
enum GlyphPencil: GrammarGlyph {
    static let unit: CGFloat = 12
    static func layers() -> [GrammarGlyphLayer] {
        var p = Path()
        p.move(to: CGPoint(x: 8.4, y: 1.6))
        p.addLine(to: CGPoint(x: 10.4, y: 3.6))
        p.addLine(to: CGPoint(x: 4, y: 10))
        p.addLine(to: CGPoint(x: 2, y: 10))
        p.addLine(to: CGPoint(x: 2, y: 8))
        p.closeSubpath()
        return [.init(path: p, stroke: 1.6)]
    }
}

/// The Send cap's paper plane (draft-edit.html) — filled, unlike its siblings.
enum GlyphSendPlane: GrammarGlyph {
    static let unit: CGFloat = 12
    static func layers() -> [GrammarGlyphLayer] {
        var p = Path()
        p.move(to: CGPoint(x: 11, y: 1))
        p.addLine(to: CGPoint(x: 1, y: 5.2))
        p.addLine(to: CGPoint(x: 4.6, y: 6.6))
        p.addLine(to: CGPoint(x: 10.2, y: 2))
        p.addLine(to: CGPoint(x: 5.6, y: 7.6))
        p.addLine(to: CGPoint(x: 7, y: 11))
        p.closeSubpath()
        return [.init(path: p, stroke: nil)]
    }
}
