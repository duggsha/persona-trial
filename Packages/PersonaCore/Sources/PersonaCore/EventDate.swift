import Foundation

/// Formats a calendar event's start for display — from a Google/Graph ISO
/// `dateTime` (`2026-07-17T20:00:00-04:00`) or an all-day `date` (``).
///
/// The time is ANCHORED IN THE EVENT'S OWN TIME ZONE — the offset carried in the
/// string — never the device's. A dinner at 8 PM in New York reads "8:00 PM" on
/// a phone in any zone: an invite's time is only meaningful where the event
/// happens, so we must never silently convert it (a device in Berlin showing
/// "2:00 AM" for an 8 PM NYC dinner would be wrong AND confusing). Falls back to
/// the raw string if it can't be parsed, so the row is never worse than today.
public enum EventDate {
    public static func format(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return raw }

        // All-day event: date only, no time component. Rendered as the plain day
        // (parsed as UTC so the calendar date can't slip across a zone boundary).
        if !s.contains("T") {
            guard let day = dayOnlyParser.date(from: String(s.prefix(10))) else { return raw }
            return dayLabel.string(from: day)
        }

        // Timed event: parse to the absolute instant, then render it back in the
        // event's OWN offset so the wall-clock time is exactly what was invited.
        guard let instant = parseInstant(s) else { return raw }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEE, MMM d · h:mm a"
        formatter.timeZone = offsetZone(from: s) ?? .current
        return formatter.string(from: instant)
    }

    // MARK: - Parsing

    /// The instant behind a stored event date, for callers that need the DAY
    /// rather than a label (the card's "View event" fetches that day's events
    /// to open the real one). All-day strings parse as UTC midnight, the same
    /// anchor `format` uses, so the day can't slip across a zone boundary.
    public static func parse(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("T") { return dayOnlyParser.date(from: String(s.prefix(10))) }
        return parseInstant(s)
    }

    private static func parseInstant(_ s: String) -> Date? {
        ISO8601.parse(s)
    }

    /// The UTC offset embedded in the ISO string (`-04:00`, `+0200`, `Z`) as a
    /// fixed `TimeZone`, so the displayed time is the event's local wall-clock.
    /// `nil` when the string carries no offset (then the caller uses device time).
    private static func offsetZone(from s: String) -> TimeZone? {
        if s.hasSuffix("Z") { return TimeZone(identifier: "UTC") }
        guard let range = s.range(of: "[+-][0-9]{2}:?[0-9]{2}$", options: .regularExpression) else { return nil }
        let offset = s[range] // e.g. "-04:00"
        let sign = offset.hasPrefix("-") ? -1 : 1
        let digits = offset.dropFirst().filter(\.isNumber) // "0400"
        guard digits.count == 4,
              let hours = Int(digits.prefix(2)),
              let minutes = Int(digits.suffix(2)) else { return nil }
        return TimeZone(secondsFromGMT: sign * (hours * 3600 + minutes * 60))
    }

    // MARK: - Cached immutable parsers (formatter init is expensive)

    private nonisolated(unsafe) static let dayOnlyParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private nonisolated(unsafe) static let dayLabel: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEE, MMM d"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}
