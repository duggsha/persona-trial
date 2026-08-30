import Foundation

// The client model of an engine-v2 PROPOSAL — the thing the confirm card
// renders and the two decision routes act on.
//
// The rule it serves: a gated or destructive call NEVER runs on a model tool
// call alone. The registry mints this from HOST-normalized validated args and
// stops; execution needs a single-use grant that only the user's tap issues.
// Every field here is host-derived — not one is model prose — which is what
// makes it safe to treat a tap on this card as authority.

/// The engine's capability classes, in ascending consequence. Raw values match
/// the backend card's `capability`.
public enum EngineCapability: String, Hashable, Sendable {
    case read
    case egressRead = "egress-read"
    case autoWrite = "auto-write"
    case gatedWrite = "gated-write"
    case destructive
}

/// The six states a proposal card can be in, and the only six.
///
/// The server's own status enum has two more — `approved` and `executing` —
/// which are the approval CAS's in-flight bookkeeping; it collapses them to
/// `pending` before the card is built, because a card that said "executing"
/// would be a promise the server has not kept yet.
public enum EngineProposalStatus: String, Hashable, Sendable {
    /// Minted, awaiting the user. The only state with live buttons.
    case pending
    /// Approved and executed. The ONLY state that backs "it happened".
    case executed
    /// The user said no. It did not happen and must not be retried.
    case denied
    /// Approved, but the transmit lock is off: NOTHING was sent or placed.
    /// This is not a success and must never be coloured like one.
    case parked
    /// Approved, executor ran, executor failed.
    case failed
    /// The approval window closed before the user decided. Nothing ran;
    /// re-approving means asking for the thing again.
    case expired
}

/// What a proposal's transmit-lock copy is about — the one place the client
/// decides which verb the "switched off right now" sentences speak in.
///
/// Three cases and no more, because the card only ever has to answer "what
/// won't happen if I approve this?": something gets removed, something leaves
/// the account, or something inside the user's own world changes.
public enum EngineLockLanguage: Hashable, Sendable {
    /// Destructive. Every destructive verb the registry mints today is a
    /// removal — `calendar_write.delete`, `mail_admin.delete_folder`,
    /// `empty_trash`, `delete_permanently` — so the copy can say "deleted" and
    /// be exact. A destructive verb that is NOT a removal needs its own case
    /// here rather than borrowing this one.
    case removal
    /// Leaves the account and is not destructive: a send, an invitation, an
    /// autoreply that will answer strangers.
    case send
    /// Stays in the user's own world: a draft saved, a filter armed.
    case change
}

/// One host-normalized display entity of a proposal — pulled from the
/// VALIDATED args, never from model prose.
///
/// Ordered PAIRS rather than a dictionary, deliberately: the server sends them
/// in reading order (to, cc, subject, body) and that order is part of the
/// meaning. A dictionary would lose it, and the payload survives a `jsonb`
/// column on the way to a reloaded transcript, which reorders object keys.
public struct EngineProposalEntity: Hashable, Sendable, Identifiable {
    public let key: String
    public let value: String
    /// HOST COPY: the row's label, authored beside the field it describes and
    /// carried on the wire. The host owns this for the same reason it owns
    /// `headline` — a label the client derives from an arg key is our source
    /// code quoted at the user, however nicely it is title-cased, and the host
    /// is the only side that knows `sendAt` reads "Send at" and `fromChoice`
    /// reads "Picked for you".
    private let hostLabel: String?
    public var id: String { key }
    public init(key: String, value: String, label: String? = nil) {
        self.key = key
        self.value = value
        self.hostLabel = label
    }

    /// The host's label when it sent one. The table below is the fallback for
    /// a payload minted before the host carried labels; an unknown key passes
    /// through title-cased rather than being dropped, because a proposal field
    /// the card silently swallows is a field the user approved without seeing.
    public var label: String {
        if let hostLabel, !hostLabel.isEmpty { return hostLabel }
        return switch key {
        case "to": "To"
        case "cc": "Cc"
        case "bcc": "Bcc"
        // Which account this goes OUT of. A person with two mailboxes cannot
        // approve a send without it, so when the host sends it, it gets a
        // proper name rather than falling through the title-caser as
        // "FromAccount".
        case "from", "fromAccount", "sender": "From"
        case "account": "Account"
        case "subject": "Subject"
        case "body": "Message"
        case "title": "Title"
        case "start": "Starts"
        case "end": "Ends"
        case "attendees": "Guests"
        case "response": "RSVP"
        case "message": "Message"
        case "reason": "Reason"
        case "at": "When"
        case "action": "Action"
        case "draftId": "Draft"
        default: key.prefix(1).uppercased() + key.dropFirst()
        }
    }

    /// Long-form fields get their own quoted well rather than a one-line row.
    public var isLongForm: Bool {
        key == "body" || key == "message" || value.count > 64
    }
}

/// One thing a proposal will act on — the unit of a destructive confirm.
///
/// THE HOUSE RULE: a destructive verb confirms by IDENTITY, never by a generic
/// "are you sure?". `id` is the REAL domain id the executor will act on,
/// derived host-side from the frozen args, so the card's set and the
/// executor's set are the same set by construction. `label`/`detail` are
/// display only and are deliberately excluded from the proposal's args hash,
/// so a name lookup can never invalidate an approval.
public struct EngineProposalTarget: Hashable, Sendable, Identifiable {
    public let id: String
    /// The validated arg field it came from ("eventIds").
    public let field: String
    /// Which id space this is ("event", "thread", "reminder").
    public let domain: String
    /// The human name of the thing ("Dentist"). Falls back to the id itself.
    public let label: String
    /// The disambiguator, and the reason `label` alone is not enough: two
    /// events both called "Standup" separate only here.
    public let detail: String?
    /// The name lookup did not resolve this id. LOUD by design — a bare id
    /// shown as if it were a name is its own small lie.
    public let unresolved: Bool

