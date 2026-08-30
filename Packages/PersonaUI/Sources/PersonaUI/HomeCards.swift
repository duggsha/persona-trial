import CryptoKit
import PersonaCore
import PersonaDesign
import PersonaService
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

// MARK: - Category icon (brand-logo fallback)

/// A category color for an SF-symbol icon, so backend-driven tasks/suggestions
/// read as intentional iconography instead of a flat accent badge. Brand logos
/// still win when the card has a real `appImage` / `avatar`.
enum HomeIconTint {
    // Per-category hues mirroring the design app's icon tints (TaskAppIcon /
    // SuggestionAvatarView) — minus their blue anchor: the app's chrome (brand
    // orb, accent pills) is already blue, so badges anchor on the design's
    // indigo instead and blue stays reserved for the brand. A few semantic
    // accents carry meaning: green (an active call / money), amber (needs your
    // attention — a reminder), and ONE warm tone for "out in the world" cards.
    static let amber = Color(hex: 0xF5B700)
    static let neutral = Color(hex: 0x6E6E8A)
    static let warm = Color(hex: 0xEC6C3B)
    static let teal = Color(hex: 0x1F8A70)
    static let indigo = Color(hex: 0x5966D6)
    static let box = Color(hex: 0xC66B2D)

    /// Category tint by card KIND first (the structural signal), then by symbol.
    /// Suggestion cards pass their backend kind; tasks pass nil and fall to the
    /// tool-symbol tint. Anything not explicitly an accent lands on the indigo
    /// anchor.
    static func color(forKind kind: String?, symbol: String) -> Color {
        if let kind = kind?.lowercased(), !kind.isEmpty {
            switch kind {
            // "Out in the world" cards share the single warm accent.
            case "place", "event", "local-event", "opportunity", "travel_opportunity",
                 "networking", "discovery", "recommendation", "hidden-gem", "serendipity":
                return warm
            case "signin-code", "action-link":
                return neutral
            default:
                break // mail / reply / calendar → the anchor via the symbol path
            }
        }
        return color(for: symbol)
    }

    static func color(for symbol: String) -> Color {
        // The semantic accents (calls take the design's deep phone green).
        if symbol.hasPrefix("phone") { return teal }
        if symbol.contains("creditcard") || symbol.contains("dollarsign") { return DS.Palette.success }
        if symbol.hasPrefix("bell") { return amber } // reminder → needs attention
        if symbol.hasPrefix("shippingbox") { return box } // packages → the design's box brown
        switch symbol {
        // Utility glyphs sit in the neutral family, so they recede.
        case "gearshape", "gearshape.fill", "magnifyingglass", "car.fill", "link", "network":
            return neutral
        // Places / events / travel / commerce → the one warm tone.
        case "mappin", "mappin.circle", "mappin.circle.fill", "map", "location", "building.2",
             "storefront", "fork.knife", "bag.fill", "airplane", "ticket", "ticket.fill",
             "music.note", "sparkle":
            return warm
        // Everything else — people, mail, calendar, tasks, browsing, memory, the
        // agent's own work — lands on the indigo anchor for a harmonious deck.
        default:
            return indigo
        }
    }
}

/// logo.dev publishable token (safe to embed — same one the backend uses).
private let logoDevPublicToken = "pk_REDACTED"

/// The brand/contact source a card wants rendered. `.url` is a resolved photo URL
/// (a real person photo) rendered directly; `.email` runs the full Gravatar →
/// logo.dev chain; `.domain` skips straight to the brand logo (no person to look
/// up).
enum AvatarSource: Equatable {
    case url(String)
    case email(String)
    case domain(String)

    /// Stable cache/identity key.
    var key: String {
        switch self {
        case let .url(value): "url:" + value.trimmingCharacters(in: .whitespacesAndNewlines)
        case let .email(value): value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        case let .domain(value): "domain:" + value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }
}

/// Fetches a photo URL's bytes with whatever auth it needs. The app injects one
/// that attaches the Firebase bearer for our own backend hosts (device-contact
/// photos at `/v1/contacts/photos/:id`) and fetches public hosts
/// (`googleusercontent.com`) plainly. Nil (the default) means "no authorized
/// path wired yet" → a `.url` avatar fetches the URL plainly, which still works
/// for public photos and degrades to the icon (never blank) for auth'd ones.
public typealias AuthorizedImageLoader = @Sendable (URL) async throws -> Data

private struct AuthorizedImageLoaderKey: EnvironmentKey {
    static let defaultValue: AuthorizedImageLoader? = nil
}

public extension EnvironmentValues {
    var authorizedImageLoader: AuthorizedImageLoader? {
        get { self[AuthorizedImageLoaderKey.self] }
        set { self[AuthorizedImageLoaderKey.self] = newValue }
    }
}

/// A contact/brand image: for `.email`, Gravatar (the photo they set) → logo.dev
/// (their domain's brand logo); for `.domain`, the brand logo directly. Falls
/// through to a tinted category badge. All loads are best-effort.
struct RemoteContactAvatar: View {
    let source: AvatarSource
    var fallbackSymbol = "envelope.fill"
    var circle = true
    /// Rendered diameter — 38 is the Home-card default; chat chips use smaller.
    var size: CGFloat = 38
    /// Initials shown when no image resolves — a person monogram reads better
    /// than a generic glyph. Nil → the category badge (unchanged behaviour).
    var monogram: String? = nil
    /// Draw that monogram in ink on grey rather than the accent tint — the
    /// contact cards' monochrome language.
    var monochromeMonogram = false
    /// The person's address-book handles, when this avatar is for a PERSON. Read
    /// before anything goes over the wire: if they're in the user's contacts
    /// with a photo, those bytes are already on the device (see
    /// DeviceContactPhotos). Nil for brand/domain avatars.
    var deviceHandles: DeviceContactPhotos.Handles? = nil

    init(
        source: AvatarSource,
        fallbackSymbol: String = "envelope.fill",
        circle: Bool = true,
        size: CGFloat = 38,
        monogram: String? = nil,
        monochromeMonogram: Bool = false,
        deviceHandles: DeviceContactPhotos.Handles? = nil
    ) {
        self.source = source
        self.fallbackSymbol = fallbackSymbol
        self.circle = circle
        self.size = size
        self.monogram = monogram
        self.monochromeMonogram = monochromeMonogram
        self.deviceHandles = deviceHandles
        // A rebuilt view (recycled lazy row, any identity churn) must paint a
        // known avatar on its FIRST frame — waiting for the async `.task` to
        // re-read the cache leaves at least one frame of fallback badge, which
        // reads as the icon flashing to the wrong mark.
        #if canImport(UIKit)
            if let deviceHandles, let local = DeviceContactPhotos.cachedImage(for: deviceHandles) {
                _image = State(initialValue: Image(uiImage: local))
            } else if let cached = AvatarImageCache.shared.image(for: source.key) {
                _image = State(initialValue: Image(uiImage: cached))
            }
        #endif
    }

    /// Convenience for the common mail-sender case.
    init(email: String, fallbackSymbol: String = "envelope.fill", circle: Bool = true, size: CGFloat = 38, monogram: String? = nil) {
        self.init(source: .email(email), fallbackSymbol: fallbackSymbol, circle: circle, size: size, monogram: monogram)
    }

    @State private var image: Image?
    @Environment(\.authorizedImageLoader) private var authorizedImageLoader

    private var shape: AnyShape {
        circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 9.62, style: .continuous))
    }

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(shape)
                    .overlay { shape.stroke(DS.Palette.hairlineSoft, lineWidth: 1) }
            } else if showsGmailMark {
                // The bundled Gmail envelope, small on a white disc — the M is
                // wider than tall, so it never goes through the full-bleed
                // crop above.
                ZStack {
                    shape.fill(DS.Palette.card)
                    PersonaAsset.image("LogoGmail")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: size * 0.5)
                }
                .frame(width: size, height: size)
                .overlay { shape.stroke(DS.Palette.hairlineSoft, lineWidth: 1) }
            } else if let monogram, !monogram.isEmpty {
                MonogramBadge(
                    initials: monogram,
                    circle: circle,
                    size: size,
                    monochrome: monochromeMonogram
                )
            } else {
                CategoryIconBadge(symbol: fallbackSymbol, circle: circle, size: size)
            }
        }
        .task(id: source.key + (deviceHandles?.key ?? "")) { await load() }
    }

    @State private var showsGmailMark = false

    /// The outcome of one image fetch. `.miss` is a DEFINITIVE "this source has
    /// no image" (404 / non-200) and is safe to remember; `.retry` is a
    /// cancellation or transient transport failure (timeout, offline, view
    /// churn) that must NOT poison the cache — we keep whatever is already on
    /// screen and try again on the next appear.
    private enum Fetched { case image(Image)
        case gmailMark
        case miss
        case retry
    }

    /// Consumer Google-mail domains: logo.dev serves the Google "G" for these,
    /// which reads as the wrong brand — the bundled Gmail mark renders instead.
    private static let consumerGmailDomains: Set<String> = ["gmail.com", "googlemail.com"]

    private func load() async {
        let key = source.key

        #if canImport(UIKit)
            // The address book first: for someone the user actually has saved,
            // the photo is already on the device. Zero network, and it's the
            // same face the backend would have served back.
            if let deviceHandles, !DeviceContactPhotos.isKnownMiss(deviceHandles) {
                if let local = await DeviceContactPhotos.image(for: deviceHandles) {
                    image = Image(uiImage: local)
                    showsGmailMark = false
                    return
                }
                guard !Task.isCancelled else { return }
            }
        #endif

        // Cache hit (resolved image or a known miss) — no network, no flicker on
        // scroll re-use.
        #if canImport(UIKit)
            if let cached = AvatarImageCache.shared.image(for: key) {
                image = Image(uiImage: cached)
                return
            }
            if AvatarImageCache.shared.isKnownEmpty(key) {
                image = nil
                return
            }
        #endif
        // Do NOT wipe an already-resolved image before the network round-trip.
        // A re-run (NSCache eviction, view identity churn) then keeps showing the
        // logo while it refetches, so the hero card never flashes blank.

        let result = await resolve(key: key)
        // View went away mid-fetch: keep whatever's on screen, don't cache empty.
        guard !Task.isCancelled else { return }

        switch result {
        case let .image(loaded):
            image = loaded
            showsGmailMark = false
        case .gmailMark:
            // Deterministic from the address — no network, nothing to cache.
            image = nil
            showsGmailMark = true
        case .miss:
            image = nil
            showsGmailMark = false
            #if canImport(UIKit)
                AvatarImageCache.shared.storeEmpty(key)
            #endif
        case .retry:
            // Transient/cancelled — leave the current image (or the deterministic
            // fallback badge) and retry next time; never remember it as empty.
            break
        }
    }

    /// Resolve the source into an image, following the Gravatar → logo.dev chain
    /// for emails. Returns `.retry` if ANY step failed transiently (so the caller
    /// won't cache an empty), `.miss` only when every step gave a definitive
    /// no-image.
    private func resolve(key: String) async -> Fetched {
        switch source {
        case let .url(raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed) else { return .miss }
            return await fetchPhoto(url: url, key: key)

        case let .email(raw):
            let address = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard address.contains("@") else { return .miss }

            var sawTransient = false
            // 1) Gravatar — only returns 200 when the user actually set a photo (d=404).
            let hash = Insecure.MD5.hash(data: Data(address.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
            if let url = URL(string: "https://www.gravatar.com/avatar/\(hash)?d=404&s=240") {
                switch await Self.fetch(url, key: key) {
                case let .image(loaded): return .image(loaded)
                case .retry: sawTransient = true
                case .miss, .gmailMark: break // fetch never yields gmailMark
                }
            }
            // 2) Brand logo. Consumer Google-mail senders get the bundled Gmail
            // mark; company domains fetch their real logo from logo.dev.
            if let domain = address.split(separator: "@").last.map(String.init) {
                if Self.consumerGmailDomains.contains(domain) {
                    return sawTransient ? .retry : .gmailMark
                }
                switch await Self.fetchLogo(domain: domain, key: key) {
                case let .image(loaded): return .image(loaded)
                case .retry: sawTransient = true
                case .miss, .gmailMark: break // fetch never yields gmailMark
                }
            }
            return sawTransient ? .retry : .miss

        case let .domain(raw):
            let domain = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !domain.isEmpty else { return .miss }
            return await Self.fetchLogo(domain: domain, key: key)
        }
    }

    /// Fetch a resolved photo URL. Uses the app-injected authorized loader (which
    /// attaches the bearer for our backend host, fetches public hosts plainly)
    /// when present; otherwise a plain fetch — public photos still load, an
    /// auth-required backend URL 401s → .retry (degrades to the icon, never
    /// poisons) until the loader is wired.
    private func fetchPhoto(url: URL, key: String) async -> Fetched {
        #if canImport(UIKit)
            // A `data:` URL is self-contained (QA mocks): decode it in place.
            // It must not go through the authorized loader (which reads any
            // hostless URL as a backend-relative path and would fetch `/…`) NOR
            // through `fetch` (which demands an HTTPURLResponse and would call
            // a perfectly good payload transient). CachedRemoteImage makes the
            // same carve-out.
            if url.scheme == "data" {
                guard let data = try? Data(contentsOf: url), let uiImage = UIImage(data: data) else { return .miss }
                AvatarImageCache.shared.store(uiImage, data: data, for: key)
                return .image(Image(uiImage: uiImage))
            }
            guard let authorizedImageLoader else { return await Self.fetch(url, key: key) }
            do {
                let data = try await authorizedImageLoader(url)
                guard let uiImage = UIImage(data: data) else { return .miss }
                AvatarImageCache.shared.store(uiImage, data: data, for: key)
                return .image(Image(uiImage: uiImage))
            } catch is CancellationError {
                return .retry
            } catch {
                return .retry
            }
        #else
            return .miss
        #endif
    }

    private static func fetchLogo(domain: String, key: String) async -> Fetched {
        guard let url = URL(string: "https://img.logo.dev/\(domain)?token=\(logoDevPublicToken)&size=120&format=png")
        else { return .miss }
        return await fetch(url, key: key)
    }

    private static func fetch(_ url: URL, key: String) async -> Fetched {
        #if canImport(UIKit)
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse else { return .retry }
                switch http.statusCode {
                case 200:
                    // The only win — a decodable 200 image, cached.
                    guard let uiImage = UIImage(data: data) else { return .retry }
                    // A decodable-but-INVISIBLE mark (white-on-transparent
                    // logo art, which logo.dev serves for some domains) is a
                    // definitive miss, not a win: rendered full-bleed on the
                    // white avatar disc it paints an empty circle (the
                    // Agentcard OTP row, design report). Falling to
                    // .miss lets the category badge draw instead.
                    guard !uiImage.isEffectivelyBlank else { return .miss }
                    AvatarImageCache.shared.store(uiImage, data: data, for: key)
                    return .image(Image(uiImage: uiImage))
                case 404, 410:
                    // Definitive "no such image" (Gravatar d=404, unknown logo) —
                    // safe to remember as empty.
                    return .miss
                default:
                    // 401 needs-auth, 429/5xx, etc. — transient, never poison.
                    return .retry
                }
            } catch is CancellationError {
                return .retry
            } catch let error as URLError where error.code == .cancelled {
                return .retry
            } catch {
                // Timeout / offline / DNS — transient. Keep the logo, don't poison.
                return .retry
            }
        #else
            return .miss
        #endif
    }
}

#if canImport(UIKit)
    extension UIImage {
        /// True when the bitmap is effectively invisible on a white card —
        /// every sampled pixel transparent or near-white. logo.dev serves
        /// such marks for some domains (white-on-transparent brand art);
        /// treated as a fetch MISS so the category badge draws instead of an
        /// empty circle. Sampled at 16×16 — cheap, and a logo with any real
        /// ink survives the downscale.
        var isEffectivelyBlank: Bool {
            guard let cg = cgImage else { return false }
            let side = 16
            var pixels = [UInt8](repeating: 0, count: side * side * 4)
            guard let ctx = CGContext(
                data: &pixels, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.interpolationQuality = .low
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            for i in stride(from: 0, to: pixels.count, by: 4) {
                let a = Int(pixels[i + 3])
                if a < 13 { continue } // transparent — invisible either way
                // Premultiplied: a near-white pixel keeps r≈g≈b≈alpha. Any
                // channel meaningfully below that is visible ink.
                let floor = UInt8(max(0, a * 94 / 100 - 6))
                if pixels[i] < floor || pixels[i + 1] < floor || pixels[i + 2] < floor {
                    return false
                }
            }
            return true
        }
    }

    /// Process-wide cache so contact avatars don't refetch (and flicker) every
    /// time a row scrolls back into view. Backed by a disk mirror
    /// (Caches/PersonaAvatarImages) so they also survive a relaunch — the
    /// social-photo CDNs behind the avatar picker are slow enough that
    /// re-paying the download every launch reads as the grid "loading" each
    /// time. Only stores that hand over their ORIGINAL encoded bytes persist
    /// (small avatars/logos); derived images (prepared chat photos) stay
    /// memory-only.
    final class AvatarImageCache: @unchecked Sendable {
        static let shared = AvatarImageCache()
        private let images = NSCache<NSString, UIImage>()
        private var empties = Set<String>()
        private let lock = NSLock()

        private static let directory: URL = {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            let dir = base.appendingPathComponent("PersonaAvatarImages", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }()

        private static func fileURL(_ key: String) -> URL {
            let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
            return directory.appendingPathComponent(name)
        }

        func image(for key: String) -> UIImage? {
            if let hit = images.object(forKey: key as NSString) { return hit }
            // Cold start: revive from disk and promote to memory, so a cached
            // avatar paints on its first frame instead of re-downloading.
            guard let data = try? Data(contentsOf: Self.fileURL(key)),
                  let revived = UIImage(data: data) else { return nil }
            // Heal entries cached before blank detection existed: an
            // invisible mark on disk would paint the empty circle forever.
            // Dropping it here lets the next fetch land on .miss → badge.
            if revived.isEffectivelyBlank {
                try? FileManager.default.removeItem(at: Self.fileURL(key))
                return nil
            }
            images.setObject(revived, forKey: key as NSString)
            return revived
        }

        /// `data` is the image's original encoded bytes — passing it persists
        /// the image across launches; nil keeps it memory-only.
        func store(_ image: UIImage, data: Data? = nil, for key: String) {
            images.setObject(image, forKey: key as NSString)
            guard let data else { return }
            let url = Self.fileURL(key)
            Task.detached(priority: .utility) {
                // Recreated because the OS may evict Caches/ wholesale (same
                // rule as SnapshotCache) — otherwise every later write fails.
                try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
                try? data.write(to: url, options: .atomic)
            }
        }

        /// Sign-out: backend contact-photo URLs are account-scoped — drop the
        /// persisted bytes (and the memory cache) with the other caches.
        func clearPersisted() {
            images.removeAllObjects()
            lock.lock()
            empties.removeAll()
            lock.unlock()
            try? FileManager.default.removeItem(at: Self.directory)
        }

        func isKnownEmpty(_ key: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return empties.contains(key)
        }

        func storeEmpty(_ key: String) {
            lock.lock()
            empties.insert(key)
            lock.unlock()
        }
    }
#endif

/// Sign-out hook for the app target (the cache class itself is internal):
/// clears the persisted avatar images alongside `SnapshotCache.clearAll()`.
public enum AvatarImageDiskCache {
    public static func clear() {
        #if canImport(UIKit)
            AvatarImageCache.shared.clearPersisted()
            // The address-book faces read at render time are memory-only, but
            // they're still one account's contacts — drop them on the same hook.
            DeviceContactPhotos.clear()
        #endif
    }
}

/// The tinted SF-symbol badge shown when there's no brand logo / contact photo.
/// The brand mark sized as a task glyph — the DEFAULT task icon: a task with no real icon signal wears the persona logo, not
/// a gear/clipboard. Light mode keeps the original artwork; dark templates
/// it near-white (the mark is black shapes with off-white interiors —
/// template mode would fill it into a silhouette, see PersonaHeader's
/// wordmark note).
struct TaskBrandGlyph: View {
    @Environment(\.colorScheme) private var colorScheme
    var size: CGFloat

    var body: some View {
        PersonaAsset.image("PersonaMark")
            .renderingMode(colorScheme == .dark ? .template : .original)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(Color(light: 0x030303, dark: 0xF2F2F4))
    }
}

struct CategoryIconBadge: View {
    let symbol: String
    var circle = false
    /// Rendered size — 38 matches the Home cards; chat chips pass smaller.
    var size: CGFloat = 38
    /// The card's backend kind, when known — tints by category (place, event, …)
    /// ahead of the symbol so the badge colour reads the KIND of card.
    var kind: String? = nil
    /// Theme-ink variant: glyph in the app's near-black (the chat-bubble
    /// family) on a quiet ink wash, ignoring the per-kind tints. Task cards
    /// use this so their icons read as ONE system with the rest of the app.
    var monochrome = false

    /// The last-resort glyph so the badge is NEVER an empty tinted circle.
    private static let fallbackGlyph = "sparkles"

    /// A guaranteed-drawable SF Symbol. An empty string or an unknown symbol name
    /// (a backend icon that isn't a real SF Symbol) makes `Image(systemName:)`
    /// render NOTHING — a tinted circle with no glyph, the "blank avatar" bug.
    /// Resolve to a valid glyph so the invariant "never blank" always holds.
    private var resolvedSymbol: String {
        var trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Self.fallbackGlyph }
        // Monochrome badges draw the bare glyph: an enclosed variant
        // ("airplane.circle.fill") renders as a solid ink DISC on the grey
        // wash — a black hole next to the other badges. Strip the enclosure
        // (when the bare symbol exists) so every glyph reads ink-on-grey.
        if monochrome {
            for suffix in [".circle.fill", ".circle", ".square.fill", ".square"] where trimmed.hasSuffix(suffix) {
                let bare = String(trimmed.dropLast(suffix.count))
                #if canImport(UIKit)
                    if UIImage(systemName: bare) != nil { trimmed = bare }
                #else
                    trimmed = bare
                #endif
                break
            }
        }
        #if canImport(UIKit)
            return UIImage(systemName: trimmed) != nil ? trimmed : Self.fallbackGlyph
        #else
            return trimmed
        #endif
    }

    private var tint: Color {
        HomeIconTint.color(forKind: kind, symbol: resolvedSymbol)
    }

    private var shape: AnyShape {
        // The monochrome (task) badge wears the reference mock's rounder
        // squircle; the tinted recipe keeps the design app's 9.62.
        if circle { return AnyShape(Circle()) }
        return AnyShape(RoundedRectangle(cornerRadius: monochrome ? size * 12 / 38 : 9.62, style: .continuous))
    }

    // Badge recipe shared by the design's TaskAppIcon and SuggestionAvatarView:
    // tint fill at 0.12, a white hairline (NOT the tint), 17pt semibold glyph.
    var body: some View {
        if monochrome {
            // The reference mock's task-icon badge (task-states —
            // supersedes the 7/14 white-plate call): an ink glyph on a quiet
            // solid-grey squircle, no hairline, no shadow. The glyph runs
            // larger than the tinted recipe's — the mock's icons fill ~55% of
            // the badge. Color stays reserved for status dots, panels, and
            // real brand logos. No-signal tasks wear the brand mark instead
            // of a generic glyph (TaskBrandGlyph).
            if TaskIcon.isGeneric(symbol) {
                TaskBrandGlyph(size: size * 18 / 38)
                    .frame(width: size, height: size)
                    .background(Color(light: 0xF0F0F0, dark: 0x26272E), in: shape)
            } else {
                Image(systemName: resolvedSymbol)
                    .font(.system(size: size * 20 / 38, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(DS.Palette.ink)
                    .frame(width: size, height: size)
                    .background(Color(light: 0xF0F0F0, dark: 0x26272E), in: shape)
            }
        } else {
            Image(systemName: resolvedSymbol)
                .font(.system(size: size * 17 / 38, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(tint.opacity(0.12), in: shape)
                .overlay { shape.stroke(DS.Palette.card.opacity(0.65), lineWidth: 0.8) }
        }
    }
}

/// A person monogram (up to two initials) on a blue-anchored disc — the
/// last-resort avatar when no photo/logo resolves, in place of a generic glyph.
struct MonogramBadge: View {
    let initials: String
    var circle = true
    var size: CGFloat = 38
    /// Ink on the grey squircle tone instead of the accent tint — the chat
    /// card language, where content blue is retired.
    var monochrome = false

    private var shape: AnyShape {
        circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 9.62, style: .continuous))
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 15 / 38, weight: .semibold))
            .tracking(-0.2)
            .foregroundStyle(monochrome ? DS.Palette.ink : DS.Palette.accent)
            .frame(width: size, height: size)
            .background(monochrome ? DS.Palette.surfaceMuted : DS.Palette.accent.opacity(0.12), in: shape)
            .overlay { monochrome ? nil : shape.stroke(DS.Palette.card.opacity(0.65), lineWidth: 0.8) }
    }
}

/// Up to two uppercase initials from a person's name, else from an email local
/// part ("jenny.smith@…" → "JS", "marco21@…" → "M"). Nil when nothing name-like.
func contactMonogram(name: String?, email: String?) -> String? {
    if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first)
        if !initials.isEmpty { return String(initials).uppercased() }
    }
    guard let local = email?.split(separator: "@").first else { return nil }
    let parts = local.split(whereSeparator: { ".-_+".contains($0) }).filter { !$0.isEmpty }
    let letters: [Character] = if parts.count >= 2 {
        [parts[0], parts[1]].compactMap(\.first)
    } else if let first = parts.first {
        Array(first.prefix(2))
    } else {
        []
    }
    let result = String(letters).uppercased()
    return result.isEmpty ? nil : result
}

