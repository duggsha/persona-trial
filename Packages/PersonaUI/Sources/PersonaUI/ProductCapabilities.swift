import SwiftUI

/// Which optional feature surfaces the UI renders.
///
/// The app is one modular UI whose optional surfaces are switched on and off
/// here rather than forked per build. This trial renders a single profile, so
/// the flags exist only because Home's own code reads a few of them.
public struct ProductCapabilities: Equatable, Sendable {
    /// Rich inline chat cards. Off = text-only chat.
    public var chatCards: Bool
    /// Delegated deep-task thread view + needs-input banner.
    public var deepTasks: Bool
    /// The People page.
    public var peoplePage: Bool
    /// The Around (location) page.
    public var aroundPage: Bool
    /// The "Location & context" proactive-suggestions section on Home.
    public var locationSuggestions: Bool
    /// The Home "Other" section (informational mail cards).
    public var otherMailSection: Bool
    /// The developer model picker.
    public var devModelPicker: Bool
    /// The Home task dock. Off everywhere: running work rides the composer's
    /// task tray instead, so the dock would list the same tasks twice.
    public var homeTasks: Bool

    public init(
        chatCards: Bool,
        deepTasks: Bool,
        peoplePage: Bool,
        aroundPage: Bool,
        locationSuggestions: Bool,
        otherMailSection: Bool,
        devModelPicker: Bool,
        homeTasks: Bool = false
    ) {
        self.chatCards = chatCards
        self.deepTasks = deepTasks
        self.peoplePage = peoplePage
        self.aroundPage = aroundPage
        self.locationSuggestions = locationSuggestions
        self.otherMailSection = otherMailSection
        self.devModelPicker = devModelPicker
        self.homeTasks = homeTasks
    }

    /// Everything on.
    public static let full = ProductCapabilities(
        chatCards: true, deepTasks: true, peoplePage: true, aroundPage: true, locationSuggestions: true,
        otherMailSection: true, devModelPicker: true
    )

    /// The profile this build renders.
    public static var current: ProductCapabilities { .full }
}

private struct ProductCapabilitiesKey: EnvironmentKey {
    static let defaultValue: ProductCapabilities = .full
}

extension EnvironmentValues {
    public var capabilities: ProductCapabilities {
        get { self[ProductCapabilitiesKey.self] }
        set { self[ProductCapabilitiesKey.self] = newValue }
    }
}
