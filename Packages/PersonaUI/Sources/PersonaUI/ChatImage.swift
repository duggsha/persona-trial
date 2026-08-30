import PersonaDesign
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// The transcript photo tile's square side, in points — the single tiles and
/// the deck all render at this size, and remote decodes cache their
/// downsampled variant under a key derived from it (see CachedRemoteImage).
let chatPhotoTileSide: CGFloat = 210

#if canImport(UIKit)
    /// Decodes photo bytes for display, downsampled so the SHORTER side lands
    /// at `targetSide` points (screen-scaled) when the source is larger. A
    /// 210pt tile never needs a 12-megapixel texture — the deck scrub
    /// transforms these layers on every touch sample, and full-resolution
    /// cards are what made it drop frames. `nil` keeps the full-size decode
    /// (the fullscreen viewer, which zooms). Returns nil only when the bytes
    /// aren't an image.
    @MainActor
    func decodePhotoForDisplay(_ data: Data, targetSide: CGFloat?) async -> UIImage? {
        guard let raw = UIImage(data: data) else { return nil }
        let pixelSide = (targetSide ?? 0) * UIScreen.main.scale
        let shortSide = min(raw.size.width * raw.scale, raw.size.height * raw.scale)
        guard targetSide != nil, shortSide > pixelSide else {
            let full = await raw.byPreparingForDisplay()
            return full ?? raw
        }
        // Short side → pixelSide keeps a .fill render sharp (an aspect-FIT
        // decode into a square would leave the fill upscaling the long axis).
        let ratio = pixelSide / shortSide
        let thumbSize = CGSize(
            width: raw.size.width * raw.scale * ratio,
            height: raw.size.height * raw.scale * ratio
        )
        if let thumb = await raw.byPreparingThumbnail(ofSize: thumbSize) { return thumb }
        let full = await raw.byPreparingForDisplay()
        return full ?? raw
    }

    /// The best decoded pixels in cache for a remote chat photo — the
    /// full-size viewer decode when it exists, else the transcript tile's
    /// downsampled one. The copy/share/save fallbacks read this: "what's on
    /// screen beats nothing", and what's on screen may only be the tile.
    @MainActor
    func cachedChatPhotoPixels(forRemotePath path: String) -> UIImage? {
        AvatarImageCache.shared.image(for: "cri:\(path)")
            ?? AvatarImageCache.shared.image(for: "cri:\(path)@\(Int(chatPhotoTileSide))")
    }
#endif

/// Renders attached JPEG data as an image (cross-platform-safe). Decoding is
/// done off the main thread (`byPreparingForDisplay`) so a photo never stalls
/// scrolling, and the decoded image is held in state so it isn't re-decoded.
struct ChatImageData: View {
    let data: Data
    /// Downsample ceiling in points for the decoded texture's shorter side —
    /// set by tile-sized hosts; nil decodes full-size (the viewer).
    var targetSide: CGFloat?
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                image.resizable()
            } else {
                placeholder
            }
        }
        .task(id: data) { await decode() }
    }

    private func decode() async {
        #if canImport(UIKit)
            guard let prepared = await decodePhotoForDisplay(data, targetSide: targetSide) else { return }
            image = Image(uiImage: prepared)
        #endif
    }

    private var placeholder: some View {
        Color(light: 0x000000, dark: 0xFFFFFF, lightOpacity: 0.08, darkOpacity: 0.08)
    }
}

/// The small thumbnail floated above the composer for a queued photo.
struct ChatAttachmentThumbnail: View {
    let data: Data

    var body: some View {
        ChatImageData(data: data)
            .scaledToFill()
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DS.Palette.card.opacity(0.6), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }
}

