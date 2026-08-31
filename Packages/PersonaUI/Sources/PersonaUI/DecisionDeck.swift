import SwiftUI
import PersonaCore
import PersonaDesign

// MARK: - The decision deck
//
// The redesign this trial asked for. One thesis, carried from data to pixels:
// a feed is not a list of notifications, it is a queue of DECISIONS in three
// distinct states, and each state is its own card anatomy —
//
//   ASK      the agent needs a yes. The ask leads, the context is never
//            truncated, the stakes are printed (precedent counted, not
//            guessed), and every action is ON the card. Under the primary
//            sits the stronger yes: "always" — which also approves this one.
//   UTILITY  the card IS the action (a sign-in code exists to be copied,
//            so the whole card copies it, and it visibly expires).
//   RECEIPT  the agent already acted where it had standing. It reports,
//            names the rule that authorised it, and keeps Undo live.
//
// Approve an ask and it streams the agent's actual steps, seals, and files
// itself under HANDLED. Say "always" and later work of that shape arrives
// already done. Every standing permission is readable and deletable in
// Judgment. Dark first: this is an operator's instrument, not a companion.

// MARK: Geometry (deliberately sharper than Radius.card's 28)

private enum DK {
    static let cardRadius: CGFloat = 14
    static let wellRadius: CGFloat = 8
    static let chipRadius: CGFloat = 6
    static let pad: CGFloat = 18
    static let gap: CGFloat = 12
}

// MARK: Model

enum DeckStakes {
    case high(String)          // "no precedent for sending as you"
    case low(String)           // "3 approvals · reversible"

    var label: String { if case .high = self { "HIGH STAKES" } else { "LOW STAKES" } }
    var line: String {
        switch self {
        case let .high(reason), let .low(reason): reason
        }
    }
    var isHigh: Bool { if case .high = self { true } else { false } }
}

struct DeckRunStep: Identifiable, Equatable {
    let id = UUID()
    let symbol: String
    let text: String
}

@MainActor @Observable
final class DeckItem: Identifiable {
    enum Phase: Equatable { case asking, running(Int), done, dismissed }

    let id = UUID()
    let kind: String                 // send_draft / create_meeting / place / code / update / rule_born
    let source: String               // MAIL · SARAH WHITFIELD
    let sourceSymbol: String
    let avatarAsset: String?
    let ask: String                  // the headline decision
    let context: String              // never truncated
    let facts: String?               // mono facts line
    let stakes: DeckStakes?
    var draft: String?               // editable body (Sarah)
    let primaryLabel: String
    let declineLabel: String
    let alwaysSentence: String?      // "Always send routine replies as you"
    let steps: [DeckRunStep]
    let receiptLine: String          // what HANDLED shows
    var ranUnderRule: String?        // set when a rule authorised it
    let createdAgo: String
    var code: String?
    var codeDeadline: Date?
    var copied = false
    var phase: Phase = .asking

    init(kind: String, source: String, sourceSymbol: String, avatarAsset: String? = nil,
         ask: String, context: String, facts: String? = nil, stakes: DeckStakes? = nil,
         draft: String? = nil, primaryLabel: String = "", declineLabel: String = "Not this",
         alwaysSentence: String? = nil, steps: [DeckRunStep] = [], receiptLine: String = "",
         ranUnderRule: String? = nil, createdAgo: String, code: String? = nil,
         codeDeadline: Date? = nil, phase: Phase = .asking) {
        self.kind = kind; self.source = source; self.sourceSymbol = sourceSymbol
        self.avatarAsset = avatarAsset; self.ask = ask; self.context = context
        self.facts = facts; self.stakes = stakes; self.draft = draft
        self.primaryLabel = primaryLabel; self.declineLabel = declineLabel
        self.alwaysSentence = alwaysSentence; self.steps = steps
        self.receiptLine = receiptLine; self.ranUnderRule = ranUnderRule
        self.createdAgo = createdAgo; self.code = code; self.codeDeadline = codeDeadline
        self.phase = phase
    }
}

