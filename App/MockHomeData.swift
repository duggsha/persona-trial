import Foundation
import PersonaCore

/// Every word on screen. Nothing here is fetched, cached or persisted — the
/// stores are pinned to these values at launch and never refresh, which is what
/// lets the trial run with the network off entirely.
enum MockHomeData {
    static let userName = "Tanay"
    static let assistantName = "Iris"
    static let greeting = "Evening, Tanay — your inbox is quiet."
    static let location = "San Francisco · 63°"

    private static func minutes(_ n: Int) -> Date { Date().addingTimeInterval(TimeInterval(n * 60)) }
    private static func hoursAgo(_ n: Int) -> Date { Date().addingTimeInterval(TimeInterval(-n * 3600)) }

    // MARK: - Chat starters under the greeting

    static let chatShortcuts: [QuickAction] = [
        QuickAction(title: "Summarize today", symbol: "text.line.first.and.arrowtriangle.forward",
                    seedPrompt: "Summarize my day"),
        QuickAction(title: "What did I miss?", symbol: "envelope.badge",
                    seedPrompt: "What did I miss today?"),
        QuickAction(title: "Plan tomorrow", symbol: "calendar",
                    seedPrompt: "Help me plan tomorrow")
    ]

    // MARK: - The card feed

    static let suggestions: [Suggestion] = [
        Suggestion(
            avatar: "AvatarSarah",
            message: "Sarah asked whether Thursday still works for the walkthrough.",
            action: "Draft",
            detail: "She needs an answer before she books the room.",
            badge: "Reply",
            contactEmail: "sarah@northwind.example",
            contactName: "Sarah Whitfield",
            actions: [
                SuggestionActionItem(
                    type: "send_draft",
                    label: "Send reply",
                    draftBody: "Thursday still works — 2pm at your office? I'll bring the printed boards."
                ),
                SuggestionActionItem(type: "acknowledge", label: "Dismiss")
            ],
            draftBody: "Thursday still works — 2pm at your office? I'll bring the printed boards.",
            createdAt: hoursAgo(1),
            section: .suggestions,
            kind: "send_draft",
            headline: "Reply to Sarah"
        ),
        Suggestion(
            avatar: "AvatarJason",
            message: "Jason wants 30 minutes this week to go over the firmware timeline.",
            action: "Schedule",
            detail: "Your Wednesday afternoon is open after 3.",
            badge: "Schedule",
            contactEmail: "jason@northwind.example",
            contactName: "Jason Mehta",
            actions: [
                SuggestionActionItem(type: "create_meeting", label: "Put it on Wednesday"),
                SuggestionActionItem(type: "acknowledge", label: "Not now")
            ],
            createdAt: hoursAgo(3),
            section: .suggestions,
            kind: "create_meeting"
        ),
        Suggestion(
            avatar: "",
            message: "The ramen place you saved has a table at 7:45 tonight.",
            action: "Book",
            detail: "Two seats at the counter — the only slot left before 9.",
            badge: "Book",
            systemIcon: "fork.knife",
            logoDomain: "resy.com",
            actions: [SuggestionActionItem(type: "open_link", label: "Open Resy")],
            createdAt: hoursAgo(4),
            section: .suggestions,
            kind: "place",
            facts: Suggestion.Facts(
                date: "Tonight, 7:45 PM",
                venue: "Marufuku Ramen · Japantown",
                price: "$$",
                url: "https://example.invalid/resy",
                verdict: "You're free — the design review ends at 7:15.",
                subtitle: "Saved three weeks ago"
            )
        ),
        Suggestion(
            avatar: "",
            message: "Your GitHub sign-in code is 481 902.",
            action: "Copy",
            detail: "Tap to copy the code.",
            badge: "Copy",
            systemIcon: "key.fill",
            logoDomain: "github.com",
            createdAt: Date().addingTimeInterval(-90),
            section: .updates,
            code: "481902",
            codeValidUntil: minutes(9),
            expiresAt: minutes(9),
            kind: "code"
        ),
        Suggestion(
            avatar: "",
            message: "Delta moved your Austin flight up by 40 minutes.",
            action: "See email",
            detail: "New departure is 9:05 AM out of SFO, gate unchanged.",
            badge: "Seen",
            systemIcon: "airplane.departure",
            logoDomain: "delta.com",
            createdAt: hoursAgo(6),
            section: .updates,
            kind: "update"
        )
    ]
}
