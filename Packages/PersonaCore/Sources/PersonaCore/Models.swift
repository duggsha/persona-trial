import Foundation

// MARK: - Settings

/// The extra state a registry event connector carries (`type == "event"`):
/// Telegram, GitHub, Stripe, RSS, the generic webhook, …
///
/// One nested value rather than seven optionals on `Integration`: they are only
/// ever read together, and seven loose optionals on a struct shared by mail,
/// contacts and MCP rows is how a field ends up read for the wrong card type.
public struct EventConnectorInfo: Hashable, Sendable, Codable {
    /// "webhook" (paste a URL upstream) or "poll".
    public let transport: String
    /// How the user proves the connection: "oauth" (a consent flow, no typing),
    /// "bot-token" / "api-key" (paste one), "webhook-secret" (paste the
    /// provider's signing secret). Decides whether tapping opens a browser or
    /// a sheet — the same fork `authType` makes for MCP rows.
    public let authKind: String
    /// The URL to paste into the provider's console. Nil until connected.
    public let webhookUrl: String?
    /// Where the user goes upstream to create the token or webhook.
    public let setupUrl: String?
    /// A named limitation, rendered on the card BEFORE connecting. A gap the
    /// user finds by writing a rule that never fires costs their trust in the
    /// whole feature; one printed on the box costs nothing.
    public let caveat: String?
    /// False = it cannot receive events yet (no runner our side, or the
    /// upstream app is not registered). Show it; do not offer to connect it.
    public let available: Bool
    /// Does connecting require pasting a token / key / signing secret?
    public let needsSecret: Bool
    /// Last time it actually produced an event. "Connected" and "working" are
    /// different questions, and this is the only field that answers the second
    /// — a connector wired to the wrong channel looks exactly like a quiet week.
    public let lastEventAt: String?

    public init(
        transport: String,
        authKind: String = "webhook-secret",
        webhookUrl: String? = nil,
        setupUrl: String? = nil,
        caveat: String? = nil,
        available: Bool = true,
        needsSecret: Bool = false,
        lastEventAt: String? = nil
    ) {
        self.transport = transport
        self.authKind = authKind
        self.webhookUrl = webhookUrl
        self.setupUrl = setupUrl
        self.caveat = caveat
        self.available = available
        self.needsSecret = needsSecret
        self.lastEventAt = lastEventAt
    }
}

/// A connected service shown in Settings (mail, calendar, contacts, an MCP tool…).
public struct Integration: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let type: String
    public let title: String
    public let subtitle: String
    public let connected: Bool
    /// SF Symbol derived from the integration type.
    public let systemIcon: String
    /// "google" | "microsoft" | "imap" for mail; nil otherwise.
    public let provider: String?
    public let accountId: String?
    /// MCP tool slug (e.g. "opentable", "spotify"); nil otherwise.
    public let slug: String?
    /// For MCP tools: "oauth" | "api_key" | "none" (from /v1/mcp/catalog); nil
    /// for non-MCP integrations. Decides whether connect opens a browser or an
    /// API-key form.
    public let authType: String?
    /// Surfaced in onboarding's "Recommended for you" section when true.
    public let recommended: Bool
    /// One-line why-this-fits pitch shown as the recommended row's subtitle.
    public let recommendReason: String?
    /// 0-based ordering within the recommended set (set when `recommended`) —
    /// the evidence ranking, so a surface showing only the top pick shows the
    /// RIGHT one. Nil when not recommended, or from an older backend.
    public let recommendRank: Int?
    /// Per-integration tool switch: false = connected but its chat tools are
    /// withheld. Nil = no switch for this integration (or cached snapshot from
    /// an older build) — treated as on.
    public let enabled: Bool?
    /// Set only for `type == "event"` rows. Nil for every other card type, and
    /// for a cached snapshot written by an older build.
    public let eventInfo: EventConnectorInfo?

    public init(
        id: String,
        type: String,
        title: String,
        subtitle: String,
        connected: Bool,
        systemIcon: String,
        provider: String? = nil,
        accountId: String? = nil,
        slug: String? = nil,
        authType: String? = nil,
        recommended: Bool = false,
        recommendReason: String? = nil,
        recommendRank: Int? = nil,
        enabled: Bool? = nil,
        eventInfo: EventConnectorInfo? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.connected = connected
        self.systemIcon = systemIcon
        self.provider = provider
        self.accountId = accountId
        self.eventInfo = eventInfo
        self.slug = slug
        self.authType = authType
        self.recommended = recommended
        self.recommendReason = recommendReason
        self.recommendRank = recommendRank
        self.enabled = enabled
    }
}

// MARK: - Home

/// What a quick action does when tapped.
public enum QuickActionKind: Hashable, Sendable {
    /// Seed a chat turn with `seedPrompt` (sends immediately).
    case seedChat
    /// Open the email compose sheet.
    case composeEmail
    /// Open the reminder compose sheet (title + date/time).
    case composeReminder
    /// Open the Automations settings page.
    case automations
}

/// The single most-relevant thing to start right now, derived from the user's
/// real context (top of the backend's ranked home actions). Shown as the home
/// hero card when there's no imminent meeting; "Start" spawns a deep task from
/// `seedPrompt`.
public struct SuggestedTask: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let subtitle: String
    /// First-person goal sent to start the task.
    public let seedPrompt: String
    /// SF Symbol name for the card glyph.
    public let symbol: String
    /// Provenance for a context-driven card: where its context lives, its id, and
    /// a one-line preview. Nil on static catalog cards — then no context chip.
    /// `referenceKind`: mail-thread | mail-message | calendar_event | deep-task.
    public let referenceKind: String?
    public let referenceId: String?
    public let contextSnippet: String?

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        seedPrompt: String,
        symbol: String,
        referenceKind: String? = nil,
        referenceId: String? = nil,
        contextSnippet: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.seedPrompt = seedPrompt
        self.symbol = symbol
        self.referenceKind = referenceKind
        self.referenceId = referenceId
        self.contextSnippet = contextSnippet
    }

    /// A tappable context is present only when there's a snippet AND a resolvable
    /// reference (kind + id).
    public var hasContext: Bool {
        guard let snippet = contextSnippet, !snippet.isEmpty,
              let kind = referenceKind, !kind.isEmpty,
              let id = referenceId, !id.isEmpty else { return false }
        return true
    }
}

/// A pill-style shortcut shown under "Quick Actions".
public struct QuickAction: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    /// SF Symbol name.
    public let symbol: String
    /// What to send the assistant when tapped (from the backend's home action).
    public let seedPrompt: String
    public let kind: QuickActionKind

    public init(
        id: UUID = UUID(),
        title: String,
        symbol: String,
        seedPrompt: String,
        kind: QuickActionKind = .seedChat
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.seedPrompt = seedPrompt
        self.kind = kind
    }
}

/// The "meeting in 30 mins" summary card.
public struct MeetingSummary: Hashable, Sendable, Codable {
    public let title: String
    public let body: String
    public let joinLabel: String
    /// Calendar/hangout link to open when tapped; nil → ask Iris instead.
    public let link: String?
    /// The joinable video-call link (Meet, or Zoom/Teams via the conference
    /// payload). Present → the card shows "Join meeting"; nil → it doesn't.
    public let joinLink: String?
    /// The event's location string, when it has one — drives the card's
    /// "Get directions" button (Google Maps).
    public let location: String?
    /// A short per-meeting briefing (who you're meeting, what's at stake, a prep
    /// angle), loaded from POST /v1/home/meeting-briefing. nil until it lands;
    /// shown inline under the card, collapsed to a few lines with tap-to-expand.
    public let briefing: String?
    /// One-line glanceable version shown collapsed on the hero; the full
    /// `briefing` reveals on expand. Falls back to `briefing` when absent.
    public let briefingSummary: String?
    /// Tap-to-send chat prompts the briefing proposes ("give me a full
    /// briefing", "who is adam?"). Rendered as chips when the card is expanded.
    public let suggestedResponses: [String]
    /// Real social/profile links for the other attendee (X, Instagram, LinkedIn,
    /// Website, …) so the user can look them up before the call — rendered as
    /// tappable icon chips. Empty when the web search found none.
    public let profiles: [MeetingProfile]
    /// The calendar event id + ISO start, so the client can request the briefing
    /// and seed a meeting chat. nil for surfaces that don't carry it.
    public let eventId: String?
    public let startsAt: String?
    /// The event's wall-clock time in its own calendar time zone (for example,
    /// "10:30 AM"). This stays useful even when personalized copy changes.
    public let scheduleLabel: String?
    /// All-day event: a floating DATE, not an instant. `startsAt` then carries
    /// the local start-of-day and `endsAt` the local end of the span (end
    /// exclusive) — the dismissal tombstone must outlive the whole day, not
    /// expire at its first midnight. Optional so cached snapshots predating
    /// the field still decode (nil reads as timed).
    public let allDay: Bool?
    public let endsAt: String?

    public var isAllDay: Bool { allDay ?? false }

    public init(
        title: String,
        body: String,
        joinLabel: String,
        link: String? = nil,
        joinLink: String? = nil,
        location: String? = nil,
        briefing: String? = nil,
        briefingSummary: String? = nil,
        suggestedResponses: [String] = [],
        profiles: [MeetingProfile] = [],
        eventId: String? = nil,
        startsAt: String? = nil,
        scheduleLabel: String? = nil,
        allDay: Bool? = nil,
        endsAt: String? = nil
    ) {
        self.title = title
        self.body = body
        self.joinLabel = joinLabel
        self.link = link
        self.joinLink = joinLink
        self.location = location
        self.briefing = briefing
        self.briefingSummary = briefingSummary
        self.suggestedResponses = suggestedResponses
        self.profiles = profiles
        self.eventId = eventId
        self.startsAt = startsAt
        self.scheduleLabel = scheduleLabel
        self.allDay = allDay
        self.endsAt = endsAt
    }

    /// A copy with the briefing (short + full text + chips + profile links) filled in.
    public func withBriefing(
        _ briefing: String?,
        summary: String?,
        suggestedResponses: [String],
        profiles: [MeetingProfile]
    ) -> MeetingSummary {
        MeetingSummary(
            title: title, body: body, joinLabel: joinLabel, link: link,
            joinLink: joinLink, location: location,
            briefing: briefing, briefingSummary: summary, suggestedResponses: suggestedResponses, profiles: profiles,
            eventId: eventId, startsAt: startsAt, scheduleLabel: scheduleLabel, allDay: allDay, endsAt: endsAt
        )
    }
}

/// A social/profile link on a meeting attendee. `platform` names the service
/// ("X", "Instagram", "LinkedIn", "Website", …) → the client maps it to an icon.
public struct MeetingProfile: Hashable, Sendable, Codable {
    public let platform: String
    public let url: String

    public init(platform: String, url: String) {
        self.platform = platform
        self.url = url
    }

    /// SF Symbol for the platform (Apple has no brand logos, so these are
    /// sensible stand-ins) plus a fallback for anything unknown.
    public var systemImage: String {
        switch platform.lowercased() {
        case "x", "twitter": "at"
        case "instagram": "camera"
        case "linkedin": "briefcase"
        case "github": "chevron.left.forwardslash.chevron.right"
        case "youtube": "play.rectangle"
        case "tiktok": "music.note"
        case "farcaster": "antenna.radiowaves.left.and.right"
        case "substack": "newspaper"
        case "crunchbase", "rootdata": "building.2"
        case "website": "globe"
        default: "link"
        }
    }
}

/// A task (e.g. a food order) — live with progress, or a completed history entry.
public struct ActiveTask: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    /// Asset name of the originating app's logo.
    public let appImage: String
    public let title: String
    public let subtitle: String
    public let timeRemaining: String
    /// 0...1.
    public let progress: Double
    public let vendor: String
    /// SF Symbol for the vendor.
    public let vendorSymbol: String
    public let itemsSummary: String
    // History / "All" list fields.
    public let status: String
    public let detail: String
    public let isActive: Bool
    /// History group ("Today", "Yesterday", …); nil for the active task.
    public let historySection: String?
    public let completedDuration: String?
    /// Whether the progress bar is meaningful (true for tracked work like an
    /// order or a running agent task).
    public let showsProgress: Bool
    /// The delegated deep-task's id, so tapping the card opens the task thread.
    public let deepTaskID: String?
    /// The deep-task is parked on `ask_user` and needs the user's answer.
    public let needsInput: Bool
    /// The agent's pending question when `needsInput` — shown as the action prompt.
    public let pendingQuestion: String?
    /// Agent-supplied choice buttons for the pending question — tapping one
    /// sends that label as the answer. Optional so cached snapshots from
    /// before the field decode cleanly.
    public let pendingOptions: [String]?
    /// The task's defining event instant — creation while it runs, completion
    /// once terminal — for feed ordering. Optional so cached snapshots from
    /// before the field decode cleanly.
    public let eventDate: Date?
    /// Brand domain behind the task (e.g. an integration vendor) — drives a
    /// logo.dev brand icon in place of `vendorSymbol`. Nil when unknown.
    public let logoDomain: String?
    /// A person tied to the task — drives a Gravatar / logo.dev icon. Nil when none.
    public let contactEmail: String?
    /// A resolved real photo of the person behind the task — rendered ahead of
    /// `contactEmail`/`logoDomain`. Nil when none.
    public let photoUrl: String?
    /// Terminal outcome of a deep task: "succeeded" or "failed". Nil while the
    /// task runs — drives the green/red outcome panel.
    public let outcome: String?
    /// A terminal deep task the user hasn't dismissed yet: it stays pinned on
    /// Home with its outcome panel until acknowledged. `var` so the store can
    /// clear it optimistically on "Got it" without rebuilding the struct.
    public var needsAcknowledge: Bool
    /// Set only for a SCHEDULED deep task (created, not yet started): when it
    /// will run. Drives the calm scheduled row + the dock's "N scheduled"
    /// count. Nil for every other task. Optional so cached snapshots from
    /// before the field decode cleanly.
    public let scheduledFor: Date?

    public init(
        id: UUID = UUID(),
        appImage: String,
        title: String,
        subtitle: String,
        timeRemaining: String,
        progress: Double,
        vendor: String = "",
        vendorSymbol: String = "storefront",
        itemsSummary: String = "",
        status: String = "In progress",
        detail: String = "",
        isActive: Bool = true,
        historySection: String? = nil,
        completedDuration: String? = nil,
        showsProgress: Bool = true,
        deepTaskID: String? = nil,
        needsInput: Bool = false,
        pendingQuestion: String? = nil,
        pendingOptions: [String]? = nil,
        eventDate: Date? = nil,
        logoDomain: String? = nil,
        contactEmail: String? = nil,
        photoUrl: String? = nil,
        outcome: String? = nil,
        needsAcknowledge: Bool = false,
        scheduledFor: Date? = nil
    ) {
        self.id = id
        self.appImage = appImage
        self.title = title
        self.subtitle = subtitle
        self.timeRemaining = timeRemaining
        self.progress = progress
        self.vendor = vendor
        self.vendorSymbol = vendorSymbol
        self.itemsSummary = itemsSummary
        self.status = status
        self.detail = detail
        self.isActive = isActive
        self.historySection = historySection
        self.completedDuration = completedDuration
        self.showsProgress = showsProgress
        self.deepTaskID = deepTaskID
        self.needsInput = needsInput
        self.pendingQuestion = pendingQuestion
        self.pendingOptions = pendingOptions
        self.eventDate = eventDate
        self.logoDomain = logoDomain
        self.contactEmail = contactEmail
        self.photoUrl = photoUrl
        self.outcome = outcome
        self.needsAcknowledge = needsAcknowledge
        self.scheduledFor = scheduledFor
    }

    /// Whether the meta line (vendor + items) carries content worth showing.
    public var hasMeta: Bool {
        !vendor.isEmpty || !itemsSummary.isEmpty
    }

    /// Created but not yet started — runs itself at `scheduledFor`. Neither
    /// active (nothing to poll) nor terminal; folds into the task dock as an
    /// armed, cancelable row.
    public var isScheduled: Bool {
        scheduledFor != nil && !isActive && outcome == nil
    }

    /// Time label for the history row (remaining while active, else duration).
    public var historyDurationLabel: String {
        isActive ? timeRemaining : (completedDuration ?? timeRemaining)
    }

    /// An optimistic "stopped" copy: closing a task leaves Home at once (no longer
    /// active) but stays in the All list as a stopped entry — it is never removed.
    /// It also carries the TERMINAL pair the card actually renders the stopped
    /// state from (`outcome` + `needsAcknowledge`, exactly what HomeMapper derives
    /// for a cancelled task). Without them the row flipped its subtitle instantly
    /// but the grey STOPPED panel only appeared on the next refresh — the ~2s lag
    /// design reported on.
    public func markedClosed() -> ActiveTask {
        ActiveTask(
            id: id,
            appImage: appImage,
            title: title,
            subtitle: "Stopped",
            timeRemaining: timeRemaining,
            progress: progress,
            vendor: vendor,
            vendorSymbol: vendorSymbol,
            itemsSummary: itemsSummary,
            status: "Stopped",
            detail: detail,
            isActive: false,
            historySection: "Today",
            completedDuration: completedDuration,
            showsProgress: false,
            deepTaskID: deepTaskID,
            needsInput: false,
            pendingQuestion: nil,
            eventDate: eventDate,
            logoDomain: logoDomain,
            contactEmail: contactEmail,
            photoUrl: photoUrl,
            outcome: "cancelled",
            needsAcknowledge: true
        )
    }
}

