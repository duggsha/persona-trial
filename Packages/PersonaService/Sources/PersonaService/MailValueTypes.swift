import Foundation

// Value types the card code still names.
//
// In the real app these are the wire shapes of the mail and compose endpoints —
// what a thread, a draft and an attachment look like coming back from the
// server. Nothing populates them in this build: no mail is fetched and no draft
// is sent. They are kept as plain, empty-by-default structs so the card views
// that hold a draft in progress compile and lay out exactly as they do in the
// app.

/// One address on a draft, as the composer's chips show it.
public struct ComposeRecipient: Codable, Sendable, Hashable, Identifiable {
    public let email: String
    public let name: String?

    public var id: String { email }

    public init(email: String, name: String? = nil) {
        self.email = email
        self.name = name
    }

    /// What the chip shows: the name when we have one, the address otherwise.
    public var displayName: String {
        if let name, !name.isEmpty { return name }
        return email
    }

    /// "Ada Lovelace <ada@x.com>" | "ada@x.com".
    public var rfcString: String {
        if let name, !name.isEmpty { return "\(name) <\(email)>" }
        return email
    }
}

/// The thread a draft replies into — the "Replying to …" banner's contents.
public struct ComposeReplyContext: Codable, Sendable, Hashable {
    public let accountId: String
    public let threadId: String
    public let subject: String?
    /// Counterpart display for the banner.
    public let from: String?
    public let accountEmail: String?
    public let to: [ComposeRecipient]?
    public let cc: [ComposeRecipient]?
    public let senderOnly: [ComposeRecipient]?

    public init(
        accountId: String,
        threadId: String,
        subject: String? = nil,
        from: String? = nil,
        accountEmail: String? = nil,
        to: [ComposeRecipient]? = nil,
        cc: [ComposeRecipient]? = nil,
        senderOnly: [ComposeRecipient]? = nil
    ) {
        self.accountId = accountId
        self.threadId = threadId
        self.subject = subject
        self.from = from
        self.accountEmail = accountEmail
        self.to = to
        self.cc = cc
        self.senderOnly = senderOnly
    }
}

/// A draft in progress.
public struct ComposeEmailDraft: Codable, Sendable, Equatable {
    public var to: [ComposeRecipient]
    public var cc: [ComposeRecipient]
    public var bcc: [ComposeRecipient]
    public var subject: String
    public var body: String

    public init(
        to: [ComposeRecipient] = [],
        cc: [ComposeRecipient] = [],
        bcc: [ComposeRecipient] = [],
        subject: String = "",
        body: String = ""
    ) {
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
    }
}

/// A file riding along with a draft.
public struct ComposeAttachment: Identifiable, Hashable, Sendable {
    public enum Payload: Hashable, Sendable {
        case data(Data)
        case mailRef(accountId: String, threadId: String)
    }

    public let id: UUID
    public var filename: String
    public var mimeType: String
    public var sizeBytes: Int?
    public var payload: Payload

    public init(id: UUID = UUID(), filename: String, mimeType: String, sizeBytes: Int? = nil, payload: Payload) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.payload = payload
    }
}

/// A draft parked so it survives a relaunch.
public struct ComposeDraftSnapshot: Codable, Sendable {
    public var to: [ComposeRecipient]
    public var cc: [ComposeRecipient]
    public var bcc: [ComposeRecipient]
    public var subject: String
    public var body: String
    public var senderEmail: String?
    public var replyContext: ComposeReplyContext?
    public var forwardTitle: String?
    public var savedAt: Date

    public init(
        to: [ComposeRecipient] = [],
        cc: [ComposeRecipient] = [],
        bcc: [ComposeRecipient] = [],
        subject: String = "",
        body: String = "",
        senderEmail: String? = nil,
        replyContext: ComposeReplyContext? = nil,
        forwardTitle: String? = nil,
        savedAt: Date = Date()
    ) {
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
        self.senderEmail = senderEmail
        self.replyContext = replyContext
        self.forwardTitle = forwardTitle
        self.savedAt = savedAt
    }
}

/// One file hanging off a mail message.
public struct MailAttachmentRef: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let filename: String?
    public let mimeType: String?
    public let sizeBytes: Int?

    public init(id: String, filename: String? = nil, mimeType: String? = nil, sizeBytes: Int? = nil) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
    }
}

/// One message in a thread.
public struct MailThreadMessage: Codable, Sendable, Identifiable, Hashable {
    public let messageId: String
    public let from: String?
    public let to: [String]
    public let cc: [String]
    /// ISO timestamp.
    public let receivedAt: String?
    public let snippet: String?
    public let body: String?
    public let attachments: [MailAttachmentRef]?

    public var id: String { messageId }

    public init(
        messageId: String,
        from: String? = nil,
        to: [String] = [],
        cc: [String] = [],
        receivedAt: String? = nil,
        snippet: String? = nil,
        body: String? = nil,
        attachments: [MailAttachmentRef]? = nil
    ) {
        self.messageId = messageId
        self.from = from
        self.to = to
        self.cc = cc
        self.receivedAt = receivedAt
        self.snippet = snippet
        self.body = body
        self.attachments = attachments
    }
}

/// A whole conversation. Never populated in this build.
public struct MailThreadView: Codable, Sendable, Hashable {
    public let threadId: String
    public let accountId: String
    public let subject: String?
    public let participants: [String]
    public let messageCount: Int
    public let lastMessageAt: String?
    public let messages: [MailThreadMessage]

    public init(
        threadId: String,
        accountId: String,
        subject: String? = nil,
        participants: [String] = [],
        messageCount: Int = 0,
        lastMessageAt: String? = nil,
        messages: [MailThreadMessage] = []
    ) {
        self.threadId = threadId
        self.accountId = accountId
        self.subject = subject
        self.participants = participants
        self.messageCount = messageCount
        self.lastMessageAt = lastMessageAt
        self.messages = messages
    }
}
