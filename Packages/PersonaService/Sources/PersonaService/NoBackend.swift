import Foundation
import PersonaCore

// The seam where a backend used to be.
//
// In the real app this package is the network layer: an authenticated API
// client, a session/auth flow, analytics, and roughly two hundred REST routes
// behind a set of observable stores. None of that is in this trial. What
// remains is the SHAPE those stores presented to the UI — the same properties,
// the same method signatures — backed by local state that is seeded once at
// launch and never changes.
//
// Nothing in this file opens a socket. There is no URLSession, no host, no
// route, and no credential anywhere in this package.

/// Stand-in for the real API client. It exists because a handful of view code
/// still takes one as a parameter; every entry point fails immediately.
public struct APIClient: Sendable {
    public init() {}

    /// Always throws. The real client fetches an authenticated blob by path.
    public func data(_ path: String) async throws -> Data {
        throw APIError.noBackend
    }

    /// Always throws. Speech-to-text runs server-side in the real app; the
    /// composer's hold-to-talk therefore records and then discards.
    public func transcribeVoice(
        fileURL: URL,
        durationMs: Int,
        language: String? = nil
    ) async throws -> VoiceTranscription {
        throw APIError.noBackend
    }
}

/// The errors this package can produce.
public enum APIError: Error, Sendable, Equatable {
    /// There is no backend in this build. The only one ever thrown.
    case noBackend
    /// A status response. Never produced here, but call sites pattern-match on
    /// it to tell "gone forever" (404) apart from a transient failure, and that
    /// branch is part of how the views behave.
    case http(Int, String?)

    /// Kept because the UI switches on it to pick an error illustration.
    public enum Kind: Sendable, Equatable {
        case transport
        case auth
        case server
        case client
        case unknown
    }

    public var kind: Kind {
        switch self {
        case .noBackend: .transport
        case let .http(status, _):
            switch status {
            case 401, 403: .auth
            case 500...: .server
            case 400...: .client
            default: .unknown
            }
        }
    }
}

/// A file staged on a composer. Pure value type — it never leaves the device.
public struct ChatFileAttachment: Sendable {
    public let filename: String
    public let mimeType: String
    public let data: Data

    public init(filename: String, mimeType: String, data: Data) {
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
    }
}

/// The real app streams a reply back as these events. Nothing emits them here;
/// the type survives because card reply code still names it.
public enum ChatStreamEvent: Sendable {
    case delta(String)
    case thread(threadId: String)
    case done
}

/// What server-side speech-to-text returns. Never produced in this build.
public struct VoiceTranscription: Sendable {
    public let transcript: String
    public let audioUrl: String?
    public let durationMs: Int?

    public init(transcript: String, audioUrl: String? = nil, durationMs: Int? = nil) {
        self.transcript = transcript
        self.audioUrl = audioUrl
        self.durationMs = durationMs
    }
}

/// One hit from the draft's thread picker. Always an empty list here.
public struct ComposeThreadHit: Sendable, Hashable, Identifiable {
    public let threadId: String
    public let accountId: String
    public let subject: String?
    public let from: String?
    public let snippet: String?
    public let lastMessageAt: Date?

    public var id: String { "\(accountId)|\(threadId)" }

    public init(
        threadId: String,
        accountId: String,
        subject: String? = nil,
        from: String? = nil,
        snippet: String? = nil,
        lastMessageAt: Date? = nil
    ) {
        self.threadId = threadId
        self.accountId = accountId
        self.subject = subject
        self.from = from
        self.snippet = snippet
        self.lastMessageAt = lastMessageAt
    }
}

// MARK: - Mail-shaped stubs

/// One connected mail account. Always an empty list in this build.
public struct MailAccount: Sendable, Identifiable, Hashable {
    public let id: String
    public let email: String
    /// The assistant's own mailbox rather than one of the user's — excluded
    /// from the sender picker.
    public var isAgentMailbox: Bool { false }

    public init(id: String, email: String) {
        self.id = id
        self.email = email
    }
}

public struct ComposeEmailAssistRequest: Sendable {
    public var instruction: String
    public var draft: ComposeEmailDraft
    public var replyTo: ComposeReplyContext?

    public init(
        instruction: String = "",
        draft: ComposeEmailDraft = ComposeEmailDraft(),
        replyTo: ComposeReplyContext? = nil
    ) {
        self.instruction = instruction
        self.draft = draft
        self.replyTo = replyTo
    }
}

public struct ComposeEmailAssistResponse: Sendable {
    public var draft: ComposeEmailDraft
    public init(draft: ComposeEmailDraft = ComposeEmailDraft()) { self.draft = draft }
}

public struct ComposeEmailSendRequest: Sendable {
    public var draft: ComposeEmailDraft
    public var attachments: [ComposeAttachment]
    public var replyTo: ComposeReplyContext?

    public init(
        draft: ComposeEmailDraft = ComposeEmailDraft(),
        attachments: [ComposeAttachment] = [],
        replyTo: ComposeReplyContext? = nil
    ) {
        self.draft = draft
        self.attachments = attachments
        self.replyTo = replyTo
    }
}

/// The compose client the card reply rails hold. `sendEmail` is nil, which the
/// UI already reads as "this host cannot send" — the same branch it takes for a
/// surface with no mail account attached.
/// The bundle of closures a compose surface is handed. In the real app each one
/// is a route; here `assistEmail` throws and the optional ones are nil, which
/// the UI already reads as "this host can't do that" and hides the affordance.
public struct ComposeAssistClient: Sendable {
    /// Apply an instruction to a draft. Always throws.
    public var assistEmail: @Sendable (ComposeEmailAssistRequest) async throws -> ComposeEmailAssistResponse
    /// Nil = no direct-send backend.
    public var sendEmail: (@Sendable (ComposeEmailSendRequest) async throws -> Void)?
    /// Nil hides the "Reply to…" thread picker.
    public var searchThreads: (@Sendable (String, String?) async -> [ComposeThreadHit])?
    /// Nil hides the composer's mic.
    public var transcribe: (@Sendable (URL, TimeInterval) async throws -> String)?
    /// Picked thread → reply prefill. Nil hides the picker's follow-up.
    public var replyContext: (@Sendable (ComposeThreadHit) async throws -> ComposeReplyContext)?

    public init(
        assistEmail: @escaping @Sendable (ComposeEmailAssistRequest) async throws -> ComposeEmailAssistResponse
            = { _ in throw APIError.noBackend },
        sendEmail: (@Sendable (ComposeEmailSendRequest) async throws -> Void)? = nil,
        searchThreads: (@Sendable (String, String?) async -> [ComposeThreadHit])? = nil,
        transcribe: (@Sendable (URL, TimeInterval) async throws -> String)? = nil,
        replyContext: (@Sendable (ComposeThreadHit) async throws -> ComposeReplyContext)? = nil
    ) {
        self.assistEmail = assistEmail
        self.sendEmail = sendEmail
        self.searchThreads = searchThreads
        self.transcribe = transcribe
        self.replyContext = replyContext
    }
}

@MainActor
public final class ComposeService {
    public init() {}
    public var client: ComposeAssistClient { ComposeAssistClient() }
}

@MainActor
public final class ConnectService {
    public init() {}
    /// No accounts are ever connected in this build.
    public func mailAccounts() async throws -> [MailAccount] { [] }
}
