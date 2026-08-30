import os
import QuartzCore
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// QA-only frame-hitch meter (`PERF_HUD=1`), for measuring smoothness on a
/// REAL device from the CLI — born when the machine's Instruments
/// install was broken and we (rightly) asked for numbers instead of
/// vibes. A CADisplayLink rides every frame and reports Apple's hitch metric:
/// how many ms of lateness the UI accumulated per second of wall time.
///
/// hitch = a frame that presented LATER than its target (excess ms
/// beyond a 4ms grace, per the Instruments definition)
/// ratio = total hitch ms / elapsed s — the number Apple calls
/// "hitch time ratio"; < 5 ms/s reads smooth, > 10 reads mushy
///
/// Every 5s window prints ONE parseable line to stdout AND os_log
/// (subsystem persona.perf) so `devicectl device process launch --console`
/// captures it headlessly:
///
/// PERFHUD window=3 fps=57.8 maxfps=60 frames=289 hitches=4 hitchMs=38.2 ratio=7.6 worstMs=21.4
///
/// Zero production cost: nothing is created unless the env var is set.
@MainActor
public enum PerfMeter {
    public static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["PERF_HUD"] == "1"
    }

    #if canImport(UIKit)
        private static var driver: Driver?
    #endif

    /// Idempotent; call from the root's `.task`.
    public static func startIfEnabled() {
        #if canImport(UIKit)
            guard isEnabled, driver == nil else { return }
            driver = Driver()
        #endif
    }

    private static let log = Logger(subsystem: "persona.perf", category: "hud")

    #if canImport(UIKit)
    @MainActor
    private final class Driver {
        private var link: CADisplayLink?
        private var windowStart: CFTimeInterval = 0
        private var lastTarget: CFTimeInterval = 0
        private var frames = 0
        private var hitches = 0
        private var hitchMs: Double = 0
        private var worstMs: Double = 0
        private var windowIndex = 0
        /// Instruments' grace: a frame under 4ms late is not a perceptible hitch.
        private static let graceMs: Double = 4.0

        init() {
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        @objc private func tick(_ link: CADisplayLink) {
            let now = link.timestamp
            if windowStart == 0 { windowStart = now; lastTarget = link.targetTimestamp; return }
            frames += 1

            // Lateness: how far past the PREVIOUS frame's deadline this frame
            // actually landed. targetTimestamp is when the current frame is
            // due; `now` (this callback's vsync stamp) minus the previous
            // deadline is the miss.
            let lateMs = (now - lastTarget) * 1000
            if lateMs > Self.graceMs {
                hitches += 1
                hitchMs += lateMs - Self.graceMs
                worstMs = max(worstMs, lateMs)
            }
            lastTarget = link.targetTimestamp

            let elapsed = now - windowStart
            if elapsed >= 5 {
                windowIndex += 1
                let fps = Double(frames) / elapsed
                let ratio = hitchMs / elapsed
                let line = String(
                    format: "PERFHUD window=%d fps=%.1f maxfps=%d frames=%d hitches=%d hitchMs=%.1f ratio=%.2f worstMs=%.1f",
                    windowIndex, fps, UIScreen.main.maximumFramesPerSecond, frames, hitches, hitchMs, ratio, worstMs
                )
                // BOTH sinks: print reaches the devicectl console pipe, os_log
                // reaches `log stream`/sysdiagnose if the pipe is lost.
                print(line)
                PerfMeter.log.log("\(line, privacy: .public)")
                windowStart = now
                frames = 0; hitches = 0; hitchMs = 0; worstMs = 0
            }
        }
    }
    #endif
}
