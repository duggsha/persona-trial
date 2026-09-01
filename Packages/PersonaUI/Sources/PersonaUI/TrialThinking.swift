import SwiftUI
import PersonaCore
import PersonaDesign

/// The working out, on its own surface. A research agent shows you the trail
/// it followed; this is that, for a decision: what Iris went and looked at,
/// what it found there, and — the part a research tool never has to answer —
/// why it stopped and asked you instead of just doing it.
struct ThinkingSheet: View {
    let item: DeckItem
    let trace: ThinkingTrace

    /// Each phase reveals in order, so the sheet reads as a replay of the work
    /// rather than a list that was always sitting there.
    @State private var revealed = 0

    var body: some View {
        SheetChrome(title: "How Iris got here") {
            VStack(alignment: .leading, spacing: 0) {
                phase(0, dot: true) {
                    Text(item.ask)
                        .font(.system(size: 19, weight: .light))
                        .foregroundStyle(DS.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                phase(1) {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Looked at", systemImage: "magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.Palette.placeholder)
                        ForEach(trace.looked, id: \.self) { line in
                            Text(line)
                                .font(.system(size: 13, weight: .regular, design: .monospaced))
                                .foregroundStyle(DS.Palette.subtle)
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.ultraThinMaterial,
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                        }
                    }
                }

                phase(2) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Found \(trace.sources.count)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.Palette.placeholder)
                            .padding(.bottom, 8)
                        VStack(spacing: 0) {
                            ForEach(Array(trace.sources.enumerated()), id: \.element.id) { index, source in
                                if index > 0 {
                                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                                }
                                HStack(spacing: 10) {
                                    IrisLogoTile(logo: source.logo, size: 20)
                                    Text(source.title)
                                        .font(.system(size: 13.5))
                                        .foregroundStyle(DS.Palette.inkMuted)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(source.origin)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(DS.Palette.placeholder)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 44)
                            }
                        }
                        .background(.ultraThinMaterial,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    }
                }

                phase(3) {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Why it asked you", systemImage: "brain")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.Palette.placeholder)
                        Text(trace.judgment)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(DS.Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                phase(4, last: true) {
                    HStack(spacing: 9) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.black, DS.Palette.success)
                        Text("Ready for you")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DS.Palette.subtle)
                    }
                }
            }
        }
        .task {
            // Staged, not staggered for decoration: each step appears when the
            // one before it has been read.
            for step in 0 ... 4 {
                withAnimation(.smooth(duration: 0.32)) { revealed = step }
                try? await Task.sleep(for: .milliseconds(step == 0 ? 120 : 260))
            }
        }
    }

    /// One step of the replay, hung off a rail that runs the length of the trace.
    @ViewBuilder
    private func phase<Content: View>(_ index: Int, dot: Bool = false, last: Bool = false,
                                      @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle()
                    .fill(dot ? DS.Palette.ink : DS.Palette.placeholder.opacity(0.6))
                    .frame(width: dot ? 7 : 5, height: dot ? 7 : 5)
                    .padding(.top, 6)
                if !last {
                    Rectangle()
                        .fill(Color.white.opacity(0.09))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 8)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, last ? 0 : 22)
        }
        .opacity(revealed >= index ? 1 : 0)
        .offset(y: revealed >= index ? 0 : 6)
    }
}

/// The high-stakes control: press and hold.
///
/// A slide was the first answer and it was the wrong one. Apple's own rule for
/// a destructive or paid action is deliberate effort separated from the
/// trigger — not lateral travel; that is why paying is a double-click of the
/// side button and not a swipe. A slide also costs a full thumb traverse of a
/// 6-inch screen one-handed, and it fought the pager for the horizontal axis,
/// so approving could page the app sideways instead.
///
/// Hold keeps the thumb where it already is, shows exactly how far along the
/// commit is, and cancels the instant you let go — interruptible right up to
/// the moment it isn't.
struct HoldToApprove: View {
    let label: String
    let onApprove: () -> Void

    @State private var progress: CGFloat = 0
    @State private var holding = false
    @State private var done = false
    @State private var ticker: Task<Void, Never>?

    /// Long enough to be a decision, short enough never to feel like a wait.
    private let duration: Double = 0.9

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(alignment: .leading) {
                    // The fill IS the progress. No separate spinner, no ring
                    // orbiting a label — the button becomes the indicator.
                    GeometryReader { geo in
                        Rectangle()
                            .fill(DS.Palette.ink)
                            .frame(width: geo.size.width * progress)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))

            HStack(spacing: 7) {
                Image(systemName: done ? "checkmark" : "hand.tap.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(done ? "Sending" : (holding ? "Keep holding" : label))
                    .font(.system(size: 15.5, weight: .medium))
                    .contentTransition(.opacity)
            }
            .foregroundStyle(progress > 0.5 ? DS.Palette.onInk : DS.Palette.ink)
            .animation(.smooth(duration: 0.18), value: progress > 0.5)
        }
        .frame(height: 54)
        .contentShape(RoundedRectangle(cornerRadius: DK.wellRadius, style: .continuous))
        .scaleEffect(holding ? 0.985 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: holding)
        .onLongPressGesture(minimumDuration: 60, maximumDistance: 40) {
            // Never fires: the ticker owns completion. This gesture exists for
            // its press state, which is what gives us press-in and release.
        } onPressingChanged: { pressing in
            holding = pressing && !done
            pressing ? start() : cancel()
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(label))
        .accessibilityHint(Text("Press and hold to confirm"))
        .accessibilityAction { commit() }
    }

    private func start() {
        guard !done else { return }
        _ = DSHaptics.tap(.light)
        ticker?.cancel()
        ticker = Task { @MainActor in
            let step = 0.016
            while progress < 1 {
                try? await Task.sleep(for: .milliseconds(16))
                if Task.isCancelled { return }
                progress = min(progress + CGFloat(step / duration), 1)
            }
            commit()
        }
    }

    private func cancel() {
        guard !done else { return }
        ticker?.cancel()
        // Let go early and it drains back. Nothing happened, so nothing needs
        // undoing — the cheapest possible way to change your mind.
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { progress = 0 }
    }

    private func commit() {
        guard !done else { return }
        done = true
        holding = false
        withAnimation(.snappy(duration: 0.16)) { progress = 1 }
        _ = DSHaptics.tap(.rigid)
        onApprove()
    }
}
