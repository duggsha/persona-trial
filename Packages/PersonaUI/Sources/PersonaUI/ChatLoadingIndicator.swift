import PersonaCore
import PersonaDesign
import SwiftUI

/// The chat's single "turn in flight" signal: the Persona mark with a light
/// band sweeping through it, and the wave handing off into the status phrase
/// as an ink shimmer — motion IS the loading state, no spinner, no card. The
/// phrase is "Thinking" until a tool status arrives ("Looking that up…");
/// label changes cross-fade in place, like the task thread's step label.
struct ChatLoadingIndicator: View {
    /// What Iris is doing right now ("Thinking", "Searching your mail…").
    let label: String
    /// Optional tool identity behind the phrase — renders the tool's icon
    /// (brand mark or domain symbol) between the Persona mark and the shimmer,
    /// so "Searching your mail…" carries the Gmail mark. Nil = phrase only.
    var icon: LiveToolStatus? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One pass-then-beat cycle: the band crosses the mark over the first 62%,
    /// the phrase shimmer picks the wave up as it leaves the mark (30%–78%),
    /// then both rest until the next cycle.
    private static let cycle: TimeInterval = 1.9
    private static let markWidth: CGFloat = 30
    private static let markHeight: CGFloat = 26
    /// Resting glyph gray — the warm gray of the reference spec, sitting in the
    /// cream background's family (the DS neutrals are cooler and read heavier
    /// at this size).
    private static let rest = Color(hex: 0xB9B9B3)

    var body: some View {
        // NOT gated on Low Power Mode: the sweep is the
        // product's "working" signal — motion IS the loading state — and a
        // 30fps leaf-text redraw is pennies next to the real LPM standdowns
        // (full-surface masks, live materials, the reply blur). LPM saving
        // must never cost the personality.
        Group {
            if reduceMotion {
                HStack(spacing: 10) {
                    leadingGlyph(progress: nil)
                    phrase(sweep: nil)
                }
            } else {
                // 30fps is plenty for a 1.9s sweep and halves the main-thread
                // redraws (same cadence rationale as the old typing dots). The
                // positions derive from `context.date`, so the motion is
                // frame-rate independent, and TimelineView owns no state — it
                // stops the instant the row is removed.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let progress = (context.date.timeIntervalSinceReferenceDate / Self.cycle)
                        .truncatingRemainder(dividingBy: 1)
                    HStack(spacing: 10) {
                        leadingGlyph(progress: progress)
                        phrase(sweep: Self.easeInOut((progress - 0.30) / 0.48))
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.28), value: label)
        .animation(.easeOut(duration: 0.28), value: icon)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// The single leading glyph: the sweeping Persona mark.
    ///
    /// In the real app a running tool swaps its own badge in here instead —
    /// never both, since two glyphs side by side read as clutter. That badge
    /// carries a table of bundled brand assets and a remote logo fallback,
    /// neither of which this trial ships, and no tool ever runs against seeded
    /// messages, so the mark is the only arm left.
    @ViewBuilder
    private func leadingGlyph(progress: Double?) -> some View {
        if let progress {
            // No real identity for this tool → the sweeping mark stays as the
            // generic "working" signal; the phrase still names the activity.
            sweepingMark(progress)
        } else {
            // Static (reduce-motion / Low Power) arm. The frame is NOT
            // optional: `mark` is resizable, and `sweepingMark` carries the
            // 30×26 frame on the animated path only — without one here the
            // glyph inflates to fill the transcript width (design screenshot, — a half-screen Persona mark in LPM; latent in the
            // reduce-motion branch since it shipped, surfaced the moment LPM
            // routed through it).
            mark.opacity(0.9)
                .frame(width: Self.markWidth, height: Self.markHeight)
        }
    }

    /// The mark resting near-invisible, lit by a passing band: the band mask
    /// reveals the full-ink mark, so the internal cutout detail survives (a
    /// template tint would flatten the glyph to a blob).
    private func sweepingMark(_ progress: Double) -> some View {
        // Band center sweeps just-left-of to just-right-of the mark, relative
        // to its center: -1.0×W … +0.8×W.
        let offset = Self.markWidth * (-1.0 + 1.8 * Self.easeInOut(progress / 0.62))
        return ZStack {
            mark.opacity(0.16)
            mark.mask {
                // Focused core inside a soft halo, like the reference band.
                ZStack {
                    bandGradient.frame(width: Self.markWidth * 0.9).opacity(0.28)
                    bandGradient.frame(width: Self.markWidth * 0.38)
                }
                .offset(x: offset)
            }
        }
        .frame(width: Self.markWidth, height: Self.markHeight)
    }

    private var mark: some View {
        PersonaAsset.image("PersonaMark")
            .resizable()
            .scaledToFit()
    }

    private var bandGradient: LinearGradient {
        LinearGradient(colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing)
    }

    /// The status phrase: resting gray with an ink band sweeping across the
    /// glyphs (nil sweep = static, for reduced motion). A label change swaps
    /// with a small fade + rise, animated by the container's `.animation`.
    private func phrase(sweep: CGFloat?) -> some View {
        ZStack(alignment: .leading) {
            phraseText(label)
                .foregroundStyle(sweep == nil ? DS.Palette.inkMuted : Self.rest)
                .overlay {
                    if let sweep {
                        GeometryReader { geo in
                            let band = max(geo.size.width * 0.55, 28)
                            LinearGradient(
                                colors: [.clear, DS.Palette.ink, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: band)
                            .offset(x: geo.size.width * (-0.5 + 1.8 * sweep) - band / 2)
                        }
                        .mask { phraseText(label) }
                        .allowsHitTesting(false)
                    }
                }
                .id(label)
                .transition(.opacity.combined(with: .offset(y: 4)))
        }
    }

    private func phraseText(_ string: String) -> Text {
        Text(string)
            .font(.system(size: 14, weight: .medium))
            .tracking(-0.14)
    }

    /// Cubic ease-in-out over 0…1 (clamped) — accelerates through the middle
    /// and settles, close to the reference's cubic-bezier(.65,.05,.35,.95).
    private static func easeInOut(_ x: Double) -> CGFloat {
        let t = min(max(x, 0), 1)
        return CGFloat(t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2)
    }
}
