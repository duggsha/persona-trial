import Foundation

/// Local user preferences shared across modules — the single source of truth for
/// their UserDefaults keys, so the Settings toggles (PersonaUI @AppStorage) and the
/// code that honours them (PersonaService) never drift on a magic string.
public enum AppPreferences {
    /// "Travel-aware answers": when off, the app must not report the device
    /// location to the backend. Defaults to ON when the user has never set it.
    public static let travelAwareKey = "prefs.travelAware"

    public static var travelAware: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: travelAwareKey) == nil ? true : defaults.bool(forKey: travelAwareKey)
    }

    /// Ambient listening (band all-day capture). Device-local capture intent —
    /// the server keeps its own enforced mirror in user_settings; this is what
    /// lets capture resume on relaunch before any network round-trip. Defaults
    /// to OFF: recording everything is opt-in, never a surprise.
    public static let ambientListeningKey = "prefs.ambientListening"

    public static var ambientListening: Bool {
        get { UserDefaults.standard.bool(forKey: ambientListeningKey) }
        set { UserDefaults.standard.set(newValue, forKey: ambientListeningKey) }
    }

    /// iOS shows the native "Change to Always Allow?" upgrade dialog exactly ONCE
    /// per install; every later requestAlwaysAuthorization is silently ignored.
    /// This remembers that we've spent that one shot (there is no API to ask the
    /// system), so the UI can route straight to Settings instead of a dead call.
    public static let alwaysUpgradeSpentKey = "prefs.location.alwaysUpgradeSpent"

    public static var alwaysUpgradeSpent: Bool {
        get { UserDefaults.standard.bool(forKey: alwaysUpgradeSpentKey) }
        set { UserDefaults.standard.set(newValue, forKey: alwaysUpgradeSpentKey) }
    }
}
