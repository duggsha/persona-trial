import PersonaDesign
import SwiftUI
import UniformTypeIdentifiers

/// One identity per file type — glyph, tint, and a short kind label — shared by
/// every surface that shows a file: the composer's staged tile, the sent-bubble
/// attachment tile, and the delivered-file card. Keyed on the file EXTENSION
/// first (a .md and a .csv both "conform to text/spreadsheet" yet deserve their
/// own identity), falling back to UTType family conformance for anything
/// unlisted. Tints follow the platform's attachment conventions (PDF red,
/// sheets green, slides orange…) softened toward the app's palette.
struct FileTypeBadge {
    let symbol: String
    let tint: Color
    /// Short type word for subtitles — "PDF", "CSV", "Document" as last resort.
    let kindLabel: String

    init(filename: String, mimeType: String? = nil) {
        let ext = (filename as NSString).pathExtension.lowercased()
        let utType = mimeType.flatMap { UTType(mimeType: $0) } ?? UTType(filenameExtension: ext)
        kindLabel = Self.kindLabel(ext: ext, utType: utType)
        if let known = Self.knownExtension(ext) {
            symbol = known.symbol
            tint = known.tint
        } else {
            symbol = Self.familySymbol(utType)
            tint = DS.Palette.accent
        }
    }

    private static func knownExtension(_ ext: String) -> (symbol: String, tint: Color)? {
        switch ext {
        case "pdf":
            ("doc.richtext.fill", Color(hex: 0xE0524D))
        case "doc", "docx", "rtf", "pages", "odt":
            ("doc.text.fill", Color(hex: 0x3478F6))
        case "xls", "xlsx", "numbers", "csv", "tsv", "ods":
            ("tablecells.fill", Color(hex: 0x2E9E5B))
        case "ppt", "pptx", "key", "odp":
            ("rectangle.on.rectangle.fill", Color(hex: 0xE8883A))
        case "md", "markdown":
            ("text.alignleft", Color(hex: 0x5B6470))
        case "txt", "log":
            ("doc.plaintext.fill", Color(hex: 0x5B6470))
        case "json", "yaml", "yml", "xml", "toml", "plist":
            ("curlybraces", Color(hex: 0x2F8F9D))
        case "swift", "py", "js", "ts", "tsx", "rb", "go", "java", "c", "cpp", "h", "sh", "sql":
            ("chevron.left.forwardslash.chevron.right", Color(hex: 0x6B5BD2))
        case "html", "htm":
            ("globe", Color(hex: 0x3478F6))
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "tiff":
            ("photo.fill", Color(hex: 0x9A56C7))
        case "mp3", "wav", "m4a", "aac", "flac", "ogg":
            ("waveform", Color(hex: 0xD6558E))
        case "mp4", "mov", "mkv", "webm", "avi":
            ("film.fill", Color(hex: 0x5865CF))
        case "zip", "tar", "gz", "7z", "rar":
            ("doc.zipper", Color(hex: 0x8A7250))
        case "ics":
            ("calendar", Color(hex: 0xE0524D))
        case "vcf":
            ("person.crop.square.fill", Color(hex: 0x5B6470))
        case "epub", "mobi":
            ("book.fill", Color(hex: 0xE8883A))
        default:
            nil
        }
    }

    /// UTType-family fallback for extensions the table doesn't name.
    private static func familySymbol(_ utType: UTType?) -> String {
        guard let utType else { return "doc.fill" }
        if utType.conforms(to: .image) { return "photo.fill" }
        if utType.conforms(to: .pdf) { return "doc.richtext.fill" }
        if utType.conforms(to: .spreadsheet) || utType == .commaSeparatedText { return "tablecells.fill" }
        if utType.conforms(to: .presentation) { return "rectangle.on.rectangle.fill" }
        if utType.conforms(to: .movie) { return "film.fill" }
        if utType.conforms(to: .audio) { return "waveform" }
        if utType.conforms(to: .archive) { return "doc.zipper" }
        if utType.conforms(to: .sourceCode) { return "chevron.left.forwardslash.chevron.right" }
        if utType.conforms(to: .text) { return "doc.text.fill" }
        return "doc.fill"
    }

    private static func kindLabel(ext: String, utType: UTType?) -> String {
        if !ext.isEmpty { return ext.uppercased() }
        if let fallback = utType?.preferredFilenameExtension { return fallback.uppercased() }
        return "Document"
    }
}
