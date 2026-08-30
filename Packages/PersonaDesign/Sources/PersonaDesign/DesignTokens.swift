import SwiftUI

/// The single source of visual truth. No raw hex / magic numbers in feature code —
/// everything routes through `DS`.
public enum DS {
    // MARK: - Palette

    /// ADAPTIVE palette. Every token resolves to EXACTLY its historical hex in
    /// light mode — light is pixel-identical by construction — and to a curated
    /// dark variant when the window is dark. Dark only ever renders where a
    /// surface opts in (the appearance preference defaults to light until a
    /// screen is migrated); tokens being adaptive up-front means migration is
    /// "replace hardcodes with tokens", never "touch the palette again".
    public enum Palette {
        public static let ink = Color(light: 0x161616, dark: 0xF2F2F7)
        /// Pure-black ink for text whose historical light value was EXACTLY
        /// #000000 (bubble bodies, task-card titles/labels, search fields) —
        /// routing those through `ink` would shift light by 0x16. Same dark
        /// value as ink, so dark reads as one text color.
        public static let inkBlack = Color(light: 0x000000, dark: 0xF2F2F7)
        /// Label/glyph color for content sitting ON an ink-filled control:
        /// white in light (ink is near-black there), near-black in dark (ink
        /// flips to near-white). A hardcoded `.white` label on an ink fill
        /// disappears the moment the fill adapts.
        public static let onInk = Color(light: 0xFFFFFF, dark: 0x141416)
        public static let inkSoft = Color(light: 0x3D3D3D, dark: 0xD1D1D6)
        public static let inkMuted = Color(light: 0x4B4B4B, dark: 0xC7C7CC)
        public static let subtle = Color(light: 0x666666, dark: 0xAEAEB2)
        public static let placeholder = Color(light: 0x9D9D9D, dark: 0x8E8E93)

        public static let accent = Color(light: 0x378FFF, dark: 0x409CFF)
        /// The user bubble's solid tone — the monochrome scheme's near-black
        /// (assistant bubbles are card-colored); also worn by send buttons and
        /// the voice-note controls that used to ride the iMessage blue. Dark
        /// lifts it a step off the canvas so the bubble still reads as a shape.
        public static let userBubble = Color(light: 0x17191E, dark: 0x3A3A3C)
        /// A drafted message quoted inside a grammar card. This is deliberately
        /// lighter than `userBubble`: the draft is an inset surface on a white
        /// card, where near-black reads as a hole rather than a message bubble.
        public static let draftBubble = Color(light: 0x3A3A3A, dark: 0x48484A)
        public static let chatBlue = Color(hex: 0x0070E9)
        public static let success = Color(hex: 0x44C867)
        /// Failure/danger red. Light = the 0xE34D56 hardcoded across
        /// ConnectScaffold.swift (ConnectError) and LiveCallView's stream-error
        /// line (VoiceCallView.swift); dark = TaskState.red's dark pitch.
        public static let danger = Color(light: 0xE34D56, dark: 0xFF6B54)
        /// "Needs you" amber; TaskState.amber promoted to the app palette
        /// (TaskSurfaces.swift's TaskPalette.attention already aliases it).
        public static let attention = TaskState.amber

        public static let surface = Color(light: 0xF9F9FA, dark: 0x1C1C1E)
        public static let surfaceMuted = Color(light: 0xF5F5F5, dark: 0x2C2C2E)
        public static let surfaceAlt = Color(light: 0xF6F6F6, dark: 0x2C2C2E)

        public static let hairline = Color(light: 0xDADADA, dark: 0xFFFFFF, darkOpacity: 0.16)
        public static let hairlineSoft = Color(light: 0xF2F2F2, dark: 0xFFFFFF, darkOpacity: 0.10)
        public static let track = Color(light: 0xEAEAEA, dark: 0xFFFFFF, darkOpacity: 0.14)
        public static let tint = Color(light: 0xC2E8FA, dark: 0x1D3A50)

        public static let shadow = Color(light: 0x1E1A24, dark: 0x000000, darkOpacity: 0)

        /// The one card color across the app: the solid plate Home cards,
        /// bubbles and sheet rows wear. Today's hardcoded `.white` — migrate
        /// card fills HERE, never to another literal. Dark = elevated charcoal
        /// (a true-black card on a near-black canvas reads as a hole).
        public static let card = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
        /// The flat app canvas behind every screen (SharedAppBackground).
        public static let canvas = Color(light: 0xF8F8F8, dark: 0x141416)

