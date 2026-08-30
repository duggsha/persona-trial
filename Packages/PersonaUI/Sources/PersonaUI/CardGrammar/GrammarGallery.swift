import PersonaDesign
import SwiftUI

// The gallery: every drawing at feed width, grouped with the cards it is
// meant to be indistinguishable from — checking a card is a glance down a
// column, not a memory test. QA hook: GRAMMAR_PREVIEW=1 shows this screen;
// GRAMMAR_PREVIEW_LAND=<case-id> pins one drawing for a screenshot.

public struct GrammarGallery: View {
    private struct Band: Identifiable {
        let title: String
        let cases: [GrammarCase]
        var id: String { title }
    }

    private let bands: [Band] = [
        Band(title: "T1 · the core five", cases: [
            .opportunity, .money, .mailReconnect, .accountReview, .invite, .suggestTime, .draftedReply,
        ]),
        Band(title: "T1 · carrying a cast", cases: [
            .matter, .draftedReplyThread, .suggestTimeThread,
        ]),
        Band(title: "T1 · slots switched off", cases: [
            .startsSoon, .walletPass, .fyi, .packageWaiting,
        ]),
        Band(title: "T2 · live trackers", cases: [.orderProgress, .ride]),
        Band(title: "T3 · the sanctioned exception", cases: [.signInCode]),
        Band(title: "Lifecycle", cases: [.answered]),
    ]

    private let pinned: GrammarCase?
    private let pinnedSheet: GrammarSheetCase?
    private let pinnedClearing: Bool

    public init() {
        let land = ProcessInfo.processInfo.environment["GRAMMAR_PREVIEW_LAND"]
        pinned = land.flatMap(GrammarCase.init(rawValue:))
        pinnedSheet = land.flatMap(GrammarSheetCase.init(rawValue:))
        pinnedClearing = land == "clearing"
    }

    public var body: some View {
        if pinnedClearing {
            ScrollView {
                GrammarClearingDemo()
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            }
            .background(DS.Palette.canvas)
        } else if let pinned {
            // The land: one drawing on the canvas, nothing else — a stable
            // frame for shot-to-shot comparison against grammar.html.
            GrammarCaseView(grammarCase: pinned)
                .frame(width: GrammarChrome.feedWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.Palette.canvas)
        } else if let pinnedSheet {
            // Sheets outgrow the screen; the land scrolls so a tall drawing
            // is still shot in one pass at full width.
            ScrollView {
                pinnedSheet.view
                    .frame(width: GrammarChrome.feedWidth)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            }
            .background(DS.Palette.canvas)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(bands) { band in
                        VStack(alignment: .leading, spacing: 14) {
                            Text(band.title)
                                .font(.system(size: 18, weight: .semibold))
                                .tracking(-0.27)
                                .foregroundStyle(DS.Palette.ink)
                            ForEach(band.cases) { grammarCase in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(grammarCase.tag)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(DS.Palette.subtle)
                                    GrammarCaseView(grammarCase: grammarCase)
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Clearing, and the shuffle behind it")
                            .font(.system(size: 18, weight: .semibold))
                            .tracking(-0.27)
                            .foregroundStyle(DS.Palette.ink)
                        Text("Accept, and watch the four cards below. The card pops out of its own plane first; only then does the row close — and that is the shuffle.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DS.Palette.subtle)
                            .fixedSize(horizontal: false, vertical: true)
                        GrammarClearingDemo()
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Text("The sheets")
                            .font(.system(size: 18, weight: .semibold))
                            .tracking(-0.27)
                            .foregroundStyle(DS.Palette.ink)
                        ForEach(GrammarSheetCase.allCases) { sheetCase in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(sheetCase.tag)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(DS.Palette.subtle)
                                sheetCase.view
                            }
                        }
                    }
                }
                .frame(width: GrammarChrome.feedWidth)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
            }
            .background(DS.Palette.canvas)
        }
    }
}

#Preview("Gallery") {
    GrammarGallery()
}
