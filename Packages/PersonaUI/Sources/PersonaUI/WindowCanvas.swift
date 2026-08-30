import SwiftUI

/// The app's PHYSICAL canvas, measured through UIKit: the window's height and
/// the hosting view's top edge in window coordinates.
///
/// Why this exists: during SpringBoard's icon-tap launch zoom (iOS 26,
/// observed on 26.3) the hosting view is handed its SAFE-BOUNDS size with
/// ZERO safe-area insets for the first ~second — every SwiftUI-side read
/// (safeAreaInsets, ignoresSafeArea expansion, GeometryReader insets) is wrong
/// until UIKit re-lays-out. Full-bleed layers computed from those reads
/// painted ~47pt low with a white strip above, snapping into place only when
/// the first content change forced a re-layout. The window's bounds and the
/// hosting view's window-space origin are correct THROUGHOUT that anomaly and
/// never change when the insets finally arrive, so layers pinned to this
/// canvas are stable from the very first frame.
public struct WindowCanvas: Equatable {
    /// The hosting view's top edge in window coordinates.
    public var originY: CGFloat
    /// The window's full bounds height (the physical screen for this app).
    public var height: CGFloat
    /// True once a real measurement landed; false = fall back to SwiftUI math.
    public var isMeasured: Bool { height > 0 }

    public init(originY: CGFloat = 0, height: CGFloat = 0) {
        self.originY = originY
        self.height = height
    }
}

public extension EnvironmentValues {
    /// Set by `WindowCanvasReader` near the root; read by full-bleed layers.
    @Entry var windowCanvas = WindowCanvas()
}

#if canImport(UIKit)
/// Invisible measuring view. Attach as a `.background` of a view that spans
/// the root content — CRUCIALLY outside any scaleEffect/transition (transforms
/// leak into coordinate conversion and would pollute the measurement).
public struct WindowCanvasReader: UIViewRepresentable {
    @Binding var canvas: WindowCanvas

    public init(canvas: Binding<WindowCanvas>) {
        _canvas = canvas
    }

    public final class ReaderView: UIView {
        var onChange: ((WindowCanvas) -> Void)?

        override public func didMoveToWindow() {
            super.didMoveToWindow()
            report()
            // The anomaly resolves whenever UIKit gets around to it (~1s in);
            // layout callbacks on this leaf aren't guaranteed to fire for
            // ancestor-only changes, so re-check across the launch window.
            // Cheap no-ops once values are stable.
            for delay in [0.1, 0.3, 0.6, 1.0, 1.6, 2.4] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.report()
                }
            }
        }

        override public func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        /// Launch-window inset bridge (root-canvas normalization Phase 1).
        /// iOS 26 delivers the hosting view's safe-area insets LATE at cold
        /// launch (zero through the icon-tap zoom) while the WINDOW's insets
        /// are correct throughout — the delayed-propagation class Apple is
        /// fielding on iOS 26 (FB20281983). While the root view's INTRINSIC
        /// insets (its report minus this bridge's own contribution — reported
        /// insets INCLUDE additionalSafeAreaInsets, so the raw value can never
        /// signal arrival) are zero and the window's are not, mirror the
        /// window's insets in via additionalSafeAreaInsets; drop the bridge
        /// the moment real propagation lands. Engages only inside a 3s
        /// launch window and no-ops on healthy launches — never worse than
        /// unshimmed.
        private var shimDeadline: CFTimeInterval?

        private func applyLaunchInsetShim() {
            let now = CACurrentMediaTime()
            if shimDeadline == nil { shimDeadline = now + 3.0 }
            guard let window, let rootVC = window.rootViewController else { return }
            let additional = rootVC.additionalSafeAreaInsets
            let reported = rootVC.view.safeAreaInsets
            let intrinsicTop = max(0, reported.top - additional.top)
            let intrinsicBottom = max(0, reported.bottom - additional.bottom)
            let win = window.safeAreaInsets
            if intrinsicTop == 0, intrinsicBottom == 0, win != .zero, now < (shimDeadline ?? 0) {
                // Idempotence gates the layout pass this write triggers —
                // report() re-enters through layoutSubviews and must settle.
                if additional != win { rootVC.additionalSafeAreaInsets = win }
            } else if additional != .zero {
                rootVC.additionalSafeAreaInsets = .zero
            }
        }

        private func report() {
            guard let window else { return }
            applyLaunchInsetShim()
            onChange?(WindowCanvas(
                originY: convert(CGPoint.zero, to: window).y,
                height: window.bounds.height
            ))
        }
    }

    public func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onChange = { new in
            DispatchQueue.main.async {
                if canvas != new { canvas = new }
            }
        }
        return view
    }

    public func updateUIView(_ uiView: ReaderView, context: Context) {}
}
#endif
