import Foundation

/// Canonical `DeepTask` states for QA rigs and design labs.
///
/// Deliberately keyed to the DOMAIN MODEL, not to any surface: these are just
/// tasks in each phase the UI draws differently. Whatever renders them — the
/// composer's live-task tray, a transcript row, the Lock Screen / Dynamic
/// Island activity, the task thread — seeds from the same fixtures, so a rig
/// survives the surface being redesigned or moved (the delegation card has
/// already moved out of the transcript once).
///
/// Rigs that need a chat SCRIPT alongside these own that script themselves;
/// what lives here is only the store's side.
public enum DeepTaskFixtures {
    /// Every phase worth looking at, newest-feeling first.
    ///
    /// `createdAt` is always a RECENT offset from now, never a pinned epoch:
    /// the surfaces render elapsed time with `Text(_:style:.timer)`, which
    /// counts live from whatever date it is handed — a fixed past date can't
    /// freeze it, it only turns the clock into four-digit hours.
    public static func all() -> [DeepTask] {
        [working(), needsYouWithOptions(), needsYouFreeText(), done(), failed()]
    }

    /// Running, with live narration and a ticking clock.
    public static func working() -> DeepTask {
        DeepTask(
            id: "fixture-task-working",
            goal: "Send flowers to Mom for Thursday",
            status: "running",
            notes: [], iterations: 3, maxIterations: 40,
            result: nil, pendingInput: nil,
            statusLine: "comparing florists near her place",
            title: "Send flowers to Mom",
            createdAt: Date().addingTimeInterval(-134),
            iconSymbol: "gift.fill"
        )
    }

    /// Parked on the user with agent-supplied choices — the only state that
    /// raises a Live Activity, and the one whose buttons answer in place.
    public static func needsYouWithOptions() -> DeepTask {
        DeepTask(
            id: "fixture-task-options",
            goal: "Return the Zara order",
            status: "waiting",
            notes: [], iterations: 6, maxIterations: 40,
            result: nil,
            pendingInput: DeepTask.PendingInput(
                question: "UPS or FedEx for the pickup?",
                proposal: nil, kind: "input",
                options: ["UPS", "FedEx"]
            ),
            title: "Return the Zara order",
            createdAt: Date().addingTimeInterval(-620),
            iconSymbol: "shippingbox.fill"
        )
    }

    /// Parked on the user with NO choices — the answer has to be typed, so
    /// the activity offers a reply hand-off instead of buttons.
    public static func needsYouFreeText() -> DeepTask {
        DeepTask(
            id: "fixture-task-freetext",
            goal: "Book a table for Friday",
            status: "waiting",
            notes: [], iterations: 4, maxIterations: 40,
            result: nil,
            pendingInput: DeepTask.PendingInput(
                question: "They only have 6:30 or 9:00 tomorrow — anything else I should try?",
                proposal: nil, kind: "input"
            ),
            title: "Restaurant reservation",
            createdAt: Date().addingTimeInterval(-410),
            iconSymbol: "fork.knife"
        )
    }

    public static func done() -> DeepTask {
        DeepTask(
            id: "fixture-task-done",
            goal: "Find and book a quiet dinner spot for Friday, 2 people",
            status: "succeeded",
            notes: [], iterations: 9, maxIterations: 40,
            result: "Booked La Ciccia for 2, Friday 7:30 PM.",
            pendingInput: nil,
            title: "Book Friday dinner",
            createdAt: Date().addingTimeInterval(-2100),
            resultSummary: "Booked for 2, Friday 7:30 PM.",
            iconSymbol: "fork.knife"
        )
    }

    public static func failed() -> DeepTask {
        DeepTask(
            id: "fixture-task-failed",
            goal: "Call Amex and cancel the platinum card",
            status: "failed",
            notes: [], iterations: 12, maxIterations: 40,
            result: nil, pendingInput: nil,
            title: "Cancel the Amex card",
            createdAt: Date().addingTimeInterval(-1900),
            iconSymbol: "creditcard.fill"
        )
    }
}
