import PersonaDesign
import SwiftUI
#if os(iOS)
    import AVFoundation
#endif

enum VoiceReleaseMode {
    case send
    case delete
}

/// Records a voice memo and exposes a live level meter. Falls back to a gentle
/// animated meter if microphone permission is denied. On send, the recording is
/// kept (`finishRecording`) so it can be transcribed on device; on cancel it's
/// discarded.
@MainActor
final class VoiceMemoRecorder: ObservableObject {
    @Published var levels = Array(repeating: CGFloat(0.16), count: 18)
    @Published var isListening = false

    #if os(iOS)
        private var recorder: AVAudioRecorder?
    #endif
    private var recordingURL: URL?
    private var meterTask: Task<Void, Never>?
    private var phase = 0.0

    /// The MEASURED length of the last finished/paused recording, read off the
    /// recorder just before it stops. The composer's wall-clock stamp starts
    /// before the mic session is even live, so it overstates short holds —
    /// this is the real captured audio duration.
    private(set) var lastFinishedDuration: TimeInterval = 0
    /// Peak 16-bit sample of the last finished/paused clip (0…32767), measured
    /// by `normalizeRecording`. Near-zero means the mic captured no signal —
    /// the clip is silence and should not be sent.
    private(set) var lastFinishedPeak = 0

    /// Below this peak (of 32767) a clip is effectively silence — no speech,
    /// just floor noise or a mic that never delivered samples.
    static let silencePeakThreshold = 250

