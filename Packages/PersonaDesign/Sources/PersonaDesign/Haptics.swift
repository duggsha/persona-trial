import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// Gates rapid-fire taps so a single interaction doesn't double-fire haptics
/// (e.g. a tap that also opens a sheet). Mirrors Persona's interaction gate.
@MainActor
public enum DSInteractionGate {
    private static var suppressTapUntil: TimeInterval = 0

    public static var allowsTap: Bool {
        CACurrentMediaTime() >= suppressTapUntil
    }

    public static func suppressTaps(for duration: TimeInterval = 0.36) {
        suppressTapUntil = max(suppressTapUntil, CACurrentMediaTime() + duration)
    }
}

/// A plain button that adds a light haptic + a subtle press scale, so every
/// primary tap feels tactile and native. Use `.buttonStyle(.hapticTap)`.
public struct HapticButtonStyle: ButtonStyle {
    /// When false, only the haptic fires — no press scale/dim. For rows that
    /// also carry a native context menu: the system's lift animation is the
    /// press feedback there, and a custom scale fights it (lift + shrink +
    /// re-expand stutter).
    let pressEffect: Bool

    public init(pressEffect: Bool = true) {
        self.pressEffect = pressEffect
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(pressEffect && configuration.isPressed ? 0.97 : 1)
            .opacity(pressEffect && configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { DSHaptics.tap(.light) }
            }
    }
}

public extension ButtonStyle where Self == HapticButtonStyle {
    /// Plain look + light haptic + subtle press scale.
    static var hapticTap: HapticButtonStyle { HapticButtonStyle() }
    /// Light haptic only — no press scale/dim. Use on rows with a native
    /// context menu so the system lift is the sole press animation.
    static var hapticTapNoPress: HapticButtonStyle { HapticButtonStyle(pressEffect: false) }
}

/// Haptic feedback, routed through the design system so feature code doesn't
/// reach UIKit directly. Patterns mirror Persona's `PersonaHaptics`.
public enum DSHaptics {
    #if canImport(UIKit)
        /// One long-lived generator per style. A generator created cold right
        /// before `impactOccurred` routinely DROPS the transient — the Taptic
        /// Engine needs a beat to spin up, and `prepare()` immediately before
        /// the impact doesn't buy it one (the long-press menu's pop was lost
        /// this way on infrequent taps). Kept generators + an explicit
        /// `prepareTap` at a gesture's touch-down make the pop land reliably.
        @MainActor private static var impactGenerators: [Style: UIImpactFeedbackGenerator] = [:]

        @MainActor private static func impactGenerator(for style: Style) -> UIImpactFeedbackGenerator {
            if let generator = impactGenerators[style] { return generator }
            let generator = UIImpactFeedbackGenerator(style: style.uiStyle)
            impactGenerators[style] = generator
            return generator
        }

        /// Kept for the same cold-engine reason as the impact generators.
        @MainActor private static let notificationGenerator = UINotificationFeedbackGenerator()
    #endif

    /// Spin the Taptic Engine up ahead of a knowable upcoming `tap` — e.g. at
    /// a long-press's touch-down, so the pop at recognition isn't dropped by
    /// a cold engine. Harmless when the tap never comes.
    @MainActor
    public static func prepareTap(_ style: Style = .light) {
        #if canImport(UIKit)
            impactGenerator(for: style).prepare()
        #endif
    }

    @discardableResult
    @MainActor
    public static func tap(_ style: Style = .light) -> Bool {
        guard DSInteractionGate.allowsTap else { return false }
        #if canImport(UIKit)
            let generator = impactGenerator(for: style)
            generator.impactOccurred(intensity: 1)
            // Keep the engine warm for a quick follow-up tap.
            generator.prepare()
        #endif
        return true
    }

    /// A swipe-gesture threshold cue (card reject/snooze crossing the commit
    /// line). Deliberately ungated, same rationale as `pageSettle` below: the
    /// swipe holds `suppressTaps` for its whole drag, which would swallow a
    /// gated tap exactly at the crossing. Kept generators — the callers'
    /// former per-call cold generator + prepare() is the documented
    /// dropped-transient recipe (see `impactGenerators`), and constructing
    /// one mid-drag is main-thread work at the worst possible moment.
    @MainActor
    public static func swipeThreshold(_ style: Style, intensity: CGFloat = 1) {
        #if canImport(UIKit)
            let generator = impactGenerator(for: style)
            generator.impactOccurred(intensity: intensity)
            generator.prepare()
        #endif
    }

    /// A page-level navigation settle (root pager, iris menu). Deliberately
    /// bypasses the interaction gate: the page swipe that lands here holds
    /// `suppressTaps` for its whole drag (so controls under the finger don't
    /// fire on release), and a gated tap would be swallowed by exactly that
    /// suppression at the moment the page commits.
    @MainActor
    public static func pageSettle(_ style: Style = .light) {
        #if canImport(UIKit)
            let generator = impactGenerator(for: style)
            generator.impactOccurred(intensity: 1)
            generator.prepare()
        #endif
    }

    @MainActor
    public static func selection() {
        guard DSInteractionGate.allowsTap else { return }
        #if canImport(UIKit)
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            generator.selectionChanged()
        #endif
    }

    /// An incoming message landing — iMessage's received-text feel: the
    /// system "success" double tap (soft then firm), a clearly bigger moment
    /// than a single light impact.
    @MainActor
    public static func messageReceived() {
        guard DSInteractionGate.allowsTap else { return }
        #if canImport(UIKit)
            notificationGenerator.notificationOccurred(.success)
            // Keep the engine warm for the next arrival.
            notificationGenerator.prepare()
        #endif
    }

    @MainActor
    public static func composerTap() {
        tap(.light)
    }

    /// Entering listening mode — a firm, unmistakable cue.
    @MainActor
    public static func composerListeningStart() {
        tap(.heavy)
    }

    /// Switching between send / delete release modes — a two-stage tick.
    @MainActor
    public static func composerModeChange() {
        selection()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.018) {
            tap(.medium)
        }
    }

    /// Releasing into the delete zone — a warning notification.
    @MainActor
    public static func composerDeleteRelease() {
        guard DSInteractionGate.allowsTap else { return }
        #if canImport(UIKit)
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.warning)
        #endif
    }

    public enum Style: Hashable {
        case light
        case medium
        case heavy
        case rigid

        #if canImport(UIKit)
            var uiStyle: UIImpactFeedbackGenerator.FeedbackStyle {
                switch self {
                case .light: .light
                case .medium: .medium
                case .heavy: .heavy
                case .rigid: .rigid
                }
            }
        #endif
    }
}
