import PersonaCore
import PersonaDesign
import PersonaService
import SwiftUI

/// The design trial's whole app: the REAL Home page, the REAL floating header
/// and the REAL composer bar, over stores that were pinned to dummy data and
/// never talk to a backend.
///
/// This file is the ONLY addition to the ported `PersonaUI` — it exists because
/// `HomeScreen`, `PersonaHeader` and `PersonaComposer` are all internal to the
/// package, so the app target can't mount them directly. Everything it draws is
/// the shipping view code, unmodified; it is a thinner `PersonaRootView` with
/// the pager, the Iris menu, the chat page and every network-bound handler
/// removed.
public struct DesignTrialHost: View {
    public init() {}

    @Environment(HomeStore.self) private var home
    @Environment(ProfileStore.self) private var profile

    /// The header's Home/Chat toggle still moves (it's a real control), but
    /// there is no chat page to page to — the binding just parks back on Home.
    @State private var page: PersonaPage = .home
    /// Home's scroll-under signal, which ramps the wordmark's glass exactly as
    /// it does in the real app.
    @State private var scrolledUnderHeader = false
    /// The one Stop-menu slot Home's task cards share.
    @State private var revealedTaskDeleteId: AnyHashable?
    /// A card asking Home to scroll it into view (a card's own reveal).
    @State private var revealTarget: HomeRevealTarget?

    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                SharedAppBackground()
                    .ignoresSafeArea()

                // The page itself, mounted exactly as the root pager mounts it:
                // native safe-area height, opted out of the keyboard (Home
                // hosts no focusable field of its own).
                HomeScreen(
                    onStartChat: { _ in },
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
                .frame(width: geo.size.width)
                .ignoresSafeArea(.keyboard, edges: .bottom)

                // The floating glass header rides on top of the feed.
                PersonaHeader(
                    page: $page,
                    homeScrolled: scrolledUnderHeader,
                    avatarUrl: profile.avatarUrl
                )
                .frame(maxHeight: .infinity, alignment: .top)

                // The composer, bottom-pinned at the safe-area line, with the
                // same fade slab glued to it. `onSend` and `onVoiceMessage` are
                // the two dead ends: the bar behaves, nothing is delivered.
                bottomComposer(keyboardUp: geo.safeAreaInsets.bottom > 100)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        // The header's toggle is live chrome, but Chat doesn't exist here —
        // let it flip, then settle back so the icon never sticks on Chat.
        .onChange(of: page) { _, newValue in
            guard newValue != .home else { return }
            withAnimation(DS.Motion.page) { page = .home }
        }
    }

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
