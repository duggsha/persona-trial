import PersonaCore
import PersonaDesign
import PersonaService
import SwiftUI

/// The design trial's whole app: the REAL Home page and chat transcript under
/// the REAL floating header, with the REAL composer pinned to the bottom, over
/// stores that were pinned to dummy data and never talk to a backend.
///
/// This file is the ONLY addition to the ported `PersonaUI` — it exists because
/// `HomeScreen`, `ChatScreen`, `PersonaHeader` and `PersonaComposer` are all
/// internal to the package, so the app target can't mount them directly.
/// Everything it draws is the shipping view code, unmodified; it is a thinner
/// `PersonaRootView` with the Iris menu, the thread overlays and every
/// network-bound handler removed.
public struct DesignTrialHost: View {
    /// The seeded transcript. Passed in rather than read from a store because
    /// the app target owns the dummy data.
    private let messages: [ChatMessage]

    public init(messages: [ChatMessage] = []) {
        self.messages = messages
    }

    @Environment(HomeStore.self) private var home
    @Environment(ProfileStore.self) private var profile

    /// Which page is showing. Driven by the header's toggle AND by the pager's
    /// own swipe, exactly as in the app.
    @State private var page: PersonaPage = .home
    /// The menu button's slide-over.
    @State private var profileShown = false
    /// The transcript, live: voice mode appends to it.
    @State private var chatLog: [ChatMessage] = []
    @State private var chatTrails: [UUID: ChatToolTrail] = [:]
    @State private var voiceShown = false
    /// The + menu's destinations. Every one of them is a real page.
    @State private var appsShown = false
    @State private var photosShown = false
    @State private var filesShown = false
    @State private var cameraShown = false
    @State private var notificationsShown = false
    /// Light / dark / follow the system, chosen in Profile and remembered.
    @AppStorage("trial.appearance") private var appearance = "system"
    private var scheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
    /// Live horizontal drag distance while a page swipe is in flight.
    @State private var dragX: CGFloat = 0
    /// Latched once a drag is decisively horizontal: the pages' vertical
    /// scrollers stand down for exactly that gesture, so the feed never creeps
    /// while you're paging.
    @State private var pagingHorizontally = false
    /// Home's scroll-under signal, which ramps the wordmark's glass exactly as
    /// it does in the real app.
    @State private var scrolledUnderHeader = false
    /// The one Stop-menu slot Home's task cards share.
    @State private var revealedTaskDeleteId: AnyHashable?
    /// A card asking Home to scroll it into view (a card's own reveal).
    @State private var revealTarget: HomeRevealTarget?
    /// Bumped to ask the transcript to settle back to its newest message.
    @State private var chatScrollTick = 0

    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // The ground the glass lifts off: true black in dark, the
                // canvas token in light.
                (scheme == .light ? DS.Palette.canvas : Color.black)
                    .ignoresSafeArea()

                pager(width: geo.size.width, safeHeight: geo.size.height)