/// Resolves a home entry's icon to the best real source: a contact (email) →
/// then a brand (domain) → then the tinted category badge. Shared by task rows
/// and suggestion rows so both degrade identically.
struct HomeEntryAvatar: View {
    /// A resolved real photo (person photo) — rendered first when present.
    var photoUrl: String?
    var contactEmail: String?
    var logoDomain: String?
    var fallbackSymbol: String
    var circle = false
    /// The card's backend kind, forwarded to the fallback badge for a category tint.
    var kind: String? = nil
    /// Theme-ink fallback badge (see CategoryIconBadge.monochrome) — real
    /// photos/logos render as themselves either way.
    var monochromeFallback = false

    var body: some View {
        if let photo = photoUrl, !photo.isEmpty {
            RemoteContactAvatar(source: .url(photo), fallbackSymbol: fallbackSymbol, circle: circle)
        } else if let email = contactEmail, !email.isEmpty {
            RemoteContactAvatar(source: .email(email), fallbackSymbol: fallbackSymbol, circle: circle)
        } else if let domain = logoDomain, !domain.isEmpty {
            RemoteContactAvatar(source: .domain(domain), fallbackSymbol: fallbackSymbol, circle: circle)
        } else {
            CategoryIconBadge(symbol: fallbackSymbol, circle: circle, kind: kind, monochrome: monochromeFallback)
        }
    }
}

/// A suggestion's avatar, shared by the Home card and the "All" sheet row so
/// both degrade identically: the bundled asset when the card names one; a real
/// person/contact image when the backend can resolve one; otherwise the GMAIL
/// mark for drafted email replies before falling back to a category badge.
struct SuggestionEntryAvatar: View {
    let suggestion: Suggestion
    var size: CGFloat = 38
    /// The sender resolved from the card's own mail-thread fetch, when the
    /// host already made one (UniversalCard). The feed's enrichment only pins
    /// a contact for `mail-message` cards, so a thread- or matter-referenced
    /// card arrives with every identity field null and would fall all the way
    /// to the brand mark — even though the source row two rows down is
    /// already drawing the real sender's logo. Same address the source tile
    /// uses, so the image is a cache hit rather than a second fetch.
    var resolvedSenderEmail: String?

    private var isEmailReply: Bool {
        suggestion.actions.first?.type == "send_draft"
    }

    /// Initials for the monogram fallback — from the display name when the card
    /// carries one, else the email local part.
    private var monogram: String? {
        contactMonogram(name: suggestion.contactName, email: suggestion.contactEmail ?? suggestion.avatarEmail)
    }

    var body: some View {
        if !suggestion.avatar.isEmpty {
            PersonaAsset.image(suggestion.avatar)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else if let photo = suggestion.photoUrl, !photo.isEmpty {
            RemoteContactAvatar(
                source: .url(photo),
                fallbackSymbol: suggestion.systemIcon ?? "person.fill",
                circle: true,
                size: size,
                monogram: monogram
            )
        } else if let email = suggestion.contactEmail ?? suggestion.avatarEmail, !email.isEmpty {
            RemoteContactAvatar(
                source: .email(email),
                fallbackSymbol: suggestion.systemIcon ?? "person.fill",
                circle: true,
                size: size,
                monogram: monogram
            )
        } else if let sender = resolvedSenderEmail, !sender.isEmpty {
            // Below the feed's pinned contact (a producer-stamped face still
            // wins) and above the Gmail mark: the actual sender beats "this
            // came from mail".
            RemoteContactAvatar(
                source: .email(sender),
                fallbackSymbol: suggestion.systemIcon ?? "person.fill",
                circle: true,
                size: size,
                monogram: contactMonogram(name: suggestion.contactName, email: sender)
            )
        } else if isEmailReply {
            // The bundled Gmail envelope, small on a white disc (like the app's
            // own icon treatment) — a full-bleed fetched logo reads wrong here.
            ZStack {
                Circle().fill(DS.Palette.card)
                PersonaAsset.image("LogoGmail")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size * 0.50)
            }
            .frame(width: size, height: size)
            .overlay { Circle().stroke(DS.Palette.hairlineSoft, lineWidth: 1) }
        } else {
            HomeEntryAvatar(
                photoUrl: suggestion.photoUrl,
                contactEmail: suggestion.contactEmail ?? suggestion.avatarEmail,
                logoDomain: suggestion.logoDomain,
                fallbackSymbol: suggestion.systemIcon ?? "sparkles",
                circle: true,
                kind: suggestion.kind,
                // Task-icon scheme: ink glyph on the quiet
                // grey wash, so suggestion/update badges read as one system
                // with the Tasks deck. Real photos/logos stay themselves.
                monochromeFallback: true
            )
        }
    }
}

// MARK: - Hero card scaffold

/// Shared hero-card geometry, matched to the design app's 362×160 canvas
/// (HomeSections.MeetingCard / SuggestedTaskCard): a fixed 160pt panel on the
/// gutter width, orb+title header (title 16 semibold, centred on the 26pt orb),
/// the 14pt subtitle landing at y≈55, and a 42pt pill pinned 13pt off the
/// bottom (y≈105). Widths stay responsive; the vertical rhythm is the design's.
private struct HeroCardScaffold<Pill: View>: View {
    let title: String
    let symbol: String
    var symbolStyle: Color = DS.Palette.ink
    let subtitle: String
    /// Iris is still writing this card's personalized copy — show shimmer
    /// bars where the title/subtitle text will land instead of placeholder
    /// template copy.
    var redactsCopy = false
    /// Optional extra content between the subtitle and the pill — the meeting
    /// hero uses it for the inline briefing block. nil for every other hero
    /// (which stays the fixed-height card), so existing callers are unchanged.
    var briefingView: AnyView? = nil
    @ViewBuilder let pill: Pill

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                BrandMark(size: 26)
                if redactsCopy {
                    ShimmerBar(height: 15).frame(maxWidth: 190)
                } else {
                    Text(title)
                        .font(DS.Typography.cardTitle)
                        .foregroundStyle(DS.Palette.inkBlack)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                Spacer(minLength: 8)
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(symbolStyle)
            }

            if redactsCopy {
                VStack(alignment: .leading, spacing: 7) {
                    ShimmerBar(height: 11)
                    ShimmerBar(height: 11).frame(maxWidth: 200)
                }
                .padding(.top, 13)
                .padding(.leading, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if !subtitle.isEmpty {
                // Empty means the caller renders its own body copy inside
                // `briefingView` (the meeting hero's inline expander does).
                Text(subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .tracking(-0.21)
                    .foregroundStyle(DS.Palette.subtle)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 11)
                    .padding(.leading, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let briefingView {
                briefingView
                    .padding(.top, 12)
                    .padding(.leading, 3)
            }

            Spacer(minLength: 8)

            pill
        }
        .padding(EdgeInsets(top: 18, leading: 19, bottom: 13, trailing: 19))
        .frame(maxWidth: .infinity, alignment: .leading)
        // Minimum, not fixed: the briefing block lets the meeting hero grow with
        // its content (2-3 lines collapsed, more when expanded); every other
        // hero has no briefingView and stays the 160pt card.
        .frame(minHeight: 160, alignment: .top)
        .solidCardPlate()
        .animation(.easeInOut(duration: 0.22), value: redactsCopy)
    }
}

/// A soft skeleton bar with a travelling highlight — shown where a line of
/// copy will land while it's still being written.
struct ShimmerBar: View {
    var height: CGFloat
    @State private var phase: CGFloat = -0.7

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(DS.Palette.ink.opacity(0.07))
            .frame(height: height)
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.65), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.55)
                    .offset(x: geo.size.width * phase)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
            .onAppear {
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                    phase = 1.25
                }
            }
    }
}

// MARK: - Meeting

struct MeetingCard: View {
    @Environment(\.openURL) private var openURL

    let meeting: MeetingSummary
    /// Iris's personalized copy is still in flight — shimmer instead of the
    /// template placeholder.
    var isWritingCopy = false
    var onOpen: () -> Void = {}
    /// Open a meeting chat from the keyboard affordance.
    var onAsk: (String) -> Void = { _ in }
    /// The keyboard affordance as reply-to-event mode (chat page, dimmed reply
    /// state, this card as the quote). Falls back to `onAsk` (seed a chat turn)
    /// where the surface doesn't wire it.
    var onCompose: (() -> Void)?
    /// Dismiss the card (swipe left, same mechanic as the suggestion deck).
    /// The store remembers the event id so this meeting never takes the slot
    /// again. nil = not swipeable (galleries, quote previews).
    var onDismiss: (() -> Void)?
    /// Renders as the reply state's quoted card: no action row, and the card
    /// hugs its text instead of growing into the unconstrained bottom-pinned
    /// slot (the Spacer + minHeight are HOME's shape, where the scroll view
    /// bounds them).
    var isQuotePreview = false

    // Swipe state machine — SuggestionCard's mechanic verbatim: rubber-banded
    // leftward drag, 74pt commit with a rigid haptic at the threshold, fling
    // off-screen on commit. Rightward drags stay with the Home⇄Chat pager.
    @State private var dragOffset: CGFloat = 0
    @State private var isSwipeActive = false
    @State private var isCompletingSwipe = false
    @State private var wasPastCommitThreshold = false
    /// MeetingSummary carries no stable UUID, so the pager's no-page zone
    /// registers under a per-view key (deregistered when the card leaves).
    @State private var swipeZoneID = UUID()

    private let maxDrag: CGFloat = 104
    private let commitDistance: CGFloat = 74

    private var isSwipeable: Bool { onDismiss != nil && !isQuotePreview }

    var body: some View {
        Group {
            #if canImport(UIKit)
                if isSwipeable {
                    ZStack {
                        swipeAffordance
                        cardContent.offset(x: dragOffset)
                    }
                    .overlay {
                        // Leftward only, same contract as the suggestion deck:
                        // the pan's page-edge stripes stay with the pager, and
                        // rightward drags never begin here.
                        HorizontalSwipeGestureAttachment(
                            edgeSwipeWidth: 16,
                            usesPageEdgeStripes: true,
                            locksVerticalScroll: true,
                            allowsRightward: false,
                            onChanged: handleSwipeChanged(translation:),
                            onEnded: handleSwipeEnded(translation:)
                        )
                    }
                    // A drag that starts on the hero never pages Home⇄Chat,
                    // whether or not the swipe pan ends up claiming it.
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                        SuggestionSwipeZones.update(swipeZoneID, frame: frame)
                    }
                    .onDisappear { SuggestionSwipeZones.update(swipeZoneID, frame: nil) }
                } else {
                    cardContent
                }
            #else
                cardContent
            #endif
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Give the event headline a little more breathing room above and
            // below without changing the card or action-row positions.
            VStack(alignment: .leading, spacing: 4) {
                Text("Up Next")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .tracking(-0.18)
                    .foregroundStyle(Color(light: 0x007AFF, dark: 0x409CFF))

                if isWritingCopy {
                    VStack(alignment: .leading, spacing: 7) {
                        ShimmerBar(height: 15).frame(maxWidth: 270)
                        // Wide second bar: the subtitle is Iris's sentence now,
                        // not a short "Calendar · time" tag.
                        ShimmerBar(height: 12).frame(maxWidth: 225)
                    }
                } else {
                    Text(headlineText)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(DS.Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    // Iris's personalized line is the subtitle: the headline
                    // already carries the clock, so this slot earns its place
                    // by saying something the title doesn't. Two lines max —
                    // the backend writes to that budget.
                    Text(detailText)
                        .font(.subheadline)
                        .tracking(-0.21)
                        .foregroundStyle(DS.Palette.subtle)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 19)

            if !isQuotePreview, hasActionRow {
                // Floor the gap above the action row: a two-line subtitle must
                // grow the card, not swallow the air between text and buttons.
                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    if meeting.joinLink != nil {
                        joinButton
                    }
                    if directionsDestination != nil {
                        directionsButton
                    }
                    Spacer(minLength: 8)
                }
                .padding(.leading, 13)
                .padding(.trailing, 14)
            }
        }
        // Preserve the approved top and bottom insets, adding the extra card
        // height entirely to the flexible gap above the action row. Min, not
        // fixed: a two-line personalized subtitle grows the card instead of
        // overflowing the glass panel. An event with no join link and no
        // location has no action row — the card hugs its text instead of
        // holding the row's slot open as dead air.
        .padding(.top, 20)
        .padding(.bottom, !isQuotePreview && !hasActionRow ? 20 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: isQuotePreview || !hasActionRow ? 0 : 140)
        // solidCardPlate's exact recipe, with the fill opened up so the deck's
        // swipe tint can mix into the plate during a drag (cardFill is plain
        // DS.Palette.card at rest — rendering-identical to solidCardPlate).
        // Shape-cast shadow, same as solidCardPlate: no compositingGroup, so
        // the card doesn't rasterize its whole content to derive the depth
        // pair on every frame it moves.
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(cardFill)
                .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)
                .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1.5)
        }
        .animation(.easeInOut(duration: 0.22), value: isWritingCopy)
    }

    // MARK: Swipe (dismiss) — SuggestionCard's affordance and tint, verbatim

    /// Left = dismiss (trash, red), fading in behind the sliding card exactly
    /// like the suggestion deck — one dismissal language across Home.
    private var swipeAffordance: some View {
        HStack {
            Spacer(minLength: 0)

            if dragOffset < 0 {
                Image(systemName: "trash")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(swipeColor)
                    .frame(width: 42, height: 42)
                    .background(swipeColor.opacity(0.12), in: Circle())
                    .padding(.trailing, 28)
                    .transition(.opacity)
            }
        }
        .opacity(min(abs(dragOffset) / 48.0, 1.0))
    }

    private var swipeColor: Color {
        Color(hex: 0xFF3B30)
    }

    /// The plate fill picks up the commit tint as the drag deepens — the
    /// suggestion deck's formula on the same card base.
    private var cardFill: Color {
        guard dragOffset != 0 else {
            return DS.Palette.card
        }

        let intensity = min(abs(dragOffset) / commitDistance, 1)
        let tintOpacity: CGFloat = 0.10 + (0.16 * intensity)
        return DS.Palette.card
            .mix(with: swipeColor.opacity(tintOpacity), by: 0.48)
    }

    private func handleSwipeChanged(translation: CGSize) {
        guard !isCompletingSwipe else { return }

        isSwipeActive = true
        // While a swipe is live, keep taps suppressed so releasing the finger
        // never fires the join/keyboard buttons underneath.
        DSInteractionGate.suppressTaps()
        // Dismiss is leftward-only: a claimed drag that wanders back rightward
        // parks at rest instead of revealing a phantom accept.
        dragOffset = min(0, rubberBand(translation.width, limit: maxDrag))
        updateCommitThresholdHaptic(for: dragOffset)
    }

    private func handleSwipeEnded(translation: CGSize) {
        defer {
            isSwipeActive = false
            wasPastCommitThreshold = false
        }
        guard !isCompletingSwipe, isSwipeActive else { return }

        DSInteractionGate.suppressTaps()
        if translation.width < -commitDistance {
            completeSwipe()
        } else {
            withAnimation(.smooth(duration: 0.2, extraBounce: 0)) {
                dragOffset = 0
            }
        }
    }

    /// Fling the card off leftward, then hand the dismissal to the surface
    /// (the store tombstones the event id and backfills the next meeting).
    private func completeSwipe() {
        isCompletingSwipe = true
        playSwipeHaptic(.medium, intensity: 1)
        withAnimation(.smooth(duration: 0.12, extraBounce: 0)) {
            dragOffset = -430
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            onDismiss?()
            isCompletingSwipe = false
        }

        // Dismiss swaps the slot's content synchronously (backfill or empty),
        // so snap the offset back unseen — the next meeting must not inherit
        // an off-screen card.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dragOffset = 0
            }
        }
    }

    private func updateCommitThresholdHaptic(for visibleOffset: CGFloat) {
        let isPastCommit = abs(visibleOffset) > commitDistance

        if isPastCommit, !wasPastCommitThreshold {
            playSwipeHaptic(.rigid, intensity: 0.82)
        }

        wasPastCommitThreshold = isPastCommit
    }

    private func playSwipeHaptic(_ style: DSHaptics.Style, intensity: CGFloat) {
        // Kept-generator route: constructing a cold generator at the commit
        // crossing is main-thread work mid-drag AND the documented
        // dropped-transient recipe (see DSHaptics.impactGenerators).
        DSHaptics.swipeThreshold(style, intensity: intensity)
    }

    private func rubberBand(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        let sign: CGFloat = value < 0 ? -1 : 1
        let magnitude = abs(value)

        guard magnitude > limit else {
            return value
        }

        return sign * (limit + (magnitude - limit) * 0.18)
    }

    /// Whether the card earns an action row at all: only a real video link
    /// ("Join meeting") or a location ("Get directions") puts buttons on the
    /// card — a plain event shows none, not a generic "view event".
    private var hasActionRow: Bool {
        meeting.joinLink != nil || directionsDestination != nil
    }

    private var directionsDestination: String? {
        guard let location = meeting.location?.trimmingCharacters(in: .whitespacesAndNewlines),
              !location.isEmpty else { return nil }
        return location
    }

    private var joinButton: some View {
        Button {
            guard DSInteractionGate.allowsTap else { return }
            onOpen()
        } label: {
            HStack(spacing: 6) {
                PersonaAsset.image("ThumbMeet")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                Text("Join meeting")
                    .font(.caption)
                    .fontWeight(.medium)
                    .tracking(-0.18)
                    .foregroundStyle(DS.Palette.ink)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Color(light: 0xFFFFFF, dark: 0x3A3A3C, lightOpacity: 0.50, darkOpacity: 0.60), in: Capsule(style: .continuous))
            .overlay { Capsule(style: .continuous).stroke(DS.Palette.hairlineSoft, lineWidth: 1.2) }
        }
        .buttonStyle(.hapticTap)
    }

    /// Opens the event's location in Google Maps (the app claims the
    /// universal link when installed; the web route handles the rest).
    private var directionsButton: some View {
        Button {
            guard DSInteractionGate.allowsTap else { return }
            openDirections()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(light: 0x007AFF, dark: 0x409CFF))
                Text("Get directions")
                    .font(.caption)
                    .fontWeight(.medium)
                    .tracking(-0.18)
                    .foregroundStyle(DS.Palette.ink)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Color(light: 0xFFFFFF, dark: 0x3A3A3C, lightOpacity: 0.50, darkOpacity: 0.60), in: Capsule(style: .continuous))
            .overlay { Capsule(style: .continuous).stroke(DS.Palette.hairlineSoft, lineWidth: 1.2) }
        }
        .buttonStyle(.hapticTap)
    }

    private func openDirections() {
        guard let destination = directionsDestination else { return }
        var components = URLComponents(string: "https://www.google.com/maps/dir/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: destination)
        ]
        guard let url = components?.url else { return }
        openURL(url)
    }

    private func sentenceCased(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + String(text.dropFirst())
    }

    /// Persona tone may affect the words, but never the basic headline casing.
    private var headlineText: String {
        sentenceCased(meeting.title)
            .replacingOccurrences(of: " am", with: " AM", options: [.caseInsensitive])
            .replacingOccurrences(of: " pm", with: " PM", options: [.caseInsensitive])
    }

    /// Iris's personalized one-liner (from /v1/home/meeting-card): the thing
    /// worth walking in knowing — sometimes useful, sometimes a nudge — instead
    /// of restating the clock the headline already shows. The calendar label is
    /// only the fallback for degenerate copy (empty, or repeating the headline).
    private var detailText: String {
        let line = meeting.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !line.isEmpty, line.caseInsensitiveCompare(meeting.title) != .orderedSame {
            return line
        }
        return calendarLabel
    }

    /// "Calendar · 10:30 AM" — the event's own wall-clock time; falls back to
    /// the raw event title only for legacy snapshots that predate `startsAt`.
    private var calendarLabel: String {
        if let scheduleLabel = meeting.scheduleLabel, !scheduleLabel.isEmpty {
            return "Calendar · \(normalizedClock(scheduleLabel))"
        }
        // Old personalized snapshots already carry the correct calendar-zone
        // clock in the compact headline ("... @ 10:30 am"). Prefer it over
        // converting a UTC `startsAt` without the event's original zone.
        if let at = meeting.title.range(of: "@", options: .backwards) {
            let clock = String(meeting.title[at.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !clock.isEmpty { return "Calendar · \(normalizedClock(clock))" }
        }
        guard let startsAt = meeting.startsAt, !startsAt.isEmpty else { return meeting.body }
        let formatted = EventDate.format(startsAt)
        if let separator = formatted.range(of: "·", options: .backwards) {
            let clock = normalizedClock(String(formatted[separator.upperBound...]).trimmingCharacters(in: .whitespaces))
            return "Calendar · \(clock)"
        }
        return formatted
    }

    private func normalizedClock(_ text: some StringProtocol) -> String {
        String(text)
            .replacingOccurrences(of: " am", with: " AM", options: [.caseInsensitive])
            .replacingOccurrences(of: " pm", with: " PM", options: [.caseInsensitive])
    }
}

// MARK: - Suggested task (hero fallback)

/// The hero slot when there's no meeting: the single most-relevant task to start
/// now, with a prominent Start action. Responsive take on the design app's
/// SuggestedTaskCard (glass panel, orb + title, trailing glyph, ink Start pill).
struct SuggestedTaskCard: View {
    let task: SuggestedTask
    var onStart: (SuggestedTask) -> Void = { _ in }
    /// Tapped the context chip — open the card's source (mail/event/task).
    var onOpenContext: (SuggestedTask) -> Void = { _ in }

    var body: some View {
        HeroCardScaffold(title: task.title, symbol: task.symbol, subtitle: task.subtitle) {
            if task.hasContext {
                HStack(spacing: 10) {
                    startButton
                    contextChip
                }
            } else {
                startButton
            }
        }
    }

    private var startButton: some View {
        Button {
            guard DSInteractionGate.allowsTap else { return }
            onStart(task)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                Text("Start")
                    .font(DS.Typography.label)
                    .tracking(-0.21)
            }
            .foregroundStyle(DS.Palette.onInk)
            .frame(width: 108, height: 42)
            .background(DS.Palette.ink, in: Capsule(style: .continuous))
        }
        .buttonStyle(.hapticTap)
    }

    /// A dezent context chip: source icon + one-line snippet → opens the source.
    private var contextChip: some View {
        Button {
            guard DSInteractionGate.allowsTap else { return }
            onOpenContext(task)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: contextIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Palette.ink.opacity(0.55))
                Text(task.contextSnippet ?? "")
                    .font(.system(size: 12, weight: .medium))
                    .tracking(-0.1)
                    .foregroundStyle(DS.Palette.ink.opacity(0.72))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DS.Palette.placeholder)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(DS.Palette.card.opacity(0.55), in: Capsule(style: .continuous))
            .overlay { Capsule(style: .continuous).stroke(DS.Palette.card.opacity(0.55), lineWidth: 0.8) }
        }
        .buttonStyle(.plain)
    }

    /// Source glyph by reference kind (structural, from the backend).
    private var contextIcon: String {
        switch task.referenceKind {
        case "mail-thread", "mail-message": "envelope.fill"
        case "calendar_event": "calendar"
        case "deep-task": "square.stack.3d.up.fill"
        default: "sparkles"
        }
    }
}

