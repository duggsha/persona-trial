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
