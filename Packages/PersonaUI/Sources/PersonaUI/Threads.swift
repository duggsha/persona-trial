import PersonaCore
import PersonaDesign
import PersonaService
import SwiftUI

/// The small chip under a message that opens its side thread. Flat in the
/// assistant bubble's fill — a sibling of the message above it, not a floating
/// glass pill — with the PersonaMark as its brand cue.
struct ThreadPreviewChip: View {
    let text: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                PersonaAsset.image("PersonaMark")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 11, height: 10)
                // Hard character cap, not a maxWidth frame: a flexible frame
                // expands to its cap and leaves short text swimming in a wide
                // pill (see ThreadHeaderView's title note).
                Text(text.count > 26 ? String(text.prefix(26)) + "…" : text)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(-0.08)
                    .foregroundStyle(DS.Palette.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .frame(height: 26)
            .incomingBubblePlate(in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// The top bar shown inside an open thread: back button + centred title.
struct ThreadHeaderView: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(DS.Palette.ink)
                    .frame(width: 42, height: 42)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .smallGlassCircle()

            Spacer(minLength: 8)

            // Hug the title TIGHTLY — natural width, no greedy max-width frame
            // (`.frame(maxWidth:)` expands to its cap, leaving a short title
            // swimming in a wide pill). A long title still truncates cleanly:
            // the spacers compress to their minimum and the tail ellipsizes.
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .tracking(-0.14)
                .foregroundStyle(DS.Palette.ink.opacity(0.82))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .smallGlassCapsule()

            Spacer(minLength: 8)

            // Balances the back button so the title stays centred.
            Color.clear.frame(width: 42, height: 42)
        }
        .padding(.horizontal, DS.Spacing.gutter)
        .padding(.top, 4)
    }
}