/// One actionable button on a suggestion (mirrors the backend action).
public struct SuggestionActionItem: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    /// "send_draft" | "open_link" | "acknowledge" | "start_task" | "create_meeting".
    public let type: String
    public let label: String
    /// The drafted reply body for a send_draft action — lets the card preview
    /// each option before sending. Nil for non-draft actions.
    public let draftBody: String?

    public init(id: UUID = UUID(), type: String, label: String, draftBody: String? = nil) {
        self.id = id
        self.type = type
        self.label = label
        self.draftBody = draftBody
    }
}

/// One Apple Wallet pass parked by the backend for a wallet-pass card: the
/// bytes live behind GET /v1/files/{objectId} and feed PassKit's add sheet.
public struct WalletPassItem: Hashable, Sendable, Codable {
    public let objectId: String
    public let filename: String?

    public init(objectId: String, filename: String?) {
        self.objectId = objectId
        self.filename = filename
    }
}

/// A running DoorDash order as Home renders it: one bar, one line, one store.
/// `progress` is authoritative — the client draws it and never re-ranks the
/// states itself, so a new DoorDash status can't silently land at 0%.
public struct OrderProgressItem: Hashable, Sendable, Codable {
    public let status: String
    /// 0…1 along placed → done.
    public let progress: Double
    public let isPickup: Bool
    public let done: Bool
    public let storeName: String?

    public init(status: String, progress: Double, isPickup: Bool, done: Bool, storeName: String?) {
        self.status = status
        self.progress = progress
        self.isPickup = isPickup
        self.done = done
        self.storeName = storeName
    }
}

