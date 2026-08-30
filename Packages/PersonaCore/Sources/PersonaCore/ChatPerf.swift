import os

/// Debug-only signposts around the chat first-entry hot paths (cold markdown
/// parse, transcript array swaps, the task-card fold), so entry lag can be
/// MEASURED on a simulator instead of eyeballed:
///
/// xcrun simctl spawn <udid> log show --last 2m \
/// --predicate 'category == "ChatPerf"' --style compact
///
/// Compiled to no-ops in release builds — a buildpays nothing.
public enum ChatPerf {
    #if DEBUG
    public static let log = OSLog(subsystem: "in.schard.persona.dev", category: "ChatPerf")
    #endif

    /// Wrap a hot path in a signpost interval. `detail` is only evaluated in
    /// debug builds (autoclosure), so call sites can interpolate counts freely.
    @inline(__always)
    public static func measure<T>(_ name: StaticString, _ detail: @autoclosure () -> String = "", _ work: () -> T) -> T {
        #if DEBUG
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id, "%{public}s", detail())
        defer { os_signpost(.end, log: log, name: name, signpostID: id) }
        return work()
        #else
        return work()
        #endif
    }
}
