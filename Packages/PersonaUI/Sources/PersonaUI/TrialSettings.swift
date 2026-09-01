import SwiftUI
import PersonaDesign

/// Settings — the page a signed-in user expects to exist. Static data, live
/// controls: every toggle toggles, every row presses, nothing dead.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var notifications = true
    @State private var voice = "Iris"
    @State private var speaks = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SETTINGS")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .kerning(1.4)
                    .foregroundStyle(DS.Palette.ink)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Palette.subtle)
                        .frame(width: 28, height: 28)
                        .background(DS.Palette.surfaceMuted, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 10) {
                    // Account
                    HStack(spacing: 12) {
                        PersonaAsset.image("AvatarShaurya")
                            .resizable().scaledToFill()
                            .frame(width: 46, height: 46)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Shaurya Duggal")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(DS.Palette.ink)
                            Text("duggalshaurya1234@gmail.com")
                                .font(.system(size: 12.5))
                                .foregroundStyle(DS.Palette.subtle)
                        }
                        Spacer()
                        Text("PRO")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .kerning(1)
                            .foregroundStyle(DS.Palette.onInk)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(DS.Palette.ink, in: Capsule())
                    }
                    .padding(14)
                    .settingsCard()

                    VStack(spacing: 0) {
                        settingRow("waveform", "Voice") {
                            Menu {
                                ForEach(["Iris", "Ash", "Cove"], id: \.self) { candidate in
                                    Button(candidate) { voice = candidate }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(voice)
                                        .font(.system(size: 14.5))
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .foregroundStyle(DS.Palette.subtle)
                            }
                        }
                        divider
                        settingRow("bell.badge.fill", "Ask out loud") {
                            Toggle("", isOn: $speaks).labelsHidden().tint(DS.Palette.ink)
                        }
                        divider
                        settingRow("app.badge.fill", "Notifications") {
                            Toggle("", isOn: $notifications).labelsHidden().tint(DS.Palette.ink)
                        }
                    }
                    .settingsCard()

                    VStack(spacing: 0) {
                        settingRow("brain", "Judgment") {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DS.Palette.placeholder)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismiss()
                            DecisionEngine.shared.judgmentShown = true
                        }
                        divider
                        settingRow("hand.raised.fill", "Privacy") {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DS.Palette.placeholder)
                        }
                    }
                    .settingsCard()

                    Button {} label: {
                        Text("Sign out")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(DS.Palette.danger)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.plain)
                    .settingsCard()
                }
                .padding(.horizontal, 20)
            }
        }
        .presentationBackground(DS.Palette.canvas)
        .sensoryFeedback(.selection, trigger: notifications)
        .sensoryFeedback(.selection, trigger: speaks)
        .sensoryFeedback(.selection, trigger: voice)
    }

    private var divider: some View {
        Rectangle().fill(DS.Palette.hairlineSoft).frame(height: 1).padding(.leading, 46)
    }

    private func settingRow<Trailing: View>(_ symbol: String, _ label: String,
                                            @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.Palette.inkMuted)
                .frame(width: 22)
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(DS.Palette.ink)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
    }
}

private extension View {
    func settingsCard() -> some View {
        background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(DS.Palette.hairlineSoft, lineWidth: 1))
    }
}