/// A remote image cached in the shared `AvatarImageCache` (NSCache) and decoded
/// off the main thread, so a view scrolling back into a `LazyVStack` is a cache
/// hit — no re-download, no main-thread re-decode (unlike `AsyncImage`).
/// `placeholder` shows while loading AND on failure.
struct CachedRemoteImage<Content: View, Placeholder: View>: View {
    let url: String?
    /// Cross-fade placeholder → photo when the image arrives over the NETWORK
    /// (a cache hit still lands instantly — no flash on scroll-back).
    var fadeIn = false
    /// Downsample ceiling in points for the decoded texture's shorter side.
    /// Tile-sized hosts MUST set it — a transcript tile rendering a
    /// full-resolution decode is what made the photo deck scrub drop frames.
    /// Each size caches under its own key; nil is the full-size decode (the
    /// fullscreen viewer, which zooms).
    var targetSide: CGFloat?
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: Image?
    @Environment(\.authorizedImageLoader) private var authorizedImageLoader

    var body: some View {
        Group {
            if let image {
                content(image)
                    .transition(fadeIn ? .opacity : .identity)
            } else {
                placeholder()
                    .transition(fadeIn ? .opacity : .identity)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        #if canImport(UIKit)
            guard let url, let parsed = URL(string: url) else { return }
            // Negative results (404/undecodable) key by URL alone — a missing
            // asset is missing at every size.
            let baseKey = "cri:\(url)"
            let key = targetSide.map { "\(baseKey)@\(Int($0))" } ?? baseKey
            if let cached = AvatarImageCache.shared.image(for: key) {
                image = Image(uiImage: cached)
                return
            }
            if AvatarImageCache.shared.isKnownEmpty(baseKey) { return }
            // Full-size request with only the tile's thumb cached (the viewer
            // opening out of a transcript tile): paint the thumb NOW and let
            // the full decode sharpen it in place — pixels immediately, like
            // iMessage, instead of a spinner over black.
            if targetSide == nil, image == nil,
               let thumb = AvatarImageCache.shared.image(for: "\(baseKey)@\(Int(chatPhotoTileSide))") {
                image = Image(uiImage: thumb)
            }
            do {
                let data: Data
                // A `data:` URL is self-contained (QA mocks) — never routed
                // through the authorized loader, which treats any hostless URL
                // as a backend-relative path.
                if let authorizedImageLoader, parsed.scheme != "data" {
                    data = try await authorizedImageLoader(parsed)
                } else {
                    let (raw, response) = try await URLSession.shared.data(from: parsed)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        if http.statusCode == 404 || http.statusCode == 410 {
                            AvatarImageCache.shared.storeEmpty(baseKey)
                        }
                        return
                    }
                    data = raw
                }
                guard !Task.isCancelled else { return }
                guard let prepared = await decodePhotoForDisplay(data, targetSide: targetSide) else {
                    AvatarImageCache.shared.storeEmpty(baseKey)
                    return
                }
                guard !Task.isCancelled else { return }
                AvatarImageCache.shared.store(prepared, for: key)
                if fadeIn {
                    withAnimation(.smooth(duration: 0.4)) { image = Image(uiImage: prepared) }
                } else {
                    image = Image(uiImage: prepared)
                }
            } catch {
                // Transient — keep the placeholder, retry next appear.
            }
        #endif
    }
}

/// The loading placeholder for a chat photo: the neutral surface tile with a
/// travelling highlight (ShimmerBar's language, tile-shaped) — reads as "a
/// photo is landing here", not a dead grey block.
struct ShimmerTile: View {
    @State private var phase: CGFloat = -0.7

    var body: some View {
        DS.Palette.surface.opacity(0.7)
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.55), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: geo.size.width * phase)
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    phase = 1.3
                }
            }
    }
}

/// One photo the fullscreen viewer can show: a persisted backend asset path,
/// or the local bytes of a just-sent photo that hasn't round-tripped yet.
enum ChatViewerPhoto {
    case remote(path: String)
    case local(data: Data)

    /// Stable within the session — keys the cover identity and the
    /// zoom-transition source (must match the tapped tile's source id).
    var id: String {
        switch self {
        case let .remote(path): path
        case let .local(data): "local-\(data.hashValue)"
        }
    }
}

