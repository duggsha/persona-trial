#if canImport(UIKit)
    import UIKit
#endif
import SwiftUI

// Makes the light/dark flip readable instead of instantaneous.
//
// `.preferredColorScheme` repaints every colour in ONE frame. There is no
// animatable value in that path — no view downstream can smooth it, because by
// the time anything downstream re-evaluates, the trait has already changed. So
// the transition has to happen at the WINDOW: freeze the old look as a
// snapshot, let the new theme paint underneath it, then take the snapshot
// away — as a circle opening from whatever the user touched, or as a dissolve
// when the change came from somewhere with no on-screen origin (the assistant
// flipping it mid-reply, or the launch reconcile).
//
// This hangs off `dsAppearance()`, the one modifier that APPLIES the
// preference, so every writer inherits it: the Settings screen, the in-chat
// appearance card, and the streamed assistant change alike — none of them has
// to know the transition exists.

@MainActor
public enum DSAppearanceTransition {
    /// Where the next wipe should open from, in GLOBAL (window) coordinates.
    /// Set by the control that is about to change the appearance; CONSUMED by
    /// the next flip, so a stale anchor can never misdirect an unrelated one —
    /// a flip with no anchor dissolves instead, which is the honest rendering
    /// of "this did not come from a thing you touched".
    public static var anchor: CGPoint?

    /// One transition per flip. `dsAppearance()` is applied at the root AND at
    /// several sheets, so a single change notifies N modifiers in the same
    /// frame; without this they would each stack their own snapshot.
    private static var inFlight = false

    private static let wipeDuration: CFTimeInterval = 0.45
    private static let fadeDuration: TimeInterval = 0.28

    /// Run the transition for a flip that just happened. `motionAllowed` is
    /// false under Reduce Motion or Low Power, where the geometry is dropped
    /// but the dissolve stays — the point is to avoid a jarring snap, and a
    /// cross-fade carries no motion to be sensitive to.
    static func run(motionAllowed: Bool) {
        #if canImport(UIKit)
            guard !inFlight, let window = activeWindow else { return }
            // afterScreenUpdates: false = the pixels ALREADY on screen, i.e.
            // the OLD theme. SwiftUI has updated its state by now but the
            // render has not been committed, so this catches the last frame of
            // the outgoing look. Passing true here would capture the NEW theme
            // and animate one identical image over another — nothing visible,
            // and a wasted render pass.
            guard let frozen = window.snapshotView(afterScreenUpdates: false) else { return }
            inFlight = true
            frozen.frame = window.bounds
            frozen.isUserInteractionEnabled = false
            window.addSubview(frozen)

            let origin = takeAnchor()
            guard motionAllowed, let origin else {
                UIView.animate(withDuration: fadeDuration, delay: 0, options: [.curveEaseInOut]) {
                    frozen.alpha = 0
                } completion: { _ in
                    frozen.removeFromSuperview()
                    inFlight = false
                }
                return
            }
            wipe(frozen, from: origin, in: window.bounds)
        #endif
    }

    /// Consume the pending anchor — one flip, one use.
    private static func takeAnchor() -> CGPoint? {
        defer { anchor = nil }
        return anchor
    }

    #if canImport(UIKit)
        /// The frozen OLD look is erased through a growing circular hole, so
        /// the new theme appears to spread from the control that caused it.
        private static func wipe(_ frozen: UIView, from origin: CGPoint, in bounds: CGRect) {
            let mask = CAShapeLayer()
            mask.frame = bounds
            // Even-odd: the full-bounds rect fills, and the circle inside it
            // punches a HOLE. A mask hides what it does not cover, so the hole
            // is exactly the window of new theme — and growing it sweeps the
            // old look off the screen.
            mask.fillRule = .evenOdd
            let start = holePath(in: bounds, at: origin, radius: 0)
            let end = holePath(in: bounds, at: origin, radius: maxRadius(from: origin, in: bounds))
            mask.path = end // settle on the finished state; the animation plays into it
            frozen.layer.mask = mask

            let grow = CABasicAnimation(keyPath: "path")
            grow.fromValue = start
            grow.toValue = end
            grow.duration = wipeDuration
            grow.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            CATransaction.begin()
            CATransaction.setCompletionBlock {
                frozen.removeFromSuperview()
                inFlight = false
            }
            // The snapshot stays fully OPAQUE and is removed only by the mask.
            // Fading it as well double-exposes the two themes across the whole
            // screen — every element ghosts over its own new-theme copy, which
            // reads as a smear rather than a sweep. The hard mask edge is what
            // makes it look like one surface passing over another.
            mask.add(grow, forKey: "dsAppearanceWipe")
            CATransaction.commit()
        }

        /// Full-bounds rect + a circle at `origin`. Both paths in the animation
        /// share this structure (rect then arc) so Core Animation interpolates
        /// them point-for-point; paths built differently would pop instead.
        private static func holePath(in bounds: CGRect, at origin: CGPoint, radius: CGFloat) -> CGPath {
            let path = UIBezierPath(rect: bounds)
            path.append(UIBezierPath(
                arcCenter: origin, radius: max(radius, 0.01),
                startAngle: 0, endAngle: .pi * 2, clockwise: true
            ))
            path.usesEvenOddFillRule = true
            return path.cgPath
        }

        /// Far enough to clear the corner furthest from the origin — a wipe
        /// that stops short would strand a sliver of the old theme.
        private static func maxRadius(from origin: CGPoint, in bounds: CGRect) -> CGFloat {
            let corners = [
                CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
                CGPoint(x: bounds.minX, y: bounds.maxY), CGPoint(x: bounds.maxX, y: bounds.maxY)
            ]
            return corners.reduce(0) { furthest, corner in
                max(furthest, hypot(corner.x - origin.x, corner.y - origin.y))
            }
        }

        private static var activeWindow: UIWindow? {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }?
                .keyWindow
        }
    #endif
}

public extension View {
    /// Record this control as the origin of the appearance flip it is about to
    /// make — the theme then wipes outward from its centre. Pair it with the
    /// tap that writes the preference; without it the flip dissolves instead,
    /// which is what a change the user did not touch should look like.
    func dsAppearanceOrigin(_ store: Binding<CGPoint?>) -> some View {
        onGeometryChange(for: CGPoint.self) { proxy in
            let frame = proxy.frame(in: .global)
            return CGPoint(x: frame.midX, y: frame.midY)
        } action: { centre in
            store.wrappedValue = centre
        }
    }
}
