import PersonaDesign
import SwiftUI

/// The first-run launch skeleton: shimmer stand-ins for the home layout — the
/// hero card slot and a couple of section rows — shown ONLY while the very
/// first refresh of an empty-cache install is in flight. Any launch with a
/// snapshot paints its last-known content instantly instead; the skeleton
/// never covers cached content (the shimmer-at-launch doctrine — same
/// treatment as the greeting's writing state, so it reads as one system).
/// Monochrome by design: `ShimmerBar` greys only, no color, no spinner.

/// The Up Next slot's stand-in: same plate, insets and minimum height as
/// `MeetingCard`, with shimmer bars where the caption/headline/subtitle land
/// and ghost shapes where the action row sits.
struct HomeSkeletonHeroCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                ShimmerBar(height: 10).frame(width: 56)
                ShimmerBar(height: 15).frame(maxWidth: 270)
                ShimmerBar(height: 12).frame(maxWidth: 225)
            }
            .padding(.horizontal, 19)

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Capsule(style: .continuous)
                    .fill(DS.Palette.ink.opacity(0.05))
                    .frame(width: 96, height: 32)
                Spacer(minLength: 8)
                Circle()
                    .fill(DS.Palette.ink.opacity(0.05))
                    .frame(width: 32, height: 32)
            }
            .padding(.leading, 13)
            .padding(.trailing, 14)
        }
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 140)
        .solidCardPlate()
        .accessibilityHidden(true)
    }
}

/// Two ghost sections where the decks (Updates/Tasks/Suggestions) will land:
/// a section-header bar and two card rows each, on the sections' real spacing
/// rhythm (26 between sections, 12 under the header, 10 between rows).
struct HomeSkeletonSections: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            skeletonSection
            skeletonSection
        }
        .accessibilityHidden(true)
    }

    private var skeletonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShimmerBar(height: 13).frame(width: 92)
            VStack(spacing: 10) {
                skeletonRow
                skeletonRow
            }
        }
    }

    private var skeletonRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShimmerBar(height: 13).frame(maxWidth: 210)
            ShimmerBar(height: 11).frame(maxWidth: 260)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .solidCardPlate()
    }
}
