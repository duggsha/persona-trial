import SwiftUI
import PersonaDesign

/// Shared chrome for every sheet in this build: a close disc, a centred
/// title, and grouped rows on one glass plate. Settings set the language;
/// Profile and Judgment speak it too, so the app has one sheet, not three.
struct SheetChrome<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(DS.Palette.ink)
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DS.Palette.inkMuted)
                            .frame(width: 34, height: 34)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .smallGlassCircle()
                    Spacer()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 18)

            ScrollView { content.padding(.horizontal, 18).padding(.bottom, 30) }
        }
        .presentationBackground(DS.Palette.canvas)
    }
}

/// A titled group of rows on one plate.
struct SheetSection<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .kerning(1.2)
                    .foregroundStyle(DS.Palette.placeholder)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) { content }
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(LinearGradient(colors: [Color.white.opacity(0.05),
                                                              Color.white.opacity(0.012)],
                                                     startPoint: .top, endPoint: .bottom))
                        }
                }
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(DS.Palette.hairlineSoft, lineWidth: 1))
        }
        .padding(.bottom, 18)
    }
}

struct SheetRow<Trailing: View>: View {
    let symbol: String
    let label: String
    var tint: Color?
    var action: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        let row = HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(tint ?? DS.Palette.inkMuted)
                .frame(width: 22)
            Text(label)
                .font(.system(size: 15.5, weight: .regular))
                .foregroundStyle(tint ?? DS.Palette.ink)
            Spacer()
            trailing
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .contentShape(Rectangle())

        if let action {
            Button(action: action) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }
}

struct SheetDivider: View {
    var body: some View {
        Rectangle().fill(DS.Palette.hairlineSoft).frame(height: 1).padding(.leading, 49)
    }
}

struct SheetChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(DS.Palette.placeholder)
    }
}

// MARK: - Profile (what the menu button opens)

/// One sheet for the person and their settings. They were two, which meant the
/// profile could only be reached through a row inside itself and the same face
/// and email were drawn twice in two different sizes.
struct ProfileSheet: View {
    let onHome: () -> Void
    let onChat: () -> Void
    let onJudgment: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var notifications = true
    @State private var voice = "Iris"
    @State private var speaks = true

    var body: some View {
        SheetChrome(title: "Profile") {
            VStack(spacing: 0) {
                PersonaAsset.image("AvatarShaurya")
                    .resizable().scaledToFill()
                    .frame(width: 92, height: 92)
                    .clipShape(Circle())
                    .padding(.bottom, 14)
                Text("Shaurya Duggal")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(DS.Palette.ink)
                Text(verbatim: "duggalshaurya1234@gmail.com")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(DS.Palette.subtle)
                Text("IRIS PRO · JOINED MARCH 2026")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(DS.Palette.placeholder)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 26)

            SheetSection(title: "This week") {
                SheetRow(symbol: "checkmark.seal", label: "Handled without asking") {
                    Text("14").font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(DS.Palette.subtle)
                }
                SheetDivider()
                SheetRow(symbol: "hand.raised", label: "Asked you") {
                    Text("6").font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(DS.Palette.subtle)
                }
                SheetDivider()
                SheetRow(symbol: "arrow.uturn.backward", label: "Undone") {
                    Text("1").font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(DS.Palette.subtle)
                }
            }

            SheetSection(title: "Go to") {
                SheetRow(symbol: "house", label: "Home", action: { dismiss(); onHome() }) { SheetChevron() }
                SheetDivider()
                SheetRow(symbol: "text.bubble", label: "Chat", action: { dismiss(); onChat() }) { SheetChevron() }
                SheetDivider()
                SheetRow(symbol: "brain", label: "Judgment", action: { dismiss(); onJudgment() }) { SheetChevron() }
            }

            SheetSection(title: "Voice") {
                SheetRow(symbol: "waveform", label: "Voice") {
                    Menu {
                        ForEach(["Iris", "Ash", "Cove"], id: \.self) { candidate in
                            Button(candidate) { voice = candidate }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(voice).font(.system(size: 15, weight: .regular))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(DS.Palette.subtle)
                    }
                }
                SheetDivider()
                SheetRow(symbol: "speaker.wave.2", label: "Ask out loud") {
                    Toggle("", isOn: $speaks).labelsHidden()
                }
                SheetDivider()
                SheetRow(symbol: "bell", label: "Notifications") {
                    Toggle("", isOn: $notifications).labelsHidden()
                }
            }

            SheetSection(title: "More") {
                SheetRow(symbol: "hand.raised", label: "Privacy", action: {}) { SheetChevron() }
                SheetDivider()
                SheetRow(symbol: "questionmark.circle", label: "Help", action: {}) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.Palette.placeholder)
                }
                SheetDivider()
                SheetRow(symbol: "rectangle.portrait.and.arrow.right",
                         label: "Sign out", tint: DS.Palette.danger, action: {}) { EmptyView() }
            }

            Text("IRIS 1.0 (TRIAL)")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .kerning(1)
                .foregroundStyle(DS.Palette.placeholder)
                .frame(maxWidth: .infinity)
        }
    }
}
