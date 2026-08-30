import PersonaDesign
import SwiftUI

// The T1 mark: 34pt, always (R2). Pill radius for a person, tile radius for
// a Persona-authored notice or a brand. What varies is only how the artwork
// is drawn inside the square — a brand does not get to change the square.

/// One face of a cast pile. The tints are roles, not identities: warm and
/// cool are the two parties of the negotiation, service is the robot (which
/// as of never appears in a card's pile — it announces a state,
/// it does not take a position; it survives in the sheet).
struct GrammarFace: Hashable {
    enum Tint: Hashable {
        case warm
        case cool
        case service
    }

    var initials: String
    var tint: Tint

    var fill: Color {
        switch tint {
        case .warm: GrammarPalette.faceWarmFill
        case .cool: GrammarPalette.faceCoolFill
        case .service: DS.Palette.surfaceMuted
        }
    }

    var ink: Color {
        switch tint {
        case .warm: GrammarPalette.faceWarmInk
        case .cool: GrammarPalette.faceCoolInk
        case .service: DS.Palette.inkMuted
        }
    }
}

/// `.t1-mark` and its variants — a closed set, one per way a mark can be
/// supplied, never per producer.
enum GrammarMark: Hashable {
    /// A Persona-drawn notice glyph, stroked ink on the muted tile.
    case pin
    case creditCard
    case shieldCheck
    case envelope
    /// A person's monogram on the pill disc.
    case person(String)
    /// A service's monogram on the pill disc (airline code, robot).
    case service(String)
    /// A bundled multicolour service glyph on a white tile with a hairline —
    /// BrandGlyphBadge's geometry at mark size (Gmail, Calendar, Drive).
    case glyphAsset(String)
    /// Brand artwork on the muted tile (the Meet logo).
    case brandAsset(String)
    /// The vendor's own app tile, full-bleed with the hairline that keeps a
    /// near-white field from dissolving into the card (Amazon).
    case tileAsset(String)
    /// The cast: two 22pt faces on the 34pt square's diagonal. Who the card
    /// is between, not everyone on the thread (R6).
    case pile(GrammarFace, GrammarFace)
}

struct GrammarMarkView: View {
    let mark: GrammarMark

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DS.Radius.iconTile, style: .continuous)
    }

    var body: some View {
        switch mark {
        case .pin: glyphTile { GrammarGlyphView(glyph: GlyphPin.self, size: 15) }
        case .creditCard: glyphTile { GrammarGlyphView(glyph: GlyphCreditCard.self, size: 15) }
        case .shieldCheck: glyphTile { GrammarGlyphView(glyph: GlyphShieldCheck.self, size: 15) }
        case .envelope: glyphTile { GrammarGlyphView(glyph: GlyphEnvelope.self, size: 15) }
        case let .person(initials):
            monogram(initials, fill: GrammarPalette.personFill, ink: GrammarPalette.personInk)
        case let .service(initials):
            monogram(initials, fill: GrammarPalette.serviceFill, ink: GrammarPalette.serviceInk)
        case let .glyphAsset(asset):
            ZStack {
                tileShape.fill(DS.Palette.card)
                PersonaAsset.image(asset)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    // 34 × 0.58 — BrandGlyphBadge's fit, at mark size.
                    .frame(width: 19.7, height: 19.7)
            }
            .frame(width: DS.Metrics.iconTile, height: DS.Metrics.iconTile)
            .overlay { tileShape.strokeBorder(DS.Palette.hairlineSoft, lineWidth: 1) }
        case let .brandAsset(asset):
            ZStack {
                tileShape.fill(DS.Palette.surfaceMuted)
                PersonaAsset.image(asset)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 19)
            }
            .frame(width: DS.Metrics.iconTile, height: DS.Metrics.iconTile)
        case let .tileAsset(asset):
            PersonaAsset.image(asset)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: DS.Metrics.iconTile, height: DS.Metrics.iconTile)
                .clipShape(tileShape)
                .overlay { tileShape.strokeBorder(DS.Palette.hairlineSoft, lineWidth: 1) }
        case let .pile(first, second):
            // Second face paints over the first, as the prototype's DOM order
            // does — the overlap is on the diagonal, top-left under.
            ZStack {
                face(first)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                face(second)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .frame(width: DS.Metrics.iconTile, height: DS.Metrics.iconTile)
        }
    }

    private func glyphTile(@ViewBuilder content: () -> some View) -> some View {
        ZStack {
            tileShape.fill(DS.Palette.surfaceMuted)
            content().foregroundStyle(DS.Palette.ink)
        }
        .frame(width: DS.Metrics.iconTile, height: DS.Metrics.iconTile)
    }

    private func monogram(_ initials: String, fill: Color, ink: Color) -> some View {
        Circle()
            .fill(fill)
            .frame(width: DS.Metrics.iconTile, height: DS.Metrics.iconTile)
            .overlay {
                Text(initials)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(ink)
            }
    }

    /// One 22pt disc of the pile, with the 2pt card-colour ring that makes
    /// two overlapping discs read as two people rather than one dented shape.
    /// The ring sits fully OUTSIDE the disc (the CSS is a box-shadow), so it
    /// is a 26pt card-colour disc underneath, not a centred stroke.
    private func face(_ face: GrammarFace) -> some View {
        Circle()
            .fill(face.fill)
            .frame(width: 22, height: 22)
            .overlay {
                Text(face.initials)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(face.ink)
            }
            .background { Circle().fill(DS.Palette.card).frame(width: 26, height: 26) }
    }
}
