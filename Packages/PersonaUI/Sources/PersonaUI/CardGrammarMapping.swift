import Foundation
import PersonaCore

// Live suggestion → card grammar. The backend bends to the design here, not
// the other way round: every slot below is filled from a
// field the feed already sends, and where the design wants something the feed
// has no field for, the slot stays EMPTY rather than being faked out of a
// neighbouring value. An invented subtitle is worse than none — it reads as a
// fact and is not one.
//
// Rules and slot order: docs/prototypes/notification-cards/CARD-RULES.md.

/// The migration switch. `CARD_GRAMMAR=1` (env) or `-CARD_GRAMMAR` (launch
/// arg) draws the feed through the grammar; off, every card keeps the drawing
/// it has today. Off by default while Alan is still polishing the deck.
enum CardGrammar {
    static var isOn: Bool {
        let process = ProcessInfo.processInfo
        return process.environment["CARD_GRAMMAR"] == "1" || process.arguments.contains("-CARD_GRAMMAR")
    }
}

extension Suggestion {
    /// This card as a grammar drawing, or nil when it has none and must keep
    /// the drawing it has today.
    ///
    /// `codeCountdown` is passed IN rather than computed here because T3's
    /// countdown is a plain String and the row it belongs to ticks once a
    /// second. The caller owns the clock (a TimelineView), so the model is
    /// rebuilt each tick and the countdown stays live instead of freezing at
    /// whatever it read when the card was first laid out. A sign-in code
    /// without one returns nil rather than a stopped clock.
    func grammarDrawing(isUnread: Bool, codeCountdown: String? = nil) -> GrammarDrawing? {
        if let code {
            guard let codeCountdown else { return nil }
            // R14: the one card allowed to be shaped like nothing else. The
            // eyebrow is the row's own line ("Your Notion sign-in code") — the
            // deck writes "Anthropic · sign-in code", but the service name is
            // not a field we are sent, and splitting it out of the copy would
            // be guessing at a string's shape.
            return .t3(GrammarT3Model(eyebrow: message, countdown: codeCountdown, code: code))
        }
        if let order = orderProgress { return .t2(grammarTracker(order)) }
        return grammarCard(isUnread: isUnread).map { .t1($0) }
    }

    /// T2 · the live tracker. `progress` is authoritative (the backend ranks
    /// the states, the client never re-ranks them), so the stage index is read
    /// off it rather than matched on the status words.
    private func grammarTracker(_ order: OrderProgressItem) -> GrammarT2Model {
        // The delivery run's own stages. A pickup order never gets a courier,
        // so it stops one short and the last stage is the counter, not a door.
        let stops = order.isPickup
            ? [String(localized: "Placed"), String(localized: "Confirmed"), String(localized: "Ready"), String(localized: "Picked up")]
            : [String(localized: "Placed"), String(localized: "Confirmed"), String(localized: "Ready"), String(localized: "On the way"), String(localized: "Delivered")]
        let last = stops.count - 1
        return GrammarT2Model(
            lockup: .doorDash,
            // The deck omits the ETA until the live socket lands (T5.4a) and
            // the feed has no ETA field, so it stays off rather than guessed.
            trailingFact: nil,
            status: order.status,
            detail: order.storeName ?? "",
            stops: stops,
            currentStop: order.done ? last : min(Int((order.progress * Double(last)).rounded()), last),
            brandTint: GrammarPalette.brandDoorDash
        )
    }

    func grammarCard(isUnread: Bool) -> GrammarT1Model? {
        guard code == nil, orderProgress == nil else { return nil }
        return GrammarT1Model(
            mark: grammarMark,
            title: proposalLine,
            subtitle: grammarSubtitle,
            meta: .age(ageLabel, unread: isUnread),
            body: contextLine.isEmpty ? nil : contextLine,
            // The green dot, straight from the producer. Absent when it found
            // nothing real to say, which is the correct empty slot rather than
            // something the client invents to fill it.
            verdict: facts?.verdict.flatMap { text in
                text.isEmpty ? nil : GrammarVerdict(text: text, clash: facts?.verdictClash == true)
            },
            pills: grammarPills
        )
    }

    /// R2's mark. A BRAND the card is unmistakably about wins first (its own
    /// tile is more identifying than the sender's initials), then a real
    /// person, then a Persona-drawn notice glyph.
    ///
    /// ponytail: the glyph fallbacks stay a SMALL set. The deck draws a credit
    /// card for money and a pin for a place, but the feed sends no category
    /// field to pick those off, and guessing one from title words would be a
    /// lie that looks like a fact. Widen this when the backend names it.
    private var grammarMark: GrammarMark {
        if let brand = grammarBrandMark { return brand }
        if let initials = contactMonogram(name: contactName, email: contactEmail ?? avatarEmail) {
            return .person(initials)
        }
        switch kind {
        case "mail-reconnect": return .glyphAsset("LogoGmail")
        case "review.suggestion": return .shieldCheck
        default: return facts?.venue?.isEmpty == false ? .pin : .envelope
        }
    }