/// Fullscreen photo viewer for a chat message's photos: swipe sideways to page
/// between sibling photos, pinch/double-tap zoom, drag to pan when zoomed,
/// swipe down to dismiss when not, and an optional Reply pill that
/// quote-replies to the photo's message. Presented from the tapped tile via a
/// zoom transition so the photo grows out of its bubble.
struct ChatPhotoViewer: View {
    let photos: [ChatViewerPhoto]
    var onReply: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    /// The visible page. The pager is a MANUAL offset HStack, not a paging
    /// ScrollView / page-style TabView: on this SDK the TabView pages
    /// vertically, and the paging ScrollView's position binding churned
    /// against the dismissing cover until the main thread starved (the
    /// harness-verified freeze). A plain offset has no machinery to fight.
    @State private var index: Int
    /// Live horizontal page drag while unzoomed — follows the finger, then
    /// the settle animates via `index`.
    @GestureState private var pageDrag: CGFloat = 0
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var drag: CGSize = .zero
    /// Vertical pull while NOT zoomed — drives the dismiss slide + dim.
    @State private var pull: CGFloat = 0
    /// Horizontal follow during a dismiss pull, so the photo tracks the finger
    /// instead of sliding on a rail.
    @State private var pullX: CGFloat = 0
    /// A drag commits to paging or pulling at its first event and stays there —
    /// flip-flopping dominance mid-drag snapped the photo between the two.
    private enum DragMode { case undecided, page, pull }
    @State private var dragMode: DragMode = .undecided
    /// The in-view goodbye for the pager (which can't run a cover transition —
    /// see `closeViewer`): fades the backdrop/chrome while the photo slides off
    /// (a pull-commit) or fades/shrinks in place (the close button).
    @State private var closing = false
    @State private var closingSlide = false
    /// Pages whose photo was saved to the camera roll this presentation —
    /// their save button rests as a checkmark (saving twice would duplicate).
    @State private var savedIndices: Set<Int> = []
    /// iMessage-style chrome: the counter/close/save/reply overlays start
    /// visible and a single tap on the photo toggles them away for a clean
    /// look (double-tap stays zoom — the single tap waits it out).
    @State private var chromeVisible = true
    /// Same authorized fetch the tiles render through — Save needs the real
    /// bytes for a backend-relative asset path.
    @Environment(\.authorizedImageLoader) private var imageLoader

    init(photos: [ChatViewerPhoto], initialIndex: Int = 0, onReply: (() -> Void)? = nil) {
        self.photos = photos
        self.onReply = onReply
        _index = State(initialValue: min(max(initialIndex, 0), max(photos.count - 1, 0)))
    }

