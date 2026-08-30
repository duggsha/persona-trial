import Foundation
import Observation
import PersonaCore

/// Everything the Home screen reads, held in memory.
///
/// The real `HomeStore` fetches the feed, the greeting, the location and the
/// task list, long-polls while work is running, and writes every user action
/// back to the server. This one is seeded once by the app at launch and then
/// only ever mutates locally: a dismissed card leaves the array, a read update
/// joins a set. Every method that would have called the backend is present with
/// its original signature so the views compile unchanged, and does the local
/// half of its job — or nothing, where the job was entirely remote.
@MainActor
@Observable
public final class HomeStore {
    public init() {}

    // MARK: - The feed

    public private(set) var suggestions: [Suggestion] = []
    public private(set) var tasks: [ActiveTask] = []
    public private(set) var resolvedSuggestions: [Suggestion] = []
    public private(set) var quickActions: [QuickAction] = HomeStore.createAffordances
    public private(set) var chatShortcuts: [QuickAction] = []
    public private(set) var chatShortcutsPending = false

    public private(set) var greeting: String = HomeStore.templateGreeting()
    public private(set) var greetingPending = false
    public private(set) var location = ""
    public private(set) var locationUnavailable = false
    public var locationNeedsSettings: Bool { false }

    public private(set) var isLoading = false
    public private(set) var errorText: String?
    public private(set) var errorKind: APIError.Kind = .unknown

    /// Update rows the user has seen, and sign-in codes they have used or
    /// outlived. Local in the real app too — these drive the unread dot and the
    /// live countdown, and never needed the server to be correct.
    private var seenUpdateIds: Set<String> = []
    public private(set) var consumedCodeIds: Set<UUID> = []
    public private(set) var expiredCodeIds: Set<UUID> = []
    /// Card id → the chat thread its reply rail opened, so a re-open resumes.
    private var sideThreads: [UUID: String] = [:]

    // MARK: - Seeding

    /// Pin the whole surface to fixed content. The only way anything gets into
    /// this store.
    public func seedForDesignTrial(
        greeting: String,
        location: String,
        chatShortcuts: [QuickAction],
        suggestions: [Suggestion]
    ) {
        self.greeting = greeting
        self.location = location
        self.chatShortcuts = chatShortcuts
        self.suggestions = suggestions
        chatShortcutsPending = false
        greetingPending = false
        locationUnavailable = false
        isLoading = false
        errorText = nil
    }

    // MARK: - Greeting

    /// Daypart greeting in the assistant's register — the template the real
    /// store shows until a written line arrives from the server.
    public static func templateGreeting(now: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        let daypart: String
        switch hour {
        case 5 ..< 12: daypart = String(localized: "morning")
        case 12 ..< 17: daypart = String(localized: "afternoon")
        default: daypart = String(localized: "evening")
        }
        switch IrisRegister.current {
        // Lowercase, no terminal punctuation — the register's own spine rule.
        case .veryCasual: return String(localized: "good \(daypart)")
        // Sentence case like a phone with autocaps on, and never a final period.
        case .casual: return String(localized: "Good \(daypart)")
        // Complete, composed, terminal period. No exclamation enthusiasm.
        case .formal: return String(localized: "Good \(daypart).")
        }
    }

    public func refreshGreetingTemplate() { greeting = Self.templateGreeting() }

    /// The real store asks the assistant to write a fresh line. Seeded copy
    /// stands, so the tap is inert.
    public func regenerateGreeting() {}
    public func regenerateSassGreeting(annoyance: Int, fallbackLine: String) {}
    public func regenerateChatShortcuts() {}

    /// The + menu's create rows. Fixed in the real app too.
    public static let createAffordances: [QuickAction] = [
        QuickAction(title: String(localized: "Set reminder"), symbol: "bell.badge", seedPrompt: "", kind: .composeReminder),
        QuickAction(title: String(localized: "New email"), symbol: "envelope.badge", seedPrompt: "", kind: .composeEmail),
        QuickAction(title: String(localized: "Automations"), symbol: "sparkles", seedPrompt: "", kind: .automations)
    ]

    // MARK: - Fetching (all inert)

    public func refresh() async {}
    public func pollTasksWhileActive() async {}
    public func loadResolvedSuggestions() async {}
    public func retryLocation() async {}
    public func noteSuggestionsSeen(_ shown: [Suggestion]) {}
    public func noteTaskStarted(taskId: String, goal: String) {}

    // MARK: - Read state