struct DeckRule: Identifiable, Equatable {
    let id = UUID()
    let sentence: String
    let scope: String
    var uses: Int
}

// MARK: Engine

@MainActor @Observable
final class DecisionEngine {
    /// One engine for the whole app: the deck renders it, the header and the
    /// sidebar open its Judgment, and the sheet lives on the host so it can
    /// present from either page.
    static let shared = DecisionEngine()

    var items: [DeckItem] = []
    var rules: [DeckRule] = [
        DeckRule(sentence: "Keep travel plans current", scope: "Calendar", uses: 7),
        DeckRule(sentence: "Move gym bookings when classes clash", scope: "Calendar", uses: 4),
        DeckRule(sentence: "File receipts into Notion", scope: "Mail", uses: 12),
    ]
    var judgmentShown = false
    private var graduated = false

    var asks: [DeckItem] { items.filter { $0.phase == .asking || isRunning($0) } }
    var handled: [DeckItem] { items.filter { $0.phase == .done } }
    private func isRunning(_ item: DeckItem) -> Bool {
        if case .running = item.phase { true } else { false }
    }

    func seed() {
        guard items.isEmpty else { return }
        items = [
            DeckItem(
                kind: "code",
                source: "GITHUB",
                sourceSymbol: "key.fill",
                ask: "", context: "Tap to copy",
                createdAgo: "1m",
                code: "481 902",
                codeDeadline: Date().addingTimeInterval(9 * 60)
            ),
            DeckItem(
                kind: "send_draft",
                source: "SARAH WHITFIELD · MAIL",
                sourceSymbol: "envelope.fill",
                avatarAsset: "AvatarSarah",
                ask: "Confirm Thursday with Sarah?",
                context: "She needs an answer before she books the room.",
                stakes: .high("first send as you"),
                draft: "Thursday still works — 2pm at your office? I'll bring the printed boards.",
                primaryLabel: "Send reply",
                alwaysSentence: "Always send routine replies as you",
                steps: [
                    DeckRunStep(symbol: "envelope.open", text: "Opening the thread"),
                    DeckRunStep(symbol: "paperplane.fill", text: "Sending as you"),
                    DeckRunStep(symbol: "checkmark", text: "Sent"),
                ],
                receiptLine: "Replied to Sarah — Thursday 2 PM confirmed.",
                createdAgo: "1h"
            ),
            DeckItem(
                kind: "create_meeting",
                source: "JASON MEHTA · MAIL",
                sourceSymbol: "calendar",
                avatarAsset: "AvatarJason",
                ask: "Give Jason 30 minutes Wednesday?",
                context: "Firmware timeline. Wednesday is open after 3.",
                facts: "WED · 3:30 – 4:00 PM · INVITE TO JASON",
                stakes: .low("3 approvals · reversible"),
                primaryLabel: "Book 3:30",
                alwaysSentence: "Always schedule when my calendar is open",
                steps: [
                    DeckRunStep(symbol: "calendar.badge.plus", text: "Holding Wed 3:30"),
                    DeckRunStep(symbol: "paperplane.fill", text: "Inviting Jason"),
                    DeckRunStep(symbol: "checkmark", text: "On the calendar"),
                ],
                receiptLine: "Jason — Wednesday 3:30, invite sent.",
                createdAgo: "3h"
            ),
            DeckItem(
                kind: "place",
                source: "RESY",
                sourceSymbol: "fork.knife",
                ask: "Take the 7:45 at Marufuku?",
                context: "Two counter seats — the last slot before 9.",
                facts: "TONIGHT · 7:45 · FREE CANCEL TO 6",
                stakes: .low("booked twice · free cancel"),
                primaryLabel: "Book it",
                alwaysSentence: "Always grab tables at places I've saved",
                steps: [
                    DeckRunStep(symbol: "fork.knife", text: "Taking the 7:45"),
                    DeckRunStep(symbol: "checkmark", text: "Booked · confirmation in Mail"),
                ],
                receiptLine: "Marufuku tonight — 7:45, two seats.",
                createdAgo: "4h"
            ),
            DeckItem(
                kind: "update",
                source: "DELTA 1187",
                sourceSymbol: "airplane.departure",
                ask: "Move your Austin flight alarm?",
                context: "Moved up 40 minutes. Gate unchanged.",
                facts: "SFO → AUS · 9:05 AM · GATE C11",
                primaryLabel: "Update calendar",
                steps: [DeckRunStep(symbol: "calendar", text: "Calendar moved to 9:05")],
                receiptLine: "Austin flight — calendar moved to 9:05 AM.",
                ranUnderRule: "Keep travel plans current",
                createdAgo: "6h",
                phase: .done
            ),
        ]
    }

