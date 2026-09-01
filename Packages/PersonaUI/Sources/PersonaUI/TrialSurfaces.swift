import SwiftUI
import PersonaCore
import PersonaDesign

// MARK: - Iris outside the app

/// The argument for muting everything else: your phone currently delivers the
/// message and nothing more, so every notification is a task you now have to go
/// do. Iris delivers the message AND the reply it already wrote, and you finish
/// it from the lock screen without opening anything.
struct NotificationsSheet: View {
    @State private var muted = true
    @State private var approved = false

    var body: some View {
        SheetChrome(title: "Notifications") {
            LockScreenMock(approved: $approved)
                .padding(.bottom, 22)

            SheetSection(title: "Silenced, and answered instead") {
                MutedRow(logo: .messages, name: "Messages", muted: muted)
                SheetDivider()
                MutedRow(logo: .mail, name: "Mail", muted: muted)
                SheetDivider()
                HStack(spacing: 13) {
                    IrisLogoTile(logo: .iris, size: 26)
                    Text("Let Iris answer for them")
                        .font(.system(size: 16.5, weight: .regular))
                        .foregroundStyle(DS.Palette.ink)
                    Spacer(minLength: 8)
                    Toggle("", isOn: $muted).labelsHidden()
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 58)
            }

            SheetSection(title: "Widget") {
                HomeWidgetMock()
                    .padding(14)
            }
        }
    }
}

private struct MutedRow: View {
    let logo: IrisLogo
    let name: String
    let muted: Bool

    var body: some View {
        HStack(spacing: 13) {
            IrisLogoTile(logo: logo, size: 26)
                .opacity(muted ? 0.45 : 1)
            Text(name)
                .font(.system(size: 16.5, weight: .regular))
                .foregroundStyle(muted ? DS.Palette.placeholder : DS.Palette.ink)
            Spacer(minLength: 8)
            if muted {
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Palette.placeholder)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
    }
}

/// The lock screen, with the whole decision on it.
private struct LockScreenMock: View {
    @Binding var approved: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("9:41")
                .font(.system(size: 52, weight: .thin))
                .foregroundStyle(.white)
                .padding(.top, 26)
            Text("Saturday, August 31")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.bottom, 26)

            notification
                .padding(.horizontal, 12)
                .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.20),
                                    Color(red: 0.04, green: 0.05, blue: 0.09)],
                           startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }

    private var notification: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                IrisLogoTile(logo: .iris, size: 17)
                Text("IRIS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                Spacer(minLength: 0)
                Text("now")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .frame(height: 30)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    IrisLogoTile(logo: .messages, size: 15)
                    Text("Maya Chen")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text("we still on for saturday? need to give them a headcount tonight")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)

                Text(approved ? "SENT" : "IRIS WROTE")
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(approved ? DS.Palette.success : .white.opacity(0.45))
                    .padding(.top, 2)

                Text("Yes, count me in for Saturday.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(
                        LinearGradient(colors: [Color(red: 0.16, green: 0.53, blue: 1),
                                                Color(red: 0.05, green: 0.40, blue: 0.96)],
                                       startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .opacity(approved ? 0.55 : 1)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 13)

            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)

            // The whole point: the decision ends here, not in another app.
            HStack(spacing: 0) {
                Button {
                    withAnimation(.snappy(duration: 0.25)) { approved = true }
                    _ = DSHaptics.tap(.rigid)
                } label: {
                    Text(approved ? "Sent" : "Send")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(approved ? .white.opacity(0.45) : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .disabled(approved)

                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 26)

                Text("Edit")
                    .font(.system(size: 14.5))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)

                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 26)

                Text("Not now")
                    .font(.system(size: 14.5))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}

/// The home-screen widget: the count, and the one ask that matters most.
private struct HomeWidgetMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                IrisLogoTile(logo: .iris, size: 15)
                Text("2 ASKS")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(DS.Palette.placeholder)
                Spacer(minLength: 0)
                IrisLogoTile(logo: .messages, size: 15)
            }

            Spacer(minLength: 10)

            Text("Tell Maya you're in for Saturday?")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(DS.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 10)

            Text("Send it")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Palette.onInk)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(DS.Palette.ink, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(14)
        .frame(width: 168, height: 168)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .frame(maxWidth: .infinity)
    }
}
