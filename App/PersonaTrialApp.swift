import PersonaService
import PersonaUI
import SwiftUI

/// Design trial. One window, one screen: the real Home page over dummy data.
@main
struct PersonaTrialApp: App {
    @State private var environment = TrialEnvironment()
    /// Chosen in Profile. Dark is the default because the deck's contrast
    /// system is tuned for it, but light is a real, working theme rather than
    /// a token set nobody ever renders.
    @AppStorage("trial.appearance") private var appearance = "system"
    private var scheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: .dark
        }
    }

    var body: some Scene {
        WindowGroup {
            DesignTrialHost(messages: MockHomeData.messages)
                .preferredColorScheme(scheme)
                // The four stores the Home surfaces read. All seeded, all
                // local, none of them able to fetch anything.
                .environment(environment.home)
                .environment(environment.profile)
                .environment(environment.settings)
                .environment(environment.deepTasks)
        }
    }
}