    func approve(_ item: DeckItem, always: Bool) {
        if always, let sentence = item.alwaysSentence,
           !rules.contains(where: { $0.sentence == sentence }) {
            rules.insert(DeckRule(sentence: sentence, scope: scope(for: item.kind), uses: 1), at: 0)
        }
        run(item)
        if always, item.kind == "send_draft" { graduate() }
    }

    func decline(_ item: DeckItem) {
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
                try? await Task.sleep(for: .milliseconds(index == item.steps.indices.last ? 620 : 480))
            }
            withAnimation(.smooth(duration: 0.4)) { item.phase = .done }
        }
    }

    /// The graduation demo: minutes after "always", work of the same shape
    /// arrives already handled — the rule acting alone, receipt and Undo left
    /// behind. This is the product's whole argument, shown not told.
    private func graduate() {
        guard !graduated else { return }
        graduated = true
        Task {
            try? await Task.sleep(for: .seconds(7))
            if let index = rules.firstIndex(where: { $0.sentence == "Always send routine replies as you" }) {
                rules[index].uses += 1
            }
            let born = DeckItem(
                kind: "send_draft",
                source: "PRIYA NAIR · MAIL",
                sourceSymbol: "envelope.fill",
                ask: "Reply to Priya about the deck?",
                context: "She asked for the three changed slides before the review.",
                draft: "Attached — the three slides that changed since last quarter.",
                primaryLabel: "Send reply",
                steps: [DeckRunStep(symbol: "paperplane.fill", text: "Sent as you")],
                receiptLine: "Sent Priya the three changed slides.",
                ranUnderRule: "Always send routine replies as you",
                createdAgo: "now",
                phase: .done
            )
            withAnimation(.smooth(duration: 0.45)) { items.insert(born, at: 0) }
        }
    }

    func deleteRule(_ rule: DeckRule) {
        rules.removeAll { $0.id == rule.id }
        // A deleted rule takes its authority with it: anything sitting in
        // HANDLED under that sentence goes back to asking.
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

// MARK: - Deck root

public struct DecisionDeck: View {
    private let engine = DecisionEngine.shared

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: DK.gap) {
            deckHeader(count: engine.asks.filter { $0.kind != "code" }.count)

            ForEach(engine.asks) { item in
                Group {
                    if item.kind == "code" {
                        CodeCard(item: item)
                    } else {
                        AskCard(item: item, engine: engine)
                    }
                }
                .transition(.asymmetric(
                    insertion: .offset(y: 14).combined(with: .opacity),
                    removal: .offset(x: 120).combined(with: .opacity)))
            }

            if !engine.handled.isEmpty {
                sectionLabel("HANDLED · \(engine.handled.count)")
                    .padding(.top, 8)
                ForEach(engine.handled) { item in
                    ReceiptCard(item: item, engine: engine)
                        .transition(.asymmetric(
                            insertion: .offset(y: 12).combined(with: .opacity),
                            removal: .opacity))
                }
            }
        }
        .animation(.smooth(duration: 0.34), value: engine.items.map(\.id))
        .animation(.smooth(duration: 0.34), value: engine.handled.map(\.id))
        .onAppear { engine.seed() }
    }

    private func deckHeader(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            sectionLabel("NEEDS YOU · \(count)")
            Spacer()
            Button { engine.judgmentShown = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "brain")
                        .font(.system(size: 10, weight: .semibold))
                    Text("JUDGMENT · \(engine.rules.count)")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .kerning(0.8)
                }
                .foregroundStyle(DS.Palette.subtle)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(DS.Palette.surfaceMuted,
                            in: RoundedRectangle(cornerRadius: DK.chipRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DK.chipRadius, style: .continuous)
                    .strokeBorder(DS.Palette.hairlineSoft, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 2)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .kerning(1.1)
            .foregroundStyle(DS.Palette.placeholder)
    }
}

