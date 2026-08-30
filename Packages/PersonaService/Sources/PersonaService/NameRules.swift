import Foundation

/// THE client half of the name-validation contract — same numbers the backend
/// enforces in `backend/src/services/users/name-rules.ts`. Every surface that
/// edits a name (onboarding naming screen, Settings → Names) clamps and gates
/// through this, so a name accepted anywhere is accepted everywhere.
public enum NameRules {
    /// What the assistant is named (`pref.assistant_name`).
    public static let assistantName = 2 ... 24
    /// What the assistant calls the user (`pref.name`).
    public static let nickname = 1 ... 40

    /// Live-typing clamp: single line, hard length cap. Trimming for the
    /// length GATE happens at commit (`isValid`), not here — mid-typing spaces
    /// must survive.
    public static func clamp(_ input: String, to range: ClosedRange<Int>) -> String {
        let singleLine = input
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return String(singleLine.prefix(range.upperBound))
    }

    /// Commit gate: the trimmed value fits the range.
    public static func isValid(_ input: String, for range: ClosedRange<Int>) -> Bool {
        range.contains(input.trimmingCharacters(in: .whitespacesAndNewlines).count)
    }

    /// The one human-readable rule, shown verbatim when a commit fails the
    /// gate (mirrors the backend's zod message).
    public static func requirement(for range: ClosedRange<Int>) -> String {
        String(localized: "Use \(range.lowerBound)–\(range.upperBound) characters.")
    }
}
