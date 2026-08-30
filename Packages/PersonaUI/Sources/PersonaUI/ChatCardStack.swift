import PersonaCore
import PersonaDesign
import SwiftUI

/// Where a message's rich inline cards would draw.
///
/// In the real app a turn can carry structured cards — a ride, an order, a mail
/// chip, a link preview — and they render here, above or below the assistant's
/// text. Every one of those renderers is a live surface wired to a backend
/// (Amazon checkout, the connect sheets, contacts and photo-library sync), so
/// they were cut from this trial along with the rest of it.
///
/// The seeded transcript carries no cards, so this never has anything to draw.
/// It exists because the transcript still asks for it in two places, and
/// keeping the call sites intact keeps the message layout — the spacing rules,
/// which element in a run wears the tail — exactly as it is in the app.
struct ChatCardStack: View {
    let cards: [ChatCard]
    /// When set, each card renders AS an iMessage bubble the way Messages
    /// renders app-messages.
    var bubbleSide: IMessageBubbleShape.Side? = nil
    /// Whether this stack closes its sender run — the last card then carries
    /// the tail. Exactly one element per run tails.
    var bubbleTail = false
    /// When the enclosing message was created.
    var messageDate: Date? = nil
    /// Reply wiring for cards that own their own context menu.
    var onReplyCard: ((ChatCard) -> Void)? = nil

    var body: some View {
        EmptyView()
    }
}

extension ChatCard {
    /// Chips ride bare in the transcript; everything else takes a bubble. The
    /// transcript reads this to decide which element in a sender run wears the
    /// tail, so it stays correct even with no cards to draw.
    var rendersAsChip: Bool {
        switch self {
        case .status, .mailRef, .unknown, .toolRun, .task, .delegation: true
        default: false
        }
    }

    /// Cards that draw their OWN bubble-shaped container rather than riding the
    /// white plate — the link preview's full-bleed image with the tail traced on
    /// its own outline.
    var drawsOwnBubble: Bool {
        if case .linkPreview = self { return true }
        return false
    }
}

/// A reminder's bare Snooze / Done actions, hung under the text bubble of the
/// turn that delivered it.
///
/// The real card talks to the reminders service: snoozing and completing are
/// both writes, and it reconciles against the server's status. Seeded
/// transcripts carry no reminder cards, so this never draws.
struct ReminderChatCard: View {
    let reminderId: String
    let title: String
    let serverStatus: String
    let serverUntilISO: String?
    var embedded = false

    var body: some View {
        EmptyView()
    }
}