// MARK: - Card chrome shared by all three anatomies

private struct DeckPlate<Content: View>: View {
    var emphasized = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.card,
                        in: RoundedRectangle(cornerRadius: DK.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DK.cardRadius, style: .continuous)
                .strokeBorder(emphasized ? DS.Palette.hairline : DS.Palette.hairlineSoft,
                              lineWidth: 1))
    }
}

private struct SourceRow: View {
    let item: DeckItem

    var body: some View {
        HStack(spacing: 8) {
            if let asset = item.avatarAsset {
                PersonaAsset.image(asset)
                    .resizable().scaledToFill()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: item.sourceSymbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Palette.subtle)
                    .frame(width: 22, height: 22)
                    .background(DS.Palette.surfaceMuted,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            Text(item.source)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .kerning(0.8)
                .foregroundStyle(DS.Palette.subtle)
            Spacer()
            Text(item.createdAgo)
                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                .foregroundStyle(DS.Palette.placeholder)
        }
    }
}

private struct StakesChip: View {
    let stakes: DeckStakes

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .strokeBorder(DS.Palette.ink, lineWidth: 1)
                .background(Circle().fill(stakes.isHigh ? Color.clear : DS.Palette.ink))
                .frame(width: 5, height: 5)
            Text(stakes.label)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .kerning(0.9)
                .foregroundStyle(DS.Palette.inkMuted)
            Rectangle().fill(DS.Palette.hairlineSoft).frame(width: 1, height: 10)
            Text(stakes.line)
                .font(.system(size: 11.5))
                .foregroundStyle(DS.Palette.subtle)
                .lineLimit(1)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(DS.Palette.surfaceMuted,
                    in: RoundedRectangle(cornerRadius: DK.chipRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DK.chipRadius, style: .continuous)
            .strokeBorder(DS.Palette.hairlineSoft, lineWidth: 1))
    }
}

// MARK: - ASK

private struct AskCard: View {
    @Bindable var item: DeckItem
    let engine: DecisionEngine
    @State private var alwaysOpen = false
    @State private var editingDraft = false
    @FocusState private var draftFocused: Bool

    private var running: Bool { if case .running = item.phase { true } else { false } }

    var body: some View {
        DeckPlate(emphasized: true) {
            VStack(alignment: .leading, spacing: 12) {
                SourceRow(item: item)

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.ask)
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(DS.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.context)
                        .font(.system(size: 16))
                        .foregroundStyle(DS.Palette.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let facts = item.facts {
                    Text(facts)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .kerning(0.6)
                        .foregroundStyle(DS.Palette.inkMuted)
                }

                if let stakes = item.stakes { StakesChip(stakes: stakes) }

                if item.draft != nil, !alwaysOpen { draftWell }

                if alwaysOpen, let sentence = item.alwaysSentence, !running {
                    alwaysMenu(sentence)
                        .transition(.asymmetric(
                            insertion: .offset(y: 8).combined(with: .opacity),
                            removal: .opacity))
                }

                if running { runRail } else { actionRow }
            }
            .padding(DK.pad)
        }
        .animation(.snappy(duration: 0.2), value: alwaysOpen)
        .animation(.snappy(duration: 0.26), value: running)
    }

