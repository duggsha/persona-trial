import PersonaDesign
import SwiftUI

// The deck: every drawing in grammar.html, payload-for-payload. This is mock
// data for the visual build — the strings are the prototype's own, so a
// simulator shot can be checked against the page column-for-column.

enum GrammarDrawing {
    case t1(GrammarT1Model)
    case t2(GrammarT2Model)
    case t3(GrammarT3Model)
    /// The lifecycle drawing: a header whose pills gave way to the settled chip.
    case settled(GrammarT1Model, String)
}

enum GrammarCase: String, CaseIterable, Identifiable {
    case opportunity
    case money
    case mailReconnect = "mail-reconnect"
    case accountReview = "account-review"
    case invite
    case suggestTime = "suggest-time"
    case draftedReply = "drafted-reply"
    case matter
    case draftedReplyThread = "drafted-reply-thread"
    case suggestTimeThread = "suggest-time-thread"
    case startsSoon = "starts-soon"
    case walletPass = "wallet-pass"
    case fyi
    case packageWaiting = "package-waiting"
    case orderProgress = "order-progress"
    case ride
    case signInCode = "sign-in-code"
    case answered

    var id: String { rawValue }

    /// The gallery's label — the `.sp-tag` above each drawing.
    var tag: String {
        switch self {
        case .opportunity: "Opportunity · with a verdict"
        case .money: "Money"
        case .mailReconnect: "Mail reconnect"
        case .accountReview: "Account review"
        case .invite: "Invite · can I say yes?"
        case .suggestTime: "Suggest a time · is Thursday free?"
        case .draftedReply: "Drafted reply · is Friday 2 clear?"
        case .matter: "Matter"
        case .draftedReplyThread: "Drafted reply · thread"
        case .suggestTimeThread: "Suggest a time · thread"
        case .startsSoon: "Starts soon · no body"
        case .walletPass: "Wallet pass · no body, no evidence"
        case .fyi: "FYI · no body, no actions"
        case .packageWaiting: "Package waiting · header only"
        case .orderProgress: "Order progress"
        case .ride: "Ride"
        case .signInCode: "Sign-in code"
        case .answered: "Answered"
        }
    }

