import SwiftUI

/// The Persona brand mark (the black teardrop), fit inside a square slot so it
/// drops in anywhere an avatar/badge-sized glyph goes. The old blue "smile orb"
/// is retired — this is the only brand glyph in the app.
public struct BrandMark: View {
    private let size: CGFloat

    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        PersonaAsset.image("PersonaMark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

/// A live "in progress" green dot with a soft ring.
public struct PulseDot: View {
    private let color: Color

    /// Defaults to the live-activity green; pass an attention color (e.g. the
    /// amber used for "needs your input") to flag a task that's parked on you.
    public init(color: Color = DS.Palette.success) {
        self.color = color
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .overlay { Circle().stroke(color.opacity(0.28), lineWidth: 2) }
            .frame(width: 10, height: 10)
    }
}

/// A horizontal progress bar that fills the available width.
public struct ProgressTrack: View {
    private let progress: Double
    private let color: Color

    /// Defaults to the live-activity green; pass an attention color (e.g. the
    /// amber used for "needs your input") so the fill mirrors the task's status.
    public init(progress: Double, color: Color = DS.Palette.success) {
        self.progress = max(0, min(1, progress))
        self.color = color
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(DS.Palette.track)
                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: 6)
    }
}

/// A small labelled pill for card metadata — a price, ★rating, "Prime", tag, etc.
/// Generic and universal: the caller passes the accent `color` and an optional
/// leading glyph. Tinted capsule, compact, rounded numerals.
public struct MetaBadge: View {
    private let text: String
    private let systemImage: String?
    private let color: Color

    public init(_ text: String, systemImage: String? = nil, color: Color = DS.Palette.inkMuted) {
        self.text = text
        self.systemImage = systemImage
        self.color = color
    }

    public var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .bold))
            }
            Text(text).font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
        // A badge is a glanceable chip — it hugs its content on ONE line rather
        // than wrapping into a two-line pill inside a tight tile.
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule(style: .continuous))
    }
}

/// A left-aligned section heading ("Quick Actions", "Tasks", …).
public struct SectionHeader: View {
    public enum Style {
        /// The classic bold heading (sheets, Settings, Around).
        case standard
        /// Home's quiet divider label: the cards carry the visual weight,
        /// the label only names the group.
        case compact
    }

    private let title: String
    private let style: Style

    public init(_ title: String, style: Style = .standard) {
        self.title = title
        self.style = style
    }

    public var body: some View {
        // Localize the header from the app catalog (Text(String) is verbatim).
        // A literal title resolves to its translation; a dynamic one falls back.
        switch style {
        case .standard:
            Text(String(localized: String.LocalizationValue(title)))
                .font(DS.Typography.sectionTitle)
                .tracking(-0.27)
                // Pure black in light (unchanged); near-white in dark.
                .foregroundStyle(Color(light: 0x000000, dark: 0xECECEF))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .compact:
            Text(String(localized: String.LocalizationValue(title)))
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.1)
                .foregroundStyle(DS.Palette.subtle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
