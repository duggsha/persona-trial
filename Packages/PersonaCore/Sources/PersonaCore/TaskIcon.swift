import Foundation
import NaturalLanguage

/// Picks the task card's badge glyph. The backend derives `iconSymbol` from
/// the running tool, but plenty of tasks arrive with no signal at all — the
/// mapper coalesces those to a neutral gear, so half the Home deck used to
/// read as "machinery". This resolver keeps a REAL backend icon untouched and
/// only steps in for the generic ones, in three tiers:
///
/// 1. keyword rules — exact word-prefix matches on the task's own words
/// ("Shopping list created" → bag), precise and explainable;
/// 2. semantic — Apple's on-device word embedding (`NLEmbedding`) maps the
/// long tail the rules don't know ("Hamburger run" → food → fork.knife)
/// by nearest category anchor, gated by a strict distance threshold so
/// it prefers silence over a wrong guess;
/// 3. a quiet clipboard — reads "a task", never "a machine".
///
/// Cost: the embedding is a lazily-loaded local asset (no network) and every
/// resolved (symbol, title, subtitle) is memoized, so a task pays the lookup
/// once — microseconds after the first load.
public enum TaskIcon {
    /// Backend values that carry no real signal — the mapper's own defaults
    /// and the UI's last-resort glyphs. A symbol outside this set was chosen
    /// deliberately and always wins.
    private static let genericSymbols: Set<String> = ["", "gearshape", "storefront", "sparkles", "list.clipboard"]

    /// The no-signal, no-match fallback: reads "a task", not "a machine".
    public static let fallback = "list.clipboard"