    func start() {
        stop()
        #if os(iOS)
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                // The steady state: no permission-callback hop — the recorder is
                // live before even the shortest real hold can release.
                startRecorder()
            case .undetermined:
                // First-ever hold: the meter animates IMMEDIATELY (pending
                // permission, so the label already reads "release to send") and
                // the real recorder swaps in once the system prompt resolves.
                startFallbackMeter(isPendingPermission: true)
                // The async form, never the completion handler: this class is
                // @MainActor, so the compiler hands @preconcurrency
                // AVFAudio a main-actor-isolated closure and inserts an
                // isolation check that TRAPS when it fires on AVFAudio's own
                // queue. The inner `Task { @MainActor }` does not save it —
                // the outer closure is what gets checked, which is exactly how
                // the photo viewer's Save died.
                Task { [weak self] in
                    let allowed = await AVAudioApplication.requestRecordPermission()
                    guard let self else { return }
                    if allowed { startRecorder() } else { startFallbackMeter() }
                }
            default:
                startFallbackMeter()
            }
        #else
            startFallbackMeter()
        #endif
    }

    /// Stop and keep the recording; returns its file URL for transcription.
    /// `lastFinishedDuration` / `lastFinishedPeak` describe the finished clip.
    func finishRecording() -> URL? {
        meterTask?.cancel()
        meterTask = nil
        #if os(iOS)
            lastFinishedDuration = recorder?.currentTime ?? 0
            recorder?.stop()
            recorder = nil
        #else
            lastFinishedDuration = 0
        #endif
        releaseSession()
        isListening = false
        levels = Array(repeating: CGFloat(0.16), count: levels.count)
        let url = recordingURL
        recordingURL = nil
        lastFinishedPeak = url.map { Self.normalizeRecording(at: $0) } ?? 0
        return url
    }

    /// Peak-normalize the finished 16-bit PCM WAV in place (target ≈ −1.5 dBFS,
    /// boost capped at +30 dB so near-silence isn't amplified into noise).
    /// Mic capture lands ~15–20 dB low on the simulator (whose session gain
    /// processing is a stub) and on some devices — this fixes local playback
    /// AND what the backend receives, deterministically.
    /// Returns the clip's PRE-gain peak sample (0…32767); 0 when the file can't
    /// be parsed — so callers can gate silent clips instead of sending them.
    @discardableResult
    static func normalizeRecording(at url: URL) -> Int {
        guard let data = try? Data(contentsOf: url), data.count > 44 else { return 0 }
        var bytes = [UInt8](data)

        // RIFF chunk walk — Apple often inserts a FLLR filler chunk, so the
        // 'data' payload is NOT at a fixed offset.
        func chunkSize(_ o: Int) -> Int {
            Int(bytes[o]) | Int(bytes[o + 1]) << 8 | Int(bytes[o + 2]) << 16 | Int(bytes[o + 3]) << 24
        }
        var offset = 12
        var start = 0
        var count = 0
        while offset + 8 <= bytes.count {
            let id = String(decoding: bytes[offset ..< offset + 4], as: UTF8.self)
            let size = chunkSize(offset + 4)
            if id == "data" {
                start = offset + 8
                count = min(size, bytes.count - start)
                break
            }
            offset += 8 + size + (size & 1)
        }
        guard count > 1 else { return 0 }
        let end = start + count - (count & 1)

        var peak = 0
        var i = start
        while i + 1 < end {
            let sample = Int(Int16(bitPattern: UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8))
            peak = max(peak, abs(sample))
            i += 2
        }
        // Already healthy (or pure digital silence) → leave it untouched.
        let gain = min(27500.0 / Double(max(peak, 1)), 31.6)
        guard peak > 0, gain > 1.05 else { return peak }

        i = start
        while i + 1 < end {
            let sample = Double(Int16(bitPattern: UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8))
            let scaled = Int16(max(-32768, min(32767, (sample * gain).rounded())))
            let raw = UInt16(bitPattern: scaled)
            bytes[i] = UInt8(raw & 0xFF)
            bytes[i + 1] = UInt8(raw >> 8)
            i += 2
        }
        try? Data(bytes).write(to: url)
        return peak
    }

    /// Hand the audio session back once the mic is done — otherwise the
    /// record session (playAndRecord + duckOthers) lingers and playback comes
    /// out ducked / routed to the earpiece.
    private func releaseSession() {
        #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }

    /// Stop and keep the recording, but freeze the current level bars in place
    /// (used by tap-to-record's "ready to send" state so the waveform stays put).
    /// Returns the file URL for later transcription.
    /// `lastFinishedDuration` / `lastFinishedPeak` describe the paused clip.
    func pauseKeepingLevels() -> URL? {
        meterTask?.cancel()
        meterTask = nil
        #if os(iOS)
            lastFinishedDuration = recorder?.currentTime ?? 0
            recorder?.stop()
            recorder = nil
        #else
            lastFinishedDuration = 0
        #endif
        releaseSession()
        isListening = false
        let url = recordingURL
        recordingURL = nil
        lastFinishedPeak = url.map { Self.normalizeRecording(at: $0) } ?? 0
        return url
    }

    /// Stop and throw the recording away (slide-to-cancel, or view disappears).
    func discard() {
        meterTask?.cancel()
        meterTask = nil
        #if os(iOS)
            recorder?.stop()
            recorder?.deleteRecording()
            recorder = nil
        #endif
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        releaseSession()
        recordingURL = nil
        isListening = false
        levels = Array(repeating: CGFloat(0.16), count: levels.count)
    }

    func stop() {
        discard()
    }

    #if os(iOS)
        private func startRecorder() {
            do {
                // Take over from the pending-permission fallback meter.
                meterTask?.cancel()
                meterTask = nil

                let session = AVAudioSession.sharedInstance()
                // .default mode, NOT .measurement: measurement disables the
                // system's input gain processing (AGC), which bakes whisper-
                // quiet levels into the recording itself.
                try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
                try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
                try session.setActive(true, options: [])

                // Linear-PCM WAV, 16 kHz mono. This is the ONE format every STT
                // backend accepts (OpenRouter/Groq/Whisper AND the Gemini fallback);
                // the old Apple-IMA4 .caf was rejected by every Whisper host (400).
                // 16 kHz mono is Whisper's native rate — smaller upload, no quality
                // loss for speech. On-device SFSpeechRecognizer reads WAV too, so the
                // default (pref-off) transcription path is unaffected.
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("persona-voice-\(UUID().uuidString).wav")
                let settings: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatLinearPCM),
                    AVSampleRateKey: 16000,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false
                ]
                let recorder = try AVAudioRecorder(url: url, settings: settings)
                recorder.isMeteringEnabled = true
                recorder.prepareToRecord()
                recorder.record()
                self.recorder = recorder
                recordingURL = url
                isListening = true
                startLiveMeter()
            } catch {
                startFallbackMeter()
            }
        }

        private func startLiveMeter() {
            meterTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(33))
                    guard let self, let recorder = self.recorder else { break }
                    recorder.updateMeters()
                    let power = Double(recorder.averagePower(forChannel: 0))
                    let normalized = min(max((power + 54) / 54, 0), 1)
                    self.push(level: CGFloat(pow(normalized, 0.58)))
                }
            }
        }
    #endif

    /// `isPendingPermission` = the moments between hold-down and the permission
    /// callback: the meter animates and the UI reads as listening (design-app
    /// parity); a plain fallback (permission denied) shows "mic needed" instead.
    private func startFallbackMeter(isPendingPermission: Bool = false) {
        isListening = isPendingPermission
        meterTask?.cancel()
        meterTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(42))
                guard let self else { break }
                self.phase += 0.26
                self.push(level: CGFloat(0.18 + 0.08 * sin(self.phase)))
            }
        }
    }

    private func push(level: CGFloat) {
        let smoothed = min(max(level, 0.05), 1)
        var next = levels
        next.removeFirst()
        next.append(smoothed)
        levels = next
    }
}