    private var draftWell: some View {
        Group {
            if editingDraft {
                TextEditor(text: Binding(get: { item.draft ?? "" }, set: { item.draft = $0 }))
                    .focused($draftFocused)
                    .font(.system(size: 15))
                    .foregroundStyle(DS.Palette.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 64, maxHeight: 120)
                    .padding(10)
                    .background(DS.Palette.surfaceMuted,
                                in: RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous)
                        .strokeBorder(DS.Palette.hairline, lineWidth: 1))
                    .onAppear { draftFocused = true }
                    .onChange(of: draftFocused) { _, focused in
                        if !focused { editingDraft = false }
                    }
            } else {
                Button {
                    editingDraft = true
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle().fill(DS.Palette.hairline).frame(width: 2)
                        Text(item.draft ?? "")
                            .font(.system(size: 15))
                            .foregroundStyle(DS.Palette.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.Palette.placeholder)
                    }
                    .padding(10)
                    .background(DS.Palette.surfaceMuted,
                                in: RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button { engine.decline(item) } label: {
                Text(item.declineLabel)
                    .font(.system(size: 15.5, weight: .medium))
                    .foregroundStyle(DS.Palette.inkMuted)
                    .frame(height: 48)
                    .padding(.horizontal, 16)
                    .background(DS.Palette.surfaceMuted,
                                in: RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous)
                        .strokeBorder(DS.Palette.hairlineSoft, lineWidth: 1))
            }
            .buttonStyle(.plain)

            HStack(spacing: 1) {
                Button {
                    alwaysOpen = false
                    engine.approve(item, always: false)
                    _ = DSHaptics.tap(.rigid)
                } label: {
                    Text(item.primaryLabel)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.Palette.onInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.plain)

                if item.alwaysSentence != nil {
                    Button {
                        alwaysOpen.toggle()
                        _ = DSHaptics.tap(.light)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(DS.Palette.onInk.opacity(0.85))
                            .frame(width: 40, height: 48)
                            .rotationEffect(.degrees(alwaysOpen ? 180 : 0))
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(DS.Palette.onInk.opacity(0.22))
                            .frame(width: 1, height: 22)
                    }
                }
            }
            .background(DS.Palette.ink,
                        in: RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous))
        }
    }

    private func alwaysMenu(_ sentence: String) -> some View {
        Button {
            alwaysOpen = false
            engine.approve(item, always: true)
            _ = DSHaptics.tap(.rigid)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(sentence)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DS.Palette.ink)
                Text("Approves this one too. Undo any time in Judgment.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.Palette.subtle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(DS.Palette.surface,
                        in: RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous)
                .strokeBorder(DS.Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var runRail: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(item.steps.enumerated()), id: \.element.id) { index, step in
                let state: Int = {
                    if case let .running(current) = item.phase {
                        return index < current ? 2 : (index == current ? 1 : 0)
                    }
                    return 2
                }()
                HStack(spacing: 9) {
                    Image(systemName: state == 2 ? "checkmark" : step.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(state == 0 ? DS.Palette.placeholder : DS.Palette.ink)
                        .frame(width: 20, height: 20)
                        .background(DS.Palette.surfaceMuted,
                                    in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    Text(step.text)
                        .font(.system(size: 14.5, weight: state == 1 ? .semibold : .regular))
                        .foregroundStyle(state == 0 ? DS.Palette.placeholder : DS.Palette.inkMuted)
                    if state == 1 {
                        ProgressView().controlSize(.mini).tint(DS.Palette.subtle)
                    }
                }
                .opacity(state == 0 ? 0.5 : 1)
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - UTILITY (the sign-in code)

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
                _ = DSHaptics.tap(.rigid)
                Task { try? await Task.sleep(for: .seconds(2))
                       withAnimation(.smooth(duration: 0.3)) { item.copied = false } }
            } label: {
                DeckPlate {
                    VStack(alignment: .leading, spacing: 10) {
                        SourceRow(item: item)
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.code ?? "")
                                .font(.system(size: 40, weight: .semibold, design: .monospaced))
                                .kerning(2)
                                .foregroundStyle(expired ? DS.Palette.placeholder : DS.Palette.ink)
                                .contentTransition(.opacity)
                            Spacer()
                            Text(item.copied ? "COPIED" : (expired ? "EXPIRED" : "TAP TO COPY"))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .kerning(1)
                                .foregroundStyle(item.copied ? DS.Palette.success : DS.Palette.placeholder)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(DS.Palette.track).frame(height: 2)
                                Capsule().fill(expired ? DS.Palette.placeholder : DS.Palette.ink)
                                    .frame(width: proxy.size.width * (left / total), height: 2)
                            }
                        }
                        .frame(height: 2)
                        Text(expired ? "This code is dead." : "Expires in \(Int(left) / 60):\(String(format: "%02d", Int(left) % 60))")
                            .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                            .foregroundStyle(DS.Palette.placeholder)
                    }
                    .padding(DK.pad)
                }
            }
            .buttonStyle(.plain)
            .opacity(expired ? 0.55 : 1)
        }
    }
}

