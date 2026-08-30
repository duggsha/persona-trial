import Foundation

/// What to CALL a mail attachment on a card.
///
/// A card row saying "INV-8837_ACME_final_v2.pdf" is a filename, not a name —
/// the user has to parse it to learn it's the invoice. Real attachment
/// filenames almost always contain the noun that matters ("Invoice_8837.pdf",
/// "signed-lease.pdf", "BoardingPass.pdf"), so pulling that noun out gets a
/// human label for the common case with no model call, no latency, and no
/// per-provider metadata to go wrong.
///
/// When nothing recognizable is in there, it degrades by file TYPE rather than
/// guessing — "See PDF" is honest where "See document" pretends to know.
public enum MailAttachmentName {
    /// The nouns worth naming, longest-first so "boarding pass" wins over the
    /// bare "pass" and "purchase order" over "order". Each maps to the word the
    /// row shows, which is not always the word matched ("cv" reads as "resume").
    private static let nouns: [(needle: String, label: String)] = [
        ("boarding pass", "boarding pass"), ("boardingpass", "boarding pass"),
        ("purchase order", "purchase order"),
        ("bank statement", "statement"),
        ("pay stub", "payslip"), ("paystub", "payslip"), ("payslip", "payslip"),
        ("shipping label", "shipping label"),
        ("presentation", "presentation"),
        ("certificate", "certificate"),
        ("transcript", "transcript"),
        ("itinerary", "itinerary"),
        ("agreement", "agreement"),
        ("statement", "statement"),
        ("proposal", "proposal"),
        ("contract", "contract"),
        ("estimate", "estimate"),
        ("invoice", "invoice"),
        ("receipt", "receipt"),
        ("summary", "summary"),
        ("ticket", "ticket"),
        ("resume", "resume"),
        ("report", "report"),
        ("waiver", "waiver"),
        ("policy", "policy"),
        ("permit", "permit"),
        ("lease", "lease"),
        ("quote", "quote"),
        ("offer", "offer"),
        ("deck", "deck"),
        ("form", "form"),
        ("menu", "menu"),
        ("plan", "plan"),
        ("bill", "bill"),
        ("nda", "nda"),
        ("cv", "resume"),
    ]

    /// The row's label — "See invoice", "See PDF", "See attachment".
    public static func label(filename: String?, mimeType: String? = nil) -> String {
        if let noun = noun(in: filename) {
            return String(localized: "See \(noun)")
        }
        return String(localized: "See \(typeWord(filename: filename, mimeType: mimeType))")
    }

    /// The recognized noun in a filename, or nil. Separators become spaces so
    /// "signed-lease" and "signed_lease" read the same, and matching is on
    /// WORD boundaries — otherwise "planner" contains "plan" and "invoiced
    /// items" is fine but "province" would match "nda"-style fragments.
    static func noun(in filename: String?) -> String? {
        guard let filename, !filename.isEmpty else { return nil }
        let stem = (filename as NSString).deletingPathExtension
        var words = stem.lowercased()
        for separator in ["-", "_", ".", "+", "(", ")", "[", "]", "#", "/"] {
            words = words.replacingOccurrences(of: separator, with: " ")
        }
        // Digits glued to a word ("invoice8837") would hide the noun.
        words = words.replacingOccurrences(
            of: "[0-9]+", with: " ", options: .regularExpression
        )
        let padded = " \(words.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)) "
        for entry in nouns where padded.contains(" \(entry.needle) ") {
            return entry.label
        }
        return nil
    }

    /// The fallback: name the FILE TYPE, which we actually know, instead of
    /// guessing at contents we don't.
    static func typeWord(filename: String?, mimeType: String?) -> String {
        let ext = (filename.map { ($0 as NSString).pathExtension } ?? "").lowercased()
        let mime = (mimeType ?? "").lowercased()
        if ext == "pdf" || mime.contains("pdf") { return "PDF" }
        if mime.hasPrefix("image/") || ["png", "jpg", "jpeg", "heic", "gif", "webp"].contains(ext) {
            return String(localized: "image")
        }
        if ["doc", "docx", "pages", "rtf", "txt", "md"].contains(ext) || mime.contains("word") {
            return String(localized: "document")
        }
        if ["xls", "xlsx", "numbers", "csv"].contains(ext) || mime.contains("sheet") || mime.contains("excel") {
            return String(localized: "spreadsheet")
        }
        if ["ppt", "pptx", "key"].contains(ext) || mime.contains("presentation") {
            return String(localized: "slides")
        }
        return String(localized: "attachment")
    }
}
