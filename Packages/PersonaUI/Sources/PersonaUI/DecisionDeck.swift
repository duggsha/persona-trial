import SwiftUI
import PersonaCore
import PersonaDesign

// MARK: - The decision deck, round 3
//
// One decision owns the screen. The feed is a vertical pager: the focused
// card takes most of the viewport, the previous card's tail and the next
// card's head stay visible as depth cues, and one swipe moves exactly one
// card — the TikTok contract, applied to permission instead of video.
//
// ASKS carry the question, the full context, the draft, and both actions.
// UTILITY (a sign-in code) is the action itself. HANDLED is the ledger:
// receipts, the rule that authorised each, undo. Judgment stays one tap away
// and every standing rule reads as a sentence.
//
// Two ways to look at the same day: FEED (the pager) and BRIEF (a single
// composed page, closer to a morning briefing). The switcher is a native
// menu; the engine is shared, so both views are the same truth.

enum DK {
    static let cardRadius: CGFloat = 8
    static let wellRadius: CGFloat = 5
    static let chipRadius: CGFloat = 4
    static let pad: CGFloat = 18
    static let gutter: CGFloat = 16
}

// MARK: Model

struct DeckRunStep: Identifiable, Equatable {
    let id = UUID()
    let logo: IrisLogo
    let text: String
    var detail: String? = nil
}

@MainActor @Observable
final class DeckItem: Identifiable {
    enum Phase: Equatable { case asking, running(Int), done, failed, dismissed }

    let id = UUID()
    let kind: String
    let source: String
    let logo: IrisLogo
    let avatarAsset: String?
    let ask: String
    let context: String
    let facts: String?
    var draft: String?
    let primaryLabel: String
    let declineLabel: String
    let alwaysSentence: String?
    let steps: [DeckRunStep]
    let receiptLine: String
    var ranUnderRule: String?
    /// What the other side actually said. A card that asks you to reply should
    /// show you the sentence you are replying to.
    let incoming: String?
    /// Who caused this, and what Iris made of it. Two words each: the card has
    /// to be readable as cause then response without being read as a paragraph.
    let triggerLabel: String
    let responseLabel: String
    let replyStyle: ReplyStyle
    let stakes: Stakes
    /// What is actually at risk, said plainly, above a high-stakes control.
    let consequence: String?
    /// Seeded so one card can fail on purpose. Failure is a state this product
    /// has to have an answer for, not an edge case to leave out of the demo.
    let failsOnce: Bool
    let failureLine: String?
    let trace: ThinkingTrace?
    let tracker: DeckTracker?
    let ticket: DeckTicket?
    /// Set once the receipt has been read and the card has left the deck.
    var filed = false
    /// Cleared by a retry so the seeded failure only happens once.
    var failed = true
    /// The window this card is about, drawn as a ruler rather than described.
    let window: DeckWindow?
    /// How this got here: the signals that produced the card, in order.
    /// Rendered as one dense mono line, not prose.
    let trail: [String]
    let createdAgo: String
    var code: String?
    var codeDeadline: Date?
    var copied = false
    /// The ticket's time, editable in place.
    var ticketTime = Date()
    var phase: Phase = .asking

    init(kind: String, source: String, logo: IrisLogo, avatarAsset: String? = nil,
         ask: String, context: String, facts: String? = nil,
         incoming: String? = nil, triggerLabel: String = "", responseLabel: String = "",
         replyStyle: ReplyStyle = .plain, stakes: Stakes = .low,
         consequence: String? = nil, failsOnce: Bool = false, failureLine: String? = nil,
         trace: ThinkingTrace? = nil, tracker: DeckTracker? = nil, ticket: DeckTicket? = nil,
         window: DeckWindow? = nil,
         draft: String? = nil, primaryLabel: String = "", declineLabel: String = "Not this",
         alwaysSentence: String? = nil, steps: [DeckRunStep] = [], receiptLine: String = "",
         ranUnderRule: String? = nil,
         trail: [String] = [], createdAgo: String, code: String? = nil,
         codeDeadline: Date? = nil, phase: Phase = .asking, filed: Bool = false) {
        self.kind = kind; self.source = source; self.logo = logo
        self.avatarAsset = avatarAsset; self.ask = ask; self.context = context
        self.facts = facts; self.draft = draft
        self.primaryLabel = primaryLabel; self.declineLabel = declineLabel
        self.alwaysSentence = alwaysSentence; self.steps = steps
        self.receiptLine = receiptLine; self.ranUnderRule = ranUnderRule
        self.incoming = incoming
        self.triggerLabel = triggerLabel; self.responseLabel = responseLabel
        self.replyStyle = replyStyle; self.stakes = stakes
        self.consequence = consequence
        self.failsOnce = failsOnce; self.failureLine = failureLine
        self.trace = trace; self.tracker = tracker; self.ticket = ticket
        self.window = window
        self.trail = trail; self.createdAgo = createdAgo; self.code = code; self.codeDeadline = codeDeadline
        self.phase = phase; self.filed = filed
    }
}

/// A block of time, for drawing. Hours are 24h decimals: 15.5 is 3:30 PM.
/// How the reply should be drawn. A message you are about to send in iMessage
/// should look like an iMessage; the point of approving is recognising the
/// thing you are approving.
enum ReplyStyle { case plain, mail, imessage }

/// How much the ask should cost you. Moving your own calendar and spending
/// your money must not be approved by the same gesture: a tap is right for
/// something reversible and private, and wrong for something that reaches a
/// real person or a real card. High stakes asks for a deliberate slide, and
/// the slide is the only way through.
/// Three tiers, because two was too blunt. A calendar move you can undo, a
/// message you can follow up on, and money you cannot get back are three
/// different weights, and holding down a button to answer a friend is absurd.
///
///   low      → tap. Your own calendar, reversible, private.
///   notable  → tap, with the consequence named. Reaches a real person.
///   high     → press and hold. Spends money.
enum Stakes { case low, notable, high }

/// Everything Iris did before it asked. Kept OFF the card and behind one
/// control: a card is a decision, and the working out belongs where you can go
/// looking for it rather than in front of the thing you are deciding.
struct ThinkingTrace: Equatable {
    struct Source: Equatable, Identifiable {
        let id = UUID()
        let logo: IrisLogo
        let title: String
        let origin: String
    }
    let looked: [String]
    let sources: [Source]
    /// Why this is being asked rather than just done.
    let judgment: String
    /// What Iris considered and dropped. A trace that only lists what survived
    /// reads as a summary; the discarded options are what make it reasoning.
    let ruledOut: [String]
}

/// A thing already in motion. Their repo has this shape behind an unshipped
/// CARD_GRAMMAR flag (T2, the live tracker) and it never got turned on — the
/// feed can only ever ask, so there is nowhere to watch what you already said
/// yes to. This is that card.
/// The object being proposed: a slot, a table, a seat.
struct DeckTicket: Equatable {
    let eyebrow: String
    let headline: String
    let lines: [String]
}

struct DeckTracker: Equatable {
    let headline: String
    let detail: String
    /// 0...1 along the run.
    let progress: Double
    let glyph: String
    let courierAsset: String?
    let items: [String]
}

struct DeckWindow: Equatable {
    let day: String
    let start: Double
    let end: Double
    let openFrom: Double
    let openTo: Double
}

