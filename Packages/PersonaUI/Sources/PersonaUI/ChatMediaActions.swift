import CryptoKit
import Foundation
import PersonaDesign
import SwiftUI
#if canImport(Photos)
    import Photos
#endif
#if canImport(UIKit)
    import UIKit
#endif

extension ChatViewerPhoto {
    /// Stable identity for the saved-to-Photos registry. Remote tiles key on
    /// their asset path (stable across reloads); local tiles on a content
    /// digest — `id`'s `data.hashValue` is seeded per launch, so it can't be
    /// the key of anything persisted.
    var savedKey: String {
        switch self {
        case let .remote(path):
            return "remote:\(path)"
        case let .local(data):
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return "local:\(digest.prefix(24))"
        }
    }
}

/// Save-to-Photos and native-share-sheet plumbing for chat media (photo tiles,
/// file tiles, delivered file cards). Kept out of the views so every surface
/// shares one permission flow and one "already saved" registry.
enum ChatMediaActions {
    // MARK: - Saved-to-Photos registry

    /// Photos this app has ALREADY written to the camera roll, so the menu can
    /// say "Saved to Photos" instead of quietly stacking duplicates. We can't
    /// see the user's library (add-only permission), so this only knows about
    /// our own saves — which is exactly the duplicate we could create.
    private static let savedKeysDefaultsKey = "chat.media.savedPhotoKeys"
    private static let savedKeysCap = 300

