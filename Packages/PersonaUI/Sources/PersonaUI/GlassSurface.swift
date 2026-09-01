import SwiftUI
import PersonaDesign

/// Real glass is never optically clean — it scatters. A flat material over a
/// flat fill reads as plastic, so every glass surface here gets a fine grain
/// laid over it: enough to catch the eye at arm's length, not enough to read
/// as texture.
struct Grain: View {
    var opacity: Double = 0.055
    var density: Int = 900

    var body: some View {
        Canvas { context, size in
            // Deterministic: a grain that reshuffles on every redraw shimmers,
            // which is the opposite of what glass does.
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> Double {
                seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                return Double(seed % 10_000) / 10_000
            }
            for _ in 0 ..< density {
                let x = next() * size.width
                let y = next() * size.height
                let bright = next()
                context.fill(
                    Path(CGRect(x: x, y: y, width: 1, height: 1)),
                    with: .color(.white.opacity(bright > 0.5 ? 1 : 0.35)))
            }
        }
        .opacity(opacity)
        .blendMode(.overlay)
        .allowsHitTesting(false)
        .drawingGroup()
    }
}

/// The house glass: material, a whisper of tint, grain, and a specular top
/// edge that falls off before the bottom.
struct GlassBackground: ViewModifier {
    var radius: CGFloat = 6
    var emphasis: Double = 1
    var grain: Bool = true

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .background(Color.primary.opacity(0.05 * emphasis), in: shape)
            .overlay { if grain { Grain().clipShape(shape) } }
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.primary.opacity(0.22 * emphasis),
                                 Color.primary.opacity(0.07 * emphasis),
                                 Color.primary.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 1))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

extension View {
    func glassSurface(radius: CGFloat = 6, emphasis: Double = 1, grain: Bool = true) -> some View {
        modifier(GlassBackground(radius: radius, emphasis: emphasis, grain: grain))
    }
}