struct DeckRule: Identifiable, Equatable {
    let id = UUID()
    let sentence: String
    let scope: String
    let logo: IrisLogo
    var uses: Int
    /// The approvals this rule was learned from — shown when the row is opened,
    /// so a standing permission can always be traced back to what you allowed.
    var trail: [String] = []
}

// MARK: Engine

@MainActor @Observable
final class DecisionEngine {
    static let shared = DecisionEngine()

    var items: [DeckItem] = []
    var rules: [DeckRule] = [
        DeckRule(sentence: "Keep travel plans current", scope: "Calendar", logo: .calendar, uses: 7,
                 trail: ["JUN 3 · you moved a Delta alarm yourself",
                         "JUN 19 · you approved a gate change",
                         "AUG 2 · you approved 3 in a row, so Iris asked to stop asking"]),
        DeckRule(sentence: "Move gym bookings when classes clash", scope: "Calendar", logo: .calendar, uses: 4,
                 trail: ["JUL 8 · you rebooked Tuesday spin",
                         "JUL 22 · you approved the same move twice in a week"]),
        DeckRule(sentence: "File receipts into Notion", scope: "Mail", logo: .mail, uses: 12,
                 trail: ["MAY 14 · you filed 6 receipts by hand",
                         "MAY 30 · you approved filing without opening the mail"]),
    ]
    var judgmentShown = false
    /// Which card the deck is resting on. The composer reads it so one input
    /// can edit whatever you are looking at.
    var focusedID: UUID?
    private var graduated = false

    // Haptic pulses. Views subscribe with .sensoryFeedback on these counters;
    // the engine bumps them at the moments that should be felt.
    var stepPulse = 0
    var donePulse = 0
    var declinePulse = 0
    var failPulse = 0

    /// A card that just finished stays in the deck until its receipt has had
    /// a beat on screen. Filing it instantly meant the result of approving was
    /// something you only ever saw somewhere else.
    var asks: [DeckItem] {
        items.filter { $0.phase == .asking || $0.phase == .failed || isRunning($0)
            || ($0.phase == .done && !$0.filed) }
    }
    var handled: [DeckItem] { items.filter { $0.phase == .done && $0.filed } }
    private func isRunning(_ item: DeckItem) -> Bool {
        if case .running = item.phase { true } else { false }
    }

    func seed() {
        guard items.isEmpty else { return }
        items = [
            DeckItem(
                kind: "send_draft", source: "MAYA CHEN · MESSAGES", logo: .messages,
                avatarAsset: "AvatarSarah",
                ask: "Tell Maya you're in for Saturday?",
                context: "",
                incoming: "we still on for saturday? need to give them a headcount tonight",
                triggerLabel: "MAYA TEXTED", responseLabel: "IRIS WROTE",
                replyStyle: .imessage, stakes: .notable,
                consequence: "Sends from your number, as you.",
                trace: ThinkingTrace(
                    looked: ["maya chen · messages",
                             "your saturday",
                             "how you answer maya"],
                    sources: [
                        .init(logo: .messages, title: "Asked twice in 20 minutes", origin: "urgency"),
                        .init(logo: .calendar, title: "Saturday is clear", origin: "no conflicts"),
                        .init(logo: .messages, title: "You reply to Maya in one line", origin: "tone"),
                    ],
                    judgment: "Sending as you to a person is always worth one tap.",
                    ruledOut: ["Waiting until tonight. She needs the headcount by then",
                               "A longer reply. You answer Maya in one line",
                               "Declining. Your Saturday is clear"]),
                draft: "Yes, count me in for Saturday.",
                primaryLabel: "Send it",
                declineLabel: "Don't send",
                alwaysSentence: "Always send plan replies to Maya",
                steps: [
                    DeckRunStep(logo: .messages, text: "Sending as you", detail: "to Maya Chen"),
                    DeckRunStep(logo: .check, text: "Delivered", detail: "read 9:58 PM"),
                ],
                receiptLine: "Told Maya you're in for Saturday.",
                trail: ["HER TEXT 20m", "SHE ASKED TWICE", "YOUR SATURDAY IS OPEN"],
                createdAgo: "20m"
            ),
            DeckItem(
                kind: "tracker", source: "DOORDASH", logo: .doordash,
                ask: "Lunch is on the way.",
                context: "",
                tracker: DeckTracker(
                    headline: "Arrives in 12 min",
                    detail: "Marufuku · 2 items · Dmitri is 4 stops away",
                    progress: 0.68,
                    glyph: "bag.fill",
                    courierAsset: "AvatarJason",
                    items: ["1 × Tonkotsu ramen", "1 × Karaage", "2 × Green tea"]),
                createdAgo: "6m"
            ),
            DeckItem(
                kind: "send_draft", source: "SARAH WHITFIELD · MAIL", logo: .mail,
                avatarAsset: "AvatarSarah",
                ask: "Confirm Thursday with Sarah?",
                context: "",
                incoming: "Does Thursday still work for the walkthrough? I have to book the room today.",
                triggerLabel: "SARAH ASKED", responseLabel: "IRIS WROTE",
                replyStyle: .mail, stakes: .notable,
                consequence: "Sends from your address, as you.",
                trace: ThinkingTrace(
                    looked: ["sarah whitfield · recent thread",
                             "your calendar · thursday",
                             "your sent mail · tone match"],
                    sources: [
                        .init(logo: .mail, title: "Re: Thursday walkthrough", origin: "3 messages"),
                        .init(logo: .calendar, title: "Thursday 2:00–3:00 PM", origin: "free"),
                        .init(logo: .mail, title: "Your last 40 replies to Sarah", origin: "tone"),
                    ],
                    judgment: "No standing rule covers replying to Sarah, so this one is yours.",
                    ruledOut: ["Friday. She is out of office",
                               "Answering without the room booked. She asked for both",
                               "Sending it silently. You have never let Iris write to Sarah"]),
                draft: "Thursday still works. 2pm at your office? I'll bring the printed boards.",
                primaryLabel: "Send reply",
                declineLabel: "Don't send",
                alwaysSentence: "Always send scheduling replies to Sarah",
                steps: [
                    DeckRunStep(logo: .mail, text: "Opening the thread", detail: "Re: Thursday walkthrough"),
                    DeckRunStep(logo: .mail, text: "Sending as you", detail: "to sarah@northwind.example"),
                    DeckRunStep(logo: .check, text: "Sent", detail: "delivered 2:41 PM"),
                ],
                receiptLine: "Replied to Sarah. Thursday 2 PM confirmed.",
                trail: ["HER MAIL 1h", "YOUR LAST 40 REPLIES", "THU 2PM OPEN"],
                createdAgo: "1h"
            ),
            DeckItem(
                kind: "create_meeting", source: "JASON MEHTA · MAIL", logo: .calendar,
                avatarAsset: "AvatarJason",
                ask: "Book 30 minutes with Jason?",
                context: "",
                incoming: "Can I get 30 minutes this week to go over the firmware timeline?",
                triggerLabel: "JASON ASKED", responseLabel: "IRIS FOUND",
                trace: ThinkingTrace(
                    looked: ["jason mehta · recent thread",
                             "both calendars · this week",
                             "your meeting length habits"],
                    sources: [
                        .init(logo: .mail, title: "Firmware timeline", origin: "3 messages"),
                        .init(logo: .calendar, title: "Wed 3:30–4:00 PM", origin: "only shared slot"),
                        .init(logo: .calendar, title: "You default to 30 minutes", origin: "42 meetings"),
                    ],
                    judgment: "Booking time with someone new is not covered by a rule yet.",
                    ruledOut: ["Tuesday 2:00. You hold that for deep work",
                               "60 minutes. Your last 42 meetings were 30",
                               "Thursday. Sarah already has that slot pending"]),
                ticket: DeckTicket(eyebrow: "WEDNESDAY",
                                   headline: "3:30 – 4:00 PM",
                                   lines: ["30 min", "invite to Jason", "no conflicts"]),
                primaryLabel: "Book 3:30",
                declineLabel: "Don't book",
                alwaysSentence: "Always book time with anyone when I'm free",
                steps: [
                    DeckRunStep(logo: .calendar, text: "Holding Wed 3:30", detail: "no conflicts · 30 min"),
                    DeckRunStep(logo: .mail, text: "Inviting Jason", detail: "jason@northwind.example"),
                    DeckRunStep(logo: .check, text: "On the calendar", detail: "invite accepted pending"),
                ],
                receiptLine: "Jason booked Wednesday 3:30, invite sent.",
                trail: ["HIS MAIL 3h", "3 MESSAGES READ", "ONLY SLOT YOU BOTH HAVE"],
                createdAgo: "3h"
            ),
            DeckItem(
                kind: "place", source: "RESY", logo: .resy,
                ask: "Book Marufuku tonight?",
                context: "",
                incoming: "book dinner tonight if marufuku has anything",
                triggerLabel: "YOU ASKED", responseLabel: "IRIS FOUND",
                stakes: .high,
                consequence: "Charges $40 to your Visa ending 4412.",
                failsOnce: true,
                failureLine: "resy declined the hold · card not on file",
                trace: ThinkingTrace(
                    looked: ["resy · marufuku tonight",
                             "your saved places",
                             "your usual dinner time"],
                    sources: [
                        .init(logo: .resy, title: "7:45 PM · 2 counter seats", origin: "last under 8"),
                        .init(logo: .resy, title: "Saved by you Mar 2", origin: "saved"),
                        .init(logo: .calendar, title: "Nothing after 6 PM", origin: "free"),
                    ],
                    judgment: "You asked for this in chat, so it is a confirmation, not a suggestion.",
                    ruledOut: ["9:15 PM. Later than you have ever booked",
                               "Sushi Kashiba. You have not saved it",
                               "Booking silently. It charges a deposit"]),
                ticket: DeckTicket(eyebrow: "TONIGHT · MARUFUKU",
                                   headline: "7:45 PM",
                                   lines: ["2 seats", "counter", "$40 hold"]),
                primaryLabel: "Book it",
                declineLabel: "Don't book",
                alwaysSentence: "Always book tables at Marufuku",
                steps: [
                    DeckRunStep(logo: .resy, text: "Taking the 7:45", detail: "Marufuku · 2 seats · counter"),
                    DeckRunStep(logo: .wallet, text: "Authorising $40", detail: "Visa · 4412"),
                    DeckRunStep(logo: .check, text: "Booked", detail: "conf #R-2847 · in Mail"),
                ],
                receiptLine: "Marufuku tonight, 7:45. $40 held.",
                trail: ["SAVED BY YOU MAR 2", "YOU ASKED IN CHAT 4h", "LAST TABLE UNDER 8PM"],
                createdAgo: "4h"
            ),
            DeckItem(
                kind: "update", source: "DELTA 1187", logo: .delta,
                ask: "Move your Austin flight alarm?",
                context: "",
                facts: "SFO → AUS · 9:05 AM · MOVED UP 40 MIN",
                incoming: "Your flight is now departing 40 minutes earlier.",
                triggerLabel: "DELTA SAID", responseLabel: "IRIS UPDATED",
                primaryLabel: "Update calendar",
                declineLabel: "Leave it",
                alwaysSentence: "Always move my calendar for any airline",
                steps: [DeckRunStep(logo: .calendar, text: "Calendar moved to 9:05", detail: "DL 1187 · gate C11")],
                receiptLine: "Austin flight moved to 9:05 AM.",
                ranUnderRule: "Keep travel plans current",
                trail: ["DELTA PUSH 6h", "MATCHED YOUR CALENDAR", "RAN UNDER A RULE"],
                createdAgo: "6h", phase: .done, filed: true
            ),
            DeckItem(
                kind: "code", source: "GITHUB", logo: .github,
                ask: "", context: "Tap to copy",
                trail: ["GITHUB SIGN-IN 1m", "SAME DEVICE AS ALWAYS"],
                createdAgo: "1m", code: "481 902",
                codeDeadline: Date().addingTimeInterval(9 * 60)
            ),
        ]
    }

