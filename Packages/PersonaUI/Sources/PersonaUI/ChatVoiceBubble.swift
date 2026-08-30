import AVFoundation
import PersonaCore
import PersonaDesign
import PersonaService
import SwiftUI

/// The waveform + play control shown inside a voice-message bubble. Rendered
/// above the transcript. Playback works both for a freshly-recorded clip (local
/// file) and for a reloaded bubble after an app restart: the first play tap
/// downloads the clip from the backend (authenticated), caches it, and plays —
/// with a spinner on the button while it loads and an honest retry state on
/// failure (never a dead, grayed-out control).
struct ChatVoiceNoteView: View {
    /// The local clip when this bubble was just recorded; nil after a reload.
    let audioURL: URL?
    /// Backend replay path ("/v1/chat/voice/audio/<id>") for a reloaded bubble.
    let audioRemotePath: String?
    let duration: TimeInterval
    let isUser: Bool

    @Environment(VoiceAudioCache.self) private var voiceAudio
    @StateObject private var player = VoiceNotePlayer()
    /// The clip resolved from `audioRemotePath` (downloaded + cached); reused for
    /// subsequent plays this session.
    @State private var resolvedURL: URL?
    @State private var isLoading = false
    @State private var loadFailed = false
    /// The backend answered 404: the clip's background upload was lost, so no
    /// retry can ever succeed. The control dims instead of offering a dead
    /// retry loop — the transcript below the bubble still carries the content.
    @State private var clipMissing = false
    /// The clip's REAL amplitude envelope, computed off-thread once the file is
    /// at hand; the fixed placeholder shows until then.
    @State private var waveform: [CGFloat]?

    @MainActor
    init(audioURL: URL?, audioRemotePath: String?, duration: TimeInterval, isUser: Bool) {
        self.audioURL = audioURL
        self.audioRemotePath = audioRemotePath
        self.duration = duration
        self.isUser = isUser
        // A rebuilt bubble (recycled lazy row, any identity churn) must paint
        // its REAL waveform on the FIRST frame when the clip and envelope are
        // already known — waiting for the async `.task`s to re-derive them
        // flashes the placeholder bars and then crossfades back.
        let resolved = audioURL == nil
            ? audioRemotePath.flatMap(VoiceAudioCache.cachedFile(forRemotePath:))
            : nil
        _resolvedURL = State(initialValue: resolved)
        if let url = audioURL ?? resolved {
            _waveform = State(initialValue: VoiceWaveform.cached(for: url))
        }
    }

    private var tint: Color { isUser ? .white : DS.Palette.inkBlack }
    /// A file we can hand straight to the player without a download.
    private var readyURL: URL? { audioURL ?? resolvedURL }
    /// Whether this bubble can ever play (local file OR a remote path to fetch
    /// whose object is not known-missing).
    private var isPlayable: Bool { readyURL != nil || (audioRemotePath != nil && !clipMissing) }

    var body: some View {
        HStack(spacing: 10) {
            playIcon
                .frame(width: 30, height: 30)
                .background(tint.opacity(isPlayable ? 0.92 : 0.35), in: Circle())

            // Fixed width (not a greedy GeometryReader fill) so the bubble
            // hugs its content instead of stretching to the max bubble width.
            // 110, down from 150 (memo bubbles read too
            // wide) — bar count drops with it so the density holds.
            WaveformBars(tint: tint, heights: waveform ?? WaveformBars.placeholder, player: player)
                .frame(width: 110, height: 24)

            Text(Self.durationLabel(duration))
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(tint.opacity(0.8))
        }
        // The WHOLE bubble is the play/pause target, not just the round button.
        .contentShape(Rectangle())
        .onTapGesture {
            guard DSInteractionGate.allowsTap else { return }
            handleTap()
        }
        // QA stamp: hold-to-speak tests read "a voice bubble landed" as proof
        // a released memo was handed off (TaskComposerVoiceCancelSmoke).
        .accessibilityIdentifier("chat-voice-bubble")
        // Pre-resolve the clip the moment the bubble scrolls into reach, so the
        // play tap starts instantly instead of showing a download spinner. A
        // failure stays silent here — the tap path keeps its spinner + retry.
        .task {
            guard audioURL == nil, resolvedURL == nil, let path = audioRemotePath else { return }
            do {
                resolvedURL = try await voiceAudio.localFile(forRemotePath: path)
            } catch let APIError.http(status, _) where status == 404 {
                clipMissing = true // upload was lost server-side — unplayable forever
            } catch {
                // Transient failure stays silent here — the tap path keeps its
                // spinner + retry.
            }
        }
        // The bars show THIS clip's real envelope — recomputed (or served from
        // the session cache) whenever the playable file becomes available. A
        // cache hit that matches what's already on screen (the init seed) must
        // not re-set state: the crossfade animation on a value that didn't
        // change still reads as a flicker mid-gesture.
        .task(id: readyURL) {
            guard let url = readyURL else { return }
            if let envelope = await VoiceWaveform.envelope(for: url), envelope != waveform {
                withAnimation(.easeOut(duration: 0.25)) { waveform = envelope }
            }
        }
        .onDisappear { player.stop() }
    }

