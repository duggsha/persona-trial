import Foundation

/// Tiny JSON-on-disk cache so a store can paint its last-known state *instantly*
/// on cold start, then refresh in the background — no empty-then-load flash.
///
/// Snapshots live in Caches/ (the OS may evict them under pressure, which is
/// fine: the store just refetches). Reads are synchronous and tiny — safe during
/// a store's `init` on the main actor. Writes are pushed off the main thread so a
/// refresh never blocks the UI. Everything is cleared on sign-out so one account
/// never paints another's data.
public enum SnapshotCache {
    private static let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("PersonaSnapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func fileURL(_ key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }

    /// Last-known value for `key`, or nil when absent / unreadable / stale schema.
    public static func load<T: Decodable>(_ key: String, as _: T.Type = T.self) -> T? {
        guard let data = try? Data(contentsOf: fileURL(key)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Delete `key`'s snapshot (e.g. the avatar was removed) — off-main.
    public static func remove(_ key: String) {
        let url = fileURL(key)
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Persist `value` under `key`, encoding + writing off the main thread.
    public static func save<T: Encodable & Sendable>(_ value: T, to key: String) {
        let url = fileURL(key)
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(value) else { return }
            // `clearAll()` (sign-out) removes the whole directory, and the OS
            // may evict Caches/ wholesale — recreate it or every save after
            // that silently fails until the next launch.
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Drop every snapshot — call on sign-out.
    public static func clearAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