    func approve(_ item: DeckItem, always: Bool) {
        if always, let sentence = item.alwaysSentence,
           !rules.contains(where: { $0.sentence == sentence }) {
            rules.insert(DeckRule(sentence: sentence, scope: scope(for: item.kind), logo: item.logo, uses: 1,
                                  trail: ["JUST NOW · you approved \"\(item.ask)\" and chose always"]), at: 0)
        }
        run(item)
        if always, item.kind == "send_draft" { graduate() }
    }

    /// Retry clears the seeded failure, so the second attempt actually lands.
    func retry(_ item: DeckItem) {
        item.failed = false
        run(item)
    }

    func decline(_ item: DeckItem) {
        declinePulse += 1
        withAnimation(.smooth(duration: 0.3)) { item.phase = .dismissed }
        Task { try? await Task.sleep(for: .milliseconds(320))
               items.removeAll { $0.id == item.id && $0.phase == .dismissed } }
    }

    func undo(_ item: DeckItem) {
        withAnimation(.snappy(duration: 0.28)) {
            item.ranUnderRule = nil
            item.phase = .asking
        }
    }

    private func run(_ item: DeckItem) {
        guard !item.steps.isEmpty else { item.phase = .done; return }
        item.phase = .running(0)
        Task {
            for index in item.steps.indices {
                withAnimation(.snappy(duration: 0.24)) { item.phase = .running(index) }
                stepPulse += 1
                // The seeded failure lands on the last step, where a real one
                // usually does: everything worked until the thing that mattered.
                if item.failsOnce, item.failed, index == item.steps.count - 1 {
                    try? await Task.sleep(for: .milliseconds(700))
                    failPulse += 1
                    withAnimation(.smooth(duration: 0.32)) { item.phase = .failed }
                    return
                }
                // The last step lingers: the artifact line (the conf number,
                // the delivery time) is the receipt being minted, and it
                // deserves a beat before the card files itself.
                try? await Task.sleep(for: .milliseconds(index == item.steps.indices.last ? 1150 : 560))
            }
            donePulse += 1
            withAnimation(.smooth(duration: 0.4)) { item.phase = .done }
            // The receipt gets its own beat in the card before the card goes.
            try? await Task.sleep(for: .milliseconds(2400))
            withAnimation(.smooth(duration: 0.45)) { item.filed = true }
        }
    }