    @MainActor private static var savedKeys: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: savedKeysDefaultsKey) ?? []
    )

    @MainActor
    static func isSavedToPhotos(_ photo: ChatViewerPhoto) -> Bool {
        savedKeys.contains(photo.savedKey)
    }

    @MainActor
    private static func markSaved(_ key: String) {
        savedKeys.insert(key)
        var stored = UserDefaults.standard.stringArray(forKey: savedKeysDefaultsKey) ?? []
        stored.removeAll { $0 == key }
        stored.append(key)
        // Oldest-first trim: the registry is a courtesy, not a ledger.
        if stored.count > savedKeysCap { stored.removeFirst(stored.count - savedKeysCap) }
        UserDefaults.standard.set(stored, forKey: savedKeysDefaultsKey)
    }

    // MARK: - Save to Photos

    /// Returns whether the write actually landed, so a caller with its own
    /// "Saved" affordance only flips it on a CONFIRMED write.
    @MainActor @discardableResult
    static func saveToPhotos(_ photo: ChatViewerPhoto, loader: AuthorizedImageLoader?) async -> Bool {
        if let data = await resolveData(photo, loader: loader) {
            return await saveToPhotos(data: data, key: photo.savedKey)
        }
        // The tile is SHOWING pixels we couldn't re-fetch. Save what's on
        // screen rather than nothing — the viewer's button used to save this
        // cached image and only this, so failing here would be a regression.
        #if canImport(UIKit)
            if case let .remote(path) = photo,
               let cached = cachedChatPhotoPixels(forRemotePath: path),
               let encoded = cached.pngData() {
                return await saveToPhotos(data: encoded, key: photo.savedKey)
            }
        #endif
        return false
    }

    /// Write image bytes to the camera roll under add-only permission. Saves
    /// the ORIGINAL bytes (no decode → re-encode generation loss). Success
    /// gets the system double-tap haptic — a menu has closed by the time the
    /// write lands, so the buzz is the receipt.
    ///
    /// The main-actor half: permission, the "already saved" registry, and the
    /// receipt buzz. The library write itself must NOT live here — see
    /// `writePhotoToLibrary`, and do not fold it back in.
    @MainActor @discardableResult
    static func saveToPhotos(data: Data, key: String) async -> Bool {
        #if canImport(Photos) && canImport(UIKit)
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else { return false }
            // A false here is a denied-mid-flight or a library write error —
            // nothing usable to tell the user from here; the menu simply still
            // offers Save next time.
            guard await writePhotoToLibrary(data) else { return false }
            markSaved(key)
            DSHaptics.messageReceived()
            return true
        #else
            return false
        #endif
    }

    // MARK: - Share

    @MainActor
    static func share(_ photo: ChatViewerPhoto, loader: AuthorizedImageLoader?) {
        #if canImport(UIKit)
            Task {
                // Prefer the raw bytes (full quality, and the share sheet's own
                // "Save Image" row keeps working); fall back to the decoded
                // image the tile is showing (CachedRemoteImage's cache) if the
                // fetch fails — sharing what's on screen beats doing nothing.
                if let data = await resolveData(photo, loader: loader), let decoded = UIImage(data: data) {
                    presentShareSheet([decoded])
                } else if case let .remote(path) = photo,
                          let cached = cachedChatPhotoPixels(forRemotePath: path) {
                    presentShareSheet([cached])
                }
            }
        #endif
    }

    /// The native share sheet. UIKit presentation, not `ShareLink` — the
    /// payload is fetched async at tap time, after the menu's items were
    /// built.
    ///
    /// The context menu that triggered this is STILL DISMISSING when the
    /// button's action runs, and it dismisses through its own window, which
    /// is briefly the key window sitting above the app's. Presenting "over
    /// whatever is frontmost" therefore attached the sheet to a controller
    /// that was on its way out, and it never appeared (build 244). So: only
    /// ever present into the app's own normal-level window, and wait for the
    /// transition on top of it to finish first.
    @MainActor
    static func presentShareSheet(_ items: [Any]) {
        #if canImport(UIKit)
            guard !items.isEmpty else { return }
            present(items, attempt: 0)
        #endif
    }

    #if canImport(UIKit)
        /// ~0.6s of patience in 50ms steps: comfortably longer than the
        /// menu's dismissal, and it gives up rather than retrying forever if
        /// something else owns the screen.
        private static let presentRetryLimit = 12

        @MainActor
        private static func present(_ items: [Any], attempt: Int) {
            guard let top = presentableTop() else {
                guard attempt < presentRetryLimit else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    present(items, attempt: attempt + 1)
                }
                return
            }
            let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
            // iPhone-only today, but a popover anchor keeps this from crashing
            // if a regular-width presentation ever hosts it.
            sheet.popoverPresentationController?.sourceView = top.view
            top.present(sheet, animated: true)
        }

        /// The frontmost controller in the APP's window that can present right
        /// now — nil while a transition is in flight, so the caller retries.
        /// The window filter is the important half: the context menu's platter
        /// and other system overlays ride windows above `.normal`, and those
        /// are never a valid host for our sheet.
        @MainActor
        private static func presentableTop() -> UIViewController? {
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }?
                .windows
                .filter { $0.windowLevel == .normal && !$0.isHidden } ?? []
            let window = windows.first(where: \.isKeyWindow) ?? windows.first
            guard var top = window?.rootViewController else { return nil }
            while let presented = top.presentedViewController {
                // Something above us is mid-dismissal (the context menu, a
                // closing sheet) — presenting onto it is the bug we're fixing.
                if presented.isBeingDismissed { return nil }
                top = presented
            }
            return top.isBeingPresented || top.isBeingDismissed ? nil : top
        }
    #endif

    // MARK: - Bytes

    /// Local bytes are in hand; a remote path fetches like the tile rendered
    /// it (authorized loader for backend-relative paths, plain URLSession
    /// otherwise — `CachedRemoteImage.load`'s routing).
    private static func resolveData(_ photo: ChatViewerPhoto, loader: AuthorizedImageLoader?) async -> Data? {
        switch photo {
        case let .local(data):
            return data
        case let .remote(path):
            guard let url = URL(string: path) else { return nil }
            if let loader, url.scheme != "data" {
                return try? await loader(url)
            }
            return try? await URLSession.shared.data(from: url).0
        }
    }
}

/// The camera-roll write, at FILE SCOPE on purpose — that is what keeps it off
/// the main actor.
///
/// Moving to the async form of `performChanges` did not leave the trap behind
///. The change BLOCK is a plain non-Sendable closure:
/// written inside a `@MainActor` function it inherits the main actor, and the
/// compiler puts a `_checkExpectedExecutor` inside it — confirmed in SIL, not
/// guessed. Photos then runs that block on its own serial queue, the check
/// fails, and `dispatch_assert_queue` takes the whole app down with
/// EXC_BREAKPOINT — Save killed the app on every tap. Same shape as the
/// callbacks swept in, one call deeper.
///
/// A global function inherits no isolation, so the block has no executor to
/// check. Nothing in here touches UI; the isolated work stays in
/// `ChatMediaActions.saveToPhotos`.
private func writePhotoToLibrary(_ data: Data) async -> Bool {
    #if canImport(Photos)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }
            return true
        } catch {
            return false
        }
    #else
        return false
    #endif
}
