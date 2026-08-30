import Foundation
import PersonaCore
#if canImport(Contacts)
    import Contacts
#endif
#if canImport(UIKit)
    import UIKit
#endif

/// The LOCAL rung of the contact-avatar ladder: the photo already sitting in the
/// user's address book, read straight from Contacts at render time.
///
/// The backend serves these same faces (ContactsSync uploads every thumbnail,
/// `/v1/contacts/photos/:id` streams them back), and for anyone who ISN'T in the
/// address book — a mail correspondent, a person mined from a calendar invite —
/// that remote photo is the only one there is. But when the contact IS local,
/// paying a round trip for bytes already on the device is the laggy way to get
/// the same pixels: a people list is hundreds of avatars, and each remote one is
/// an authenticated request that reads bytes out of Postgres. This rung answers
/// from local storage in microseconds and costs no network at all.
///
/// Rules it holds to:
/// - **Never prompts.** Only reads when access is ALREADY granted; a card
/// scrolling into view must never raise a permission sheet. Without access
/// this is a no-op and the remote rungs carry the avatar as before.
/// - **Never blocks the main thread.** Lookups run on a detached utility task;
/// the synchronous entry point only ever consults the in-memory cache.
/// - **Remembers misses.** A handle with no local photo is cached as such, so
/// scrolling a list of non-contacts doesn't re-query Contacts per frame.
/// - **Never guesses a face.** Addresses and numbers are identities and match
/// outright; a name only counts when it's a full one AND exactly one contact
/// carries it. Showing the wrong person beats showing no one, never.
enum DeviceContactPhotos {
    /// The handles a person is reachable at, in preference order.
    struct Handles: Equatable, Hashable, Sendable {
        /// Their display name — the LAST resort, and only when it's a full one
        /// (see `matchableName`). Most People-page rows are people memory
        /// recognised by name alone and carry no address or number at all; for
        /// the ones the address book also knows, the name is the only bridge to
        /// their face.
        var name: String? = nil
        var emails: [String] = []
        var phones: [String] = []

        var isEmpty: Bool { normalizedEmails.isEmpty && normalizedPhones.isEmpty && matchableName == nil }

        /// Lowercased, trimmed, blank-free — matched against Contacts as-is.
        var normalizedEmails: [String] {
            emails
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { $0.contains("@") }
        }

        /// Kept in their original form: `CNPhoneNumber` matching does its own
        /// normalisation, and is better at it than we would be.
        var normalizedPhones: [String] {
            phones
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count >= 7 }
        }

        /// The name we're willing to match a face on: a FULL one (two or more
        /// words). A first name alone — "design", "Margaret", the shape most
        /// memory-derived people arrive in — matches a stranger in the address
        /// book as easily as the right person, and the wrong face is worse than
        /// no face. Nil when there's nothing safe to match.
        var matchableName: String? {
            guard let name else { return nil }
            let collapsed = name
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard collapsed.split(separator: " ").count >= 2 else { return nil }
            return collapsed
        }