    private func graduate() {
        guard !graduated else { return }
        graduated = true
        Task {
            try? await Task.sleep(for: .seconds(7))
            if let index = rules.firstIndex(where: { $0.sentence == "Always send routine replies as you" }) {
                rules[index].uses += 1
            }
            let born = DeckItem(
                kind: "send_draft", source: "PRIYA NAIR · MAIL", logo: .mail,
                ask: "Reply to Priya about the deck?",
                context: "She asked for the three changed slides.",
                draft: "Attached — the three slides that changed since last quarter.",
                primaryLabel: "Send reply",
                steps: [DeckRunStep(logo: .mail, text: "Sent as you", detail: "3 slides attached")],
                receiptLine: "Sent Priya the three changed slides.",
                ranUnderRule: "Always send routine replies as you",
                createdAgo: "now", phase: .done
            )
            donePulse += 1
            withAnimation(.smooth(duration: 0.45)) { items.insert(born, at: 0) }
        }
    }

    func deleteRule(_ rule: DeckRule) {
        rules.removeAll { $0.id == rule.id }
        for item in items where item.ranUnderRule == rule.sentence {
            undo(item)
        }
    }

    private func scope(for kind: String) -> String {
        switch kind {
        case "send_draft": "Mail"
        case "create_meeting": "Calendar"
        case "place": "Reservations"
        default: "General"
        }
    }
}

// MARK: - The screen

enum DeckMode: String, CaseIterable {
    case feed = "Card feed"
    case brief = "Briefing"
}

struct DeckScreen: View {
    private let engine = DecisionEngine.shared
    @State private var mode: DeckMode = .feed
    @State private var focused: String?

    /// True while the deck is resting on the opening card — the only moment
    /// the greeting has room to exist.
    private var atFirstCard: Bool {
        focused == nil || focused == engine.asks.first?.id.uuidString
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The greeting IS the header clearance now. It used to ride inside
            // the first card's snap slot, below 64pt of dead space, which left
            // it stranded in the middle of the screen with nothing above it.
            // Pinned here it sits directly under the chrome, and card one rises
            // into the space it vacated — while every later card, whose rest
            // position is set by the pager's own insets, stays exactly put.
            switch mode {
            case .feed:
                // The greeting OVERLAYS the pager's top inset rather than
                // sitting above it. That band is empty while card one is
                // focused — nothing can peek above the first card — so the
                // greeting can own it, which puts it under the chrome and
                // card one directly beneath it. From card two on, the band is
                // the previous card's tail, so the greeting gets out of the
                // way rather than printing over it.
                ZStack(alignment: .top) {
                    pager
                    greetingRow
                        // The header's gutter, so "Welcome back" starts exactly
                        // where the avatar does and the mode chip ends exactly
                        // where the page toggle does.
                        .padding(.horizontal, DS.Spacing.gutter)
                        .padding(.top, 72)
                        .opacity(atFirstCard ? 1 : 0)
                        .animation(.smooth(duration: 0.22), value: atFirstCard)
                        .allowsHitTesting(atFirstCard)
                }
            case .brief:
                // Brief has no pager inset to hide under, so it carries the
                // header clearance itself.
                BriefView(engine: engine,
                          header: AnyView(greetingRow
                              .padding(.horizontal, DS.Spacing.gutter)
                              .padding(.top, 72)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        .onAppear { engine.seed() }
        // The moments that should be felt, not just seen.
        .sensoryFeedback(.selection, trigger: focused)
        .onChange(of: focused) { _, id in
            engine.focusedID = engine.asks.first { $0.id.uuidString == id }?.id
        }
        .sensoryFeedback(.impact(weight: .light), trigger: engine.stepPulse)
        .sensoryFeedback(.success, trigger: engine.donePulse)
        .sensoryFeedback(.warning, trigger: engine.declinePulse)
        .sensoryFeedback(.selection, trigger: mode)
    }

    private var greetingRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Welcome back, Shaurya.")
                .font(.system(size: 28, weight: .thin))
                .tracking(-0.2)
                .foregroundStyle(DS.Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            modeSwitch
        }
        .padding(.bottom, 2)
    }

    private var modeSwitch: some View {
        Menu {
            ForEach(DeckMode.allCases, id: \.self) { candidate in
                Button {
                    withAnimation(.smooth(duration: 0.3)) { mode = candidate }
                } label: {
                    if candidate == mode {
                        Label(candidate.rawValue, systemImage: "checkmark")
                    } else {
                        Text(candidate.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(mode == .feed ? "FEED" : "BRIEF")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .kerning(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(DS.Palette.inkMuted)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .contentShape(Capsule())
        }
        .smallGlassCapsule()
    }

    // MARK: The pager

    private var pageIDs: [String] {
        engine.asks.map(\.id.uuidString) + ["handled"]
    }

    private var pager: some View {
        GeometryReader { geo in
            let height = geo.size.height
            // The focused card owns the screen; the neighbours split what is
            // left, so both are visibly there without competing for the eye.
            let slot = height * 0.66
            // The peek has to come from ANCHORING, not from insetting.
            // viewAligned snaps the focused card's TOP edge to the top content
            // inset, so an asymmetric top margin was dead space and the
            // previous card scrolled clean out of frame. Symmetric margins let
            // the first and last cards reach the same resting place; the
            // anchor decides what shows around the focused one.
            let margin = (height - slot) / 2

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(engine.asks) { item in
                        // The greeting shares the FIRST slot with the first
                        // card: one snap unit, so the opening swipe lands on
                        // card two, and only the first card has words instead
                        // of a previous card peeking above it.
                        Group {
                            if item.kind == "code" {
                                CodeCard(item: item)
                            } else if item.tracker != nil {
                                TrackerCard(item: item)
                            } else {
                                AskCard(item: item, engine: engine)
                            }
                        }
                        .frame(height: slot, alignment: .center)
                        .id(item.id.uuidString)
                        .scrollTransition(axis: .vertical) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.45)
                                .scaleEffect(phase.isIdentity ? 1 : 0.97)
                        }
                        .transition(.asymmetric(
                            insertion: .offset(y: 16).combined(with: .opacity),
                            removal: .offset(x: 140).combined(with: .opacity)))
                    }

                }
                .scrollTargetLayout()
                .padding(.horizontal, DK.gutter)
            }
            // Anchored just above centre: the card sits high enough to clear
            // the floating composer, and BOTH neighbours stay on screen —
            // the previous card's tail above, the next card's head below.
            .scrollPosition(id: $focused, anchor: UnitPoint(x: 0.5, y: 0.44))
            // One card per gesture, even on an over-scroll.
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .contentMargins(.vertical, margin, for: .scrollContent)
            .animation(.smooth(duration: 0.34), value: engine.asks.map(\.id))
        }
    }
}

// MARK: - Shared card chrome

/// The 1px rule that turns a dark rectangle into an instrument: full-bleed
/// inside the card, separating the strata — source, body, actions.
private struct LedgerLine: View {
    var body: some View {
        Rectangle().fill(DS.Palette.hairlineSoft).frame(height: 1)
    }
}

private struct DeckPlate<Content: View>: View {
    var emphasized = false

    /// Whether the plate stretches to its whole slot. Ask cards do not: a card
    /// padded out to a fixed height with nothing in the middle reads as a bug,
    /// not as breathing room. The code card does, because its one number is
    /// meant to be found in the centre of the screen.
    var fills = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity,
                   maxHeight: fills ? .infinity : nil,
                   alignment: .topLeading)
            // One surface: frosted dark glass over the canvas. No inner fills
            // anywhere — structure comes from the hairline strata, never from
            // patches of a second grey.
            // Glass, in layers: the app's colour washed across the top, a
            // frosted plate under it, and the black canvas showing through
            // both. A single flat fill is what made this read as grey card
            // stock instead of glass.
            // One surface for every card. Tinting each plate by its source app
            // turned the feed into a colour chart; the logo already says where
            // a card came from, and it says it more precisely.
            .background(
                LinearGradient(colors: [Color.white.opacity(0.055), Color.white.opacity(0.012), .clear],
                               startPoint: .top, endPoint: .bottom)
            )
            .background(DS.Palette.card.opacity(0.16))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: DK.cardRadius, style: .continuous))
            // The specular edge: light catches the top lip of real glass and
            // falls off before the bottom. Without it a frosted panel just
            // reads as flat grey.
            .overlay(
                RoundedRectangle(cornerRadius: DK.cardRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(emphasized ? 0.26 : 0.16),
                                     Color.white.opacity(0.06),
                                     Color.white.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
            )
            .overlay(RoundedRectangle(cornerRadius: DK.cardRadius, style: .continuous)
                .strokeBorder(emphasized ? DS.Palette.hairlineSoft : DS.Palette.hairlineSoft,
                              lineWidth: 0.5))
    }
}

