import Foundation
import Observation
import PersonaCore
import PersonaService

/// The trial's composition root.
///
/// There is no API client to build and no session to restore: `PersonaService`
/// holds no network layer at all in this build. This just makes the four stores
/// the Home surfaces read and pins them to `MockHomeData` before the first
/// frame. Nothing here — or anywhere below it — can reach the network.
@MainActor
@Observable
final class TrialEnvironment {
    let home = HomeStore()
    let profile = ProfileStore()
    let settings = SettingsStore()
    let deepTasks = DeepTaskStore()

    init() {
        profile.seedForDesignTrial(
            name: MockHomeData.userName,
            assistantName: MockHomeData.assistantName,
            avatarUrl: MockHomeData.accountAvatarUrl
        )
        home.seedForDesignTrial(
            greeting: MockHomeData.greeting,
            location: MockHomeData.location,
            chatShortcuts: MockHomeData.chatShortcuts,
            suggestions: MockHomeData.suggestions
        )
    }
}
