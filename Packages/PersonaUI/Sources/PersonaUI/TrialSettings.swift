import SwiftUI
import PersonaDesign

/// Settings — the page a signed-in user expects to exist. Static data, live
/// controls: every toggle toggles, every row presses, nothing dead.
struct SettingsSheet: View {
    @State private var notifications = true
    @State private var voice = "Iris"
    @State private var speaks = true

    var body: some View {
        SheetChrome(title: "Settings") {
            SheetSection {
                HStack(spacing: 13) {
                    PersonaAsset.image("AvatarShaurya")
                        .resizable().scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Shaurya Duggal")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(DS.Palette.ink)
                        Text("duggalshaurya1234@gmail.com")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(DS.Palette.subtle)
                    }
                    Spacer()
                    Text("PRO")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(DS.Palette.onInk)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(DS.Palette.ink, in: Capsule())
                }
                .padding(.horizontal, 14)
                .frame(height: 72)
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
                    Toggle("", isOn: $speaks).labelsHidden().tint(DS.Palette.ink)
                }
                SheetDivider()
                SheetRow(symbol: "bell", label: "Notifications") {
                    Toggle("", isOn: $notifications).labelsHidden().tint(DS.Palette.ink)
                }
            }

            SheetSection(title: "Permissions") {
                SheetRow(symbol: "brain", label: "Judgment", action: {
                    DecisionEngine.shared.judgmentShown = true
                }) { SheetChevron() }
                SheetDivider()
                SheetRow(symbol: "hand.raised", label: "Privacy", action: {}) { SheetChevron() }
            }

            SheetSection(title: "More") {
                SheetRow(symbol: "rectangle.portrait.and.arrow.right",
                         label: "Sign out", tint: DS.Palette.danger, action: {}) { EmptyView() }
            }
        }
        .sensoryFeedback(.selection, trigger: notifications)
        .sensoryFeedback(.selection, trigger: speaks)
        .sensoryFeedback(.selection, trigger: voice)
    }
}

private extension View {
    func settingsCard() -> some View {
        background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(DS.Palette.hairlineSoft, lineWidth: 1))
    }
}