    /// The pager's cover dismissal stays transition-free: a removal transition
    /// on the multi-photo pager repeatedly froze mid-flight with the main
    /// thread unresponsive. Instead the goodbye is animated IN-VIEW (plain
    /// offset + opacity on static frames — nothing relayouts): the photo
    /// slides off along the pull direction while the backdrop fades, and only
    /// then does the cover drop, with animations disabled. A single-photo
    /// viewer keeps the animated zoom-back to its bubble tile.
    private func closeViewer(slide: CGFloat? = nil) {
        if photos.count > 1 {
            guard !closing else { return }
            closingSlide = slide != nil
            withAnimation(.smooth(duration: 0.28)) {
                closing = true
                if let slide {
                    pull = slide * pageSize.height * 0.9
                    pullX *= 2.5
                }
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 280_000_000)
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { dismiss() }
            }
        } else {
            dismiss()
        }
    }

    /// Fullscreen page size, frozen at presentation (see the pager comment).
    private let pageSize: CGSize = {
        #if canImport(UIKit)
            return UIScreen.main.bounds.size
        #else
            return CGSize(width: 400, height: 800)
        #endif
    }()

    private var zoomed: Bool { scale > 1.02 }

    /// The chrome's floor. Was `DS.Palette.card.opacity(0.18)` — card is WHITE
    /// in light mode, so over a white photo (documents, screenshots) the
    /// white-glyph chrome dissolved completely.
    /// A fixed dark scrim reads on ANY photo and matches the viewer's black
    /// backdrop; it deliberately ignores the app theme — the photo behind it
    /// is the only thing that matters here.
    private static let chromeScrim = Color.black.opacity(0.42)

    /// The cover's content reaches the physical screen top, so overlay chrome
    /// must dodge the sensor housing itself — the real window inset, not a
    /// guessed constant (island heights differ across devices).
    private var topInset: CGFloat {
        #if canImport(UIKit)
            let inset = UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.top }
                .max() ?? 0
            return max(inset, 20)
        #else
            return 20
        #endif
    }

    /// 0 → 1 over the first ~260pt of dismiss pull — drives the dim, the
    /// shrink, and the chrome fade as one continuous gesture.
    private var pullProgress: Double {
        min(Double(abs(pull)) / 260.0, 1)
    }

    /// Chrome shows only at rest: hidden by the user's tap, fading out over
    /// the first stretch of a dismiss pull (not hard-cutting on its first
    /// pixel), and gone once the goodbye is running.
    private var chromeOpacity: Double {
        guard chromeVisible, !closing else { return 0 }
        return max(1 - Double(abs(pull)) / 80.0, 0)
    }

    /// Dim the backdrop as the dismiss pull grows, revealing the chat behind
    /// (the cover's presentation background is clear) — the photo "lets go".
    private var backgroundOpacity: Double {
        closing ? 0 : 1 - pullProgress * 0.7
    }

    /// The photo shrinks slightly under the finger as the pull grows — the
    /// Photos-app cue that release will drop it. A button-close (no slide)
    /// shrinks it a touch further as it fades in place.
    private var pullScale: CGFloat {
        closing && !closingSlide ? 0.88 : 1 - CGFloat(pullProgress) * 0.15
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            // All pages side by side (a message carries a handful at most),
            // slid by a plain offset. Pages are STATIC screen-size frames so
            // nothing relayouts during presentation/dismissal.
            HStack(spacing: 0) {
                ForEach(Array(photos.enumerated()), id: \.offset) { i, photo in
                    photoPage(photo, current: i == index)
                        .frame(width: pageSize.width, height: pageSize.height)
                        // A page renders inside ITS slot only. Without this a
                        // zoomed photo (2.5× a screen wide) paints across its
                        // neighbors' slots — visible the moment anything slides.
                        .clipped()
                }
            }
            .frame(width: pageSize.width, height: pageSize.height, alignment: .leading)
            .offset(x: -CGFloat(index) * pageSize.width + pageDrag)
            .animation(.smooth(duration: 0.3), value: index)
            .ignoresSafeArea()
        }
        // Zoom/pan/pull state belongs to a single photo — paging away resets.
        .onChange(of: index) {
            if scale != 1 { scale = 1 }
            if offset != .zero { offset = .zero }
            if pull != 0 { pull = 0 }
            if pullX != 0 { pullX = 0 }
        }
        .gesture(containerDrag)
        .overlay(alignment: .top) {
            if photos.count > 1 {
                Text("\(index + 1) of \(photos.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Self.chromeScrim, in: Capsule(style: .continuous))
                    .padding(.top, topInset + 6)
                    .opacity(chromeOpacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                closeViewer()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Self.chromeScrim, in: Circle())
            }
            .accessibilityIdentifier("photo-viewer-close")
            .padding(.top, topInset + 2)
            .padding(.trailing, 16)
            .opacity(chromeOpacity)
        }
        .overlay(alignment: .topLeading) {
            // Save + share — same chrome as close, opposite corner. Absent
            // only for photos that already live in the device library (`ph:`
            // refs): saving those would file a photo where it already lives.
            #if canImport(UIKit)
                if let photo = actionablePhoto {
                    let saved = savedIndices.contains(index)
                    HStack(spacing: 10) {
                        Button {
                            guard !saved else { return }
                            // The checkmark only lands on a CONFIRMED write —
                            // a denied add-only permission must not fake "Saved".
                            //
                            // Through ChatMediaActions, never a `performChanges`
                            // of our own: every isolation rule that keeps this
                            // from trapping lives in one place there, and the
                            // viewer shares its permission flow and its "already
                            // saved" registry with the long-press menu.
                            let photoIndex = index
                            Task { @MainActor in
                                guard await ChatMediaActions.saveToPhotos(photo, loader: imageLoader)
                                else { return }
                                withAnimation(.smooth(duration: 0.25)) {
                                    _ = savedIndices.insert(photoIndex)
                                }
                            }
                        } label: {
                            Image(systemName: saved ? "checkmark" : "square.and.arrow.down")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(Self.chromeScrim, in: Circle())
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .accessibilityIdentifier("photo-viewer-save")
                        .accessibilityLabel(saved ? "Saved" : "Save to camera roll")

                        Button {
                            // Same path as the transcript's long-press Share:
                            // it fetches the real bytes (falling back to the
                            // pixels on screen) and presents into the app's own
                            // window — the presentation fix from, which
                            // the viewer's private copy never got.
                            ChatMediaActions.share(photo, loader: imageLoader)
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(Self.chromeScrim, in: Circle())
                        }
                        .accessibilityIdentifier("photo-viewer-share")
                        .accessibilityLabel("Share photo")
                    }
                    .padding(.top, topInset + 2)
                    .padding(.leading, 16)
                    .opacity(chromeOpacity)
                }
            #endif
        }
        .overlay(alignment: .bottom) {
            if let onReply {
                Button {
                    closeViewer()
                    onReply()
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Self.chromeScrim, in: Capsule(style: .continuous))
                }
                .padding(.bottom, 24)
                .opacity(chromeOpacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: chromeVisible)
        .statusBarHidden()
    }

    /// The visible page, when Save/Share make sense for it — which is every
    /// photo except a device-library `ph:` ref (already in the camera roll).
    ///
    /// This deliberately does NOT ask whether the pixels are decoded yet. It
    /// used to hand back `AvatarImageCache`'s entry, which meant the buttons
    /// were missing for any page whose image wasn't cached — and because an
    /// NSCache read is not observable, nothing re-rendered the chrome when the
    /// image did land, so they never appeared at all. Only the photo you
    /// tapped in from (already decoded by its tile) reliably had them:
    /// design's "Save and Share show on the first image and vanish on the
    /// next ones", build 245. The bytes are resolved at TAP time instead, by
    /// ChatMediaActions — which fetches through the authorized loader and
    /// falls back to the cached pixels.
    private var actionablePhoto: ChatViewerPhoto? {
        let photo = photos[index]
        if case let .remote(path) = photo,
           PhotoLibraryImageView.localIdentifier(fromAssetPath: path) != nil {
            return nil
        }
        return photo
    }

    /// One pager page: the photo with the zoom/pan/dismiss gestures. The
    /// gesture state is shared across pages, but only the visible page can
    /// receive touches, and paging away resets it (see `onChange` above).
    /// `current` gates the TRANSFORMS too: the shared scale/offset used to
    /// apply to every page, so a pinch also blew up the NEIGHBOR around its
    /// own center and its edge slid onto screen mid-zoom (design report, — "zooming bleeds in the next image").
    private func photoPage(_ photo: ChatViewerPhoto, current: Bool) -> some View {
        Group {
            switch photo {
            case let .remote(path):
                if let localId = PhotoLibraryImageView.localIdentifier(fromAssetPath: path) {
                    // Device-library photo (`ph:` ref) — full-quality local load.
                    PhotoLibraryImageView(localIdentifier: localId, targetSide: 1200)
                        .aspectRatio(contentMode: .fit)
                } else {
                    CachedRemoteImage(url: path, fadeIn: true) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView().tint(.white)
                    }
                }
            case let .local(data):
                // A just-sent photo's bytes are already in memory — no fetch.
                ChatImageData(data: data)
                    .scaledToFit()
            }
        }
        .scaleEffect(current ? max(scale * pinch, 0.8) * pullScale : 1)
        .opacity(current && closing && !closingSlide ? 0 : 1)
        .offset(
            x: current ? offset.width + drag.width + pullX : 0,
            y: current ? offset.height + drag.height + pull : 0
        )
        // Full-page hit area: the chrome toggle (and double-tap zoom) answer
        // anywhere on the page, not just on the fitted photo's pixels.
        .frame(width: pageSize.width, height: pageSize.height)
        .contentShape(Rectangle())
        // The pan exists ONLY while zoomed (paging is disabled then, so there
        // is no fight). Unzoomed it must be fully detached: ANY DragGesture on
        // the photo — even a simultaneous one — starves the pager's pan and
        // page swipes die (same trap as the root pager's bubbles). The
        // unzoomed dismiss-pull lives on the container instead.
        .gesture(pan, including: zoomed ? .all : .subviews)
        .simultaneousGesture(magnify)
        .onTapGesture(count: 2) {
            withAnimation(.smooth(duration: 0.3)) {
                if zoomed {
                    scale = 1
                    offset = .zero
                } else {
                    scale = 2.5
                }
            }
        }
        // Single tap toggles the chrome, iMessage-style. Attached AFTER the
        // double-tap so SwiftUI holds it back until a second tap is ruled out
        // — a double-tap zoom never also flips the chrome.
        .onTapGesture {
            chromeVisible.toggle()
        }
    }

    private var magnify: some Gesture {
        MagnificationGesture()
            .updating($pinch) { value, state, _ in
                state = value
            }
            .onEnded { value in
                withAnimation(.smooth(duration: 0.25)) {
                    scale = min(max(scale * value, 1), 4)
                    if scale <= 1.02 { offset = .zero }
                }
            }
    }

    /// Pans the photo while zoomed. Never installed unzoomed (see photoPage).
    private var pan: some Gesture {
        DragGesture()
            .updating($drag) { value, state, _ in
                if scale > 1.02 { state = value.translation }
            }
            .onEnded { value in
                guard scale > 1.02 else { return }
                offset = CGSize(
                    width: offset.width + value.translation.width,
                    height: offset.height + value.translation.height
                )
            }
    }

    /// The container drag while unzoomed: it commits to ONE job at its first
    /// event — horizontally-dominant pages between photos (follows the finger,
    /// settles on release with a flick allowance), vertically-dominant drives
    /// the dismiss pull — and keeps that job for the whole drag, so a finger
    /// that wanders diagonally never snaps the photo between modes. The pull
    /// follows the finger on both axes and a flick past the velocity gate
    /// dismisses even from a short pull. While zoomed the image's own pan owns
    /// dragging and this gesture stands down.
    private var containerDrag: some Gesture {
        DragGesture(minimumDistance: 15)
            .updating($pageDrag) { value, state, _ in
                guard scale <= 1.02 else { return }
                let horizontal = abs(value.translation.width) > abs(value.translation.height)
                if dragMode == .page || (dragMode == .undecided && horizontal) {
                    state = value.translation.width
                }
            }
            .onChanged { value in
                guard !zoomed, !closing else { return }
                if dragMode == .undecided {
                    dragMode = abs(value.translation.width) > abs(value.translation.height) ? .page : .pull
                }
                if dragMode == .pull {
                    pull = value.translation.height
                    pullX = value.translation.width
                }
            }
            .onEnded { value in
                let mode = dragMode
                dragMode = .undecided
                guard !zoomed, !closing else { return }
                switch mode {
                case .pull:
                    let dy = value.translation.height
                    let flick = value.predictedEndTranslation.height
                    if abs(dy) > 90 || abs(flick) > 240 {
                        closeViewer(slide: (flick == 0 ? dy : flick) >= 0 ? 1 : -1)
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            pull = 0
                            pullX = 0
                        }
                    }
                case .page, .undecided:
                    var next = index
                    let dx = value.translation.width
                    let flick = value.predictedEndTranslation.width
                    if dx < -pageSize.width * 0.25 || flick < -pageSize.width * 0.5 {
                        next += 1
                    } else if dx > pageSize.width * 0.25 || flick > pageSize.width * 0.5 {
                        next -= 1
                    }
                    index = min(max(next, 0), photos.count - 1)
                }
            }
    }
}

