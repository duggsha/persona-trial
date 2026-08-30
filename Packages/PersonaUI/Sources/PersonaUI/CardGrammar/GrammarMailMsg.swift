import PersonaDesign
import SwiftUI

// The embedded email (flow-reply.css `.mail-msg`): one message of the thread,
// shown rather than listed — R7's artifact. The body deliberately does not
// wear Persona type; it wears the mail's own (the shipped rendition is
// SelfSizingMailWebView drawing the sender's HTML).

/// `.mail-avatar` tints. Warm/cool match the card pile's faces so the pile on
/// the card and the avatar in the sheet read as the same person; service is
/// the robot's neutral.
enum GrammarSenderTint: Hashable {
    /// Marisa's own sender colour — not a DS token.
    case marisa
    case warm
    case cool
    case service

    var fill: Color {
        switch self {
        case .marisa: Color(hex: 0xA8563F)
        case .warm: GrammarPalette.faceWarmInk
        case .cool: DS.Palette.accent
        case .service: DS.Palette.surfaceMuted
        }
    }

    var ink: Color {
        self == .service ? DS.Palette.ink : .white
    }
}

struct GrammarMailMessageModel: Hashable {
    var initials: String
    var tint: GrammarSenderTint
    var name: String
    var date: String
    /// Paragraphs, inline-markdown (`**bold**`) rendered in the mail's type.
    var paragraphs: [String]
}

struct GrammarMailMessage: View {
    let model: GrammarMailMessageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(model.tint.fill)
                    .frame(width: 34, height: 34)
                    .overlay {
                        Text(model.initials)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(model.tint.ink)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DS.Palette.ink)
                    Text(model.date)
                        .font(.system(size: 11.5))
                        .foregroundStyle(DS.Palette.placeholder)
                }
            }
            .padding(.bottom, 10)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.paragraphs, id: \.self) { paragraph in
                    Text(.init(paragraph))
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: 0x111111))
                        .grammarLeading(size: 15, weight: .regular, lineHeight: 1.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.78))
                .strokeBorder(DS.Palette.hairlineSoft, lineWidth: 1)
        }
    }
}

// MARK: - The mail as context (flow-times.css `.ts-ctx`)

/// NOT the full render — the mail quoted at the size a quote should be: who
/// asked, what they asked, and the way to the rest one row down.
struct GrammarContextQuoteModel: Hashable {
    var initials: String
    var tint: GrammarSenderTint
    var who: String
    var when: String
    /// Inline-markdown quote; the ask is bold.
    var quote: String
    var openLabel: String
}

struct GrammarContextQuote: View {
    let model: GrammarContextQuoteModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(model.tint.fill)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Text(model.initials)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(model.tint.ink)
                    }
                Text(model.who)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(model.when)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Palette.placeholder)
            }
            .padding(.horizontal, 14)
            Text(.init(model.quote))
                .font(.system(size: 13.5))
                .foregroundStyle(DS.Palette.inkMuted)
                .grammarLeading(size: 13.5, weight: .regular, lineHeight: 1.45)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.top, 9)
            // The full mail is a ROW, not a second copy of the mail — the
            // card's own source row, full-bleed to the plate's edges.
            HStack(spacing: 9) {
                GrammarGlyphView(glyph: GlyphEnvelope.self, size: 14)
                    .foregroundStyle(DS.Palette.placeholder)
                Text(model.openLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.ink)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DS.Palette.placeholder)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle().fill(DS.Palette.hairlineSoft).frame(height: 1)
            }
            .padding(.top, 11)
        }
        .padding(.top, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.78))
                .strokeBorder(DS.Palette.hairlineSoft, lineWidth: 1)
        }
    }
}

// MARK: - The conversation bubble (flow-reply.css `.msg--in`)

/// Persona's line above an embedded draft — a card-coloured bubble with the
/// contact shadow, tail corner at 6.
struct GrammarThreadBubble: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .grammarLeading(size: 15, weight: .regular, lineHeight: 1.4)
            .foregroundStyle(DS.Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                UnevenRoundedRectangle(
                    topLeadingRadius: DS.Radius.bubble,
                    bottomLeadingRadius: 6,
                    bottomTrailingRadius: DS.Radius.bubble,
                    topTrailingRadius: DS.Radius.bubble,
                    style: .continuous
                )
                .fill(DS.Palette.card)
                .dsShadow(DS.Shadow.contact)
            }
            // `.msg` caps at 84% and hugs its content.
            .frame(maxWidth: GrammarChrome.feedWidth * 0.84, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