    public init(id: String, field: String, domain: String, label: String, detail: String? = nil, unresolved: Bool = false) {
        self.id = id
        self.field = field
        self.domain = domain
        self.label = label
        self.detail = detail
        self.unresolved = unresolved
    }
}

/// A typed proposal, as the confirm card renders it.
public struct EngineProposalCard: Hashable, Sendable, Identifiable {
    /// The proposal id — what the approve/deny routes take.
    public let id: String
    public let tool: String
    public let suite: String
    public let action: String?
    public let capability: EngineCapability
    /// Executing this makes something LEAVE the user's account.
    public let transmit: Bool
    /// CARD COPY, server-authored: what approval does, as a sentence a person
    /// reads ("Send “Re: lease” to chris@x.com"). The client does NOT derive
    /// this from the entities — the host owns the words the user is deciding
    /// about, so there is one sentence and no second opinion.
    public let headline: String
    /// PROVENANCE: the raw call line ("mail_compose · send — to: …"), small
    /// and monospaced at the foot. Kept because `mail_compose · create` and
    /// `mail_compose · send` are exactly the difference this card exists to
    /// make visible.
    public let call: String
    /// What approval actually DOES, in the engine's own words — the same
    /// sentence the model gets on its proposal receipt.
    public let whatApprovalDoes: String
    public let entities: [EngineProposalEntity]
    /// Named targets. Non-empty on a destructive card ⇒ confirm-by-ID.
    public let targets: [EngineProposalTarget]
    /// The verb the user is authorising ("Send", "Delete"). Server-derived —
    /// reading it off the headline's first word gives "Permanently".
    public let verb: String
    /// The singular noun for one target ("event"), for the confirm copy.
    public let targetNoun: String
    /// ISO8601.
    public let createdAt: String
    /// ISO8601. The pending TTL boundary — past it the server refuses, so the
    /// card must go quiet on its own rather than offer a live Send forever.
    public let expiresAt: String
    public let status: EngineProposalStatus
    /// Host-derived outcome line for an executed proposal ("messageId m_88").
    public let resultSummary: String?
    /// Failure reason for `.failed`.
    public let error: String?
    /// True when the transmit lock is off, so approving will PARK. Shown
    /// BEFORE the user decides — discovering the lock after tapping Send is
    /// how "I sent it" becomes a lie the user then repeats.
    public let transmitLocked: Bool

    public init(
        id: String,
        tool: String,
        suite: String,
        action: String? = nil,
        capability: EngineCapability,
        transmit: Bool,
        headline: String,
        call: String,
        whatApprovalDoes: String,
        entities: [EngineProposalEntity] = [],
        targets: [EngineProposalTarget] = [],
        verb: String,
        targetNoun: String = "item",
        createdAt: String,
        expiresAt: String,
        status: EngineProposalStatus = .pending,
        resultSummary: String? = nil,
        error: String? = nil,
        transmitLocked: Bool = false
    ) {
        self.id = id
        self.tool = tool
        self.suite = suite
        self.action = action
        self.capability = capability
        self.transmit = transmit
        self.headline = headline
        self.call = call
        self.whatApprovalDoes = whatApprovalDoes
        self.entities = entities
        self.targets = targets
        self.verb = verb
        self.targetNoun = targetNoun
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.status = status
        self.resultSummary = resultSummary
        self.error = error
        self.transmitLocked = transmitLocked
    }

    /// The destructive variant: hard to undo, so the user confirms the exact
    /// targets by identity rather than answering "are you sure?".
    public var isDestructive: Bool { capability == .destructive }

    /// Which verb the transmit-lock sentences must speak about.
    ///
    /// `transmit` alone CANNOT pick it, and the reason is not an edge case:
    /// `calendar_write.delete` is minted with `transmit: true`, correctly —
    /// deleting an event with guests mails every attendee a cancellation. Key
    /// the copy off that bit and a person deleting three of their own standups
    /// is told "nothing will actually go out", which is a sentence about an
    /// action they are not taking. A safety notice the reader cannot map onto
    /// what they are doing is a safety notice they skip, so the DESTRUCTIVE
    /// class is asked first and the transmit bit only decides the rest.
    public var lockLanguage: EngineLockLanguage {
        if isDestructive { return .removal }
        return transmit ? .send : .change
    }

    /// A copy in a new state — what a decision hands back to the transcript so
    /// the live card settles without waiting for a reload.
    public func settled(_ status: EngineProposalStatus, resultSummary: String? = nil, error: String? = nil) -> EngineProposalCard {
        EngineProposalCard(
            id: id, tool: tool, suite: suite, action: action, capability: capability, transmit: transmit,
            headline: headline, call: call, whatApprovalDoes: whatApprovalDoes, entities: entities, targets: targets,
            verb: verb, targetNoun: targetNoun, createdAt: createdAt, expiresAt: expiresAt,
            status: status, resultSummary: resultSummary, error: error, transmitLocked: transmitLocked
        )
    }
}
