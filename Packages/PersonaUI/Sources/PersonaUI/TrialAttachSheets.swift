import SwiftUI
import PersonaCore
import PersonaDesign

// MARK: - What the + actually opens

/// The apps Iris is allowed to act inside. This is the page an agent product
/// has to have and usually doesn't: not "integrations" as a marketing list, but
/// the standing reach of the thing acting on your behalf, with the scope spelled
/// out and a switch beside it.
struct ConnectedAppsSheet: View {
    private struct App: Identifiable {
        let id = UUID()
        let logo: IrisLogo
        let name: String
        let scope: String
        var on: Bool
    }

    @State private var apps: [App] = [
        App(logo: .mail, name: "Mail", scope: "Read · draft · send as you", on: true),
        App(logo: .calendar, name: "Calendar", scope: "Read · hold · invite", on: true),
        App(logo: .resy, name: "Resy", scope: "Search · book · cancel", on: true),
        App(logo: .github, name: "GitHub", scope: "Read codes only", on: true),
        App(logo: .delta, name: "Delta", scope: "Read flight status", on: true),
        App(logo: .messages, name: "Messages", scope: "Not connected", on: false),
        App(logo: .wallet, name: "Wallet", scope: "Not connected", on: false)
    ]

    private var liveCount: Int { apps.filter(\.on).count }

    var body: some View {
        SheetChrome(title: "Apps") {
            SheetSection(title: "\(liveCount) connected") {
                ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                    if index > 0 { SheetDivider() }
                    HStack(spacing: 13) {
                        IrisLogoTile(logo: app.logo, size: 26)
                        Text(app.name)
                            .font(.system(size: 16.5, weight: .regular))
                            .foregroundStyle(DS.Palette.ink)
                        Spacer(minLength: 8)
                        Toggle("", isOn: Binding(
                            get: { apps[index].on },
                            set: { apps[index].on = $0 }
                        ))
                        .labelsHidden()
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 58)
                }
            }
        }
    }
}

/// Recents, as a picker. Real tiles rather than a grey grid, so the sheet reads
/// as a working library instead of a placeholder.
struct PhotosSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Int?

    private let assets = ["AvatarSarah", "AvatarJason", "AvatarShaurya"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        SheetChrome(title: "Photos") {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(0 ..< 18, id: \.self) { index in
                    Button {
                        picked = index
                        _ = DSHaptics.tap(.light)
                    } label: {
                        ZStack {
                            if index % 4 == 0 {
                                PersonaAsset.image(assets[(index / 4) % assets.count])
                                    .resizable().scaledToFill()
                            } else {
                                LinearGradient(
                                    colors: [Color(hue: Double(index) / 22, saturation: 0.30, brightness: 0.34),
                                             Color(hue: Double(index) / 22, saturation: 0.22, brightness: 0.16)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing)
                            }
                        }
                        .frame(height: 118)
                        .clipped()
                        .overlay(alignment: .topTrailing) {
                            if picked == index {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 17))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(Color.black, Color.white)
                                    .padding(6)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                dismiss()
            } label: {
                Text(picked == nil ? "Choose a photo" : "Attach 1 photo")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(picked == nil ? DS.Palette.placeholder : DS.Palette.onInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(picked == nil ? DS.Palette.surfaceMuted : DS.Palette.ink,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(picked == nil)
            .padding(.top, 14)
        }
    }
}

/// Files, with the detail that matters for an agent: not just the name, but
/// whether Iris has already read it.
struct FilesSheet: View {
    private struct Doc: Identifiable {
        let id = UUID()
        let icon: String
        let tint: Color
        let name: String
        let meta: String
        let read: Bool
    }

    private let docs: [Doc] = [
        Doc(icon: "doc.richtext", tint: Color(red: 0.30, green: 0.55, blue: 0.95),
            name: "Northwind walkthrough.pdf", meta: "2.4 MB · yesterday", read: true),
        Doc(icon: "tablecells", tint: Color(red: 0.20, green: 0.70, blue: 0.40),
            name: "Firmware timeline.xlsx", meta: "88 KB · 3 days ago", read: true),
        Doc(icon: "doc.text", tint: Color(white: 0.62),
            name: "Boards v4 notes.txt", meta: "6 KB · last week", read: false),
        Doc(icon: "photo.stack", tint: Color(red: 0.95, green: 0.55, blue: 0.15),
            name: "Printed boards.zip", meta: "41 MB · last week", read: false)
    ]

    var body: some View {
        SheetChrome(title: "Files") {
            SheetSection(title: "Recent") {
                ForEach(Array(docs.enumerated()), id: \.element.id) { index, doc in
                    if index > 0 { SheetDivider() }
                    HStack(spacing: 13) {
                        Image(systemName: doc.icon)
                            .font(.system(size: 17))
                            .foregroundStyle(doc.tint)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(doc.name)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(DS.Palette.ink)
                                .lineLimit(1)
                            Text(doc.meta)
                                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                                .foregroundStyle(DS.Palette.placeholder)
                        }
                        Spacer(minLength: 8)
                        if doc.read {
                            Text("READ")
                                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                .kerning(0.8)
                                .foregroundStyle(DS.Palette.placeholder)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 56)
                }
            }
        }
    }
}
