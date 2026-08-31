import SwiftUI
import PersonaDesign

/// The menu button finally opens something: a left slide-over with the three
/// places the app has — Home, Chat, Judgment — and the signed-in account at
/// the bottom. Same ink, same hairlines, no soft chrome.
struct TrialSidebar: View {
    @Binding var isOpen: Bool
    let page: PersonaPage
    let onHome: () -> Void
    let onChat: () -> Void
    let onJudgment: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            if isOpen {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { close() }

                panel
                    .transition(.move(edge: .leading))
            }
        }
        .animation(.snappy(duration: 0.28, extraBounce: 0), value: isOpen)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("IRIS")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .kerning(2.2)
                .foregroundStyle(DS.Palette.ink)
                .padding(.horizontal, 22)
                .padding(.top, 74)
                .padding(.bottom, 18)

            row("house.fill", "Home", active: page == .home) { close(); onHome() }
            row("text.bubble", "Chat", active: page == .chat) { close(); onChat() }
            row("brain", "Judgment", active: false) { close(); onJudgment() }

            Spacer(minLength: 0)

            Rectangle().fill(DS.Palette.hairlineSoft).frame(height: 1)

            HStack(spacing: 12) {
                PersonaAsset.image("AvatarShaurya")
                    .resizable().scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shaurya Duggal")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Palette.ink)
                    Text("ACCOUNT")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(DS.Palette.placeholder)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
        .frame(width: 296, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(DS.Palette.canvas)
        .overlay(alignment: .trailing) {
            Rectangle().fill(DS.Palette.hairlineSoft).frame(width: 1)
        }
        .ignoresSafeArea()
    }

    private func row(_ symbol: String, _ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 24)
                Text(label)
                    .font(.system(size: 17, weight: active ? .semibold : .medium))
                Spacer()
            }
            .foregroundStyle(active ? DS.Palette.ink : DS.Palette.inkMuted)
            .padding(.horizontal, 22)
            .frame(height: 52)
            .background(active ? DS.Palette.surfaceMuted : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func close() { isOpen = false }
}
