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
                // The four stores the Home surfaces read. All seeded, all
                // local, none of them able to fetch anything.
                .environment(environment.home)
                .environment(environment.profile)
                .environment(environment.settings)
                .environment(environment.deepTasks)
        }
    }
}