        /// The hold-to-talk rim (universal update/suggestion card): the ONE
        /// place color enters the monochrome system — a soft pastel conic
        /// that sweeps the card while Iris listens, dimmed and slowed while
        /// she works. First and last stop match so the sweep tiles seamlessly.
        public static let listeningGlow: [Color] = [
            Color(hex: 0x8FB6FF), Color(hex: 0xC7B7F0), Color(hex: 0xF1C9AE),
            Color(hex: 0x9FD8C4), Color(hex: 0x8FB6FF),
        ]

        /// Figma primary-action fill (node 1246:848/849): charcoal left-to-right.
        /// Dark lifts both stops so the button separates from dark surfaces.
        public static let primaryActionGradient = LinearGradient(
            colors: [Color(light: 0x272727, dark: 0x3C3D44), Color(light: 0x444444, dark: 0x5A5B63)],
            startPoint: .leading,
            endPoint: .trailing
        )
        public static let primaryActionOuterGradient = LinearGradient(
            colors: [
                Color(light: 0x494949, dark: 0x60616A, lightOpacity: 0.9, darkOpacity: 0.9),
                Color(light: 0x383838, dark: 0x4A4B54, lightOpacity: 0.9, darkOpacity: 0.9),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Task state family

    /// The task-state palette from the reference mock (task-states,
    ///), shared by the Home cards and the chat task surfaces so a
    /// task wears ONE family everywhere: olive-gold "needs you", the badge
    /// green/red, the borderless state bubbles, and the grey action chips.
    /// Adaptive like DS.Palette: light = the mock's exact hex, dark = the same
    /// hue re-pitched for the charcoal card (pastel washes become tinted
    /// darks, the grey chips join the iOS-gray elevation ladder — a light
    /// pastel plate on a dark card reads as a glowing hole otherwise).
    public enum TaskState {
        public static let amber = Color(light: 0xBBA958, dark: 0xD9C874)
        public static let green = Color(light: 0x2D9B3C, dark: 0x30C144)
        public static let red = Color(light: 0xF24B2F, dark: 0xFF6B54)
        public static let bubbleAmber = Color(light: 0xF3EFDE, dark: 0x3B3524)
        public static let bubbleGreen = Color(light: 0xEBF6E9, dark: 0x22371F)
        public static let bubbleRed = Color(light: 0xF6EAE9, dark: 0x3B2523)
        public static let bubbleGrey = Color(light: 0xF2F2F2, dark: 0x2C2C2E)
        public static let bubbleText = Color(light: 0x565656, dark: 0xD6D6DB)
        public static let chipFill = Color(light: 0xF3F3F3, dark: 0x3A3A3C)
        public static let checkCircle = Color(light: 0x303030, dark: 0x48484A)
    }

    // MARK: - Spacing

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        /// The screen's standard horizontal gutter.
        public static let gutter: CGFloat = 20
        public static let xl: CGFloat = 24
        public static let section: CGFloat = 32
    }

    // MARK: - Radius

    public enum Radius {
        public static let sm: CGFloat = 8
        /// The 34pt header icon tile's rounding (chat-card v2); a tile accent,
        /// not part of the surface scale below.
        public static let iconTile: CGFloat = 10
        public static let md: CGFloat = 12
        /// Inner wells INSIDE a chatCardPanel; chatCardInset's md + 2, named.
        public static let inset: CGFloat = 14
        public static let bubble: CGFloat = 20
        /// Wallet-pass surfaces: a step rounder than a bubble, softer than a card.
        public static let pass: CGFloat = 22
        /// 34 read as a lozenge once cards stacked in a list: at row height the
        /// corners ate most of the vertical edge and the stack lost its rhythm.
        /// 28 keeps the card soft and distinctly rounder than a bubble (the
        /// invariant PaletteTests pins) without the lozenge, and lands on the
        /// 4pt scale the rest of this enum uses.
        public static let card: CGFloat = 28
        public static let pill: CGFloat = 999
    }

    // MARK: - Metrics

    /// Chat-card v2 fixed geometry (design audit).
    public enum Metrics {
        public static let chatCardMaxWidth: CGFloat = 320
        public static let cardPadding: CGFloat = 14
        public static let actionRowHeight: CGFloat = 40
        public static let pillHeightSm: CGFloat = 30
        public static let pillHeightMd: CGFloat = 44
        /// The header icon tile's edge (rounded at Radius.iconTile).
        public static let iconTile: CGFloat = 34
    }

    // MARK: - Shadow

    /// The two existing card shadow recipes, NAMED; values are Glass.swift's
    /// verbatim (chatCardPanel / solidCardPlate), which now consume these.
    public enum Shadow {
        /// One drop-shadow layer, always cast in black at `opacity`.
        public struct Layer: Equatable, Sendable {
            public let opacity: Double
            public let radius: CGFloat
            public let x: CGFloat
            public let y: CGFloat

            public init(opacity: Double, radius: CGFloat, x: CGFloat, y: CGFloat) {
                self.opacity = opacity
                self.radius = radius
                self.x = x
                self.y = y
            }
        }

        /// The ambient-halo + tight-contact pair every full card plate wears.
        public struct Pair: Equatable, Sendable {
            public let ambient: Layer
            public let key: Layer

            public init(ambient: Layer, key: Layer) {
                self.ambient = ambient
                self.key = key
            }
        }

        /// The chat bubble/card contact shadow (Figma spec): black 4%, y 3, σ2.
        public static let contact = Layer(opacity: 0.04, radius: 2, x: 0, y: 3)
        /// solidCardPlate's depth pair: soft ambient halo + tight contact.
        public static let plate = Pair(
            ambient: Layer(opacity: 0.08, radius: 18, x: 0, y: 8),
            key: Layer(opacity: 0.05, radius: 3, x: 0, y: 1.5)
        )
        /// The COLLAPSED row's shallower pair (`--shadow-chip`). A tier-3 row
        /// sits lower in the stack than the card it opens into, and matching
        /// `plate` would give a 54pt row the same lift as a full card.
        /// CSS blur is diameter, so 8px/2px land as radius 4/1 here.
        public static let chip = Pair(
            ambient: Layer(opacity: 0.06, radius: 4, x: 0, y: 2),
            key: Layer(opacity: 0.04, radius: 1, x: 0, y: 1)
        )
    }

    // MARK: - Typography

    public enum Typography {
        public static let greeting = Font.system(size: 24, weight: .semibold)
        public static let sectionTitle = Font.system(size: 18, weight: .semibold)
        public static let cardTitle = Font.system(size: 16, weight: .semibold)
        public static let body = Font.system(size: 16, weight: .regular)
        public static let figure = Font.system(size: 32, weight: .semibold)
        public static let label = Font.system(size: 14, weight: .medium)
        public static let caption = Font.system(size: 12, weight: .medium)
        /// Card eyebrow ("EMAIL" / "APPROVAL"): pair with .textCase(.uppercase)
        /// + a positive tracking; CardHeaderRow applies both.
        public static let cardLabel = Font.system(size: 12, weight: .medium)
        public static let micro = Font.system(size: 10, weight: .medium)
    }

    // MARK: - Motion

    public enum Motion {
        public static let standard = Animation.smooth(duration: 0.32, extraBounce: 0)
        public static let snappy = Animation.snappy(duration: 0.28)
        public static let gentle = Animation.easeInOut(duration: 0.22)
        public static let page = Animation.smooth(duration: 0.32, extraBounce: 0)
    }
}

// MARK: - Primary action surface

public struct DSPrimaryActionSurface<S: InsettableShape>: View {
    let shape: S
    let enabled: Bool