/// A small leading thumbnail for chat cards (selection options, restaurants,
/// flights, products…): a remote photo shown .fill (or .fit on a tinted tile for
/// transparent PNGs, via `illustration`), else a fallback SF Symbol glyph.
///
/// NOT `AsyncImage`: that re-downloads AND re-decodes on the main thread every
/// time a row scrolls back into the `LazyVStack`, which stutters a card-heavy
/// transcript. This holds the decoded image in the shared `AvatarImageCache`
/// (NSCache) and decodes off-main (`byPreparingForDisplay`), so a re-appearance
/// is a cache hit with no network and no main-thread decode.
struct ChatCardThumbnail: View {
    let imageURL: String?
    let systemImage: String?
    var illustration = false
    var size: CGFloat = 44
    /// Fill mode: the image stretches to fill its parent frame (the caller sets
    /// the frame, e.g. a full-width fixed-height media header) instead of the
    /// fixed `size` square. `size` still drives the placeholder glyph scale.
    var fill = false
    /// Corner radius of the clip + hairline. A full-bleed media header clips to
    /// its tile's corner; the default keeps the small-thumbnail look.
    var cornerRadius: CGFloat = 10
    /// Draw the hairline stroke. Off for a full-bleed header inside a card that
    /// already carries its own border.
    var stroke = true
    /// No tile at all — clear background, no stroke: the image floats naked on
    /// the card (flight rows show the airline wordmark this way; the tinted
    /// plate read as a card-inside-a-card).
    var plain = false

