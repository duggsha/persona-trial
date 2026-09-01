import SwiftUI
import PersonaDesign

/// Real-app tiles for the run steps. Drawn, not fetched: the trial has no
/// network, and a step that says "Mail" should look like Mail from across
/// the room. Same trick as the challenge-one build.
enum IrisLogo {
    case iris, mail, calendar, messages, resy, github, delta, wallet, check
}

struct IrisLogoTile: View {
    let logo: IrisLogo
    var size: CGFloat = 22

    var body: some View {
        Group {
            switch logo {
            case .iris:
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 0.75, green: 0.62, blue: 1.0),
                                                  Color(red: 0.98, green: 0.62, blue: 0.45)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: size, height: size)
            case .mail:
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.11, green: 0.63, blue: 0.95),
                                                      Color(red: 0.05, green: 0.45, blue: 0.88)],
                                             startPoint: .top, endPoint: .bottom))
                    Image(systemName: "envelope.fill")
                        .font(.system(size: size * 0.5))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
            case .calendar:
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .fill(Color.white)
                    Text("WED")
                        .font(.system(size: size * 0.22, weight: .semibold))
                        .foregroundStyle(Color(red: 0.95, green: 0.26, blue: 0.21))
                        .padding(.top, size * 0.1)
                    Text("3")
                        .font(.system(size: size * 0.42, weight: .medium))
                        .foregroundStyle(.black)
                        .padding(.top, size * 0.32)
                }
                .frame(width: size, height: size)
            case .messages:
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.9, blue: 0.44),
                                                      Color(red: 0.13, green: 0.77, blue: 0.35)],
                                             startPoint: .top, endPoint: .bottom))
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: size * 0.5))
                        .foregroundStyle(.white)
                        .offset(y: -size * 0.02)
                }
                .frame(width: size, height: size)
            case .resy:
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .fill(Color(red: 0.91, green: 0.19, blue: 0.28))
                    Text("R")
                        .font(.system(size: size * 0.55, weight: .heavy, design: .serif))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
            case .github:
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .fill(Color(white: 0.1))
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
            case .delta:
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.6, green: 0.08, blue: 0.2),
                                                      Color(red: 0.83, green: 0.1, blue: 0.26)],
                                             startPoint: .top, endPoint: .bottom))
                    Image(systemName: "airplane")
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(-45))
                }
                .frame(width: size, height: size)
            case .wallet:
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .fill(Color(white: 0.13))
                    VStack(spacing: size * 0.055) {
                        Capsule().fill(Color(red: 0.28, green: 0.62, blue: 0.99)).frame(height: size * 0.14)
                        Capsule().fill(Color(red: 1.0, green: 0.8, blue: 0.25)).frame(height: size * 0.14)
                        RoundedRectangle(cornerRadius: size * 0.07)
                            .fill(Color(white: 0.85))
                            .frame(height: size * 0.28)
                    }
                    .padding(size * 0.17)
                }
                .frame(width: size, height: size)
            case .check:
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .fill(DS.Palette.ink)
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.45, weight: .bold))
                        .foregroundStyle(DS.Palette.onInk)
                }
                .frame(width: size, height: size)
            }
        }
    }
}
