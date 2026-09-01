import SwiftUI
import PersonaDesign

/// The menu. Modelled on the sidebars people actually live in — account up
/// top, destinations, recent conversations, search at the bottom — drawn in
/// this app's ink instead of anyone else's brand.
struct TrialSidebar: View {
    @Binding var isOpen: Bool
    let page: PersonaPage
    let onHome: () -> Void
    let onChat: () -> Void
    let onJudgment: () -> Void
    let onSettings: () -> Void

    private let recents = [
        "Jason's 30 minutes",
        "Dinner at Marufuku",
        "Sarah — Thursday reply",
    ]

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
        .sensoryFeedback(.impact(weight: .light), trigger: isOpen)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Account, first. The app is signed in; the menu should say so.
            HStack(spacing: 12) {
                PersonaAsset.image("AvatarShaurya")
                    .resizable().scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shaurya Duggal")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.Palette.ink)
                    Text("IRIS PRO")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .kerning(1.1)
                        .foregroundStyle(DS.Palette.placeholder)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 76)
            .padding(.bottom, 22)

            row("house.fill", "Home", active: page == .home) { close(); onHome() }
            row("text.bubble", "Chat", active: page == .chat) { close(); onChat() }
            row("brain", "Judgment", active: false) { close(); onJudgment() }
            row("gearshape.fill", "Settings", active: false) { close(); onSettings() }

            Text("RECENT")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .kerning(1.2)
                .foregroundStyle(DS.Palette.placeholder)
                .padding(.horizontal, 22)
                .padding(.top, 26)
                .padding(.bottom, 8)

            ForEach(recents, id: \.self) { title in
                Button { close(); onChat() } label: {
                    Text(title)
                        .font(.system(size: 15))
                        .foregroundStyle(DS.Palette.inkMuted)
                        .lineLimit(1)
                        .padding(.horizontal, 22)
                        .frame(height: 38)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            // The bottom rail: search and a new thread, the two things a
            // sidebar is opened for when it isn't navigation.
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DS.Palette.placeholder)
                    Text("Search")
                        .font(.system(size: 14))
                        .foregroundStyle(DS.Palette.placeholder)
                    Spacer()
                }
                .padding(.horizontal, 13)
                .frame(height: 42)
                .background(DS.Palette.surfaceMuted, in: Capsule())

                Button { close(); onChat() } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Palette.ink)
                        .frame(width: 42, height: 42)
                        .background(DS.Palette.surfaceMuted, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .frame(width: 308, alignment: .leading)
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
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(active ? DS.Palette.surfaceMuted : .clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }

    private func close() { isOpen = false }
}
