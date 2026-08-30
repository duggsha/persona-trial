import PersonaDesign
import SwiftUI

/// Muted `(bg, glyph)` pair (adaptive: light pastel / hue-tinted charcoal) for an automation template's category — used
/// to tint the row's icon circle so the gallery reads with a little color
/// instead of a wall of grey. Matched case-insensitively on the backend's
/// category label; anything unknown or absent falls back to the neutral
/// surface + inked glyph the rows used before.
///
/// Shared by the onboarding `AutomationsScreen` and Settings' template gallery
/// so both surfaces tint identically.
func automationCategoryTint(_ category: String?) -> (bg: Color, glyph: Color) {
    switch category?.trimmingCharacters(in: .whitespaces).lowercased() {
    case "mail": return (Color(light: 0xE8F1FB, dark: 0x1E2A38), Color(light: 0x3B76C2, dark: 0x7FB0E8))
    case "money": return (Color(light: 0xE6F4EA, dark: 0x203524), Color(light: 0x2E8B57, dark: 0x5EC98B))
    case "travel": return (Color(light: 0xFDF1E0, dark: 0x362C1C), Color(light: 0xC77E2D, dark: 0xE8A85C))
    case "calendar": return (Color(light: 0xEDEAFB, dark: 0x27233C), Color(light: 0x6D5BD0, dark: 0x9C8BEB))
    // Meetings wears Calendar's purple — the standing Meetings card always
    // used it, and the category grew out of Calendar's turf.
    case "meetings": return (Color(light: 0xEDEAFB, dark: 0x27233C), Color(light: 0x6D5BD0, dark: 0x9C8BEB))
    case "health": return (Color(light: 0xFBEAEE, dark: 0x361F26), Color(light: 0xC05070, dark: 0xE87F9C))
    case "daily rhythm": return (Color(light: 0xFDF6E3, dark: 0x35301D), Color(light: 0xB8922B, dark: 0xDDBA55))
    case "productivity": return (Color(light: 0xE9F0F4, dark: 0x232D33), Color(light: 0x4A6A7B, dark: 0x8AAABB))
    case "people": return (Color(light: 0xE9F6F6, dark: 0x1E3232), Color(light: 0x3A9188, dark: 0x67C2B8))
    case "home": return (Color(light: 0xEEF4E9, dark: 0x27301F), Color(light: 0x5F8A46, dark: 0x93BE79))
    case "fun": return (Color(light: 0xF6EAF9, dark: 0x2F2233), Color(light: 0x9A55B8, dark: 0xC489DE))
    default: return (DS.Palette.surfaceMuted, DS.Palette.ink.opacity(0.62))
    }
}

/// SF Symbol for a category label — templates carry their own per-row icons,
/// but the browse-by-category rows need one icon PER category. Matched the
/// same way as the tint so the two always agree.
func automationCategoryIcon(_ category: String?) -> String {
    switch category?.trimmingCharacters(in: .whitespaces).lowercased() {
    case "mail": return "envelope.fill"
    case "money": return "dollarsign.circle.fill"
    case "travel": return "airplane"
    case "calendar": return "calendar"
    case "meetings": return "video.fill"
    case "health": return "heart.fill"
    case "daily rhythm": return "sun.max.fill"
    case "productivity": return "checkmark.circle.fill"
    case "people": return "person.2.fill"
    case "home": return "house.fill"
    case "fun": return "party.popper.fill"
    default: return "square.grid.2x2.fill"
    }
}