/// A proactive suggestion card (someone wrote back, a draft is ready, …).
public struct Suggestion: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    /// Asset name of the contact avatar.
    public let avatar: String
    public let message: String
    /// The blue inline action verb ("Draft", "Schedule", …).
    public let action: String
    public let detail: String
    public let badge: String
    /// Still awaiting action vs. already handled (groups the "All" list).
    public let isOpen: Bool
    /// What was done, shown on handled rows in the "All" list.
    public let handledResult: String?
    /// SF Symbol shown in place of a contact avatar when there's no photo
    /// (backend suggestions are mail/calendar-driven, not contacts).
    public let systemIcon: String?
    /// Sender email for mail suggestions — drives a Gravatar / logo.dev brand
    /// icon (falls back to `systemIcon`). Nil when not a mail card.
    public let avatarEmail: String?
    /// The person behind the card (mail sender / calendar organizer) — preferred
    /// over `avatarEmail` for a Gravatar / logo.dev contact icon. Nil when none.
    public let contactEmail: String?
    /// The person's display name — the source of the "Reply to X" label and the
    /// avatar monogram, in preference to the email local part. Nil when unknown.
    public let contactName: String?
    /// The brand behind the card (meeting provider / integration vendor) — drives
    /// a logo.dev brand icon when there's no contact. Nil when none.
    public let logoDomain: String?
    /// Backend actions, rendered as buttons in the detail sheet.
    public let actions: [SuggestionActionItem]
    /// The full drafted email body for `send_draft` cards (backend `bodyText`),
    /// shown editable in the suggestion chat's draft preview. Nil for non-mail
    /// cards; the sheet falls back to `detail` when absent.
    public let draftBody: String?
    /// When the card was created (backend `createdAt`), for the "All" list's
    /// relative age label. Defaults to now for locally-built suggestions.
    public let createdAt: Date
    /// Which Home section the card belongs to. Backend `section`; unknown/absent
    /// values fall back to `.suggestions` so nothing is dropped.
    public let section: HomeSection
    /// A structured sign-in code, when the card is one — lets a tap copy it
    /// deterministically. Nil for every other card.
    public let code: String?
    /// When the sign-in code's mail SAYS the code dies ("valid for 10
    /// minutes"), the computed deadline — drives the live countdown on the
    /// Updates row. Nil when the mail stated no window (the row then shows its
    /// age; the card still self-expires server-side on a default TTL — never
    /// render an invented countdown), and on every other card kind.
    public let codeValidUntil: Date?
    /// When the card row self-expires server-side (backend `expiresAt`; sign-in
    /// codes always carry one — the stated window when the mail gave it, else
    /// the default TTL). Display never shows it as a countdown (that stays
    /// `codeValidUntil`-only — no invented precision); it exists so live
    /// surfaces can DROP a dead code on time between feed refreshes. Nil on
    /// kinds that don't self-expire and on older snapshots.
    public let expiresAt: Date?
    /// A running DoorDash order (order-progress cards only) — carried
    /// structurally so Home draws a real bar instead of reading progress out
    /// of a sentence. Nil on every other kind and on older snapshots.
    public let orderProgress: OrderProgressItem?
    /// The card is up but its work is still running — drawn greyed out with a
    /// spinner, not tappable, and sorted below the finished feed by the server.
    /// False for every card the backend has finished and for locally-built ones.
    public let isPending: Bool
    /// The parked Apple Wallet passes (wallet-pass cards only): each objectId
    /// is fetchable at GET /v1/files/{objectId}; the bytes feed PassKit's add
    /// sheet. Nil on every other kind and on older snapshots.
    public let walletPasses: [WalletPassItem]?
    /// When the pass becomes relevant per its own pass.json relevantDate
    /// (earliest across the mail's passes). Rows with this imminent ride the
    /// pinned group like a live sign-in code. Nil when the pass didn't say.
    public let walletRelevantAt: Date?
    /// The backend card kind (place, event, opportunity, important-mail, …). Drives
    /// the badge tint by category when there's no contact/brand logo to show.
    public let kind: String
    /// Structured event/opportunity facts (when / where / price / link), when the
    /// card is one. Nil otherwise; each field is independently optional.
    public let facts: Facts?
    /// What the card references (backend `referenceKind`): mail-thread |
    /// mail-message | calendar_event | deep-task. Drives calendar-invite
    /// detection (a `calendar_event` card is an invite that expands inline).
    public let referenceKind: String?
    /// What that kind points AT — for a `calendar_event` card, the provider
    /// event id, which is how the card opens the real event in-app instead of
    /// deep-linking out to the provider's web page.
    public let referenceId: String?
    /// A resolved real photo of the person behind the card — rendered ahead of
    /// `contactEmail`/`avatarEmail`/`logoDomain`. Nil when none.
    public let photoUrl: String?
    /// How a CLOSED card was resolved: "dismissed" (the user deleted it) or
    /// "acted" (an action consumed it). Nil while open — and optional so cached
    /// snapshots from before this field decode cleanly.
    public let resolution: String?
    /// What Iris PROPOSES to do (backend `cardSummary`/`irisSuggestion`, e.g.
    /// "want me to draft a quick yes?"). Optional so cached snapshots decode.
    public let offer: String?
    /// The grounding context — what actually landed (backend `bodyText`, the
    /// triage heads-up line). Optional so cached snapshots decode.
    public let context: String?
    /// Mail-referenced cards only (read-time enrichment): the referenced
    /// message's mailbox account + thread, so the card can open the email
    /// in-app, and when it was received for the meta line. Nil elsewhere and
    /// on snapshots from before these fields.
    public let mailAccountId: String?
    public let mailThreadId: String?
    public let mailReceivedAt: Date?
    /// Provider web link for the referenced message (Gmail/Outlook web) — lets
    /// the in-app mail viewer offer its "open in provider" button, matching the
    /// chat mail chips. Nil for IMAP, non-mail cards, and older snapshots.
    public let mailWebUrl: String?
    /// EVERY conversation this card is about, newest mail first. A matter card
    /// (one situation stitched from many mails) routinely spans several — the
    /// counterparty's thread, a co-signer's, the vendor's reminders. The
    /// singular fields above are this list's head. Empty on non-mail cards and
    /// on snapshots from before the backend sent it.
    public let mailReferences: [MailThreadRef]
    /// When the card is in a "waiting on a reply" state, the moment the wait
    /// began — drives the subtle "Waiting for a reply · N days" status line. Nil
    /// unless the backend marks the card as waiting (field not yet emitted;
    /// component renders behind this nil-guard).
    public let waitingSince: Date?
    /// Generated action set (backend `generatedActions`): 1 primary + up to 3
    /// options, each a {label, kind, payload}. Empty until the backend field
    /// lands; the card falls back to `actions` when this is empty.
    public let generatedActions: [GeneratedAction]
    /// A daily-sync agenda as structured lines, each able to carry ONE mini-chip
    /// (backend field not yet emitted). Nil → fall back to splitting the body
    /// text into plain lines.
    public let dailyLines: [DailyAgendaLine]?
    /// The short blue action VERB the Figma card leads its grounding line with
    /// ("Schedule", "Draft", …) — editorial and backend-authored (`contextVerb`),
    /// present on some cards and absent on others. Distinct from `action` (the
    /// primary chip's label). Nil until the backend emits it; the context line
    /// renders gray-only behind this nil-guard.
    public let contextVerb: String?
    /// Updates rows only (backend `headline`): the row's HEADER line — the
    /// exact line the chat-thread delivery carried before the mail-chat
    /// cutover, so the card reads like the bubble it replaced. Nil on sign-in
    /// codes (their rows keep the title + big-code layout), on non-update
    /// cards, and on rows from a backend that predates the field — display
    /// falls back to `message`.
    public let headline: String?
    /// The chat thread this card's in-sheet replies stream on (backend
    /// `chatThreadId`, linked when the first reply created the thread) —
    /// reopening the card resumes that conversation on any device. Nil until a
    /// reply exists, and on snapshots/backends from before the field.
    public let chatThreadId: String?

    /// The card's TOP line (reference design): the proposal question when the
    /// backend authored one, else the plain title. A legacy `irisSuggestion`
    /// can be a full draft body — anything past headline length is not a
    /// pitch, so fall back to the title rather than sprawl.
    public var proposalLine: String {
        let offer = (offer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return offer.isEmpty || offer.count > 90 ? message : offer
    }

    /// The card's arrow DETAIL line (reference design): the grounding context
    /// under the proposal. Falls back to `detail` for cards without a separate
    /// context — and hides (empty) rather than repeating the top line. Two
    /// server clamps of the SAME line differ only by a "…" cut, so a clamped
    /// prefix of the other counts as a repeat too.
    public var contextLine: String {
        let context = (context ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let line = context.isEmpty ? detail : context
        func stem(_ s: String) -> String {
            s.hasSuffix("…") ? String(s.dropLast()).trimmingCharacters(in: .whitespaces) : s
        }
        let a = stem(line)
        if a.isEmpty { return line }
        // Never repeat the proposal.
        let b = stem(proposalLine)
        if !b.isEmpty, a.hasPrefix(b) || b.hasPrefix(a) { return "" }
        // A reply card's draft belongs ONLY in the editable draft box — if the
        // grounding line IS that draft (identical, or one a prefix of the other),
        // drop it so the card never spills "half a novel". Scoped to cards that
        // actually render a draft box, so a heads-up's body summary is untouched.
        if rendersDraftBox {
            let draft = stem(shownDraftText.trimmingCharacters(in: .whitespacesAndNewlines))
            if !draft.isEmpty, a == draft || a.hasPrefix(draft) || draft.hasPrefix(a) { return "" }
        }
        return line
    }

    /// The card shows an editable draft box (a legacy send_draft, or a generated
    /// reply_send) — the only case where the grounding line may be the draft.
    private var rendersDraftBox: Bool {
        actions.contains { $0.type == "send_draft" }
            || generatedActions.contains { $0.kind == .replySend }
    }

    /// The text shown in the draft box — the generated reply_send body wins,
    /// else the legacy draftBody.
    private var shownDraftText: String {
        if let body = generatedActions.first(where: { $0.kind == .replySend })?.payload.body,
           !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return body
        }
        return draftBody ?? ""
    }

    /// The user deleted this card rather than acting on it.
    public var wasDismissed: Bool { resolution == "dismissed" }

    /// A calendar invite — expandable inline (time/where/organizer/link) rather
    /// than opening the chat sheet. Detected structurally: a calendar_event
    /// reference, or a card with a date fact and the calendar glyph.
    public var isCalendarInvite: Bool {
        if referenceKind == "calendar_event" { return true }
        return systemIcon == "calendar" && !(facts?.date ?? "").isEmpty
    }

    /// Any mail-driven card (important mail, action link, open loop, …).
    /// The backend tags these with a mail-* reference.
    public var isMailRelated: Bool {
        (referenceKind ?? "").hasPrefix("mail")
    }

    /// Cards that reveal an inline DETAIL panel on tap (chevron), instead of
    /// jumping straight into the chat sheet.
    ///
    /// A card expands ONLY when the panel has REAL content — never an empty white
    /// panel. Real content is: a draft box, meta/facts rows,
    /// mail meta (View email), a daily-sync agenda, or ≥1 real action chip beyond
    /// a bare dismiss/acknowledge. A grounding context line ALONE no longer
    /// qualifies — its "see more" lives in the collapsed card — and the
    /// delegate+dismiss fallback row is not content on its own. Everything else
    /// stays flat (no chevron); a tap opens the chat sheet.
    public var isExpandable: Bool {
        if isCalendarInvite { return true }
        let hasDraft = rendersDraftBox || !(draftBody ?? "").isEmpty
        let hasFacts = !(facts?.isEmpty ?? true)
        let hasMailMeta = mailReference != nil || mailReceivedAt != nil
        let hasRealAction = actions.contains { $0.type != "acknowledge" } || hasRenderableGeneratedChip
        let dailyBody = (context ?? draftBody ?? detail).trimmingCharacters(in: .whitespacesAndNewlines)
        let isDailyAgenda = kind.lowercased().hasPrefix("daily")
            && (!(dailyLines?.isEmpty ?? true) || !dailyBody.isEmpty)
        // A LIFE.MD matter card (V2 engine): the matter's state from the life
        // document IS the panel's content — context alone justifies the expand
        // here, unlike the generic rule above, because without it the card fell
        // into the chat sheet and lost its whole grounding.
        let isLifeMatter = kind == "life.suggestion"
            && !(context ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasDraft || hasFacts || hasMailMeta || hasRealAction || isDailyAgenda || isLifeMatter
    }

    /// A generated action that actually renders as a chip in the expanded panel —
    /// a reply option, meeting confirm, remind, task, or link. An acknowledge or
    /// unknown kind renders nothing, so on its own it never makes a card
    /// expandable (mirrors the panel's `hasRenderableGeneratedChips`).
    private var hasRenderableGeneratedChip: Bool {
        generatedActions.contains {
            switch $0.kind {
            case .replySend, .replyOption, .createMeeting, .remind, .startTask, .openLink: true
            case .acknowledge, .unknown: false
            }
        }
    }

    /// When/where/price/link for an event or opportunity — all display-ready
    /// strings, each present only when the source really has it.
    public struct Facts: Hashable, Sendable, Codable {
        public let date: String?
        public let venue: String?
        public let price: String?
        public let url: String?
        /// The green-dot line — a finding about the user's own data that bears
        /// on the decision. Nil when the producer had nothing real to say.
        public let verdict: String?
        /// The finding costs something rather than clearing the way (amber).
        public let verdictClash: Bool?
        /// "The one fact that identifies the source" (R2).
        public let subtitle: String?
        /// The sheet rail's question chips.
        public let sheetQuestions: [String]?

        public init(
            date: String?,
            venue: String?,
            price: String?,
            url: String?,
            verdict: String? = nil,
            verdictClash: Bool? = nil,
            subtitle: String? = nil,
            sheetQuestions: [String]? = nil
        ) {
            self.date = date
            self.venue = venue
            self.price = price
            self.url = url
            self.verdict = verdict
            self.verdictClash = verdictClash
            self.subtitle = subtitle
            self.sheetQuestions = sheetQuestions
        }

        /// Any renderable fact at all?
        public var isEmpty: Bool {
            [date, venue, price, url].allSatisfy { ($0 ?? "").isEmpty }
        }
    }

    /// The Home deck a card renders in: proactive picks vs. informational mail.
    public enum HomeSection: String, Hashable, Sendable, Codable {
        case suggestions
        case location
        case other
        /// See-only notices (sign-in codes, mail heads-ups, fired reminders) —
        /// the Updates section above Tasks. Backend stamps it only for clients
        /// that request `includeUpdates`.
        case updates

        public init(backend: String?) {
            self = HomeSection(rawValue: backend ?? "") ?? .suggestions
        }
    }

    public init(
        id: UUID = UUID(),
        avatar: String,
        message: String,
        action: String,
        detail: String,
        badge: String = "Open chat",
        isOpen: Bool = true,
        handledResult: String? = nil,
        systemIcon: String? = nil,
        avatarEmail: String? = nil,
        contactEmail: String? = nil,
        contactName: String? = nil,
        logoDomain: String? = nil,
        actions: [SuggestionActionItem] = [],
        draftBody: String? = nil,
        createdAt: Date = Date(),
        section: HomeSection = .suggestions,
        code: String? = nil,
        codeValidUntil: Date? = nil,
        expiresAt: Date? = nil,
        orderProgress: OrderProgressItem? = nil,
        isPending: Bool = false,
        walletPasses: [WalletPassItem]? = nil,
        walletRelevantAt: Date? = nil,
        kind: String = "",
        facts: Facts? = nil,
        referenceKind: String? = nil,
        referenceId: String? = nil,
        photoUrl: String? = nil,
        resolution: String? = nil,
        offer: String? = nil,
        context: String? = nil,
        mailAccountId: String? = nil,
        mailThreadId: String? = nil,
        mailReceivedAt: Date? = nil,
        mailWebUrl: String? = nil,
        mailReferences: [MailThreadRef] = [],
        waitingSince: Date? = nil,
        generatedActions: [GeneratedAction] = [],
        dailyLines: [DailyAgendaLine]? = nil,
        contextVerb: String? = nil,
        headline: String? = nil,
        chatThreadId: String? = nil
    ) {
        self.id = id
        self.avatar = avatar
        self.message = message
        self.action = action
        self.detail = detail
        self.badge = badge
        self.isOpen = isOpen
        self.handledResult = handledResult
        self.systemIcon = systemIcon
        self.avatarEmail = avatarEmail
        self.contactEmail = contactEmail
        self.contactName = contactName
        self.logoDomain = logoDomain
        self.actions = actions
        self.draftBody = draftBody
        self.createdAt = createdAt
        self.section = section
        self.code = code
        self.codeValidUntil = codeValidUntil
        self.expiresAt = expiresAt
        self.orderProgress = orderProgress
        self.isPending = isPending
        self.walletPasses = walletPasses
        self.walletRelevantAt = walletRelevantAt
        self.kind = kind
        self.facts = facts
        self.referenceKind = referenceKind
        self.referenceId = referenceId
        self.photoUrl = photoUrl
        self.resolution = resolution
        self.offer = offer
        self.context = context
        self.mailAccountId = mailAccountId
        self.mailThreadId = mailThreadId
        self.mailReceivedAt = mailReceivedAt
        self.mailWebUrl = mailWebUrl
        self.mailReferences = mailReferences
        self.waitingSince = waitingSince
        self.generatedActions = generatedActions
        self.dailyLines = dailyLines
        self.contextVerb = contextVerb
        self.headline = headline
        self.chatThreadId = chatThreadId
    }

    /// The subtle status line shown when a card is waiting on a reply, e.g.
    /// "Waiting for a reply · 3d" (compact, matching the app's age labels). Nil
    /// unless `waitingSince` is set.
    public var waitingStatusLine: String? {
        guard let waitingSince else { return nil }
        let days = max(0, Calendar.current.dateComponents([.day], from: waitingSince, to: Date()).day ?? 0)
        return days == 0 ? "Waiting for a reply · today" : "Waiting for a reply · \(days)d"
    }

    /// The Updates card's one header line: the backend's `headline` (the
    /// pre-cutover chat delivery line) when it sent one, else the raw title —
    /// so rows from an older backend never render blank.
    public var updateHeaderLine: String {
        let line = (headline ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? message : line
    }

    /// The in-app mail target ("View email"), when the card references a mail
    /// message the backend could resolve.
    public var mailReference: (accountId: String, threadId: String)? {
        if let mailAccountId, let mailThreadId, !mailAccountId.isEmpty, !mailThreadId.isEmpty {
            return (mailAccountId, mailThreadId)
        }
        // A backend that sent only the list still opens the primary thread.
        guard let head = mailReferences.first else { return nil }
        return (head.accountId, head.threadId)
    }

    /// Every conversation to offer, always at least the primary one — so the
    /// card has ONE list to render whether the backend sent the list or just
    /// the pair.
    public var allMailReferences: [MailThreadRef] {
        if !mailReferences.isEmpty { return mailReferences }
        guard let primary = mailReference else { return [] }
        return [MailThreadRef(accountId: primary.accountId, threadId: primary.threadId)]
    }

    /// Compact relative age ("now", "5m", "2h", "3d", "2w") — matches the Task
    /// pendant's time label. Empty when in the future / unknown.
    public var ageLabel: String {
        let seconds = Date().timeIntervalSince(createdAt)
        guard seconds >= 0 else { return "" }
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 7 { return "\(days)d" }
        return "\(days / 7)w"
    }
}

// MARK: - Chat

/// A lightweight quote of the message a reply points at.
public struct ChatReplyReference: Hashable, Sendable {
    /// What the reply quotes: an earlier chat message (the default), a Home
    /// suggestion card, or the Up Next calendar event — the two Home keyboard
    /// affordances. Drives the bubble's "Replying to …" wording and where the
    /// line navigates on tap. Session-local, like `sourceID`.
    public enum Kind: Hashable, Sendable {
        case message
        case suggestion(id: UUID)
        case meeting(eventID: String?)
    }

    public let text: String
    public let isUser: Bool
    /// The quoted message's id, so tapping the "Replying to" line can jump the
    /// transcript to it. Session-local (references aren't rebuilt from the
    /// backend); nil falls back to a text match.
    public let sourceID: UUID?
    public let kind: Kind
    /// The FULL grounding context sent to the model — everything known about
    /// the quoted suggestion / calendar event, so the reply can answer
    /// questions about it or act on it. The bubble keeps showing the short
    /// `text`; nil (chat-message quotes) falls back to `text` on the wire.
    public let context: String?

    public init(
        text: String,
        isUser: Bool,
        sourceID: UUID? = nil,
        kind: Kind = .message,
        context: String? = nil
    ) {
        self.text = text
        self.isUser = isUser
        self.sourceID = sourceID
        self.kind = kind
        self.context = context
    }

    /// The quoted suggestion card's id, when this is a suggestion reply.
    public var suggestionID: UUID? {
        if case let .suggestion(id) = kind { return id }
        return nil
    }

    /// True when this reply quotes the Up Next calendar event.
    public var isMeeting: Bool {
        if case .meeting = kind { return true }
        return false
    }
}

/// One chat bubble. Layout (width / position / wrapping) is the view's job —
/// the model carries content only.
public struct ChatMessage: Identifiable, Hashable, Sendable {
    /// One tool call inside a deep-task activity step: a short human label
    /// ("Searching: hotels downtown") plus its SF Symbol — the task thread
    /// renders these as chips instead of raw tool names.
    public struct ToolStep: Hashable, Sendable {
        public let name: String
        public let label: String
        public let symbol: String?
        /// Brand host of a browse/open step — the rail shows its favicon.
        public let domain: String?

        public init(name: String, label: String, symbol: String?, domain: String? = nil) {
            self.name = name
            self.label = label
            self.symbol = symbol
            self.domain = domain
        }
    }

    public let id: UUID
    public let text: String
    public let isUser: Bool
    public let time: String
    /// Set when this message is a reply to an earlier one.
    public let replyTo: ChatReplyReference?
    /// Set when this message opens into a side thread.
    public let threadID: UUID?
    /// An attached photo (JPEG), shown above the text. Set for a fresh local send
    /// (immediate render); nil on a reloaded bubble, which loads from
    /// `imageRemotePath` instead. When several photos ride on one send this is
    /// the FIRST of `imageDatas` — the single-image back-compat field.
    public let imageData: Data?
    /// ALL locally attached photos on this message (the composer stages up to
    /// 5). Non-empty only for a fresh local send — the views render every tile
    /// from this list; a reloaded bubble uses `imageRemotePaths` instead.
    public let imageDatas: [Data]
    /// Backend path for an uploaded image ("/v1/assets/<id>"), carried through
    /// history so a reloaded bubble can fetch + show the photo the user sent
    /// (chat uploads are now persisted server-side). nil for a fresh send.
    public let imageRemotePath: String?
    /// ALL image asset paths on this message ("/v1/assets/<id>" each) — a
    /// message can carry several photos (the assistant's send_photo sends up
    /// to 4 in one turn). When non-empty this supersedes `imageRemotePath`
    /// (which stays as the single-image back-compat field).
    public let imageRemotePaths: [String]
    /// A recorded voice message (server-side "voice message mode"). Playable file
    /// source — the local clip while it's still being sent (immediate playback);
    /// nil on a reloaded bubble, which replays from `audioRemotePath` instead.
    /// When set (or `audioRemotePath` is), the bubble renders as a voice note.
    public let audioURL: URL?
    /// Backend replay path for this voice message ("/v1/chat/voice/audio/<id>"),
    /// carried through history so a reloaded bubble can fetch + play the clip on
    /// first tap. nil for a fresh send (which uses the local `audioURL`).
    public let audioRemotePath: String?
    /// Length of the voice message, for the bubble's duration label + waveform.
    public let audioDuration: TimeInterval?
    /// Name of a document the USER attached to this message (a picked PDF/CSV,
    /// or an oversized paste auto-converted to "Pasted"). Set on a fresh local
    /// send and re-derived on reload from the message's non-image asset —
    /// renders as a compact document tile above the text bubble, so a file-only
    /// send is never an invisible turn. Assistant deliveries use `.file` cards
    /// instead; this is nil for assistant messages.
    public let fileAttachmentName: String?
    /// The attached document's bytes while the send is still local (tapping the
    /// tile opens the content without a round-trip); nil on a reloaded bubble,
    /// which fetches from `fileAttachmentPath` instead.
    public let fileAttachmentData: Data?
    /// Backend path for the attached document ("/v1/assets/<id>"), carried
    /// through history so a reloaded tile can fetch + open the file. nil for a
    /// fresh send (which uses the local `fileAttachmentData`).
    public let fileAttachmentPath: String?
    /// Inline cards the agent surfaced this turn (a created task, an agenda, a
    /// draft, a tap-to-confirm payment…). Rendered read-only under the bubble.
    public let cards: [ChatCard]
    /// Set when this bubble is a finished deep-task's result posted into the main
    /// chat — the task's id, so the bubble can re-surface the task's card (unless
    /// one already shows just above — ChatScreen.taskCardRepeats).
    public let taskReferenceId: String?
    /// The message's real wall-clock instant (the backend `createdAt`), used to
    /// group the transcript into WhatsApp/iMessage-style day sections. `time` is
    /// a pre-formatted display label with no date, so this carries the calendar
    /// day. `nil` for surfaces that don't have a real date (a lightweight/live
    /// bubble that hasn't round-tripped) — such messages simply get no divider.
    public let date: Date?
    /// The message's role in a deep-task thread ("activity", "ask_user",
    /// "result", …) — `nil` for ordinary chat messages.
    public let kind: String?
    /// The tools an activity step ran (deep-task threads only; empty elsewhere).
    public let toolSteps: [ToolStep]
    /// iMessage-style receipts (user messages only). `deliveredAt`: the backend
    /// confirmed it persisted this message (proof the send really landed).
    /// `readAt`: the assistant actually consumed it — the only acknowledgment
    /// the user gets when the AI deliberately stays silent (no_reply).
    public let deliveredAt: Date?
    public let readAt: Date?
    /// The task a reminder FOLLOW-UP is chasing, for the kicker above the
    /// bubble ("REMINDER · walk the dog") — a nudge's prose is conversational
    /// and may not restate the task, and no card renders beside it anymore,
    /// so the kicker is the deterministic context. Nil on the initial fire
    /// (its bubble IS the task) and on every non-reminder message.
    public let reminderFollowUpTitle: String?

    /// True when this bubble should render as a voice note.
    public var isVoiceMessage: Bool { audioDuration != nil }

    /// Filename sentinel for composer text auto-folded into an attachment
    /// (an oversized paste). Both the pending chip and the sent tile key their
    /// clipboard styling off this name.
    public static let pastedAttachmentName = "Pasted"

    /// The wire stubs an ATTACHMENT-ONLY send carries: every send endpoint
    /// requires non-empty text, so a photo-alone (or file-alone) turn ships one
    /// of these instead. The bubble renders tile-/photo-only both locally and on
    /// reload — ChatMapper hides exactly these strings, which is why they live
    /// here, once, rather than in each surface that sends (the main chat, the
    /// task thread) and the mapper that has to recognize them.
    public static let photoOnlyPrompts = ["What's in this photo?", "What's in these photos?"]
    public static let fileOnlyPrompts = [
        "Read the attached file.",
        "Read the attached text.",
        "Read the attached file and look at the attached photo.",
        "Read the attached file and look at the attached photos.",
    ]

    /// The stub for a turn whose only content is what's attached.
    public static func attachmentOnlyPrompt(imageCount: Int, fileName: String?) -> String {
        let photoNoun = imageCount > 1 ? "photos" : "photo"
        guard let fileName else {
            return imageCount > 1 ? "What's in these photos?" : "What's in this photo?"
        }
        if imageCount > 0 { return "Read the attached file and look at the attached \(photoNoun)." }
        return fileName == pastedAttachmentName ? "Read the attached text." : "Read the attached file."
    }

    /// `kind` of the local-only "this turn failed" row. It renders as a quiet
    /// system notice with a Retry affordance instead of an assistant bubble,
    /// and it never exists server-side — any history reload drops it.
    public static let sendErrorKind = "send_error"
    public var isSendError: Bool { kind == Self.sendErrorKind }

    public init(
        id: UUID = UUID(),
        text: String,
        isUser: Bool,
        time: String,
        replyTo: ChatReplyReference? = nil,
        threadID: UUID? = nil,
        imageData: Data? = nil,
        imageDatas: [Data] = [],
        imageRemotePath: String? = nil,
        imageRemotePaths: [String] = [],
        audioURL: URL? = nil,
        audioRemotePath: String? = nil,
        audioDuration: TimeInterval? = nil,
        fileAttachmentName: String? = nil,
        fileAttachmentData: Data? = nil,
        fileAttachmentPath: String? = nil,
        cards: [ChatCard] = [],
        taskReferenceId: String? = nil,
        date: Date? = nil,
        kind: String? = nil,
        toolSteps: [ToolStep] = [],
        deliveredAt: Date? = nil,
        readAt: Date? = nil,
        reminderFollowUpTitle: String? = nil
    ) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.time = time
        self.replyTo = replyTo
        self.threadID = threadID
        // Same coalescing both ways as the remote-path pair below: a caller
        // that only knows one field still yields both a consistent list (the
        // views render from `imageDatas`) and a consistent single (the
        // has-photo checks read `imageData`).
        self.imageData = imageData ?? imageDatas.first
        self.imageDatas = imageDatas.isEmpty ? [imageData].compactMap(\.self) : imageDatas
        self.imageRemotePath = imageRemotePath
        // Callers that only know the single legacy field still yield a
        // consistent list — the views render from `imageRemotePaths`.
        self.imageRemotePaths = imageRemotePaths.isEmpty ? [imageRemotePath].compactMap(\.self) : imageRemotePaths
        self.audioURL = audioURL
        self.audioRemotePath = audioRemotePath
        self.audioDuration = audioDuration
        self.fileAttachmentName = fileAttachmentName
        self.fileAttachmentData = fileAttachmentData
        self.fileAttachmentPath = fileAttachmentPath
        self.cards = cards
        self.taskReferenceId = taskReferenceId
        self.date = date
        self.kind = kind
        self.toolSteps = toolSteps
        self.deliveredAt = deliveredAt
        self.readAt = readAt
        self.reminderFollowUpTitle = reminderFollowUpTitle
    }

    /// Returns a copy with only the given fields overridden; every other field is
    /// carried verbatim. This is the ONE place besides `init` that enumerates the
    /// full field list, so an in-place chat mutation can no longer silently drop a
    /// field it didn't mean to touch (a newly added field is preserved for free).
    /// A `nil` argument means "keep the current value" — these mutations only ever
    /// set fields, never clear them.
    public func with(
        text: String? = nil,
        replyTo: ChatReplyReference? = nil,
        imageRemotePaths: [String]? = nil,
        audioRemotePath: String? = nil,
        cards: [ChatCard]? = nil,
        deliveredAt: Date? = nil,
        readAt: Date? = nil
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            text: text ?? self.text,
            isUser: isUser,
            time: time,
            replyTo: replyTo ?? self.replyTo,
            threadID: threadID,
            imageData: imageData,
            imageDatas: imageDatas,
            imageRemotePath: imageRemotePath,
            imageRemotePaths: imageRemotePaths ?? self.imageRemotePaths,
            audioURL: audioURL,
            audioRemotePath: audioRemotePath ?? self.audioRemotePath,
            audioDuration: audioDuration,
            fileAttachmentName: fileAttachmentName,
            fileAttachmentData: fileAttachmentData,
            fileAttachmentPath: fileAttachmentPath,
            cards: cards ?? self.cards,
            taskReferenceId: taskReferenceId,
            date: date,
            kind: kind,
            toolSteps: toolSteps,
            deliveredAt: deliveredAt ?? self.deliveredAt,
            readAt: readAt ?? self.readAt,
            reminderFollowUpTitle: reminderFollowUpTitle
        )
    }
}