        /// Stable cache key across the whole handle set.
        var key: String {
            "device:" + (normalizedEmails + normalizedPhones + [matchableName ?? ""]).joined(separator: "|")
        }
    }

    #if canImport(UIKit)

        /// Cached lookups, including misses (`nil` value = "asked, nothing there").
        /// Small: address-book thumbnails are a few KB and only visible rows ever
        /// land here.
        private static let cache = Cache()

        private final class Cache: @unchecked Sendable {
            private var entries: [String: UIImage?] = [:]
            private let lock = NSLock()

            func value(_ key: String) -> UIImage?? {
                lock.lock()
                defer { lock.unlock() }
                return entries[key]
            }

            func store(_ image: UIImage?, for key: String) {
                lock.lock()
                defer { lock.unlock() }
                entries[key] = image
            }

            func clear() {
                lock.lock()
                defer { lock.unlock() }
                entries.removeAll()
            }
        }

        /// Whether the address book is readable RIGHT NOW, without prompting.
        /// iOS 18's `.limited` counts: the user picked a subset to share, and a
        /// contact inside that subset is fair game.
        private static var canRead: Bool {
            #if canImport(Contacts)
                switch CNContactStore.authorizationStatus(for: .contacts) {
                case .authorized: return true
                case .limited: return true
                default: return false
                }
            #else
                return false
            #endif
        }

        /// The cached answer, if we already have one. Synchronous and lock-only —
        /// safe to call from a view's `init` so a recycled row paints the right
        /// face on its FIRST frame instead of flashing initials.
        static func cachedImage(for handles: Handles) -> UIImage? {
            guard !handles.isEmpty else { return nil }
            guard let entry = cache.value(handles.key) else { return nil }
            return entry
        }

        /// True once we've looked this handle set up and found nothing — lets the
        /// caller skip straight to the remote ladder without awaiting again.
        static func isKnownMiss(_ handles: Handles) -> Bool {
            guard !handles.isEmpty, let entry = cache.value(handles.key) else { return false }
            return entry == nil
        }

        /// Look up the address-book thumbnail for any of these handles. Returns
        /// nil when access isn't granted, no contact matches, or the match has no
        /// photo — all of which are cached as a miss.
        static func image(for handles: Handles) async -> UIImage? {
            guard !handles.isEmpty else { return nil }
            let key = handles.key
            if let entry = cache.value(key) { return entry }
            guard canRead else { return nil } // NOT cached: access can be granted later.

            let image = await Task.detached(priority: .utility) { () -> UIImage? in
                lookup(handles)
            }.value
            cache.store(image, for: key)
            return image
        }

        /// Sign-out / permission change: drop what we read from the address book.
        static func clear() {
            cache.clear()
        }

        #if canImport(Contacts)
            /// One indexed Contacts query per handle, stopping at the first photo.
            /// Thumbnail-only key set, so this never pulls a full-size image.
            /// A handle match is exact by construction — an address or number is
            /// an identity — so any of them wins outright; the name rung below
            /// only runs when none of them matched.
            private static func lookup(_ handles: Handles) -> UIImage? {
                let store = CNContactStore()
                let keys = [CNContactThumbnailImageDataKey as CNKeyDescriptor]

                for email in handles.normalizedEmails {
                    let predicate = CNContact.predicateForContacts(matchingEmailAddress: email)
                    if let image = firstPhoto(store, predicate, keys) { return image }
                }
                for phone in handles.normalizedPhones {
                    let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: phone))
                    if let image = firstPhoto(store, predicate, keys) { return image }
                }
                return photoByName(store, handles.matchableName)
            }

            /// The name rung: the address book's own entry for someone we know
            /// only by name. `predicateForContacts(matchingName:)` is a loose
            /// token search ("Michael Mauboussin" also returns every other
            /// Michael), so a match only counts when the contact's formatted
            /// name EQUALS the one we asked for, ignoring case and accents. And
            /// it must be the ONLY such contact: two people who share a name
            /// leave us with no way to tell whose face this is, and a card
            /// showing the wrong person is a worse answer than initials.
            private static func photoByName(_ store: CNContactStore, _ name: String?) -> UIImage? {
                guard let name else { return nil }
                let keys: [CNKeyDescriptor] = [
                    CNContactThumbnailImageDataKey as CNKeyDescriptor,
                    CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
                ]
                let predicate = CNContact.predicateForContacts(matchingName: name)
                guard let matches = try? store.unifiedContacts(matching: predicate, keysToFetch: keys) else { return nil }

                let exact = matches.filter { contact in
                    guard let formatted = CNContactFormatter.string(from: contact, style: .fullName) else { return false }
                    return sameName(formatted, name)
                }
                guard exact.count == 1, let data = exact[0].thumbnailImageData else { return nil }
                return UIImage(data: data)
            }

            /// Name equality as a person would read it: case, accents and runs of
            /// whitespace don't make two names different.
            private static func sameName(_ lhs: String, _ rhs: String) -> Bool {
                func normalize(_ value: String) -> String {
                    value.split(whereSeparator: \.isWhitespace)
                        .joined(separator: " ")
                        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                }
                return normalize(lhs) == normalize(rhs)
            }

            private static func firstPhoto(
                _ store: CNContactStore,
                _ predicate: NSPredicate,
                _ keys: [CNKeyDescriptor]
            ) -> UIImage? {
                guard let matches = try? store.unifiedContacts(matching: predicate, keysToFetch: keys) else { return nil }
                for contact in matches {
                    if let data = contact.thumbnailImageData, let image = UIImage(data: data) { return image }
                }
                return nil
            }
        #else
            private static func lookup(_: Handles) -> UIImage? { nil }
        #endif

    #endif
}

extension ChatCard.ContactPerson {
    /// The card's own handles, as the local photo lookup's input.
    var deviceHandles: DeviceContactPhotos.Handles {
        DeviceContactPhotos.Handles(name: name, emails: emailHandles, phones: phoneHandles)
    }
}
