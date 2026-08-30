import Foundation

/// Decides when the "Hold to record a voice memo" coach mark (the DSTooltip
/// over the main-chat composer) may appear. It rides the user's FIRST text
/// send: the moment they've just proven they text and haven't voiced is the
/// moment the hold gesture is worth teaching. Shown exactly once, ever, and
/// never to anyone who already sends voice memos.
///
/// (It used to wait for 100 text sends across two launches, which in practice
/// meant nobody ever saw it — including the people who shipped it.)
@MainActor
enum VoiceMemoTipGate {
    /// Text sends before the tip is allowed. ONE: the send itself is the cue.
    static let sendThreshold = 1
    /// A coach mark that comes back is a nag. One showing, then retired.
    static let maxShowings = 1

    private static let sendsKey = "voiceMemoTip.textSends"
    private static let everSentMemoKey = "voiceMemoTip.everSentVoiceMemo"
    private static let shownCountKey = "voiceMemoTip.shownCount"
    /// Belt-and-braces against a double offer inside one process.
    private static var offeredThisLaunch = false

    private static var defaults: UserDefaults { .standard }

    /// Every text send, from any composer surface. Call BEFORE `takeOffer()`
    /// — the offer reads the count this bumps.
    static func recordTextSend() {
        resetForQAIfRequested()
        defaults.set(defaults.integer(forKey: sendsKey) + 1, forKey: sendsKey)
    }

    /// Any voice memo, ever, from any surface — retires the tip permanently.
    static func recordVoiceMemoSend() {
        defaults.set(true, forKey: everSentMemoKey)
    }

    /// Consumes the one offer when the gate passes: the caller MUST present
    /// the tip on `true` (the showing is already counted). Called right after
    /// a TEXT send — a voice memo never offers, it retires the tip instead.
    static func takeOffer() -> Bool {
        resetForQAIfRequested()
        guard !offeredThisLaunch,
              !defaults.bool(forKey: everSentMemoKey),
              defaults.integer(forKey: sendsKey) >= sendThreshold,
              defaults.integer(forKey: shownCountKey) < maxShowings
        else { return false }
        offeredThisLaunch = true
        defaults.set(defaults.integer(forKey: shownCountKey) + 1, forKey: shownCountKey)
        return true
    }

    /// QA only (`VOICE_TIP_QA_FORCE=1`): present at launch without spending an
    /// offer, so a screenshot rig can shoot the bubble in the real bar.
    static var isForcedForQA: Bool {
        ProcessInfo.processInfo.environment["VOICE_TIP_QA_FORCE"] == "1"
    }

    /// QA only (`VOICE_TIP_QA_NEVER_VOICED=1`): pretend the TRANSCRIPT is
    /// silent, whatever it actually holds. Deliberately separate from the
    /// counter reset below, because the two rigs need opposite things and one
    /// flag doing both would leave the history check with no test at all:
    ///
    /// - the send→tip lifecycle test needs a user who has never voiced, but
    /// the QA sim carries live dev auth even under the preview hosts, so its
    /// "fresh user" is really an account with 17 voice memos in its last 200
    /// messages — the history check retires the tip before that test can see
    /// it. It sets BOTH flags.
    /// - the history test needs exactly that populated account, with only the
    /// counters cleared. It sets the reset flag ALONE and asserts no tip.
    static var pretendNeverVoicedForQA: Bool {
        ProcessInfo.processInfo.environment["VOICE_TIP_QA_NEVER_VOICED"] == "1"
    }

    /// QA only (`VOICE_TIP_QA_RESET=1`): clear the counters once per launch so
    /// the send→tip path is repeatable on a sim without reinstalling the app.
    private static var didResetForQA = false
    private static func resetForQAIfRequested() {
        guard !didResetForQA,
              ProcessInfo.processInfo.environment["VOICE_TIP_QA_RESET"] == "1"
        else { return }
        didResetForQA = true
        defaults.removeObject(forKey: sendsKey)
        defaults.removeObject(forKey: everSentMemoKey)
        defaults.removeObject(forKey: shownCountKey)
    }
}
