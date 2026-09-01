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
    static let cardRadius: CGFloat = 12
    static let wellRadius: CGFloat = 7
    static let chipRadius: CGFloat = 5
    static let pad: CGFloat = 18
    static let gutter: CGFloat = 16
}

// MARK: Model

struct DeckRunStep: Identifiable, Equatable {
    let id = UUID()
    let logo: IrisLogo
    let text: String
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
    let createdAgo: String
    var code: String?
    var codeDeadline: Date?
    var copied = false
    var phase: Phase = .asking

    init(kind: String, source: String, logo: IrisLogo, avatarAsset: String? = nil,
         ask: String, context: String, facts: String? = nil,
         draft: String? = nil, primaryLabel: String = "", declineLabel: String = "Not this",
         alwaysSentence: String? = nil, steps: [DeckRunStep] = [], receiptLine: String = "",
         ranUnderRule: String? = nil, createdAgo: String, code: String? = nil,
         codeDeadline: Date? = nil, phase: Phase = .asking) {
        self.kind = kind; self.source = source; self.logo = logo
        self.avatarAsset = avatarAsset; self.ask = ask; self.context = context
        self.facts = facts; self.draft = draft
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
    static let shared = DecisionEngine()

    var items: [DeckItem] = []
    var rules: [DeckRule] = [
        DeckRule(sentence: "Keep travel plans current", scope: "Calendar", uses: 7),
        DeckRule(sentence: "Move gym bookings when classes clash", scope: "Calendar", uses: 4),
        DeckRule(sentence: "File receipts into Notion", scope: "Mail", uses: 12),
    ]
    var judgmentShown = false
    private var graduated = false

    // Haptic pulses. Views subscribe with .sensoryFeedback on these counters;
    // the engine bumps them at the moments that should be felt.
    var stepPulse = 0
    var donePulse = 0
    var declinePulse = 0

    var asks: [DeckItem] { items.filter { $0.phase == .asking || isRunning($0) } }
    var handled: [DeckItem] { items.filter { $0.phase == .done } }
    private func isRunning(_ item: DeckItem) -> Bool {
        if case .running = item.phase { true } else { false }
    }

    func seed() {
        guard items.isEmpty else { return }
        items = [
            DeckItem(
                kind: "code", source: "GITHUB", logo: .github,
                ask: "", context: "Tap to copy",
                createdAgo: "1m", code: "481 902",
                codeDeadline: Date().addingTimeInterval(9 * 60)
            ),
            DeckItem(
                kind: "send_draft", source: "SARAH WHITFIELD · MAIL", logo: .mail,
                avatarAsset: "AvatarSarah",
                ask: "Confirm Thursday with Sarah?",
                context: "She needs an answer before she books the room.",
                draft: "Thursday still works — 2pm at your office? I'll bring the printed boards.",
                primaryLabel: "Send reply",
                alwaysSentence: "Always send routine replies as you",
                steps: [
                    DeckRunStep(logo: .mail, text: "Opening the thread"),
                    DeckRunStep(logo: .mail, text: "Sending as you"),
                    DeckRunStep(logo: .check, text: "Sent"),
                ],
                receiptLine: "Replied to Sarah — Thursday 2 PM confirmed.",
                createdAgo: "1h"
            ),
            DeckItem(
                kind: "create_meeting", source: "JASON MEHTA · MAIL", logo: .calendar,
                avatarAsset: "AvatarJason",
                ask: "Give Jason 30 minutes Wednesday?",
                context: "Firmware timeline. Wednesday is open after 3.",
                facts: "WED · 3:30 – 4:00 PM · INVITE TO JASON",
                primaryLabel: "Book 3:30",
                alwaysSentence: "Always schedule when my calendar is open",
                steps: [
                    DeckRunStep(logo: .calendar, text: "Holding Wed 3:30"),
                    DeckRunStep(logo: .mail, text: "Inviting Jason"),
                    DeckRunStep(logo: .check, text: "On the calendar"),
                ],
                receiptLine: "Jason — Wednesday 3:30, invite sent.",
                createdAgo: "3h"
            ),
            DeckItem(
                kind: "place", source: "RESY", logo: .resy,
                ask: "Take the 7:45 at Marufuku?",
                context: "Two counter seats — the last slot before 9.",
                facts: "TONIGHT · 7:45 · FREE CANCEL TO 6",
                primaryLabel: "Book it",
                alwaysSentence: "Always grab tables at places I've saved",
                steps: [
                    DeckRunStep(logo: .resy, text: "Taking the 7:45"),
                    DeckRunStep(logo: .check, text: "Booked — confirmation in Mail"),
                ],
                receiptLine: "Marufuku tonight — 7:45, two seats.",
                createdAgo: "4h"
            ),
            DeckItem(
                kind: "update", source: "DELTA 1187", logo: .delta,
                ask: "Move your Austin flight alarm?",
                context: "Moved up 40 minutes. Gate unchanged.",
                facts: "SFO → AUS · 9:05 AM · GATE C11",
                primaryLabel: "Update calendar",
                steps: [DeckRunStep(logo: .calendar, text: "Calendar moved to 9:05")],
                receiptLine: "Austin flight — calendar moved to 9:05 AM.",
                ranUnderRule: "Keep travel plans current",
                createdAgo: "6h", phase: .done
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
                try? await Task.sleep(for: .milliseconds(index == item.steps.indices.last ? 650 : 520))
            }
            donePulse += 1
            withAnimation(.smooth(duration: 0.4)) { item.phase = .done }
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
                context: "She asked for the three changed slides before the review.",
                draft: "Attached — the three slides that changed since last quarter.",
                primaryLabel: "Send reply",
                steps: [DeckRunStep(logo: .mail, text: "Sent as you")],
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the floating header the host draws over this screen.
            Spacer().frame(height: 118)

            Text("Welcome back, Shaurya.")
                .font(.system(size: 31, weight: .thin))
                .foregroundStyle(DS.Palette.ink)
                .padding(.horizontal, DK.gutter + 4)
                .padding(.bottom, 12)

            controlRow
                .padding(.horizontal, DK.gutter + 4)
                .padding(.bottom, 6)

            switch mode {
            case .feed: pager
            case .brief: BriefView(engine: engine)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Palette.canvas)
        .onAppear { engine.seed() }
        // The moments that should be felt, not just seen.
        .sensoryFeedback(.selection, trigger: focused)
        .sensoryFeedback(.impact(weight: .light), trigger: engine.stepPulse)
        .sensoryFeedback(.success, trigger: engine.donePulse)
        .sensoryFeedback(.warning, trigger: engine.declinePulse)
        .sensoryFeedback(.selection, trigger: mode)
    }

    private var controlRow: some View {
        HStack(spacing: 8) {
            Text("NEEDS YOU · \(engine.asks.filter { $0.kind != "code" }.count)")
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .kerning(1.1)
                .foregroundStyle(DS.Palette.placeholder)

            Spacer()

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
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(DS.Palette.surfaceMuted,
                            in: RoundedRectangle(cornerRadius: DK.chipRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DK.chipRadius, style: .continuous)
                    .strokeBorder(DS.Palette.hairlineSoft, lineWidth: 1))
            }

            Button {
                engine.judgmentShown = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "brain")
                        .font(.system(size: 10, weight: .semibold))
                    Text("\(engine.rules.count)")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(DS.Palette.inkMuted)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(DS.Palette.surfaceMuted,
                            in: RoundedRectangle(cornerRadius: DK.chipRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DK.chipRadius, style: .continuous)
                    .strokeBorder(DS.Palette.hairlineSoft, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: The pager

    private var pageIDs: [String] {
        engine.asks.map(\.id.uuidString) + ["handled"]
    }

    private var pager: some View {
        GeometryReader { geo in
            let height = geo.size.height
            // The focused card owns the screen; the neighbours' 25% keeps the
            // stack legible. Slot + two peeks + two gaps = the viewport.
            let slot = height * 0.70
            // Asymmetric peeks: the composer floats over the bottom of the
            // viewport, so the focused card sits high — the previous card's
            // tail shows a sliver, the NEXT card's head gets the real estate.
            let spare = height - slot
            let topMargin = spare * 0.32
            let bottomMargin = spare * 0.68

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(engine.asks) { item in
                        Group {
                            if item.kind == "code" {
                                CodeCard(item: item)
                            } else {
                                AskCard(item: item, engine: engine)
                            }
                        }
                        .frame(height: slot)
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

                    HandledPage(engine: engine)
                        .frame(height: slot)
                        .id("handled")
                        .scrollTransition(axis: .vertical) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.45)
                                .scaleEffect(phase.isIdentity ? 1 : 0.97)
                        }
                }
                .scrollTargetLayout()
                .padding(.horizontal, DK.gutter)
            }
            .scrollPosition(id: $focused)
            // One card per gesture, even on an over-scroll.
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .contentMargins(.top, topMargin, for: .scrollContent)
            .contentMargins(.bottom, bottomMargin, for: .scrollContent)
            .animation(.smooth(duration: 0.34), value: engine.asks.map(\.id))
        }
    }
}

// MARK: - Shared card chrome

private struct DeckPlate<Content: View>: View {
    var emphasized = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
    @State private var editingDraft = false
    @FocusState private var draftFocused: Bool

    private var running: Bool { if case .running = item.phase { true } else { false } }

    var body: some View {
        DeckPlate(emphasized: true) {
            VStack(alignment: .leading, spacing: 14) {
                SourceRow(item: item)

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.ask)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(DS.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.context)
                        .font(.system(size: 16.5))
                        .foregroundStyle(DS.Palette.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let facts = item.facts {
                    Text(facts)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .kerning(0.6)
                        .foregroundStyle(DS.Palette.inkMuted)
                }

                if item.draft != nil, !alwaysOpen, !running { draftWell }

                Spacer(minLength: 0)

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
        // The mechanical yes: double-tap anywhere on the focused card.
        .onTapGesture(count: 2) {
            guard !running, item.phase == .asking else { return }
            alwaysOpen = false
            engine.approve(item, always: false)
        }
        .animation(.snappy(duration: 0.2), value: alwaysOpen)
        .animation(.snappy(duration: 0.26), value: running)
    }

    private var draftWell: some View {
        Group {
            if editingDraft {
                TextEditor(text: Binding(get: { item.draft ?? "" }, set: { item.draft = $0 }))
                    .focused($draftFocused)
                    .font(.system(size: 15.5))
                    .foregroundStyle(DS.Palette.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 70, maxHeight: 130)
                    .padding(10)
                    .background(DS.Palette.surfaceMuted,
                                in: RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous)
                        .strokeBorder(DS.Palette.hairline, lineWidth: 1))
                    .onAppear { draftFocused = true }
                    .onChange(of: draftFocused) { _, focus in
                        if !focus { editingDraft = false }
                    }
            } else {
                Button { editingDraft = true } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle().fill(DS.Palette.hairline).frame(width: 2)
                        Text(item.draft ?? "")
                            .font(.system(size: 15.5))
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { engine.decline(item) } label: {
                    Text(item.declineLabel)
                        .font(.system(size: 15.5, weight: .medium))
                        .foregroundStyle(DS.Palette.inkMuted)
                        .frame(height: 50)
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
                    } label: {
                        Text(item.primaryLabel)
                            .font(.system(size: 16, weight: .semibold))
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

            Text("DOUBLE-TAP APPROVES")
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .kerning(1.2)
                .foregroundStyle(DS.Palette.placeholder.opacity(0.7))
                .frame(maxWidth: .infinity)
        }
    }

    private func alwaysMenu(_ sentence: String) -> some View {
        Button {
            alwaysOpen = false
            engine.approve(item, always: true)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(sentence)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(DS.Palette.ink)
                Text("Approves this one too. Undo any time in Judgment.")
                    .font(.system(size: 12))
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
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(item.steps.enumerated()), id: \.element.id) { index, step in
                let state: Int = {
                    if case let .running(current) = item.phase {
                        return index < current ? 2 : (index == current ? 1 : 0)
                    }
                    return 2
                }()
                HStack(spacing: 10) {
                    IrisLogoTile(logo: state == 2 ? .check : step.logo, size: 24)
                        .saturation(state == 0 ? 0 : 1)
                    Text(step.text)
                        .font(.system(size: 15, weight: state == 1 ? .semibold : .regular))
                        .foregroundStyle(state == 0 ? DS.Palette.placeholder : DS.Palette.inkMuted)
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
                DeckPlate {
                    VStack(alignment: .leading, spacing: 0) {
                        SourceRow(item: item)
                        Spacer(minLength: 0)
                        Text(item.code ?? "")
                            .font(.system(size: 58, weight: .thin, design: .monospaced))
                            .kerning(3)
                            .foregroundStyle(expired ? DS.Palette.placeholder : DS.Palette.ink)
                            .frame(maxWidth: .infinity)
                        Text(item.copied ? "COPIED" : (expired ? "EXPIRED" : "TAP TO COPY"))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .kerning(1.4)
                            .foregroundStyle(item.copied ? DS.Palette.success : DS.Palette.placeholder)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 10)
                        Spacer(minLength: 0)
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
                            .padding(.top, 10)
                    }
                    .padding(DK.pad)
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
        DeckPlate {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("HANDLED · \(engine.handled.count)")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .kerning(1.1)
                        .foregroundStyle(DS.Palette.placeholder)
                    Spacer()
                    Button { engine.judgmentShown = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "brain")
                                .font(.system(size: 9, weight: .semibold))
                            Text("JUDGMENT")
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .kerning(0.9)
                        }
                        .foregroundStyle(DS.Palette.subtle)
                    }
                    .buttonStyle(.plain)
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
            IrisLogoTile(logo: .check, size: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.receiptLine)
                    .font(.system(size: 15, weight: .medium))
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
        .background(DS.Palette.surfaceMuted,
                    in: RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous))
    }
}

// MARK: - BRIEF (the composed view)

private struct BriefView: View {
    let engine: DecisionEngine

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
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

                Button { engine.judgmentShown = true } label: {
                    HStack {
                        Image(systemName: "brain")
                            .font(.system(size: 12, weight: .semibold))
                        Text("\(engine.rules.count) standing rules")
                            .font(.system(size: 15, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.Palette.placeholder)
                    }
                    .foregroundStyle(DS.Palette.inkMuted)
                    .padding(14)
                    .background(DS.Palette.surfaceMuted,
                                in: RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous))
                }
                .buttonStyle(.plain)

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
                        .font(.system(size: 16.5, weight: .semibold))
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
                            .background(DS.Palette.card,
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
        .background(DS.Palette.surfaceMuted,
                    in: RoundedRectangle(cornerRadius: DK.wellRadius + 2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DK.wellRadius + 2, style: .continuous)
            .strokeBorder(DS.Palette.hairlineSoft, lineWidth: 1))
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
                                    .font(.system(size: 14.5, weight: .medium))
                                    .foregroundStyle(DS.Palette.ink)
                                Text("\(rule.scope.uppercased()) · USED \(rule.uses)×")
                                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                    .kerning(0.8)
                                    .foregroundStyle(DS.Palette.placeholder)
                            }
                            Spacer()
                            Button {
                                withAnimation(.snappy(duration: 0.25)) { engine.deleteRule(rule) }
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
