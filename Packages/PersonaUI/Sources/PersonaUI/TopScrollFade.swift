import PersonaDesign
import SwiftUI

/// Home's top-edge treatment, lifted verbatim out of `SettingsScreen` — that
/// 4,000-line file was cut from this trial and this modifier was the only thing
/// in it Home still used.

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
}

/// Hides iOS 26's automatic top scroll-edge effect (no-op pre-26). Its
/// white-ish wash under the status bar fights the header's glass ramp.
/// Lifted verbatim from `ChatScreen`, which this trial doesn't include.
struct TopScrollEdgeEffectHidden: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .top)
        } else {
            content
        }
    }
}
