import PersonaDesign
import SwiftUI

/// THE snooze preset list — one set of times everywhere something can be
/// deferred.
/// Consumed by the reminder chat card, the reminder list card's re-time menu,
/// and the suggestion/update cards' long-press menu.
struct SnoozePreset: Identifiable, Sendable {
    /// Menu row label ("10 minutes", …, "Tomorrow morning").
    let label: String
    /// Undo-toast copy for surfaces with a deferred commit (Home cards).
    let toast: String
    /// Resolved at PICK time, not list-build time — "Tomorrow morning" is a
    /// wall-clock target, and the offsets should count from the tap.
    let until: @Sendable () -> Date
    var id: String { label }

    static let all: [SnoozePreset] = [
        .init(label: "10 minutes", toast: "Snoozed for 10 minutes.") { Date().addingTimeInterval(10 * 60) },
        .init(label: "1 hour", toast: "Snoozed for 1 hour.") { Date().addingTimeInterval(3_600) },
        .init(label: "3 hours", toast: "Snoozed for 3 hours.") { Date().addingTimeInterval(3 * 3_600) },
        .init(label: "Tomorrow morning", toast: "Snoozed until tomorrow morning.") { tomorrowMorning() },
    ]

    /// 9:00 AM tomorrow — shared clock for the "Tomorrow morning" preset
    /// (was duplicated in ReminderChatCard and ReminderListCard).
    static func tomorrowMorning() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.startOfDay(for: Date()).addingTimeInterval(86_400)
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow.addingTimeInterval(9 * 3600)
    }
}

/// The preset rows for any snooze `Menu`/context submenu — every surface
/// renders the identical list, so the options can never drift apart again.
struct SnoozePresetButtons: View {
    let onPick: (SnoozePreset) -> Void

    var body: some View {
        ForEach(SnoozePreset.all) { preset in
            Button {
                onPick(preset)
            } label: {
                Text(String(localized: String.LocalizationValue(preset.label)))
            }
        }
    }
}

/// The Home cards' long-press menu — the SAME native context-menu treatment
/// as a chat bubble's Copy/Reply: the system lifts the
/// card on its own rounded plate and shows Reply plus a Snooze submenu (the
/// system draws the chevron) carrying the shared presets. Native is fine here
/// because these cards are white plates like chat bubbles — only the task
/// rows' interactive liquid glass needs the hand-rolled TaskStopMenu.
struct CardContextMenu: ViewModifier {
    /// Off = no menu at all: an empty context menu would still hijack the
    /// long-press (same rule as `deleteContextMenu`). Surfaces that can't act
    /// (reply previews, demo rigs, code/wallet rows) stay inert.
    var isEnabled = true
    /// The lifted preview traces the card's plate.
    var cornerRadius: CGFloat = DS.Radius.card
    let onReply: () -> Void
    /// nil hides the Snooze submenu (the surface can't snooze).
    var onSnooze: ((SnoozePreset) -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .contentShape(
                    .contextMenuPreview,
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .contextMenu {
                    Button {
                        DSHaptics.tap(.light)
                        onReply()
                    } label: {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                    }
                    if let onSnooze {
                        Menu {
                            SnoozePresetButtons { preset in
                                DSHaptics.tap(.light)
                                onSnooze(preset)
                            }
                        } label: {
                            // The reminders' snooze glyph — one snooze look
                            // across chat and Home.
                            Label("Snooze", systemImage: "moon.zzz.fill")
                        }
                    }
                }
        } else {
            content
        }
    }
}

extension View {
    /// Attach the shared card long-press menu (Reply / Snooze ›).
    func cardContextMenu(
        isEnabled: Bool = true,
        cornerRadius: CGFloat = DS.Radius.card,
        onReply: @escaping () -> Void,
        onSnooze: ((SnoozePreset) -> Void)? = nil
    ) -> some View {
        modifier(CardContextMenu(
            isEnabled: isEnabled,
            cornerRadius: cornerRadius,
            onReply: onReply,
            onSnooze: onSnooze
        ))
    }
}
