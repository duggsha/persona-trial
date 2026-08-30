import PersonaDesign
import SwiftUI

// The sheet chrome (flow-reply.css `.sheet`): grab, head (title + optional
// subtitle + close), scroll, optional suggestion rail, composer. R8 makes the
// sheet the deck's main road — every card opens one — and R7 says it shows
// the artifact. Design implementation only: nothing here is wired.

struct GrammarSheetScaffold<Content: View>: View {
    var title: String
    var subtitle: String?
    /// `.ev-sugs`: offered questions, not a menu of features. The test is the
    /// same one that justifies the sheet — **each chip is a thing the card
    /// itself cannot answer**, so a chip that the collapsed card already
    /// settles is decoration. Most sheets carry a pair;
    /// they read as the second and third questions a person has after the one
    /// the card answered, and they are drawn from a source the sheet can
    /// actually reach: the calendar (`What else is on Thursday?`), the mail
    /// history (`When did she last reschedule?`), the draft in front of you
    /// (`Can you make it shorter?`).
    ///
    /// A RAIL, not a wrapping block: pinned above the composer it has one line
    /// to live on, and a second row would push the field down as suggestions
    /// change — overflow scrolls sideways instead. They disappear once tapped;
    /// a suggestion that survives being taken is a button.
    var suggestions: [String] = []
    /// The composer placeholder — this sheet's own; everything else about the
    /// composer is the home bar's.
    var composerHint: String
    /// Dismiss. Nil in the gallery, where the sheet is a drawing on a canvas
    /// and the close circle has nothing to close.
    var onClose: (() -> Void)?
    /// A chip was taken. Nil leaves the rail decorative, which is what the
    /// gallery wants; the feed passes one and the chip becomes a question.
    var onSuggestion: ((String) -> Void)?
    /// The composer's text was submitted. Nil renders the drawn placeholder
    /// (no field), so the gallery's screenshot is unchanged.
    var onSubmit: ((String) -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(DS.Palette.ink.opacity(0.18))
                .frame(width: 36, height: 5)
                .padding(.top, 7)
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 20, weight: .semibold))
                        .tracking(-0.30)
                        .grammarLeading(size: 20, weight: .semibold, lineHeight: 1.2)
                        .foregroundStyle(DS.Palette.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13.5))
                            .foregroundStyle(DS.Palette.placeholder)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let onClose {
                    Button(action: onClose) { closeCircle }.buttonStyle(.plain)
                } else {
                    closeCircle
                }
            }
            .padding(EdgeInsets(top: 15, leading: 18, bottom: 14, trailing: 18))
            ScrollView {
                content
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .padding(.bottom, 22)
            }
            .scrollIndicators(.hidden)
            if !suggestions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            let chip = Text(suggestion)
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(DS.Palette.ink)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(DS.Palette.card, in: Capsule())
                                .compositingGroup()
                                .dsShadow(DS.Shadow.contact)
                                .grammarPressable()
                            if let onSuggestion {
                                Button { onSuggestion(suggestion) } label: { chip }.buttonStyle(.plain)
                            } else {
                                chip
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 2)
                }
                .scrollIndicators(.hidden)
            }
            GrammarSheetComposer(hint: composerHint, onSubmit: onSubmit)
        }
        .background {
            // The soft wash: white fading out over the top 220pt of surface.
            ZStack(alignment: .top) {
                DS.Palette.surface
                LinearGradient(
                    colors: [.white.opacity(0.75), .white.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 220)
            }
        }
    }

    private var closeCircle: some View {
        Circle()
            .fill(.white.opacity(0.85))
            .frame(width: 34, height: 34)
            .overlay { Circle().strokeBorder(DS.Palette.hairlineSoft, lineWidth: 1) }
            .overlay {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.ink)
            }
            .grammarPressable()
    }
}

/// `.sheet-composer`: the REAL composer — same capsule, same floating +, same
/// metrics as the home bar. The mic here is the only mic in the deck (R12).
struct GrammarSheetComposer: View {
    var hint: String
    /// Wired = a REAL field. Nil keeps Alan's drawn placeholder, so the
    /// gallery still screenshots the composer as designed.
    var onSubmit: ((String) -> Void)?

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(DS.Palette.card)
                .frame(width: 46, height: 46)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 19, weight: .light))
                        .foregroundStyle(DS.Palette.ink)
                }
                .compositingGroup()
                .dsShadow(DS.Shadow.chip)
            HStack(spacing: 10) {
                if onSubmit != nil {
                    TextField(hint, text: $text, axis: .vertical)
                        .font(.system(size: 16))
                        .foregroundStyle(DS.Palette.ink)
                        .lineLimit(1 ... 4)
                        .focused($focused)
                        .submitLabel(.send)
                        .onSubmit(send)
                } else {
                    Text(hint)
                        .font(.system(size: 16))
                        .foregroundStyle(DS.Palette.placeholder)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if onSubmit != nil, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DS.Palette.onInk)
                            .frame(width: 32, height: 32)
                            .background(DS.Palette.ink, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                }
                if onSubmit == nil {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DS.Palette.subtle)
                        .frame(width: 9, height: 15)
                        .padding(.trailing, 10)
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 8)
            .frame(minHeight: 46)
            .background(DS.Palette.card, in: Capsule())
            .compositingGroup()
            .dsShadow(DS.Shadow.chip)
        }
        .padding(EdgeInsets(top: 10, leading: 18, bottom: 26, trailing: 18))
    }

    private func send() {
        let outgoing = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !outgoing.isEmpty else { return }
        text = ""
        focused = false
        onSubmit?(outgoing)
    }
}

/// The gallery's sheet plate (grammar.css `.win`): 362 wide, fixed height,
/// 28pt corner, surface fill, the card's plate shadow — a stable frame for
/// shot-to-shot comparison, not app chrome.
struct GrammarSheetFrame<Content: View>: View {
    var height: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: GrammarChrome.feedWidth, height: height)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.Palette.surface)
                    .dsShadow(DS.Shadow.plate)
            }
    }
}
