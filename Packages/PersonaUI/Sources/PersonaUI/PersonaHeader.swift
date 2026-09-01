import PersonaDesign
import PersonaService
import SwiftUI

/// The floating top bar: menu, centred Persona wordmark, and Home/Chat toggle.
struct PersonaHeader: View {
    @Binding var page: PersonaPage
    /// Whether Home content has scrolled under the header — drives the
    /// wordmark's glass (see the wordmark comment below).
    var homeScrolled: Bool = false
    /// The user's profile picture (authenticated backend URL, auto-harvested at
    /// onboarding). When it loads, the menu button shows the face instead of
    /// the hamburger glyph; nil → the glyph. While a known photo is still
    /// loading the button holds a quiet placeholder disc — the glyph never
    /// flashes as a loading state.
    var avatarUrl: String? = nil
    /// Count of unseen assistant messages waiting in the main chat — drives the
    /// numbered badge on the chat toggle so a user on Home clearly notices there's
    /// something new (e.g. the get-to-know-you welcome for a brand-new user).
    /// Cleared to 0 once they open the chat.
    var chatUnreadCount: Int = 0
    /// New Home-feed arrivals (tasks/suggestions/updates) while the user is on
    /// the chat — same badge, mirrored onto the Home toggle.
    var homeUnreadCount: Int = 0
    /// Opens the same Iris menu the former smile/orb button opened.
    var onLogo: () -> Void = {}
    /// Opens Judgment — the standing rules. Lives in the header because the
    /// rules govern every page, not just Home's deck.
    var onJudgment: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    // Optional: design-preview rigs mount the header without ProfileStore —
    // they fall back to the product wordmark.
    @Environment(ProfileStore.self) private var profile: ProfileStore?

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Button(action: onLogo) {
                    // The avatar stays on BOTH pages — swiping to Chat must not
                    // drop the face.
                    HeaderMenuFace(avatarUrl: avatarUrl)
                        .frame(width: 42, height: 42)
                        // The frame's transparent padding isn't tappable on its
                        // own — without this only the glyph's strokes hit, and
                        // the 42pt circle misses most touches.
                        .contentShape(Circle())
                }
                .buttonStyle(.hapticTap)
                .smallGlassCircle()
                .accessibilityLabel("Open menu")
                .accessibilityIdentifier("header-menu")

                Spacer(minLength: 0)

                // Each half navigates to ITS page. It read as a toggle before,
                // so tapping Home while on Home threw you into Chat — a
                // control that punishes you for confirming where you are.
                HStack(spacing: 15) {
                    Button {
                        withAnimation(DS.Motion.page) { page = .home }
                    } label: {
                        toggleIcon(.home, symbol: "house.fill", size: 17, weight: .semibold)
                            .overlay(alignment: .topTrailing) {
                                if homeUnreadCount > 0, page != .home {
                                    ChatUnreadBadge(count: homeUnreadCount)
                                        .offset(x: 5, y: -4)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .animation(.snappy(duration: 0.24), value: homeUnreadCount)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.hapticTap)

                    Button {
                        withAnimation(DS.Motion.page) { page = .chat }
                    } label: {
                        toggleIcon(.chat, symbol: "text.bubble", size: 16, weight: .medium)
                            .overlay(alignment: .topTrailing) {
                                if chatUnreadCount > 0, page != .chat {
                                    ChatUnreadBadge(count: chatUnreadCount)
                                        .offset(x: 5, y: -4)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .animation(.snappy(duration: 0.24), value: chatUnreadCount)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.hapticTap)
                }
                .padding(.horizontal, 12)
                .frame(height: 42)
                .smallGlassCapsule()
                .accessibilityIdentifier("header-page-toggle")

                Button(action: onJudgment) {
                    Image(systemName: "brain")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Palette.inkMuted)
                        .frame(width: 42, height: 42)
                        .contentShape(Circle())
                }
                .buttonStyle(.hapticTap)
                .smallGlassCircle()
                .accessibilityLabel("Judgment")
                .padding(.leading, 8)
            }

            // The wordmark keeps its glass at all times. It used to appear
            // only once cards scrolled under it, which left the mark floating
            // bare and unmatched beside two capsules that were always there.
            // Now the chrome reads as one row of three glass elements.
            wordmark
                .padding(.horizontal, 14)
                .frame(height: 42)
                .modifier(WordmarkGlass(visible: true))
                .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, DS.Spacing.gutter)
        // Figma: the 42pt controls begin at y=71 on the 402pt canvas. The
        // additional 6pt brings the safe-area-relative system placement there.
        .padding(.top, 10)
    }