// MARK: - Quiet day (hero fallback)

/// The hero slot's calm fallback when there's no meeting to surface — so the top
/// of Home is never empty. Mirrors `MeetingCard`'s shape (orb, title, body, a
/// single pill) and keeps a gentle main action: plan the day with Iris.
struct QuietDayCard: View {
    var onPlan: () -> Void = {}

    var body: some View {
        Button {
            guard DSInteractionGate.allowsTap else { return }
            onPlan()
        } label: {
            HeroCardScaffold(
                title: "a quiet day",
                symbol: "sun.max",
                symbolStyle: DS.Palette.subtle,
                subtitle: "nothing on your calendar right now — i’ll surface anything that needs you."
            ) {
                planButton
            }
        }
        .buttonStyle(.hapticTap)
    }

    private var planButton: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(DS.Palette.ink)
            Text("plan your day")
                .font(DS.Typography.label)
                .tracking(-0.21)
                .foregroundStyle(DS.Palette.ink)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(DS.Palette.card, in: Capsule(style: .continuous))
        .overlay { Capsule(style: .continuous).stroke(DS.Palette.hairline, lineWidth: 1) }
    }
}

// MARK: - Chat shortcuts

/// The one-tap prompt rail under the greeting: a horizontal scroller of chat
/// starters (a ride, dinner, the inbox, …), each seeding a chat turn with its
/// prompt verbatim. The static catalog always renders; Iris-written pills for
/// THIS moment ("Uber to the Westin" at 2:30 am at the office) lead the rail
/// when they land, scrolling in where ghost capsules shimmered while the
/// writer worked — the same replace-with-shimmer idiom as the greeting line.
/// Registers its frame as a no-page zone so a horizontal drag scrolls the
/// rail instead of paging Home⇄Chat (MeetingCard's carve-out).
struct HomeChatShortcuts: View {
    let onTap: (QuickAction) -> Void

    /// Iris-written pills for this moment — lead the rail when present.
    var personalized: [QuickAction] = []
    /// A personalized set is in flight: the leading slot shows shimmer ghosts
    /// (replacing any pills already there, greeting-style) while the static
    /// chips stay put and tappable. Never holds the pull spinner — the store's
    /// generation is fire-and-forget.
    var isWriting = false

    /// Bleeds the rail to the screen edges from inside the page's gutter so
    /// chips scroll edge-to-edge (and the half-visible last chip advertises
    /// the scroll).
    var gutter: CGFloat = DS.Spacing.gutter

    @State private var pageZoneID = UUID()

    /// Ghost widths while writing: varied like real labels, one per expected
    /// pill (three on a cold rail, else however many are being replaced).
    private var ghostWidths: [CGFloat] {
        let base: [CGFloat] = [118, 92, 132, 104, 96]
        let count = personalized.isEmpty ? 3 : min(personalized.count, base.count)
        return Array(base.prefix(count))
    }

    /// Owner-finalized set and order ().
    static let shortcuts: [QuickAction] = [
        QuickAction(
            title: String(localized: "Get a coffee"),
            symbol: "cup.and.saucer.fill",
            seedPrompt: String(localized: "Order my usual coffee from somewhere close.")
        ),
        QuickAction(
            title: String(localized: "Grab a ride"),
            symbol: "car.fill",
            seedPrompt: String(localized: "Get me an Uber.")
        ),
        QuickAction(
            title: String(localized: "Book an appointment"),
            symbol: "calendar.badge.plus",
            seedPrompt: String(localized: "Book an appointment for me — I'll tell you what.")
        ),
        QuickAction(
            title: String(localized: "Make a reservation"),
            symbol: "fork.knife",
            seedPrompt: String(localized: "Find me a good restaurant and book a table.")
        ),
        QuickAction(
            title: String(localized: "Brief me"),
            symbol: "newspaper.fill",
            seedPrompt: String(localized: "Give me today's rundown — inbox, calendar, and news.")
        ),
        QuickAction(
            title: String(localized: "Find a gift"),
            symbol: "gift.fill",
            seedPrompt: String(localized: "Help me find a gift for someone.")
        ),
        QuickAction(
            title: String(localized: "Cancel my subscription"),
            symbol: "scissors",
            seedPrompt: String(localized: "Help me cancel a subscription.")
        ),
        QuickAction(
            title: String(localized: "Track my packages"),
            symbol: "shippingbox.fill",
            seedPrompt: String(localized: "Where are my packages? Check everything on the way.")
        ),
        QuickAction(
            title: String(localized: "Book a flight"),
            symbol: "airplane",
            seedPrompt: String(localized: "Look up flights for my next trip and help me book one.")
        )
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                if isWriting {
                    // The leading slot shimmers while Iris writes — ghosts
                    // stand where the personalized pills will land, so the
                    // static chips never shift when they do.
                    ForEach(Array(ghostWidths.enumerated()), id: \.offset) { _, width in
                        ShimmerChip(width: width)
                    }
                } else {
                    ForEach(personalized) { shortcut in
                        chip(shortcut)
                            // Scroll in from the leading edge when a set lands.
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                ForEach(Self.shortcuts) { shortcut in
                    chip(shortcut)
                }
            }
            .padding(.horizontal, gutter)
            // Room for the chip shadows: a tight scroller clips them into
            // hard-edged rectangles at the rail's top and bottom.
            .padding(.vertical, 6)
        }
        .padding(.horizontal, -gutter)
        .padding(.vertical, -6)
        // One curve for the whole swap: ghosts out, arrivals in, statics slide.
        .animation(.smooth(duration: 0.32, extraBounce: 0), value: personalized)
        .animation(.smooth(duration: 0.32, extraBounce: 0), value: isWriting)
        // A drag that starts on the rail scrolls it — never pages Home⇄Chat.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            SuggestionSwipeZones.update(pageZoneID, frame: frame)
        }
        .onDisappear { SuggestionSwipeZones.update(pageZoneID, frame: nil) }
    }

    private func chip(_ shortcut: QuickAction) -> some View {
        Button {
            guard DSInteractionGate.allowsTap else { return }
            onTap(shortcut)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: shortcut.symbol)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(DS.Palette.ink)
                    // Equal-width glyph slots so text starts on a steady rhythm
                    // chip to chip (SF symbols vary a lot in width).
                    .frame(width: 17)
                Text(shortcut.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(DS.Palette.ink)
            }
            .padding(.leading, 13)
            .padding(.trailing, 15)
            .frame(height: 37)
            // The menu-control recipe: quiet card plate + hairline. Tight
            // shadow pair — hugging the capsule, not blooming past it.
            .background {
                Capsule(style: .continuous)
                    .fill(DS.Palette.card)
                    .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                    .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
            }
            .overlay { Capsule(style: .continuous).stroke(DS.Palette.hairlineSoft, lineWidth: 1) }
        }
        .buttonStyle(.hapticTap)
    }
}

/// A ghost capsule with ShimmerBar's travelling highlight, standing where a
/// personalized chip will land. Same height and plate recipe as a real chip,
/// so the swap is a content change, not a layout jump.
private struct ShimmerChip: View {
    var width: CGFloat
    @State private var phase: CGFloat = -0.7

    var body: some View {
        Capsule(style: .continuous)
            .fill(DS.Palette.ink.opacity(0.07))
            .frame(width: width, height: 37)
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.65), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.55)
                    .offset(x: geo.size.width * phase)
                }
            }
            .clipShape(Capsule(style: .continuous))
            .overlay { Capsule(style: .continuous).stroke(DS.Palette.hairlineSoft, lineWidth: 1) }
            .onAppear {
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                    phase = 1.25
                }
            }
    }
}

// MARK: - Quick actions

/// The create affordances (Set reminder / New email / Automations) as evenly
/// distributed boxed tiles — icon over label, one line, no section header and
/// no scroller (three always fit, so nothing competes with Home⇄Chat paging;
/// the old scrolling pill row and its no-page-zone carve-out are gone).
struct QuickActionCreateTiles: View {
    let actions: [QuickAction]
    let onTap: (QuickAction) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(actions) { action in
                Button {
                    guard DSInteractionGate.allowsTap else { return }
                    onTap(action)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: action.symbol)
                            .font(.system(size: 17, weight: .regular))
                            .frame(height: 20)
                        Text(action.title)
                            .font(DS.Typography.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(DS.Palette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(DS.Palette.hairlineSoft, lineWidth: 1)
                    }
                }
                .buttonStyle(.hapticTap)
            }
        }
    }
}

// MARK: - Task

struct TaskCard: View {
    let task: ActiveTask
    var onTap: () -> Void = {}
    /// "Got it" on a terminal task's outcome panel — dismisses the Home pin.
    /// Only wired where the panel shows (Home's featured list).
    var onAcknowledge: (() -> Void)?
    /// Answer a parked task's pending question with one of its option chips —
    /// the label is sent verbatim as the ask_user answer.
    var onRespond: ((String) -> Void)?
    /// The needs-help panel's keyboard affordance: open the task thread with
    /// the composer already focused (free-text answer instead of the chips).
    var onOpenComposer: (() -> Void)?
    /// Failed task only: re-running its goal needs the task store, taken from the
    /// environment rather than threaded down as another closure — one more
    /// parameter at the Home call site tipped that body over the Swift
    /// type-checker's budget.
    @Environment(DeepTaskStore.self) private var deepTaskStore: DeepTaskStore?

    /// Failed task → re-run its goal as a fresh task. nil when we have no store
    /// or no backend id, in which case the chip falls back to opening the thread.
    private var retryAction: (() -> Void)? {
        guard let deepTaskStore, let deepTaskID = task.deepTaskID else { return nil }
        return {
            DSHaptics.tap()
            Task { await deepTaskStore.retry(deepTaskID) }
        }
    }

    /// Delete the task, reachable via long-press → Stop Task capsule only (no
    /// swipe: horizontal drags stay with the Home⇄Chat pager; the swipe mechanic
    /// belongs to suggestion cards). The design has no task-delete affordance,
    /// so this is a minimal, consistent one.
    var onDelete: (() -> Void)?
    /// Long-press menu's non-destructive action: pause a running task / resume
    /// a paused one. nil hides the button (e.g. history rows).
    var onPause: (() -> Void)?
    /// The pause button's label — "Pause" for running work, "Resume" once paused.
    var pauseLabel = "Pause"
    /// The id of the card currently showing its Stop Task menu in this list —
    /// only one at a time (opening another closes the previous). Owned by the
    /// parent list; the menu path only runs when `onDelete` is also set.
    var revealedDeleteId: Binding<AnyHashable?> = .constant(nil)

    var body: some View {
        if task.needsInput, let onDelete {
            // A STUCK task is still cancellable work: it keeps the panel
            // card's tap-gesture opening (the needs-help chips are real
            // buttons a wrapping Button would swallow) via the container's
            // gesture mode, so long-press → Stop Task works exactly like a
            // running task's.
            TaskStopMenuContainer(
                id: task.id,
                revealedId: revealedDeleteId,
                onTap: onTap,
                onDelete: onDelete,
                onPause: onPause,
                pauseLabel: pauseLabel,
                opensOnTapGesture: true
            ) {
                cardContent
            }
        } else if task.needsAcknowledge || task.needsInput {
            // A finished/failed card carries its OWN action buttons in the
            // outcome panel (Got it / Open) — and a parked card its option
            // chips + keyboard in the needs-help panel. Nested Buttons inside
            // a Button label don't receive their taps in SwiftUI — the outer
            // Button swallows them — so these cards open on a tap GESTURE
            // instead of a Button, leaving the panels' buttons to handle
            // their own taps.
            cardContent
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .onTapGesture {
                    // A page swipe moves the card WITH the finger, so touch-up
                    // still lands "inside" — the gate (held by the pager while
                    // it drags) is what keeps a swipe from opening the task.
                    guard DSInteractionGate.allowsTap else { return }
                    DSHaptics.tap(.light)
                    onTap()
                }
        } else if let onDelete {
            TaskStopMenuContainer(
                id: task.id,
                revealedId: revealedDeleteId,
                onTap: onTap,
                onDelete: onDelete,
                onPause: onPause,
                pauseLabel: pauseLabel
            ) {
                cardContent
            }
        } else {
            Button {
                guard DSInteractionGate.allowsTap else { return }
                onTap()
            } label: { cardContent }
                .buttonStyle(.hapticTap)
        }
    }

    /// The status accent for the pulse dot — the reference mock's amber for
    /// anything parked on the user (needs help AND failed), green for live or
    /// succeeded work, quiet grey for a stop.
    private var statusColor: Color {
        if task.needsInput { return TaskStateStyle.amber }
        if task.needsAcknowledge, let outcome = task.outcome {
            if outcome == "succeeded" { return TaskStateStyle.green }
            if outcome == "cancelled" { return DS.Palette.placeholder }
            return TaskStateStyle.amber
        }
        return DS.Palette.success
    }

    /// The reference design's under-title state line — icon + tinted label
    /// ("Needs help" amber, "Done" green, "Failed" red) in place of the grey
    /// subtitle whenever the task is parked or terminal. nil while it runs
    /// normally (the subtitle keeps that slot).
    private var statusBadge: (icon: String, label: String, color: Color)? {
        if task.needsInput { return ("checkmark.circle.fill", "Needs help", TaskStateStyle.amber) }
        guard task.needsAcknowledge, let outcome = task.outcome else { return nil }
        switch outcome {
        case "succeeded": return ("checkmark.circle.fill", "Done", TaskStateStyle.green)
        case "cancelled": return ("xmark.circle.fill", "Stopped", DS.Palette.placeholder)
        default: return ("exclamationmark.triangle.fill", "Failed", TaskStateStyle.red)
        }
    }

    // Geometry mirrors the design app's fixed-width TaskCard, translated to an
    // adaptive width: icon inset 20, icon→text gap 10, title column dropped 2pt
    // so the title baseline lands at the reference y=22, status cluster
    // top-aligned with the icon. (The progress track under the text was cut —
    // design: ugly — so the card is just the header row + any terminal panel.)
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Everything in the header row centers VERTICALLY: the icon and
            // the trailing status cluster sit at the card's midline whatever
            // the text column's height (one subtitle line or two).
            HStack(alignment: .center, spacing: 10) {
                taskIcon

                VStack(alignment: .leading, spacing: 2) {
                    // No minimumScaleFactor: cards whose titles barely overflowed
                    // rendered at a visibly different size than their neighbors —
                    // a straight tail-truncation keeps every card's type identical.
                    Text(task.title)
                        .font(DS.Typography.cardTitle)
                        .foregroundStyle(DS.Palette.inkBlack)
                        .lineLimit(1)
                    // A parked/terminal task wears its state HERE (reference
                    // design): tinted icon + label under the title. Only a
                    // normally-running task keeps the grey subtitle.
                    if let badge = statusBadge {
                        HStack(spacing: 4) {
                            Image(systemName: badge.icon)
                                .font(.system(size: 13, weight: .semibold))
                            Text(String(localized: String.LocalizationValue(badge.label)))
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(badge.color)
                    } else {
                        Text(task.subtitle)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.placeholder)
                            // Two lines of room: one line truncated most real task
                            // descriptions mid-thought; the card grows by one caption
                            // line at most.
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    // Design parity: the status dot rides every stateful card —
                    // live green, amber when the task needs the user (parked OR
                    // failed), green again once done.
                    if task.isActive || task.needsInput || task.needsAcknowledge {
                        PulseDot(color: statusColor)
                    }
                    // The elapsed timer keeps ticking through a park — the amber
                    // dot alone flags the stuck state (outcome-panel parity).
                    Text(task.timeRemaining)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.inkBlack)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }

            // A PARKED task wears its pending question as a full-width amber
            // panel — the live sibling of the terminal outcome panel below:
            // the agent's latest ask, its option chips as one-tap answers, and
            // a keyboard affordance that opens the thread composer-focused.
            if task.needsInput {
                TaskNeedsHelpPanel(
                    text: task.pendingQuestion ?? task.detail,
                    options: task.pendingOptions ?? [],
                    onRespond: { answer in onRespond?(answer) },
                    onOpen: onTap,
                    onOpenComposer: { (onOpenComposer ?? onTap)() }
                )
                .padding(.top, 12)
            }

            // Below that only a TERMINAL task shows anything (its outcome
            // panel). The old meta/context fourth line was cut for focus.
            if task.needsAcknowledge, let outcome = task.outcome {
                // A terminal task wears its outcome as a full-width panel (the
                // terminal sibling of the amber "Stuck" prompt): green DONE,
                // red FAILED, or a quiet grey STOPPED for a cancel — so no task
                // ever just vanishes. "Got it" dismisses the pin; the second
                // button goes into the thread to follow up.
                TaskOutcomePanel(
                    outcome: outcome,
                    text: task.detail,
                    onAcknowledge: { onAcknowledge?() },
                    // Non-failed chips open the thread (composer focused).
                    onOpen: { (onOpenComposer ?? onTap)() },
                    // Failed: actually re-run the goal.
                    onRetry: retryAction
                )
                .padding(.top, 12)
            }
        }
        // Tighter frame: the old 20/19 verticals left the cards visibly
        // airier than their content needs.
        .padding(.top, 14)
        .padding(.horizontal, 20)
        .padding(.bottom, task.needsAcknowledge ? 12 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The shared full-white plate — the muted glass tint here read a step
        // grey next to the suggestion cards in the same stack.
        .solidCardPlate()
    }

    /// The bundled app logo when known, else a real contact/brand icon from the
    /// task's enrichment, else a tinted category badge.
    @ViewBuilder private var taskIcon: some View {
        if task.appImage.isEmpty {
            HomeEntryAvatar(
                photoUrl: task.photoUrl,
                contactEmail: task.contactEmail,
                logoDomain: task.logoDomain,
                fallbackSymbol: task.displayIconSymbol,
                // Task icons stay in the app's ink family (chat-bubble black)
                // instead of the per-kind rainbow tints.
                monochromeFallback: true
            )
        } else {
            PersonaAsset.image(task.appImage)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 9.62, style: .continuous))
        }
    }
}

/// Wraps a task row with the long-press "Stop Task" affordance: the press lifts
/// the row and asks the screen's `taskStopMenuHost()` to dim everything else
/// and float a glass "Stop Task" capsule centered under it — the system context
/// menu's shape, but hand-rolled because `.contextMenu`'s lift animation fights
/// the card's interactive liquid glass and stutters; here the glass press
/// response plays untouched, then the lift/dim/capsule settle in. One open menu
/// per list (`revealedId`). Deliberately NO swipe-to-delete here — horizontal
/// drags on a task row stay with the enclosing pager/scroll (suggestion cards
/// keep their own swipe mechanic).
struct TaskStopMenuContainer<Content: View>: View {
    let id: AnyHashable
    var revealedId: Binding<AnyHashable?>
    let onTap: () -> Void
    let onDelete: () -> Void
    /// Optional non-destructive menu action (pause/resume). nil → stop-only.
    var onPause: (() -> Void)? = nil
    var pauseLabel = "Pause"
    /// The row surface's corner radius — the dim layer's cutout must trace it.
    var menuCornerRadius: CGFloat = DS.Radius.card
    /// Open on a tap GESTURE instead of wrapping the row in a Button. For
    /// panel cards (a stuck task's needs-help chips): buttons nested inside a
    /// Button label never receive their taps, but the long-press → Stop menu
    /// must still work on them.
    var opensOnTapGesture = false
    @ViewBuilder let content: Content

    /// True while THIS row's menu is up. The shared `revealedId` is the single
    /// source of truth now that the menu itself lives in `TaskStopMenuGesture`
    /// — it's claimed the instant the press opens the menu and released on
    /// dismiss, so the row's tap guard below reads it directly.
    private var isMenuActive: Bool { revealedId.wrappedValue == id }

    var body: some View {
        #if canImport(UIKit)
            tappableRow
                .taskStopMenu(
                    id: id,
                    revealedId: revealedId,
                    cornerRadius: menuCornerRadius,
                    pauseLabel: pauseLabel,
                    onPause: onPause,
                    onStop: onDelete
                )
        #else
            Button(action: onTap) { content }
                .buttonStyle(.hapticTapNoPress)
                .deleteContextMenu(onDelete)
        #endif
    }