// On-device SpeechTranscriber (SFSpeechRecognizer) removed: every
// surface now hands the recorded clip to the backend for transcription (or
// sends it as a real voice message). The Apple path was permission-gated and
// silently produced nothing when the grant was missing.

// MARK: - Meter UI

struct VoiceMemoListeningDisplay: View {
    let releaseMode: VoiceReleaseMode
    /// When set (tap-to-record), shows the running / frozen duration instead of
    /// the "release to send" hint.
    var copy: String?
    /// Compact = the "ready to send" state (narrower meter + label).
    var isCompact = false
    /// Width the display may occupy (the composer's edge-relative slot). The
    /// meter absorbs any shortfall on narrow screens; the designed meter
    /// widths are a cap — extra room on wide screens stays empty rather than
    /// stretching the meter.
    var availableWidth: CGFloat? = nil
    let levels: [CGFloat]
    let isListening: Bool

    var body: some View {
        HStack(spacing: 12) {
            VoiceMemoMeter(levels: levels, releaseMode: releaseMode, width: meterWidth)
                .frame(width: meterWidth, height: 30)

            Text(releaseMode == .delete ? String(localized: "release to delete") : releaseCopy)
                .font(.system(size: 12, weight: .regular))
                .tracking(-0.12)
                .foregroundStyle(releaseMode == .delete ? Color(hex: 0xFF3B30) : Color(light: 0x6F6F6F, dark: 0xAEAEB2))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: labelWidth, alignment: .trailing)
        }
        .frame(width: meterWidth + labelWidth + 12, height: 40, alignment: .leading)
    }

    private var releaseCopy: String {
        if let copy { return copy }
        // Always the promise, never plumbing: the mic may still be spinning up
        // (or even denied) behind the already-visible UI, but the label reads
        // "release to send" throughout.
        return "release to send"
    }

    private var meterWidth: CGFloat {
        let designed: CGFloat = isCompact ? 130 : 164
        guard let availableWidth else { return designed }
        // The meter absorbs ALL of the shortfall (it drops whole bars to fit;
        // a 60pt floor keeps it reading as a meter) — it must never hold
        // width at the label's expense: the old 123pt bar floor pushed the
        // trailing timer past the slot's end, under the trash button (design
        // screenshot).
        return min(designed, max(60, availableWidth - labelWidth - 12))
    }

    private var labelWidth: CGFloat {
        // Compact (stopped, ready-to-send) only ever shows the short duration
        // ("0:07"); the wide 92pt slot was dead air that crowded the meter.
        isCompact ? 60 : 110
    }
}

struct VoiceMemoMeter: View {
    let levels: [CGFloat]
    let releaseMode: VoiceReleaseMode
    var width: CGFloat = 164

    /// WHOLE bars only — 4pt bars on 3pt gaps, so n bars need 7n−3 points.
    /// A narrow slot used to clip the centered 18-bar row at both edges,
    /// leaving sliver bars left and right;
    /// dropping the OLDEST levels to what fits keeps every rendered bar
    /// intact at any width.
    private var visibleLevels: [CGFloat] {
        let capacity = max(1, Int((width + 3) / 7))
        return Array(levels.suffix(capacity))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(visibleLevels.enumerated()), id: \.offset) { _, level in
                let clamped = min(max(level, 0.06), 1)
                Capsule(style: .continuous)
                    .fill(meterColor.opacity(0.30 + clamped * 0.58))
                    .frame(width: 4, height: 4 + clamped * 24)
                    .animation(.linear(duration: 0.05), value: clamped)
            }
        }
        .frame(width: width, height: 30)
    }

    private var meterColor: Color {
        releaseMode == .delete ? Color(hex: 0xFF3B30) : DS.Palette.accent
    }
}
