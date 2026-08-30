import PersonaDesign
import SwiftUI

/// A deferred action riding a toast: `commit` runs when the toast lapses (or
/// is swipe-dismissed early); tapping runs `restore` instead. Extracted from
/// HomeScreen so the compose preview rig can drive the same send-undo flow.
struct UndoToastState: Identifiable {
    let id = UUID()
    let message: String
    let restore: () -> Void
    let commit: () async -> Void
    /// A plain confirmation (e.g. "Code copied") drops the "Undo?" affordance.
    var showsUndo = true
    /// The tap verb — "Undo?" for deferred actions, "Edit?" for a failed
    /// send whose tap reopens the draft.
    var actionLabel = "Undo?"

    /// Design parity: a slightly wider capsule once the copy passes ~16 chars.
    var toastWidth: CGFloat { message.count > 16 ? 208 : 184 }
}

/// The "<message> · Undo?" capsule (ported value-for-value from the design's
/// `PersonaUndoToast`): the whole capsule is one Undo button. Swiping it DOWN
/// dismisses it early — "I don't need the undo" — which commits the pending
/// action immediately (same outcome as letting the toast lapse, just sooner).
struct UndoToast: View {
    let message: String
    var showsUndo = true
    var actionLabel = "Undo?"
    let onUndo: () -> Void
    /// Early dismissal (the downward swipe). Commits the deferred action.
    var onDismiss: () -> Void = {}

    /// Live drag: the capsule follows the finger downward (rubber-banded
    /// upward), and past the threshold it's flung off.
    @State private var dragOffset: CGFloat = 0

    // NOT a Button: a Button claims the touch, so the drag never tracks and a
    // released swipe still fires the tap. One DragGesture(minimumDistance: 0)
    // owns the whole interaction — the capsule follows the finger from the
    // first point, and RELEASE decides what the touch was: barely moved = the
    // Undo tap; flung/moved down = early dismiss (commit now); anything else
    // springs back and does nothing.
    var body: some View {
        HStack(spacing: 7) {
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .tracking(-0.13)
                .foregroundStyle(DS.Palette.ink.opacity(0.82))
            if showsUndo {
                Text(actionLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.13)
                    .foregroundStyle(Color(light: 0x097FFF, dark: 0x409CFF))
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 9)
        .frame(height: 42)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Capsule(style: .continuous))
        .background(DS.Palette.card.opacity(0.82), in: Capsule(style: .continuous))
        .personaGlass(in: Capsule(style: .continuous), interactive: true)
        .shadow(color: Color(hex: 0x1E1A24).opacity(0.12), radius: 14, x: 0, y: 7)
        .offset(y: dragOffset)
        .opacity(dragOffset > 0 ? max(0.25, 1 - dragOffset / 90) : 1)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // Downward follows the finger 1:1; upward rubber-bands.
                    let dy = value.translation.height
                    dragOffset = dy > 0 ? dy : dy / 6
                }
                .onEnded { value in
                    let dy = value.translation.height
                    let moved = max(abs(value.translation.width), abs(dy))
                    if moved < 10 {
                        // A genuine tap → Undo.
                        withAnimation(.smooth(duration: 0.2, extraBounce: 0)) { dragOffset = 0 }
                        DSHaptics.tap(.light)
                        onUndo()
                    } else if dy > 28 || value.predictedEndTranslation.height > 80 {
                        // A real downward swipe/fling → dismiss early, commit now.
                        DSHaptics.tap(.light)
                        withAnimation(.smooth(duration: 0.2, extraBounce: 0)) { dragOffset = 120 }
                        onDismiss()
                    } else {
                        // Wandered but committed to nothing → spring back, no tap.
                        withAnimation(.smooth(duration: 0.24, extraBounce: 0)) { dragOffset = 0 }
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(showsUndo ? "\(message) \(actionLabel)" : message)
        .accessibilityHint(showsUndo ? "Double-tap to \(actionLabel.lowercased().replacingOccurrences(of: "?", with: "")). Swipe down to dismiss." : "")
    }
}