    var drawing: GrammarDrawing {
        switch self {
        case .opportunity:
            .t1(.init(
                mark: .pin,
                title: "Chef’s counter pop-up on Ossington",
                subtitle: "Fri Sep 4 · Ossington & Argyle · from $85",
                meta: .age("2d"),
                body: "Twelve seats, and it’s the chef you saved from the Bar Isabel list.",
                verdict: .init(text: "Nothing booked Friday Sep 4"),
                pills: [.init(label: "Book it", fill: .primary, icon: .agent)]
            ))
        case .money:
            .t1(.init(
                mark: .creditCard,
                title: "$2,340 due Sep 3",
                subtitle: "Amex statement · autopay off",
                meta: .age("3h"),
                // A finding read out of your OWN past statements, not out of
                // the bill that arrived — so it is a verdict, not a body.
                verdict: .init(text: "Nothing unusual — same as last month, ±$40."),
                pills: [
                    .init(label: "Check this bill", fill: .primary, icon: .agent),
                    .init(label: "Remind me Sep 1", fill: .secondary, icon: nil),
                ]
            ))
        case .mailReconnect:
            .t1(.init(
                mark: .glyphAsset("LogoGmail"),
                title: "Gmail stopped syncing",
                subtitle: "xuealan101@gmail.com",
                meta: nil,
                body: "Iris can’t see new mail until you reconnect the account.",
                pills: [.init(label: "Reconnect Gmail", fill: .primary, icon: .external)]
            ))
        case .accountReview:
            .t1(.init(
                mark: .shieldCheck,
                title: "Two subscriptions renew Tuesday",
                subtitle: "Figma · News Daily — $31",
                meta: nil,
                // "haven’t opened since June" is read out of your own mail,
                // and it is the whole reason Cancel the trial is safe to press.
                verdict: .init(text: "Figma ($16) and a news trial you haven’t opened since June ($15). Want me to cancel the trial?"),
                pills: [
                    .init(label: "Cancel the trial", fill: .primary, icon: .agent),
                    .init(label: "Keep both", fill: .secondary, icon: nil),
                ]
            ))
        case .invite:
            .t1(.init(
                mark: .person("IM"),
                title: "Dinner with the design team",
                subtitle: "Thu Aug 27, 6:30 PM · Bar Raval",
                meta: .chevronUp,
                verdict: .init(text: "Nothing else booked Thursday evening"),
                pills: [
                    .init(label: "Accept", fill: .commit, icon: nil),
                    .init(label: "Can’t make it", fill: .secondary, icon: nil),
                ]
            ))
        case .suggestTime:
            .t1(.init(
                mark: .person("MC"),
                title: "Marisa needs a walkthrough time for Unit 4B",
                subtitle: "Marisa Chen · Apex Properties",
                meta: .age("27m", unread: true),
                body: "The re-tile finished early — she needs 45 minutes between 10 and 4.",
                verdict: .init(text: "Thursday 10 AM is your only free 45 minutes"),
                pills: [
                    .init(label: "Thursday, 10:00 AM", fill: .commit, icon: nil, weight: 1.55),
                    .init(label: "Others", fill: .secondary, icon: .sheet),
                ]
            ))
        case .draftedReply:
            .t1(.init(
                mark: .person("DP"),
                title: "Confirm Friday 2 PM with Dana?",
                subtitle: "Dana Prasad · Design review",
                meta: .age("1h", unread: true),
                body: "Dana asked to move your review — Friday 2 is the slot she proposed.",
                verdict: .init(text: "Nothing else booked Friday afternoon"),
                pills: [.init(label: "Read the draft", fill: .primary, icon: .mail)]
            ))
        case .matter:
            .t1(.init(
                mark: .pile(.init(initials: "D", tint: .warm), .init(initials: "D", tint: .cool)),
                title: "Call Debi to break the impasse?",
                subtitle: "Unsigned 44 days",
                meta: .age("27m"),
                body: "Debi and David are at a standstill on flat fee scope and QuickBooks pricing.",
                pills: [
                    .init(label: "Call Debi", fill: .primary, icon: .agent),
                    .init(label: "Read the emails", fill: .secondary, icon: .mail),
                ]
            ))
        case .draftedReplyThread:
            .t1(.init(
                mark: .pile(.init(initials: "D", tint: .warm), .init(initials: "D", tint: .cool)),
                title: "BDO engagement letter: call Debi to break the impasse?",
                subtitle: "Unsigned 44 days",
                meta: .age("2h", unread: true),
                body: "Debi and David are at a standstill on flat fee scope and QuickBooks pricing.",
                pills: [.init(label: "Read & reply", fill: .primary, icon: .mail)]
            ))
        case .suggestTimeThread:
            .t1(.init(
                mark: .pile(.init(initials: "M", tint: .warm), .init(initials: "D", tint: .cool)),
                title: "Unit 4B walkthrough: Marisa needs times, David needs to be there",
                subtitle: "Nothing booked",
                meta: .age("27m", unread: true),
                body: "She wants 45 minutes this week between 10 and 4; he can do any day but Wednesday.",
                verdict: .init(text: "Thursday 10 AM is the only slot that clears both"),
                pills: [.init(label: "Read & reply", fill: .primary, icon: .mail)]
            ))
        case .startsSoon:
            .t1(.init(
                mark: .brandAsset("LogoGoogleMeet"),
                title: "Standup",
                subtitle: "In 15 min · Google Meet · 4 going",
                meta: .age("9:30"),
                pills: [.init(label: "Join Meet", fill: .meet, icon: .external)]
            ))
        case .walletPass:
            .t1(.init(
                mark: .service("AC"),
                title: "AC 759 · YYZ → SFO",
                subtitle: "Boards 7:45 · Gate D22 · Window seat",
                meta: .age("Tue"),
                pills: [.init(label: "Add to Wallet", fill: .wallet, icon: nil)]
            ))
        case .fyi:
            .t1(.init(
                mark: .envelope,
                title: "Cancellation confirmed",
                subtitle: "Gallo Nero · Sat Aug 30, 8:00 PM",
                meta: .age("2h")
            ))
        case .packageWaiting:
            .t1(.init(
                mark: .tileAsset("LogoAmazonTile"),
                title: "Your running shoes are waiting at the front desk",
                subtitle: "Arrived 9:12 AM",
                meta: .age("9h", unread: true)
            ))
        case .orderProgress:
            .t2(.init(
                lockup: .doorDash,
                trailingFact: "18 min away",
                status: "The courier is nearby",
                detail: "Kiin",
                stops: ["Placed", "Confirmed", "Ready", "On the way", "Delivered"],
                currentStop: 3,
                brandTint: GrammarPalette.brandDoorDash
            ))
        case .ride:
            .t2(.init(
                lockup: .lyft,
                trailingFact: "3 min to pickup",
                status: "Driver on the way",
                detail: "Marcus · 4.9★ · Black Toyota Camry · ABC 123",
                stops: ["Requested", "Assigned", "Arrived", "On trip"],
                currentStop: 1,
                brandTint: nil
            ))
        case .signInCode:
            .t3(.init(
                eyebrow: "Anthropic · sign-in code",
                countdown: "4:38",
                code: "645 201"
            ))
        case .answered:
            .settled(
                .init(
                    mark: .person("MC"),
                    title: "Marisa needs a walkthrough time for Unit 4B",
                    subtitle: "Marisa Chen · Apex Properties",
                    meta: .age("27m")
                ),
                "Sent to Marisa — Thursday, 10:00 AM"
            )
        }
    }
}

/// Renders any deck case — the gallery's cell and the land rig's subject.
struct GrammarCaseView: View {
    let grammarCase: GrammarCase

    var body: some View {
        switch grammarCase.drawing {
        case let .t1(model):
            GrammarT1Card(model: model)
        case let .t2(model):
            GrammarT2Tracker(model: model)
        case let .t3(model):
            GrammarT3Code(model: model)
        case let .settled(header, text):
            VStack(alignment: .leading, spacing: 12) {
                GrammarT1Header(mark: header.mark, title: header.title, subtitle: header.subtitle, meta: header.meta)
                GrammarSettledChip(text: text)
            }
            .grammarCardPlate()
        }
    }
}
