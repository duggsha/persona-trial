import PersonaDesign
import SwiftUI

// The sheet drawings: grammar.html's `sheet-for-*` columns, payload-for-
// payload. Every card opens a sheet (R8) and the sheet shows the artifact
// (R7) — these are the templates the artifacts arrive in: the embedded
// email, the day grid, the fields plate, the drafted reply. Design only;
// nothing here is wired.

enum GrammarSheetCase: String, CaseIterable, Identifiable {
    case suggestTimeSheet = "sheet-suggest-time"
    case inviteSheet = "sheet-invite"
    case accountReviewSheet = "sheet-account-review"
    case threadSheet = "sheet-thread"
    case draftedReplySheet = "sheet-drafted-reply"
    case draftCard = "draft-card"

    var id: String { rawValue }

    var tag: String {
        switch self {
        case .suggestTimeSheet: "Suggest a time · the sheet"
        case .inviteSheet: "Calendar invite · the sheet"
        case .accountReviewSheet: "Account review · the sheet"
        case .threadSheet: "Suggest a time · thread · the sheet"
        case .draftedReplySheet: "Drafted reply · the sheet"
        case .draftCard: "The draft, in the flow"
        }
    }

    @ViewBuilder
    var view: some View {
        switch self {
        case .suggestTimeSheet:
            GrammarSheetFrame(height: 1050) {
                GrammarSheetScaffold(
                    title: "Unit 4B walkthrough",
                    suggestions: ["What else is on Thursday?", "When did she last reschedule?"],
                    composerHint: "Suggest other time"
                ) {
                    VStack(spacing: 12) {
                        GrammarContextQuote(model: .init(
                            initials: "M",
                            tint: .marisa,
                            who: "Marisa Chen · Apex Properties",
                            when: "9:14 AM",
                            quote: "“The re-tile finished a day early, so I can do the final walkthrough this week. **What times are you free?** I’d need about 45 minutes, anywhere between 10 and 4.”",
                            openLabel: "View email"
                        ))
                        GrammarDayGridCard(model: Self.pickerGrid)
                    }
                }
            }
        case .inviteSheet:
            GrammarSheetFrame(height: 626) {
                GrammarSheetScaffold(
                    title: "Dinner with the design team",
                    suggestions: ["Who hasn’t answered?", "What’s my Friday morning?"],
                    composerHint: "Ask about this invite"
                ) {
                    GrammarDayGridCard(model: Self.inviteGrid)
                }
            }
        case .accountReviewSheet:
            GrammarSheetFrame(height: 669) {
                GrammarSheetScaffold(
                    title: "News Daily — renewal",
                    subtitle: "Trial ends Tuesday · $15/month",
                    suggestions: ["What else renews this month?", "What has it cost me so far?"],
                    composerHint: "Ask about this renewal"
                ) {
                    VStack(spacing: 12) {
                        GrammarMailMessage(model: .init(
                            initials: "ND",
                            tint: .service,
                            name: "News Daily",
                            date: "Aug 25 at 7:02 AM",
                            paragraphs: [
                                "Your trial ends Tuesday and your subscription will renew at **$15/month**.",
                                "You can manage or cancel your subscription any time in **Account › Billing**.",
                            ]
                        ))
                        GrammarFieldsCard(model: .init(
                            rows: [
                                ("Cancelling", "News Daily · $15 a month from Tuesday"),
                                ("Because", "Last opened June 3 — eleven weeks ago"),
                                ("Keeping", "Figma · $16, renews the same day"),
                            ],
                            pill: .init(label: "Cancel at News Daily", fill: .primary, icon: .external)
                        ))
                    }
                }
            }
        case .threadSheet:
            GrammarSheetFrame(height: 505) {
                GrammarSheetScaffold(
                    title: "Unit 4B walkthrough",
                    suggestions: ["What else is on Thursday?", "When were we last at 4B?"],
                    composerHint: "Ask about this thread"
                ) {
                    VStack(spacing: 12) {
                        GrammarMailMessage(model: .init(
                            initials: "M",
                            tint: .warm,
                            name: "Marisa Chen",
                            date: "Today at 9:14 AM",
                            paragraphs: ["The re-tile finished a day early, so I can do the final walkthrough this week. **What times are you free?** I’d need about 45 minutes, anywhere between 10 and 4."]
                        ))
                        GrammarMailMessage(model: .init(
                            initials: "D",
                            tint: .cool,
                            name: "David Reyes",
                            date: "Today at 10:02 AM",
                            paragraphs: ["I should be there for the walkthrough — any day but Wednesday works on my end."]
                        ))
                    }
                }
            }
        case .draftedReplySheet:
            GrammarSheetFrame(height: 683) {
                GrammarSheetScaffold(
                    title: "Review move — Friday 2 PM?",
                    suggestions: ["What else is on Friday?", "Can you make it shorter?"],
                    composerHint: "Reply to Dana — Persona handles it"
                ) {
                    VStack(alignment: .leading, spacing: 0) {
                        GrammarMailMessage(model: .init(
                            initials: "D",
                            tint: .marisa,
                            name: "Dana Park",
                            date: "Today at 11:40 AM",
                            paragraphs: ["Alan — something came up Thursday. Could we move the review to **Friday at 2**? Same room."]
                        ))
                        GrammarThreadBubble(text: "Drafted a yes to Dana for Friday at 2. Good to send?")
                            .padding(.top, 18)
                        GrammarDraftCard(model: .init(
                            showsBrand: false,
                            fields: [
                                ("To", "dana@studio.co"),
                                ("Subject", "Re: Friday instead?"),
                            ],
                            paragraphs: ["Friday at 2 works — see you then."]
                        ))
                        .padding(.top, 10)
                    }
                }
            }
        case .draftCard:
            GrammarDraftCard(model: .init(
                fields: [
                    ("From", "xuealan101@gmail.com"),
                    ("To", "marisa@apexpropertiesllc.com"),
                    ("Subject", "Re: Unit 4B walkthrough — Thursday instead of Monday?"),
                ],
                paragraphs: [
                    "Thursday works — let’s say 2:00. I’ll be there for the full 45 minutes.",
                    "The contractor can take the scaffolding down.",
                    "Sent by Persona",
                ]
            ))
        }
    }