    /// Longest custom assistant name the header renders. Names may be up to 24
    /// characters (NameRules.assistantName); beyond this the wordmark crowds
    /// the menu button and the page toggle, so it falls back to the brand.
    private static let maxWordmarkName = 12

    /// The name the wordmark draws: the user's chosen one when it fits, the
    /// product brand otherwise — including when no profile is in scope (design
    /// rigs) or the name hasn't loaded yet.
    private var wordmarkName: String {
        let name = (profile?.assistantName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= Self.maxWordmarkName else {
            return ProfileStore.defaultAssistantName
        }
        return name
    }

    private var wordmark: some View {
        HStack(spacing: 4) {
            // The mark's "line art" is really black shapes with OFF-WHITE
            // interior paths on top (PersonaMark.svg: fill=#FAFAF9) — template
            // mode tints every non-transparent pixel, so the whole logo fills
            // into a solid silhouette (a build regression). Light mode
            // therefore keeps the original artwork, and only dark templates it
            // near-white so the mark doesn't vanish into the near-black canvas.
            PersonaAsset.image("PersonaMark")
                .renderingMode(colorScheme == .dark ? .template : .original)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 28, height: 24)
                .foregroundStyle(Color(light: 0x030303, dark: 0xF2F2F4))
            // The user's chosen name for their persona, not the product
            // wordmark — whatever they renamed her to.
            // Long names blow out the 42pt bar, so past `maxWordmarkName` the
            // header reverts to the product wordmark.
            Text(wordmarkName)
                .font(.system(size: 18, weight: .semibold))
                .tracking(-0.27)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(light: 0x030303, dark: 0xF2F2F4),
                            Color(light: 0x696969, dark: 0xA6A6AE),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }

    private func toggleIcon(_ target: PersonaPage, symbol: String, size: CGFloat, weight: Font.Weight) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(page == target ? DS.Palette.ink : DS.Palette.ink.opacity(0.48))
            .frame(width: 21, height: 21)
    }
}

/// Numbered unread badge on the chat toggle. Wears EXACTLY the transcript's
/// jump-to-latest badge language (iMessage-red capsule, white bold count) so
/// the two unread signals read as one system — the old accent-blue ring/halo
/// version looked like a different app.
private struct ChatUnreadBadge: View {
    let count: Int

    private var label: String { count > 9 ? "9+" : "\(count)" }

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .monospacedDigit()
            .lineLimit(1)
            // The badge overlays a 21pt icon frame, so the overlay proposes only
            // ~21pt down; after the horizontal padding the Text is offered ~11pt —
            // enough for one digit but not "9+" or two digits, which SwiftUI then
            // truncates to "…". fixedSize pins the Text to its intrinsic width so
            // the count is always fully drawn regardless of the small host frame.
            .fixedSize()
            .padding(.horizontal, 4)
            .frame(minWidth: 14, minHeight: 14)
            .background(Color(hex: 0xFF3B30), in: Capsule(style: .continuous))
            .transition(.scale.combined(with: .opacity))
    }
}

/// Fades the wordmark's glass capsule in/out around the logo without ever
/// cross-fading the mark. The wordmark sits INSIDE the glass element (not
/// over a background glass layer): interactive liquid glass scales the whole
/// element on press, and a background-layer capsule left the mark and text
/// standing still while the glass stretched under them.
/// Visibility toggles via `isEnabled` — same identity, no branch swap, so
/// the mark still never cross-fades.
private struct WordmarkGlass: ViewModifier {
    let visible: Bool