/// An inline card streamed by the agent during a chat turn. Most are read-only;
/// `selection` is interactive (tap an option to answer), and `delegation` is live
/// (tracks its background task). Confirm/pay flows aren't wired yet.
/// The live tool-phase state behind the chat loading indicator: the narrator
/// phrase plus optional icon identity (domain family / brand mark slug).
public struct LiveToolStatus: Equatable, Hashable, Sendable {
    public let label: String
    public let domain: String?
    public let brand: String?
    public let brandDomain: String?
    public init(label: String, domain: String? = nil, brand: String? = nil, brandDomain: String? = nil) {
        self.label = label
        self.domain = domain
        self.brand = brand
        self.brandDomain = brandDomain
    }
}

public enum ChatCard: Hashable, Sendable {
    /// Transient progress ("Looking that up…", "Drafting your reply…").
    /// Transient tool-phase progress pill. `domain`/`brand` identify the tool
    /// family behind the phrase so the loading indicator can show its icon
    /// ("Searching your mail…" + the Gmail mark). Nil on legacy cards.
    case status(label: String, domain: String?, brand: String?, brandDomain: String?)
    /// A created/standing task.
    case task(title: String, status: String)
    /// A fired reminder in the main chat. `status` is the server truth at load:
    /// "fired" renders live snooze/done buttons, "snoozed"/"done" render the
    /// settled state (stamped onto the persisted card server-side, like a
    /// draft's `sent`). `snoozedUntil` is ISO8601, display only. `embedded`
    /// marks the card riding a prose delivery (EVERY fire and nudge — the
    /// message text is the substance): the turn renders kicker + bubble + bare
    /// snooze/done actions, never the full notification card. The full card
    /// survives only as the defensive fallback for a prose-less message.
    case reminder(reminderId: String, title: String, status: String, snoozedUntil: String?, embedded: Bool)
    /// A standing automation as a first-class card — the proof-of-action for
    /// automation create/update, and the off state after a turn-off. Shows the
    /// compiled interpretation (trigger + instruction) and carries the real
    /// `automationId`, so the card's on/off toggle drives PATCH
    /// /v1/automations/:id live. `triggerSummary` is server-rendered prose
    /// ("Every Saturday at 9:00 AM") displayed verbatim; `action` is
    /// "agent" (background task) or "call_user" (phone call). `facts` are the
    /// server-built trigger-criteria pairs behind the tap-open detail;
    /// `lastRunError` is the short "latest run failed and here's why" note.
    /// `icon` is the server-chosen SF Symbol for the identity tile (template
    /// icon or trigger-kind fallback); nil on legacy cards → neutral glyph.
    case automation(
        automationId: String,
        icon: String?,
        category: String?,
        title: String,
        triggerSummary: String,
        instruction: String,
        action: String,
        enabled: Bool,
        nextFireAt: String?,
        lastRunError: String?,
        facts: [ToolRunFact]
    )
    /// A delegated background task (carries the live deep-task id).
    case delegation(taskId: String, goal: String, status: String)
    /// A composed mail draft. `sent` is true once it was sent (stamped onto the
    /// persisted card server-side), so a reloaded conversation shows "Sent"
    /// instead of a live Send button. `superseded` is stamped (same mechanism)
    /// when a NEWER draft replaced this one in the thread — the stale card then
    /// collapses so it can't be edited/sent above the current draft.
    case draft(
        draftId: String,
        accountId: String,
        subject: String,
        recipients: [String],
        cc: [String],
        bcc: [String],
        body: String,
        attachments: [String],
        sent: Bool,
        superseded: Bool
    )
    /// A read-only calendar day view.
    case agenda(title: String, entries: [AgendaEntry])
    /// The user's reminders as a card — the "what reminders do I have" answer
    /// as UI. Each row carries its real reminderId, so change-time/cancel row
    /// actions are live (same plumbing as the single reminder card).
    case reminderList(reminders: [ReminderListEntry])
    /// The user's standing automations as a card with live per-row toggles —
    /// each switch drives PATCH /v1/automations/:id (the same route Settings
    /// uses).
    case automationList(automations: [AutomationListEntry])
    /// The per-turn tool receipt — a quiet ledger of what the assistant's tool
    /// loop actually executed this turn ("Searched your mail ✓ · Created a
    /// calendar event ✓"). Built server-side from the real call ledger, never
    /// from model text, and persisted so the evidence survives reload.
    case toolRun(runs: [ToolRunEntry])
    /// A "pick one" list the user would tap to choose (rides, flights, tracks…).
    /// `brand` is the service's slug ("uber", "opentable", …, the ToolRunEntry
    /// vocabulary) so the card wears its logo — without it two same-shaped
    /// pickers from different services were indistinguishable.
    case selection(title: String, confirmVerb: String, options: [SelectionOption], brand: String?)
    /// A generic display-only payment chip (fallback for providers without a
    /// dedicated confirm flow).
    case payment(provider: String, summary: String, amountLabel: String?)
    /// A tap-to-confirm Soar flight booking. Tapping opens the confirm sheet which
    /// books the offer paid by a server-issued AgentCard virtual card.
    case soarBookingPayment(offerId: String, maxSpendCents: Int, currency: String, summary: String, resolved: String?)
    /// A tap-to-confirm DoorDash order. Tapping opens the confirm sheet which
    /// places the cart order paid by a server-issued AgentCard virtual card.
    /// `detail` carries the rich breakdown (real itemized lines + fee/tax split +
    /// store logo) when the backend supplied it; nil → the card shows the
    /// summary only.
    case doordashPayment(
        cartId: String,
        maxSpendCents: Int,
        storeName: String?,
        itemsSummary: String?,
        detail: DoordashPayDetail?,
        resolved: String?
    )

    /// A tap-to-approve GENERIC browser payment (a parking fine, a portal, any
    /// site). Tapping issues a single-use AgentCard virtual card capped to
    /// `amountCents`; the parked browser task then types it into the merchant's
    /// own payment form. `deepTaskId` ties the approval back to that task.
    case agentcardPayment(merchant: String, amountCents: Int, reason: String?, deepTaskId: String)

    /// The rich contents of a DoorDash pay card: the REAL cart, not a "1× Item"
    /// summary. Lines carry real names + prices; the fee split explains why a
    /// $0.39 lime becomes a $12 total.
    public struct DoordashPayDetail: Hashable, Sendable {
        public let lines: [PayLine]
        public let subtotalCents: Int?
        public let feesCents: Int?
        public let taxCents: Int?
        public let storeImageUrl: String?
        /// true = pickup order, false = delivery, nil = unknown (badge hidden).
        public let isPickup: Bool?
        /// Server-preformatted ETA ("25–35 min"); nil = unknown (the chip then
        /// falls back to the bare "Pickup"/"Delivery" word).
        public let etaLabel: String?
        /// Which rails the Pay sheet may charge, plus the preselected card.
        public let funding: Funding?
        public init(lines: [PayLine], subtotalCents: Int?, feesCents: Int?, taxCents: Int?, storeImageUrl: String?, isPickup: Bool? = nil, etaLabel: String? = nil, funding: Funding? = nil) {
            self.lines = lines
            self.subtotalCents = subtotalCents
            self.feesCents = feesCents
            self.taxCents = taxCents
            self.storeImageUrl = storeImageUrl
            self.isPickup = isPickup
            self.etaLabel = etaLabel
            self.funding = funding
        }

        /// Funding sources offered by the Pay sheet. The preselected card is
        /// carried inline so the sheet renders the right label with no fetch;
        /// the full picker list is loaded live when the user opens it, because a
        /// card list persisted into chat history goes stale.
        public struct Funding: Hashable, Sendable {
            public let agentcardAvailable: Bool
            public let cardOnFileAvailable: Bool
            public let defaultCard: Card?
            public init(agentcardAvailable: Bool, cardOnFileAvailable: Bool, defaultCard: Card?) {
                self.agentcardAvailable = agentcardAvailable
                self.cardOnFileAvailable = cardOnFileAvailable
                self.defaultCard = defaultCard
            }

            public struct Card: Hashable, Sendable {
                public let paymentMethodId: String
                public let cardId: String?
                public let brand: String
                public let last4: String
                /// This card has paid a DoorDash order before — the signal that
                /// it clears the risk gate a fresh virtual card trips.
                public let proven: Bool
                public init(paymentMethodId: String, cardId: String?, brand: String, last4: String, proven: Bool) {
                    self.paymentMethodId = paymentMethodId
                    self.cardId = cardId
                    self.brand = brand
                    self.last4 = last4
                    self.proven = proven
                }
            }
        }

        public struct PayLine: Hashable, Sendable, Identifiable {
            public let id = UUID()
            /// Cart LINE id (UUID) — carried since the pay card became the ONE
            /// editable order card: the edit sheet PATCHes/DELETEs by this id.
            /// nil on older persisted cards → the card renders read-only.
            public let lineId: String?
            public let name: String
            public let quantity: Int
            public let unitPriceCents: Int?
            /// Item photo URL when DoorDash carried one; nil → the line shows a
            /// neutral placeholder tile instead of a thumbnail.
            public let imageUrl: String?
            public init(lineId: String? = nil, name: String, quantity: Int, unitPriceCents: Int?, imageUrl: String? = nil) {
                self.lineId = lineId
                self.name = name
                self.quantity = quantity
                self.unitPriceCents = unitPriceCents
                self.imageUrl = imageUrl
            }
        }
    }