    #if canImport(UIKit)
        @ViewBuilder private var tappableRow: some View {
            if opensOnTapGesture {
                content
                    .contentShape(RoundedRectangle(cornerRadius: menuCornerRadius, style: .continuous))
                    .onTapGesture {
                        guard DSInteractionGate.allowsTap else { return }
                        // While the menu is up the host's dim swallows every
                        // tap, so a press landing here can only be the
                        // finger-up ending the long-press that opened it.
                        if isMenuActive { return }
                        DSHaptics.tap(.light)
                        onTap()
                    }
            } else {
                Button {
                    guard DSInteractionGate.allowsTap else { return }
                    // Same finger-up rule as the gesture path above.
                    if isMenuActive { return }
                    onTap()
                } label: { content }
                    // No press scale here: the card's interactive glass already
                    // responds to the press, and a custom scale stutters it.
                    .buttonStyle(.hapticTapNoPress)
            }
        }
    #endif
}

/// The long-press → Stop menu itself, with NO tap handling: the lift, the press
/// gesture, and the anchor the screen's `taskStopMenuHost()` draws the dim and
/// capsule from. `TaskStopMenuContainer` layers a tappable row on top of this;
/// a surface that already owns its tap — the composer tray's pills, whose open
/// button lives inside the pill — wears it directly via `taskStopMenu(...)`.
struct TaskStopMenuGesture: ViewModifier {
    let id: AnyHashable
    let revealedId: Binding<AnyHashable?>
    let cornerRadius: CGFloat
    let pauseLabel: String
    let onPause: (() -> Void)?
    let onStop: () -> Void

    @State private var isMenuActive = false

    func body(content: Content) -> some View {
        content
            // The lift holds while the menu is up (the interactive glass's
            // own press response has already relaxed by then) and settles
            // back on dismiss — same shape as the system context menu's lift.
            .scaleEffect(isMenuActive ? taskMenuLiftScale : 1)
            // Simultaneous for the same reason as the chat bubbles (ChatRow):
            // a plain `.onLongPressGesture` would win touch arbitration over
            // the pager's horizontal pan and kill swipes that start on a row.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.22)
                    .onEnded { _ in showMenu() }
            )
            // The dim + capsule render at the screen root (taskStopMenuHost)
            // so they cover the other rows and float above the scroll clipping.
            .anchorPreference(key: TaskStopMenuPreferenceKey.self, value: .bounds) { anchor in
                guard isMenuActive else { return nil }
                return TaskStopMenuRequest(
                    id: id,
                    anchor: anchor,
                    cornerRadius: cornerRadius,
                    pauseLabel: pauseLabel,
                    onStop: { performFromMenu(onStop) },
                    onPause: onPause.map { pause in { performFromMenu(pause) } },
                    onDismiss: { dismissMenu() }
                )
            }
            .onChange(of: revealedId.wrappedValue) { _, newValue in
                if newValue != id, isMenuActive {
                    withAnimation(.snappy(duration: 0.18)) { isMenuActive = false }
                }
            }
    }

    private func showMenu() {
        guard !isMenuActive else { return }
        DSHaptics.tap(.medium)
        // Claim the one-open-at-a-time slot so a menu on another row — or on
        // the tray pill for the same task — closes (its onChange handles it).
        revealedId.wrappedValue = id
        withAnimation(.snappy(duration: 0.24)) { isMenuActive = true }
    }

    private func dismissMenu() {
        guard isMenuActive else { return }
        withAnimation(.snappy(duration: 0.18)) { isMenuActive = false }
        if revealedId.wrappedValue == id { revealedId.wrappedValue = nil }
    }

    private func performFromMenu(_ action: @escaping () -> Void) {
        DSHaptics.tap(.medium)
        dismissMenu()
        action()
    }
}

extension View {
    /// Attach the long-press "Stop Agent" menu to a view that handles its own
    /// tap. The screen root must carry `taskStopMenuHost()`, and `revealedId`
    /// must be the same binding every other stoppable surface uses — the host
    /// draws ONE menu, so two surfaces holding themselves open would leave the
    /// loser lifted with nothing under it.
    @ViewBuilder func taskStopMenu(
        id: AnyHashable,
        revealedId: Binding<AnyHashable?>,
        cornerRadius: CGFloat,
        pauseLabel: String = "Pause",
        onPause: (() -> Void)? = nil,
        onStop: @escaping () -> Void
    ) -> some View {
        #if canImport(UIKit)
            modifier(
                TaskStopMenuGesture(
                    id: id,
                    revealedId: revealedId,
                    cornerRadius: cornerRadius,
                    pauseLabel: pauseLabel,
                    onPause: onPause,
                    onStop: onStop
                )
            )
        #else
            deleteContextMenu(onStop)
        #endif
    }
}

/// How much a long-pressed row grows while its menu is up (system context
/// menus lift about this much). The dim cutout inflates by the same factor.
private let taskMenuLiftScale: CGFloat = 1.045

/// What an active row hands the screen so it can present the menu layer:
/// where the row is, how round its corners are, and what to do on stop/dismiss.
///
/// EQUATABLE ON PURPOSE — and the conformance is load-bearing: a preference
/// value SwiftUI can't compare is treated as changed on EVERY layout pass, so
/// each pass re-propagated this key from every task row to Home's full-screen
/// overlay host, whose re-layout re-ran the row preferences — a self-
/// sustaining invalidation loop that intermittently froze the app at launch
/// at 99% CPU (two captured samples both spinning in this key's reduce).
/// Closures are excluded from equality (same row ⇒ same handlers); the anchor
/// token is a stable reference the layer resolves at draw time.
struct TaskStopMenuRequest: Equatable {
    let id: AnyHashable
    let anchor: Anchor<CGRect>
    let cornerRadius: CGFloat
    let pauseLabel: String
    let onStop: () -> Void
    let onPause: (() -> Void)?
    let onDismiss: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.cornerRadius == rhs.cornerRadius && lhs.pauseLabel == rhs.pauseLabel
            && (lhs.onPause == nil) == (rhs.onPause == nil)
    }
}

struct TaskStopMenuPreferenceKey: PreferenceKey {
    static var defaultValue: TaskStopMenuRequest? { nil }
    static func reduce(value: inout TaskStopMenuRequest?, nextValue: () -> TaskStopMenuRequest?) {
        value = value ?? nextValue()
    }
}

extension View {
    /// Hosts the long-press "Stop Task" presentation for every
    /// TaskStopMenuContainer row in the subtree: a dim over the whole screen
    /// with a cutout so the lifted row stays bright, and the glass capsule
    /// centered under the row. Apply once at the screen root (Home page,
    /// task-history sheet) — rows request it via TaskStopMenuPreferenceKey.
    func taskStopMenuHost() -> some View {
        overlayPreferenceValue(TaskStopMenuPreferenceKey.self) { request in
            TaskStopMenuHostLayer(request: request)
                .ignoresSafeArea()
        }
    }
}

/// Keeps the layer MOUNTED through its fade-out (rendering the last request)
/// with hit-testing cut the instant the menu dismisses. A plain conditional
/// with a removal transition would keep the full-screen dim swallowing touches
/// for its whole fade, leaving a dead window where an immediate second
/// long-press on a row does nothing.
private struct TaskStopMenuHostLayer: View {
    let request: TaskStopMenuRequest?
    @State private var lastRequest: TaskStopMenuRequest?

    var body: some View {
        let active = request != nil
        ZStack {
            if let shown = request ?? lastRequest {
                TaskStopMenuLayer(request: shown, active: active)
            }
        }
        .allowsHitTesting(active)
        .onChange(of: request?.id) { _, _ in
            if request != nil { lastRequest = request }
        }
    }
}

/// The dim + capsule layer itself. Any tap on the dim (including on the row —
/// the dim covers it too, the cutout is only visual) dismisses, so the row's
/// own tap action can never fire underneath an open menu.
private struct TaskStopMenuLayer: View {
    let request: TaskStopMenuRequest
    let active: Bool

    /// False for the first frame after mounting so the initial presentation
    /// fades in too (the `active` animation can only animate CHANGES on an
    /// already-mounted view; this view mounts once and then stays).
    @State private var appeared = false

    private var shown: Bool { active && appeared }

    var body: some View {
        GeometryReader { proxy in
            let rect = proxy[request.anchor]
            let lifted = rect.insetBy(
                dx: -rect.width * (taskMenuLiftScale - 1) / 2,
                dy: -rect.height * (taskMenuLiftScale - 1) / 2
            )
            DimWithCutout(hole: lifted, cornerRadius: request.cornerRadius * taskMenuLiftScale)
                .fill(Color.black.opacity(0.18), style: FillStyle(eoFill: true))
                .contentShape(Rectangle())
                .onTapGesture { request.onDismiss() }
                .opacity(shown ? 1 : 0)
                .overlay {
                    TaskStopMenu(onStop: request.onStop, onPause: request.onPause, pauseLabel: request.pauseLabel)
                        .fixedSize()
                        // Centered under the lifted row; if the row sits at the
                        // very bottom of the screen, flip above it instead.
                        .position(
                            x: rect.midX,
                            y: lifted.maxY + 48 > proxy.size.height
                                ? lifted.minY - 28
                                : lifted.maxY + 28
                        )
                        .offset(y: shown ? 0 : -8)
                        .opacity(shown ? 1 : 0)
                }
                .animation(.snappy(duration: 0.22), value: shown)
        }
        .onAppear {
            withAnimation(.snappy(duration: 0.22)) { appeared = true }
        }
    }
}

/// The full-screen dim with a rounded-rect hole punched over the lifted row
/// (fill with `FillStyle(eoFill: true)`).
private struct DimWithCutout: Shape {
    let hole: CGRect
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRoundedRect(
            in: hole,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius),
            style: .continuous
        )
        return path
    }
}

/// The glass "Stop Task" capsule shown under a long-pressed task row.
private struct TaskStopMenu: View {
    let onStop: () -> Void
    var onPause: (() -> Void)? = nil
    var pauseLabel = "Pause"

    var body: some View {
        HStack(spacing: 0) {
            if let onPause {
                Button(action: onPause) {
                    Label(pauseLabel, systemImage: pauseLabel == "Resume" ? "play.circle" : "pause.circle")
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.Palette.ink)
            }
            Button(action: onStop) {
                Label("Stop Agent", systemImage: "stop.circle")
                    .padding(.horizontal, 16)
                    .frame(height: 40)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(hex: 0xFF3B30))
        }
        .font(.system(size: 12, weight: .medium))
        .labelStyle(.titleAndIcon)
        .frame(height: 40)
        .smallGlassCapsule()
        .accessibilityElement(children: .contain)
    }
}

extension View {
    /// Attach a destructive "Stop Task" long-press menu only when a handler is
    /// given (an empty context menu would still hijack the long-press). Only
    /// the macOS fallback uses this; on iOS the rows show TaskStopMenu instead.
    @ViewBuilder func deleteContextMenu(_ onDelete: (() -> Void)?) -> some View {
        if let onDelete {
            contextMenu {
                Button(role: .destructive, action: onDelete) {
                    Label("Stop Agent", systemImage: "stop.circle")
                }
            }
        } else {
            self
        }
    }
}

/// The task card's meta row. Two shapes, mirroring the design's TaskMetaLine:
/// an ORDER-style line (vendor + fork.knife + items) when the task carries
/// structured order data, else a DESCRIPTIVE line (clipboard + the task's context
/// sentence) — so a plain agent task still shows what it's about.
private struct TaskMetaLine: View {
    let task: ActiveTask

    private static let primary = Color(hex: 0x161616)
    private static let secondary = Color(hex: 0x777777)

    var body: some View {
        HStack(spacing: 5) {
            if task.hasMeta {
                Image(systemName: task.vendorSymbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Self.primary)
                Text(task.vendor)
                    .font(.system(size: 10, weight: .medium))
                    .tracking(-0.10)
                    .foregroundStyle(Self.primary)
                if !task.itemsSummary.isEmpty {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Self.secondary)
                        .padding(.leading, 3)
                    Text(task.itemsSummary)
                        .font(.system(size: 10, weight: .medium))
                        .tracking(-0.10)
                        .foregroundStyle(Self.secondary)
                        .lineLimit(1)
                }
            } else {
                Image(systemName: "list.clipboard")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Self.secondary)
                Text(task.detail)
                    .font(.system(size: 10, weight: .medium))
                    .tracking(-0.10)
                    .foregroundStyle(Self.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.black)
        }
    }
}

/// The terminal-task outcome — the green/red sibling of the beige "needs
/// help" bubble. A succeeded task reports what it achieved, a failed one why
/// it failed (both from the agent's own final report), with the dark check
/// circle to dismiss the Home pin and a chip into the thread to read on or
/// steer again ("Retry" on a failure).
private struct TaskOutcomePanel: View {
    /// "succeeded" | "failed" | "cancelled" — drives the panel's family.
    let outcome: String
    let text: String
    let onAcknowledge: () -> Void
    let onOpen: () -> Void
    /// Failed only: run the goal again as a fresh task. Absent → the chip falls
    /// back to opening the thread.
    var onRetry: (() -> Void)?

    private var succeeded: Bool { outcome == "succeeded" }
    private var cancelled: Bool { outcome == "cancelled" }

    /// The bubble wash per family (reference mock, normalized to the white
    /// card): soft green for done, soft rose for failed, quiet grey for a stop.
    private var bubbleColor: Color {
        if succeeded { return TaskStateStyle.bubbleGreen }
        if cancelled { return TaskStateStyle.bubbleGrey }
        return TaskStateStyle.bubbleRed
    }

    /// The leading chip under the bubble: a failed task offers "Retry" (which
    /// RE-RUNS the goal — a failed task is terminal, so the old behaviour of
    /// opening the thread to "steer it again" was a dead end: steer 404s on
    /// terminal rows); anything else opens the task to read on.
    private var chipLabel: String {
        succeeded || cancelled ? "Open agent" : "Retry"
    }

    /// Failed → retry when we have a handler; everything else opens the thread.
    private var chipAction: () -> Void {
        if !succeeded, !cancelled, let onRetry { return onRetry }
        return onOpen
    }