// MARK: - RECEIPT

private struct ReceiptCard: View {
    @Bindable var item: DeckItem
    let engine: DecisionEngine

    var body: some View {
        DeckPlate {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.Palette.subtle)
                    .frame(width: 18, height: 18)
                    .background(DS.Palette.surfaceMuted,
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(DS.Palette.hairlineSoft, lineWidth: 1))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.receiptLine)
                        .font(.system(size: 15.5, weight: .medium))
                        .foregroundStyle(DS.Palette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let rule = item.ranUnderRule {
                        Text("RULE · \(rule.uppercased())")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .kerning(0.8)
                            .foregroundStyle(DS.Palette.placeholder)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Button { engine.undo(item) } label: {
                    Text("Undo")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(DS.Palette.subtle)
                        .underline()
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DK.pad)
            .padding(.vertical, 12)
        }
        .opacity(0.92)
    }
}

// MARK: - Judgment

struct JudgmentSheet: View {
    var engine: DecisionEngine = .shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "brain")
                        .font(.system(size: 12, weight: .semibold))
                    Text("JUDGMENT")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .kerning(1.4)
                }
                .foregroundStyle(DS.Palette.ink)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Palette.subtle)
                        .frame(width: 28, height: 28)
                        .background(DS.Palette.surfaceMuted, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 6)

            Text("Everything Iris may do without asking. Each learned from your own approvals.")
                .font(.system(size: 12.5))
                .foregroundStyle(DS.Palette.subtle)
                .padding(.horizontal, 20).padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(engine.rules) { rule in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(rule.sentence)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(DS.Palette.ink)
                                Text("\(rule.scope.uppercased()) · USED \(rule.uses)×")
                                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                    .kerning(0.8)
                                    .foregroundStyle(DS.Palette.placeholder)
                            }
                            Spacer()
                            Button {
                                withAnimation(.snappy(duration: 0.25)) { engine.deleteRule(rule) }
                                _ = DSHaptics.tap(.light)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(DS.Palette.subtle)
                                    .frame(width: 26, height: 26)
                                    .background(DS.Palette.surfaceMuted,
                                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(DS.Palette.card,
                                    in: RoundedRectangle(cornerRadius: DK.wellRadius + 2, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: DK.wellRadius + 2, style: .continuous)
                            .strokeBorder(DS.Palette.hairlineSoft, lineWidth: 1))
                    }
                }
                .padding(.horizontal, 20)
            }

            Text("Delete a rule and Iris asks again.")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(DS.Palette.placeholder)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .presentationBackground(DS.Palette.canvas)
    }
}