    /// A tap-to-confirm Amazon order — a "buy now" item or a cart checkout. The
    /// chat renders an "Order €X.XX" card; tapping it presents the confirm sheet
    /// which POSTs the carried MCP `tool` + opaque `args` to place the order on the
    /// user's own connected Amazon account. `argsJSON` carries the args object as a
    /// raw JSON string (the enum is Hashable and can't hold a free-form object); the
    /// sheet hands it back to the service, which re-parses it before placing.
    case amazonOrderConfirm(summary: String, totalCents: Int, currency: String, tool: String, argsJSON: String, resolved: String?)
    /// A "Place order on Uber Eats" card after the agent built the cart + previewed
    /// the total. Tapping it opens the REAL authenticated Uber Eats checkout for this
    /// draft in an in-app browser (cookies injected) — the user just taps Place order.
    /// We never handle payment.
    case uberEatsCheckout(draftOrderUuid: String, totalCents: Int, currency: String, storeName: String?)
    /// A tap-to-confirm Uber ride. The chat renders a "Book · €X" card; tapping
    /// it presents a confirm sheet that POSTs the chosen tier + trip coords to
    /// /v1/uber-rides/book, which re-quotes the live fare and books on the user's
    /// OWN Uber account (their payment profile) — no AgentCard.
    case uberRideConfirm(
        productName: String,
        fareCents: Int,
        currency: String,
        summary: String,
        pickupLat: Double,
        pickupLng: Double,
        dropoffLat: Double,
        dropoffLng: Double,
        // Server-stamped reload state ("booked") — a reloaded, already-booked
        // card renders the settled chip, never a live Book button.
        resolved: String?
    )
    /// A tap-to-confirm Lyft ride — same shape + card as uberRideConfirm; the
    /// sheet POSTs the tier + trip coords to /v1/lyft/book (re-quotes + books on
    /// the user's connected Lyft account, charging its default card).
    case lyftRideConfirm(
        productName: String,
        fareCents: Int,
        currency: String,
        summary: String,
        pickupLat: Double,
        pickupLng: Double,
        dropoffLat: Double,
        dropoffLng: Double,
        resolved: String?,
        /// Set once booked — the card hands off to the in-thread live tracker.
        rideId: String?
    )
    /// The Lyft ride PICKER: every tier for one trip, drawn with Lyft's own
    /// vehicle art, the upfront fare and the pickup ETA. Tapping a tier opens
    /// the confirm sheet directly, so choosing and booking is one gesture rather
    /// than a second agent turn. Once `rideId` is set the card renders the live
    /// tracker in its place.
    case lyftRideOptions(
        rides: [LyftRideOption],
        currency: String,
        pickupLat: Double,
        pickupLng: Double,
        dropoffLat: Double,
        dropoffLng: Double,
        resolved: String?,
        rideId: String?
    )
    /// A person card — name + relationship/detail + tappable call/message/email.
    /// The person's `imageURL` is their address-book photo when we have one
    /// (falls back to the initials disc); tapping the body opens the full
    /// Contacts-style detail sheet built from their `fields`.
    case profile(person: ContactPerson)
    /// SEVERAL people from one lookup, as ONE card — the address-book list, not
    /// N stacked person cards. Each row taps into the same detail sheet a single
    /// `profile` card opens.
    case contactGroup(title: String?, subtitle: String?, people: [ContactPerson])
    /// A generic collection of items rendered as a grid / list / carousel — the
    /// universal card behind rich integration results (Amazon products, Spotify
    /// recommendations, …). Each item carries an image, title, metadata badges
    /// (price/rating/…) and an OPTIONAL tap action (sends `item.action` verbatim,
    /// like a selection tap). Facts come from the backend's real tool data.
    /// `brand` is the service's slug ("uber-eats", "doordash", …) so the card
    /// wears its logo — a DoorDash and an Uber Eats result list were identical
    /// without it.
    case collection(title: String?, subtitle: String?, layout: CollectionLayout, brand: String?, items: [CollectionItem])
    /// A tappable "Connect <X>" card the agent surfaces mid-chat when a task needs
    /// an integration the user hasn't linked yet. Tapping it opens that
    /// integration's real connect flow in context (`slug` routes to the sheet /
    /// OAuth), so the user never has to hunt through Settings. `logoDomain` drives
    /// the brand logo (logo.dev) — the same iconography as the Settings Apps rows.
    /// `domain` is set on `site` cards only: the website the in-app browser login
    /// opens ("Sign in to alibaba.com" → "alibaba.com").
    case connect(slug: String, title: String, subtitle: String?, logoDomain: String?, domain: String?)
    /// A live phone call iris is placing — the card streams the call's status +
    /// two-sided transcript (SSE), and taps open the full live view.
    case voiceCall(voiceCallId: String, phone: String, mission: String)
    /// The notetaker bot's presence in a meeting — the "is it in there or not"
    /// proof for join/leave/active-meeting turns. `status` mirrors the server
    /// recording row ("requested"/"joining"/"active"/"completed"/"failed"/
    /// "left"); the card polls GET /v1/meetings/:id while live so "Joining…"
    /// flips to "In the meeting" (or the settled state) without a reload, and
    /// its Leave button drives POST /v1/meetings/:id/leave. Timestamps are
    /// ISO8601, display only (elapsed/duration labels).
    case meeting(
        recordingId: String,
        meetingCode: String,
        meetingUrl: String?,
        status: String,
        botName: String?,
        failureReason: String?,
        startedAt: String?,
        endedAt: String?,
        title: String?,
        /// What became of the recap: "pending" (still working, or a card
        /// persisted before this existed), "ready", "failed", "none". The
        /// settled row used to promise "recap in your chat" unconditionally,
        /// which was a lie whenever the transcript came back empty.
        recapState: String
    )
    /// The FINISHED meeting recap — a different card from the presence one
    /// above, and the one that survives in the transcript afterwards. It is
    /// deliberately thin (headline, duration, follow-up count): tapping it opens
    /// the recap page, which loads the body from GET /v1/meetings/:id/recap
    /// rather than shipping an hour of notes inside every chat transcript load.
    case meetingRecap(
        recordingId: String,
        title: String?,
        headline: String?,
        actionItemCount: Int,
        startedAt: String?,
        endedAt: String?
    )
    /// A reference to a specific received email, attached to messages that are
    /// ABOUT a mail (e.g. the proactive heads-up in the main chat). Renders as
    /// a tappable mail chip: open the mail (provider web link when present,
    /// otherwise ask the agent to show it via the structured ref) plus an
    /// optional suggested-next-step chip the client localizes.
    case mailRef(
        accountId: String,
        threadId: String,
        messageId: String,
        subject: String?,
        from: String?,
        fromAddress: String?,
        webUrl: String?,
        suggestedAction: MailRefSuggestedAction?
    )
    /// A received email displayed ON REQUEST — the "pull up that email" answer
    /// as UI (mail_display). Distinct from `mailRef` by role: the chip is a
    /// citation under a heads-up bubble, this card IS the content — sender
    /// avatar, subject, preview, time; tapping opens the in-app thread viewer.
    case email(
        accountId: String,
        threadId: String,
        messageId: String,
        subject: String?,
        from: String?,
        fromAddress: String?,
        snippet: String?,
        receivedAt: String?,
        unread: Bool,
        messageCount: Int,
        hasAttachments: Bool,
        webUrl: String?
    )
    /// A file the agent produced and delivered from its sandbox (a rendered PDF,
    /// a generated CSV, an exported image). Renders as a tappable file chip;
    /// tapping fetches the bytes from `url` (auth-scoped) and opens an in-app
    /// QuickLook preview. `url` is a path relative to the API base.
    case file(fileId: String, filename: String, mimeType: String, sizeBytes: Int, url: String)
    /// An iMessage-style rich link preview (show_link) — page image on top, a
    /// grey band with title + domain below. Every fact was unfurled server-side
    /// from the real page, never model text. Tapping opens `url`; no `imageURL`
    /// → the compact favicon row. `above` keeps the message's reading order:
    /// true when the URL LED its text (the preview renders before the bubble).
    case linkPreview(url: String, title: String?, siteName: String?, imageURL: String?, domain: String, above: Bool)
    /// An itemized shopping cart (DoorDash / Uber Eats) — the "here's your cart"
    /// view. Each line carries its removable id so a swipe/remove sends the exact
    /// item back to the agent. Display + light edit; checkout stays on the pay card.
    case cart(provider: String, cartId: String, storeName: String?, storeImageUrl: String?, lines: [CartLine], subtotalCents: Int?, currency: String)
    /// A confirm-before-send card for a WhatsApp message to a NEW contact — one
    /// the user has no existing conversation with. The agent tool surfaces this
    /// instead of sending; the card shows the recipient (a phone number, since a
    /// new contact isn't in the chat list yet) + the exact text, and the user's
    /// Send tap POSTs /v1/whatsapp/send with allowNewContact:true. Known-contact
    /// sends never render a card, so this always represents a new contact.
    case whatsappSend(
        chatJid: String,
        text: String,
        contactLabel: String,
        isNewContact: Bool,
        assetId: String?,
        attachmentName: String?,
        sent: Bool
    )
    /// A ready-to-send draft the USER sends from their own phone — the compose
    /// hand-off ("text design I'm running late", compose_imessage /
    /// compose_whatsapp). Shows the recipient + the exact text; the button
    /// opens the phone's own app via `url` (sms:…&body=… for Messages, wa.me
    /// for WhatsApp) with everything pre-filled, so the send goes out from the
    /// user's own number/account. `channel` ("imessage" | "whatsapp") only
    /// picks the icon + button label — the URL is server-built so the client
    /// stays a dumb opener, same doctrine as the contact card's tel:/sms:
    /// actions. Opening the app is idempotent (nothing sends until the user
    /// taps send there), so no `sent` stamp exists.
    /// iMessage channel prefers the in-app Messages compose sheet (MessageUI)
    /// over the sms: deep link — the sheet is what carries the attachment (a
    /// stored file: auth-scoped download URL + display name + optional mime
    /// for UTI inference), which the URL scheme cannot.
    case messageCompose(
        channel: String,
        contactName: String,
        phone: String,
        text: String,
        url: String,
        initials: String?,
        imageURL: String?,
        attachmentUrl: String?,
        attachmentName: String?,
        attachmentMime: String?
    )
    /// ONE of the assistant's own settings as its own EDITABLE in-chat card —
    /// emitted by the assistant_settings tool (proof-of-change + live control).
    /// `field` is the setting this card OWNS and draws; every card still carries
    /// the full state because the REST routes stamp persisted cards by KIND, and
    /// a partial payload would drift the moment one got restamped. `field` nil =
    /// a pre-split combined panel in an older transcript, drawn as the stack of
    /// all four. `tone` is the register id ("very_casual" | "casual" | "formal");
    /// `appearance` is "light"/"dark"/"system" or nil (backend never synced — the
    /// client shows its local pick); `changed` lists the fields THIS call changed
    /// (the live stream applies an appearance change to the device theme the
    /// moment the card lands — a merely SHOWN card changes nothing).
    case assistantSettings(
        field: AssistantSettingField?,
        assistantName: String,
        userNickname: String?,
        tone: String,
        appearance: String?,
        changed: [String]
    )
    /// Search hits over past chat conversations + background agents (the
    /// history_search tool). Each row deep-links: a chat row opens the history
    /// thread overlay, an agent row opens the task thread.
    case historyResults(query: String, results: [HistoryResultEntry])
    /// A one-way device-permission ask: one enable button, no revoke state.
    /// The backend attaches it when a tool's work was blocked by the missing
    /// grant; the device-permissions report restamps it to granted, at which
    /// point it renders as a settled checkmark. Nothing ever renders a
    /// disable affordance for it — by design.
    case permissionRequest(scope: PermissionScope, granted: Bool)
    /// THE CONFIRM CARD — engine v2's authority surface, and the only card in
    /// this enum a tap on which IS authority rather than a message back to the
    /// agent. A gated or destructive engine call never runs on a model tool
    /// call alone: it mints a proposal and stops, and this card is the only
    /// way one ever executes. See EngineConfirm.swift.
    case engineConfirm(proposal: EngineProposalCard)
    /// The v2 PROPOSAL card (design pass): the approval/denial
    /// surface for a gated or destructive engine call, composed from the
    /// shared chat-card primitives. Carries the host-normalized entities the
    /// approval would execute, in reading order. See ProposalCardView.swift.
    case proposal(ProposalCardModel)
    /// The v2 `mail-list` display kind: several inbox matches as ONE card of
    /// hairline rows, folding past the first few.
    case mailList(title: String?, total: Int, entries: [MailListEntry])
    /// The v2 `file-list` display kind: several files as ONE card of stacked
    /// hairline rows, folding past the first few.
    case fileList(title: String?, files: [FileListEntry])
    /// An unrecognized card kind — a neutral chip so nothing is silently dropped.
    case unknown(kind: String)

    /// The four assistant settings, one editable card each, in the order they
    /// lay out in the chat: who it is, what it calls you, how it talks, how the
    /// app looks. Raw values match the backend's `field`.
    public enum AssistantSettingField: String, Hashable, Sendable, CaseIterable, Identifiable {
        case assistantName, userNickname, tone, appearance
        public var id: String { rawValue }
    }

    /// The permission scopes a `permissionRequest` card can ask for. Raw
    /// values match the backend card's `scope` AND the existing
    /// `HomeStore.requestPermission(scope:)` strings — one vocabulary.
    public enum PermissionScope: String, Hashable, Sendable {
        case notifications
        case locationWhenInUse = "location_when_in_use"
        case locationAlways = "location_always"
        case contacts
    }

    /// One row of a `historyResults` card. `id` is the chat thread id (kind
    /// .chat) or the deep-task id (kind .agent); `lastActiveAt` is ISO8601,
    /// display only; `status` is the agent's status word (nil on chat rows).
    public struct HistoryResultEntry: Hashable, Sendable, Identifiable {
        public enum Kind: String, Hashable, Sendable { case chat, agent }
        public let id: String
        public let kind: Kind
        public let title: String
        public let subtitle: String?
        public let lastActiveAt: String?
        public let status: String?
        public init(id: String, kind: Kind, title: String, subtitle: String? = nil, lastActiveAt: String? = nil, status: String? = nil) {
            self.id = id
            self.kind = kind
            self.title = title
            self.subtitle = subtitle
            self.lastActiveAt = lastActiveAt
            self.status = status
        }
    }

    /// One inbox row of a `mailList` card. Ids ride along so a row can open
    /// the in-app thread viewer (the mail-chip contract).
    public struct MailListEntry: Hashable, Sendable, Identifiable {
        public let accountId: String
        public let threadId: String
        public let messageId: String
        public let from: String
        public let fromAddress: String?
        public let subject: String
        public let receivedAt: String?
        public let unread: Bool
        public let hasAttachments: Bool
        public var id: String { "\(accountId)/\(threadId)/\(messageId)" }
        public init(
            accountId: String,
            threadId: String,
            messageId: String,
            from: String,
            fromAddress: String? = nil,
            subject: String,
            receivedAt: String? = nil,
            unread: Bool = false,
            hasAttachments: Bool = false
        ) {
            self.accountId = accountId
            self.threadId = threadId
            self.messageId = messageId
            self.from = from
            self.fromAddress = fromAddress
            self.subject = subject
            self.receivedAt = receivedAt
            self.unread = unread
            self.hasAttachments = hasAttachments
        }
    }

    /// One row of a `fileList` card; the same fields the single `file` card
    /// carries, so a row can open the same QuickLook path.
    public struct FileListEntry: Hashable, Sendable, Identifiable {
        public let fileId: String
        public let filename: String
        public let mimeType: String
        public let sizeBytes: Int
        public let url: String
        public var id: String { fileId }
        public init(fileId: String, filename: String, mimeType: String, sizeBytes: Int, url: String) {
            self.fileId = fileId
            self.filename = filename
            self.mimeType = mimeType
            self.sizeBytes = sizeBytes
            self.url = url
        }
    }

