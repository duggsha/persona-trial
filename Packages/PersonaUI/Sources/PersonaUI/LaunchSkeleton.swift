import PersonaDesign
import SwiftUI

/// The launch-gate placeholder: the HOME screen's structure with shimmer where
/// content will land — real background, header chrome shapes, greeting lines,
/// the hero card and a task card — instead of a bare spinner on white. The
/// session check usually resolves in well under a second, so this reads as
/// "Home is coming" rather than "an app is thinking".
public struct LaunchSkeletonScreen: View {
    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            SharedAppBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header

                // Greeting block: location line + the big greeting line.
                ShimmerBar(height: 12)
                    .frame(width: 118)
                    .padding(.top, 26)
                ShimmerBar(height: 22)
                    .frame(width: 215)
                    .padding(.top, 9)

                heroCard
                    .padding(.top, 26)

                // A section header + one task-shaped card.
                ShimmerBar(height: 14)
                    .frame(width: 74)
                    .padding(.top, 30)
                taskCard
                    .padding(.top, 14)

                Spacer(minLength: 0)

                composerBar
            }
            .padding(.horizontal, DS.Spacing.gutter)
            .padding(.top, 4)
        }
    }

    /// The floating header chrome: brand-orb slot left, page-toggle capsule right.
    private var header: some View {
        HStack {
            Circle()
                .fill(DS.Palette.card.opacity(0.55))
                .frame(width: 32, height: 32)
            Spacer(minLength: 0)
            Capsule(style: .continuous)
                .fill(DS.Palette.card.opacity(0.50))
                .frame(width: 108, height: 42)
        }
    }

    /// The hero (meeting / suggested task) card silhouette.
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(DS.Palette.ink.opacity(0.07))
                    .frame(width: 26, height: 26)
                ShimmerBar(height: 15).frame(maxWidth: 170)
            }
            ShimmerBar(height: 12)
                .frame(maxWidth: 250)
                .padding(.top, 16)
            ShimmerBar(height: 12)
                .frame(maxWidth: 190)
                .padding(.top, 7)
            Spacer(minLength: 0)
            Capsule(style: .continuous)
                .fill(DS.Palette.ink.opacity(0.06))
                .frame(width: 132, height: 42)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 160)
        .solidCardPlate()
    }

    /// A task-card silhouette (icon square + title/subtitle + progress track).
    private var taskCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 9.62, style: .continuous)
                    .fill(DS.Palette.ink.opacity(0.07))
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 7) {
                    ShimmerBar(height: 13).frame(maxWidth: 180)
                    ShimmerBar(height: 11).frame(maxWidth: 110)
                }
                .padding(.top, 2)
                Spacer(minLength: 8)
            }
            ShimmerBar(height: 5)
                .padding(.top, 14)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .solidCardPlate()
    }

    /// The composer bar silhouette, at the bar's real resting position.
    private var composerBar: some View {
        RoundedRectangle(cornerRadius: 27, style: .continuous)
            .fill(DS.Palette.card.opacity(0.55))
            .frame(height: 54)
            .padding(.bottom, 32)
    }
}
