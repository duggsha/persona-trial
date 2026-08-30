import SwiftUI

/// Records a view's on-screen (window) frame so chrome that positions
/// window-level overlays can anchor to it — the composer's attach bloom menu
/// anchors to the + button's frame this way.
struct WindowFrameCapture: ViewModifier {
    @Binding var rect: CGRect

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { rect = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, new in rect = new }
            }
        )
    }
}

extension View {
    /// Continuously publish this view's window-space frame into `rect`.
    func captureWindowFrame(into rect: Binding<CGRect>) -> some View {
        modifier(WindowFrameCapture(rect: rect))
    }
}
