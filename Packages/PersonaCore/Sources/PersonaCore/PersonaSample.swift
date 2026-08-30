import Foundation

/// Static placeholder content for the design build. Swap for live data behind
/// a repository protocol when the backend is wired in.
public enum PersonaSample {
    public static let location = "Miami, FL · 84°"
    public static let greeting = "good morning!"

    public static let meeting = MeetingSummary(
        title: "meeting in 30 mins",
        body: "dont forget! you have a meeting with your lawyer in 30 minutes about the lawsuit with that pussy.",
        joinLabel: "join meeting",
        joinLink: "https://meet.google.com/sample-join"
    )

    public static let quickActions: [QuickAction] = [
        QuickAction(title: "New reminder", symbol: "bell.badge", seedPrompt: "Create a new reminder for me."),
        QuickAction(title: "New email", symbol: "envelope.badge", seedPrompt: "Help me write a new email.")
    ]

    public static let tasks: [ActiveTask] = [
        ActiveTask(
            appImage: "LogoDoorDash",
            title: "Order placed",
            subtitle: "Ordering you dinner",
            timeRemaining: "4m 23s",
            progress: 0.11,
            vendor: "Joe’s Pizza",
            vendorSymbol: "storefront",
            itemsSummary: "2 cheese · caesar · 1 pepperoni slice",
            status: "In progress",
            detail: "Joe’s Pizza · 2 cheese · caesar · 1 pepperoni slice",
            isActive: true
        ),
        ActiveTask(
            appImage: "LogoDoorDash",
            title: "Dinner delivered",
            subtitle: "Joe’s Pizza arrived",
            timeRemaining: "Yesterday",
            progress: 1,
            status: "Completed",
            detail: "Left at the front desk at 8:18 PM",
            isActive: false,
            historySection: "Today",
            completedDuration: "18m"
        ),
        ActiveTask(
            appImage: "ThumbMeet",
            title: "Lawyer reply sent",
            subtitle: "Email drafted and sent",
            timeRemaining: "Today",
            progress: 1,
            status: "Completed",
            detail: "Confirmed friday availability and asked for exact times",
            isActive: false,
            historySection: "Today",
            completedDuration: "4m"
        ),
        ActiveTask(
            appImage: "LogoDoorDash",
            title: "Reminder created",
            subtitle: "Dinner reminder set",
            timeRemaining: "Today",
            progress: 1,
            status: "Completed",
            detail: "Reminder set for 6:00 PM before dinner",
            isActive: false,
            historySection: "Today",
            completedDuration: "12s"
        ),
        ActiveTask(
            appImage: "ThumbMeet",
            title: "Meeting joined",
            subtitle: "Lawyer call opened",
            timeRemaining: "Fri",
            progress: 1,
            status: "Completed",
            detail: "Joined the call and kept notes ready",
            isActive: false,
            historySection: "Yesterday",
            completedDuration: "32m"
        ),
        ActiveTask(
            appImage: "LogoDoorDash",
            title: "Breakfast ordered",
            subtitle: "Uber Eats checkout",
            timeRemaining: "Thu",
            progress: 1,
            status: "Completed",
            detail: "Bagels and two coffees delivered",
            isActive: false,
            historySection: "June 26",
            completedDuration: "24m"
        )
    ]

    /// The featured (active) task shown on the home card.
    public static var task: ActiveTask {
        tasks.first(where: \.isActive) ?? tasks[0]
    }

    public static let suggestions: [Suggestion] = [
        Suggestion(
            avatar: "AvatarSarah",
            message: "Sarah wrote back 8 pm works for her",
            action: "Draft",
            detail: "Want me to reply to lara about friday dinner?",
            isOpen: true
        ),
        Suggestion(
            avatar: "AvatarLawyer",
            message: "Your lawyer sent you a document with a draft about the lawsuit and wants to know if you can meet on friday",
            action: "Schedule",
            detail: "Your calendar is open. Want me to say yes and see what times he proposes?",
            badge: "Schedule",
            isOpen: true
        ),
        Suggestion(
            avatar: "AvatarJason",
            message: "Jason wrote back 8 pm works for her",
            action: "Draft",
            detail: "Want me to reply to lara about friday dinner?",
            isOpen: false,
            handledResult: "Replied that friday dinner at 8 works."
        )
    ]

    public static let chatMessages: [ChatMessage] = [
        ChatMessage(text: "morning", isUser: true, time: "9:41 AM"),
        ChatMessage(text: "Good morning. You have\nthree things coming up.", isUser: false, time: "9:41 AM"),
        ChatMessage(text: "What needs attention?", isUser: true, time: "9:42 AM"),
        ChatMessage(
            text: "Your lawyer needs a reply,\nSarah confirmed dinner,\nand your order is en route.",
            isUser: false,
            time: "9:42 AM"
        ),
        ChatMessage(text: "Draft the lawyer reply", isUser: true, time: "9:43 AM"),
        ChatMessage(text: "Sure. I’ll keep it short\nand ask for friday times.", isUser: false, time: "9:43 AM"),
        ChatMessage(text: "Also remind me at 6", isUser: true, time: "9:44 AM"),
        ChatMessage(text: "Done. I’ll remind you\nbefore dinner.", isUser: false, time: "9:44 AM"),
        ChatMessage(text: "I can order breakfast\non Uber Eats", isUser: true, time: "9:45 AM"),
        ChatMessage(
            text: "I can order breakfast\non Uber Eats",
            isUser: false,
            time: "9:45 AM",
            threadID: breakfastThreadID
        )
    ]

    public static let breakfastThreadID = UUID()

    public static let threads: [ChatThread] = [
        ChatThread(
            id: breakfastThreadID,
            title: "Breakfast Order",
            messages: [
                ChatMessage(text: "I’ll handle the breakfast order.", isUser: false, time: "9:45 AM"),
                ChatMessage(text: "Looking for nearby options on Uber Eats.", isUser: false, time: "9:45 AM"),
                ChatMessage(text: "Found a bagel place with 20 minute delivery.", isUser: false, time: "9:46 AM"),
                ChatMessage(text: "Can you make it something with coffee too?", isUser: true, time: "9:46 AM"),
                ChatMessage(text: "Yes. I’ll add two coffees and keep watching checkout.", isUser: false, time: "9:47 AM")
            ]
        )
    ]
}
