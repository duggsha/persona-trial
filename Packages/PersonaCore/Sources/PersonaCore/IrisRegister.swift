import Foundation

/// The user's picked voice register (`pref.tone`), mirrored on the client.
///
/// Every line the BACKEND writes already lands in this register — chat, the
/// home greeting, notifications, calls (see `core/persona.ts`). The lines the
/// APP writes for itself (a greeting fallback, an empty-state panel) used to
/// ignore it entirely, which is how a formal user got "good evening!" with an
/// exclamation mark their assistant would never type.
///
/// Normalization mirrors the backend's `toneFromPreference` exactly — the same
/// production values ("Casual", "Formal.", "very casual") have to resolve the
/// same way on both sides, or the two halves of the product speak differently
/// to the same person.
public enum IrisRegister: String, Sendable, CaseIterable {
    case veryCasual
    case casual
    case formal

    /// The default for anyone who never picked (matches the backend's).
    public static let fallback: IrisRegister = .casual

    public init?(preference: String?) {
        guard let raw = preference else { return nil }
        // A stored value can be a bare label or a quoted one inside a sentence
        // ("Preferred reply tone: \"formal\"") — take the quoted part first.
        let quoted: String? = {
            guard let open = raw.firstIndex(of: "\"") else { return nil }
            let rest = raw.index(after: open)
            guard let close = raw[rest...].firstIndex(of: "\"") else { return nil }
            return String(raw[rest ..< close])
        }()
        let label = (quoted ?? raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!,;: "))
        switch label {
        case "very casual": self = .veryCasual
        case "casual": self = .casual
        case "formal": self = .formal
        default: return nil
        }
    }

    /// The register in force right now, for the non-view code that writes a
    /// user-facing string (the home greeting fallback in `HomeMapper`).
    /// `ProfileStore` sets it from the cached preference at launch and again on
    /// every load; views with the store in their environment should read it
    /// from there instead.
    @MainActor public static var current: IrisRegister = .fallback
}