private struct TrackerCard: View {
    let item: DeckItem

    var body: some View {
        DeckPlate(fills: true) {
            VStack(alignment: .leading, spacing: 0) {
                SourceRow(item: item)
                    .padding(.horizontal, DK.pad)
                    .frame(height: 48)

                if let tracker = item.tracker {
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer(minLength: 0)

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(tracker.headline)
                                    .font(.system(size: 30, weight: .semibold))
                                    .tracking(-0.6)
                                    .foregroundStyle(DS.Palette.ink)
                                Text(tracker.detail)
                                    .font(.system(size: 14))
                                    .foregroundStyle(DS.Palette.subtle)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            if let asset = tracker.courierAsset {
                                PersonaAsset.image(asset)
                                    .resizable().scaledToFill()
                                    .frame(width: 52, height: 52)
                                    .clipShape(Circle())
                                    .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 2))
                            }
                        }

                        RunTrack(progress: tracker.progress, glyph: tracker.glyph)
                            .padding(.top, 22)

                        Spacer(minLength: 20)

                        // The contents sit at the FOOT of the card on purpose:
                        // that band is what the next card sees of this one, and
                        // a peek of empty plate says nothing about what is in
                        // the bag.
                        if !tracker.items.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(Array(tracker.items.enumerated()), id: \.offset) { index, line in
                                    if index > 0 {
                                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                                    }
                                    HStack {
                                        Text(line)
                                            .font(.system(size: 13.5))
                                            .foregroundStyle(DS.Palette.subtle)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(height: 38)
                                    .padding(.horizontal, 14)
                                }
                            }
                            .background(.ultraThinMaterial,
                                        in: RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, DK.pad)
                    .padding(.bottom, DK.pad)
                    .frame(maxHeight: .infinity, alignment: .top)
                }

            }
        }
    }
}

/// The track. Filled behind, hairline ahead, the glyph riding the head of the
/// fill — so where it is reads without a single label.
private struct RunTrack: View {
    let progress: Double
    let glyph: String

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let head = max(min(progress, 1), 0) * (w - 34)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10)).frame(height: 4)
                Capsule().fill(DS.Palette.ink).frame(width: head + 17, height: 4)
                Circle()
                    .fill(DS.Palette.ink)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: glyph)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DS.Palette.onInk))
                    .offset(x: head)
                Circle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 7, height: 7)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: 34)
        }
        .frame(height: 34)
    }
}

/// The thing being proposed, and — the part that was missing — a thing you can
/// change. Tapping the time opens a wheel, the way tapping a time in Clock
/// does. Edit before approving cannot only mean editing a sentence.
private struct DetailTicket: View {
    let ticket: DeckTicket
    let item: DeckItem
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ticket.eyebrow)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .kerning(1.1)
                .foregroundStyle(DS.Palette.placeholder)

            Button {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) { editing.toggle() }
                _ = DSHaptics.tap(.light)
            } label: {
                HStack(spacing: 8) {
                    Text(item.ticketTime.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 30, weight: .light))
                        .tracking(-0.4)
                        .foregroundStyle(DS.Palette.ink)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Palette.placeholder)
                        .rotationEffect(.degrees(editing ? 180 : 0))
                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if editing {
                DatePicker("", selection: Binding(get: { item.ticketTime },
                                                  set: { item.ticketTime = $0 }),
                           displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .frame(height: 128)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }

            HStack(spacing: 7) {
                ForEach(Array(ticket.lines.enumerated()), id: \.offset) { index, line in
                    if index > 0 {
                        Circle().fill(DS.Palette.placeholder.opacity(0.5))
                            .frame(width: 2.5, height: 2.5)
                    }
                    Text(line)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(DS.Palette.subtle)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous))
        .background(Color.white.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.04)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1))
    }
}

/// A thread, drawn the way Messages draws one: theirs grey on the left, yours
/// blue on the right, both hugging their own text. Yours is the live field —
/// tap anywhere in the blue and the caret is there.
private struct MessageThread: View {
    let incoming: String
    @Binding var draft: String
    var focused: FocusState<Bool>.Binding
    let editable: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(incoming)
                    .font(.system(size: 16.5))
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(white: 0.24),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                // A bubble that stretches the full width is not a bubble.
                Spacer(minLength: 44)
            }

            HStack {
                Spacer(minLength: 44)
                Group {
                    if editable {
                        TextField("", text: $draft, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1 ... 5)
                            .multilineTextAlignment(.trailing)
                            .focused(focused)
                            .tint(.white)
                    } else {
                        Text(draft)
                    }
                }
                .font(.system(size: 16.5))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(colors: [Color(red: 0.16, green: 0.53, blue: 1),
                                            Color(red: 0.05, green: 0.40, blue: 0.96)],
                                   startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }
}

/// Mail has no bubble geometry, so it gets Mail's: a header that says who it
/// is going to and what it is answering, a rule, then the body you can type in.
private struct MailReply: View {
    let to: String
    let incoming: String
    @Binding var draft: String
    var focused: FocusState<Bool>.Binding
    let editable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("TO")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(DS.Palette.placeholder)
                    .frame(width: 26, alignment: .leading)
                Text(to)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Palette.inkMuted)
                Spacer(minLength: 0)
            }
            .frame(height: 26)

            HStack(alignment: .top, spacing: 8) {
                Text("RE")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(DS.Palette.placeholder)
                    .frame(width: 26, alignment: .leading)
                    .padding(.top, 3)
                Text(incoming)
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(DS.Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.bottom, 12)

            Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1)

            Group {
                if editable {
                    TextField("", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1 ... 6)
                        .focused(focused)
                        .tint(DS.Palette.ink)
                } else {
                    Text(draft)
                }
            }
            .font(.system(size: 17))
            .foregroundStyle(DS.Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)
        }
    }
}

