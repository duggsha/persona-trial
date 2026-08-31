import PersonaService
import PersonaUI
import SwiftUI

/// Design trial. One window, one screen: the real Home page over dummy data.
@main
struct PersonaTrialApp: App {
    @State private var environment = TrialEnvironment()

    var body: some Scene {
        WindowGroup {
            DesignTrialHost(messages: MockHomeData.messages)
                // The redesign commits to dark. This surface is an operator's
                // instrument — Jarvis, not a companion — and the deck's whole
                // contrast system (ink on near-black, hairlines, one accent)
                // is tuned for it. Light remains reachable through tokens; it
                // is just no longer the default story.
                .preferredColorScheme(.dark)
                // The four stores the Home surfaces read. All seeded, all
                // local, none of them able to fetch anything.
                .environment(environment.home)
                .environment(environment.profile)
                .environment(environment.settings)
                .environment(environment.deepTasks)
        }
    }
}