                // The header floats, so content has to DISSOLVE into it rather
                // than collide with it. Without this the transcript's bubbles
                // ran straight through the wordmark. Instrument, not accident.
                HeaderScrim(safeTop: geo.safeAreaInsets.top)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)

                // The same courtesy at the other end: the composer floats too,
                // and a card sliding under it should fade, not collide.
                FooterScrim(safeBottom: geo.safeAreaInsets.bottom)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)

                // The floating glass header rides on top of both pages.
                PersonaHeader(
                    page: $page,
                    homeScrolled: page == .home && scrolledUnderHeader,
                    avatarUrl: profile.avatarUrl,
                    onLogo: { profileShown = true },
                    onJudgment: { DecisionEngine.shared.judgmentShown = true }
                )
                .frame(maxHeight: .infinity, alignment: .top)

                // Voice mode, over everything: it hears, it works, and the
                // engine it drives is the same one the feed is reading.
                if voiceShown {
                    VoiceOverlay(onFinish: completeVoiceFlow)
                        .transition(.opacity)
                        .zIndex(10)
                }

                // The composer is ONE shared bar across both pages — it stays
                // put as you swipe, which is why it lives outside the pager.
                // `onSend` and `onVoiceMessage` are the two dead ends: the bar
                // behaves, nothing is delivered.
                bottomComposer(keyboardUp: geo.safeAreaInsets.bottom > 100)
                    .frame(maxHeight: .infinity, alignment: .bottom)

            }
            .sheet(isPresented: $profileShown) {
                ProfileSheet(
                    onHome: { withAnimation(DS.Motion.page) { page = .home } },
                    onChat: { showChat() },
                    onJudgment: { DecisionEngine.shared.judgmentShown = true }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $appsShown) {
                ConnectedAppsSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $notificationsShown) {
                NotificationsSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $photosShown) {
                PhotosSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $filesShown) {
                FilesSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
            }
            // The app's own camera, not a mock of one.
            .fullScreenCover(isPresented: $cameraShown) {
                CameraSheet(onDismiss: { cameraShown = false })
            }
            .sheet(isPresented: Bindable(DecisionEngine.shared).judgmentShown) {
                JudgmentSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
            }
                    }
    }

    // MARK: - Pager

    /// A content-only pager. Unlike a page-style TabView it never snapshots or
    /// moves the root backdrop during an interactive transition.
    private func pager(width: CGFloat, safeHeight: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            HomeScreen(
                onStartChat: { _ in showChat() },
                onOpenTask: { _ in },
                onOpenConnectedApps: {},
                onOpenAutomations: {},
                revealedDeleteTaskId: $revealedTaskDeleteId,
                scrolledUnderHeader: $scrolledUnderHeader,
                onReplyToSuggestion: { _ in },
                revealTarget: $revealTarget,
                onOpenUpdate: { _ in },
                onDismissKeyboard: { composerFocused = false },
                extraBottomInset: 0
            )
            .equatable()
            .frame(width: width)
            // Home never moves for the keyboard: it hosts no focusable field of
            // its own (its card drafts edit in a modal sheet).
            .ignoresSafeArea(.keyboard, edges: .bottom)

            ChatScreen(
                messages: chatLog.isEmpty ? messages : chatLog,
                // Seeded work + anything the live voice flow has since added.
                toolTrails: seededTrails.merging(chatTrails) { _, live in live },
                scrollTick: chatScrollTick,
                onDismissKeyboard: { composerFocused = false }
            )
            .frame(width: width)
            // Native safe-area mount: the transcript's keyboard ride IS the
            // system's own resize, so the frame must end at the safe-area line.
            .frame(height: safeHeight, alignment: .top)
        }
        .frame(width: width * 2, alignment: .topLeading)
        .offset(x: -CGFloat(page.rawValue) * width + dragX)
        .frame(width: width, alignment: .topLeading)
        // Horizontal-only clip: the off-screen page must never show during a
        // drag, but Home's ScrollView still overhangs this container vertically
        // (it expands up under the island and bleeds into the bottom safe
        // area), so a plain .clipped() would guillotine that full bleed.
        .clipShape(PagerHorizontalClip())
        .contentShape(Rectangle())
        .simultaneousGesture(pageDrag(width: width))
        // The moment the drag latches horizontal, the pages' vertical scrollers
        // stand down — one gesture, one design.
        .environment(\.pagerHorizontalDragActive, pagingHorizontally)
    }

    private func pageDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                // A slide-to-approve owns the horizontal axis while it is under
                // the finger.
                guard !DecisionEngine.shared.slideActive else { return }
                // Latch the axis once: a drag that started vertical belongs to
                // the page's own scroller and must never move the pager.
                if !pagingHorizontally {
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.2 else { return }
                    pagingHorizontally = true
                    composerFocused = false
                }
                // Rubber-band at the two ends — there is nothing beyond them.
                let raw = value.translation.width
                let atStart = page == .home && raw > 0
                let atEnd = page == .chat && raw < 0
                dragX = (atStart || atEnd) ? raw / 4 : raw
            }
            .onEnded { value in
                defer { pagingHorizontally = false }
                guard pagingHorizontally else { return }
                // Commit on distance OR on a flick, the way the app does.
                let travelled = value.translation.width
                let predicted = value.predictedEndTranslation.width
                let committed = abs(travelled) > width * 0.28 || abs(predicted) > width * 0.6
                var target = page
                if committed {
                    target = travelled < 0 ? .chat : .home
                }
                withAnimation(DS.Motion.page) {
                    page = target
                    dragX = 0
                }
            }
    }

    /// The composer names the card you are looking at. That is the whole edit
    /// system: one input that already has the context, instead of a pencil on
    /// every card and a mode to leave afterwards.
    private var composerPrompts: [String]? {
        let engine = DecisionEngine.shared
        guard page == .home else { return nil }
        let card = engine.asks.first { $0.id == engine.focusedID }
            ?? engine.asks.first { $0.phase == .asking }
        guard let card, card.phase == .asking else { return nil }
        // First name only: "Tell Iris to change Sarah's reply" is an
        // instruction; "SARAH WHITFIELD · MAIL" is a database row.
        let who = card.source
            .split(separator: "·").first?
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ").first
            .map { $0.capitalized }
        if card.draft != nil, let who {
            return ["Tell Iris to change \(who)'s reply"]
        }
        return ["Tell Iris to change this"]
    }

    /// The voice ask, made real: the engine books the table (the feed's
    /// Marufuku card runs and files itself), and the transcript records the
    /// turn, the tool trail, and the reply.
    private func completeVoiceFlow() {
        voiceShown = false
        if chatLog.isEmpty { chatLog = messages }
        let now = Date()
        let clock = now.formatted(.dateTime.hour().minute())
        chatLog.append(ChatMessage(
            text: "book the table too", isUser: true, time: clock, date: now,
            deliveredAt: now, readAt: now))

        let engine = DecisionEngine.shared
        if let table = engine.items.first(where: { $0.kind == "place" && $0.phase == .asking }) {
            engine.approve(table, always: false)
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1900))
            let reply = ChatMessage(
                text: "Booked — Marufuku at 7:45, two counter seats. The receipt is under Handled.",
                isUser: false,
                time: Date().formatted(.dateTime.hour().minute()),
                date: Date())
            chatLog.append(reply)
            chatTrails[reply.id] = ChatToolTrail(
                summary: "Worked 4s · 3 steps",
                steps: [
                    .init(logo: .resy, label: "Opened Resy", detail: "Marufuku · tonight"),
                    .init(logo: .resy, label: "Took the 7:45", detail: "2 seats · counter"),
                    .init(logo: .check, label: "Booked", detail: "conf #R-2847"),
                ])
            chatScrollTick += 1
            showChat()
        }
    }

    /// A Home affordance that wants the conversation — the chat starters, a
    /// card's "ask" — pages over instead of seeding a turn, since nothing can
    /// be sent here.
    private func showChat() {
        withAnimation(DS.Motion.page) { page = .chat }
        chatScrollTick += 1
    }

    // MARK: - Composer

    private func bottomComposer(keyboardUp: Bool) -> some View {
        VStack(spacing: 10) {
            PersonaComposer(
                draft: $draft,
                isFocused: $composerFocused,
                // Dead on purpose: the send lands nowhere. The bar still
                // clears its own draft so the gesture reads as complete.
                onSend: { draft = "" },
                // Dead on purpose: a released memo is dropped, not uploaded.
                onVoiceMessage: { url, _ in
                    try? FileManager.default.removeItem(at: url)
                },
                // Voice mode opens on the HOLD, not the release: the overlay
                // has to be up while you're still speaking. (It also means the
                // flow is reachable on a simulator, which has no microphone —
                // a release-triggered HUD would never once appear in Xcode.)
                onListeningBegan: { voiceShown = true },
                voiceHandledExternally: true,
                // Every one of these opens a real page.
                onCamera: { cameraShown = true },
                onPhotoLibrary: { photosShown = true },
                onAttachFile: { filesShown = true },
                quickActions: [
                    ComposerAttachMenuItem(id: "apps", icon: "square.grid.2x2.fill",
                                           label: "Apps") { appsShown = true },
                    ComposerAttachMenuItem(id: "notifications", icon: "bell.badge.fill",
                                           label: "Notifications") { notificationsShown = true },
                    ComposerAttachMenuItem(id: "judgment", icon: "brain",
                                           label: "Judgment") { DecisionEngine.shared.judgmentShown = true }
                ],
                placeholderPrompts: composerPrompts,
                assistantName: profile.assistantName
            )
            .padding(.horizontal, DS.Spacing.gutter)
        }
        .background(alignment: .bottom) {
            BottomComposerBackdrop()
                .frame(height: 200)
                .offset(y: 44)
                .allowsHitTesting(false)
        }
        .padding(.bottom, keyboardUp ? 8 : 2)
    }

    /// The + menu's upper shelf. Real rows drawn from the seeded store, each
    /// wired to nothing — the bloom opens and collapses as it does in the app.
    private var quickActions: [ComposerAttachMenuItem] {
        home.quickActions.map { action in
            ComposerAttachMenuItem(
                id: action.id.uuidString,
                icon: action.symbol,
                label: action.title,
                action: {}
            )
        }
    }
}

