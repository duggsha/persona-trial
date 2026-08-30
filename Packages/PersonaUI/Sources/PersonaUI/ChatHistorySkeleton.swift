import PersonaDesign
import SwiftUI

/// Bubble-shaped placeholder transcript shown while the FIRST history load is
/// still in flight and there is nothing to paint — the same travelling-highlight
/// treatment as `ShimmerBar`, swept across a whole mock conversation at once so
/// the blank chat page reads as "messages loading", not a dead screen.
struct ChatHistorySkeleton: View {
    @State private var phase: CGFloat = -0.7

    /// One placeholder bubble: side, width as a fraction of the transcript, and
    /// height. The long/short rhythm loosely echoes a real conversation so the
    /// skeleton reads as messages rather than stripes.
    private struct Row {
        let isUser: Bool
        let width: CGFloat
        let height: CGFloat
    }

    private static let rows: [Row] = [
        Row(isUser: false, width: 0.62, height: 44),
        Row(isUser: false, width: 0.38, height: 36),
        Row(isUser: true, width: 0.55, height: 44),
        Row(isUser: false, width: 0.74, height: 64),
        Row(isUser: true, width: 0.34, height: 36),
        Row(isUser: false, width: 0.48, height: 44),
        Row(isUser: true, width: 0.60, height: 56),
        Row(isUser: false, width: 0.70, height: 44),
        Row(isUser: true, width: 0.42, height: 36),
        Row(isUser: false, width: 0.58, height: 56),
        Row(isUser: false, width: 0.36, height: 36),
        Row(isUser: true, width: 0.52, height: 44),
    ]

    /// Same-sender rows sit close, a sender change opens a turn gap — the real
    /// transcript's per-pair spacing (ChatBubbleGrouping), so the skeleton
    /// doesn't shift rhythm when the messages land.
    private nonisolated static func gapAbove(_ index: Int) -> CGFloat {
        ChatBubbleGrouping.gapAbove(
            previousIsUser: rows[index - 1].isUser, currentIsUser: rows[index].isUser
        )
    }

    private static let totalHeight: CGFloat =
        rows.map(\.height).reduce(0, +) + (1 ..< rows.count).map(gapAbove).reduce(0, +)

    var body: some View {
        bubbles
            // One highlight travels the whole skeleton (ShimmerBar's gradient,
            // masked to the bubble shapes) — calmer than nine bars each running
            // their own sweep.
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightOpacity: 0.55, darkOpacity: 0.18), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.55)
                    .offset(x: geo.size.width * phase)
                }
                .mask(bubbles)
            }
            .frame(height: Self.totalHeight)
            .onAppear {
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                    phase = 1.25
                }
            }
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel("Loading conversation")
    }

    private var bubbles: some View {
        VStack(spacing: 0) {
            ForEach(Self.rows.indices, id: \.self) { index in
                let row = Self.rows[index]
                GeometryReader { geo in
                    // The real bubble's corner radius (capped at a capsule for
                    // the shortest rows) so corners don't snap when content
                    // replaces the placeholder.
                    RoundedRectangle(
                        cornerRadius: min(IMessageBubbleShape.cornerRadius, row.height / 2),
                        style: .continuous
                    )
                    .fill(DS.Palette.ink.opacity(row.isUser ? 0.10 : 0.07))
                        .frame(width: geo.size.width * row.width, height: row.height)
                        .frame(maxWidth: .infinity, alignment: row.isUser ? .trailing : .leading)
                }
                .frame(height: row.height)
                .padding(.top, index == 0 ? 0 : Self.gapAbove(index))
            }
        }
    }
}