/// A named block of the card:/// A named block of the card:/// A named block of the card: two mono words, then the thing itself.
private struct Stratum<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .kerning(1.1)
                    .foregroundStyle(DS.Palette.placeholder)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What approving will actually do, before you approve it. The same steps the
/// run rail plays back, shown up front so the button is never a leap.
private struct StepPreview: View {
    let steps: [DeckRunStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(steps) { step in
                HStack(spacing: 8) {
                    IrisLogoTile(logo: step.logo, size: 16)
                    Text(step.text)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(DS.Palette.subtle)
                    if let detail = step.detail {
                        Text(detail)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(DS.Palette.placeholder)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// The window, drawn. A hairline rule spanning the open hours, the proposed
/// block struck solid across it, the edges labelled. No sentence needed.
private struct WindowRuler: View {
    let window: DeckWindow

    private var span: Double { max(window.openTo - window.openFrom, 0.001) }
    private var startFraction: Double { (window.start - window.openFrom) / span }
    private var widthFraction: Double { (window.end - window.start) / span }

    private func label(_ hour: Double) -> String {
        let h = Int(hour) % 12 == 0 ? 12 : Int(hour) % 12
        let m = Int((hour - Double(Int(hour))) * 60)
        return m == 0 ? "\(h)" : String(format: "%d:%02d", h, m)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(window.day)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .kerning(1.1)
                .foregroundStyle(DS.Palette.placeholder)

            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    // The open span, ticked at each hour.
                    HStack(spacing: 0) {
                        ForEach(0 ..< Int(span), id: \.self) { _ in
                            Rectangle()
                                .fill(DS.Palette.hairline)
                                .frame(width: 1, height: 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(height: 6)
                    .frame(maxHeight: .infinity, alignment: .center)

                    Rectangle()
                        .fill(DS.Palette.hairlineSoft)
                        .frame(height: 1)

                    // The block itself.
                    Rectangle()
                        .fill(DS.Palette.ink)
                        .frame(width: max(w * widthFraction, 3), height: 3)
                        .offset(x: w * startFraction)
                }
                .frame(height: 14)
            }
            .frame(height: 14)

            HStack {
                Text(label(window.openFrom))
                Spacer()
                Text("\(label(window.start))–\(label(window.end))")
                    .foregroundStyle(DS.Palette.inkMuted)
                Spacer()
                Text(label(window.openTo))
            }
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .foregroundStyle(DS.Palette.placeholder)
        }
    }
}

/// The provenance line: what Iris saw, in order, to arrive at this ask.
/// Mono, tracked, separated by hairline ticks — a readout, not a sentence.
private struct TrailLine: View {
    let steps: [String]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Rectangle()
                        .fill(DS.Palette.hairline)
                        .frame(width: 1, height: 8)
                }
                Text(step)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .kerning(0.5)
                    .foregroundStyle(DS.Palette.placeholder)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct SourceRow: View {
    let item: DeckItem

    var body: some View {
        HStack(spacing: 8) {
            if let asset = item.avatarAsset {
                PersonaAsset.image(asset)
                    .resizable().scaledToFill()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        IrisLogoTile(logo: item.logo, size: 12)
                            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(DS.Palette.card, lineWidth: 1.5))
                            .offset(x: 4, y: 4)
                    }
            } else {
                IrisLogoTile(logo: item.logo, size: 24)
            }
            Text(item.source)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .kerning(0.8)
                .foregroundStyle(DS.Palette.subtle)
            Spacer()
            Text(item.createdAgo)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(DS.Palette.placeholder)
        }
    }
}

// MARK: - ASK

private struct AskCard: View {
    @Bindable var item: DeckItem
    let engine: DecisionEngine
    @State private var alwaysOpen = false
    @State private var traceShown = false
    /// "Sarah Whitfield · Mail" is a database row; "Sarah" is who you are
    /// writing to.
    private var firstName: String {
        item.source.split(separator: "·").first?
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ").first
            .map { $0.capitalized } ?? ""
    }

    @FocusState private var draftFocused: Bool

    private var running: Bool { if case .running = item.phase { true } else { false } }

    var body: some View {
        DeckPlate(emphasized: true, fills: true) {
            VStack(alignment: .leading, spacing: 0) {
                SourceRow(item: item)
                    .padding(.horizontal, DK.pad)
                    .frame(height: 48)

                // Cause, then response, then how it runs — each named in two
                // words, each given its own share of the card. The blocks are
                // separated by Spacers rather than a fixed gap so they use the
                // whole plate instead of stacking at the top.
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.ask)
                        .font(.system(size: 33, weight: .light))
                        .tracking(-0.5)
                        .foregroundStyle(DS.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if !item.context.isEmpty {
                        Text(item.context)
                            .font(.system(size: 16.5, weight: .light))
                            .foregroundStyle(DS.Palette.subtle)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                    }

                    if item.trace != nil, item.phase == .asking {
                        Button { traceShown = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("How Iris got here")
                                    .font(.system(size: 12, weight: .medium))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundStyle(DS.Palette.subtle)
                            .padding(.horizontal, 11)
                            .frame(height: 30)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 14)
                    }

                    // Each app's reply is drawn the way that app draws it.
                    // A thread is grey-left / blue-right with bubbles that hug
                    // their text — that geometry IS how you read who said what,
                    // so the SARAH ASKED / IRIS WROTE labels are redundant there.
                    // Mail has no shape of its own, so it keeps a header.
                    if let incoming = item.incoming, item.replyStyle == .imessage {
                        Spacer(minLength: 14)
                        MessageThread(incoming: incoming,
                                      draft: Binding(get: { item.draft ?? "" },
                                                     set: { item.draft = $0 }),
                                      focused: $draftFocused,
                                      editable: !running)
                    } else if let incoming = item.incoming, item.replyStyle == .mail {
                        Spacer(minLength: 14)
                        MailReply(to: firstName,
                                  incoming: incoming,
                                  draft: Binding(get: { item.draft ?? "" },
                                                 set: { item.draft = $0 }),
                                  focused: $draftFocused,
                                  editable: !running)
                    } else {
                        if let incoming = item.incoming {
                            Spacer(minLength: 16)
                            Stratum(label: item.triggerLabel) {
                                Text(incoming)
                                    .font(.system(size: 17, weight: .light))
                                    .foregroundStyle(DS.Palette.subtle)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 16)
                        if let ticket = item.ticket {
                            DetailTicket(ticket: ticket, item: item)
                        } else if let facts = item.facts {
                            Stratum(label: item.responseLabel) {
                                Text(facts)
                                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                    .kerning(0.6)
                                    .foregroundStyle(DS.Palette.inkMuted)
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(DK.pad)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if let sentence = item.alwaysSentence, item.phase == .asking {
                    alwaysMenu(sentence)
                        .padding(.horizontal, DK.pad)
                        .padding(.bottom, 12)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.86, anchor: .bottomTrailing)
                                .combined(with: .opacity)
                                .combined(with: .offset(y: 10)),
                            removal: .scale(scale: 0.94, anchor: .bottomTrailing)
                                .combined(with: .opacity)))
                }

                Group {
                    if running { runRail }
                    else if item.phase == .failed { failedRow }
                    else if item.phase == .done { doneRow }
                    else { actionRow }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.74), value: alwaysOpen)
        .animation(.snappy(duration: 0.26), value: running)
        .sheet(isPresented: $traceShown) {
            if let trace = item.trace {
                ThinkingSheet(item: item, trace: trace)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
            }
        }
    }

    /// The draft is not a box inside the card — it IS the card's own words.
    /// One tap puts the caret in it; there is no edit mode to enter, no second
    /// surface, no border drawn around your own sentence.
    private var draftWell: some View {
        TextField("", text: Binding(get: { item.draft ?? "" }, set: { item.draft = $0 }),
                  axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1 ... 5)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(item.replyStyle == .imessage ? Color.white : DS.Palette.ink)
            .tint(item.replyStyle == .imessage ? Color.white : DS.Palette.ink)
            .focused($draftFocused)
            .submitLabel(.done)
    }

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let consequence = item.consequence {
                HStack(spacing: 7) {
                    Image(systemName: item.stakes == .high ? "creditcard.fill" : "person.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text(consequence)
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundStyle(DS.Palette.subtle)
                .padding(.horizontal, 6)
            }
            if item.stakes == .high {
                highStakesRow
            } else {
                lowStakesRow
            }
        }
    }

    /// Something that reaches a person or a card. The consequence is named,
    /// and the only way through is a deliberate gesture — you cannot send this
    /// by brushing the screen in your pocket.
    private var highStakesRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { engine.decline(item) } label: {
                    Text(item.declineLabel)
                        .font(.system(size: 15.5, weight: .regular))
                        .foregroundStyle(DS.Palette.inkMuted)
                        .frame(height: 54)
                        .padding(.horizontal, 16)
                        .background(.ultraThinMaterial,
                                    in: RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                }
                .buttonStyle(.plain)

                HoldToApprove(label: item.primaryLabel) {
                    alwaysOpen = false
                    engine.approve(item, always: false)
                }
            }
        }
    }

    private var lowStakesRow: some View {
        HStack(spacing: 8) {
            Button { engine.decline(item) } label: {
                Text(item.declineLabel)
                    .font(.system(size: 15.5))
                    .foregroundStyle(DS.Palette.inkMuted)
                    .frame(height: 54)
                    .padding(.horizontal, 18)
                    .background(.ultraThinMaterial,
                                in: RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button {
                engine.approve(item, always: alwaysOpen)
            } label: {
                Text(alwaysOpen ? "\(item.primaryLabel), always" : item.primaryLabel)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(DS.Palette.onInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        LinearGradient(colors: [Color.white, Color(white: 0.88)],
                                       startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous))
                    .contentTransition(.opacity)
            }
            .buttonStyle(.plain)
        }
    }

    /// The standing rule is a decision you make BEFORE approving, so it is a
    /// switch above the button rather than a second button beside it — and the
    /// button then says what it is about to do: "Send it, always".
    private func alwaysMenu(_ sentence: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) { alwaysOpen.toggle() }
            _ = DSHaptics.tap(.light)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: alwaysOpen ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(alwaysOpen ? DS.Palette.ink : DS.Palette.placeholder)
                Text(sentence)
                    .font(.system(size: 13.5, weight: alwaysOpen ? .medium : .regular))
                    .foregroundStyle(alwaysOpen ? DS.Palette.ink : DS.Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(alwaysOpen ? 0.22 : 0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// It did not work. The rail stops where it stopped, the reason is plain,
    /// and the way forward is one control — not a dead end and not a toast
    /// that disappears before it is read.
    private var failedRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(DS.Palette.danger)
            VStack(alignment: .leading, spacing: 1) {
                Text("Didn't go through")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DS.Palette.ink)
                if let line = item.failureLine {
                    Text(line)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(DS.Palette.placeholder)
                }
            }
            Spacer(minLength: 8)
            Button { engine.retry(item) } label: {
                Text("Try again")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Palette.onInk)
                    .padding(.horizontal, 15)
                    .frame(height: 38)
                    .background(DS.Palette.ink,
                                in: RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 46)
        .transition(.opacity)
    }

    /// The result, in the card that asked for it.
    private var doneRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.black, DS.Palette.success)
            Text(item.receiptLine)
                .font(.system(size: 15.5, weight: .medium))
                .foregroundStyle(DS.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button { engine.undo(item) } label: {
                Text("Undo")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Palette.subtle)
                    .underline()
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .frame(minHeight: 46)
    }

    private var runRail: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(item.steps.enumerated()), id: \.element.id) { index, step in
                let state: Int = {
                    if case let .running(current) = item.phase {
                        return index < current ? 2 : (index == current ? 1 : 0)
                    }
                    return 2
                }()
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    IrisLogoTile(logo: state == 2 ? .check : step.logo, size: 24)
                        .saturation(state == 0 ? 0 : 1)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(step.text)
                            .font(.system(size: 15.5, weight: .regular))
                            .foregroundStyle(state == 0 ? DS.Palette.placeholder : DS.Palette.inkMuted)
                        if state >= 1, let detail = step.detail {
                            Text(detail)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(DS.Palette.placeholder)
                                .transition(.opacity)
                        }
                    }
                    if state == 1 {
                        ProgressView().controlSize(.mini).tint(DS.Palette.subtle)
                    }
                }
                .opacity(state == 0 ? 0.45 : 1)
            }
        }
        .padding(.bottom, 4)
    }
}

