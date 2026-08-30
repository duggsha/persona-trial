import PersonaCore
import PersonaDesign
import SwiftUI

/// Brand artwork for an integration row, shared by Settings → Connected Apps and
/// the onboarding connect screen so both degrade identically.
///
/// The first-party account rows (mail / calendar / workspace) always show the
/// SERVICE mark, never the account domain's logo: logo.dev serves the same plain
/// Google "G" for every Google product, and a custom domain hosted on
/// Squarespace/GoDaddy serves the registrar's placeholder cube — both read as
/// the wrong brand next to "Gmail".
enum IntegrationBrandIcon: Equatable {
    /// Bundled glyph-shaped mark, drawn small on a white disc (like the app's
    /// own Gmail treatment) — full-bleed would distort a non-square glyph.
    case glyphAsset(String)
    /// Bundled square tile artwork, drawn full-bleed (e.g. Soar's favicon).
    case tileAsset(String)
    /// Brand domain fetched from logo.dev.
    case domain(String)
    /// A specific site's own favicon (its real product mark), for brands whose
    /// logo.dev entry is the wrong company logo — e.g. Canvas.
    case faviconHost(String)

    static func resolve(for i: Integration) -> IntegrationBrandIcon? {
        switch i.type {
        case "mail":
            return .glyphAsset(i.provider == "microsoft" ? "LogoOutlook" : "LogoGmail")
        case "calendar":
            return .glyphAsset(i.provider == "microsoft" ? "LogoOutlook" : "LogoGoogleCalendar")
        case "workspace":
            return .glyphAsset("LogoGoogleDrive")
        case "google-contacts":
            // Google Contacts product mark via its own domain — no bundled
            // asset yet; falls back to the category badge offline.
            return .domain("contacts.google.com")
        case "contacts":
            // The real iOS Contacts app icon (full-bleed tile) — the generic
            // silhouette badge read as a placeholder next to Gmail/Calendar
            // brand marks on the onboarding apps screen.
            return .tileAsset("LogoContactsApp")
        case "soar":
            // Near-black mark on transparency — as a full-bleed tile it vanishes on
            // the dark sheet in dark mode; a glyph badge sits it on a white disc.
            return .glyphAsset("LogoSoar")
        default:
            break
        }
        // Exact slug only — "x" as a substring would match half the catalog,
        // and "link" would claim LinkedIn and every "…link" tool besides.
        if i.slug == "x" || i.type == "x" { return .domain("x.com") }
        if i.slug == "link" || i.type == "link" { return .domain("link.com") }
        let key = "\(i.slug ?? "") \(i.type) \(i.title)".lowercased()
        if key.contains("ubereats") || (key.contains("uber") && key.contains("eat")) { return .domain("ubereats.com") }
        if key.contains("uber") { return .domain("uber.com") }
        if key.contains("lyft") { return .domain("lyft.com") }
        if key.contains("doordash") { return .domain("doordash.com") }
        if key.contains("opentable") { return .domain("opentable.com") }
        if key.contains("canvas") || key.contains("instructure") { return .faviconHost("canvas.instructure.com") }
        if key.contains("whatsapp") { return .domain("whatsapp.com") }
        // Registry connectors. Each is an EXACT brand domain rather than a
        // guess: logo.dev keys on the domain, and a near-miss serves the wrong
        // company's mark, which reads worse than the generic badge. Placed
        // above the google/microsoft fallbacks so a title mentioning either
        // cannot claim the row.
        if key.contains("telegram") { return .domain("telegram.org") }
        if key.contains("github") { return .domain("github.com") }
        if key.contains("linear") { return .domain("linear.app") }
        if key.contains("dropbox") { return .domain("dropbox.com") }
        if key.contains("discord") { return .domain("discord.com") }
        // zoom.us, not zoom.com — the .com is a different company entirely and
        // logo.dev happily serves its logo.
        if key.contains("zoom") { return .domain("zoom.us") }
        if key.contains("notion") { return .domain("notion.so") }
        if key.contains("slack") { return .domain("slack.com") }
        if key.contains("quickbooks") || key.contains("intuit") { return .domain("quickbooks.intuit.com") }
        if key.contains("soar") { return .glyphAsset("LogoSoar") }
        if key.contains("spotify") { return .domain("spotify.com") }
        if key.contains("amazon") { return .domain("amazon.com") }
        if key.contains("agentcard") || key.contains("mastercard") { return .domain("mastercard.com") }
        if key.contains("drive") { return .glyphAsset("LogoGoogleDrive") }
        if key.contains("gmail") { return .glyphAsset("LogoGmail") }
        if key.contains("outlook") || key.contains("microsoft") { return .glyphAsset("LogoOutlook") }
        if key.contains("google") { return .domain("google.com") }
        switch i.provider {
        case "google": return .domain("google.com")
        case "microsoft": return .domain("microsoft.com")
        default: return nil
        }
    }
}

/// The 38pt integration-row avatar: bundled service mark → logo.dev brand →
/// SF-symbol category badge.
struct IntegrationAvatar: View {
    let integration: Integration
    var size: CGFloat = 38

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.253, style: .continuous)
    }

    var body: some View {
        switch IntegrationBrandIcon.resolve(for: integration) {
        case .glyphAsset(let name):
            BrandGlyphBadge(asset: name, size: size)
        case .tileAsset(let name):
            PersonaAsset.image(name)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(shape)
                .overlay { shape.stroke(DS.Palette.hairlineSoft, lineWidth: 1) }
        case .domain(let domain):
            RemoteContactAvatar(
                source: .domain(domain),
                fallbackSymbol: integration.systemIcon,
                circle: false,
                size: size
            )
        case .faviconHost(let host):
            FaviconTile(host: host, fallbackSymbol: integration.systemIcon, size: size)
        case nil:
            CategoryIconBadge(symbol: integration.systemIcon, circle: false, size: size)
        }
    }
}

/// A bundled brand glyph small on a white rounded-rect disc — the same
/// treatment RemoteContactAvatar gives the Gmail mark, shared here so every
/// bundled service mark (Calendar, Drive, Outlook…) matches it exactly.
struct BrandGlyphBadge: View {
    let asset: String
    var size: CGFloat = 38

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.253, style: .continuous)
    }

    var body: some View {
        ZStack {
            shape.fill(DS.Palette.card)
            PersonaAsset.image(asset)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size * 0.58, height: size * 0.58)
        }
        .frame(width: size, height: size)
        .overlay { shape.stroke(DS.Palette.hairlineSoft, lineWidth: 1) }
    }
}

/// A site's own favicon on a white rounded tile — its real product mark, for
/// brands whose logo.dev entry is the wrong company logo. Google's favicon
/// service normalizes .ico → PNG and returns the actual site icon (e.g. the red
/// Canvas ring for canvas.instructure.com). Falls back to the category glyph.
struct FaviconTile: View {
    let host: String
    var fallbackSymbol: String = "square.grid.2x2.fill"
    var size: CGFloat = 38

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.253, style: .continuous)
    }
    private var url: URL? {
        URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128")
    }

    var body: some View {
        ZStack {
            shape.fill(.white)
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().interpolation(.high).scaledToFit()
                        .frame(width: size * 0.62, height: size * 0.62)
                default:
                    Image(systemName: fallbackSymbol)
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(DS.Palette.inkMuted)
                }
            }
        }
        .frame(width: size, height: size)
        .overlay { shape.stroke(DS.Palette.hairlineSoft, lineWidth: 1) }
    }
}
