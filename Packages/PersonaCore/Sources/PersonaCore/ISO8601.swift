import Foundation

/// The one ISO-8601 parse/format pair for the whole app. Parsing tolerates the
/// backend's millisecond timestamps (`2026-06-23T21:40:39.663Z`) as well as
/// whole-second ones. The formatters are cached — init is expensive, and the
/// per-call `ISO8601DateFormatter()` copies this replaces were re-paying that
/// cost inside view bodies and mappers.
public enum ISO8601 {
    private nonisolated(unsafe) static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func parse(_ raw: String) -> Date? {
        withFraction.date(from: raw) ?? plain.date(from: raw)
    }

    /// Format an instant as `2026-06-28T13:00:00Z` (query parameters, wire
    /// payloads, share-sheet copy).
    public static func string(_ date: Date) -> String {
        plain.string(from: date)
    }
}