    @ViewBuilder private var playIcon: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .tint(isUser ? DS.Palette.userBubble : .white)
        } else {
            Image(systemName: loadFailed ? "arrow.clockwise" : (player.isPlaying ? "pause.fill" : "play.fill"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isUser ? DS.Palette.userBubble : DS.Palette.onInk)
        }
    }

    private func handleTap() {
        guard isPlayable, !isLoading else { return }
        // Already have the file (fresh clip, or downloaded earlier) → just play.
        if let url = readyURL {
            player.toggle(url: url)
            return
        }
        guard let path = audioRemotePath, !isLoading else { return }
        isLoading = true
        loadFailed = false
        Task {
            do {
                let url = try await voiceAudio.localFile(forRemotePath: path)
                resolvedURL = url
                isLoading = false
                player.toggle(url: url) // start playing — the user asked to
            } catch let APIError.http(status, _) where status == 404 {
                isLoading = false
                clipMissing = true // gone server-side; a retry can never succeed
            } catch {
                isLoading = false
                loadFailed = true
            }
        }
    }

    static func durationLabel(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// The transcription under the waveform, inside the bubble — a softened cast
/// of the bubble's ink, a step smaller than message text so the waveform stays
/// the bubble's headline. Long transcripts fold to a few lines behind an
/// inline "Read more" — a rambling memo shouldn't push a screenful of caption
/// text into the transcript.
struct VoiceTranscriptCaption: View {
    let text: String
    let isUser: Bool

    @State private var expanded = false

    /// ~5 transcript lines at 13pt across the bubble column; folding below
    /// this would hide only a line or two — not worth the extra tap.
    private static let foldThreshold = 280
    private static let previewChars = 200

    private var ink: Color { isUser ? Color.white.opacity(0.72) : DS.Palette.inkBlack.opacity(0.6) }
    private var needsFold: Bool { text.count > Self.foldThreshold }

    /// Preview cut backwards to a whitespace so a word is never split.
    private var preview: String {
        var cut = String(text.prefix(Self.previewChars))
        if let lastBreak = cut.lastIndex(where: \.isWhitespace),
           cut.distance(from: lastBreak, to: cut.endIndex) < 40 {
            cut = String(cut[..<lastBreak])
        }
        return cut.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(needsFold && !expanded ? preview : text)
                .font(.system(size: 13, weight: .regular))
                .lineSpacing(2) // keep the 22/17 bubble rhythm at 13pt
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
            if needsFold {
                Button {
                    guard DSInteractionGate.allowsTap else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Text(expanded ? String(localized: "Show less") : String(localized: "Read more"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ink)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("voice-transcript-toggle")
            }
        }
    }
}

/// A row of waveform bars showing the clip's real amplitude envelope (the
/// fixed placeholder shows only until it's computed); at rest the bars are dim
/// and cost nothing per-frame. During playback a full-tint copy is masked to
/// the played fraction and swept left→right by SwiftUI's animation clock
/// (nothing animates while the clip isn't playing, so the idle transcript
/// stays animation-free).
private struct WaveformBars: View {
    let tint: Color
    /// Normalized bar heights — the clip's envelope, or `placeholder`.
    var heights: [CGFloat] = WaveformBars.placeholder
    @ObservedObject var player: VoiceNotePlayer

    /// Played fraction shown by the mask. NOT polled from the player per-frame:
    /// on play it's animated `current → 1` with a linear curve over the clip's
    /// remaining time, so SwiftUI's own animation clock does the sweeping. On
    /// pause/finish it snaps (no animation) to the player's real position —
    /// frozen mid-clip on pause, back to 0 after a finish (the player rewinds).
    @State private var fill: CGFloat = 0

    // A pleasant, fixed "speech envelope" — shown until the real one resolves.
    // Deterministic two-sine mix so the density can change without hand-tuning
    // a literal per bar.
    static let placeholder: [CGFloat] = (0 ..< 28).map { index in
        let x = Double(index)
        let mix = 0.48 + 0.27 * sin(x * 0.74) + 0.2 * sin(x * 2.13 + 1.3)
        return CGFloat(min(1, max(0.15, mix)))
    }

    var body: some View {
        GeometryReader { geo in
            bars(opacity: 0.45, size: geo.size)
                .overlay(alignment: .leading) {
                    bars(opacity: 1, size: geo.size)
                        .mask(alignment: .leading) {
                            Rectangle()
                                .frame(width: geo.size.width * fill)
                        }
                }
        }
        .onChange(of: player.isPlaying) { _, playing in
            if playing {
                var snap = Transaction()
                snap.disablesAnimations = true
                withTransaction(snap) { fill = player.progress }
                withAnimation(.linear(duration: max(0.01, player.remainingTime))) { fill = 1 }
            } else {
                var snap = Transaction()
                snap.disablesAnimations = true
                withTransaction(snap) { fill = player.progress }
            }
        }
    }

    private func bars(opacity: Double, size: CGSize) -> some View {
        let count = heights.count
        let spacing: CGFloat = 2
        let barWidth = max(1.5, (size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
        return HStack(alignment: .center, spacing: spacing) {
            ForEach(0 ..< count, id: \.self) { index in
                Capsule()
                    .fill(tint.opacity(opacity))
                    .frame(width: barWidth, height: max(3, size.height * heights[index]))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .center)
    }
}

/// Computes a clip's amplitude envelope: `WaveformBars.placeholder.count` bars
/// of per-window RMS, normalized so the loudest window is full height and the
/// quietest still visibly a bar. Cached per file URL for the session — a
/// transcript full of voice notes decodes each clip once, off the main thread.
@MainActor
enum VoiceWaveform {
    private static var cache: [URL: [CGFloat]] = [:]

    /// Synchronous cache read, so a rebuilt bubble can seed its bars on the
    /// first frame (no async hop → no placeholder flash).
    static func cached(for url: URL) -> [CGFloat]? { cache[url] }

    static func envelope(for url: URL) async -> [CGFloat]? {
        if let hit = cache[url] { return hit }
        let barCount = WaveformBars.placeholder.count // main-actor read, before detaching
        let bars = await Task.detached(priority: .utility) {
            compute(url: url, barCount: barCount)
        }.value
        if let bars { cache[url] = bars }
        return bars
    }

    private nonisolated static func compute(url: URL, barCount: Int) -> [CGFloat]? {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0,
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: file.processingFormat,
                  frameCapacity: AVAudioFrameCount(file.length)
              ),
              (try? file.read(into: buffer)) != nil,
              let samples = buffer.floatChannelData?[0]
        else { return nil }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return nil }
        let window = max(1, frameCount / barCount)
        var rms: [CGFloat] = []
        rms.reserveCapacity(barCount)
        for bar in 0 ..< barCount {
            let start = bar * window
            let end = min(frameCount, start + window)
            guard start < end else {
                rms.append(0)
                continue
            }
            var sum: Float = 0
            for frame in start ..< end {
                let value = samples[frame]
                sum += value * value
            }
            rms.append(CGFloat(sqrt(sum / Float(end - start))))
        }
        guard let peak = rms.max(), peak > 0 else { return nil }
        // Speech RMS clusters near the top of its range, which renders as a
        // near-flat bar row; the >1 exponent expands those differences so the
        // envelope visibly tracks the clip's loud and quiet moments. Quietest
        // windows keep a visible stub (0.12) instead of vanishing.
        return rms.map { 0.12 + 0.88 * CGFloat(pow(Double($0 / peak), 1.5)) }
    }
}

/// Minimal AVAudioPlayer wrapper: play/pause a local clip, reset on finish.
/// `progress` is read per-frame by the waveform's TimelineView while playing —
/// no polling timer and no published churn of its own.
@MainActor
final class VoiceNotePlayer: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    private var player: AVAudioPlayer?
    private var playingURL: URL?

    /// Played fraction of the current clip (0…1). Holds position while paused;
    /// back to 0 once a clip finishes (AVAudioPlayer rewinds on completion).
    var progress: Double {
        guard let player, player.duration > 0 else { return 0 }
        return min(max(player.currentTime / player.duration, 0), 1)
    }

    /// Seconds left in the current clip — the duration of the fill animation
    /// started on play/resume.
    var remainingTime: TimeInterval {
        guard let player else { return 0 }
        return max(0, player.duration - player.currentTime)
    }

    func toggle(url: URL) {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }
        // EVERY play (re)claims the playback session — a resume after the mic
        // held the session would otherwise route to the earpiece, whisper-quiet.
        configureSession()
        // Resume the same clip, or (re)load a new one.
        if player == nil || playingURL != url {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            playingURL = url
        }
        player?.volume = 1
        if player?.play() == true { isPlaying = true }
    }

    func stop() {
        player?.stop()
        isPlaying = false
    }

    private func configureSession() {
        #if canImport(UIKit)
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .spokenAudio)
            try? session.setActive(true)
        #endif
    }
}

extension VoiceNotePlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully _: Bool) {
        Task { @MainActor in self.isPlaying = false }
    }
}