    /// Whether a symbol carries no real signal — the mapper defaults, the
    /// UI's last-resort glyphs, and this resolver's own fallback. Task
    /// surfaces swap these for the brand mark (the default task icon is the
    /// persona logo, not machinery — design).
    public static func isGeneric(_ symbol: String) -> Bool {
        genericSymbols.contains(symbol.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Ordered first-match-wins keyword rules. Each pattern matches at a word
    /// start (`\b` + prefix), so "grocer" covers "groceries" without "order"
    /// swallowing "border".
    private static let rules: [(pattern: String, symbol: String)] = [
        ("schedul|calendar|agenda|itinerar|appointment|meeting", "calendar"),
        ("shop|grocer|cart|buy|purchas|order", "bag"),
        ("restaurant|reservation|dinner|lunch|brunch|meal|food|takeout", "fork.knife"),
        ("call|phone|dial|voicemail", "phone"),
        ("email|mail|reply|inbox", "envelope"),
        ("flight|airline|airport|travel|trip", "airplane"),
        ("ride|uber|lyft|taxi", "car"),
        ("pay|invoice|bill|refund|subscription|receipt", "creditcard"),
        ("remind", "bell"),
        ("draft|writ|document|essay", "doc.text"),
        ("fix|repair|maintenance|plumb|handyman|leak", "wrench.and.screwdriver"),
        ("gift|birthday|present", "gift"),
        ("doctor|dentist|pharmac|prescription|refill", "cross.case"),
        // Last on purpose: "find/search" ride along in half of all task
        // titles ("Find a plumber", "Finding a table") — the specific rules
        // above must win before this generic one mops up true research asks.
        ("research|search|find|compar|look up", "magnifyingglass"),
    ]

    private static let compiled: [(regex: NSRegularExpression, symbol: String)] = rules.compactMap { rule in
        guard let regex = try? NSRegularExpression(pattern: "\\b(?:\(rule.pattern))") else { return nil }
        return (regex, rule.symbol)
    }

    /// Semantic anchors per symbol — a task word within `semanticThreshold`
    /// (cosine distance) of ANY anchor claims the symbol; the closest pair
    /// across all categories wins. Calibrated against the English embedding:
    /// true pairs land ≤ ~1.05 (vet↔doctor 1.049, taxes↔payment 0.995,
    /// hamburger↔food 0.963, dinner↔restaurant 1.001), noise sits ≥ ~1.2
    /// (soccer↔shopping 1.218, blinds↔repair 1.255).
    private static let anchors: [(words: [String], symbol: String)] = [
        (["schedule", "calendar", "appointment", "meeting"], "calendar"),
        (["shopping", "groceries", "store"], "bag"),
        (["restaurant", "dinner", "food", "lunch"], "fork.knife"),
        (["call", "phone"], "phone"),
        (["email", "message"], "envelope"),
        (["flight", "airport", "vacation"], "airplane"),
        (["ride", "taxi", "drive"], "car"),
        (["payment", "invoice", "taxes", "money"], "creditcard"),
        (["reminder"], "bell"),
        (["document", "essay", "writing"], "doc.text"),
        (["repair", "plumbing", "maintenance", "broken"], "wrench.and.screwdriver"),
        (["gift", "birthday"], "gift"),
        (["doctor", "pharmacy", "medicine", "dentist", "veterinarian"], "cross.case"),
        (["research"], "magnifyingglass"),
    ]
    private static let semanticThreshold = 1.06

    /// Words too common to carry a category on their own — either function
    /// words or task-title furniture ("plan", "list") whose nearest anchors
    /// would tint every card the same way.
    private static let stopwords: Set<String> = [
        "the", "and", "for", "with", "your", "this", "that", "about", "from",
        "get", "got", "was", "were", "are", "has", "have", "had", "will",
        "you", "them", "then", "than", "when", "what", "week", "today",
        "tomorrow", "new", "next", "last", "make", "made", "want", "wants",
        "need", "needs", "created", "create", "plan", "list", "task", "help",
    ]

    /// The embedding + memo cache behind one lock: `NLEmbedding` isn't
    /// Sendable and its thread-safety is undocumented, so all access is
    /// serialized. Lookups are microseconds; contention is a non-issue at
    /// card-render scale.
    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        lazy var embedding: NLEmbedding? = NLEmbedding.wordEmbedding(for: .english)
        var memo: [String: String] = [:]
    }
    private static let box = Box()

    /// Fires once, on the first resolve: loads the embedding off-main so a
    /// later semantic-tier miss finds it ready instead of paying the ~100ms
    /// asset load inside a card render. The immediate caller continues
    /// synchronously (keyword tier needs no embedding); the detached task
    /// races nothing — it just holds the lock briefly while loading.
    private static let warmup: Void = {
        Task.detached(priority: .utility) { loadEmbedding() }
    }()

    /// Synchronous on purpose: NSLock is source-banned in async contexts on
    /// the iOS SDK, so the detached warmup hops through this sync frame.
    private static func loadEmbedding() {
        box.lock.lock()
        _ = box.embedding
        box.lock.unlock()
    }

    /// The glyph for a task: its own backend icon when specific, else the
    /// first keyword rule its title/subtitle matches, else the semantically
    /// nearest category, else the clipboard.
    public static func resolve(backendSymbol: String, title: String, subtitle: String = "") -> String {
        let trimmed = backendSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard genericSymbols.contains(trimmed) else { return trimmed }
        _ = warmup

        let key = "\(title)|\(subtitle)"
        box.lock.lock()
        if let hit = box.memo[key] {
            box.lock.unlock()
            return hit
        }
        box.lock.unlock()

        let resolved = resolveUncached(title: title, subtitle: subtitle)

        box.lock.lock()
        // A runaway memo can't happen at task-deck scale, but cap it anyway.
        if box.memo.count > 512 { box.memo.removeAll(keepingCapacity: true) }
        box.memo[key] = resolved
        box.lock.unlock()
        return resolved
    }

    private static func resolveUncached(title: String, subtitle: String) -> String {
        let haystack = "\(title) \(subtitle)".lowercased()

        // Tier 1: exact keyword rules.
        let range = NSRange(haystack.startIndex..., in: haystack)
        for (regex, symbol) in compiled where regex.firstMatch(in: haystack, range: range) != nil {
            return symbol
        }

        // Tier 2: semantic nearest-anchor over the task's content words.
        let words = haystack
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopwords.contains($0) && Int($0) == nil }
            .prefix(12)
        if !words.isEmpty {
            box.lock.lock()
            defer { box.lock.unlock() }
            if let embedding = box.embedding {
                var best: (distance: Double, symbol: String)?
                for word in words where embedding.contains(word) {
                    for (anchorWords, symbol) in anchors {
                        for anchor in anchorWords {
                            let distance = embedding.distance(between: word, and: anchor)
                            if distance <= semanticThreshold, distance < (best?.distance ?? .infinity) {
                                best = (distance, symbol)
                            }
                        }
                    }
                }
                if let best { return best.symbol }
            }
        }

        // Tier 3: nothing matched — a task, not a machine.
        return fallback
    }
}

public extension ActiveTask {
    /// The badge glyph the task surfaces render — see `TaskIcon.resolve`.
    var displayIconSymbol: String {
        TaskIcon.resolve(backendSymbol: vendorSymbol, title: title, subtitle: subtitle)
    }
}

public extension DeepTask {
    /// The glyph the chat surfaces render (thread header via `vitals`, the
    /// in-chat task chip) — same resolver as the Home cards, so a task wears
    /// ONE icon everywhere. The goal doubles as the subtitle; for pre-title
    /// tasks `displayTitle` IS the goal and the duplication is harmless.
    var displayIconSymbol: String {
        TaskIcon.resolve(backendSymbol: iconSymbol ?? "", title: displayTitle, subtitle: goal)
    }
}
