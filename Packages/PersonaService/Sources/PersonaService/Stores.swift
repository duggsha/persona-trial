import Foundation
import Observation
import PersonaCore

/// The user and their assistant's identity, as the header draws it.
///
/// The real store loads `/v1/profile`, harvests an avatar during onboarding and
/// caches both. This one is told who it is at launch.
@MainActor
@Observable
public final class ProfileStore {
    public init() {}

    /// What the user renamed their assistant to. The header's wordmark.
    public private(set) var assistantName = ProfileStore.defaultAssistantName
    /// The user's profile photo. Always nil here — there is nothing to download
    /// it from, and the header falls back to its glyph exactly as it does on a
    /// fresh install.
    public private(set) var avatarUrl: String?
    public private(set) var name: String?

    public static let defaultAssistantName = "Persona"

    public var initial: String? {
        guard let first = name?.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
        return String(first).uppercased()
    }

    public func seedForDesignTrial(name: String, assistantName: String) {
        self.name = name
        self.assistantName = assistantName
        avatarUrl = nil
    }
}

/// The app's settings and the service handles hanging off them.
///
/// In the real app this owns connected accounts, preferences, memory import and
/// the mail compose client. Here it is a holder for three inert handles that
/// card and composer code still reaches for.
@MainActor
@Observable
public final class SettingsStore {
    public init() {}

    public let apiClient = APIClient()
    public let compose = ComposeService()
    public let connect = ConnectService()
}

/// Background agent work.
///
/// The real store polls running tasks and relays the user's answers. Nothing
/// runs in this build, so the list is permanently empty and every command is a
/// no-op — which is what makes the composer's task tray correctly absent.
@MainActor
@Observable
public final class DeepTaskStore {
    public init() {}

    public private(set) var tasks: [DeepTask] = []
    public var activeTaskID: String?
    /// A card asked the task thread to open with its composer focused. Read by
    /// the thread view, which this trial doesn't include.
    public private(set) var composerFocusRequested = false

    public var activeTask: DeepTask? { nil }

    public func refresh() async {}
    public func refreshTask(_ id: String) async {}
    public func requestComposerFocus() { composerFocusRequested = true }

    /// The real store optimistically inserts a placeholder the moment a task is
    /// kicked off, so the tray fills before the server answers. There is no
    /// server, so the id it hands back is never claimed.
    public func notePendingStart(goal: String) -> String { UUID().uuidString }
    public func cancelPendingStart(_ localId: String) {}

    public func markStoppedLocally(_ id: String) -> DeepTask? { nil }
    public func pause(_ id: String) async {}
    public func resume(_ id: String) async {}
    public func retry(_ id: String) async {}

    public func respond(
        _ id: String,
        answer: String,
        voice: VoiceMeta? = nil,
        replyTo: ReplyMeta? = nil,
        attachments: Attachments? = nil
    ) async -> Error? {
        APIError.noBackend
    }

    /// Shapes the answer call took. Kept so call sites compile; never read.
    public struct VoiceMeta: Sendable {
        public init() {}
    }

    public struct ReplyMeta: Sendable {
        public init() {}
    }

    public struct Attachments: Sendable {
        public var images: [Data]
        public var file: ChatFileAttachment?
        public init(images: [Data] = [], file: ChatFileAttachment? = nil) {
            self.images = images
            self.file = file
        }
    }
}