    @State private var image: Image?
    @State private var failed = false
    @Environment(\.authorizedImageLoader) private var authorizedImageLoader

    var body: some View {
        Group {
            if let image {
                if fill {
                    // A .fill-aspect image reports its intrinsic aspect upward and
                    // can push PAST the frame its parent proposed (in a grid it
                    // overflowed the cell and mashed into its neighbor). Hanging it
                    // off a Color makes the view exactly the proposed size; the
                    // image just paints (and clips) inside it.
                    Color.clear.overlay {
                        image.resizable().aspectRatio(contentMode: illustration ? .fit : .fill)
                    }
                } else {
                    image.resizable().aspectRatio(contentMode: illustration ? .fit : .fill)
                }
            } else if imageURL != nil, !failed {
                // Loading — the same neutral tile AsyncImage's default showed.
                DS.Palette.surface.opacity(0.6)
            } else {
                glyph
            }
        }
        .frame(width: fill ? nil : size, height: fill ? nil : size)
        .frame(maxWidth: fill ? .infinity : nil, maxHeight: fill ? .infinity : nil)
        .background(illustration && !plain ? DS.Palette.surface.opacity(0.6) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if stroke, !plain { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(
                DS.Palette.hairlineSoft,
                lineWidth: 1
            ) }
        }
        .task(id: imageURL) { await load() }
    }

