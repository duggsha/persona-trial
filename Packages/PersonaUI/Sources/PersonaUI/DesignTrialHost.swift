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
                SharedAppBackground()
                    .ignoresSafeArea()

                pager(width: geo.size.width, safeHeight: geo.size.height)

                // The floating glass header rides on top of both pages.
                PersonaHeader(
                    page: $page,
                    homeScrolled: page == .home && scrolledUnderHeader,
                    avatarUrl: profile.avatarUrl
                )
                .frame(maxHeight: .infinity, alignment: .top)

                // The composer is ONE shared bar across both pages — it stays
                // put as you swipe, which is why it lives outside the pager.
                // `onSend` and `onVoiceMessage` are the two dead ends: the bar
                // behaves, nothing is delivered.
                bottomComposer(keyboardUp: geo.safeAreaInsets.bottom > 100)
                    .frame(maxHeight: .infinity, alignment: .bottom)
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
                messages: messages,
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
                onVoiceMessage: { url, _ in try? FileManager.default.removeItem(at: url) },
                onCamera: {},
                onPhotoLibrary: {},
                onAttachFile: {},
                quickActions: quickActions,
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
