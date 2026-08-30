import SwiftUI

/// The handful of shell-level types Home and the header still need after the
/// root pager (`PersonaRootView`) was cut from this trial. Lifted verbatim from
/// that file so the values Home lays itself out against are unchanged.

/// Shared layout constants so Home clears the floating header / composer.
enum PersonaLayout {
    static let contentTopInset: CGFloat = 58
    // Keep scroll content clear of the composer at its resting height: the bar
    // occupies ~90pt (36 rest height + ~54 bar), so anything
    // under ~90 tucks the last card beneath it; ~24pt breathing room on top
    // (the earlier bar rested at 67 → 138; the bar dropped 31pt → 107 read
    // "too little space", +7 air → 114 — tuned live).
    static let contentBottomInset: CGFloat = 114
}

/// Which page the header's toggle points at. The trial only ever renders
/// `.home`; `.chat` is kept so the toggle is the real two-state control rather
/// than a redrawn stand-in.
enum PersonaPage: Int, Hashable, CaseIterable {
    case home
    case chat
}

/// True while a root pager owns a latched-HORIZONTAL page drag — the feed
/// freezes its own vertical scrolling for exactly that gesture. The trial has
/// no pager, so nothing ever sets it; Home reads it exactly as it does in the
/// real app.
private struct PagerHorizontalDragKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var pagerHorizontalDragActive: Bool {
        get { self[PagerHorizontalDragKey.self] }
        set { self[PagerHorizontalDragKey.self] = newValue }
    }
}
