import Foundation

/// When the app may sync the address book on its OWN — no tap, no permission
/// prompt. Kept pure and here (not next to the CNContactStore glue) so the
/// rules can be tested; the caller supplies the state and applies the verdict.
///
/// The rule that motivated this: a snapshot upload that failed used to be a
/// dead end. The old `resyncIfStale` ran only for devices that had already
/// synced successfully once, so the users whose FIRST sync failed were exactly
/// the ones it would never retry — they had to notice the People banner and
/// tap it again, with no error ever shown explaining why the first tap did
/// nothing at all.
public enum ContactsSyncSchedule {
    public enum Decision: Equatable, Sendable {
        /// Leave it alone.
        case skip
        /// Mirror is stale — re-upload so the backend sees today's book.
        case refreshStale
        /// A sync the user asked for never landed. Try it again, silently.
        case retryFailed
    }

    /// Everything the decision depends on, so it depends on nothing else.
    public struct State: Equatable, Sendable {
        /// Contacts access is already `.full`/`.limited`. False here always
        /// means skip: an automatic path must never trigger the OS prompt.
        public var accessGranted: Bool
        /// A snapshot upload has succeeded at least once on this device.
        public var hasSyncedLocally: Bool
        public var lastSyncedAt: Date?
        /// The last user-initiated sync ended without a stored snapshot.
        public var lastAttemptFailed: Bool
        public var lastAttemptAt: Date?
        /// App build of that last attempt, and the build running now.
        public var lastAttemptBuild: String?
        public var currentBuild: String
        /// When this device last asked the server whether it needs repairing,
        /// and on which build — the throttle for `shouldAskServer`.
        public var lastServerCheckAt: Date?
        public var lastServerCheckBuild: String?

        public init(
            accessGranted: Bool,
            hasSyncedLocally: Bool,
            lastSyncedAt: Date?,
            lastAttemptFailed: Bool,
            lastAttemptAt: Date?,
            lastAttemptBuild: String?,
            currentBuild: String,
            lastServerCheckAt: Date? = nil,
            lastServerCheckBuild: String? = nil
        ) {
            self.accessGranted = accessGranted
            self.hasSyncedLocally = hasSyncedLocally
            self.lastSyncedAt = lastSyncedAt
            self.lastAttemptFailed = lastAttemptFailed
            self.lastAttemptAt = lastAttemptAt
            self.lastAttemptBuild = lastAttemptBuild
            self.currentBuild = currentBuild
            self.lastServerCheckAt = lastServerCheckAt
            self.lastServerCheckBuild = lastServerCheckBuild
        }
    }

    /// A synced mirror still goes stale — people change numbers.
    public static let refreshInterval: TimeInterval = 24 * 60 * 60
    /// How often a failed sync is retried on an UNCHANGED build. Long on
    /// purpose: a book can be several MB, and whatever broke it is unlikely to
    /// heal within the hour.
    public static let retryInterval: TimeInterval = 6 * 60 * 60

    /// Whether it is worth ASKING the server if this device needs repairing.
    /// The device's own record cannot cover a failure that predates it — an
    /// older build, a reinstall, a restored backup — and that is exactly the
    /// population sitting at zero contacts with a banner they have no reason to
    /// tap. Kept rare on purpose: only devices with a granted grant, no
    /// successful sync and nothing already known to be broken, and then only
    /// once per build or per retry window.
    public static func shouldAskServer(_ state: State, now: Date = Date()) -> Bool {
        guard state.accessGranted, !state.hasSyncedLocally, !state.lastAttemptFailed else { return false }
        if state.lastServerCheckBuild != state.currentBuild { return true }
        guard let last = state.lastServerCheckAt else { return true }
        return now.timeIntervalSince(last) >= retryInterval
    }

    public static func decide(_ state: State, now: Date = Date()) -> Decision {
        guard state.accessGranted else { return .skip }

        if state.hasSyncedLocally {
            guard let last = state.lastSyncedAt else { return .refreshStale }
            return now.timeIntervalSince(last) >= refreshInterval ? .refreshStale : .skip
        }

        // Nothing has ever landed. Repair ONLY what the user started: contacts
        // access can also be granted by the assistant-contact-card writer, and
        // uploading a whole address book off the back of that grant would be an
        // upload nobody asked for. A recorded failed attempt is the consent.
        guard state.lastAttemptFailed else { return .skip }

        // The point of the whole path: when the release that fixes the cause
        // lands, every stuck device gets one clean attempt immediately instead
        // of waiting out the retry window. A build only changes on update, so
        // this can't loop.
        if state.lastAttemptBuild != state.currentBuild { return .retryFailed }

        guard let last = state.lastAttemptAt else { return .retryFailed }
        return now.timeIntervalSince(last) >= retryInterval ? .retryFailed : .skip
    }
}