/// Clips the pager horizontally only, leaving vertical overhang alone.
private struct PagerHorizontalClip: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: -10_000, width: rect.width, height: 20_000))
    }
}

// MARK: - The work behind the seeded replies

extension DesignTrialHost {
    /// No trace boxes in the transcript. Chat is where you talk to Iris; the
    /// working out belongs on the card that is asking, behind its own control.
    var seededTrails: [UUID: ChatToolTrail] { [:] }
}

// MARK: - The fade that keeps content out of the chrome

/// A canvas-coloured fall-off under the floating header. Opaque through the
/// chrome, gone 44pt later — so a bubble or a card slides UNDER the wordmark
/// and disappears instead of printing through it.
struct HeaderScrim: View {
    let safeTop: CGFloat

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color.black, location: 0),
                .init(color: Color.black, location: 0.84),
                .init(color: Color.black.opacity(0.55), location: 0.93),
                .init(color: Color.black.opacity(0), location: 1)
            ],
            startPoint: .top, endPoint: .bottom
        )
        // Exactly the chrome's own height: any taller and it starts dimming
        // the greeting that sits directly beneath it.
        .frame(height: safeTop + 62)
        .ignoresSafeArea(edges: .top)
    }
}

/// HeaderScrim's opposite number, under the floating composer.
struct FooterScrim: View {
    let safeBottom: CGFloat

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color.black.opacity(0), location: 0),
                .init(color: Color.black.opacity(0.86), location: 0.28),
                .init(color: Color.black, location: 0.46),
                .init(color: Color.black, location: 1)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: safeBottom + 118)
    }
}