    /// Card placement relative to the assistant's message text.
    ///
    /// DEFAULT (false → renders ABOVE the text): the "generative" chatCardPanel
    /// family — collection, draft, file/QuickLook, selection, profile, agenda,
    /// cart, status/task/delegation, connect, voiceCall, unknown. The card is
    /// the substance; the text is a lead-in caption beneath it.
    ///
    /// EXCEPTION (true → stays BELOW/after the text):
    /// - confirmation-gated elements that CONCLUDE an action — payment/checkout
    /// confirms and approve/deny UI — so the user reads the consequence in the
    /// text BEFORE the commit control. `.doordashPayment` LEFT this group
    /// (): it is now the ONE order card — the itemized editable
    /// cart with the Review-order button on it — so the card is the
    /// consequence display itself and the text is a caption under it;
    /// - mail reference chips — the message TEXT is the substance (the heads-up
    /// itself) and the chip is its citation/affordance, so it reads as a
    /// footer under the message, not a header above it;
    /// - link previews — same reading order as iMessage: the prose introduces
    /// the link ("found that article"), then the preview follows it — EXCEPT
    /// when the URL led its message (`above`), where the preview reads first;
    /// - embedded reminder cards — same shape as mailRef: the delivery prose
    /// is the substance, the card is just its snooze/done affordance
    /// (ChatRow renders it under the bubble, outside the card stacks).
    public var rendersBelowText: Bool {
        switch self {
        case .payment, .soarBookingPayment, .agentcardPayment,
             .amazonOrderConfirm, .uberEatsCheckout, .uberRideConfirm, .lyftRideConfirm, .whatsappSend,
             .messageCompose, .mailRef,
             // The confirm card is the canonical member of the first group in
             // the doc above — approve/deny UI that CONCLUDES an action. The
             // agent's sentence ("drafted that to Dana — want me to send it?")
             // has to be read before the commit control, not after it.
             .engineConfirm, .proposal:
            true
        case let .linkPreview(_, _, _, _, _, above):
            !above
        case let .reminder(_, _, _, _, embedded):
            embedded
        default:
            false
        }
    }

    /// Suggested next step riding on a `mailRef` card — an enum (not free
    /// text) so the chip label is localized client-side, language-neutrally.
    public enum MailRefSuggestedAction: String, Hashable, Sendable {
        case reply, link
    }

    public enum CollectionLayout: String, Hashable, Sendable {
        case grid, list, carousel
    }

    /// What a receipt row's step ACTUALLY did. `ok` alone cannot say it: a
    /// step that minted a confirmation, or that the send lock held, RAN
    /// NOTHING — neither a success nor a failure — and drawing either one as a
    /// tick is the overclaim the receipt exists to prevent.
    ///
    /// `attention` is the middle band: the step is real and finished, but the
    /// thing the user cares about has not happened yet. It reads amber, and it
    /// is never counted as "failed".
    public enum ToolRunOutcome: Hashable, Sendable {
        /// The executor ran and succeeded. The only state `ok` is true for.
        case done
        /// The executor ran and failed.
        case failed
        /// Nothing ran, and it is not a failure — waiting on the user, held
        /// by the send lock, declined, refused, or bounced back to the model.
        case attention
    }

    /// One executed tool in the per-turn receipt (`.toolRun`).
    public struct ToolRunEntry: Hashable, Sendable, Identifiable {
        public let id: String
        /// Past-tense human label ("Searched your mail").
        public let label: String
        public let ok: Bool
        /// The server's one-word state, when it sends one ("done", "failed",
        /// "awaiting", "not-sent", "declined", "refused", "bounced"). Prod's
        /// tool loop sends nil and the boolean decides; engine v2 always sends
        /// it. Kept as the raw string so a word this build has never heard of
        /// degrades through `outcome` instead of failing to decode.
        public let state: String?
        /// Icon family (mail | calendar | reminder | phone | sms | contacts |
        /// food | ride | music | web | docs | payment | task | other).
        public let domain: String
        /// Brand slug when a bundled mark exists ("gmail", "doordash", …).
        public let brand: String?
        /// Consumer brand domain for a mark we do NOT bundle ("notion.so",
        /// "slack.com") — rendered through logo.dev. The server sends it only
        /// when the service has a real recognizable mark, so nil means "draw the
        /// domain symbol", never "go looking".
        public let brandDomain: String?
        /// Short user-safe failure note, only when ok == false.
        public let error: String?
        /// Plain-language facts behind the row ("Searched for — dentist
        /// invoice", "Account — all connected accounts") — the tap-open detail
        /// sheet. Built server-side from the call's own args; empty when the
        /// call had nothing user-meaningful to show.
        public let details: [ToolRunFact]

        /// The row's outcome, resolved once so every surface agrees.
        ///
        /// Unknown or absent `state` falls back to the boolean — which is what
        /// keeps an older server (and prod's own loop) rendering exactly as it
        /// does today. It also means the fallback can never invent a success:
        /// the server sets `ok` true for `done` alone, so a state this build
        /// does not recognise lands in `failed`, not in `done`.
        public var outcome: ToolRunOutcome {
            switch state {
            case "done": return .done
            case "failed": return .failed
            case "awaiting", "not-sent", "declined", "refused", "bounced": return .attention
            default: return ok ? .done : .failed
            }
        }

        public init(
            id: String,
            label: String,
            ok: Bool,
            state: String? = nil,
            domain: String,
            brand: String? = nil,
            brandDomain: String? = nil,
            error: String? = nil,
            details: [ToolRunFact] = []
        ) {
            self.id = id
            self.label = label
            self.ok = ok
            self.state = state
            self.domain = domain
            self.brand = brand
            self.brandDomain = brandDomain
            self.error = error
            self.details = details
        }
    }

    /// One label/value fact in a receipt row's tap-open detail sheet.
    public struct ToolRunFact: Hashable, Sendable, Identifiable {
        public let label: String
        public let value: String
        public var id: String { "\(label)\u{1F}\(value)" }
        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    public struct AgendaEntry: Hashable, Sendable {
        public let time: String
        /// Optional end time ("10:15") shown under the start in the card.
        public let endTime: String?
        public let title: String
        public let subtitle: String?
        /// Legacy colour name — no longer rendered (the calendar card is
        /// monochrome), kept so persisted cards keep decoding.
        public let accent: String?
        /// The event's day ("", user-tz) — multi-day payloads group
        /// into day sections by it. Absent on legacy cards (heuristic fallback).
        public let date: String?
        /// Where the event lives ("Google", "Outlook", "iCloud", …) — shown as
        /// a small trailing badge. Absent on legacy cards.
        public let source: String?
        /// The event's calendar colour ("#RRGGBB", per-event override
        /// winning) — the row's dot, matching the browse sheet's. Absent on
        /// legacy cards → no dot.
        public let colorHex: String?
        /// True when a video-conference link is attached — small camera glyph.
        public let meet: Bool?
        /// Attendee display names; the single-event card's Attendees field
        /// (v2 calendar-events). Empty on legacy cards and list rows.
        public let attendees: [String]
        public init(
            time: String,
            title: String,
            subtitle: String?,
            endTime: String? = nil,
            accent: String? = nil,
            date: String? = nil,
            source: String? = nil,
            colorHex: String? = nil,
            meet: Bool? = nil,
            attendees: [String] = []
        ) {
            self.time = time
            self.endTime = endTime
            self.accent = accent
            self.date = date
            self.source = source
            self.colorHex = colorHex
            self.meet = meet
            self.attendees = attendees
            self.title = title
            self.subtitle = subtitle
        }
    }

    /// One row of a `reminderList` card. `fireAt` is the next fire instant
    /// (ISO8601); `firedAt` is set only on recently-fired rows, which render
    /// as a settled line with no live actions.
    public struct ReminderListEntry: Hashable, Sendable, Identifiable {
        public let reminderId: String
        public let title: String
        public let fireAt: String
        /// "pending" (live actions) or "fired" (settled).
        public let status: String
        public let recurrence: String?
        /// Location-trigger label ("home") when the reminder fires on arrival;
        /// `fireAt` is then the fallback deadline.
        public let place: String?
        /// An acting reminder: a background task runs the content at fire time.
        public let startsTask: Bool
        public let firedAt: String?
        /// Pending recurring rows: when the series last fired (the newest
        /// fired occurrence's instant).
        public let lastFiredAt: String?
        public var id: String { reminderId + status }
        public init(
            reminderId: String,
            title: String,
            fireAt: String,
            status: String,
            recurrence: String? = nil,
            place: String? = nil,
            startsTask: Bool = false,
            firedAt: String? = nil,
            lastFiredAt: String? = nil
        ) {
            self.reminderId = reminderId
            self.title = title
            self.fireAt = fireAt
            self.status = status
            self.recurrence = recurrence
            self.place = place
            self.startsTask = startsTask
            self.firedAt = firedAt
            self.lastFiredAt = lastFiredAt
        }
    }

    /// One row of an `automationList` card. `triggerSummary` is server-rendered
    /// prose, displayed verbatim.
    public struct AutomationListEntry: Hashable, Sendable, Identifiable {
        public let automationId: String
        /// SF Symbol for the row's icon tile; nil on legacy rows → neutral glyph.
        public let icon: String?
        /// Template category label ("Mail", "Money", …) — tints the icon tile
        /// like the Settings automations page; nil (custom rules) → neutral tile.
        public let category: String?
        public let title: String
        public let triggerSummary: String
        public let enabled: Bool
        /// Why a disabled automation is off ("user" | "failures" | "completed");
        /// "failures" renders a caution note.
        public let disabledReason: String?
        public let nextFireAt: String?
        public let lastFiredAt: String?
        /// What the row runs — shown in the drill-in detail.
        public let instruction: String?
        /// Short note when the LATEST run failed — the row's visible "broken
        /// and here's why" line, independent of the enabled state.
        public let lastRunError: String?
        /// Server-built trigger-criteria + run-state pairs for the drill-in.
        public let facts: [ToolRunFact]
        public var id: String { automationId }
        public init(
            automationId: String,
            icon: String? = nil,
            category: String? = nil,
            title: String,
            triggerSummary: String,
            enabled: Bool,
            disabledReason: String? = nil,
            nextFireAt: String? = nil,
            lastFiredAt: String? = nil,
            instruction: String? = nil,
            lastRunError: String? = nil,
            facts: [ToolRunFact] = []
        ) {
            self.automationId = automationId
            self.icon = icon
            self.category = category
            self.title = title
            self.triggerSummary = triggerSummary
            self.enabled = enabled
            self.disabledReason = disabledReason
            self.nextFireAt = nextFireAt
            self.lastFiredAt = lastFiredAt
            self.instruction = instruction
            self.lastRunError = lastRunError
            self.facts = facts
        }
    }

    /// One Lyft tier in a `lyftRideOptions` card. Everything here comes from
    /// Lyft's own offer: the name and blurb they show, the upfront fare, the
    /// pickup ETA, and their vehicle art for both appearances (`imageURL` is
    /// light, `imageURLDark` dark — the row car; `hero…` is the large one the
    /// confirm surface uses).
    public struct LyftRideOption: Hashable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let description: String?
        public let fareCents: Int
        public let fareDisplay: String?
        public let etaMinutes: Int?
        public let seats: Int?
        public let imageURL: String?
        public let imageURLDark: String?
        public let heroImageURL: String?
        public let heroImageURLDark: String?
        /// Lyft's own grouping ("Recommended", "Economy", "Luxury", …).
        public let category: String?
        public let recommended: Bool
        public let preselected: Bool
        public init(
            id: String,
            name: String,
            fareCents: Int,
            description: String? = nil,
            fareDisplay: String? = nil,
            etaMinutes: Int? = nil,
            seats: Int? = nil,
            imageURL: String? = nil,
            imageURLDark: String? = nil,
            heroImageURL: String? = nil,
            heroImageURLDark: String? = nil,
            category: String? = nil,
            recommended: Bool = false,
            preselected: Bool = false
        ) {
            self.id = id
            self.name = name
            self.description = description
            self.fareCents = fareCents
            self.fareDisplay = fareDisplay
            self.etaMinutes = etaMinutes
            self.seats = seats
            self.imageURL = imageURL
            self.imageURLDark = imageURLDark
            self.heroImageURL = heroImageURL
            self.heroImageURLDark = heroImageURLDark
            self.category = category
            self.recommended = recommended
            self.preselected = preselected
        }
    }

    /// One choice in a `selection` card. `title`/`detail` are for display; `value`
    /// is the EXACT text sent back when tapped. The backend resolves a pick by
    /// matching `"<confirmVerb> <title>"` to an offer, so `value` must carry that
    /// verbatim — never the composed display string.
    public struct SelectionOption: Hashable, Sendable {
        public let title: String
        public let subtitle: String?
        public let detail: String?
        public let trailing: String?
        public let imageURL: String?
        public let systemImage: String?
        /// true = transparent illustration (e.g. a car PNG) shown .fit on a tint;
        /// false/photo = a real photo shown .fill.
        public let illustration: Bool
        public let value: String
        /// Structured flight facts — present ⇒ the transcript renders the
        /// dedicated flight row instead of the generic title/subtitle strings
        /// (same opt-in pattern as `place` on collection items). The tap still
        /// sends `value` verbatim either way.
        public let flight: FlightInfo?
        public init(
            title: String,
            detail: String?,
            value: String,
            subtitle: String? = nil,
            trailing: String? = nil,
            imageURL: String? = nil,
            systemImage: String? = nil,
            illustration: Bool = false,
            flight: FlightInfo? = nil
        ) {
            self.title = title
            self.subtitle = subtitle
            self.detail = detail
            self.trailing = trailing
            self.imageURL = imageURL
            self.systemImage = systemImage
            self.illustration = illustration
            self.value = value
            self.flight = flight
        }

        /// One flight leg — outbound, plus the return on a round trip.
        public struct FlightLeg: Hashable, Sendable {
            public let dep: String // "7:15 AM"
            public let arr: String // "4:37 PM"
            /// Small muted suffix after the arrival time: arrival tz when it
            /// differs + a next-day marker ("EST +1").
            public let arrSuffix: String?
            public let duration: String? // "6h 22m"
            public let stops: Int?
            /// Airport pair for the detail sheet: "SFO → JFK".
            public let route: String?
            /// Human departure day for the detail sheet: "Wed, Aug 12".
            public let date: String?
            /// Operating flight codes: "UA 123 → UA 456".
            public let flights: String?
            public init(
                dep: String,
                arr: String,
                arrSuffix: String? = nil,
                duration: String? = nil,
                stops: Int? = nil,
                route: String? = nil,
                date: String? = nil,
                flights: String? = nil
            ) {
                self.dep = dep
                self.arr = arr
                self.arrSuffix = arrSuffix
                self.duration = duration
                self.stops = stops
                self.route = route
                self.date = date
                self.flights = flights
            }
        }

        public struct FlightInfo: Hashable, Sendable {
            public let carrier: String
            public let fare: String? // "Blue Basic" / "Business"
            public let refundable: Bool
            public let legs: [FlightLeg]
            /// Cabin when the fare is a branded name: "Economy".
            public let cabin: String?
            /// Changes allowed per the offer's conditions (detail sheet only).
            public let changeable: Bool?
            /// Exact fare with cents ("$228.38") — the row shows the rounded
            /// trailing price.
            public let priceExact: String?
            /// Web fallback for this search (Google Flights, route + dates).
            public let url: String?
            public init(
                carrier: String,
                fare: String? = nil,
                refundable: Bool = false,
                legs: [FlightLeg],
                cabin: String? = nil,
                changeable: Bool? = nil,
                priceExact: String? = nil,
                url: String? = nil
            ) {
                self.carrier = carrier
                self.fare = fare
                self.refundable = refundable
                self.legs = legs
                self.cabin = cabin
                self.changeable = changeable
                self.priceExact = priceExact
                self.url = url
            }
        }
    }

