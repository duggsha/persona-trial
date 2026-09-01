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

private enum DK {
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
    enum Phase: Equatable { case asking, running(Int), done, dismissed }

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
    /// Set once the receipt has been read and the card has left the deck.
    var filed = false
    /// The window this card is about, drawn as a ruler rather than described.
    let window: DeckWindow?
    /// How this got here: the signals that produced the card, in order.
    /// Rendered as one dense mono line, not prose.
    let trail: [String]
    let createdAgo: String
    var code: String?
    var codeDeadline: Date?
    var copied = false
    var phase: Phase = .asking

    init(kind: String, source: String, logo: IrisLogo, avatarAsset: String? = nil,
         ask: String, context: String, facts: String? = nil,
         incoming: String? = nil, triggerLabel: String = "", responseLabel: String = "",
         replyStyle: ReplyStyle = .plain, window: DeckWindow? = nil,
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
        self.replyStyle = replyStyle
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
    private var graduated = false

    // Haptic pulses. Views subscribe with .sensoryFeedback on these counters;
    // the engine bumps them at the moments that should be felt.
    var stepPulse = 0
    var donePulse = 0
    var declinePulse = 0

    /// A card that just finished stays in the deck until its receipt has had
    /// a beat on screen. Filing it instantly meant the result of approving was
    /// something you only ever saw somewhere else.
    var asks: [DeckItem] { items.filter { $0.phase == .asking || isRunning($0) || ($0.phase == .done && !$0.filed) } }
    var handled: [DeckItem] { items.filter { $0.phase == .done && $0.filed } }
    private func isRunning(_ item: DeckItem) -> Bool {
        if case .running = item.phase { true } else { false }
    }

    func seed() {
        guard items.isEmpty else { return }
        items = [
            DeckItem(
                kind: "code", source: "GITHUB", logo: .github,
                ask: "", context: "Tap to copy",
                trail: ["GITHUB SIGN-IN 1m", "SAME DEVICE AS ALWAYS"],
                createdAgo: "1m", code: "481 902",
                codeDeadline: Date().addingTimeInterval(9 * 60)
            ),
            DeckItem(
                kind: "send_draft", source: "SARAH WHITFIELD · MAIL", logo: .mail,
                avatarAsset: "AvatarSarah",
                ask: "Confirm Thursday with Sarah?",
                context: "",
                incoming: "Does Thursday still work for the walkthrough? I have to book the room today.",
                triggerLabel: "SARAH ASKED", responseLabel: "IRIS WROTE",
                replyStyle: .mail,
                draft: "Thursday still works. 2pm at your office? I'll bring the printed boards.",
                primaryLabel: "Send reply",
                alwaysSentence: "Always reply to Sarah about scheduling",
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
                ask: "Give Jason 30 minutes Wednesday?",
                context: "",
                facts: "WED · 3:30 – 4:00 PM · INVITE TO JASON",
                incoming: "Can I get 30 minutes this week to go over the firmware timeline?",
                triggerLabel: "JASON ASKED", responseLabel: "IRIS FOUND",
                window: DeckWindow(day: "WEDNESDAY", start: 15.5, end: 16, openFrom: 9, openTo: 18),
                primaryLabel: "Book 3:30",
                alwaysSentence: "Always give Jason time when I'm free",
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
                kind: "send_draft", source: "MAYA CHEN · MESSAGES", logo: .messages,
                ask: "Tell Maya you're in for Saturday?",
                context: "",
                incoming: "we still on for saturday? need to give them a headcount tonight",
                triggerLabel: "MAYA TEXTED", responseLabel: "IRIS WROTE",
                replyStyle: .imessage,
                draft: "Yes, count me in for Saturday.",
                primaryLabel: "Send it",
                alwaysSentence: "Always answer Maya about plans",
                steps: [
                    DeckRunStep(logo: .messages, text: "Sending as you", detail: "to Maya Chen"),
                    DeckRunStep(logo: .check, text: "Delivered", detail: "read 9:58 PM"),
                ],
                receiptLine: "Told Maya you're in for Saturday.",
                trail: ["HER TEXT 20m", "SHE ASKED TWICE", "YOUR SATURDAY IS OPEN"],
                createdAgo: "20m"
            ),
            DeckItem(
                kind: "place", source: "RESY", logo: .resy,
                ask: "Take the 7:45 at Marufuku?",
                context: "",
                facts: "TONIGHT · 7:45 · 2 SEATS · FREE CANCEL TO 6",
                incoming: "book dinner tonight if marufuku has anything",
                triggerLabel: "YOU ASKED", responseLabel: "IRIS FOUND",
                window: DeckWindow(day: "TONIGHT", start: 19.75, end: 21.25, openFrom: 17, openTo: 23),
                primaryLabel: "Book it",
                alwaysSentence: "Always book Marufuku when I ask",
                steps: [
                    DeckRunStep(logo: .resy, text: "Taking the 7:45", detail: "Marufuku · 2 seats · counter"),
                    DeckRunStep(logo: .check, text: "Booked", detail: "conf #R-2847 · in Mail"),
                ],
                receiptLine: "Marufuku tonight, 7:45, two seats.",
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
                alwaysSentence: "Always move my calendar when a flight moves",
                steps: [DeckRunStep(logo: .calendar, text: "Calendar moved to 9:05", detail: "DL 1187 · gate C11")],
                receiptLine: "Austin flight moved to 9:05 AM.",
                ranUnderRule: "Keep travel plans current",
                trail: ["DELTA PUSH 6h", "MATCHED YOUR CALENDAR", "RAN UNDER A RULE"],
                createdAgo: "6h", phase: .done, filed: true
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
                        .padding(.horizontal, DK.gutter)
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
                              .padding(.horizontal, DK.gutter)
                              .padding(.top, 72)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        .onAppear { engine.seed() }
        // The moments that should be felt, not just seen.
        .sensoryFeedback(.selection, trigger: focused)
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
        .padding(.horizontal, 4)
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

/// Draws the reply in the shape of the app that will carry it. An iMessage
/// gets the blue bubble with its tail; mail gets a plain block, because mail
/// has no shape of its own. Still fully editable inside either.
private struct ReplyBubble<Content: View>: View {
    let style: ReplyStyle
    @ViewBuilder var content: Content

    var body: some View {
        switch style {
        case .imessage:
            content
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .background(
                    LinearGradient(colors: [Color(red: 0.16, green: 0.53, blue: 1),
                                            Color(red: 0.05, green: 0.40, blue: 0.96)],
                                   startPoint: .top, endPoint: .bottom),
                    in: BubbleShape())
                .frame(maxWidth: .infinity, alignment: .leading)
        case .mail, .plain:
            content
        }
    }
}

/// A rounded rectangle with the tail iMessage puts on an outgoing bubble.
private struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: 19, style: .continuous)
        let tail = CGRect(x: rect.maxX - 16, y: rect.maxY - 19, width: 16, height: 19)
        path.move(to: CGPoint(x: tail.minX, y: tail.maxY))
        path.addCurve(to: CGPoint(x: tail.maxX, y: tail.maxY),
                      control1: CGPoint(x: tail.minX + 9, y: tail.maxY),
                      control2: CGPoint(x: tail.maxX - 5, y: tail.maxY - 3))
        path.addCurve(to: CGPoint(x: tail.minX + 3, y: tail.minY),
                      control1: CGPoint(x: tail.maxX - 11, y: tail.maxY - 7),
                      control2: CGPoint(x: tail.minX + 3, y: tail.maxY - 12))
        path.closeSubpath()
        return path
    }
}

/// A named block of the card: two mono words, then the thing itself.
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
    @FocusState private var draftFocused: Bool

    private var running: Bool { if case .running = item.phase { true } else { false } }

    var body: some View {
        DeckPlate(emphasized: true, fills: true) {
            VStack(alignment: .leading, spacing: 0) {
                SourceRow(item: item)
                    .padding(.horizontal, DK.pad)
                    .frame(height: 44)

                LedgerLine()

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

                    Stratum(label: item.responseLabel) {
                        VStack(alignment: .leading, spacing: 10) {
                            if item.draft != nil, !running {
                                ReplyBubble(style: item.replyStyle) { draftWell }
                            }
                            if let facts = item.facts {
                                Text(facts)
                                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                    .kerning(0.6)
                                    .foregroundStyle(DS.Palette.inkMuted)
                            }
                            if let window = item.window, !running {
                                WindowRuler(window: window)
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(DK.pad)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if alwaysOpen, let sentence = item.alwaysSentence, !running {
                    alwaysMenu(sentence)
                        .padding(.horizontal, DK.pad)
                        .padding(.bottom, 10)
                        .transition(.asymmetric(
                            insertion: .offset(y: 8).combined(with: .opacity),
                            removal: .opacity))
                }

                // How this got here. The card has the room, and a machine that
                // acts on your behalf should always be able to show its work
                // without being asked — one dense line, no prose.
                if !item.trail.isEmpty, !running {
                    TrailLine(steps: item.trail)
                        .padding(.horizontal, DK.pad)
                        .padding(.bottom, 11)
                }

                LedgerLine()

                Group {
                    if running { runRail }
                    else if item.phase == .done { doneRow }
                    else { actionRow }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
        .animation(.snappy(duration: 0.2), value: alwaysOpen)
        .animation(.snappy(duration: 0.26), value: running)
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
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Button { engine.decline(item) } label: {
                    Text(item.declineLabel)
                        .font(.system(size: 15.5, weight: .regular))
                        .foregroundStyle(DS.Palette.inkMuted)
                        .frame(height: 50)
                        .padding(.horizontal, 16)
                        .overlay(RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous)
                            .strokeBorder(DS.Palette.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)

                HStack(spacing: 1) {
                    Button {
                        alwaysOpen = false
                        engine.approve(item, always: false)
                    } label: {
                        Text(item.primaryLabel)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(DS.Palette.onInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.plain)

                    if item.alwaysSentence != nil {
                        Button {
                            alwaysOpen.toggle()
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(DS.Palette.onInk.opacity(0.85))
                                .frame(width: 42, height: 50)
                                .rotationEffect(.degrees(alwaysOpen ? 180 : 0))
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(DS.Palette.onInk.opacity(0.22))
                                .frame(width: 1, height: 24)
                        }
                    }
                }
                .background(DS.Palette.ink,
                            in: RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous))
            }

        }
    }

    private func alwaysMenu(_ sentence: String) -> some View {
        Button {
            alwaysOpen = false
            engine.approve(item, always: true)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "infinity")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.logo.accent)
                Text(sentence)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(DS.Palette.ink)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .frame(height: 46)
            .background(
                LinearGradient(colors: [item.logo.accent.opacity(0.16), .clear],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous))
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [item.logo.accent.opacity(0.4), Color.white.opacity(0.05)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1))
        }
        .buttonStyle(.plain)
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

    var body: some View {
        SheetChrome(title: "Judgment") {
            SheetSection(title: "Acts without asking") {
                ForEach(Array(engine.rules.enumerated()), id: \.element.id) { index, rule in
                    if index > 0 { SheetDivider() }
                    RuleRow(
                        rule: rule,
                        open: opened == rule.id,
                        onToggle: {
                            withAnimation(.snappy(duration: 0.24)) {
                                opened = opened == rule.id ? nil : rule.id
                            }
                            _ = DSHaptics.tap(.light)
                        },
                        onDelete: {
                            withAnimation(.snappy(duration: 0.25)) { engine.deleteRule(rule) }
                        }
                    )
                }
            }
        }
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
                    IrisLogoTile(logo: rule.logo, size: 22)
                    Text(rule.sentence)
                        .font(.system(size: 15.5, weight: .regular))
                        .foregroundStyle(DS.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Palette.placeholder)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 54)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(rule.trail.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(DS.Palette.hairline)
                                .frame(width: 3, height: 3)
                                .padding(.top, 5)
                            Text(line)
                                .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                                .foregroundStyle(DS.Palette.placeholder)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Button(action: onDelete) {
                        Text("Ask me again")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DS.Palette.ink)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(DS.Palette.surfaceMuted,
                                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 3)
                }
                .padding(.horizontal, 49)
                .padding(.bottom, 14)
                .transition(.opacity)
            }
        }
    }
}