    func body(content: Content) -> some View {
        content
            .smallGlassCapsule(isEnabled: visible)
            .animation(.snappy(duration: 0.22), value: visible)
    }
}

/// The menu button's face: the user's avatar photo when one loads, the
/// hamburger glyph when the profile has no photo at all. Loads through the
/// same authorized loader + memory/disk cache the contact avatars use
/// (bearer for backend hosts). While a KNOWN photo is loading, a quiet
/// placeholder disc holds the slot — the glyph is never a loading state
/// (beta reports: glyph ⇄ face flicker on cold open and page swipes).
private struct HeaderMenuFace: View {
    var avatarUrl: String?

    @State private var image: Image?
    @Environment(\.authorizedImageLoader) private var authorizedImageLoader

    init(avatarUrl: String?) {
        self.avatarUrl = avatarUrl
        // Seed the avatar SYNCHRONOUSLY from the cache so a recreated header
        // shows the face from its first frame. The chrome is rebuilt via an
        // A trial-only lane: an "asset:" avatar renders from the design
        // bundle, so the face never depends on the network this build
        // doesn't really have.
        // `.id(...)` swap on every Iris-menu mount/unmount (the stale-presentation
        // safety), which resets this @State to nil — the async `.task` cache
        // read then flashed the hamburger glyph for a frame and morphed the
        // avatar back in on every menu round-trip ("profile image jumps after
        // visiting chat history"). A hit here renders the face with no morph.
        #if canImport(UIKit)
            if let raw = avatarUrl, !raw.isEmpty,
               let cached = AvatarImageCache.shared.image(for: "header-avatar:\(raw)") {
                _image = State(initialValue: Image(uiImage: cached))
            }
        #endif
    }

    var body: some View {
        Group {
            if let asset = avatarUrl, asset.hasPrefix("asset:") {
                PersonaAsset.image(String(asset.dropFirst("asset:".count)))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(Circle())
            } else if let image {
                // Full-bleed in the 42pt disc: the photo IS the button — no
                // visible glass rim or stroke around it.
                image
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(Circle())
                    .transition(.scale(scale: 0.55).combined(with: .opacity))
            } else if avatarUrl?.isEmpty == false {
                // The profile HAS a photo — it just isn't decoded yet (first-ever
                // download, or the cache was evicted). A quiet disc holds the slot
                // so the loading state never flashes the hamburger glyph
                // (beta-reported flicker: glyph ⇄ face on open and page swipes);
                // the photo fades in over it with no glyph morph.
                Circle()
                    .fill(DS.Palette.ink.opacity(0.08))
                    .frame(width: 42, height: 42)
                    .transition(.opacity)
            } else {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DS.Palette.ink.opacity(0.46))
                    .transition(.scale(scale: 1.35).combined(with: .opacity))
            }
        }
        // The face morphs between glyph and avatar when the photo loads (or
        // the account signs out) instead of hard-swapping. avatarUrl drives
        // the glyph ⇄ placeholder branch, so it animates too.
        .animation(DS.Motion.page, value: image != nil)
        .animation(DS.Motion.page, value: avatarUrl)
        .task(id: avatarUrl) { await load() }
    }

    private func load() async {
        guard let raw = avatarUrl, !raw.isEmpty, let url = URL(string: raw) else {
            image = nil
            return
        }
        #if canImport(UIKit)
            let key = "header-avatar:\(raw)"
            if let cached = AvatarImageCache.shared.image(for: key) {
                image = Image(uiImage: cached)
                return
            }
            guard let authorizedImageLoader else { return }
            do {
                let data = try await authorizedImageLoader(url)
                guard let uiImage = UIImage(data: data) else { return }
                // Hand over the original encoded bytes so the cache's disk
                // mirror keeps the face across relaunches — memory-only stores
                // made every cold start re-download the avatar, flashing the
                // fallback while the network round-trip ran.
                AvatarImageCache.shared.store(uiImage, data: data, for: key)
                image = Image(uiImage: uiImage)
            } catch {
                // Transient failure → keep the glyph this pass; the next appear retries.
            }
        #endif
    }
}
