import PersonaDesign
import SwiftUI

// T3 · the figure: eyebrow · countdown · big-figure · copy chip. Sign-in code
// only, and the exception holds only while it stays alone (R14). The number
// is regex-captured, never model text.

struct GrammarT3Model: Hashable {
    var eyebrow: String
    var countdown: String
    var code: String
}

struct GrammarT3Code: View {
    let model: GrammarT3Model
    /// Seed for the gallery's static land; the plate drives it live otherwise.
    var copied = false

    @State private var isCopied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content.grammarCardPlate()
    }

    /// The drawing WITHOUT its plate — same split as T1 and T2: the live feed
    /// already owns a plate that tints on a reject swipe.
    @ViewBuilder
    var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(model.eyebrow)
                    .font(.system(size: 12, weight: .medium))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(DS.Palette.subtle)
                Spacer(minLength: 0)
                Text(model.countdown)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.placeholder)
            }
            // `.big-figure--code`: a code that IS the card earns 28 with wider
            // tracking, so six digits read as three-and-three.
            Text(model.code)
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .tracking(3)
                .foregroundStyle(DS.Palette.ink)
                .padding(.top, 10)
            copyChip
                .padding(.top, 10)
        }
        // The tap stays on `content`, so the copy affordance survives being
        // embedded in the feed's own plate (body re-adds the plate above).
        .contentShape(Rectangle())
        .onTapGesture { copy() }
    }

    /// Asymmetric on purpose: 0.2s in, 1.8s held, 0.3s out. Arriving should be
    /// quicker than leaving, and the code stays put the whole time so it can
    /// be read back off the card while the paste lands.
    private func copy() {
        guard !isCopied else { return }
        withAnimation(reduceMotion ? nil : GrammarMotion.smooth(0.2)) { isCopied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1800))
            withAnimation(reduceMotion ? nil : GrammarMotion.smooth(0.3)) { isCopied = false }
        }
    }

    private var showsCopied: Bool { copied || isCopied }

    /// The Copy affordance is a chip, not a button: the whole plate is the
    /// copy target, this is a label for what a tap does. Copied inverts to
    /// ink — the task-state green means "the background job finished", and
    /// six characters landing on the clipboard is not that.
    private var copyChip: some View {
        ZStack {
            face(glyph: { GrammarGlyphView(glyph: GlyphCopy.self, size: 12) }, label: "Copy")
                .opacity(showsCopied ? 0 : 1)
                .offset(y: showsCopied ? -5 : 0)
            face(glyph: {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
            }, label: "Copied")
                .opacity(showsCopied ? 1 : 0)
                .offset(y: showsCopied ? 0 : 5)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(showsCopied ? DS.Palette.onInk : DS.TaskState.bubbleText)
        .padding(.horizontal, 11)
        .frame(height: 28)
        .background(showsCopied ? DS.Palette.ink : DS.TaskState.chipFill, in: Capsule())
        // The INK inversion, not the task-state green: green means "the
        // background job finished", and six characters landing on the
        // clipboard is not that.
        .grammarAnimation(GrammarMotion.smooth(0.2), value: showsCopied)
    }

    /// Both faces occupy one cell, so the capsule is as wide as the wider of
    /// them and the box never jumps when the label swaps.
    private func face(@ViewBuilder glyph: () -> some View, label: String) -> some View {
        HStack(spacing: 6) {
            glyph()
            Text(label)
        }
        .fixedSize()
    }
}