    /// The four brand marks the deck ships artwork for. Matched on the resolved
    /// `logoDomain` rather than on words in the copy: the domain is a fact the
    /// backend resolved, a title that happens to say "amazon" is not.
    ///
    /// A brand with no bundled artwork deliberately falls through to the
    /// monogram — logo.dev can fetch it for the old card, but GrammarMark has
    /// no remote-image case, and inventing one is Alan's call, not this file's.
    private var grammarBrandMark: GrammarMark? {
        guard let domain = logoDomain?.lowercased(), !domain.isEmpty else { return nil }
        if domain.contains("amazon") { return .tileAsset("LogoAmazonTile") }
        if domain.contains("meet.google") || domain.contains("google.com") { return .brandAsset("LogoGoogleMeet") }
        if domain.contains("doordash") { return .tileAsset("LogoDoorDashMark") }
        if domain.contains("lyft") { return .tileAsset("LogoLyft") }
        return nil
    }

    /// R2: "the one fact that identifies the source" — the person, or the
    /// event's own when/where/price. Empty when the card names neither, which
    /// the header renders as an absent slot rather than a blank line.
    private var grammarSubtitle: String {
        // The producer's own line wins: most of the deck's subtitles name a
        // source the client cannot compose (an org, an account state, a
        // boarding gate). The derivations below stay as the fallback for cards
        // minted before the field existed.
        if let authored = facts?.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !authored.isEmpty {
            return authored
        }
        if let facts, !facts.isEmpty {
            let parts = [facts.date, facts.venue, facts.price]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !parts.isEmpty { return parts.joined(separator: " · ") }
        }
        return contactName ?? contactEmail ?? avatarEmail ?? ""
    }

    /// The generated actions the pills stand for, in pill order. The row taps
    /// by INDEX, so this and `grammarPills` must stay in lockstep — they are
    /// two maps over this ONE list rather than two independent filters, which
    /// is the only way an index can be trusted. Empty on a card whose actions
    /// are all legacy; those pills open the sheet instead of running.
    var grammarPillActions: [GeneratedAction] {
        Array(generatedActions.filter(\.isProposable).prefix(2))
    }

    /// R6/R13: one or two pills, primary first. Generated actions are the real
    /// vocabulary; the legacy `actions` list is the fallback for cards minted
    /// before it. A bare acknowledge is a dismissal, never a proposed action,
    /// so it never becomes a pill — a card left with none draws no pill row.
    private var grammarPills: [GrammarPill] {
        // A parked Apple Wallet pass carries no backend action — the row's
        // whole point is the one-tap add, and it was expressed as a bespoke
        // chip rather than an action. Without this the card draws with no
        // button at all and the pass becomes unreachable. R13: Wallet's own
        // black, because the button IS a handoff to Wallet.
        if !(walletPasses ?? []).isEmpty {
            return [GrammarPill(label: String(localized: "Add to Wallet"), fill: .wallet, icon: nil)]
        }
        let generated = grammarPillActions
        if !generated.isEmpty {
            return generated.enumerated().map { index, action in
                GrammarPill(
                    label: action.label,
                    fill: index == 0 ? .primary : .secondary,
                    icon: index == 0 ? GrammarPillIcon.forGeneratedKind(action.kind) : nil
                )
            }
        }
        return actions.filter { $0.type != "acknowledge" }.prefix(2).enumerated().map { index, action in
            GrammarPill(
                label: action.label,
                fill: index == 0 ? .primary : .secondary,
                icon: index == 0 ? GrammarPillIcon(legacyActionType: action.type) : nil
            )
        }
    }

}

extension GrammarPillIcon {
    /// R6: the glyph says what pressing the button does to the world. Anything
    /// that opens a composing surface is `.mail`, work handed to the agent is
    /// `.agent`, and a link that leaves the app trails `.external`. A pill with
    /// no glyph is the default — a row where every button is decorated says
    /// nothing.
    static func forGeneratedKind(_ kind: GeneratedActionKind) -> GrammarPillIcon? {
        switch kind {
        case .replySend, .replyOption: .mail
        case .startTask: .agent
        case .openLink: .external
        case .createMeeting, .remind: .sheet
        case .acknowledge, .unknown: nil
        }
    }

    init?(legacyActionType: String) {
        switch legacyActionType {
        case "send_draft": self = .mail
        case "start_task": self = .agent
        case "open_link": self = .external
        case "create_meeting": self = .sheet
        default: return nil
        }
    }
}

extension GeneratedActionKind {
    /// Does tapping this pill DO the thing, or open the sheet first?
    ///
    /// Read straight off the deck's own glyph semantics (R6): `.agent` is
    /// "Persona goes and does it out of band" and `.external` is "puts you in
    /// another app" — both are complete on one tap. Everything else composes
    /// something the user must see first, and a card that mails a draft nobody
    /// read is the one failure this rule exists to prevent.
    var runsOnTap: Bool {
        switch self {
        case .startTask, .openLink: true
        default: false
        }
    }
}
