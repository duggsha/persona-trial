import Foundation

/// A backend-generated card action (the `generatedActions` field): a card ships
/// exactly one primary (index 0) + up to 3 options, each a {id, kind, label,
/// primary, payload}. Rendering is driven by `kind`; execution posts to
/// `/v1/suggestions/:id/actions/:kind` with `body.actionId = id`. This is the
/// model half of the isolated decode layer — the JSON decode lives in
/// PersonaService's `GeneratedActionDTO`.
public struct GeneratedAction: Identifiable, Hashable, Sendable, Codable {
    /// The backend action id ("g0") — routes execution via `body.actionId`.
    public let id: String
    public let kind: GeneratedActionKind
    public let label: String
    /// Exactly one action is primary (index 0) — the collapsed card's one chip.
    public let primary: Bool
    public let payload: GeneratedActionPayload

    public init(
        id: String,
        kind: GeneratedActionKind,
        label: String,
        primary: Bool = false,
        payload: GeneratedActionPayload = GeneratedActionPayload()
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.primary = primary
        self.payload = payload
    }

    /// A proposable action leads the collapsed card; a bare acknowledge is a
    /// dismissal, never a proposed action.
    public var isProposable: Bool {
        switch kind {
        case .acknowledge, .unknown: return false
        default: return true
        }
    }

    /// The text a reply action carries: an editable draft body (reply_send) or a
    /// canned quick answer (reply_option).
    public var replyText: String? {
        switch kind {
        case .replySend: return payload.body
        case .replyOption: return payload.text
        default: return nil
        }
    }
}

/// The seven contract kinds, plus a tolerant `.unknown` so a newer backend kind
/// never breaks an older client — the renderer skips `.unknown`. Raw values match
/// the `/actions/:kind` path segment.
public enum GeneratedActionKind: String, Hashable, Sendable, Codable {
    case replySend = "reply_send"
    case replyOption = "reply_option"
    case startTask = "start_task"
    case openLink = "open_link"
    case createMeeting = "create_meeting"
    case remind
    case acknowledge
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = GeneratedActionKind(rawValue: raw) ?? .unknown
    }
}

/// Per-kind payload specifics (the union of the contract's shapes). Every field
/// is optional; only the ones a kind needs are set. A fixed typed shape (not
/// free-form JSON) keeps `Suggestion` Hashable/Codable; unknown keys are ignored.
public struct GeneratedActionPayload: Hashable, Sendable, Codable {
    // reply_send
    public let accountId: String?
    public let draftId: String?
    /// The editable draft body — the send posts the EDITED text as `body`.
    public let body: String?
    public let to: String?
    public let subject: String?
    public let inReplyToThreadId: String?
    // reply_option
    public let text: String?
    // start_task
    public let goal: String?
    // open_link
    public let url: String?
    // create_meeting
    public let title: String?
    public let startISO: String?
    public let endISO: String?
    // remind
    public let content: String?
    public let fireAtISO: String?

    public init(
        accountId: String? = nil,
        draftId: String? = nil,
        body: String? = nil,
        to: String? = nil,
        subject: String? = nil,
        inReplyToThreadId: String? = nil,
        text: String? = nil,
        goal: String? = nil,
        url: String? = nil,
        title: String? = nil,
        startISO: String? = nil,
        endISO: String? = nil,
        content: String? = nil,
        fireAtISO: String? = nil
    ) {
        self.accountId = accountId
        self.draftId = draftId
        self.body = body
        self.to = to
        self.subject = subject
        self.inReplyToThreadId = inReplyToThreadId
        self.text = text
        self.goal = goal
        self.url = url
        self.title = title
        self.startISO = startISO
        self.endISO = endISO
        self.content = content
        self.fireAtISO = fireAtISO
    }
}

/// One line of a daily-sync agenda that may carry at most ONE mini-chip. When
/// the backend doesn't send structured lines, the card falls back to splitting
/// the body text into plain (chip-less) lines.
public struct DailyAgendaLine: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let text: String
    /// At most ONE action chip for this line (kinds: start_task | remind |
    /// open_link | acknowledge). It executes via the same POST as
    /// `generatedActions` — its id also rides in `card.generatedActions`. Nil = a
    /// plain, chip-less line.
    public let chip: GeneratedAction?

    public init(id: UUID = UUID(), text: String, chip: GeneratedAction? = nil) {
        self.id = id
        self.text = text
        self.chip = chip
    }
}