    // MARK: - Grid payloads (positions in points, as the prototype inlines them)

    /// The picker: Thursday drawn with Marisa's window shaded, Persona's two
    /// slots dashed at their real position and length.
    static let pickerGrid = GrammarDayGridModel(
        head: ("MC", "Marisa Chen asked", "What times are you free?"),
        chips: [.text("45 min"), .text("between 10 and 4"), .text("by tomorrow")],
        days: [
            .init(name: "Today", number: "25", free: "2 open"),
            .init(name: "Wed", number: "26", free: "full", state: .full),
            .init(name: "Thu", number: "27", free: "6 open", state: .selected),
            .init(name: "Fri", number: "28", free: "6 open"),
        ],
        column: .init(
            hours: ["9 AM", "10 AM", "11 AM", "12 PM", "1 PM", "2 PM", "3 PM", "4 PM", "5 PM"],
            hourStep: 44,
            bands: [
                .init(top: 0, height: 44, label: "Marisa asked for 10–4"),
                .init(top: 308, height: 44, label: nil, labelAtBottom: false),
            ],
            busy: [
                .init(top: 0, height: 22, title: "Standup", when: nil),
                .init(top: 154, height: 48, title: "Deposit call — Apex", when: "12:30"),
                .init(top: 308, height: 33, title: "School pickup", when: "4:00"),
            ],
            ghosts: [
                .init(top: 44, height: 33, time: "10:00 – 10:45 AM", starred: true, why: "before your 12:30"),
                .init(top: 198, height: 33, time: "1:30 – 2:15 PM", why: "clear till 4"),
            ]
        ),
        hint: "Tap a dashed block to take Persona’s pick, tap any open space for 45 minutes, or drag to set your own.",
        foot: .commit("Pick a time")
    )

    /// The invite: the picker's plate with the day tabs and the tap hint
    /// switched off — one day, and you are not choosing a time.
    static let inviteGrid = GrammarDayGridModel(
        head: ("IM", "Isa Moreno invited you", "Can you make Thursday?"),
        chips: [
            .text("2 hours"),
            .text("Bar Raval"),
            .cast(
                [
                    .init(initials: "I", tint: .cool),
                    .init(initials: "D", tint: .warm),
                    .init(initials: "M", tint: .service),
                ],
                "Seven of nine"
            ),
        ],
        column: .init(
            hours: ["5 PM", "6 PM", "7 PM", "8 PM", "9 PM"],
            hourStep: 56,
            ghosts: [.init(top: 84, height: 112, time: "6:30 – 8:30 PM")]
        ),
        foot: .pair([
            .init(label: "Accept", fill: .commit, icon: nil),
            .init(label: "Can’t make it", fill: .secondary, icon: nil),
        ])
    )

}