    public init(shape: S, enabled: Bool = true) {
        self.shape = shape
        self.enabled = enabled
    }

    public var body: some View {
        ZStack {
            // PERF: the shadow is cast by the OPAQUE base fill, not by the
            // three-layer stack. A shadow on the ZStack has to rasterize the
            // whole composite offscreen to derive its silhouette, re-done on
            // every frame the pill moves — and this pill rides every connect /
            // sign-in card in the transcript, so a scroll past one pays for it
            // continuously. The base fill covers the entire shape, so the
            // silhouette IS this shape: same shadow, no raster. (Same fix as
            // the card plates in Glass.swift.)
            shape.fill(DS.Palette.primaryActionOuterGradient)
                .shadow(color: .black.opacity(0.05), radius: 2.4, x: 0, y: 2.4)
            shape.inset(by: 1).fill(DS.Palette.primaryActionGradient)
            // Figma's inset 20%-white top light, kept inside the 1pt outer rim.
            shape.inset(by: 1).fill(
                LinearGradient(
                    colors: [.white.opacity(0.20), .clear, .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            )
        }
        .opacity(enabled ? 1 : 0.4)
    }
}

public extension View {
    /// Applies the exact charcoal primary-action treatment sampled from Figma.
    func primaryActionBackground<S: InsettableShape>(in shape: S, enabled: Bool = true) -> some View {
        background { DSPrimaryActionSurface(shape: shape, enabled: enabled) }
    }

    /// Cast one named shadow layer (DS.Shadow) from this view's silhouette;
    /// apply to the opaque plate shape, never a composited subtree (Glass.swift).
    func dsShadow(_ layer: DS.Shadow.Layer) -> some View {
        shadow(color: .black.opacity(layer.opacity), radius: layer.radius, x: layer.x, y: layer.y)
    }

    /// Cast a named shadow pair (ambient first, key second; the plate order).
    func dsShadow(_ pair: DS.Shadow.Pair) -> some View {
        dsShadow(pair.ambient).dsShadow(pair.key)
    }
}

// MARK: - Hex Color

public extension Color {
    /// `Color(hex: 0x378FFF)` — sRGB from a packed 24-bit value.
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    /// Trait-adaptive color: resolves to EXACTLY `light` in light mode and to
    /// `dark` in dark mode — the palette's dark-mode seam. Resolution happens
    /// at RENDER time per window, so a scheme flip re-paints live. Platforms
    /// without UIKit collapse to the light value (macOS tooling builds).
    init(light: UInt32, dark: UInt32, lightOpacity: Double = 1, darkOpacity: Double = 1) {
        #if canImport(UIKit)
            self.init(uiColor: UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(Color(hex: dark, opacity: darkOpacity))
                    : UIColor(Color(hex: light, opacity: lightOpacity))
            })
        #else
            self.init(hex: light, opacity: lightOpacity)
        #endif
    }
}

// MARK: - Appearance preference

/// The user's appearance pick (Settings → Customize): follow the system, or
/// pin light/dark. Stored raw in UserDefaults under `DSAppearance.storageKey`.
/// DEFAULT IS LIGHT (dark needs a polish round before it
/// ships) — dark/system stay OPT-IN via Settings until the punch list is
/// cleared.
public enum DSAppearance: String, CaseIterable, Identifiable, Sendable {
    case light
    case dark
    case system

