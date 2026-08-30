import SwiftUI

/// A reusable, dismissible coach-mark tooltip: a charcoal speech bubble with a
/// pointer, anchored to any view (an icon, a button) and rendered at the
/// SCREEN ROOT so it floats above scroll clipping and sibling chrome.
///
/// Usage — mark the anchor, host once at the root of the same hosting
/// controller (anchor preferences do not cross UIHostingController
/// boundaries, so a composer hosted in its own controller needs the host
/// inside that controller's hierarchy):
///
/// micButton.dsTooltip("Hold to record a voice memo", isPresented: $showTip)
/// ...
/// screenRoot.dsTooltipHost()
///
/// Tapping the bubble dismisses it (the trailing ✕ signals that); everything
/// else on screen stays fully interactive — no dim, no touch shield — so the
/// tip never blocks the control it's teaching.
public struct DSTooltipRequest: Equatable {
    let id: String
    let text: String
    let anchor: Anchor<CGRect>
    /// The side of the ANCHOR the bubble sits on. `.top` = above (default);
    /// the host flips it when the preferred side runs out of room.
    let edge: VerticalEdge
    /// Where the anchor currently IS, in global space. Carried purely so the
    /// equality below has a positional term — see `==`.
    let anchorY: CGFloat
    let onDismiss: () -> Void

    /// EQUATABLE ON PURPOSE (same lesson as TaskStopMenuRequest): a value
    /// SwiftUI can't compare re-propagates on every layout pass and can feed
    /// an invalidation loop. Closures are excluded (same id ⇒ same handler).
    ///
    /// `anchorY` IS load-bearing. `Anchor<CGRect>` is not comparable, and the
    /// original `==` compared only id/text/edge — so when the anchor MOVED
    /// with everything else about the request unchanged, SwiftUI saw an equal
    /// value, skipped the overlay rebuild, and the host went on resolving the
    /// FIRST anchor it was ever handed. That is how the composer rode 307pt up
    /// with the keyboard while the coach mark stayed exactly where it was,
    /// stranded ~283pt below the bar it points at:
    /// an anchor token is not a live reference, it is a snapshot of one layout
    /// pass. With the position in the equality the bubble re-resolves whenever
    /// the anchor actually moves, and still no more often than that.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.text == rhs.text && lhs.edge == rhs.edge
            && lhs.anchorY == rhs.anchorY
    }
}

public struct DSTooltipPreferenceKey: PreferenceKey {
    public static var defaultValue: DSTooltipRequest? { nil }
    public static func reduce(value: inout DSTooltipRequest?, nextValue: () -> DSTooltipRequest?) {
        value = value ?? nextValue()
    }
}

public extension View {
    /// Marks this view as a tooltip anchor. The preference is ALWAYS applied
    /// (value nil while hidden) — a conditional modifier here would change the
    /// view's identity on toggle and reset descendant @State.
    func dsTooltip(
        _ text: String,
        isPresented: Binding<Bool>,
        edge: VerticalEdge = .top,
        id: String = "ds-tooltip"
    ) -> some View {
        modifier(DSTooltipAnchor(text: text, isPresented: isPresented, edge: edge, id: id))
    }

    /// Hosts every `dsTooltip` in the subtree. Apply once at the screen root
    /// (within the same hosting controller as the anchors).
    func dsTooltipHost() -> some View {
        overlayPreferenceValue(DSTooltipPreferenceKey.self) { request in
            DSTooltipHostLayer(request: request)
        }
    }
}

/// Marks an anchor and keeps the request's position term current.
///
/// The `onGeometryChange` read is what makes the coach mark RIDE its anchor:
/// it fires whenever the marked view's global frame moves (the keyboard
/// raising the composer, a growing text field, the menu dive), which changes
/// `anchorY`, which makes the emitted request compare UNEQUAL, which is the
/// only thing that gets the host to resolve the new anchor. Reading the frame
/// alone would not be enough — the value has to reach the preference.
private struct DSTooltipAnchor: ViewModifier {
    let text: String
    @Binding var isPresented: Bool
    let edge: VerticalEdge
    let id: String
    @State private var anchorY: CGFloat = 0

    init(text: String, isPresented: Binding<Bool>, edge: VerticalEdge, id: String) {
        self.text = text
        _isPresented = isPresented
        self.edge = edge
        self.id = id
    }

    func body(content: Content) -> some View {
        content
            // Half-point deadband: this write feeds a preference the host
            // rebuilds on, so sub-pixel jitter must never be able to hand
            // layout a reason to run again.
            .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minY }) { newY in
                guard abs(newY - anchorY) > 0.5 else { return }
                anchorY = newY
            }
            // The preference is ALWAYS applied (value nil while hidden) — a
            // conditional modifier here would change the view's identity on
            // toggle and reset descendant @State.
            .anchorPreference(key: DSTooltipPreferenceKey.self, value: .bounds) { anchor in
                guard isPresented else { return nil }
                return DSTooltipRequest(
                    id: id, text: text, anchor: anchor, edge: edge, anchorY: anchorY
                ) {
                    isPresented = false
                }
            }
    }
}

/// Keeps the bubble MOUNTED through its fade-out (rendering the last request)
/// with hit-testing cut the instant it dismisses, so the disappearing bubble
/// can't swallow a tap meant for the control underneath.
private struct DSTooltipHostLayer: View {
    let request: DSTooltipRequest?
    @State private var lastRequest: DSTooltipRequest?
    /// Bumped on every request change; lets the deferred unmount below detect
    /// that a NEW tooltip presented while it slept and stand down.
    @State private var fadeGeneration = 0

