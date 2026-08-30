import SwiftUI

/// Live Low Power Mode state.
///
/// LPM is not "the phone is a bit slower" — two things stack, and both are
/// out of our hands: ProMotion is capped 120Hz → 60Hz (every spring is
/// sampled half as often, so motion visibly steps even with zero dropped
/// frames), and the CPU/GPU clocks are throttled, so every millisecond of
/// per-frame work costs materially more than it does at full clock. Work
/// that comfortably fits the frame budget normally can blow it here.
///
/// What IS ours: not doing full-fat work in the one mode where the user has
/// explicitly asked the phone to conserve. Decorative continuous redraws
/// (shimmers, bouncing dots, marquees), full-screen blurs, and fast polls
/// are the first things that should stand down — see `dsPowerSaving`'s
/// readers. Apple asks apps to adapt here; it is also a battery win.
///
/// Never a substitute for making the normal path fast: this class only
/// decides what to SKIP, never how the app behaves at full power.
@MainActor
@Observable
public final class DSPowerState {
    public static let shared = DSPowerState()

    /// True while the device is in Low Power Mode. Observed, so a view that
    /// reads it re-renders when the user flips the switch mid-session (the
    /// battery hitting 20% is a system prompt away from doing exactly that).
    public private(set) var isLowPower: Bool

    private init() {
        isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        NotificationCenter.default.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { _ in
            // The notification arrives on .main, but the closure isn't
            // MainActor-isolated to the compiler — hop explicitly.
            Task { @MainActor in
                let now = ProcessInfo.processInfo.isLowPowerModeEnabled
                if DSPowerState.shared.isLowPower != now {
                    DSPowerState.shared.isLowPower = now
                }
            }
        }
    }
}

/// True when the app should skip decorative work: Low Power Mode, or the
/// user's Reduce Motion preference where the site already honours it.
///
/// Read this instead of `ProcessInfo` directly — it is injected once at the
/// root (`dsPowerAware()`), so previews and QA rigs can force either state
/// and no view has to observe the notification itself.
private struct DSPowerSavingKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var dsPowerSaving: Bool {
        get { self[DSPowerSavingKey.self] }
        set { self[DSPowerSavingKey.self] = newValue }
    }
}

public extension View {
    /// Injects live Low Power Mode state into the environment. Applied ONCE
    /// at the app root, next to `dsAppearance()`.
    ///
    /// QA/preview override: `PERSONA_FORCE_LOW_POWER=1` forces the saving
    /// path on at full power, so the LPM rendering can be captured headlessly
    /// (a simulator cannot enter real Low Power Mode).
    func dsPowerAware() -> some View {
        modifier(DSPowerAwareModifier())
    }
}

private struct DSPowerAwareModifier: ViewModifier {
    /// Reading the shared box HERE (one small modifier body) keeps the
    /// observation off the app root's own body — the root re-evaluates for
    /// the environment write, not for the observation.
    private var state = DSPowerState.shared

    private static let forced =
        ProcessInfo.processInfo.environment["PERSONA_FORCE_LOW_POWER"] == "1"

    func body(content: Content) -> some View {
        content.environment(\.dsPowerSaving, state.isLowPower || Self.forced)
    }
}

/// Non-SwiftUI reader for the same signal — stores and workers have no
/// environment. Cheap enough to call per loop iteration, so a poll adapts
/// the moment the user flips the switch.
public enum DSPowerSaving {
    public static var isOn: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
            || ProcessInfo.processInfo.environment["PERSONA_FORCE_LOW_POWER"] == "1"
    }
}
