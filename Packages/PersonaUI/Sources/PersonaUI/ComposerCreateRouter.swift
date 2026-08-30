import Combine
import Foundation

/// Bridges the composer's + menu to HomeScreen's create sheets (mail compose /
/// reminder). The composer lives on the chat page while the sheets — with
/// their sender accounts and the undo-send queue — live in HomeScreen, a
/// separate subtree under the pager, so a shared observable is the channel
/// that crosses between them. HomeScreen stays mounted under the pager
/// on either page (a sheet presents fine from the off-screen page), consumes
/// `pending`, and clears it. Same singleton shape as NotificationRouter, and
/// for the same reason: HomeScreen's Equatable conformance is always-true, so
/// only an observed object reliably invalidates it.
@MainActor
final class ComposerCreateRouter: ObservableObject {
    static let shared = ComposerCreateRouter()
    private init() {}

    enum Request: Equatable {
        case reminder
        case email
    }

    @Published var pending: Request?
}