    private func load() async {
        #if canImport(UIKit)
            guard let imageURL, let url = URL(string: imageURL) else { return }
            let key = "thumb:\(imageURL)"
            if let cached = AvatarImageCache.shared.image(for: key) {
                image = Image(uiImage: cached)
                return
            }
            if AvatarImageCache.shared.isKnownEmpty(key) {
                failed = true
                return
            }
            do {
                let data: Data
                if let authorizedImageLoader {
                    data = try await authorizedImageLoader(url)
                } else {
                    let (raw, response) = try await URLSession.shared.data(from: url)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        if http.statusCode == 404 || http.statusCode == 410 {
                            AvatarImageCache.shared.storeEmpty(key)
                            failed = true
                        }
                        return
                    }
                    data = raw
                }
                guard !Task.isCancelled else { return }
                guard let decoded = UIImage(data: data) else {
                    AvatarImageCache.shared.storeEmpty(key)
                    failed = true
                    return
                }
                let prepared = await decoded.byPreparingForDisplay() ?? decoded
                guard !Task.isCancelled else { return }
                AvatarImageCache.shared.store(prepared, for: key)
                image = Image(uiImage: prepared)
            } catch {
                // Transient (cancel/timeout/offline): keep the loading tile and
                // retry on the next appear — never poison the cache.
            }
        #endif
    }

    private var glyph: some View {
        ZStack {
            DS.Palette.surface.opacity(0.6)
            Image(systemName: systemImage ?? "photo")
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(DS.Palette.placeholder)
        }
    }
}