    public struct ProfileAction: Hashable, Sendable {
        public let label: String
        public let systemImage: String
        /// A tel:/sms:/mailto: URL the app opens directly.
        public let value: String
        public init(label: String, systemImage: String, value: String) {
            self.label = label
            self.systemImage = systemImage
            self.value = value
        }
    }

    /// One line of a contact's address book — a single number or address under
    /// the label the user filed it as ("mobile", "work"), the way the Contacts
    /// app lists them. The card face shows only the quick actions; this is the
    /// full list behind the tap.
    public struct ContactField: Hashable, Sendable, Identifiable {
        public enum Kind: String, Hashable, Sendable {
            case phone, email
        }

        public var id: String { "\(kind.rawValue):\(value)" }
        /// The user's own filing: "mobile", "work", "home".
        public let label: String
        /// The handle as the user reads it: "+1 (415) 555-0123", "a@b.com".
        public let value: String
        public let kind: Kind
        /// tel:/sms:/mailto: URL the row opens on tap.
        public let actionValue: String
        public init(label: String, value: String, kind: Kind, actionValue: String) {
            self.label = label
            self.value = value
            self.kind = kind
            self.actionValue = actionValue
        }
    }

    /// One person on a contact card — carried IDENTICALLY by the single-person
    /// `profile` card and by every row of a `contactGroup`, so a row and a card
    /// open the same detail sheet with the same facts.
    public struct ContactPerson: Hashable, Sendable, Identifiable {
        /// Stable within a card (name + primary handle) — good enough to key a
        /// ForEach and to re-present a sheet for the same person.
        public var id: String { "\(name)|\(detail ?? "")" }
        public let name: String
        /// Org / relationship, else their primary handle.
        public let detail: String?
        /// Their address-book photo (contact_photos), nil → initials disc.
        public let imageURL: String?
        public let initials: String
        /// Quick actions on the primary handle — the chips on the card face.
        public let actions: [ProfileAction]
        /// Every number and address, labelled. Empty for a contact we only know
        /// by name (an unreachable address-book entry).
        public let fields: [ContactField]

        /// Their primary address — the avatar's Gravatar/brand-logo fallback
        /// input when we hold no stored photo. Read from `fields` first (the
        /// full labelled list), else parsed out of the mailto: quick action, so
        /// an older persisted card without fields still resolves a face.
        public var primaryEmail: String? {
            if let field = fields.first(where: { $0.kind == .email }) { return field.value }
            guard let action = actions.first(where: { $0.value.hasPrefix("mailto:") }) else { return nil }
            let raw = String(action.value.dropFirst("mailto:".count))
            // Drop any ?subject=… query — only the address is a lookup key.
            let addr = raw.split(separator: "?", maxSplits: 1).first.map(String.init) ?? raw
            let decoded = addr.removingPercentEncoding ?? addr
            return decoded.isEmpty ? nil : decoded
        }

        /// Every address on the card — the local address-book lookup matches on
        /// ANY of them, since a card row can lead with a secondary handle.
        public var emailHandles: [String] {
            var out = fields.filter { $0.kind == .email }.map(\.value)
            if out.isEmpty, let primary = primaryEmail { out = [primary] }
            return out
        }

        /// Every number on the card, from the labelled fields else the tel:
        /// quick action (which is all an older persisted card carries).
        public var phoneHandles: [String] {
            let fromFields = fields.filter { $0.kind == .phone }.map(\.value)
            if !fromFields.isEmpty { return fromFields }
            guard let action = actions.first(where: { $0.value.hasPrefix("tel:") }) else { return [] }
            let raw = String(action.value.dropFirst("tel:".count))
            let decoded = raw.removingPercentEncoding ?? raw
            return decoded.isEmpty ? [] : [decoded]
        }

        public init(
            name: String,
            detail: String?,
            imageURL: String?,
            initials: String,
            actions: [ProfileAction],
            fields: [ContactField] = []
        ) {
            self.name = name
            self.detail = detail
            self.imageURL = imageURL
            self.initials = initials
            self.actions = actions
            self.fields = fields
        }
    }

    /// A small labelled chip on a collection item (a price, rating, "Prime", …).
    /// `tone` is a styling hint mapped to a colour in the view.
    public struct CollectionBadge: Hashable, Sendable {
        public enum Tone: String, Hashable, Sendable {
            case `default`, price, rating, accent, positive
        }

        public let text: String
        public let systemImage: String?
        public let tone: Tone
        public init(text: String, systemImage: String? = nil, tone: Tone = .default) {
            self.text = text
            self.systemImage = systemImage
            self.tone = tone
        }
    }

    /// One item in a `collection` card. Generic by design so it backs products,
    /// tracks, places, etc. `action` is the text sent back verbatim when tapped
    /// (same contract as a selection tap); nil = a pure-display item.
    public struct CollectionItem: Hashable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let subtitle: String?
        public let detail: String?
        public let imageURL: String?
        public let systemImage: String?
        public let illustration: Bool
        public let badges: [CollectionBadge]
        public let action: String?
        /// Rich Google-Maps place detail (from Serper). When present, tapping the
        /// item opens PlaceDetailView instead of sending `action` as a follow-up.
        public let place: PlaceInfo?
        /// A query the client can use to LAZILY enrich this item into a full
        /// `place` on tap (via /v1/places/lookup) — for thin cards (Uber Eats /
        /// DoorDash restaurants carry only a name + photo).
        public let placeLookup: String?
        /// Structured store-row facts on food cards (rating, review count, ETA,
        /// delivery fee) — typeset like the delivery apps. When present it wins
        /// over `subtitle` (which carries the joined string for old clients).
        public let foodMeta: FoodMeta?
        /// Menu items the search matched at this store ("Tiramisu $8.50"),
        /// query hits first — the caption line under a store row.
        public let menuPreview: [String]
        /// Direct-order ids for a menu-item row: the "+" tap adds this item to
        /// the provider cart itself (ConnectService.foodCartAdd) instead of
        /// bouncing an "Add X (storeId…)" message through the chat.
        public let orderRef: OrderRef?
        public init(
            id: String,
            title: String,
            subtitle: String? = nil,
            detail: String? = nil,
            imageURL: String? = nil,
            systemImage: String? = nil,
            illustration: Bool = false,
            badges: [CollectionBadge] = [],
            action: String? = nil,
            place: PlaceInfo? = nil,
            placeLookup: String? = nil,
            foodMeta: FoodMeta? = nil,
            menuPreview: [String] = [],
            orderRef: OrderRef? = nil
        ) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.detail = detail
            self.imageURL = imageURL
            self.systemImage = systemImage
            self.illustration = illustration
            self.badges = badges
            self.action = action
            self.place = place
            self.placeLookup = placeLookup
            self.foodMeta = foodMeta
            self.menuPreview = menuPreview
            self.orderRef = orderRef
        }
    }

    /// The ids a menu-item "+" tap needs to add the item to the provider cart
    /// directly ("doordash" needs menuId + unit price; "uber_eats" just the
    /// store/item uuids).
    public struct OrderRef: Hashable, Sendable {
        public let provider: String
        public let storeId: String
        public let itemId: String
        public let menuId: String?
        public let unitPriceCents: Int?
        public init(provider: String, storeId: String, itemId: String, menuId: String? = nil, unitPriceCents: Int? = nil) {
            self.provider = provider
            self.storeId = storeId
            self.itemId = itemId
            self.menuId = menuId
            self.unitPriceCents = unitPriceCents
        }
    }

    /// Structured store-row facts for the food cards (Uber Eats / DoorDash).
    public struct FoodMeta: Hashable, Sendable {
        public let rating: Double?
        public let ratingCount: String?
        public let eta: String?
        public let fee: String?
        public let cuisine: String?
        public init(
            rating: Double? = nil, ratingCount: String? = nil,
            eta: String? = nil, fee: String? = nil, cuisine: String? = nil
        ) {
            self.rating = rating
            self.ratingCount = ratingCount
            self.eta = eta
            self.fee = fee
            self.cuisine = cuisine
        }
    }

    /// Google-Maps place detail carried on a collection item — powers the
    /// tap → PlaceDetailView (hours, address, phone, navigate, reviews).
    public struct PlaceInfo: Hashable, Sendable {
        public let mapsUrl: String
        /// Exact coordinates from the maps result — let the client route natively
        /// (Apple Maps) to the RIGHT place instead of a name-based web search.
        public let latitude: Double?
        public let longitude: Double?
        public let rating: Double?
        public let ratingCount: Int?
        public let category: String?
        public let priceLevel: String?
        public let distanceMeters: Double?
        public let address: String?
        public let phone: String?
        public let website: String?
        public let openNow: Bool?
        public let hoursToday: String?
        public let cid: String?
        public let reviews: [String]
        public init(
            mapsUrl: String, latitude: Double? = nil, longitude: Double? = nil,
            rating: Double? = nil, ratingCount: Int? = nil,
            category: String? = nil, priceLevel: String? = nil, distanceMeters: Double? = nil,
            address: String? = nil, phone: String? = nil, website: String? = nil,
            openNow: Bool? = nil, hoursToday: String? = nil, cid: String? = nil,
            reviews: [String] = []
        ) {
            self.mapsUrl = mapsUrl
            self.latitude = latitude
            self.longitude = longitude
            self.rating = rating
            self.ratingCount = ratingCount
            self.category = category
            self.priceLevel = priceLevel
            self.distanceMeters = distanceMeters
            self.address = address
            self.phone = phone
            self.website = website
            self.openNow = openNow
            self.hoursToday = hoursToday
            self.cid = cid
            self.reviews = reviews
        }
    }

    /// One line in a `cart` card. `lineId` is the removable id the backend needs
    /// (DoorDash cart-line UUID); `unitPriceCents` is nil when the price isn't
    /// exposed. Pure value type; the card view renders + offers remove.
    public struct CartLine: Hashable, Sendable, Identifiable {
        public let lineId: String
        public let name: String
        public let quantity: Int
        public let unitPriceCents: Int?
        /// Product photo for the line's thumbnail (nil = placeholder glyph).
        public let imageUrl: String?
        /// Chosen options / description line under the name.
        public let optionsText: String?
        public var id: String { lineId }
        public init(
            lineId: String, name: String, quantity: Int, unitPriceCents: Int?,
            imageUrl: String? = nil, optionsText: String? = nil
        ) {
            self.lineId = lineId
            self.name = name
            self.quantity = quantity
            self.unitPriceCents = unitPriceCents
            self.imageUrl = imageUrl
            self.optionsText = optionsText
        }
    }
}

/// A past conversation (backend chat thread) shown in the conversations list.
public struct Conversation: Identifiable, Hashable, Sendable, Codable {
    /// Backend thread id.
    public let id: String
    public let title: String
    public let timeLabel: String
    /// One-line "what this chat is about" (backend thread-titler). Nil until
    /// the titler has written one — the row hides its subtitle line then.
    public let summary: String?

    public init(id: String, title: String, timeLabel: String, summary: String? = nil) {
        self.id = id
        self.title = title
        self.timeLabel = timeLabel
        self.summary = summary
    }
}

/// A side conversation branched off a chat message.
public struct ChatThread: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public var messages: [ChatMessage]

    public init(id: UUID, title: String, messages: [ChatMessage]) {
        self.id = id
        self.title = title
        self.messages = messages
    }

    /// The latest assistant line — shown on the message's thread chip.
    public var previewText: String? {
        messages.last(where: { !$0.isUser })?.text.replacingOccurrences(of: "\n", with: " ")
    }
}

// MARK: - Deep tasks (delegated background work)

/// A delegated background task the agent runs over time. A `delegation` chat
/// card links to one of these by `id`; tapping it opens the task thread where
/// you see progress and answer the agent's `ask_user` questions.
public struct DeepTask: Identifiable, Hashable, Sendable {
    public let id: String
    public let goal: String
    /// Short backend-distilled headline (budgeted to one line). Nil only on
    /// servers from before the column existed — fall back to `goal`.
    public let title: String?
    /// The task's own chat thread (goal + activity + ask_user + result). Drives
    /// the task-detail chat view; nil for legacy tasks created before it existed.
    public let activityThreadId: String?
    /// queued | running | waiting | succeeded | failed | cancelled
    public let status: String
    /// Rolling progress log (newest last).
    public let notes: [String]
    public let iterations: Int
    public let maxIterations: Int
    public let result: String?
    /// Present only when the task parked on `ask_user` and needs your answer.
    public let pendingInput: PendingInput?
    /// The LIVE "doing X right now…" line the backend rewrites during every
    /// step — the thread's live chip and the Home row's subtitle. Nil for
    /// tasks from before the column existed.
    public let statusLine: String?
    /// Rolling first-person OVERVIEW of the task — what's been done so far and
    /// what it's doing right now, rewritten server-side after every step. The
    /// thread's bottom overview panel shows this. Nil until the first rewrite.
    public let overview: String?
    /// The phone call this task is on RIGHT NOW (parked on a voice_call wait),
    /// or nil. Present on children of a parallel fan-out too, so every live
    /// call in the fan-out can be shown and drilled into, not just one.
    public let activeCall: ActiveCall?
    /// When a task sleeping on the `wait` tool resumes ("call back in 15") —
    /// drives the "back at 3:45 PM" affordance so a timed park never reads as
    /// stuck. The agent's reason needs no field of its own: the backend writes
    /// it into `statusLine` at park time. Nil on every other wait kind
    /// (ask_user, mail reply, call) and on older servers.
    public let waitingUntil: Date?
    /// When the task started — drives the header's elapsed clock, the honest
    /// progress signal (a deep task has no meaningful percentage).
    public let createdAt: Date?
    /// The start instant of a pre-created SCHEDULED task ("order the pizza at
    /// noon"): the row exists and is cancelable now, but doesn't run until this
    /// time. Set only while `status == "scheduled"` — drives the "Starts …"
    /// line and the calm scheduled treatment. Nil for every other task.
    public let scheduledFor: Date?
    /// The backend's one-line outcome digest, fitted to a card line. Nil for
    /// tasks from before the column existed — fall back to `result`.
    public let resultSummary: String?
    /// Stamped when the user dismissed this task's outcome (Home's "Got it",
    /// or the chat tray's dismiss on a failure). Nil means a terminal task is
    /// still unacknowledged and stays pinned wherever it's shown.
    public let acknowledgedAt: Date?
    /// Card-icon enrichment, same sources the Home task row resolves in order:
    /// person photo → contact email → brand domain → the SF-symbol badge.
    public let iconSymbol: String?
    public let photoUrl: String?
    public let contactEmail: String?
    public let logoDomain: String?

    /// Child sub-tasks spawned by `spawn_parallel` — each carries its own
    /// activeCall, so every live call of a parallel fan-out is visible.
    public let children: [Child]

    /// A live call a task is currently on.
    public struct ActiveCall: Hashable, Sendable {
        public let voiceCallId: String
        /// The dialed number (from the task's own call ledger), or nil.
        public let to: String?
        public init(voiceCallId: String, to: String?) {
            self.voiceCallId = voiceCallId
            self.to = to
        }
    }

