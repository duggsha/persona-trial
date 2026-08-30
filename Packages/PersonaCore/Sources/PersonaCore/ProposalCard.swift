import Foundation

/// The v2 proposal card's model (design pass): the presentation
/// shape of a durable engine proposal, composed from the shared chat-card
/// primitives (CardHeaderRow → FieldStack → PillPair / status row).
///
/// It deliberately carries LESS than `EngineProposalCard`: the durable record
/// keeps the full authority contract (tool, capability, expiry, targets); this
/// model keeps only what the v2 card DRAWS; the domain eyebrow, the
/// host-normalized entities in reading order, the two pill titles, and the
/// settled state. Status reuses `EngineProposalStatus` so the two surfaces can
/// never disagree about what a proposal's state is called.
public struct ProposalCardModel: Hashable, Sendable, Identifiable {
    /// One host-normalized entity row, in reading order (To / Subject / Body…).
    /// These are the entities the approval would EXECUTE; display copy is
    /// never invented client-side; the host normalized them at mint time.
    public struct Field: Hashable, Sendable {
        public let label: String?
        public let value: String
        /// Multi-line preview treatment (an email body, a long note): renders
        /// through the FieldStack's fading body-preview row.
        public let isBodyPreview: Bool

        public init(label: String? = nil, value: String, isBodyPreview: Bool = false) {
            self.label = label
            self.value = value
            self.isBodyPreview = isBodyPreview
        }
    }

    /// The durable proposal id; the buttons' authority key, and the view
    /// identity (two proposals in one transcript never share arming state).
    public let id: String
    /// Uppercase eyebrow: the DOMAIN of the ask ("Email", "Calendar",
    /// "Purchase"); never the tool name.
    public let eyebrow: String
    /// SF symbol for the header's leading icon tile; nil = text-only header.
    public let iconSymbol: String?
    /// The engine suite the proposal came from ("mail", "calendar") — drives
    /// the header's brand mark and the settled card's open-in-app action.
    /// Nil on old persisted cards; the view falls back to the SF tile.
    public let suite: String?
    public let fields: [Field]
    /// The approve pill's title; the proposal's own verb ("Send", "Delete
    /// 3 events"), which is also the sentence the user is agreeing to.
    public let primaryTitle: String
    /// The decline pill's title; nil renders the single full-width primary.
    public let secondaryTitle: String?
    /// A destructive ask (irreversible delete/cancel): the outlined pill wears
    /// the danger label per PillPair's contract; color encodes state.
    public let destructive: Bool
    public let status: EngineProposalStatus
    /// The settled line ("Sent", "Declined, nothing was sent"). Nil while
    /// pending; the view falls back to the status's own vocabulary.
    public let statusText: String?
    /// Display-formatted timestamp for the settled row ("9:41 AM").
    public let timestamp: String?

    public init(
        id: String,
        eyebrow: String,
        iconSymbol: String? = nil,
        suite: String? = nil,
        fields: [Field],
        primaryTitle: String,
        secondaryTitle: String? = nil,
        destructive: Bool = false,
        status: EngineProposalStatus = .pending,
        statusText: String? = nil,
        timestamp: String? = nil
    ) {
        self.id = id
        self.eyebrow = eyebrow
        self.iconSymbol = iconSymbol
        self.suite = suite
        self.fields = fields
        self.primaryTitle = primaryTitle
        self.secondaryTitle = secondaryTitle
        self.destructive = destructive
        self.status = status
        self.statusText = statusText
        self.timestamp = timestamp
    }
}
