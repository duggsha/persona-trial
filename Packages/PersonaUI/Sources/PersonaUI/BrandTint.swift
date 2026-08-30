import PersonaDesign
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// The merchant's brand color, resolved to a small tonal palette so surfaces
/// can wear it at different depths: `deep`/`rich` build the immersive
/// wallet-pass gradient on the pay card, `wash` is the soft pour for light
/// sheets. All derive from ONE extracted hue, so they always harmonize.
struct BrandPalette: Equatable {
    let hue: Double
    let sat: Double
    let bri: Double

    /// Dark anchor of the card gradient (bottom) — rich, near-black brand tone.
    var deep: Color { Color(hue: hue, saturation: min(sat * 1.2, 0.9), brightness: 0.26) }
    /// Lit anchor of the card gradient (top) — the brand color in full voice.
    var rich: Color { Color(hue: hue, saturation: min(sat * 1.05, 0.85), brightness: 0.45) }
    /// Soft tint for light surfaces (the confirm sheet's top pour).
    var wash: Color { Color(hue: hue, saturation: min(sat, 0.72), brightness: min(max(bri, 0.42), 0.82)) }
}

/// Extracts a brand color from a merchant logo / product photo so payment
/// surfaces can wear the merchant's identity (Starbucks → green) instead of a
/// generic gray. The heavy lifting happens once per URL: the image is
/// downsampled to a few hundred pixels, every pixel votes for its hue bucket
/// weighted by how "brand-like" it is (saturated, mid-brightness — whites,
/// blacks and grays don't vote), and the winning bucket's weighted mean color
/// is cached. Falls back to nil (callers render their neutral look) for
/// monochrome logos or load failures.
enum BrandTint {
    /// URL string → resolved palette (nil = tried, nothing usable). Main-actor
    /// mutable state; lookups and stores happen on the main actor.
    @MainActor private static var cache: [String: BrandPalette?] = [:]

    /// The dominant saturated color of the image at `urlString`, as a tonal
    /// palette. Reuses the chat thumbnail's decoded-image cache when the card
    /// already loaded the picture, so a card + its tint cost one download.
    @MainActor
    static func palette(fromImageAt urlString: String?) async -> BrandPalette? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        if let hit = cache[urlString] { return hit }
        #if canImport(UIKit)
            var ui = AvatarImageCache.shared.image(for: "thumb:\(urlString)")
            if ui == nil, let (data, _) = try? await URLSession.shared.data(from: url) {
                ui = UIImage(data: data)
            }
            let palette = ui.flatMap { extract(from: $0) }
            cache[urlString] = palette
            return palette
        #else
            return nil
        #endif
    }

    /// Back-compat single tone (the sheet's soft pour).
    @MainActor
    static func dominant(fromImageAt urlString: String?) async -> Color? {
        await palette(fromImageAt: urlString)?.wash
    }

    #if canImport(UIKit)
        /// Downsample + hue-bucket vote. 24 hue buckets; each pixel's weight is
        /// saturation² scaled by a mid-brightness window, so the white cup on a
        /// green logo contributes nothing and the green ring decides.
        ///
        /// The image is redrawn into an OWN RGBA8888 big-endian context — reading
        /// the platform renderer's backing store directly is a byte-order trap
        /// (iOS renders BGRA little-endian, which silently swaps channels).
        private static func extract(from image: UIImage) -> BrandPalette? {
            let side = 24
            guard let src = image.cgImage else { return nil }
            guard
                let ctx = CGContext(
                    data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
                )
            else { return nil }
            ctx.interpolationQuality = .low
            ctx.draw(src, in: CGRect(x: 0, y: 0, width: side, height: side))
            guard let base = ctx.data else { return nil }
            let data = base.assumingMemoryBound(to: UInt8.self)

            let buckets = 24
            var weight = [Double](repeating: 0, count: buckets)
            var sumH = [Double](repeating: 0, count: buckets)
            var sumS = [Double](repeating: 0, count: buckets)
            var sumB = [Double](repeating: 0, count: buckets)

            for py in 0..<side {
                for px in 0..<side {
                    let i = (py * side + px) * 4
                    // premultipliedLast + byteOrder32Big = R,G,B,A in memory.
                    let a = Double(data[i + 3]) / 255
                    guard a > 0.5 else { continue }
                    let r = Double(data[i]) / 255 / max(a, 0.01)
                    let g = Double(data[i + 1]) / 255 / max(a, 0.01)
                    let b = Double(data[i + 2]) / 255 / max(a, 0.01)

                    let (h, s, v) = hsb(r: r, g: g, b: b)
                    // Brand-likeness: needs real saturation and mid brightness.
                    let w = s * s * max(0, 1 - abs(v - 0.55) * 1.8) * a
                    guard w > 0.02 else { continue }
                    let bucket = min(buckets - 1, Int(h * Double(buckets)))
                    weight[bucket] += w
                    sumH[bucket] += h * w
                    sumS[bucket] += s * w
                    sumB[bucket] += v * w
                }
            }

            guard let top = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[top] > 0.5 else { return nil }
            return BrandPalette(
                hue: sumH[top] / weight[top],
                sat: sumS[top] / weight[top],
                bri: sumB[top] / weight[top]
            )
        }

        private static func hsb(r: Double, g: Double, b: Double) -> (h: Double, s: Double, v: Double) {
            let mx = max(r, g, b), mn = min(r, g, b)
            let d = mx - mn
            var h = 0.0
            if d > 0 {
                switch mx {
                case r: h = ((g - b) / d).truncatingRemainder(dividingBy: 6)
                case g: h = (b - r) / d + 2
                default: h = (r - g) / d + 4
                }
                h /= 6
                if h < 0 { h += 1 }
            }
            return (h, mx == 0 ? 0 : d / mx, mx)
        }
    #endif
}
