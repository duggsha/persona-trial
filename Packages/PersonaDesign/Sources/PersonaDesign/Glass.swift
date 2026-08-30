import SwiftUI

/// iOS 26.4+ renders liquid glass with a markedly heavier gray frost than the
/// 26.3-era renderer this design was tuned against (looks right on a 26.3 sim,
/// reads "super gray" on a 26.5 phone). Counter it with a white tint on those
/// runtimes ONLY — 26.0–26.3 keeps the original, untinted look untouched.
/// This is the tuning knob: raise to lighten device glass, lower if chrome
/// starts reading as flat white.
private enum GlassFrostCompensation {
    /// Regular glass — composer bar, header capsule/circle.
    static let regular = 0.38
}

@available(iOS 26.0, macOS 26.0, *)
private func frostCompensated(_ glass: Glass, whiteTint: Double) -> Glass {
    if #available(iOS 26.4, macOS 26.4, *) {
        // Adaptive tint: the 26.4+ frost uses a WHITE base, so in dark mode
        // the untinted chrome GLOWS. Light keeps the white
        // compensation; dark counter-tints toward black to sit the chrome
        // into the dark canvas instead of floating above it.
        return glass.tint(Color(light: 0xFFFFFF, dark: 0x1C1C1E, lightOpacity: whiteTint, darkOpacity: 0.42))
    }
    return glass
}

