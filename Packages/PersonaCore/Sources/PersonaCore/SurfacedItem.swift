import Foundation

/// Selection logic for Home's "surfaced item" slot — the one useful-right-now
/// artifact pinned directly under the Up Next hero. Today that's exactly one
/// thing: the newest still-active sign-in code. The slot itself is generic on
/// purpose (boarding passes are earmarked for it next); the chooser lives here
/// as plain data logic so it stays testable without UI.
extension Suggestion {
    /// The newest still-active sign-in code in `cards`, or nil when the slot
    /// should stay empty.
    ///
    /// Active means: an open card with a structured code, not locally consumed
    /// (copied or dismissed this session), and not past its deadline — the
    /// mail's stated `codeValidUntil` when there is one, else the server row's
    /// `expiresAt` (the default TTL). A card with neither deadline trusts the
    /// server's own expiry filter: it wouldn't be in the feed if it were dead.
    public static func surfacedCode(
        in cards: [Suggestion],
        consumed: Set<UUID> = [],
        now: Date = Date()
    ) -> Suggestion? {
        cards
            .filter { card in
                card.kind == "signin-code"
                    && card.isOpen
                    && !(card.code ?? "").isEmpty
                    && !consumed.contains(card.id)
                    && ((card.codeValidUntil ?? card.expiresAt).map { $0 > now } ?? true)
            }
            .max { $0.createdAt < $1.createdAt }
    }
}