    var body: some View {
        let active = request != nil
        ZStack {
            if let shown = request ?? lastRequest {
                DSTooltipLayer(request: shown, active: active)
            }
        }
        .allowsHitTesting(active)
        // The fading bubble is already untappable; hide it from assistive
        // tech too, so VoiceOver never lands on a dismissed tooltip.
        .accessibilityHidden(!active)
        .onChange(of: request) { _, _ in
            fadeGeneration += 1
            if request != nil {
                lastRequest = request
            } else {
                // Unmount once the fade-out finishes — the bubble must not
                // linger in the view/UI-test hierarchy after dismissal.
                let generation = fadeGeneration
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    if generation == fadeGeneration { lastRequest = nil }
                }
            }
        }
    }
}

private struct DSTooltipLayer: View {
    let request: DSTooltipRequest
    let active: Bool

    /// False for the first frame after mounting so the initial presentation
    /// animates in (the `active` animation only animates CHANGES on an
    /// already-mounted view).
    @State private var appeared = false
    @State private var bubbleSize: CGSize = .zero

    private var shown: Bool { active && appeared }

    private let pointerSize = CGSize(width: 14, height: 6)
    /// Gap between the anchor's edge and the pointer tip.
    private let anchorGap: CGFloat = 6
    private let screenMargin: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            let rect = proxy[request.anchor]
            // Flip when the preferred side runs out of room.
            let neededHeight = bubbleSize.height + pointerSize.height + anchorGap + screenMargin
            let above = request.edge == .top
                ? rect.minY - neededHeight >= 0
                : rect.maxY + neededHeight > proxy.size.height
            // The bubble hugs the screen edges; the pointer stays on the anchor.
            let bubbleX = min(
                max(rect.midX, screenMargin + bubbleSize.width / 2),
                proxy.size.width - screenMargin - bubbleSize.width / 2
            )
            let bubbleY = above
                ? rect.minY - anchorGap - pointerSize.height - bubbleSize.height / 2
                : rect.maxY + anchorGap + pointerSize.height + bubbleSize.height / 2

            bubble
                .onGeometryChange(for: CGSize.self, of: \.size) { bubbleSize = $0 }
                .background(alignment: above ? .bottom : .top) {
                    DSTooltipPointer(pointingDown: above)
                        .fill(DS.Palette.userBubble)
                        .frame(width: pointerSize.width, height: pointerSize.height)
                        .alignmentGuide(above ? .bottom : .top) { d in
                            above ? d[.top] : d[.bottom]
                        }
                        // Keep the pointer over the anchor even when the
                        // bubble itself was clamped off-center by the edge.
                        .offset(x: pointerOffset(anchorMidX: rect.midX, bubbleX: bubbleX))
                }
                // Proposal cap, NOT a stretch: the visible bubble (padding +
                // background) hugs its text, so short tips stay narrow while
                // long ones wrap at 264. Center-aligned, so `.position` below
                // (which places THIS frame) still centers the visible bubble.
                .frame(maxWidth: 264)
                .position(x: bubbleX, y: bubbleY)
                .scaleEffect(shown ? 1 : 0.86, anchor: above ? .bottom : .top)
                .offset(y: shown ? 0 : (above ? 5 : -5))
                .opacity(shown ? 1 : 0)
                .animation(.snappy(duration: 0.28, extraBounce: 0.06), value: shown)
        }
        // `.container` ONLY — never the keyboard region. A bare
        // `ignoresSafeArea()` defaults to `.all`, which opts the layer out of
        // the keyboard inset its own anchor rides: the composer went up 307pt
        // with the keyboard and the bubble stayed exactly where it was,
        // stranded ~283pt BELOW the bar it points at (design report,
        //). The bubble still needs to escape the container's
        // insets to sit over the bar's head-room, so keep that half.
        .ignoresSafeArea()
        .onAppear { appeared = true }
    }

    private var bubble: some View {
        HStack(spacing: 9) {
            Text(request.text)
                .font(.system(size: 13, weight: .medium))
                .tracking(-0.08)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(
            DS.Palette.userBubble,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .shadow(color: DS.Palette.shadow.opacity(0.16), radius: 10, y: 4)
        .contentShape(Rectangle())
        .onTapGesture {
            DSHaptics.tap(.light)
            request.onDismiss()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(request.text)
        .accessibilityHint("Dismisses the tip")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(request.id)
    }

    /// How far the pointer shifts off the bubble's center to sit over the
    /// anchor, clamped so it never escapes the bubble's rounded corners.
    private func pointerOffset(anchorMidX: CGFloat, bubbleX: CGFloat) -> CGFloat {
        let limit = max(0, bubbleSize.width / 2 - 14 - pointerSize.width / 2)
        return min(max(anchorMidX - bubbleX, -limit), limit)
    }
}

/// The bubble's little speech pointer — an isosceles triangle with a softened
/// tip, drawn separately so it can slide along the bubble edge to track a
/// clamped anchor.
private struct DSTooltipPointer: Shape {
    let pointingDown: Bool

    func path(in rect: CGRect) -> Path {
        let tipY = pointingDown ? rect.maxY : rect.minY
        let baseY = pointingDown ? rect.minY : rect.maxY
        // The tip flattens 2pt short of the point and rounds across it.
        let shoulderY = tipY + (pointingDown ? -2 : 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: baseY))
        path.addLine(to: CGPoint(x: rect.midX - 2.5, y: shoulderY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX + 2.5, y: shoulderY),
            control: CGPoint(x: rect.midX, y: tipY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: baseY))
        path.closeSubpath()
        return path
    }
}