// MARK: - UTILITY (the code)

private struct CodeCard: View {
    @Bindable var item: DeckItem

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let deadline = item.codeDeadline ?? now
            let left = max(0, deadline.timeIntervalSince(now))
            let total: TimeInterval = 10 * 60
            let expired = left <= 0

            Button {
                guard !expired else { return }
                UIPasteboard.general.string = item.code?.filter(\.isNumber)
                withAnimation(.snappy(duration: 0.22)) { item.copied = true }
                DecisionEngine.shared.donePulse += 1
                Task { try? await Task.sleep(for: .seconds(2))
                       withAnimation(.smooth(duration: 0.3)) { item.copied = false } }
            } label: {
                DeckPlate(fills: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        SourceRow(item: item)
                            .padding(.horizontal, DK.pad)
                            .frame(height: 44)
                        LedgerLine()
                        Spacer(minLength: 0)
                        Text(item.code ?? "")
                            .font(.system(size: 58, weight: .thin, design: .monospaced))
                            .kerning(3)
                            .foregroundStyle(expired ? DS.Palette.placeholder : DS.Palette.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, DK.pad)
                        Text(item.copied ? "COPIED" : (expired ? "EXPIRED" : "TAP TO COPY"))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .kerning(1.4)
                            .foregroundStyle(item.copied ? DS.Palette.success : DS.Palette.placeholder)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 10)
                        Spacer(minLength: 0)
                        LedgerLine()
                        VStack(alignment: .leading, spacing: 8) {
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(DS.Palette.track).frame(height: 2)
                                    Capsule().fill(expired ? DS.Palette.placeholder : DS.Palette.ink)
                                        .frame(width: proxy.size.width * (left / total), height: 2)
                                }
                            }
                            .frame(height: 2)
                            Text(expired ? "This code is dead." : "Expires in \(Int(left) / 60):\(String(format: "%02d", Int(left) % 60))")
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(DS.Palette.placeholder)
                        }
                        .padding(.horizontal, DK.pad)
                        .padding(.vertical, 12)
                    }
                }
            }
            .buttonStyle(.plain)
            .opacity(expired ? 0.55 : 1)
        }
    }
}

