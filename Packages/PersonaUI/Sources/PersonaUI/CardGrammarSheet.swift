import PersonaCore
import PersonaDesign
import SwiftUI

// The card's sheet, filled from a live suggestion. R8 makes the sheet the
// deck's only navigation — every card opens one — and R7 says what it opens to
// is THE ARTIFACT: the mail that arrived, the draft that is waiting. Not the
// card restated in bigger type.
//
// What this can honestly show today is bounded by what the feed sends: the
// counterpart's line, and the draft when there is one. The day grid the
// suggest-a-time and invite sheets are drawn around needs a free/busy read the
// card does not carry, so those sheets are not claimed here — a grid drawn
// from nothing would be the exact lie the verdict slot is being kept empty to
// avoid.

struct GrammarCardSheet: View {
    let suggestion: Suggestion
    var onClose: () -> Void
    /// Something the user typed or took off the rail. Both are the same act —
    /// a question or an instruction about THIS card — so they share one route
    /// out (Home seeds a chat turn with the card's context, the way the old
    /// sheet's reply did).
    var onAsk: ((Suggestion, String) -> Void)?

    /// The reply the card is offering, if it is offering one. Its payload is
    /// the real draft: recipient, subject and the body the send would post.
    private var replyAction: GeneratedAction? {
        suggestion.generatedActions.first { $0.kind == .replySend }
    }

    private var senderName: String {
        suggestion.contactName ?? suggestion.contactEmail ?? suggestion.avatarEmail ?? ""
    }

    var body: some View {
        GrammarSheetScaffold(
            title: suggestion.proposalLine,
            subtitle: senderName.isEmpty ? nil : senderName,
            // The rail's chips come from the producer. Empty when it had none
            // worth offering, which is the correct empty rail rather than a
            // generic "Tell me more".
            suggestions: suggestion.facts?.sheetQuestions ?? [],
            composerHint: composerHint,
            onClose: onClose,
            onSuggestion: onAsk.map { ask in { question in ask(suggestion, question) } },
            onSubmit: onAsk.map { ask in { text in ask(suggestion, text) } }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if !suggestion.contextLine.isEmpty {
                    GrammarContextQuote(model: .init(
                        initials: contactMonogram(name: suggestion.contactName, email: suggestion.contactEmail ?? suggestion.avatarEmail) ?? "•",
                        tint: .cool,
                        who: senderName.isEmpty ? String(localized: "The message") : senderName,
                        when: suggestion.ageLabel,
                        quote: suggestion.contextLine,
                        openLabel: String(localized: "View email")
                    ))
                }
                if let reply = replyAction, let body = reply.payload.body, !body.isEmpty {
                    // R6: no bubble restating the title the sheet header
                    // already carries. The draft IS the message.
                    GrammarDraftCard(model: .init(
                        showsBrand: false,
                        fields: draftFields(reply),
                        // Blank lines are paragraph breaks; the draft is shown
                        // exactly as it would send.
                        paragraphs: body
                            .components(separatedBy: "\n")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    ))
                }
            }
        }
    }

    private func draftFields(_ reply: GeneratedAction) -> [(key: String, value: String)] {
        var rows: [(key: String, value: String)] = []
        if let to = reply.payload.to, !to.isEmpty { rows.append((String(localized: "To"), to)) }
        if let subject = reply.payload.subject, !subject.isEmpty { rows.append((String(localized: "Subject"), subject)) }
        return rows
    }

    /// R11's ban applies to the composer's own words too: it says what saying
    /// something here does, not "type a message".
    private var composerHint: String {
        if replyAction != nil, !senderName.isEmpty {
            return String(localized: "Reply to \(senderName) — Persona handles it")
        }
        return String(localized: "Ask about this")
    }
}
