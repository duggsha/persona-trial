import SwiftUI

/// The one app canvas behind every screen. Fills its container; the caller
/// applies `.ignoresSafeArea()`. FLAT, and exactly the Figma's #F8F8F8 —
/// after a round-trip through "whiter" corrections, the mock's value stands
///. The step of grey is what lets
/// the solid-white cards and bubbles read as surfaces at all; no gradient —
/// cards separate via their shadows, not canvas contrast.
public struct SharedAppBackground: View {
    public init() {}

    @Environment(\.colorScheme) private var scheme

    public var body: some View {
        // Light: the soft blue-grey wash PNG (design — "Home
        // Design" export) at HALF strength over pure white, so the tint
        // reads as a whisper rather than the export's full saturation
        //. Scaled to fill
        // whatever the caller proposes. Dark keeps the flat near-black
        // canvas (DS.Palette.canvas): the wash is a light-only design, and
        // dark cards separate by elevation, not contrast.
        if scheme == .dark {
            DS.Palette.canvas
        } else {
            GeometryReader { geo in
                ZStack {
                    Color.white
                    PersonaAsset.image("AppWashBackground")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .opacity(0.5)
                }
            }
        }
    }
}

/// A top-edge blur ramp that lets the floating header sit above scrolling content.
public struct TopHeaderBackdrop: View {
    /// Low Power Mode drops this entirely: a live material re-samples the
    /// content beneath it on every frame that content moves, THROUGH a mask
    /// (a second offscreen pass) — a standing per-frame GPU tax with the GPU
    /// throttled. Rendering nothing is the main chat's own precedent (its
    /// header deliberately mounts no backdrop at all), so LPM surfaces read
    /// like the chat page rather than broken.
    @Environment(\.dsPowerSaving) private var powerSaving

    public init() {}

    public var body: some View {
        // ONLY the masked blur — no white wash at all. Any white gradient here
        // compounds with the near-white app wash into a visible solid bar under
        // the Dynamic Island; pure fading material is invisible over empty
        // background and only reads (as glass) once content scrolls beneath it.
        // The mask NEVER reaches full alpha: full-strength ultraThin over the
        // wash renders as a milky solid strip — the exact bar this replaces.
        if !powerSaving {
            Rectangle().fill(.ultraThinMaterial)
                .mask(ramp(start: 0.00, middle: 0.45, end: 0.90))
                .allowsHitTesting(false)
        }
    }

    private func ramp(start: CGFloat, middle: CGFloat, end: CGFloat) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.58), location: start),
                .init(color: .black.opacity(0.24), location: middle),
                .init(color: .clear, location: end)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// A bottom-edge blur ramp behind the floating composer.
public struct BottomComposerBackdrop: View {
    /// Low Power Mode keeps ONLY the flat white fade below: the live material
    /// re-samples the scrolling content beneath the composer on every frame,
    /// through its own mask — the single busiest per-frame GPU item in the
    /// app (it rides every page, over every scroll). The white ramp alone
    /// still settles the very bottom into the background; content slides
    /// under the bar unfrosted, which is how iMessage's input bar edge reads
    /// in practice.
    @Environment(\.dsPowerSaving) private var powerSaving

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            // One masked material + a white fade (see TopHeaderBackdrop) — the old
            // triple-blur stack was a constant GPU sink behind the composer.
            // THIN material, and it only begins a third of the way down: cards
            // stay legible as they slide under the bar, soften through the lower
            // stretch, and only the very bottom settles into the background.
            if !powerSaving {
                Rectangle().fill(.ultraThinMaterial)
                    .mask(ramp(start: 0.58, middle: 0.88, end: 1.00))
            }
            LinearGradient(
                stops: [
                    .init(color: Color(light: 0xFFFFFF, dark: 0x141416, lightOpacity: 0.00, darkOpacity: 0.00), location: 0.00),
                    .init(color: Color(light: 0xFFFFFF, dark: 0x141416, lightOpacity: 0.03, darkOpacity: 0.03), location: 0.64),
                    .init(color: Color(light: 0xFFFFFF, dark: 0x141416, lightOpacity: 0.14, darkOpacity: 0.14), location: 0.86),
                    .init(color: Color(light: 0xFFFFFF, dark: 0x141416, lightOpacity: 0.34, darkOpacity: 0.34), location: 0.94),
                    .init(color: Color(light: 0xFFFFFF, dark: 0x141416, lightOpacity: 0.62, darkOpacity: 0.62), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .mask(ramp(start: 0.56, middle: 0.86, end: 0.99))
        }
        .allowsHitTesting(false)
    }

    private func ramp(start: CGFloat, middle: CGFloat, end: CGFloat) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .clear, location: start),
                .init(color: .black.opacity(0.34), location: middle),
                .init(color: .black, location: end)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