// MARK: - HANDLED (the last page of the stack)

private struct HandledPage: View {
    let engine: DecisionEngine

    var body: some View {
        DeckPlate(fills: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("HANDLED · \(engine.handled.count)")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .kerning(1.1)
                        .foregroundStyle(DS.Palette.placeholder)
                    Spacer()
                }

                if engine.handled.isEmpty {
                    Spacer()
                    Text("Nothing handled yet.")
                        .font(.system(size: 16))
                        .foregroundStyle(DS.Palette.subtle)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 8) {
                            ForEach(engine.handled) { item in
                                ReceiptRow(item: item, engine: engine)
                            }
                        }
                    }
                }

                Text("That is the stack. Nothing else needs you.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(DS.Palette.placeholder)
                    .frame(maxWidth: .infinity)
            }
            .padding(DK.pad)
        }
    }
}

private struct ReceiptRow: View {
    @Bindable var item: DeckItem
    let engine: DecisionEngine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // The app that actually did it, with a tick riding its corner.
            IrisLogoTile(logo: item.logo, size: 22)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DS.Palette.ink, DS.Palette.success)
                        .offset(x: 3, y: 3)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.receiptLine)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(DS.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if let rule = item.ranUnderRule {
                    Text("RULE · \(rule.uppercased())")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .kerning(0.7)
                        .foregroundStyle(DS.Palette.placeholder)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Button { engine.undo(item) } label: {
                Text("Undo")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Palette.subtle)
                    .underline()
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous)
            .strokeBorder(DS.Palette.hairlineSoft, lineWidth: 1))
    }
}

// MARK: - BRIEF (the composed view)

private struct BriefView: View {
    let engine: DecisionEngine
    var header: AnyView? = nil

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                if let header { header }
                if let code = engine.asks.first(where: { $0.kind == "code" }) {
                    CodeCard(item: code)
                        .frame(height: 210)
                }

                briefSection("TOP OF MIND") {
                    ForEach(engine.asks.filter { $0.kind != "code" }) { item in
                        BriefAskRow(item: item, engine: engine)
                    }
                }

                if !engine.handled.isEmpty {
                    briefSection("HANDLED") {
                        ForEach(engine.handled) { item in
                            ReceiptRow(item: item, engine: engine)
                        }
                    }
                }



                Spacer().frame(height: 120)
            }
            .padding(.horizontal, DK.gutter)
            .padding(.top, 10)
        }
    }

    private func briefSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .kerning(1.1)
                .foregroundStyle(DS.Palette.placeholder)
            content()
        }
    }
}

private struct BriefAskRow: View {
    @Bindable var item: DeckItem
    let engine: DecisionEngine

    private var running: Bool { if case .running = item.phase { true } else { false } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let asset = item.avatarAsset {
                    PersonaAsset.image(asset)
                        .resizable().scaledToFill()
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else {
                    IrisLogoTile(logo: item.logo, size: 26)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.ask)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(DS.Palette.ink)
                    Text(item.context)
                        .font(.system(size: 13.5))
                        .foregroundStyle(DS.Palette.subtle)
                }
                Spacer(minLength: 0)
            }

            if running {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini).tint(DS.Palette.subtle)
                    Text("Working…")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Palette.subtle)
                }
            } else {
                HStack(spacing: 8) {
                    Button { engine.decline(item) } label: {
                        Text(item.declineLabel)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(DS.Palette.inkMuted)
                            .frame(height: 36)
                            .padding(.horizontal, 12)
                            .background(Color.white.opacity(0.05),
                                        in: RoundedRectangle(cornerRadius: DK.chipRadius + 1, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: DK.chipRadius + 1, style: .continuous)
                                .strokeBorder(DS.Palette.hairlineSoft, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Button { engine.approve(item, always: false) } label: {
                        Text(item.primaryLabel)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(DS.Palette.onInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(DS.Palette.ink,
                                        in: RoundedRectangle(cornerRadius: DK.chipRadius + 1, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: DK.wellRadius + 2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DK.wellRadius + 2, style: .continuous)
            .strokeBorder(DS.Palette.hairlineSoft, lineWidth: 1))
    }
}

// MARK: - Judgment

struct JudgmentSheet: View {
    var engine: DecisionEngine = .shared
    @State private var opened: UUID?
    @State private var appeared = false

    var body: some View {
        SheetChrome(title: "Judgment") {
            VStack(alignment: .leading, spacing: 12) {
                Text("ACTS WITHOUT ASKING · \(engine.rules.count)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .kerning(1.1)
                    .foregroundStyle(DS.Palette.placeholder)
                    .padding(.leading, 2)
                    .padding(.bottom, 2)

                // Each rule is its own plate. They were rows in one container
                // divided by hairlines, which read as a settings list — but a
                // standing permission is an object you granted, and three of
                // them are three objects.
                ForEach(Array(engine.rules.enumerated()), id: \.element.id) { index, rule in
                    RuleRow(
                        rule: rule,
                        open: opened == rule.id,
                        onToggle: {
                            withAnimation(.snappy(duration: 0.26)) {
                                opened = opened == rule.id ? nil : rule.id
                            }
                            _ = DSHaptics.tap(.light)
                        },
                        onDelete: {
                            withAnimation(.snappy(duration: 0.28)) { engine.deleteRule(rule) }
                        }
                    )
                    // Staggered in, the way the trace sheet stages its steps.
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                    .animation(.smooth(duration: 0.34).delay(Double(index) * 0.05), value: appeared)
                }
            }
        }
        .task { appeared = true }
    }
}

/// One standing permission. Closed it is a sentence and nothing else; opened it
/// shows the approvals it was learned from, so no rule is ever a black box.
private struct RuleRow: View {
    let rule: DeckRule
    let open: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 13) {
                    IrisLogoTile(logo: rule.logo, size: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.sentence)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(DS.Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(rule.uses) TIMES")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .kerning(0.9)
                            .foregroundStyle(DS.Palette.placeholder)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Palette.placeholder)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)

                    Text("LEARNED FROM")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(DS.Palette.placeholder)
                        .padding(.top, 15)
                        .padding(.bottom, 10)

                    ForEach(Array(rule.trail.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .top, spacing: 11) {
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(DS.Palette.placeholder.opacity(0.7))
                                    .frame(width: 4, height: 4)
                                    .padding(.top, 6)
                                if index < rule.trail.count - 1 {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.09))
                                        .frame(width: 1)
                                        .frame(maxHeight: .infinity)
                                }
                            }
                            .frame(width: 4)
                            Text(line)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(DS.Palette.subtle)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, index < rule.trail.count - 1 ? 10 : 0)
                        }
                    }

                    Button(action: onDelete) {
                        HStack(spacing: 7) {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Ask me again")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(DS.Palette.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 15)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color.white.opacity(0.055), Color.white.opacity(0.012), .clear],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: DK.cardRadius, style: .continuous))
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: DK.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DK.cardRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(open ? 0.24 : 0.14),
                                            Color.white.opacity(0.04)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: DK.cardRadius, style: .continuous))
    }
}
