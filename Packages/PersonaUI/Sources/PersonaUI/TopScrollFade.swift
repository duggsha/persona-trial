import PersonaDesign
import SwiftUI

/// The scroll surfaces' shared top-edge treatments, applied by both Home and
/// the chat transcript. Lifted verbatim out of the settings and chat files they
/// were originally defined in.

private struct TopScrollFadeModifier: ViewModifier {
    @Environment(\.dsPowerSaving) private var powerSaving

    func body(content: Content) -> some View {
        if powerSaving {
            content
        } else {
            content.mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.085)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
        }
    }
}

extension View {
    /// Softly fades the top edge of a scrolling surface so content dissolves into
    /// the background under the Dynamic Island instead of clipping with a hard edge
    /// (the reference's "content runs under the island and fades out" behaviour,
    /// without the GPU cost of a heavier top backdrop).
    func topScrollFade() -> some View {
        modifier(TopScrollFadeModifier())
    }

    /// Kills iOS 26's automatic scroll-edge wash on a transcript surface. The
    /// system effect paints a background-capture band over content near the
    /// scroll edges; on an overlay-mounted transcript that band lands mid-screen
    /// and washes bubbles out. `topScrollFade` is the only edge treatment these
    /// surfaces want.
    @ViewBuilder
    func transcriptEdgeEffectHidden() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: .all)
        } else {
            self
        }
    }
}

/// Hides iOS 26's automatic top scroll-edge effect (no-op pre-26). Its
/// white-ish wash under the status bar fights the header's glass ramp.
struct TopScrollEdgeEffectHidden: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .top)
        } else {
            content
        }
    }
}