/// Surface treatments. Liquid Glass is CHROME-ONLY (composer bar, header
/// capsule/circle, floating buttons) — Apple's layering rule, and ours: glass
/// in the content layer had nothing to refract over the flat canvas, cost a
/// live GPU sample per view inside scrolling lists, and rendered differently
/// on every runtime (materials pre-26, frost shifts across 26.x, the user's
/// Clear/Tinted setting). Content surfaces are solid plates
/// De-glass the content layer.
///
/// The only deliberate addition over the design is `.compositingGroup()` before
/// each shadow (flattens the surface so the drop shadow is drawn once — a perf
/// win that does not change the look).
public extension View {
    /// `isEnabled: false` keeps the modified view IN the glass element but
    /// renders no glass (`Glass.identity` — this SDK's glassEffect has no
    /// isEnabled parameter) — the toggle for surfaces whose glass fades with
    /// state (the header wordmark). A branch-swap (`if` around the modifier)
    /// would re-identity the content and cross-fade it; this doesn't.
    @ViewBuilder
    func personaGlass(in shape: some Shape, interactive: Bool = false, isEnabled: Bool = true) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            glassEffect(
                isEnabled
                    ? frostCompensated(.regular.interactive(interactive),
                                       whiteTint: GlassFrostCompensation.regular)
                    : .identity,
                in: shape
            )
        } else {
            background(.ultraThinMaterial.opacity(isEnabled ? 1 : 0), in: shape)
        }
    }

    /// The secondary card surface (sheet list rows, settings cards, call
    /// panels): the caller's tint flattened over a white plate, with a soft
    /// hairline. Replaces the clear-glass mediumGlassPanel — over flat sheet
    /// backgrounds the glass had nothing to refract and read as a grey field
    /// that shifted per runtime.
    func solidListPlate(fill: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        return background(fill, in: shape)
            // The shadow is cast by the OPAQUE plate shape, not by a
            // compositing group over the row's whole content — see
            // `solidCardPlate` for why. Same silhouette, same opacity, no
            // offscreen content raster.
            .background {
                shape.fill(DS.Palette.card)
                    .shadow(color: .black.opacity(0.025), radius: 7, x: 0, y: 3)
            }
            .overlay { shape.stroke(DS.Palette.hairlineSoft, lineWidth: 1) }
    }

    /// The solid full-white card plate — the one card color across the app — suggestion cards already paint it directly (their
    /// swipe tint mixes into the fill), and task / login / empty-state cards
    /// wear it through this. Depth pair = the suggestion plate's soft ambient
    /// halo + tight contact shadow, so every card floats at the same height.
    /// PERF (): the depth pair is cast by the PLATE SHAPE, not by a
    /// `compositingGroup()` over the card's whole content. The old form made
    /// every shadowed card rasterize its entire subtree offscreen to derive
    /// the shadow — re-done on every frame the card moves (pager drag, feed
    /// scroll) or resizes (a suggestion's expand grow). The plate is opaque
    /// and the content clips to the same rounded rect, so the composite's
    /// silhouette WAS this shape: same shadow, no raster. (Applies to every
    /// plate recipe in this file.)
    func solidCardPlate(radius: CGFloat = DS.Radius.card) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background {
            shape.fill(DS.Palette.card)
                .dsShadow(DS.Shadow.plate)
        }
    }

    /// The generative chat-card surface — the ONE recipe every inline card the
    /// agent streams (collection, task, agenda, payment, profile, connect, …)
    /// should wear. The SAME solid full-white plate as the assistant bubbles
    /// and the Home cards (one white across every card —
    /// the old glass-over-tint recipe read a step grey next to them), at the
    /// bubble radius so a card sits next to a bubble as a peer. Shadow is the
    /// bubbles' Figma-spec contact shadow only (black 4%, y 3, σ2) — the
    /// cards' 18pt ambient halo pools between surfaces stacked a few points
    /// apart in a transcript.
    func chatCardPanel(radius: CGFloat = DS.Radius.bubble) -> some View {
        modifier(ChatCardPanelModifier(radius: radius))
    }

    /// Marks a subtree whose cards render INSIDE an iMessage bubble: the bubble
    /// is the card's surface, so `chatCardPanel` renders nothing of its own.
    func chatCardPanelSuppressed(_ suppressed: Bool = true) -> some View {
        environment(\.chatCardPanelSuppressed, suppressed)
    }

    /// An inset surface for a tappable row / tile INSIDE a `chatCardPanel`
    /// (a place tile, a selection option). A soft grey well with a faint dark
    /// hairline: the panel is now a SOLID white plate, so the old translucent
    /// white fill + white stroke rendered the tile invisible on it.
    func chatCardInset(fill: Color = DS.Palette.surfaceMuted, radius: CGFloat = DS.Radius.md + 2) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(fill, in: shape)
            .overlay { shape.stroke(Color(light: 0x000000, dark: 0xFFFFFF, lightOpacity: 0.05, darkOpacity: 0.10), lineWidth: 0.5) }
    }

    /// The voice-call / lightweight-thread bubble surface: a solid tinted
    /// plate, matching the main transcript's plate bubbles. Was per-bubble
    /// live glass — one GPU sample per row inside a scrolling thread.
    func chatBubblePlate(fill: Color, cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(fill, in: shape)
            .compositingGroup()
            .shadow(color: DS.Palette.shadow.opacity(0.045), radius: 4, x: 0, y: 1)
    }

    /// The floating composer bar surface. No shadow here — the composer applies its
    /// own bar-level shadow (matches the design; avoids a double shadow).
    /// REGULAR glass for body (clear read as insubstantial over the wash); the
    /// bar's whiteness is tuned via its underlay fill at the call site instead.
    /// `interactive: false` for surfaces that own their press feedback: the
    /// system swell cancels when the pressed view re-renders mid-touch (the
    /// composer's hold-to-record flips it into voice mode 0.1s in), snapping
    /// the surface back under a still-down finger.
    func composerGlassSurface(in shape: some Shape, interactive: Bool = true) -> some View {
        personaGlass(in: shape, interactive: interactive)
    }

    /// The small floating header capsule (home/chat toggle). `isEnabled: false`
    /// fades the whole rig out (underlay, glass, shadow) while the content
    /// keeps its identity — see personaGlass.
    func smallGlassCapsule(isEnabled: Bool = true) -> some View {
        let shape = Capsule(style: .continuous)
        return background(
            Color(light: 0xFFFFFF, dark: 0x1C1C1E, lightOpacity: 0.35, darkOpacity: 0.35)
                .opacity(isEnabled ? 1 : 0),
            in: shape
        )
        .personaGlass(in: shape, interactive: true, isEnabled: isEnabled)
        .compositingGroup()
        .shadow(color: .black.opacity(isEnabled ? 0.12 : 0), radius: 35, x: 0, y: 7)
    }

    /// The small floating header circle (avatar).
    func smallGlassCircle() -> some View {
        background(Color(light: 0xFFFFFF, dark: 0x1C1C1E, lightOpacity: 0.35, darkOpacity: 0.35), in: Circle())
            .personaGlass(in: Circle(), interactive: true)
            .compositingGroup()
            .shadow(color: .black.opacity(0.12), radius: 35, x: 0, y: 7)
    }
}

/// When true, a card sits inside an iMessage bubble that already IS its
/// surface — the card's own glass panel must not draw underneath it.
private struct ChatCardPanelSuppressedKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var chatCardPanelSuppressed: Bool {
        get { self[ChatCardPanelSuppressedKey.self] }
        set { self[ChatCardPanelSuppressedKey.self] = newValue }
    }
}

private struct ChatCardPanelModifier: ViewModifier {
    @Environment(\.chatCardPanelSuppressed) private var suppressed
    let radius: CGFloat

    func body(content: Content) -> some View {
        if suppressed {
            content
        } else {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            content
                // Shape-cast shadow — see `solidCardPlate`. Inline chat cards
                // ride the transcript, so they paid the raster on every
                // scroll frame.
                .background {
                    shape.fill(DS.Palette.card)
                        .dsShadow(DS.Shadow.contact)
                }
        }
    }
}
