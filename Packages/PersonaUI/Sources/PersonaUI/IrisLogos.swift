import SwiftUI
import PersonaDesign

/// Real-app tiles for the run steps. Drawn, not fetched: the trial has no
/// network, and a step that says "Mail" should look like Mail from across
/// the room. Same trick as the challenge-one build.
enum IrisLogo {
    case doordash
    case iris, mail, calendar, messages, resy, github, delta, wallet, check
}

extension IrisLogo {
    /// The app's own colour, used to tint the card that came from it. A card
    /// from Resy should not look identical to a card from Delta.
    var accent: Color {
        switch self {
        case .mail:      Color(red: 0.11, green: 0.51, blue: 0.95)
        case .calendar:  Color(red: 0.92, green: 0.24, blue: 0.20)
        case .messages:  Color(red: 0.20, green: 0.78, blue: 0.35)
        case .resy:      Color(red: 0.93, green: 0.15, blue: 0.22)
        case .github:    Color(white: 0.82)
        case .delta:     Color(red: 0.83, green: 0.10, blue: 0.26)
        case .wallet:    Color(red: 0.99, green: 0.62, blue: 0.09)
        case .check:     Color(red: 0.27, green: 0.78, blue: 0.40)
        case .doordash:  Color(red: 0.94, green: 0.23, blue: 0.16)
        case .iris:      Color(white: 0.75)
        }
    }
}

struct IrisLogoTile: View {
    let logo: IrisLogo
    var size: CGFloat = 22

    var body: some View {
        Group {
            switch logo {
            case .iris:
                // The same mark the header draws. A second, invented Iris logo
                // in the lists made the product look like two products.
                PersonaAsset.image("PersonaMark")
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(size * 0.16)
                    .foregroundStyle(DS.Palette.ink)
                    .frame(width: size, height: size)
            case .doordash:
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .fill(Color(red: 0.94, green: 0.23, blue: 0.16))
                    Text("D")
                        .font(.system(size: size * 0.58, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
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
                        .fill(Color.white)
                    VectorMark(commands: BrandPath.github, viewBox: CGSize(width: 24, height: 24))
                        .fill(Color.black)
                        .frame(width: size * 0.76, height: size * 0.76)
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