    /// One child of a parallel fan-out — just enough to show its live call
    /// and label it with the child's own mission.
    public struct Child: Hashable, Sendable, Identifiable {
        public let id: String
        public let goal: String
        public let title: String?
        public let status: String
        public let statusLine: String?
        public let activeCall: ActiveCall?
        public init(id: String, goal: String, title: String?, status: String, statusLine: String?, activeCall: ActiveCall?) {
            self.id = id
            self.goal = goal
            self.title = title
            self.status = status
            self.statusLine = statusLine
            self.activeCall = activeCall
        }
    }

    /// A live call paired with the mission it serves — the child's own goal
    /// on a fan-out, which reads better than the parent's ("book the Gion
    /// place" vs "book us a weekend in Kyoto").
    public struct LiveCall: Hashable, Sendable, Identifiable {
        public let call: ActiveCall
        public let mission: String
        public var id: String { call.voiceCallId }
    }

    /// Every phone call this task is on RIGHT NOW — its own, plus one per
    /// child of a parallel fan-out. Deduped by call id defensively.
    public var liveCalls: [LiveCall] {
        var seen = Set<String>()
        var out: [LiveCall] = []
        for (call, mission) in [(activeCall, goal)] + children.map({ ($0.activeCall, $0.goal) }) {
            guard let call, seen.insert(call.voiceCallId).inserted else { continue }
            out.append(LiveCall(call: call, mission: mission))
        }
        return out
    }

    /// "back 3:45 PM" today, "back Fri 9:00 AM" within a week, "back Sep 30"
    /// further out (with the year once it differs) — when a task sleeping on
    /// the `wait` tool resumes. A resume time already in the past (the poll
    /// caught the task mid-wake) says so instead of promising a future clock.
    /// Shared by the Home card subtitle and the task surfaces' waiting line.
    public static func resumeClock(_ until: Date, now: Date = Date()) -> String {
        guard until > now else { return String(localized: "resuming now") }
        let clock = until.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDate(until, inSameDayAs: now) {
            return String(localized: "back \(clock)")
        }
        if until.timeIntervalSince(now) < 7 * 86400 {
            let weekday = until.formatted(.dateTime.weekday(.abbreviated))
            return String(localized: "back \(weekday) \(clock)")
        }
        let sameYear = Calendar.current.component(.year, from: until) == Calendar.current.component(.year, from: now)
        let day = sameYear
            ? until.formatted(.dateTime.month(.abbreviated).day())
            : until.formatted(.dateTime.month(.abbreviated).day().year())
        return String(localized: "back \(day)")
    }

    /// "at 1:00 PM" today, "tomorrow 1:00 PM", "Fri 1:00 PM" within a week,
    /// "Sep 30" further out (with the year once it differs) — WHEN a scheduled
    /// task will start. Mirrors `resumeClock`'s grammar so the two future-time
    /// reads feel like one system; a start time already past (the poll caught
    /// it mid-fire) reads "any moment" rather than promising a stale clock.
    /// Shared by the chat card, the Home dock row and the task surfaces.
    public static func startClock(_ at: Date, now: Date = Date()) -> String {
        guard at > now else { return String(localized: "any moment") }
        let clock = at.formatted(date: .omitted, time: .shortened)
        let cal = Calendar.current
        if cal.isDateInToday(at) { return String(localized: "at \(clock)") }
        if cal.isDateInTomorrow(at) { return String(localized: "tomorrow \(clock)") }
        if at.timeIntervalSince(now) < 7 * 86400 {
            let weekday = at.formatted(.dateTime.weekday(.abbreviated))
            return String(localized: "\(weekday) \(clock)")
        }
        let sameYear = cal.component(.year, from: at) == cal.component(.year, from: now)
        return sameYear
            ? at.formatted(.dateTime.month(.abbreviated).day())
            : at.formatted(.dateTime.month(.abbreviated).day().year())
    }

    public struct PendingInput: Hashable, Sendable {
        public let question: String
        public let proposal: String?
        /// "confirmation" (Approve/Deny) | "input" (free-text answer)
        public let kind: String
        /// Agent-supplied choice buttons; the tapped label is sent verbatim as
        /// the answer. Empty → free-text box (or approve/decline for confirmation).
        public let options: [String]
        /// Set when the park is a browser_request_login "sign in to this site"
        /// request: the respond UI shows a "Sign in" button that opens the in-app
        /// browser login instead of the answer box. Nil for ordinary ask_user.
        public let connect: LoginConnect?
        /// Set when the park is a request_payment "confirm + pay" request: Home
        /// (and the task thread + main chat) shows a tappable pay card → Face ID
        /// → order. Nil for ordinary ask_user / login parks.
        public let payment: Payment?
        public init(
            question: String,
            proposal: String?,
            kind: String,
            options: [String] = [],
            connect: LoginConnect? = nil,
            payment: Payment? = nil
        ) {
            self.question = question
            self.proposal = proposal
            self.kind = kind
            self.options = options
            self.connect = connect
            self.payment = payment
        }

        /// The site the agent needs the user signed into (browser_request_login).
        public struct LoginConnect: Hashable, Sendable {
            public let domain: String
            public let loginUrl: String
            public let cookieDomains: [String]
            public init(domain: String, loginUrl: String, cookieDomains: [String]) {
                self.domain = domain
                self.loginUrl = loginUrl
                self.cookieDomains = cookieDomains
            }
        }

        /// The DoorDash order the agent needs the user to pay for (request_payment).
        public struct Payment: Hashable, Sendable {
            /// "doordash" (cart order) or "agentcard" (generic browser payment).
            public let provider: String
            /// DoorDash only — the previewed cart. Empty for an agentcard payment.
            public let cartId: String
            /// The amount to charge, in cents (the cart total, or the browser
            /// amount read off the site). Drives the pay card + the paid total.
            public let maxSpendCents: Int
            public let currency: String
            public let storeName: String?
            public let itemsSummary: String?
            /// Rich breakdown for the pay card (real lines + fee split + logo).
            public let detail: ChatCard.DoordashPayDetail?
            /// agentcard only — who's being paid (shown on the generic pay card).
            public let merchant: String?
            /// agentcard only — the site being paid on, if known.
            public let siteUrl: String?
            public init(
                provider: String,
                cartId: String,
                maxSpendCents: Int,
                currency: String,
                storeName: String?,
                itemsSummary: String?,
                detail: ChatCard.DoordashPayDetail? = nil,
                merchant: String? = nil,
                siteUrl: String? = nil
            ) {
                self.provider = provider
                self.cartId = cartId
                self.maxSpendCents = maxSpendCents
                self.currency = currency
                self.storeName = storeName
                self.itemsSummary = itemsSummary
                self.detail = detail
                self.merchant = merchant
                self.siteUrl = siteUrl
            }
        }
    }

    public init(
        id: String,
        goal: String,
        status: String,
        notes: [String],
        iterations: Int,
        maxIterations: Int,
        result: String?,
        pendingInput: PendingInput?,
        activityThreadId: String? = nil,
        statusLine: String? = nil,
        overview: String? = nil,
        title: String? = nil,
        activeCall: ActiveCall? = nil,
        waitingUntil: Date? = nil,
        children: [Child] = [],
        createdAt: Date? = nil,
        scheduledFor: Date? = nil,
        resultSummary: String? = nil,
        iconSymbol: String? = nil,
        photoUrl: String? = nil,
        contactEmail: String? = nil,
        logoDomain: String? = nil,
        acknowledgedAt: Date? = nil
    ) {
        self.id = id
        self.goal = goal
        self.title = title
        self.acknowledgedAt = acknowledgedAt
        self.activityThreadId = activityThreadId
        self.status = status
        self.notes = notes
        self.iterations = iterations
        self.maxIterations = maxIterations
        self.result = result
        self.pendingInput = pendingInput
        self.statusLine = statusLine
        self.overview = overview
        self.activeCall = activeCall
        self.waitingUntil = waitingUntil
        self.children = children
        self.createdAt = createdAt
        self.scheduledFor = scheduledFor
        self.resultSummary = resultSummary
        self.iconSymbol = iconSymbol
        self.photoUrl = photoUrl
        self.contactEmail = contactEmail
        self.logoDomain = logoDomain
    }

    /// The one-line headline for headers and rows: the backend's short title,
    /// falling back to the full goal for pre-title tasks.
    public var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return goal
    }

    /// Still working (or parked waiting) — keep polling.
    public var isActive: Bool {
        status == "queued" || status == "running" || status == "waiting"
    }

    /// Created but not yet started: it runs itself at `scheduledFor`. Visible
    /// and cancelable now, but dormant — not "active" (nothing to poll) and not
    /// terminal.
    public var isScheduled: Bool {
        status == "scheduled"
    }

    public var isWaitingForInput: Bool {
        status == "waiting" && pendingInput != nil
    }

    /// Terminal, and the user hasn't dismissed the outcome yet — it stays
    /// pinned wherever it's shown (Home's outcome panel, the chat task tray).
    public var needsAcknowledge: Bool {
        !isActive && acknowledgedAt == nil
    }

    /// A copy stamped as dismissed. Terminal tasks are immutable value types,
    /// so acknowledging rebuilds the row rather than mutating it.
    public func acknowledged(at date: Date) -> DeepTask {
        DeepTask(
            id: id,
            goal: goal,
            status: status,
            notes: notes,
            iterations: iterations,
            maxIterations: maxIterations,
            result: result,
            pendingInput: pendingInput,
            activityThreadId: activityThreadId,
            statusLine: statusLine,
            overview: overview,
            title: title,
            activeCall: activeCall,
            waitingUntil: waitingUntil,
            children: children,
            createdAt: createdAt,
            scheduledFor: scheduledFor,
            resultSummary: resultSummary,
            iconSymbol: iconSymbol,
            photoUrl: photoUrl,
            contactEmail: contactEmail,
            logoDomain: logoDomain,
            acknowledgedAt: date
        )
    }

    /// A copy stamped STOPPED, for the moment the user confirms a stop — the
    /// task leaves the live surfaces (the chat tray above all) on the tap
    /// instead of on the round-trip behind it. `cancelled` is the wire word for
    /// it; the UI says "Stopped". `pendingInput` goes with it: a stopped task's
    /// question is no longer askable, so nothing should still be offering it.
    public func stoppedLocally() -> DeepTask {
        DeepTask(
            id: id,
            goal: goal,
            status: "cancelled",
            notes: notes,
            iterations: iterations,
            maxIterations: maxIterations,
            result: result,
            pendingInput: nil,
            activityThreadId: activityThreadId,
            statusLine: statusLine,
            overview: overview,
            title: title,
            activeCall: nil,
            waitingUntil: nil,
            children: children,
            createdAt: createdAt,
            scheduledFor: scheduledFor,
            resultSummary: resultSummary,
            iconSymbol: iconSymbol,
            photoUrl: photoUrl,
            contactEmail: contactEmail,
            logoDomain: logoDomain,
            acknowledgedAt: acknowledgedAt
        )
    }

    public var isConfirmation: Bool {
        pendingInput?.kind == "confirmation"
    }

    /// Honest step progress against the budget (0…1).
    public var progress: Double {
        guard maxIterations > 0 else { return 0 }
        return min(1, Double(iterations) / Double(maxIterations))
    }
}

// MARK: - People

/// One person from the user's life, as the backend's memory + contacts know
/// them. Most carry just a name; the lucky few have a relationship, a role, or a
/// memory-derived `context` paragraph. The People screen leans on whatever's
/// present and stays quiet about what isn't.
public struct Person: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    /// One or two uppercase letters for the avatar when there's no photo.
    public let initials: String
    /// Relationship + role/company, composed into one line; empty when unknown.
    public let subtitle: String
    /// A richer memory paragraph about who they are; nil when the backend has none.
    public let context: String?
    /// Relative "last seen" label ("3d", "now"), nil when unknown.
    public let lastInteraction: String?
    /// Their real photo, resolved by the backend from the contact-photo store.
    /// Nil → the avatar falls back to the address book, then to initials.
    public let photoUrl: String?
    /// Every address and number they're reachable at — what the LOCAL
    /// address-book photo lookup matches on, so a saved contact's face paints
    /// without a round trip. Empty when the backend didn't send channels.
    public let emails: [String]
    public let phones: [String]
    /// How this person reaches the user's real life: "contact" (device address
    /// book), "email" (the user has written to them), "domain" (shares a private
    /// domain the user converses with). Nil = mentioned in memory only — the
    /// tier the People screen folds behind its Mentioned filter.
    public let connection: String?

    /// True for the tiers with real reach — what the People screen shows by default.
    public var isConnected: Bool { connection != nil }

    public init(
        id: UUID = UUID(),
        name: String,
        initials: String,
        subtitle: String = "",
        context: String? = nil,
        lastInteraction: String? = nil,
        photoUrl: String? = nil,
        emails: [String] = [],
        phones: [String] = [],
        connection: String? = nil
    ) {
        self.id = id
        self.name = name
        self.initials = initials
        self.subtitle = subtitle
        self.context = context
        self.lastInteraction = lastInteraction
        self.photoUrl = photoUrl
        self.emails = emails
        self.phones = phones
        self.connection = connection
    }
}

// MARK: - Around You (proactive location)

/// A place the user returns to, classified into a rough role. Coordinates are
/// kept as plain doubles so `PersonaCore` stays Foundation-only; the view builds
/// the map coordinate.
public struct VisitPlace: Identifiable, Hashable, Sendable {
    public let id: UUID
    /// On-device reverse-geocoded label, when the device sent one.
    public let label: String?
    public let latitude: Double
    public let longitude: Double
    /// "home" | "work" | "regular" — the derived role, nil when unclassified.
    public let zone: String?
    public let visitCount: Int

    public init(id: UUID = UUID(), label: String?, latitude: Double, longitude: Double, zone: String?, visitCount: Int) {
        self.id = id
        self.label = label
        self.latitude = latitude
        self.longitude = longitude
        self.zone = zone
        self.visitCount = visitCount
    }
}

/// A fresh, location-aware recommendation produced on demand by "what's good
/// here?" — a single tip with an optional one-tap follow-up the agent can run.
public struct AroundTip: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let suggestion: String
    /// Where the user is / what they're doing, when the agent inferred it.
    public let situation: String?
    /// Transit/maps link to the suggested spot, when there is one.
    public let transitURL: URL?
    /// A delegatable next step ("Make a reservation") — label + the task goal.
    public let followUpLabel: String?
    public let followUpGoal: String?

    public init(
        id: UUID = UUID(),
        title: String,
        suggestion: String,
        situation: String? = nil,
        transitURL: URL? = nil,
        followUpLabel: String? = nil,
        followUpGoal: String? = nil
    ) {
        self.id = id
        self.title = title
        self.suggestion = suggestion
        self.situation = situation
        self.transitURL = transitURL
        self.followUpLabel = followUpLabel
        self.followUpGoal = followUpGoal
    }
}

/// One mail conversation a card points at — the handle for opening the thread
/// and for fetching anything attached to it.
public struct MailThreadRef: Identifiable, Hashable, Sendable, Codable {
    public let accountId: String
    public let threadId: String

    public init(accountId: String, threadId: String) {
        self.accountId = accountId
        self.threadId = threadId
    }

    public var id: String { "\(accountId)|\(threadId)" }
}