    /// The agent's report arrives as markdown; the panel is a plain-text digest
    /// (the rendered version lives in the thread), so strip the syntax that
    /// reads as noise at this size: rule lines ("---"), emphasis markers,
    /// heading hashes. Collapse the blank runs the stripping leaves behind.
    private var displayText: String {
        let lines = text.components(separatedBy: "\n")
            .map { line -> String in
                var cleaned = line.trimmingCharacters(in: .whitespaces)
                if cleaned.range(of: "^[-*_]{3,}$", options: .regularExpression) != nil { return "" }
                if let heading = cleaned.range(of: "^#{1,6}\\s+", options: .regularExpression) {
                    cleaned = String(cleaned[heading.upperBound...])
                }
                return cleaned
                    .replacingOccurrences(of: "**", with: "")
                    .replacingOccurrences(of: "`", with: "")
            }
        return lines.joined(separator: "\n")
            .replacingOccurrences(of: "\n{2,}", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        // Reference design: a borderless tinted bubble carries the agent's
        // report (the state label lives under the card title now), and the
        // actions sit OUTSIDE it on the card plate — a grey chip plus the
        // dark check circle that acknowledges the pin.
        VStack(alignment: .leading, spacing: 12) {
            if !displayText.isEmpty {
                // The server-fitted outcome digest — written to the panel's
                // character budget, so it shows IN FULL (no lineLimit: nothing
                // in the task view may be cut off). Legacy rows fall back to
                // the raw result, where the markdown scrub above still applies.
                Text(displayText)
                    .font(.system(size: 15))
                    .foregroundStyle(TaskStateStyle.bubbleText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(bubbleColor, in: RoundedRectangle(cornerRadius: DS.Radius.bubble, style: .continuous))
            }
            HStack(spacing: 8) {
                TaskStateChip(label: chipLabel) { onOpen() }
                Spacer(minLength: 0)
                acknowledgeButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The reference mock's dark circle-check — "got it", dismisses the pin.
    private var acknowledgeButton: some View {
        Button {
            guard DSInteractionGate.allowsTap else { return }
            DSHaptics.tap(.light)
            onAcknowledge()
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(TaskStateStyle.checkCircle, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Got it")
    }
}

/// The parked-task panel — the amber "needs help" sibling of TaskOutcomePanel:
/// same geometry and type, tinted to the stuck family. Shows the agent's
/// pending question in full, its option chips as one-tap answers, and a
/// trailing keyboard button that opens the thread with the composer focused.
private struct TaskNeedsHelpPanel: View {
    let text: String
    let options: [String]
    let onRespond: (String) -> Void
    /// Open the task thread plainly — the collapsed "Answer in chat" path,
    /// where the full question and every option render at conversation size.
    let onOpen: () -> Void
    let onOpenComposer: () -> Void

    /// Which option was tapped — freezes the chips and shows a spinner on the
    /// chosen one until the store refresh swaps the card's state.
    @State private var answering: String?

    /// Inline chips only while they stay TIDY — a few short answers ("Email",
    /// "Voicemail", "Approve"). Many or essay-length options turned the card
    /// into a chip wall, so those collapse to one "Answer in chat".
    private var showsInlineOptions: Bool {
        !options.isEmpty && options.count <= 3 && options.allSatisfy { $0.count <= 22 }
    }

    var body: some View {
        // Reference design: the amber "Needs help" label lives under the card
        // title now, so the panel is just a borderless beige bubble with the
        // agent's ask, and the answer chips sit OUTSIDE it on the card plate
        // with the keyboard circle at the trailing edge.
        VStack(alignment: .leading, spacing: 12) {
            if !text.isEmpty {
                // The agent's most recent ask, in full — nothing in the task
                // view may be cut off (outcome-panel rule).
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(TaskStateStyle.bubbleText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(TaskStateStyle.bubbleAmber, in: RoundedRectangle(cornerRadius: DS.Radius.bubble, style: .continuous))
            }

            if showsInlineOptions {
                // Tidy chips wrap (FlowLayout) inside a lane that reserves the
                // keyboard's column, and the keyboard OVERLAYS bottom-trailing —
                // always at the panel's right edge, level with the last row,
                // never fighting the flow for width.
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                        optionButton(option)
                    }
                }
                .padding(.trailing, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottomTrailing) { keyboardButton }
            } else {
                // No options, or an untidy pile of them: one calm door into
                // the thread (where the full exchange renders at conversation
                // size), plus the keyboard for a typed answer. The door shows
                // for BOTH cases — an open-ended question without chips still
                // needs a visible way into the task, not just the keyboard.
                HStack(spacing: 8) {
                    TaskStateChip(label: "Open agent") { onOpen() }
                    Spacer(minLength: 0)
                    keyboardButton
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Every answer chip wears the reference design's quiet grey capsule.
    private func optionButton(_ label: String) -> some View {
        Button {
            guard DSInteractionGate.allowsTap, answering == nil else { return }
            DSHaptics.tap(.light)
            answering = label
            onRespond(label)
        } label: {
            Group {
                if answering == label {
                    ProgressView().tint(DS.Palette.ink).scaleEffect(0.7)
                } else {
                    Text(label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DS.Palette.ink)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(TaskStateStyle.chipFill, in: Capsule(style: .continuous))
            .opacity(answering != nil && answering != label ? 0.4 : 1)
        }
        .buttonStyle(.plain)
    }

    /// Suggestion-card parity: the same 32pt keyboard circle, here meaning
    /// "answer in your own words" — opens the thread, composer focused.
    private var keyboardButton: some View {
        Button {
            guard DSInteractionGate.allowsTap else { return }
            DSHaptics.tap(.light)
            onOpenComposer()
        } label: {
            Image(systemName: "keyboard")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Palette.ink)
                .frame(width: 32, height: 32)
                .background(Color(light: 0xFFFFFF, dark: 0x3A3A3C, lightOpacity: 0.50, darkOpacity: 0.60), in: Circle())
                .overlay { Circle().stroke(DS.Palette.hairlineSoft, lineWidth: 1.2) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Answer with the keyboard")
    }
}

/// The task-state family lives in the design system now (`DS.TaskState`) so
/// the chat task surfaces wear the identical palette; the local name stays
/// for the call sites below.
private typealias TaskStateStyle = DS.TaskState

/// The mock's grey action capsule under a task bubble ("Say Yes", "Retry",
/// "Open task") — one shared shape so every task state speaks it identically.
private struct TaskStateChip: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            guard DSInteractionGate.allowsTap else { return }
            DSHaptics.tap(.light)
            action()
        } label: {
            Text(String(localized: String.LocalizationValue(label)))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DS.Palette.ink)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(height: 32)
                .background(TaskStateStyle.chipFill, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Suggestion

/// The PRIMARY thing an expanded suggestion card should let you do — derived
/// structurally from the card's backend actions (and kind), never from copy.
/// This is what makes each expanded card its OWN experience instead of every
/// card funnelling into the same reply/draft editor: a pending RSVP leads with
/// Accept / Decline, an outcome ("… confirmed your cancellation") is a glance
/// with Got it, a link previews-and-opens, a hand-off leads with one confirm,
/// and only a genuine drafted reply keeps the draft editor.
/// The scroll anchor of a card's draft box. A surface that hosts cards inside a
/// ScrollViewReader lifts to this when the draft takes focus, so the box lands
/// fully in view with the keyboard directly beneath it
/// tapping a draft used to leave it half-under the keyboard).
struct SuggestionDraftTarget: Hashable {
    let cardID: UUID
}

enum SuggestionCardIntent {
    case reply // a drafted reply is the point → the draft editor (unchanged)
    case invite // a pending RSVP → Accept / Decline lead, event context prominent
    case scheduling // Iris offers to set up a meeting → create_meeting leads
    case link // a self-contained link → preview + open in one tap
    case info // an outcome / heads-up → glance + Got it, no composer
    case delegation // a concrete task to hand off → one "Let Iris handle it"
    case dailySync // a daily digest / agenda → the lines as rows + Got it
    case lifeMatter // a LIFE.MD matter (V2 engine) → context block leads, then its chips
    case setup // a first-session setup step (permission ask / intro call) → one decisive chip
    case generic // anything ambiguous → today's draft-forward panel (unchanged)
}

/// The ONE action-chip grammar shared by every suggestion panel (the intent
/// panels' Accept/Decline/Confirm and the generated-action panel's chips), so no
/// chip can drift off-design. Font, capsule metrics, fill and hairline live here
/// once — filled = the biased blue primary, unfilled = a white hairline pill.
@ViewBuilder
func suggestionChipLabel(_ label: String, icon: String? = nil, filled: Bool = false) -> some View {
    HStack(spacing: 6) {
        if let icon {
            Image(systemName: icon).font(.system(size: 13, weight: .medium))
        }
        Text(String(localized: String.LocalizationValue(label)))
            .font(.system(size: 15, weight: .medium))
            .tracking(-0.2)
            .lineLimit(1)
    }
    .foregroundStyle(filled ? .white : DS.Palette.ink)
    .padding(.horizontal, 19)
    .frame(height: 40)
    // Reference mock (): the primary chip is the charcoal
    // primary-action capsule; secondaries are white pills held by a #EDEDED
    // hairline and a whisper of shadow. Both 15pt medium, height 40.
    .background {
        if filled {
            DSPrimaryActionSurface(shape: Capsule(style: .continuous))
        } else {
            Capsule(style: .continuous).fill(DS.Palette.card)
                .overlay { Capsule(style: .continuous).stroke(
                    Color(light: 0xEDEDED, dark: 0xFFFFFF, lightOpacity: 1, darkOpacity: 0.14),
                    lineWidth: 1
                ) }
                .shadow(color: .black.opacity(0.05), radius: 2.5, x: 0, y: 1.5)
        }
    }
    // A chip sizes to its LABEL and never truncates: fixedSize refuses horizontal
    // compression, so a tight row overflows (wrap the row — FlowLayout) rather
    // than ellipsizing inside the pill. (Backend also caps labels ~20 chars.)
    .fixedSize(horizontal: true, vertical: false)
}

/// The quiet all-caps kind tag ("SUGGESTION" / "UPDATE") a card wears above
/// its title in the merged For-you deck — the mixed list stays legible
/// per-card without a loud badge (monochrome doctrine).
struct CardKindTag: View {
    let label: LocalizedStringKey

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .bold))
            .tracking(0.9)
            .textCase(.uppercase)
            .foregroundStyle(DS.Palette.placeholder)
    }
}

struct SuggestionCard: View, Equatable {
    /// Gate re-renders on the VALUE inputs only (the ChatRow/ChatScreen idiom).
    /// Home's body re-evaluates on every task poll — a store tick every 3s,
    /// plus every unrelated @State change on the page — and each pass hands
    /// every card a freshly allocated set of closures, which alone forced this
    /// (heavy: mail meta, chips, date formatting, a draft editor) body to
    /// re-run for every visible card. The closures all dispatch into stores or
    /// call HomeScreen methods, so a pass that changed nothing but their
    /// identity has nothing to show.
    ///
    /// Observation is unaffected: this view reads `settings`/`profile` from the
    /// environment inside its own body, so a store change still updates it —
    /// this only suppresses PARENT-driven churn.
    nonisolated static func == (lhs: SuggestionCard, rhs: SuggestionCard) -> Bool {
        lhs.suggestion == rhs.suggestion
            && lhs.showsKindTag == rhs.showsKindTag
            && lhs.isUnread == rhs.isUnread
            && lhs.startExpanded == rhs.startExpanded
            && lhs.startSentReply == rhs.startSentReply
            && lhs.startDoneDailyChips == rhs.startDoneDailyChips
            // Swipe-ability is a function of whether the surface passed a
            // delete handler — a nil/non-nil flip changes what the card DOES,
            // so it must not be gated away.
            && (lhs.onDelete == nil) == (rhs.onDelete == nil)
    }

    let suggestion: Suggestion
    var onTap: () -> Void = {}
    /// Swipe-left commit (dismiss) — the ONLY swipe on a suggestion. Swiping is
    /// enabled when this is provided (Home wires it; other surfaces keep a
    /// plain card).
    var onDelete: ((Suggestion) -> Void)?
    /// Run the suggestion's primary action. NOT a swipe anymore (accept
    /// must be deliberate, never a flick) — only the expanded panel's dismiss
    /// chip falls back to it.
    var onExecute: ((Suggestion) -> Void)?
    /// Run ONE specific backend action from the expanded calendar-invite view
    /// (a reply draft, "add to calendar", …). Wired only where the card can act.
    var onRunAction: ((Suggestion, SuggestionActionItem, String?) -> Void)?
    /// The long-press menu's Snooze pick (a shared SnoozePreset) — the surface
    /// hides the card and defers the server snooze behind its undo window,
    /// resolving the preset's return time at commit. Wired only where the
    /// card can act.
    var onRemind: ((Suggestion, SnoozePreset) -> Void)?
    /// Execute a backend-GENERATED action (reply option/send, meeting confirm,
    /// remind, …) — POSTs and returns the typed outcome the panel morphs on
    /// (the answer, "In calendar", "Reminder set"). `editedBody` carries the
    /// user-edited reply_send draft. Nil where the surface can't act.
    var onGeneratedAction: ((Suggestion, GeneratedAction, String?) async -> HomeStore.GeneratedActionOutcome)?
    /// The KEYBOARD affordance: compose a typed reply to this card on the chat
    /// page (reply-to-suggestion mode). Surfaces that don't wire it fall back
    /// to `onTap` (the chat sheet), the icon's old behaviour.
    var onComposeReply: ((Suggestion) -> Void)?
    /// The card's draft box took focus. A scrolling surface (Home) lifts the box
    /// clear of the keyboard; surfaces that don't wire it keep today's behaviour.
    var onDraftFocus: ((SuggestionDraftTarget) -> Void)?
    /// Fired when an inline expand needs a scroll reveal, with the plate's
    /// global frame — Home scrolls the card into view when its panel opened
    /// below the fold. Fires the moment the growing plate first spills past
    /// the composer (so the glide starts with the expansion, not after it),
    /// and again once the height animation settles so the final geometry
    /// corrects a glide that launched against a mid-flight frame.
    var onExpanded: ((Suggestion, CGRect) -> Void)?

    /// The floating composer overlays roughly the bottom ~110pt of the screen;
    /// a plate ending above this line is fully readable. Shared with Home's
    /// reveal guard so the card and the surface agree on where the fold is.
    static let composerFoldInset: CGFloat = 110

    /// Wear the quiet "SUGGESTION" kind tag above the title — on in the merged
    /// For-you deck (mixed with Updates), off on single-kind surfaces.
    var showsKindTag = false
    /// Semibold title while unread; regular once read. Read = the user
    /// expanded the card inline or opened its sheet — same grammar as the
    /// Updates rows.
    var isUnread = true
    /// The user just read the card (expand or open) — the surface persists
    /// the mark that drives `isUnread`.
    var onMarkRead: (() -> Void)?

    @Environment(\.openURL) private var openURL

    // Swipe state machine, ported from the design app's SuggestionCard
    // (HomeSections.swift): rubber-banded drag, 74pt commit with a rigid haptic
    // at the threshold, fling off-screen on commit.
    @State private var dragOffset: CGFloat = 0
    @State private var isSwipeActive = false
    @State private var isCompletingSwipe = false
    @State private var wasPastCommitThreshold = false
    /// A calendar invite expanded inline (details + any real actions). Local only —
    /// collapsing NEVER dismisses the card, it just closes the panel.
    @State private var isExpanded = false
    /// The user-picked draft variant (a send_draft action id) filling the box;
    /// nil = the backend's primary draft.
    @State private var selectedDraftID: UUID?
    @State private var editedDraftBody = ""
    /// Tap on the (read-only) draft box → the modal edit sheet, which the
    /// keyboard can never bury.
    @State private var editingDraft = false
    @State private var editedDraftSourceID: UUID?
    /// Daily-sync line chips already run (by chip id) — show their done state.
    @State private var executedDailyChips: Set<String> = []
    /// The in-app email viewer ("View email"), prefetched while expanded.
    @State private var mailSheetShown = false
    /// Non-observed scratch for the expand reveal. Nothing in `body` reads
    /// these — they only feed the spill trigger and headerTapped's +0.35s
    /// settled pass — so they must NOT be @State: while expanded the global
    /// frame changes on EVERY frame of the grow animation and every scroll
    /// frame, and a @State write re-ran this whole (heavy) card body each
    /// time. Mutating a plain class held in @State invalidates nothing.
    private final class RevealScratch {
        /// The plate's live global frame — read (post-animation) by the expand
        /// reveal to decide whether the grown panel spilled off-screen.
        var plateFrame: CGRect = .zero
        /// Armed on expand: the FIRST geometry tick that shows the growing
        /// plate spilling past the composer fires the reveal, so the glide
        /// starts with the expansion instead of 0.35s after it.
        var revealOnSpill = false
    }

    @State private var reveal = RevealScratch()
    @Environment(SettingsStore.self) private var settings
    /// Optional: demo/preview rigs render cards without ProfileStore.
    @Environment(ProfileStore.self) private var profile: ProfileStore?
    private var assistantName: String { profile?.assistantName ?? ProfileStore.defaultAssistantName }
    /// Preview/QA only: render the card already expanded (headless screenshots).
    var startExpanded = false
    /// Preview/QA only: seed the POST-ACTION morph states, which a live card only
    /// reaches by tapping (a generated reply → its sent thread-line, a daily chip
    /// → its green done state). Lets the demo gallery show the terminal states
    /// statically instead of only the pre-tap ones. (The bell has no morph — it
    /// opens the snooze menu and the surface hides the card.)
    var startSentReply: String?
    var startDoneDailyChips: Set<String> = []

    private let maxDrag: CGFloat = 104
    private let commitDistance: CGFloat = 74

    private var isSwipeable: Bool { onDelete != nil }

    var body: some View {
        Group {
            #if canImport(UIKit)
                if isSwipeable {
                    ZStack {
                        swipeAffordance
                        cardButton.offset(x: dragOffset)
                    }
                    .overlay {
                        // Leftward only: reject is the sole swipe. Rightward drags
                        // never begin here, so they stay with the Home⇄Chat pager.
                        //
                        // The pan's real edge band is the 18% page-edge stripe
                        // (enforced inside gestureRecognizerShouldBegin via
                        // pageEdgeFraction); this per-attachment value only ever
                        // WIDENS it, so 16 keeps the left-edge menu strip clear
                        // and otherwise defers to the shared contract. Reject
                        // flicks start from the card's middle band.
                        HorizontalSwipeGestureAttachment(
                            edgeSwipeWidth: 16,
                            usesPageEdgeStripes: true,
                            locksVerticalScroll: true,
                            allowsRightward: false,
                            onChanged: handleSwipeChanged(translation:),
                            onEnded: handleSwipeEnded(translation:)
                        )
                    }
                    // Publish the card's live frame as the pager's no-page zone: a
                    // drag that STARTS here never pages, whether or not the swipe
                    // pan above ends up claiming it. Tracks scrolling (the frame is
                    // global) and deregisters when the card leaves.
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                        SuggestionSwipeZones.update(suggestion.id, frame: frame)
                    }
                    .onDisappear { SuggestionSwipeZones.update(suggestion.id, frame: nil) }
                } else {
                    cardButton
                }
            #else
                cardButton
            #endif
        }
        // STILL WORKING: the rule has fired and the card is up, but the run
        // that fills it in has not landed. The server sorts it below the
        // finished feed; this is the rest of the same state — drained of
        // colour, inert, and spinning.
        //
        // allowsHitTesting(false) rather than a disabled Button: the card is a
        // stack of independent touch targets (header toggle, swipe attachment,
        // action chips), and disabling them one by one leaves whichever is
        // added next live by default. Killing hits at the root means expand,
        // swipe-to-dismiss and every chip are all inert together — there is
        // nothing to act on yet, and a dismiss here would race the run.
        .grayscale(suggestion.isPending ? 1 : 0)
        .opacity(suggestion.isPending ? 0.55 : 1)
        // Outside the fade, so the spinner reads at full strength against the
        // card it is greying out.
        .overlay {
            if suggestion.isPending {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.large)
                    .scaleEffect(1.5)
                    .tint(.secondary)
                    .accessibilityLabel("Working on it")
            }
        }
        .allowsHitTesting(!suggestion.isPending)
        .animation(.easeInOut(duration: 0.25), value: suggestion.isPending)
    }

    private var cardButton: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The header row toggles the drop-down. It's a tappable row (not a
            // Button) so inner controls keep their own touches without nesting
            // buttons.
            //
            // Owner spec: a COLLAPSED card has NO buttons at all — just avatar,
            // title, context and the chevron. Every action (primary first) lives
            // in the expanded panel only.
            //
            // CARD_GRAMMAR swaps that drawing for the deck's T1 led card, which
            // DOES carry its pills collapsed (R3: a collapsed card is a
            // complete, answerable thought). Only the drawing changes here —
            // swipe, expansion, the draft rail and every callback below are
            // untouched, so the flag is a pure visual A/B.
            if CardGrammar.isOn, let model = suggestion.grammarCard(isUnread: isUnread) {
                GrammarT1Card(model: model, onPillTap: grammarPillTapped).content
                    .padding(DS.Metrics.cardPadding)
            } else {
                headerRow
            }

            if suggestion.isExpandable, isExpanded {
                // The panel's OWN fade, decoupled from the plate's height curve
                //. Opening: a short fade in behind the
                // growing plate. Closing: the content is gone in 90ms — the
                // chips must not ride the collapse down (a move/slide removal
                // made them drift and linger over the shrinking card).
                expandedDetailSection
                    .transition(.asymmetric(
                        insertion: AnyTransition.opacity.animation(.easeOut(duration: 0.20).delay(0.04)),
                        removal: AnyTransition.opacity.animation(.easeIn(duration: 0.09))
                    ))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        // The padding ring around the content taps like the row itself (inner
        // buttons — chips, actions in the expanded detail — still win their
        // own touches, so this only catches otherwise-dead card area).
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .onTapGesture {
            guard !isExpanded else { return }
            headerTapped()
        }
        // Reference mock (): the card is a WHITE PLATE with a soft
        // drop shadow, not a glass panel — the swipe tint still mixes into the
        // plate fill during a drag. Shape-cast shadow (see solidCardPlate):
        // this card's height ANIMATES on expand, and the old compositing
        // group re-rasterized the whole card to derive the shadow at every
        // intermediate height.
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(cardFill)
                .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)
                .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1.5)
        }
        // UITest handle: locate (expandable) cards without matching their text.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(suggestion.isExpandable ? "suggestion-card-expandable" : "suggestion-card")
        // `plateFrame` feeds ONLY the post-expand scroll reveal (read at +0.35s
        // in headerTapped), so it's needed only while the card is expanded —
        // and it lives in the non-observed `reveal` box (NOT @State): the
        // global frame changes on every frame of the grow animation and every
        // scroll frame while expanded, and a @State write here re-ran the
        // whole (heavy) SuggestionCard body each time.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            guard isExpanded else { return }
            reveal.plateFrame = frame
            // First tick where the growing plate crosses the fold → start the
            // glide NOW. The settled pass in headerTapped re-checks the final
            // frame; an expand that never spills never scrolls.
            if reveal.revealOnSpill, frame.maxY > UIScreen.main.bounds.height - Self.composerFoldInset {
                reveal.revealOnSpill = false
                onExpanded?(suggestion, frame)
            }
        }
        .onAppear {
            syncDraftEditorIfNeeded(force: editedDraftSourceID == nil)
            // Same rule as headerTapped: under the grammar there is no expanded
            // state at all, so a surface that asks for one (the preview hosts,
            // a deep link into an expanded card) gets the collapsed card and
            // its sheet instead. Without this the old panel renders UNDER a
            // grammar card and the screen shows both card languages at once.
            if startExpanded, suggestion.isExpandable, !CardGrammar.isOn { isExpanded = true }
            if !startDoneDailyChips.isEmpty { executedDailyChips = startDoneDailyChips }
        }
        .onChange(of: selectedSend?.id) { _, _ in
            syncDraftEditorIfNeeded(force: true)
        }
        // Long-press → the same native context menu as a chat bubble (the
        // bell + keyboard circles' replacement): Reply, plus Snooze › the
        // shared presets. Armed only where the card can act — reply previews
        // and demo renders stay inert.
        .cardContextMenu(
            isEnabled: onRemind != nil || onComposeReply != nil,
            onReply: { composeOwnReply() },
            onSnooze: onRemind == nil ? nil : { preset in onRemind?(suggestion, preset) }
        )
    }

    /// One shared header action: expandables toggle inline; everything else
    /// opens its chat sheet. Swipe-release and interaction-gate guards apply
    /// no matter which surface (header row or card padding) took the tap.
    /// A pill on the collapsed grammar card. Work the agent does out of band
    /// runs right here; anything that composes something the user has not read
    /// opens the sheet instead, where the draft is visible before it goes.
    ///
    /// A legacy-action pill (index past `grammarPillActions`) always opens the
    /// sheet: those cards predate the generated vocabulary and their payloads
    /// are not safe to fire blind.
    private func grammarPillTapped(_ index: Int) {
        guard !isCompletingSwipe, DSInteractionGate.allowsTap else { return }
        let runnable = suggestion.grammarPillActions
        guard index < runnable.count, runnable[index].kind.runsOnTap else {
            headerTapped()
            return
        }
        DSHaptics.tap()
        onMarkRead?()
        Task { _ = await performGenerated(runnable[index], editedBody: nil) }
    }

    private func headerTapped() {
        // A finger that swiped must not also count as a tap on release.
        guard !isCompletingSwipe, DSInteractionGate.allowsTap else { return }
        // The haptic lives HERE, not at the call sites, so every tap surface
        // (header row, card padding, context line) buzzes identically — and a
        // gated tap that does nothing stays silent.
        DSHaptics.tap()
        // Under the grammar the card no longer grows in place: a tap anywhere
        // that is not a pill opens the sheet (Alan — "we want the
        // user to be able to click the card itself, anywhere on the card,
        // except for the buttons, and that opens the sheet"). The expansion
        // path below stays reachable with the flag off, which is still the
        // shipping drawing; it is deleted when the flag is.
        if suggestion.isExpandable, !CardGrammar.isOn {
            let expanding = !isExpanded
            if expanding { onMarkRead?() }
            withAnimation(.smooth(duration: 0.3, extraBounce: 0)) { isExpanded.toggle() }
            reveal.revealOnSpill = expanding && onExpanded != nil
            if expanding, onExpanded != nil {
                // Settled-frame pass: corrects a glide the spill trigger
                // launched against mid-flight geometry (tall panels pick
                // their anchor from the final height), and disarms the
                // trigger if the panel never spilled.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [reveal] in
                    reveal.revealOnSpill = false
                    guard isExpanded else { return }
                    onExpanded?(suggestion, reveal.plateFrame)
                }
            }
        } else {
            onMarkRead?()
            onTap()
        }
    }

    /// The tappable header: avatar, the proposal + grounding context, and the
    /// chevron (expandable) or badge. The whole row toggles the drop-down; the
    /// grounding context clamps to 3 lines collapsed and shows in full expanded,
    /// with no see-more of its own.
    private var headerRow: some View {
        HStack(alignment: .top, spacing: 12) {
            suggestionAvatar

            VStack(alignment: .leading, spacing: 5) {
                if showsKindTag {
                    // "SUGGESTION · 5h ago" — same tag-line grammar as the
                    // Updates rows.
                    HStack(spacing: 5) {
                        CardKindTag(label: "Suggestion")
                        Text("·")
                        Text(UpdateCard.timeLabel(suggestion.createdAt))
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Palette.placeholder)
                }
                // Reference design: lead with what Iris PROPOSES, ground it with
                // the context on the arrow line below. Unread wears the full
                // weight; expanding (= reading) drops it to regular, revised
                // from the earlier medium step.
                Text(suggestion.proposalLine)
                    .font(.system(size: 16, weight: isUnread ? .semibold : .regular))
                    .tracking(-0.3)
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !suggestion.contextLine.isEmpty {
                    detailLine
                }
                if let waiting = suggestion.waitingStatusLine {
                    waitingStatusRow(waiting)
                }
                // A PERMISSION ask's one decisive action rides the COLLAPSED
                // face: it must never hide behind an
                // expand. The intro call is the exception:
                // its "Call me" lives ONLY in the expanded panel, so the
                // collapsed card stays a pitch. Same chip the expanded panel
                // leads with; the !isExpanded gate keeps the two from
                // doubling up.
                if cardIntent == .setup, !isExpanded,
                   let ask = action("request_permission") {
                    chip(ask.label, filled: true) { onRunAction?(suggestion, ask, nil) }
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if suggestion.isExpandable {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Palette.placeholder)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .padding(.top, 5)
            } else {
                badge
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        // The gray band is the EXPANDED-state signal, one rule for every card — open = gray header band over the white
        // body (square seam — the body owns the bottom rounding), collapsed =
        // one white plate. Never per-card. The tint is deliberately WHISPER
        // light — just enough separation to read the header as its own block,
        // never a slab of gray.
        .background {
            if isExpanded {
                Color(light: 0xF0F0F0, dark: 0x26272E).opacity(0.75)
            }
        }
        // The WHOLE row is the tap target — including the gaps between text,
        // avatar and chevron, not just the glyphs themselves.
        .contentShape(Rectangle())
        .onTapGesture { headerTapped() }
    }

    /// A subtle, secondary-color status line for a card waiting on a reply
    /// ("Waiting for a reply · N days"). Nil-guarded by the caller.
    private func waitingStatusRow(_ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "hourglass")
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(DS.Palette.placeholder)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .tracking(-0.1)
                .foregroundStyle(DS.Palette.placeholder)
                .lineLimit(1)
        }
    }

    // MARK: Generated actions

    private var hasGeneratedActions: Bool { !suggestion.generatedActions.isEmpty }

    /// Commit a generated action for real: POST via HomeStore. Returns the typed
    /// outcome so the panel can morph (sent thread-line, "In calendar", "Reminder
    /// set"). Returns `.failed` when no executor is wired (nothing happens).
    private func performGenerated(_ action: GeneratedAction, editedBody: String?) async -> HomeStore.GeneratedActionOutcome {
        guard let onGeneratedAction else { return .failed("Not available") }
        return await onGeneratedAction(suggestion, action, editedBody)
    }

    // MARK: Inline expand — composable blocks (reference design)

    /// The expanded panel is BLOCK-ASSEMBLED: each block renders only when the
    /// suggestion carries its data, so ONE layout serves every card kind that
    /// can arrive from Gmail, calendar, or anywhere else:
    /// 1. mail meta — "Email received at 2:42 am / from: x" + View email
    /// 2. reply label — "Reply to Jenny" over a draft
    /// 3. draft box — the CURRENT draft; variant chips swap it in place
    /// 4. facts — invite/event when·where·link bullet rows
    /// 5. primary — ONE biased blue action (send the shown draft /
    /// accept the invite); everything else is secondary
    /// 6. chips row — draft variants, secondary actions, Remind me, orb
    @ViewBuilder
    private var expandedDetailSection: some View {
        ZStack(alignment: .topLeading) {
            // Figma (node "Frame 2147228468", rectRadii [0,0,34,34]): the expanded
            // content sits on a WHITE inset panel that OWNS the card's bottom
            // rounding — square top (a straight seam with the gray header above),
            // rounded bottom. The gray header keeps only its top rounding, so the
            // two blocks read as one continuous silhouette with no rounded seam.
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: DS.Radius.card,
                bottomTrailingRadius: DS.Radius.card,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(DS.Palette.card)
            expandedDetail
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The expanded panel switches on the card's INTENT (derived from its
    /// backend actions + kind), so each card is its OWN experience instead of
    /// every card funnelling into the reply/draft editor: a pending RSVP leads
    /// with Accept / Decline, an outcome is a glance with Got it, a link
    /// previews-and-opens, a hand-off leads with one confirm. Only a genuine
    /// reply (or an unmapped card) keeps the draft-forward assembly below.
    @ViewBuilder
    private var expandedDetail: some View {
        // A generated-action card drives its own panel (reply options, meeting
        // confirm, remind) — EXCEPT a daily-sync card, whose generated chips ride
        // inline on its agenda lines (dailySyncDetail). Everything else keeps the
        // intent-derived panels.
        if hasGeneratedActions, cardIntent != .dailySync, cardIntent != .lifeMatter {
            generatedActionsDetail
        } else {
            switch cardIntent {
            case .invite: inviteDetail
            case .scheduling: schedulingDetail
            case .link: linkDetail
            case .info: infoDetail
            case .delegation: delegationDetail
            case .dailySync: dailySyncDetail
            case .lifeMatter: lifeMatterDetail
            case .setup: setupDetail
            case .reply, .generic: replyDetail
            }
        }
    }

    /// The expanded panel for a `generatedActions` card: any mail meta + facts,
    /// then the generated-action chips (reply options + compose own, meeting
    /// confirm, remind).
    @ViewBuilder
    private var generatedActionsDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasMailMeta { mailMetaBlock }
            factsBlock
            if hasRenderableGeneratedChips {
                GeneratedActionsPanel(
                    actions: suggestion.generatedActions,
                    perform: { action, body in await performGenerated(action, editedBody: body) },
                    startSentReply: startSentReply,
                    cardID: suggestion.id,
                    composeClient: draftComposeClient,
                    composeReply: generatedReplyContext,
                    composeRecipients: generatedReplyRecipients,
                    composeSubject: generatedReplySubject
                )
            } else {
                // No renderable generated chip (e.g. only acknowledge/unknown) —
                // never a dead-end: offer the dismiss + delegate fallback.
                fallbackActionRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The draft-forward assembly — today's behaviour verbatim: mail meta, the
    /// drafted reply (when present), event facts, then the chips row. Serves a
    /// genuine reply and any card whose intent doesn't map cleanly.
    @ViewBuilder
    private var replyDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasMailMeta { mailMetaBlock }

            // Reference mock: the draft box stands alone — the header's context
            // line already carries the "reply to X" framing, so no label.
            if shownDraft != nil {
                draftBox()
            }

            factsBlock

            // With a draft or real actions, the chips row leads; otherwise the
            // panel would be empty, so offer the dismiss + delegate fallback.
            if shownDraft != nil || !expandableActions.isEmpty {
                chipsRow
            } else {
                fallbackActionRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Intent-specific expanded panels

    /// The card's PRIMARY intent, derived structurally from its backend actions
    /// (and kind) in priority order — never from copy. Anything that doesn't map
    /// cleanly falls through to `.generic`, which renders exactly as before, so
    /// an unknown kind / action set is never worse than today.
    private var cardIntent: SuggestionCardIntent {
        let types = Set(suggestion.actions.map(\.type))
        let kind = suggestion.kind.lowercased()

        // A daily digest is a glanceable agenda regardless of its actions.
        if kind.hasPrefix("daily") { return .dailySync }
        // A LIFE.MD matter (V2 engine) owns its panel: the matter's state leads,
        // then whatever chips the card carries — generated or legacy.
        if kind == "life.suggestion" { return .lifeMatter }
        // A first-session setup card (permission ask / the intro call): its
        // pitch rides the header, its ONE chip is the whole panel — the body
        // must never fall into the draft editor.
        if types.contains("request_permission") || types.contains("place_intro_call") { return .setup }
        // A pending RSVP is the clearest primary intent → Accept / Decline.
        if types.contains("rsvp_accept") || types.contains("rsvp_decline") { return .invite }
        // Iris offering to set up a meeting → the create leads.
        if types.contains("create_meeting") { return .scheduling }
        // A drafted reply is the point → today's draft editor.
        if types.contains("send_draft") { return .reply }
        // A self-contained link (no reply / rsvp / meeting) → preview + open.
        if types.contains("open_link") { return .link }
        // A concrete task to hand off — the goal rides in the card header.
        if types.contains("start_task"), !delegationGoal.isEmpty { return .delegation }
        // Only an acknowledge (± quiet extras): an outcome / heads-up to glance
        // at. A calendar reminder keeps the facts-forward generic panel.
        let hasPrimary = suggestion.actions.contains { !["acknowledge", "start_task"].contains($0.type) }
        if !hasPrimary, types.contains("acknowledge") || suggestion.actions.isEmpty {
            return suggestion.isCalendarInvite ? .generic : .info
        }
        return .generic
    }

    /// The first backend action of a given type, if the card carries one.
    private func action(_ type: String) -> SuggestionActionItem? {
        suggestion.actions.first { $0.type == type }
    }

    /// What Iris would take on for a delegation card — the card's proposal
    /// (already shown in the header), falling back to its title.
    private var delegationGoal: String {
        let proposal = suggestion.proposalLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return proposal.isEmpty ? suggestion.message.trimmingCharacters(in: .whitespacesAndNewlines) : proposal
    }

    /// A pending RSVP: the event's when·where lead, then Accept / Decline as the
    /// two decisive chips — no draft, no chat orb (no composer). Remind me trails.
    @ViewBuilder
    private var inviteDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            factsBlock
            intentActionRow {
                if let accept = action("rsvp_accept") {
                    chip(accept.label, filled: true) { onRunAction?(suggestion, accept, nil) }
                }
                if let decline = action("rsvp_decline") {
                    chip(decline.label) { onRunAction?(suggestion, decline, nil) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Iris offers to set up a meeting: the proposed when·where lead, then the
    /// "set it up" action as the biased primary; a drafted note, if the card also
    /// carries one, is a secondary chip. No chat orb.
    @ViewBuilder
    private var schedulingDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasMailMeta { mailMetaBlock }
            factsBlock
            intentActionRow {
                if let meeting = action("create_meeting") {
                    chip(meeting.label, filled: true) { onRunAction?(suggestion, meeting, nil) }
                }
                if let draft = action("send_draft") {
                    chip(draft.label) { onRunAction?(suggestion, draft, nil) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A self-contained link: any event facts, then a rich preview row that IS
    /// the open button — one tap opens the resolved destination. No composer.
    @ViewBuilder
    private var linkDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasMailMeta { mailMetaBlock }
            factsBlock
            if let open = action("open_link") { linkPreviewRow(open) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// An outcome / heads-up ("… confirmed your cancellation"): nothing to
    /// compose. The gist rides in the card header, so the panel adds the mail
    /// meta (for a mail heads-up) and a calm Got it — no draft, no chat orb.
    @ViewBuilder
    private var infoDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasMailMeta { mailMetaBlock }
            factsBlock
            // A heads-up has nothing better than a glance — so it always offers a
            // dismiss AND a hand-it-to-Iris delegate (never a dead-end panel).
            fallbackActionRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A LIFE.MD matter card (the V2 engine): the matter's STATE from the life
    /// document rides the HEADER's grounding context (clamped collapsed, full
    /// when expanded — the app's standard grammar), so the panel is purely the
    /// card's actions: the generated panel when chips exist (reply drafts,
    /// options, remind), else the legacy chips row, never a dead end.
    @ViewBuilder
    private var lifeMatterDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasMailMeta { mailMetaBlock }
            factsBlock
            if hasRenderableGeneratedChips {
                GeneratedActionsPanel(
                    actions: suggestion.generatedActions,
                    perform: { action, body in await performGenerated(action, editedBody: body) },
                    startSentReply: startSentReply,
                    cardID: suggestion.id,
                    composeClient: draftComposeClient,
                    composeReply: generatedReplyContext,
                    composeRecipients: generatedReplyRecipients,
                    composeSubject: generatedReplySubject
                )
            } else if !expandableActions.isEmpty {
                chipsRow
            } else {
                fallbackActionRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A concrete task to hand off. The goal already rides in the header, so the
    /// panel leads with ONE decisive primary chip. The chip text is the action's
    /// own server label — the backend LLM names the concrete step ("Draft the
    /// follow-up"); the generic "Let Iris handle it" is only the fallback for
    /// legacy cards whose label never said anything.
    @ViewBuilder
    private var delegationDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasMailMeta { mailMetaBlock }
            intentActionRow {
                if let task = action("start_task") {
                    chip(concreteChipLabel(task), filled: true) { onRunAction?(suggestion, task, nil) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A first-session setup step (turn on notifications / location / the
    /// persona intro call): the compelling pitch already rides the header's
    /// context line, so the panel is ONE decisive primary chip carrying the
    /// action's server label ("Turn on", "Enable location", "Call me").
    @ViewBuilder
    private var setupDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            intentActionRow {
                if let ask = action("request_permission") ?? action("place_intro_call") {
                    chip(ask.label, filled: true) { onRunAction?(suggestion, ask, nil) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The action's server label when it names a real step; the generic hand-off
    /// only when the backend sent nothing better. Mirrors the backend's
    /// concreteActionLabel guard so a legacy "Iris, do it" doesn't leak through.
    private func concreteChipLabel(_ task: SuggestionActionItem) -> String {
        let label = task.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let generic: Set<String> = [
            "", "do it", "iris, do it", "handle it", "handle this",
            "let iris handle it", "let iris handle this", "take care of it",
            "let persona handle it", "let persona handle this",
            "go ahead", "learn more", "review", "ok", "okay"
        ]
        return generic.contains(label.lowercased()) ? "Let \(assistantName) handle it" : label
    }

    /// A daily digest: the body's lines as glanceable bullet rows, then a calm
    /// Got it. No composer.
    @ViewBuilder
    private var dailySyncDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(dailyAgendaRows) { line in
                    dailyAgendaRow(line)
                }
            }
            // Per-line chips carry the real actions; the row below always offers a
            // dismiss + delegate so the panel is never a dead end.
            fallbackActionRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One agenda line: a bullet, the text, and AT MOST ONE trailing action chip
    /// (a smaller capsule in the same language) when the line carries one. The
    /// chip runs its generated action; on success it morphs to a done state.
    private func dailyAgendaRow(_ line: DailyAgendaLine) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "circle")
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(Color(hex: 0x8F8F8F))
            Text(line.text)
                .font(.system(size: 14, weight: .regular))
                .tracking(-0.15)
                .foregroundStyle(DS.Palette.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let chip = line.chip {
                dailyChipButton(chip)
            }
        }
    }

    @ViewBuilder
    private func dailyChipButton(_ chip: GeneratedAction) -> some View {
        if executedDailyChips.contains(chip.id) {
            dailyMiniChip(chip.label, done: true)
        } else {
            Button { runDailyChip(chip) } label: { dailyMiniChip(chip.label, done: false) }
                .buttonStyle(.plain)
        }
    }

    private func runDailyChip(_ chip: GeneratedAction) {
        guard !isCompletingSwipe, DSInteractionGate.allowsTap else { return }
        DSHaptics.tap()
        Task {
            let outcome = await performGenerated(chip, editedBody: nil)
            switch outcome {
            case let .openLink(url): openURL(url)
            case .failed: break
            default: withAnimation(.smooth(duration: 0.24)) { _ = executedDailyChips.insert(chip.id) }
            }
        }
    }

    /// The smaller sibling of `chip` — same capsule language, 24pt tall — for a
    /// per-agenda-line action; a done state adopts the success tint + checkmark.
    private func dailyMiniChip(_ label: String, done: Bool) -> some View {
        HStack(spacing: 4) {
            if done { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .tracking(-0.1)
                .lineLimit(1)
        }
        .foregroundStyle(done ? DS.Palette.success : DS.Palette.ink)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 11)
        .frame(height: 26)
        .background(
            done ? AnyShapeStyle(DS.Palette.success.opacity(0.12)) : AnyShapeStyle(DS.Palette.card),
            in: Capsule(style: .continuous)
        )
        .overlay { done ? nil : Capsule(style: .continuous).stroke(Color(light: 0xEBEBEB, dark: 0x2B2C33), lineWidth: 1) }
    }

    /// Structured agenda lines when the backend sends them (each may carry one
    /// mini-chip); otherwise the body text split into plain (chip-less) lines.
    private var dailyAgendaRows: [DailyAgendaLine] {
        if let lines = suggestion.dailyLines, !lines.isEmpty { return lines }
        return dailySyncLines.map { DailyAgendaLine(text: $0, chip: nil) }
    }

    /// The digest body split into agenda lines (a leading bullet the backend may
    /// already include is stripped so it isn't doubled).
    private var dailySyncLines: [String] {
        let source = suggestion.context ?? suggestion.draftBody ?? suggestion.detail
        return source
            .split(whereSeparator: \.isNewline)
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let unbulleted = trimmed.drop(while: { "•-*·▪◦".contains($0) }).trimmingCharacters(in: .whitespaces)
                return unbulleted.isEmpty ? trimmed : unbulleted
            }
            .filter { !$0.isEmpty }
    }

    /// The chips row shared by the intent panels, wrapping to two lines when
    /// it can't fit one (matching `chipsRow`). Reply and Snooze moved off the
    /// row and into the card's long-press glass menu — the chips stand alone.
    @ViewBuilder
    private func intentActionRow(@ViewBuilder _ lead: () -> some View) -> some View {
        FlowLayout(spacing: 9, lineSpacing: 9) {
            lead()
        }
        .padding(.top, 2)
    }

    /// The long-press menu's Reply routes here: reply-to-suggestion on the chat
    /// page where the surface wires it, else the card's chat sheet.
    private func composeOwnReply() {
        if let onComposeReply {
            onComposeReply(suggestion)
        } else {
            onTap()
        }
    }

    // MARK: No dead-end panels

    /// "Hand it to Iris": run the card's start_task when it has one, else open the
    /// chat sheet so the user can hand it off there.
    private func handToIris() {
        guard !isCompletingSwipe, DSInteractionGate.allowsTap else { return }
        if let task = action("start_task") {
            onRunAction?(suggestion, task, nil)
        } else {
            onTap()
        }
    }

    /// The delegate chip — reused wherever a panel has no better primary action.
    /// Prefers the start_task action's own server label (the concrete step) over
    /// the generic hand-off.
    private var delegateChip: some View {
        chip(action("start_task").map(concreteChipLabel) ?? "Let \(assistantName) handle it", filled: true) { handToIris() }
    }

    /// A guaranteed dismiss/acknowledge (backend ack action → execute → delete →
    /// open), so no panel is ever a dead end.
    private var dismissChip: some View {
        chip(ackLabel) {
            if let ack = action("acknowledge") {
                onRunAction?(suggestion, ack, nil)
            } else if onExecute != nil {
                onExecute?(suggestion)
            } else if onDelete != nil {
                onDelete?(suggestion)
            } else {
                onTap()
            }
        }
    }

    /// The fallback action row for a panel with nothing better: a "Let Iris
    /// handle it" delegate + a dismiss, with Remind me trailing.
    private var fallbackActionRow: some View {
        intentActionRow {
            delegateChip
            dismissChip
        }
    }

    /// Whether a generated-action card actually renders any chip (else it would
    /// expand to nothing — fall back to delegate + dismiss).
    private var hasRenderableGeneratedChips: Bool {
        suggestion.generatedActions.contains {
            switch $0.kind {
            case .replySend, .replyOption, .createMeeting, .remind, .startTask, .openLink: true
            case .acknowledge, .unknown: false
            }
        }
    }

    /// The card's acknowledge label, backend-authored when present — the dismiss
    /// chip's copy.
    private var ackLabel: String {
        let label = (action("acknowledge")?.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? "Got it" : label
    }

    /// A rich, tappable link preview that opens the resolved destination in one
    /// tap (the backend resolves the URL when the action runs; the host shown
    /// comes from the card's `facts.url` when it carries one).
    private func linkPreviewRow(_ open: SuggestionActionItem) -> some View {
        let raw = (suggestion.facts?.url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let host = URL(string: raw)?.host?.replacingOccurrences(of: "www.", with: "")
        let label = open.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return Button {
            guard DSInteractionGate.allowsTap else { return }
            onRunAction?(suggestion, open, nil)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "safari.fill")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(DS.Palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label.isEmpty ? String(localized: "Open link") : label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Palette.ink)
                        .lineLimit(1)
                    if let host, !host.isEmpty {
                        Text(host)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(DS.Palette.inkMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.placeholder)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.card.opacity(0.94), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DS.Palette.hairlineSoft, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    // MARK: Blocks

    private var hasMailMeta: Bool {
        suggestion.mailReference != nil || suggestion.mailReceivedAt != nil
    }

    /// Received time + sender, with the in-app "View email" opener (the sheet
    /// is prefetched while the card is expanded, so it opens instantly).
    private var mailMetaBlock: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if let received = suggestion.mailReceivedAt {
                    Text("Email received at \(Self.receivedFormatterLabel(received))")
                }
                if let sender = suggestion.contactEmail ?? suggestion.avatarEmail {
                    Text("from: \(sender)")
                }
            }
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(DS.Palette.inkMuted)

            Spacer(minLength: 8)

            if suggestion.mailReference != nil {
                Button {
                    guard DSInteractionGate.allowsTap else { return }
                    mailSheetShown = true
                } label: {
                    Text("View email")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Palette.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// "2:42 am" today, "Jul 6, 2:42 am" otherwise. Kept formatters —
    /// DateFormatter construction is milliseconds-class, and this renders in
    /// the expanded card's mail meta block, whose body re-runs on every draft
    /// keystroke. Main-actor only, so the shared instances are safe.
    @MainActor private static let receivedTodayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    @MainActor private static let receivedDatedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()

    @MainActor private static func receivedFormatterLabel(_ date: Date) -> String {
        (Calendar.current.isDateInToday(date) ? receivedTodayFormatter : receivedDatedFormatter)
            .string(from: date)
    }

    /// The reply recipient's first name — the display name's first word when the
    /// card carries one ("Jenny Smith" → "Jenny"), else derived from the email
    /// local part ("jenny21@…" → "Jenny"). Nil when nothing name-like.
    private var replyToName: String? {
        if let name = suggestion.contactName?.trimmingCharacters(in: .whitespacesAndNewlines),
           let first = name.split(separator: " ").first, first.count >= 2 {
            return first.prefix(1).uppercased() + first.dropFirst()
        }
        guard let email = suggestion.contactEmail ?? suggestion.avatarEmail,
              let local = email.split(separator: "@").first else { return nil }
        let letters = local.prefix { $0.isLetter }
        guard letters.count >= 2 else { return nil }
        return letters.prefix(1).uppercased() + letters.dropFirst().lowercased()
    }

    /// The white draft box showing the CURRENT (possibly variant-swapped)
    /// reply, with the edit affordance into the chat sheet.
    private func draftBox() -> some View {
        ZStack(alignment: .bottomTrailing) {
            draftEditor
                .padding(.top, 15)
                .padding(.bottom, 15)
                .padding(.leading, 18)
                .padding(.trailing, 58)
                .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
                .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(
                    Color(light: 0xEBEBEB, dark: 0x2B2C33),
                    lineWidth: 1
                ) }
                .id(selectedSend?.id) // variant swap resets editor scroll position
            if let send = selectedSend {
                Button {
                    // Gate hard: this one sends real mail.
                    guard DSInteractionGate.allowsTap else { return }
                    onRunAction?(suggestion, send, editedDraftBody)
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(DS.Palette.accent, in: Circle())
                        .shadow(color: DS.Palette.accent.opacity(0.18), radius: 5, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send reply")
                .padding(.trailing, 12)
                .padding(.bottom, 12)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: selectedSend?.id)
        // The scroll target the surface lifts to when the draft takes focus:
        // aligning THIS box's bottom with the (keyboard-inset) viewport bottom
        // puts the whole draft in view with the keyboard directly beneath it.
        .id(SuggestionDraftTarget(cardID: suggestion.id))
        // (The draft's "edit in the full composer" sheet lived here. It is the
        // app's rich MAIL composer — recipient chips, sender picker, assist —
        // i.e. a send surface, so it was cut with the rest of the backend. The
        // draft still previews in place on the card exactly as it does today.)
    }

    /// The reply recipient as a composer chip — the card's contact, when known.
    private var draftRecipients: [ComposeRecipient] {
        guard let email = suggestion.contactEmail ?? suggestion.avatarEmail, !email.isEmpty else { return [] }
        return [ComposeRecipient(email: email, name: suggestion.contactName)]
    }

    /// The GENUINE reply target: a mail-referenced card opens the composer
    /// threaded onto its own thread (the "Replying to…" banner, sender pinned
    /// to the thread's account) — the same state a hand-picked reply reaches.
    /// The card's subject line stays the display subject (the true Re: subject
    /// lives server-side with the send_draft). Nil for non-mail cards: the
    /// composer then opens as a plain prefilled draft, exactly as before.
    private var draftReplyContext: ComposeReplyContext? {
        guard let ref = suggestion.mailReference else { return nil }
        return ComposeReplyContext(
            accountId: ref.accountId,
            threadId: ref.threadId,
            from: suggestion.contactName ?? suggestion.contactEmail ?? suggestion.avatarEmail,
            senderOnly: draftRecipients.isEmpty ? nil : draftRecipients
        )
    }

    /// Editing a suggestion's send_draft: keep recipient autocomplete + Iris
    /// assist, but drop the fresh-compose send + reply re-threading — the
    /// send_draft action carries neither (it sends the body onto the thread).
    private var draftComposeClient: ComposeAssistClient {
        var client = settings.compose.client
        client.sendEmail = nil
        client.searchThreads = nil
        // HOME_MOCK rig only: the mock card's fake thread ids can't resolve
        // against the real backend, so the banner enrichment gets a canned
        // context — the demo then shows the same enriched state a real
        // mail-referenced card reaches (same pattern as COMPOSE_QA_*).
        if ProcessInfo.processInfo.environment["HOME_MOCK"] == "1" {
            client.replyContext = { hit in
                ComposeReplyContext(
                    accountId: hit.accountId,
                    threadId: hit.threadId,
                    subject: "Re: Q3 offer — final numbers",
                    from: "Marco Rossi",
                    to: [ComposeRecipient(email: "marco@northwind.co", name: "Marco Rossi")],
                    senderOnly: [ComposeRecipient(email: "marco@northwind.co", name: "Marco Rossi")]
                )
            }
        }
        return client
    }

    /// The generated panel's reply_send draft, when the card carries one —
    /// its payload is the composer prefill's first source.
    private var generatedReplySend: GeneratedAction? {
        suggestion.generatedActions.first { $0.kind == .replySend }
    }

    /// The generated draft's reply target: the reply_send's OWN threading
    /// (accountId + inReplyToThreadId) when the payload carries it, else the
    /// card-level mail reference — so the composer opens with the same
    /// "Replying to…" banner a hand-picked reply shows.
    private var generatedReplyContext: ComposeReplyContext? {
        guard let payload = generatedReplySend?.payload,
              let accountId = payload.accountId, !accountId.isEmpty,
              let threadId = payload.inReplyToThreadId, !threadId.isEmpty
        else { return draftReplyContext }
        return ComposeReplyContext(
            accountId: accountId,
            threadId: threadId,
            subject: payload.subject,
            from: suggestion.contactName ?? payload.to,
            senderOnly: generatedReplyRecipients.isEmpty ? nil : generatedReplyRecipients
        )
    }

    /// The generated draft's recipient chip: the reply_send's own `to`,
    /// carrying the card's contact name only when it names the same address.
    private var generatedReplyRecipients: [ComposeRecipient] {
        guard let to = generatedReplySend?.payload.to, !to.isEmpty else { return draftRecipients }
        let name = to.caseInsensitiveCompare(suggestion.contactEmail ?? "") == .orderedSame
            ? suggestion.contactName : nil
        return [ComposeRecipient(email: to, name: name)]
    }

    private var generatedReplySubject: String {
        let subject = (generatedReplySend?.payload.subject ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return subject.isEmpty ? suggestion.message : subject
    }

    @ViewBuilder
    private var draftEditor: some View {
        #if canImport(UIKit)
            // Read-only in place: editing happens in the modal sheet, where the
            // keyboard can't cover the text (the old inline focus + scroll-lift
            // kept leaving low cards' drafts half-buried under the keys).
            SuggestionDraftTextView(text: $editedDraftBody, editable: false)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard DSInteractionGate.allowsTap else { return }
                    DSHaptics.tap()
                    editingDraft = true
                }
        #else
            TextEditor(text: $editedDraftBody)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(hex: 0x626262))
                .scrollContentBackground(.hidden)
        #endif
    }

    /// Invite/event facts as quiet bullet rows (reference design: ○ bullets;
    /// the link row opens in the browser).
    @ViewBuilder
    private var factsBlock: some View {
        if let facts = suggestion.facts, !facts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if let date = facts.date, !date.isEmpty { factRow(EventDate.format(date)) }
                if let venue = facts.venue, !venue.isEmpty { factRow(venue) }
                if let price = facts.price, !price.isEmpty { factRow(price) }
                if let raw = facts.url, !raw.isEmpty, !hasLinkAction, let url = URL(string: raw) {
                    Button {
                        guard DSInteractionGate.allowsTap else { return }
                        openURL(url)
                    } label: { factRow(raw, isLink: true) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    // Figma meta rows: a 10pt hollow #7E7E7E circle + 12pt medium text — the date
    // in #3D3D3D, an underlined link in #2564A9 (a darker blue than the #378FFF
    // accent used for the arrow/verb, so the URL reads as a distinct hyperlink).
    private func factRow(_ value: String, isLink: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: "circle")
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(Color(hex: 0x8F8F8F))
            Text(value)
                .font(.system(size: 15, weight: .regular))
                .tracking(-0.2)
                .foregroundStyle(isLink ? Color(light: 0x2564A9, dark: 0x6FA8E8) : DS.Palette.inkSoft)
                .underline(isLink)
                .lineLimit(isLink ? 1 : 2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    /// The bottom row: draft-variant / non-draft action chips, wrapping. Reply
    /// and Snooze live in the card's long-press glass menu now.
    private var chipsRow: some View {
        FlowLayout(spacing: 9, lineSpacing: 9) {
            actionChips
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var actionChips: some View {
        ForEach(sendActions) { send in
            chip(send.label, filled: send.id == selectedSend?.id) {
                if send.id == selectedSend?.id {
                    onRunAction?(suggestion, send, editedDraftBody)
                } else {
                    DSHaptics.tap(.light)
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedDraftID = send.id
                        syncDraftEditorIfNeeded(force: true, nextSend: send)
                    }
                }
            }
        }
        ForEach(nonDraftActions) { action in
            chip(action.label, filled: sendActions.isEmpty && action.id == nonDraftActions.first?.id) {
                onRunAction?(suggestion, action, nil)
            }
        }
    }

    /// Every real non-draft action, primary-first (the first is the biased
    /// blue chip when the card has no draft).
    private var nonDraftActions: [SuggestionActionItem] {
        expandableActions.filter { $0.type != "send_draft" }
    }

    private func chip(_ label: String, icon: String? = nil, filled: Bool = false, _ act: @escaping () -> Void) -> some View {
        Button {
            // A page swipe releasing over a chip is a touch-up "inside" (the
            // pager moves the page WITH the finger) — one gate here covers
            // every chip on the card.
            guard DSInteractionGate.allowsTap else { return }
            act()
        } label: {
            suggestionChipLabel(label, icon: icon, filled: filled)
        }
        .buttonStyle(.plain)
    }

    // MARK: Draft selection

    private var sendActions: [SuggestionActionItem] {
        suggestion.actions.filter { $0.type == "send_draft" }
    }

    /// The variant whose draft fills the box and whose send the blue button
    /// fires — user-picked, else the first (backend-primary).
    private var selectedSend: SuggestionActionItem? {
        sendActions.first(where: { $0.id == selectedDraftID }) ?? sendActions.first
    }

    /// The draft the box shows: the selected variant's body, else the card's
    /// own draft. Nil = no draft block at all.
    private var shownDraft: String? {
        if let body = selectedSend?.draftBody, !body.isEmpty { return body }
        let body = (suggestion.draftBody ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }

    private func syncDraftEditorIfNeeded(force: Bool = false, nextSend: SuggestionActionItem? = nil) {
        let send = nextSend ?? selectedSend
        let sourceID = send?.id
        guard force || editedDraftSourceID != sourceID else { return }
        if let body = send?.draftBody, !body.isEmpty {
            editedDraftBody = body
        } else {
            editedDraftBody = shownDraft ?? ""
        }
        editedDraftSourceID = sourceID
    }

    /// The card's actionable actions, primary-first — RSVP for an invite, a
    /// reply draft, a link. Data-driven: labels come straight from the backend
    /// action, and `acknowledge` (a bare dismiss) is never a button here —
    /// swipe-left already dismisses.
    private var expandableActions: [SuggestionActionItem] {
        // remove_events (commitment-change cards) renders generically: the
        // server label is the chip, the POST rides the shared action path.
        // Without this entry the card would fall to the fallback row with NO
        // action button at all (unknown types are filtered out here).
        let order = ["rsvp_accept", "rsvp_decline", "send_draft", "whatsapp_send", "create_meeting", "remove_events", "open_link"]
        return suggestion.actions
            .filter { order.contains($0.type) }
            .sorted { (order.firstIndex(of: $0.type) ?? 99) < (order.firstIndex(of: $1.type) ?? 99) }
    }

    private var hasLinkAction: Bool {
        suggestion.actions.contains { $0.type == "open_link" }
    }

    // MARK: Swipe (design-app parity)

    /// Left = dismiss (trash, red), fading in behind the sliding card exactly
    /// like the design app. There is deliberately NO rightward/accept side —
    /// accepting a suggestion is a tap, never a flick.
    private var swipeAffordance: some View {
        HStack {
            Spacer(minLength: 0)

            if dragOffset < 0 {
                swipeIcon(systemName: "trash", color: Color(hex: 0xFF3B30))
                    .padding(.trailing, 28)
                    .transition(.opacity)
            }
        }
        .opacity(min(abs(dragOffset) / 48.0, 1.0))
    }

    private func swipeIcon(systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 42, height: 42)
            .background(color.opacity(0.12), in: Circle())
    }

    private var swipeColor: Color {
        Color(hex: 0xFF3B30)
    }

    /// The panel fill picks up the commit tint as the drag deepens (design-app
    /// formula on the same 0xF6F6F6 base).
    private var cardFill: Color {
        guard dragOffset != 0 else {
            return DS.Palette.card
        }

        let intensity = min(abs(dragOffset) / commitDistance, 1)
        let tintOpacity: CGFloat = 0.10 + (0.16 * intensity)
        return DS.Palette.card
            .mix(with: swipeColor.opacity(tintOpacity), by: 0.48)
    }

    private func handleSwipeChanged(translation: CGSize) {
        guard !isCompletingSwipe else { return }

        isSwipeActive = true
        // While a swipe is live, keep taps suppressed so releasing the finger
        // never fires the card's open action.
        DSInteractionGate.suppressTaps()
        // Reject is leftward-only: a claimed drag that wanders back rightward
        // parks at rest instead of revealing a phantom accept.
        dragOffset = min(0, rubberBand(translation.width, limit: maxDrag))
        updateCommitThresholdHaptic(for: dragOffset)
    }

    private func handleSwipeEnded(translation: CGSize) {
        defer {
            isSwipeActive = false
            wasPastCommitThreshold = false
        }
        guard !isCompletingSwipe, isSwipeActive else { return }

        DSInteractionGate.suppressTaps()
        if translation.width < -commitDistance {
            completeSwipe()
        } else {
            withAnimation(.smooth(duration: 0.2, extraBounce: 0)) {
                dragOffset = 0
            }
        }
    }

    /// Fling the card off leftward and dismiss it. (The old rightward
    /// swipe-to-execute is gone — accept actions are taps only.)
    private func completeSwipe() {
        isCompletingSwipe = true
        playSwipeHaptic(.medium, intensity: 1)
        withAnimation(.smooth(duration: 0.12, extraBounce: 0)) {
            dragOffset = -430
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            onDelete?(suggestion)
            isCompletingSwipe = false
        }

        // Dismiss removes the card synchronously, so snap the offset back
        // unseen (design-app timing).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dragOffset = 0
            }
        }
    }

    private func updateCommitThresholdHaptic(for visibleOffset: CGFloat) {
        let isPastCommit = abs(visibleOffset) > commitDistance

        if isPastCommit, !wasPastCommitThreshold {
            playSwipeHaptic(.rigid, intensity: 0.82)
        }

        wasPastCommitThreshold = isPastCommit
    }

    private func playSwipeHaptic(_ style: DSHaptics.Style, intensity: CGFloat) {
        // Kept-generator route: constructing a cold generator at the commit
        // crossing is main-thread work mid-drag AND the documented
        // dropped-transient recipe (see DSHaptics.impactGenerators).
        DSHaptics.swipeThreshold(style, intensity: intensity)
    }

    private func rubberBand(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        let sign: CGFloat = value < 0 ? -1 : 1
        let magnitude = abs(value)

        guard magnitude > limit else {
            return value
        }

        return sign * (limit + (magnitude - limit) * 0.18)
    }

    private var suggestionAvatar: some View {
        SuggestionEntryAvatar(suggestion: suggestion, size: 42)
    }

    private var detailLine: some View {
        // Reference design: a BLUE arrow introducing the gray grounding context,
        // with an optional inline blue action verb (backend `contextVerb`).
        // firstTextBaseline keeps the arrow glyph on the first line's baseline.
        //
        // No see-more/see-less anywhere: a COLLAPSED card
        // clamps the context to 3 lines (plain ellipsis) and the ONLY affordance
        // is expanding the card; EXPANDED shows the context in full.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Palette.accent)
            // Per-run colors are baked into `contextText` (an optional blue verb
            // leads the gray line), so no blanket foregroundStyle here — only the
            // shared default font for runs that don't set their own.
            contextText
                .font(.system(size: 14, weight: .regular))
                .tracking(-0.2)
                .lineLimit(isExpanded ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // A tap anywhere on the context expands/collapses the card — the context
        // no longer has any toggle of its own.
        .contentShape(Rectangle())
        .onTapGesture { headerTapped() }
    }

    /// The optional blue action verb ("Schedule", "Draft") the Figma design leads
    /// the grounding line with. Backend-authored (`contextVerb`) and editorial —
    /// present on some cards, absent on others — so it stays nil until the backend
    /// emits it, and today the context line renders gray-only.
    private var contextVerbText: String {
        (suggestion.contextVerb ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The grounding-context text: an optional blue verb leading the gray body,
    /// wrapping as one paragraph. The caller's `lineLimit` clamps it (3 collapsed,
    /// unbounded expanded); there is no inline see-more.
    private var contextText: Text {
        let gray = Text(suggestion.contextLine).foregroundColor(DS.Palette.subtle)
        let verb = contextVerbText
        guard !verb.isEmpty else { return gray }
        return Text(verb + " ")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(DS.Palette.accent) + gray
    }

    /// A FLAT card (no inline panel — a tap opens its chat sheet) wears the badge
    /// where an expandable wears its chevron. Restyled into the card's own pill
    /// grammar — the same white capsule, #EDEDED hairline and whisper shadow as a
    /// secondary chip — so it reads as family instead of the old heavier plate.
    private var badge: some View {
        HStack(spacing: 5) {
            BrandMark(size: 14)
            Text(suggestion.badge)
                .font(.system(size: 12, weight: .medium))
                .tracking(-0.15)
                .foregroundStyle(DS.Palette.ink)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background {
            Capsule(style: .continuous).fill(DS.Palette.card)
                .overlay { Capsule(style: .continuous).stroke(
                    Color(light: 0xEDEDED, dark: 0xFFFFFF, lightOpacity: 1, darkOpacity: 0.14),
                    lineWidth: 1
                ) }
                .shadow(color: .black.opacity(0.05), radius: 2.5, x: 0, y: 1.5)
        }
    }
}

// MARK: - Generated actions panel

/// Renders a card's backend-`generatedActions` in design's language:
/// • reply options as a WRAPPING chip row (primary ink-filled); tapping one
/// morphs the row to a sent mini thread-line on the card.
/// • a create_meeting fragment: a date bubble + Confirm chip → checkmark morph
/// and an "In calendar" status.
/// • remind: a clock-glyph chip that sets instantly (reusing the undo path).
/// Reply-your-own and snooze live in the CARD's long-press glass menu, not here.
///
/// Unknown kinds are already dropped upstream (tolerant decode). Interactions are
/// optimistic/local; `onAction` commits them once the backend executor is wired.
private struct GeneratedActionsPanel: View {
    let actions: [GeneratedAction]
    /// Commit an action for real (POST) and hand back the typed outcome the panel
    /// morphs on. `editedBody` carries the edited reply_send draft.
    var perform: @MainActor (GeneratedAction, String?) async -> HomeStore.GeneratedActionOutcome = { _, _ in .failed("") }
    /// Preview/QA only: seed the panel's sent state (see SuggestionCard's
    /// `startSentReply`) so the demo gallery can show the post-send thread-line
    /// statically, which a live card only reaches by tapping.
    var startSentReply: String?
    /// The owning card — the draft's scroll target is keyed on it.
    var cardID = UUID()
    /// Compose backend for the draft edit sheet (recipient autocomplete +
    /// Iris assist; the send stays with the card's reply_send rail). Nil =
    /// previews without a backend.
    var composeClient: ComposeAssistClient? = nil
    /// The thread the draft replies into — threads the composer's banner.
    var composeReply: ComposeReplyContext? = nil
    /// The draft's recipient as a composer chip (the panel itself doesn't
    /// know the suggestion — the owning card passes its contact).
    var composeRecipients: [ComposeRecipient] = []
    /// The composer's subject line.
    var composeSubject = ""

    @Environment(\.openURL) private var openURL

    /// The editable reply_send draft, seeded from its payload body.
    @State private var replyDraft = ""
    @State private var replyDraftSeeded = false
    /// The reply_option the user picked to REPLACE the draft (chip highlight).
    /// Only meaningful while a reply_send draft box is present — without one,
    /// option chips keep their original tap-to-send behavior.
    @State private var selectedOptionID: String?
    /// Tap on the (read-only) draft box → the modal edit sheet (same rule as
    /// the legacy draft box: the keyboard can never bury the editor).
    @State private var editingDraft = false
    @State private var isSending = false
    /// The picked reply — the chip row morphs into this sent thread-line.
    @State private var sentReplyText: String?
    @State private var confirmedMeetings: Set<String> = []
    @State private var errorText: String?

    private var replySend: GeneratedAction? { actions.first { $0.kind == .replySend } }
    private var meetings: [GeneratedAction] { actions.filter { $0.kind == .createMeeting } }

    /// The action verbs shown as inline chips (backend-ordered primary first, so
    /// exactly one is ink-filled; the rest are white outline). reply_send → the
    /// draft box, create_meeting → the meeting fragment, remind → the trailing
    /// bell, acknowledge → skipped: none of those are chips.
    private var chipActions: [GeneratedAction] {
        actions.filter { [.replyOption, .startTask, .openLink].contains($0.kind) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let sent = sentReplyText {
                sentThreadLine(sent)
            } else {
                if let send = replySend {
                    recipientLine(send)
                    replyDraftBox(send)
                }
                ForEach(meetings) { meetingFragment($0) }
                actionRow
            }
            if let errorText { errorLine(errorText) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.28), value: sentReplyText)
        .onAppear {
            if !replyDraftSeeded {
                replyDraft = replySend?.payload.body ?? ""
                replyDraftSeeded = true
            }
            if let startSentReply { sentReplyText = startSentReply }
        }
    }

    // MARK: Figma action row — inline chips

    /// Inline action chips wrap via FlowLayout (primary ink-filled, rest white
    /// outline). Reply and Snooze live in the card's long-press glass menu.
    @ViewBuilder
    private var actionRow: some View {
        if replySend != nil {
            // Draft-alternatives mode: each reply_option is a whole alternative
            // MAIL, so the chips stack one per line (a flow row reads like
            // parallel quick actions, which they are not); the non-reply chips
            // keep the flow row below.
            VStack(alignment: .leading, spacing: 9) {
                ForEach(chipActions.filter { $0.kind == .replyOption }) { action in
                    Button { run(action) } label: {
                        genChip(action.label, icon: nil, filled: selectedOptionID == action.id)
                    }
                    .buttonStyle(.plain)
                }
                FlowLayout(spacing: 9, lineSpacing: 9) {
                    ForEach(chipActions.filter { $0.kind != .replyOption }) { action in
                        Button { run(action) } label: {
                            genChip(action.label, icon: nil, filled: action.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else {
            FlowLayout(spacing: 9, lineSpacing: 9) {
                ForEach(chipActions) { action in
                    Button { run(action) } label: {
                        genChip(action.label, icon: nil, filled: action.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func run(_ action: GeneratedAction) {
        // Every chip routes through here — one gate keeps a page swipe's
        // touch-up from firing an action (the pager moves WITH the finger).
        guard DSInteractionGate.allowsTap else { return }
        switch action.kind {
        case .replyOption:
            // With a draft box present, an option chip is an ALTERNATIVE draft:
            // tapping swaps the editable body (user reviews, then Send posts
            // it via the reply_send rail). Nothing is sent by the tap itself.
            // Without a reply_send, the original tap-to-send behavior stands.
            if replySend != nil { swapDraft(to: action) } else { pick(action) }
        case .startTask, .openLink: runExtra(action)
        default: break
        }
    }

    private func swapDraft(to option: GeneratedAction) {
        DSHaptics.tap()
        withAnimation(.smooth(duration: 0.22)) {
            if selectedOptionID == option.id {
                // Tapping the picked option again restores the original draft.
                selectedOptionID = nil
                replyDraft = replySend?.payload.body ?? ""
            } else {
                selectedOptionID = option.id
                replyDraft = option.payload.text ?? option.label
            }
        }
    }

    // MARK: reply_send editable draft + reply_option chips + "Own reply…"

    /// "to: kylin@supplier.com · Re: 26mm change" — the draft's destination,
    /// mirroring mailMetaBlock's lowercase "from:" grammar. Without it the box
    /// reads as a bare text field and the user cannot tell who gets the mail.
    @ViewBuilder
    private func recipientLine(_ send: GeneratedAction) -> some View {
        if let to = send.payload.to, !to.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "arrowshape.turn.up.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.Palette.inkMuted)
                Text(send.payload.subject?.isEmpty == false ? "to: \(to) · \(send.payload.subject!)" : "to: \(to)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.Palette.inkMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.leading, 4)
        }
    }

    /// The primary drafted reply, editable in place; Send posts the EDITED body.
    /// Same metrics as the legacy draft box (SuggestionCard.draftBox) so the two
    /// are indistinguishable.
    private func replyDraftBox(_ send: GeneratedAction) -> some View {
        ZStack(alignment: .bottomTrailing) {
            draftEditor
                .padding(.top, 14)
                .padding(.bottom, 14)
                .padding(.leading, 18)
                .padding(.trailing, 58)
                .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
                .background(DS.Palette.card.opacity(0.94), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(DS.Palette.hairlineSoft, lineWidth: 1) }
            Button {
                // Gate hard: this one sends real mail. (commitDraft itself
                // stays ungated — the compose sheet's onCommitDraft also
                // lands there, and sheets sit above the pager.)
                guard DSInteractionGate.allowsTap else { return }
                DSHaptics.tap(.medium)
                commitDraft(send)
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(DS.Palette.accent, in: Circle())
                    .shadow(color: DS.Palette.accent.opacity(0.18), radius: 5, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Send reply")
            .disabled(isSending || replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.trailing, 12)
            .padding(.bottom, 12)
        }
        // Same lift-clear-of-the-keyboard target as the legacy draft box.
        .id(SuggestionDraftTarget(cardID: cardID))
        // (The draft's "edit in the full composer" sheet lived here. It is the
        // app's rich MAIL composer — recipient chips, sender picker, assist —
        // i.e. a send surface, so it was cut with the rest of the backend. The
        // draft still previews in place on the card exactly as it does today.)
    }

    @ViewBuilder
    private var draftEditor: some View {
        #if canImport(UIKit)
            // Read-only preview — the modal sheet owns editing (see the legacy
            // draft box: inline focus left the box buried under the keyboard).
            SuggestionDraftTextView(text: $replyDraft, editable: false)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard DSInteractionGate.allowsTap else { return }
                    DSHaptics.tap()
                    editingDraft = true
                }
        #else
            TextEditor(text: $replyDraft).font(.system(size: 14)).scrollContentBackground(.hidden)
        #endif
    }

    private func commitDraft(_ action: GeneratedAction) {
        guard !isSending else { return }
        isSending = true
        Task {
            let outcome = await perform(action, replyDraft)
            isSending = false
            if case let .failed(message) = outcome { withAnimation { errorText = message } }
            // .sent consumes the card server-side; Home drops it.
        }
    }

    private func pick(_ option: GeneratedAction) {
        DSHaptics.tap()
        withAnimation(.smooth(duration: 0.28)) { sentReplyText = option.payload.text ?? option.label }
        Task {
            let outcome = await perform(option, nil)
            switch outcome {
            case let .replied(reply): withAnimation { sentReplyText = reply }
            case let .failed(message): withAnimation { sentReplyText = nil
                    errorText = message
                }
            default: break
            }
        }
    }

    /// The chosen reply as a right-aligned mini thread-line (a sent bubble).
    private func sentThreadLine(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 40)
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Palette.accent)
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Palette.ink)
                    .lineLimit(4)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(DS.Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: create_meeting → date bubble + confirm → "In calendar"

    @ViewBuilder
    private func meetingFragment(_ meeting: GeneratedAction) -> some View {
        let confirmed = confirmedMeetings.contains(meeting.id)
        HStack(spacing: 11) {
            dateBubble(meeting.payload.startISO)
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.payload.title ?? meeting.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Palette.ink)
                    .lineLimit(1)
                if let when = meetingWhen(meeting.payload.startISO) {
                    Text(when).font(.system(size: 12)).foregroundStyle(DS.Palette.inkMuted).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if confirmed {
                statusPill("In calendar", icon: "checkmark")
            } else {
                Button { confirmMeeting(meeting) } label: {
                    genChip("Confirm", icon: "checkmark", filled: true)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(DS.Palette.card.opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DS.Palette.hairlineSoft, lineWidth: 1) }
    }

    private func confirmMeeting(_ meeting: GeneratedAction) {
        // Creates a real calendar event — never off a page swipe's touch-up.
        guard DSInteractionGate.allowsTap else { return }
        DSHaptics.tap()
        Task {
            let outcome = await perform(meeting, nil)
            switch outcome {
            case .meetingCreated: withAnimation(.smooth(duration: 0.28)) { _ = confirmedMeetings.insert(meeting.id) }
            case let .failed(message): withAnimation { errorText = message }
            default: break
            }
        }
    }

    private func dateBubble(_ iso: String?) -> some View {
        VStack(spacing: 1) {
            Image(systemName: "calendar")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.Palette.accent)
            if let day = Self.formatISO(iso, "d") {
                Text(day)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DS.Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(.horizontal, 4)
        .frame(width: 48, height: 46)
        .background(DS.Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func meetingWhen(_ iso: String?) -> String? { Self.formatISO(iso, "EEE, HH:mm") }

    /// Parse an ISO-8601 timestamp (with or without fractional seconds) and format
    /// it; nil when unparseable. Formatters kept per pattern — construction is
    /// milliseconds-class and this runs in card bodies (main-actor only).
    @MainActor private static var isoFormatters: [String: DateFormatter] = [:]

    @MainActor private static func formatISO(_ iso: String?, _ pattern: String) -> String? {
        guard let iso, let date = ISO8601.parse(iso) else { return nil }
        let formatter = isoFormatters[pattern] ?? {
            let fresh = DateFormatter()
            fresh.dateFormat = pattern
            isoFormatters[pattern] = fresh
            return fresh
        }()
        return formatter.string(from: date)
    }

    // MARK: start_task / open_link execution (remind is the trailing bell)

    private func runExtra(_ action: GeneratedAction) {
        DSHaptics.tap()
        Task {
            let outcome = await perform(action, nil)
            switch outcome {
            case let .openLink(url): openURL(url)
            case let .failed(message): withAnimation { errorText = message }
            default: break // start_task consumes the card
            }
        }
    }

    private func errorLine(_ message: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .semibold))
            Text(message).font(.system(size: 12, weight: .medium)).lineLimit(2)
        }
        .foregroundStyle(Color(hex: 0xE34D56))
    }

    // MARK: Shared chip language (the exact SuggestionCard chip component)

    /// The same chip grammar every other panel uses — filled = biased primary,
    /// unfilled = white hairline pill.
    private func genChip(_ label: String, icon: String?, filled: Bool) -> some View {
        suggestionChipLabel(label, icon: icon, filled: filled)
    }

    /// A done/confirmed state ("In calendar", "Reminder set") — the chip capsule
    /// metrics with the in-palette success tint (matches the app's handled-row
    /// green), so it reads as the same family as the action chips.
    private func statusPill(_ label: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(String(localized: String.LocalizationValue(label))).font(.system(size: 13, weight: .semibold)).tracking(-0.1).lineLimit(1)
        }
        .foregroundStyle(DS.Palette.success)
        .padding(.horizontal, 13)
        .frame(height: 34)
        .background(DS.Palette.success.opacity(0.12), in: Capsule(style: .continuous))
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * lineSpacing
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: maxWidth == .infinity ? widest : maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let rows = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let projected = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if projected > maxWidth, !current.items.isEmpty {
                rows.append(current)
                current = Row(items: [index], width: size.width, height: size.height)
            } else {
                current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
                current.items.append(index)
                current.height = max(current.height, size.height)
            }
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

// The Suggestions empty state moved to SuggestionsEmptyState.swift, where it
// grew from a static "No new Suggestions" plate into the live what-I'm-watching
// panel with connect / turn-on picks.

/// Set while a `HorizontalSwipeGestureAttachment` pan owns the current touch
/// (a suggestion's reject swipe, chat's timestamp reveal). The Home⇄Chat pager
/// reads it every drag tick so a claimed swipe never ALSO drags the page — the
/// two recognizers run simultaneously (the pager is a SwiftUI drag, so the
/// pan's paging-scroll-view exclusion can't see it) and this flag is their only
/// arbitration. The clear is deferred a runloop turn so the pager's `onEnded`,
/// which races the pan's `.ended` on the same touch-up, still sees the claim.
@MainActor
enum HorizontalSwipeClaim {
    static var isActive = false
}

/// The claim's mirror, pointing the other way: set while the ROOT pager's
/// drag has latched horizontal and is moving the page with the finger. The
/// UIKit card pans check it in `gestureRecognizerShouldBegin` — recognition
/// is velocity-signed (`velocity.x < 0 ? allowsLeftward : allowsRightward`),
/// so a rightward page-pull whose velocity jittered leftward for one beat
/// mid-drag let the timestamp-reveal pan BEGIN late, claim the touch, and
/// snap a half-dragged page back ("swipes halfway then snaps back", design
///). Once the page itself is traveling, the touch is settled —
/// no card pan may begin on it.
@MainActor
enum PagerHorizontalDrag {
    static var isActive = false
}

/// Where the swipeable suggestion cards are, in GLOBAL coordinates. The pager
/// reads this at drag-start and refuses outright to page from a touch that
/// began on one — a suggestion is a NO-PAGE zone, always. The quick actions
/// row registers here too: any strip that owns its own horizontal drag is a
/// no-page zone, suggestion or not.
///
/// This is deliberately independent of `HorizontalSwipeClaim`: the claim only
/// arrives once the card's pan recognizes (a decisively horizontal, fast enough
/// start), so a slow or slightly diagonal reject swipe never claims and the
/// pager used to take it — the "it still slides to chat if I start swiping
/// before the card settles" report. The zone needs no recognition: the touch
/// either began inside a card or it didn't.
/// THE page-edge contract (product decision, design; narrowed 18% →
/// 10% on design's call): the outer 10% of the screen on EACH side
/// belongs to page navigation, full stop. A drag starting there pages
/// Home⇄Chat no matter what lies underneath — suggestion cards, task cards,
/// transcript bubbles. Card-level horizontal gestures (reject swipe,
/// timestamp reveal) live in the middle 80%. Shared by the root pager, the
/// no-page zones, and the UIKit card pans so no two of them can ever
/// disagree about who owns a stripe touch.
let pageEdgeFraction: CGFloat = 0.10

/// Whether a global point sits in one of the page-edge stripes.
func inPageEdgeStripe(_ point: CGPoint, pageWidth: CGFloat) -> Bool {
    pageWidth > 0 && (point.x < pageWidth * pageEdgeFraction || point.x > pageWidth * (1 - pageEdgeFraction))
}

@MainActor
enum SuggestionSwipeZones {
    private static var frames: [UUID: CGRect] = [:]

    /// A card publishes its frame as it lays out / scrolls; nil deregisters it
    /// (dismissed, scrolled out of the deck, Home torn down).
    static func update(_ id: UUID, frame: CGRect?) {
        if let frame { frames[id] = frame } else { frames.removeValue(forKey: id) }
    }

    /// Whether a touch at `point` (global) began inside a card's no-page zone.
    /// Points in the page-edge stripes are NEVER a no-page zone — the pager
    /// owns them regardless of what lies underneath (see pageEdgeFraction).
    static func contains(_ point: CGPoint, pageWidth: CGFloat) -> Bool {
        guard !inPageEdgeStripe(point, pageWidth: pageWidth) else { return false }
        return frames.values.contains { $0.contains(point) }
    }
}

#if canImport(UIKit)

    private struct SuggestionDraftTextView: UIViewRepresentable {
        @Binding var text: String
        /// false = a read-only preview: the text view passes every touch to
        /// SwiftUI so the box's tap gesture (→ the draft edit sheet) wins.
        var editable = true
        /// The draft took focus (the keyboard is coming up) — the surface lifts
        /// the box clear of it.
        var onFocus: () -> Void = {}

        func makeCoordinator() -> Coordinator {
            Coordinator(text: $text, onFocus: onFocus)
        }

        func makeUIView(context: Context) -> UITextView {
            let textView = UITextView()
            textView.delegate = context.coordinator
            textView.backgroundColor = .clear
            textView.textColor = UIColor(Color(light: 0x6E6E6E, dark: 0xD1D1D6))
            textView.font = .systemFont(ofSize: 14.5, weight: .regular)
            textView.textContainerInset = .zero
            textView.textContainer.lineFragmentPadding = 0
            textView.textContainer.lineBreakMode = .byWordWrapping
            textView.isEditable = editable
            textView.isSelectable = editable
            textView.isUserInteractionEnabled = editable
            // Read-only preview: interaction is off, so an inner scroll region
            // is unreachable — with scrolling on, anything past the frame is
            // simply CUT ("ich kann nicht die ganze Mail sehen"). Scroll only
            // when editable; otherwise report intrinsic height so the box
            // grows to the whole draft.
            textView.isScrollEnabled = editable
            textView.showsVerticalScrollIndicator = false
            textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            // Read-only: the box must win the vertical fight so the full draft
            // shows; editable (sheet) keeps the flexible layout.
            textView.setContentCompressionResistancePriority(editable ? .defaultLow : .required, for: .vertical)
            textView.typingAttributes = Self.typingAttributes()
            return textView
        }

        /// Read-only preview: intrinsicContentSize alone under-reports before
        /// the width is known (the box stayed clipped at ~3 lines and, with
        /// interaction off, the rest was unreachable). Answer SwiftUI's actual
        /// width proposal with the text's real height so the box grows to the
        /// whole draft. Editable (sheet) keeps flexible sizing.
        func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
            guard !editable, let width = proposal.width, width.isFinite, width > 0 else { return nil }
            let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            return CGSize(width: width, height: fitted.height)
        }

        func updateUIView(_ textView: UITextView, context: Context) {
            if textView.text != text {
                textView.text = text
            }
            textView.isEditable = editable
            textView.isSelectable = editable
            textView.isUserInteractionEnabled = editable
            textView.isScrollEnabled = editable
            textView.typingAttributes = Self.typingAttributes()
            context.coordinator.onFocus = onFocus
        }

        private static func typingAttributes() -> [NSAttributedString.Key: Any] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            return [
                .font: UIFont.systemFont(ofSize: 14.5, weight: .regular),
                .foregroundColor: UIColor(Color(light: 0x6E6E6E, dark: 0xD1D1D6)),
                .paragraphStyle: paragraph
            ]
        }

        final class Coordinator: NSObject, UITextViewDelegate {
            @Binding private var text: String
            var onFocus: () -> Void

            init(text: Binding<String>, onFocus: @escaping () -> Void) {
                _text = text
                self.onFocus = onFocus
            }

            func textViewDidChange(_ textView: UITextView) {
                text = textView.text
            }

            func textViewDidBeginEditing(_: UITextView) {
                onFocus()
            }
        }
    }

    // MARK: - Horizontal swipe attachment (design-app port)

    /// Ported from the design app (HomeSections.HorizontalSwipeGestureAttachment):
    /// SwiftUI drag gestures inside the scroll/pager stack don't coexist with the
    /// pager (they win the arbitration and horizontal page swipes die), so the
    /// view installs a UIKit pan on its enclosing scroll view instead. The pan
    /// only begins for a decisively horizontal movement over this view (screen
    /// edges stay reserved for edge swipes, and each direction can be opted out
    /// so the pager keeps it), rides along with vertical scrolling (unless
    /// `locksVerticalScroll` cancels it once the swipe claims), and refuses
    /// simultaneous recognition with any paging scroll view — so a claimed swipe
    /// never drags the Home⇄Chat pager. Used by the suggestion cards
    /// (execute/dismiss) and the chat transcript (timestamp reveal).
    struct HorizontalSwipeGestureAttachment: UIViewRepresentable {
        var axisRatio: CGFloat = 1.25
        var edgeSwipeWidth: CGFloat = 40
        /// Opt-in to the 18% page-edge contract (Home cards): the pan refuses
        /// touches that started in the stripes, which belong to the pager /
        /// menu scrub. Chat's transcript gestures stay full-screen (false).
        var usesPageEdgeStripes = false
        /// Opt-in for dismiss swipes (Home cards): once this pan begins, cancel
        /// the host scroll view's own pan so the list can't keep scrolling
        /// under a card that's riding out. Chat's timestamp reveal keeps the
        /// ride-along (false) — vertical scrolling there stays legal mid-reveal.
        var locksVerticalScroll = false
        var allowsLeftward = true
        var allowsRightward = true
        /// Arbitration between OVERLAPPING attachments on the same scroll view:
        /// a higher-priority pan (the photo deck's scrub) must resolve before a
        /// lower one (the transcript-wide timestamp reveal) may begin — else a
        /// leftward swipe on a deck would flip the photo AND slide every bubble
        /// over. Same-priority attachments never overlap (cards tile).
        var priority = 0
        let onChanged: (CGSize) -> Void
        var onEnded: (CGSize) -> Void = { _ in }
        /// Velocity-aware alternative to `onEnded` (translation, then pts/s
        /// velocity at release) — takes over delivery when set. The deck scrub
        /// commits on a FLICK, which translation alone can't see; a cancelled
        /// pan reports zero for both.
        var onEndedVelocity: ((CGSize, CGSize) -> Void)?

        func makeCoordinator() -> Coordinator {
            Coordinator(onChanged: onChanged, onEnded: onEnded)
        }

        func makeUIView(context: Context) -> HorizontalSwipeAttachmentView {
            let view = HorizontalSwipeAttachmentView()
            view.coordinator = context.coordinator
            return view
        }

        func updateUIView(_ view: HorizontalSwipeAttachmentView, context: Context) {
            context.coordinator.axisRatio = axisRatio
            context.coordinator.edgeSwipeWidth = edgeSwipeWidth
            context.coordinator.usesPageEdgeStripes = usesPageEdgeStripes
            context.coordinator.locksVerticalScroll = locksVerticalScroll
            context.coordinator.allowsLeftward = allowsLeftward
            context.coordinator.allowsRightward = allowsRightward
            context.coordinator.priority = priority
            context.coordinator.onChanged = onChanged
            context.coordinator.onEnded = onEnded
            context.coordinator.onEndedVelocity = onEndedVelocity
            view.coordinator = context.coordinator
            view.installIfNeeded()
        }

        @MainActor
        final class Coordinator: NSObject, UIGestureRecognizerDelegate {
            var axisRatio: CGFloat = 1.25
            var edgeSwipeWidth: CGFloat = 40
            var usesPageEdgeStripes = false
            var locksVerticalScroll = false
            var allowsLeftward = true
            var allowsRightward = true
            var priority = 0
            var onChanged: (CGSize) -> Void
            var onEnded: (CGSize) -> Void
            var onEndedVelocity: ((CGSize, CGSize) -> Void)?
            weak var cardView: UIView?
            /// The touch-DOWN x in the scroll view, captured in shouldReceive —
            /// the ONLY location that can honestly answer "did this drag start
            /// in a page-edge stripe?" (see gestureRecognizerShouldBegin).
            var initialTouchX: CGFloat?

            init(onChanged: @escaping (CGSize) -> Void, onEnded: @escaping (CGSize) -> Void) {
                self.onChanged = onChanged
                self.onEnded = onEnded
            }

            func gestureRecognizer(
                _ gestureRecognizer: UIGestureRecognizer,
                shouldReceive touch: UITouch
            ) -> Bool {
                // Capture the un-moved touch-down location for shouldBegin's
                // stripe test; the pan's own location has already traveled by
                // the time recognition velocity is reached.
                initialTouchX = touch.location(in: gestureRecognizer.view).x
                return true
            }

            func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
                guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                      let scrollView = gestureRecognizer.view,
                      let cardView else {
                    return false
                }

                // The pager already owns this touch (the page is visibly
                // moving) — a late recognition must not steal it. See
                // `PagerHorizontalDrag`.
                if PagerHorizontalDrag.isActive { return false }

                // Page-edge stripes belong to the pager unconditionally (the
                // page-edge contract, see pageEdgeFraction) — on top of any explicit
                // per-attachment band the call site asked for. Tested against
                // the TOUCH-DOWN location, never the pan's current one: by the
                // time a fast flick reaches recognition velocity the finger has
                // already left the stripe, and testing the live location let
                // the pan begin anyway — the "it pages AND rejects the card"
                // double-trigger.
                let startX = initialTouchX ?? pan.location(in: scrollView).x
                let stripes = usesPageEdgeStripes ? scrollView.bounds.width * pageEdgeFraction : 0
                let edge = max(edgeSwipeWidth, stripes)
                guard startX > edge,
                      startX < scrollView.bounds.width - edge else {
                    return false
                }

                let touchPoint = pan.location(in: cardView)
                guard cardView.bounds.insetBy(dx: -4, dy: -4).contains(touchPoint) else {
                    return false
                }

                let velocity = pan.velocity(in: scrollView)
                guard abs(velocity.x) > 12, abs(velocity.x) > abs(velocity.y) * axisRatio else {
                    return false
                }
                // Directions the view doesn't claim stay with the pager.
                return velocity.x < 0 ? allowsLeftward : allowsRightward
            }

            func gestureRecognizer(
                _ gestureRecognizer: UIGestureRecognizer,
                shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
            ) -> Bool {
                // Vertical scrolling may ride along; the page-style pager must
                // not — exclusivity lets whichever pan begins first win outright.
                if let scrollView = otherGestureRecognizer.view as? UIScrollView, scrollView.isPagingEnabled {
                    return false
                }
                // Sibling attachments are mutually exclusive: one touch, one
                // design (deck scrub XOR timestamp reveal, never both).
                if otherGestureRecognizer.delegate is Coordinator {
                    return false
                }
                return true
            }

            func gestureRecognizer(
                _ gestureRecognizer: UIGestureRecognizer,
                shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
            ) -> Bool {
                // Defer to any overlapping higher-priority sibling: this pan
                // may only begin once that one has bowed out (off its view,
                // wrong axis, wrong direction).
                if let other = otherGestureRecognizer.delegate as? Coordinator {
                    return other.priority > priority
                }
                return false
            }

            func gestureRecognizer(
                _ gestureRecognizer: UIGestureRecognizer,
                shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
            ) -> Bool {
                // Mirror of shouldRequireFailureOf, asked from this side: a
                // lower-priority sibling waits for this pan to resolve.
                if let other = otherGestureRecognizer.delegate as? Coordinator {
                    return other.priority < priority
                }
                // The pager's pan must WAIT for this pan to resolve, not race
                // it: a touch that lands while the pager is still settling from
                // a fast page swipe otherwise begins the paging pan at
                // touch-down and swallows the drag before this recognizer can
                // claim it (chat's timestamp reveal dying into a page pull).
                // Directions/areas this view doesn't claim fail in
                // gestureRecognizerShouldBegin, releasing the pager immediately.
                if let scrollView = otherGestureRecognizer.view as? UIScrollView, scrollView.isPagingEnabled {
                    return true
                }
                return false
            }

            @objc func handlePan(_ pan: UIPanGestureRecognizer) {
                let translation = pan.translation(in: pan.view)
                let size = CGSize(width: translation.x, height: translation.y)

                switch pan.state {
                case .began:
                    HorizontalSwipeClaim.isActive = true
                    if locksVerticalScroll { cancelVerticalScroll(of: pan) }
                    onChanged(size)
                case .changed:
                    HorizontalSwipeClaim.isActive = true
                    onChanged(size)
                case .ended:
                    releaseClaim()
                    if let onEndedVelocity {
                        let velocity = pan.velocity(in: pan.view)
                        onEndedVelocity(size, CGSize(width: velocity.x, height: velocity.y))
                    } else {
                        onEnded(size)
                    }
                case .cancelled, .failed:
                    releaseClaim()
                    if let onEndedVelocity {
                        onEndedVelocity(.zero, .zero)
                    } else {
                        onEnded(.zero)
                    }
                default:
                    break
                }
            }

            /// A claimed dismiss swipe owns the whole touch: bounce the host
            /// scroll view's pan through isEnabled, which cancels it mid-flight.
            /// The scroll pan missed this touch once re-enabled (recognizers
            /// only track touches they saw begin), so scrolling stays out until
            /// the next touch-down — no restore bookkeeping needed.
            private func cancelVerticalScroll(of pan: UIPanGestureRecognizer) {
                guard let scrollView = pan.view as? UIScrollView else { return }
                scrollView.panGestureRecognizer.isEnabled = false
                scrollView.panGestureRecognizer.isEnabled = true
            }

            /// Drop the pager suppression NEXT runloop turn: the pager's own
            /// `onEnded` fires for the same touch-up in an indeterminate order
            /// with this pan's `.ended`, and must still see the claim — else a
            /// committed reject swipe would double as a page change.
            private func releaseClaim() {
                DispatchQueue.main.async {
                    HorizontalSwipeClaim.isActive = false
                }
            }
        }
    }

    /// The invisible overlay view: hit-testing is disabled (taps fall through to
    /// the card button); its only job is to install/remove the pan on the
    /// enclosing scroll view and to serve as the card-bounds reference.
    final class HorizontalSwipeAttachmentView: UIView {
        weak var coordinator: HorizontalSwipeGestureAttachment.Coordinator? {
            didSet { installIfNeeded() }
        }

        private weak var installedScrollView: UIScrollView?
        private var panRecognizer: UIPanGestureRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // Swift 6 forbids UIKit calls in deinit, so tear down on detach
            // instead: a removed card must not leave its pan (and captured card
            // state) installed on the scroll view.
            if window == nil {
                uninstall()
            } else {
                installIfNeeded()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            installIfNeeded()
        }

        override func point(inside _: CGPoint, with _: UIEvent?) -> Bool {
            false
        }

        func installIfNeeded() {
            guard window != nil,
                  let scrollView = enclosingScrollView(),
                  let coordinator else {
                return
            }

            // The overlay fills the card, so its own bounds are the swipe area.
            coordinator.cardView = self

            if installedScrollView === scrollView, panRecognizer?.delegate === coordinator {
                return
            }

            uninstall()
            let pan = UIPanGestureRecognizer(
                target: coordinator,
                action: #selector(HorizontalSwipeGestureAttachment.Coordinator.handlePan(_:))
            )
            pan.cancelsTouchesInView = false
            pan.delaysTouchesBegan = false
            pan.delegate = coordinator
            scrollView.addGestureRecognizer(pan)
            installedScrollView = scrollView
            panRecognizer = pan
        }

        private func uninstall() {
            if let panRecognizer, let installedScrollView {
                installedScrollView.removeGestureRecognizer(panRecognizer)
            }
            panRecognizer = nil
            installedScrollView = nil
        }

        /// The nearest non-paging ancestor scroll view (Home's vertical scroll —
        /// never the pager itself).
        private func enclosingScrollView() -> UIScrollView? {
            var candidate = superview

            while let view = candidate {
                if let scrollView = view as? UIScrollView, !scrollView.isPagingEnabled {
                    return scrollView
                }
                candidate = view.superview
            }

            return nil
        }
    }


#endif
