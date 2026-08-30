import Foundation

/// A reply to a Home card can be an ORDER rather than a question — "accept the
/// invite", or "decline this and email him that I can't make it but thanks".
///
/// The card's reply turn tells the model which of the card's own buttons exist
/// and asks it to answer an order with a bare directive instead of doing the
/// work itself. The client then runs it: press the button locally, hand the
/// rest to the agent, or both in that order. Two reasons the work is NOT done
/// inside the reply turn:
///
/// - The card's buttons aren't chat tools. RSVP lives in the suggestions
/// action executor, and the chat agent has no tool for it — which is why
/// "accept the invite" used to come back as "I can't do that".
/// - Undo has to be real. The client holds the whole order for the undo
/// window and only then commits, so Undo cancels the RSVP *and* the email
/// rather than apologising for them.
///
/// This is the wire format, kept in Core so it is testable on its own: the
/// parser has to make a three-way call on a PARTIAL string arriving token by
/// token, and getting it wrong either flashes markup on screen or holds a real
/// answer back forever.
public enum CardDirective {
    public static let open = "[[do:"
    public static let close = "]]"

    /// One order, exactly as the model may compose it: a card button, work for
    /// the agent, or both. At least one of `button`/`agent` is present —
    /// `read` rejects an order carrying neither.
    public struct Order: Equatable, Sendable, Decodable {
        /// 1-based index into the buttons the seed listed.
        public var button: Int?
        /// Freeform work for the agent, in the model's own words, as an
        /// instruction to itself. A chain belongs here, in order.
        public var agent: String?
        /// 2–5 words, present tense, for the undo toast.
        public var toast: String?
        /// The reply itself, WRITTEN OUT, when the order is "answer this
        /// email". It is not work to hand off — it is the mail, and the client
        /// opens it in the composer so the user sends it or throws it away
        ///. Before this, "reply to connor saying hi" came
        /// back as an `agent` errand and the agent sent it unseen.
        public var reply: String?

        public init(button: Int? = nil, agent: String? = nil, toast: String? = nil, reply: String? = nil) {
            self.button = button
            self.agent = agent
            self.toast = toast
            self.reply = reply
        }

        /// The written reply, or nil when this order isn't one.
        public var replyBody: String? {
            let body = (reply ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return body.isEmpty ? nil : body
        }

        public var isEmpty: Bool {
            button == nil
                && (agent ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                && replyBody == nil
        }
    }

    public enum Reading: Equatable, Sendable {
        /// Could still become a directive — hold the words back.
        case pending
        /// Ordinary prose; release it and stop scanning.
        case plain
        /// Carry this out instead of showing an answer.
        case order(Order)
    }

    /// A directive that never closes can't hold the words forever — past this
    /// much body, treat it as prose and let it through.
    private static let bodyLimit = 800

    /// Read the head of a streamed reply. Anything that cannot still become a
    /// directive must be released as words immediately, so the answer keeps
    /// streaming; only a live prefix of the marker keeps them waiting.
    public static func read(_ head: String) -> Reading {
        let text = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .pending }
        guard text.hasPrefix(open) else {
            // A partial marker ("[", "[[d") could still complete.
            return open.hasPrefix(text) ? .pending : .plain
        }
        let body = text.dropFirst(open.count)

        // The short form: `[[do:2]]`, a button and nothing else.
        if let close = body.range(of: close),
           let button = Int(body[body.startIndex ..< close.lowerBound])
        {
            return .order(Order(button: button))
        }

        // The full form: `[[do:{…json…}]]`. A brace in the JSON can't be
        // confused with the terminator, but a `]]` inside a string could be —
        // so try each candidate end until one parses.
        if body.hasPrefix("{") {
            var searchFrom = body.startIndex
            while let end = body.range(of: close, range: searchFrom ..< body.endIndex) {
                let json = body[body.startIndex ..< end.lowerBound]
                if let order = decode(json) {
                    // Parsed and complete: either it says to do something, or
                    // it says nothing and the words are the better fallback.
                    return order.isEmpty ? .plain : .order(order)
                }
                searchFrom = end.upperBound
            }
            // Not closed yet (or not parseable yet) — still arriving.
            return body.count > bodyLimit ? .plain : .pending
        }

        // Neither a number nor an object: only digits or a `{` can still
        // become a directive.
        if body.isEmpty { return .pending }
        return body.allSatisfy(\.isNumber) ? .pending : .plain
    }

    private static func decode(_ json: Substring) -> Order? {
        guard let data = String(json).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Order.self, from: data)
    }

    /// Scrub any directive out of words that are about to be SHOWN — one the
    /// model narrated instead of issuing ("you could [[do:1]] that"), or one
    /// read back out of history, where the turn that carried the order persists
    /// as its own wire format. Only a LEADING directive is ever carried out, so
    /// by the time text is being rendered every directive left in it is markup
    /// the user must not see.
    public static func stripped(_ text: String) -> String {
        guard text.contains(open) else { return text }
        var out = ""
        var rest = Substring(text)
        while let start = rest.range(of: open) {
            let body = rest[start.upperBound...]
            guard let end = terminator(of: body) else {
                // An unclosed or non-directive "[[do:" is just text.
                out += rest[..<start.upperBound]
                rest = rest[start.upperBound...]
                continue
            }
            out += rest[..<start.lowerBound]
            rest = body[end...]
        }
        out += rest
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Where a directive opening at the head of `body` ends — the index just
    /// past its `]]` — or nil when these are ordinary words after all.
    ///
    /// A `]]` inside the JSON is not the terminator, so candidates are tried in
    /// turn until one leaves a body that actually parses, exactly as `read`
    /// does. Cutting at the FIRST `]]` instead would strip half an order and
    /// spill the rest of its JSON onto the screen as prose.
    private static func terminator(of body: Substring) -> Substring.Index? {
        guard body.hasPrefix("{") else {
            // The short form: `[[do:2]]`, a button and nothing else.
            guard let end = body.range(of: close),
                  Int(body[body.startIndex ..< end.lowerBound]) != nil
            else { return nil }
            return end.upperBound
        }
        var searchFrom = body.startIndex
        while let end = body.range(of: close, range: searchFrom ..< body.endIndex) {
            if decode(body[body.startIndex ..< end.lowerBound]) != nil { return end.upperBound }
            searchFrom = end.upperBound
        }
        return nil
    }
}
