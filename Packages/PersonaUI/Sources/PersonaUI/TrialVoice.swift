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
struct VoiceOverlay: View {
    let onFinish: () -> Void
    @State private var phase = 0   // 0 listening · 1 heard · 2 working

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()

            VStack(spacing: 18) {
                waveform
                    .frame(height: 46)

                Group {
                    switch phase {
                    case 0:
                        Text("Listening…")
                            .font(.system(size: 15))
                            .foregroundStyle(DS.Palette.subtle)
                    case 1:
                        Text("\u{201C}book the table too\u{201D}")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(DS.Palette.ink)
                    default:
                        HStack(spacing: 8) {
                            IrisLogoTile(logo: .resy, size: 20)
                            Text("Taking the 7:45…")
                                .font(.system(size: 15))
                                .foregroundStyle(DS.Palette.inkMuted)
                        }
                    }
                }
                .transition(.opacity.combined(with: .offset(y: 6)))
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 34)
            .frame(maxWidth: 330)
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(DS.Palette.canvas.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(DS.Palette.hairlineSoft, lineWidth: 1))
        }
        .animation(.smooth(duration: 0.3), value: phase)
        .task {
            try? await Task.sleep(for: .milliseconds(1100))
            phase = 1
            try? await Task.sleep(for: .milliseconds(900))
            phase = 2
            try? await Task.sleep(for: .milliseconds(1100))
            onFinish()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: phase)
    }

    private var waveform: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0 ..< 24, id: \.self) { index in
                    let seed = Double(index) * 0.61
                    let amp = phase == 2 ? 0.25 : (0.3 + 0.7 * abs(sin(t * 3.1 + seed)))
                    Capsule()
                        .fill(DS.Palette.ink.opacity(phase == 2 ? 0.35 : 0.85))
                        .frame(width: 3, height: 8 + 34 * amp)
                }
            }
        }
    }
}