    public static let storageKey = "app.appearance"
    public var id: String { rawValue }

    /// What `.preferredColorScheme` should receive: nil = follow the system.
    public var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }

    public var label: String {
        switch self {
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        case .system: String(localized: "Automatic")
        }
    }
}

private struct DSAppearanceModifier: ViewModifier {
    @AppStorage(DSAppearance.storageKey) private var raw = DSAppearance.light.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Low Power Mode drops the geometry too — see DSPowerState.
    @Environment(\.dsPowerSaving) private var powerSaving
    /// Whether a flip should be dressed up yet. See the sleep below.
    @State private var armed = false

    func body(content: Content) -> some View {
        content
            .preferredColorScheme((DSAppearance(rawValue: raw) ?? .light).colorScheme)
            // The flip itself is one un-animatable frame; DSAppearanceTransition
            // covers it at the window. Every writer of the preference gets this
            // for free — Settings, the in-chat card, the streamed assistant
            // change — because it hangs off APPLYING the value, not writing it.
            .onChange(of: raw) { _, _ in
                guard armed else { return }
                DSAppearanceTransition.run(motionAllowed: !reduceMotion && !powerSaving)
            }
            .task {
                // Don't dress up the LAUNCH reconcile. SettingsStore pulls the
                // backend's stored pick milliseconds in, when the first frame
                // may not be on screen yet — snapshotting there fades a blank
                // window, which looks like a flash of nothing.
                try? await Task.sleep(for: .milliseconds(800))
                armed = true
            }
    }
}

public extension View {
    /// Apply the user's appearance preference to this window. Replaces the
    /// hard `.preferredColorScheme(.light)` at migrated roots — un-migrated
    /// sheets keep their explicit light force until their sweep lands.
    func dsAppearance() -> some View {
        modifier(DSAppearanceModifier())
    }
}

// MARK: - Reduce-Motion-aware animation

public extension View {
    /// Applies an animation that automatically collapses when Reduce Motion is on.
    func dsAnimation(_ animation: Animation, value: some Equatable) -> some View {
        modifier(ReduceMotionAnimation(animation: animation, value: value))
    }
}

private struct ReduceMotionAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