    public func isUpdateUnread(_ suggestion: Suggestion) -> Bool {
        !seenUpdateIds.contains(suggestion.id.uuidString)
    }

    /// A tapped / copied card is seen: the unread dot drops, the row stays.
    public func markUpdateSeen(_ suggestion: Suggestion) {
        seenUpdateIds.insert(suggestion.id.uuidString)
    }

    public func markCodeConsumed(_ suggestion: Suggestion) {
        consumedCodeIds.insert(suggestion.id)
    }

    public func markCodeExpired(_ suggestion: Suggestion) {
        expiredCodeIds.insert(suggestion.id)
    }

    // MARK: - Card lifecycle

    /// Pull a card out of the deck, handing back where it was so an Undo can
    /// put it back. The real store defers the server call to the undo window;
    /// here the local half IS the whole story.
    public func takeSuggestion(_ suggestion: Suggestion) -> Int? {
        guard let index = suggestions.firstIndex(where: { $0.id == suggestion.id }) else { return nil }
        suggestions.remove(at: index)
        return index
    }

    public func restoreSuggestion(_ suggestion: Suggestion, at index: Int) {
        let target = min(max(0, index), suggestions.count)
        suggestions.insert(suggestion, at: target)
    }

    public func dismissSuggestion(_ suggestion: Suggestion) async {
        _ = takeSuggestion(suggestion)
    }

    /// The undo window closed — the real store now tells the server. Nothing
    /// left to do locally; the card already left on the swipe.
    public func commitDismiss(_ suggestion: Suggestion) async {}

    public func snoozeSuggestion(_ suggestion: Suggestion, until: Date? = nil) async {
        _ = takeSuggestion(suggestion)
    }

    public func cancelReminder(id: String) async {}

    // MARK: - Tasks

    public func markTaskStoppedLocally(_ task: ActiveTask) {}
    public func dismissOutcomeLocally(_ task: ActiveTask) {}
    public func commitAcknowledge(_ task: ActiveTask) async {}
    public func commitTaskClose(_ task: ActiveTask) async {}
    public func closeTask(_ task: ActiveTask) async {}

    /// The real store spawns a background agent and returns its id. Nothing
    /// runs here, so there is no task to open.
    public func startTask(_ suggestion: SuggestedTask) async -> String? { nil }

    // MARK: - Actions

    public enum PermissionFollowUp: Sendable {
        case none
        case openSettings
    }

    public func requestPermission(scope: String) async -> PermissionFollowUp { .none }

    public enum ActionOutcome: Sendable, Equatable {
        case openLink(URL)
        case taskStarted(taskId: String)
        case sent
        case acknowledged
        case permissionRequested(scope: String)
        case introCallPlaced
        case failed(String)
    }

    /// A card's own action button. Every one of these was a round trip; the
    /// card reports the failure state instead, which is a path the UI already
    /// draws for a dead network.
    public func performAction(
        _ suggestion: Suggestion,
        _ action: SuggestionActionItem,
        editedBody: String? = nil
    ) async -> ActionOutcome {
        .failed(String(localized: "This build has no backend."))
    }

    public enum GeneratedActionOutcome: Sendable, Equatable {
        case replied(reply: String)
        case sent
        case reminded(reminderId: String, fireAt: Date?)
        case meetingCreated
        case taskStarted(taskId: String)
        case openLink(URL)
        case acknowledged
        case failed(String)
    }

    public func performGeneratedAction(
        _ suggestion: Suggestion,
        _ action: GeneratedAction,
        editedBody: String? = nil
    ) async -> GeneratedActionOutcome {
        .failed(String(localized: "This build has no backend."))
    }

    // MARK: - A card's reply thread

    public func sideThreadId(for cardId: UUID) -> String? { sideThreads[cardId] }

    public func recordSideThread(_ threadId: String, for cardId: UUID) {
        sideThreads[cardId] = threadId
    }

    public func fetchSideThreadMessages(_ threadId: String) async throws -> [ChatMessage] { [] }

    /// The real store streams the assistant's reply back token by token. There
    /// is nobody to answer, so the caller gets the error branch it already
    /// handles.
    public func streamSuggestionReply(
        _ text: String,
        threadId: String?,
        images: [Data] = [],
        file: ChatFileAttachment? = nil,
        onEvent: @escaping @MainActor (ChatStreamEvent) -> Void
    ) async -> (threadId: String?, error: Error?) {
        (threadId, APIError.noBackend)
    }
}
