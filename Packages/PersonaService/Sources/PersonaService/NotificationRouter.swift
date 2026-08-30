import Combine
import Foundation

/// Bridges a TAPPED notification (parsed in the App's PushManager) to the SwiftUI
/// shell, so every notification deep-links to the surface it belongs to instead of
/// dropping the user at the chat root.
///
/// The backend stamps a `route` (+ the relevant ids) onto every push — on the FCM
/// `data` dict and on the poll-fallback outbox payload alike (see
/// `routeForEventType` in the backend). This object turns that contract into a
/// `Route` the shell consumes.
///
/// A shared singleton (not environment-injected) so the PushManager singleton can
/// set a target during cold start, BEFORE any SwiftUI is on screen; `PersonaRootView`
/// consumes `pending` once it mounts (which only happens at `AppEnvironment.phase
/// == .ready`), so a launch-from-notification survives the boot.
@MainActor
public final class NotificationRouter: ObservableObject {
    public static let shared = NotificationRouter()
    private init() {}

    public enum Route: Equatable {
        /// Main chat. A sub-thread id opens that thread; nil / the main thread just
        /// pages to Chat scrolled to the latest turn (where a task result lands).
        /// A messageId (the backend's `chatMessageId` — the exact bubble the push
        /// announced) scrolls the opened thread to that bubble and flashes it.
        case chat(threadId: String?, messageId: String?)
        /// A background deep task's OWN thread — a "needs your input" push lands on
        /// the ask_user panel there.
        case task(taskId: String)
        /// The Reminders screen (calendar / generic reminders all land here).
        case reminders
        /// The Home suggestions surface; a card id opens that card's chat sheet.
        case suggestion(cardId: String?)
        /// A mail action link — open this URL directly (no in-app screen).
        case link(url: String)
        /// Settings → Automations (an automation paused itself / fired mid-meeting).
        case automations
        /// Settings → Connected Apps (an AgentCard KYC status change).
        case connectedApps
    }

    /// The pending tap target, consumed + cleared by `PersonaRootView` once the
    /// shell is ready. Survives a cold-start tap until then.
    @Published public var pending: Route?

    /// A suggestion card the Home surface should open its chat sheet for. Set by the
    /// shell after it has paged to Home (Home owns its own sheet state); Home consumes
    /// and clears it once it can resolve the card.
    @Published public var openSuggestionCardId: String?

    /// Turn a tapped notification's routing keys into a `pending` Route. The keys come
    /// from the FCM `data` dict (background push) or the poll path's local-notification
    /// userInfo (both carry the same contract). `route` is authoritative; we fall back
    /// to deriving it from the event `type` so a push that predates the `route` field
    /// still lands right.
    public func handle(userInfo: [String: String]) {
        let route = userInfo["route"] ?? Self.derive(userInfo["type"] ?? "")
        // The exact bubble this push announced (backend thread-append insert id).
        // NOT `messageId` — mail events use that key for the PROVIDER's mail id.
        let messageId = nonEmpty(userInfo["chatMessageId"])
        switch route {
        case "task":
            if let id = nonEmpty(userInfo["deepTaskId"]) {
                pending = .task(taskId: id)
            } else {
                // A task route with no id can't open a thread — land in chat instead.
                pending = .chat(threadId: nonEmpty(userInfo["threadId"]), messageId: messageId)
            }
        case "reminders":
            // A fired reminder now also lands in the MAIN chat as a message +
            // interactive card (snooze/done buttons); when the push carries that
            // threadId, open the conversation the card sits in — the actions are
            // THERE, not on the Reminders list. Older pushes (no threadId) still
            // open the list.
            if let threadId = nonEmpty(userInfo["threadId"]) {
                pending = .chat(threadId: threadId, messageId: messageId)
            } else {
                pending = .reminders
            }
        case "suggestion":
            // A sign-in code / inbox-watch hit lives on its Home "Updates" card —
            // tapping the notification lands on Home with the update in view
            // (its legacy chat bubble may still exist, but the card IS the
            // surface now). The threadId-first rule below is for important-mail
            // heads-ups only.
            let type = userInfo["type"] ?? ""
            if type == "mail.signin_code" || type == "mail.wallet_pass" || type == "mail.watch_hit" {
                pending = .suggestion(cardId: nonEmpty(userInfo["cardId"]))
                return
            }
            // An important-mail heads-up now also lands as an Iris message in a
            // reused "Iris Heads-up" chat thread; when the push carries that
            // threadId, open the thread directly (a real, continuable conversation)
            // rather than the Home card. Pushes without a threadId still open the card.
            if let threadId = nonEmpty(userInfo["threadId"]) {
                pending = .chat(threadId: threadId, messageId: messageId)
            } else {
                pending = .suggestion(cardId: nonEmpty(userInfo["cardId"]))
            }
        case "link":
            // Open the URL directly; if it's missing, fall back to the card (whose
            // own tap opens the link) rather than dropping the user in chat.
            if let url = nonEmpty(userInfo["url"]) {
                pending = .link(url: url)
            } else {
                pending = .suggestion(cardId: nonEmpty(userInfo["cardId"]))
            }
        case "automations":
            pending = .automations
        case "connected_apps":
            pending = .connectedApps
        default:
            pending = .chat(threadId: nonEmpty(userInfo["threadId"]), messageId: messageId)
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// Client-side mirror of the backend's `routeForEventType` — only used when a
    /// push arrived without the `route` field (older event, or a stripped envelope).
    static func derive(_ type: String) -> String {
        if type == "deep_task.needs_input" || type == "deep_task.failed" || type == "deep_task.call_no_answer" {
            return "task"
        }
        if type.hasPrefix("deep_task") { return "chat" }
        // Only a personal reminder opens the Reminders surface — a
        // calendar.reminder heads-up is a calendar event, which that list
        // doesn't show; it falls through to chat below.
        if type == "reminder" { return "reminders" }
        if type == "automation.paused" || type == "automation.reminder" { return "automations" }
        // an action link / meeting-join nudge opens its URL directly.
        if type == "mail.action_link" || type == "calendar.starting" { return "link" }
        // card-backed events open their card (Updates / "Other" section).
        if type == "suggestion" || type == "mail.important" || type == "mail.signin_code" || type == "mail.wallet_pass"
            || type == "mail.watch_hit" || type == "automation.notice" || type == "daily.sync" {
            return "suggestion"
        }
        if type == "agentcard.kyc" { return "connected_apps" }
        return "chat"
    }
}
