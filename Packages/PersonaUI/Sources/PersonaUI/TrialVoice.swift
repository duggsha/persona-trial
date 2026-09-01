import SwiftUI
import PersonaCore
import PersonaDesign

// MARK: - The agent's work, inside the transcript

/// What Iris did between your turn and its reply — the tool calls, folded
/// into one labelled box the way an agent transcript should read. Collapsed:
/// one line. Open: the trail, each step wearing the app it touched.
struct ChatToolTrail: Equatable {
    struct Step: Equatable, Identifiable {
        let id = UUID()
        let logo: IrisLogo
        let label: String
        let detail: String?
    }
    let summary: String        // "Worked 4s · 2 steps"
    let steps: [Step]
}

struct ChatWorkedBox: View {
    let trail: ChatToolTrail
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.22)) { open.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Palette.placeholder)
                    Text(trail.summary)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(DS.Palette.subtle)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DS.Palette.placeholder)
                        .rotationEffect(.degrees(open ? 180 : 0))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(trail.steps) { step in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            IrisLogoTile(logo: step.logo, size: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(step.label)
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(DS.Palette.inkMuted)
                                if let detail = step.detail {
                                    Text(detail)
                                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                                        .foregroundStyle(DS.Palette.placeholder)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.asymmetric(
                    insertion: .offset(y: -6).combined(with: .opacity),
                    removal: .opacity))
            }
        }
        .background(DS.Palette.surfaceMuted,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(DS.Palette.hairlineSoft, lineWidth: 1))
        .frame(maxWidth: 300, alignment: .leading)
        .padding(.top, 10)
        .sensoryFeedback(.selection, trigger: open)
    }
}

// MARK: - Voice mode

/// Hold the mic, and this is what answers: a glass sheet, live bars, the
/// heard words, then the work — done for real in the shared engine, so the
/// feed's Marufuku card is genuinely gone when the voice flow books it.
/// Hold the mic and this answers: a bottom-anchored HUD in the deck's own
/// language — mono strata label, hairline rules, sharp 8pt corners — that
/// hears you, then shows the work landing step by step. The engine it drives
/// is the shared one, so the feed's Marufuku card is genuinely booked when
/// this finishes.
struct VoiceOverlay: View {
    let onFinish: () -> Void
    /// 0 listening · 1 heard · 2 working · 3 done
    @State private var phase = 0

    private var strataLabel: String {
        switch phase {
        case 0: return "LISTENING"
        case 1: return "HEARD"
        case 2: return "WORKING"
        default: return "DONE"
        }
    }

    var body: some View {
        ZStack {
            // Bottom-weighted scrim: the HUD lives down by the composer, so
            // that is where the room should darken.
            LinearGradient(
                colors: [DS.Palette.canvas.opacity(0.2), DS.Palette.canvas.opacity(0.88)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Strata 1 — what the machine is doing, in its own voice.
                HStack(spacing: 7) {
                    Circle()
                        .fill(phase == 3 ? DS.Palette.success : DS.Palette.ink)
                        .frame(width: 5, height: 5)
                        .opacity(phase == 0 ? 0.4 + 0.6 * pulse : 1)
                    Text(strataLabel)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(DS.Palette.placeholder)
                    Spacer(minLength: 0)
                    Text("HOLD TO TALK")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(DS.Palette.placeholder.opacity(0.65))
                }
                .padding(.horizontal, 16)
                .frame(height: 34)

                LedgerRule()

                // Strata 2 — you: the bars while you talk, the words after.
                Group {
                    if phase == 0 {
                        waveform.frame(height: 40)
                    } else {
                        Text("\u{201C}book the table too\u{201D}")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(DS.Palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)

                // Strata 3 — the work, landing.
                if phase >= 2 {
                    LedgerRule()
                    HStack(spacing: 10) {
                        IrisLogoTile(logo: .resy, size: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(phase == 3 ? "Booked — Marufuku, 7:45 PM" : "Taking the 7:45…")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(DS.Palette.inkMuted)
                            Text(phase == 3 ? "2 counter seats · free cancel until 6:00"
                                            : "2 counter seats")
                                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                                .foregroundStyle(DS.Palette.placeholder)
                        }
                        Spacer(minLength: 0)
                        if phase == 3 {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(DS.Palette.success)
                        } else {
                            ProgressView().controlSize(.mini)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(DS.Palette.canvas.opacity(0.62),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(DS.Palette.hairlineSoft, lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 104)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .animation(.smooth(duration: 0.28), value: phase)
        .task {
            try? await Task.sleep(for: .milliseconds(1100))
            phase = 1
            try? await Task.sleep(for: .milliseconds(850))
            phase = 2
            try? await Task.sleep(for: .milliseconds(1300))
            phase = 3
            try? await Task.sleep(for: .milliseconds(800))
            onFinish()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: phase)
    }

    /// Drives the listening dot's breath without a second timeline.
    private var pulse: Double {
        0.5 + 0.5 * sin(Date().timeIntervalSinceReferenceDate * 4)
    }

    private var waveform: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3.5) {
                ForEach(0 ..< 30, id: \.self) { index in
                    let seed = Double(index) * 0.61
                    let amp = 0.25 + 0.75 * abs(sin(t * 3.1 + seed))
                    Capsule()
                        .fill(DS.Palette.ink.opacity(0.8))
                        .frame(width: 2.5, height: 6 + 30 * amp)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The deck's hairline, full-bleed — the rule that makes a dark panel read as
/// an instrument instead of a chat bubble.
private struct LedgerRule: View {
    var body: some View {
        Rectangle().fill(DS.Palette.hairlineSoft).frame(height: 1)
    }
}
