import PersonaCore
import PersonaDesign
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// Full-screen reader for a VERY long message. "Read more" on a bubble past
/// the reader threshold opens this instead of expanding inline — a multi-screen
/// expansion inside the transcript's LazyVStack lays out, hit-tests, and
/// composites the whole thing on every scroll frame, which is exactly the lag
/// Read-more's preview cut exists to avoid (see ChatBubbleContent.collapse).
///
/// The text renders through the SAME pipeline as the bubble (markdown blocks,
/// GFM tables, linkified URLs) but sliced into paragraph chunks in a LazyVStack,
/// so layout stays incremental no matter how long the message is. Chrome: a
/// Copy pill and a close button, floating over the shared app canvas.
struct ChatMessageReader: View {
    let message: ChatMessage

    @Environment(\.dismiss) private var dismiss
    /// Brief "Copied" confirmation on the pill after a copy.
    @State private var copied = false

    var body: some View {
        ZStack(alignment: .top) {
            SharedAppBackground().ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(chunks) { chunk in
                        chunkView(chunk)
                            // A blank line separated this chunk from the one
                            // above (22pt line pitch ≈ one empty line); a hard
                            // split inside a paragraph only restores the line
                            // spacing the Text seam dropped.
                            .padding(.top, chunk.id == 0 ? 0 : (chunk.newParagraph ? 22 : 1.7))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Spacing.gutter)
                .padding(.top, 78)
                .padding(.bottom, 40)
            }

            header
        }
        // NO identifier on this container: SwiftUI stamps a container's
        // identifier onto EVERY descendant accessibility element, which
        // overwrites the buttons' own identifiers (found the hard way — the
        // Copy/close buttons all reported 'message-reader'). UI tests key off
        // "message-reader-copy" / "message-reader-close" instead.
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            Button(action: copyAll) {
                HStack(spacing: 6) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                    Text(copied ? String(localized: "Copied") : String(localized: "Copy"))
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(DS.Palette.ink)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .background(DS.Palette.card.opacity(0.35), in: Capsule())
            .personaGlass(in: Capsule(), interactive: true)
            .accessibilityIdentifier("message-reader-copy")

            Spacer(minLength: 0)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.Palette.ink)
                    .frame(width: 34, height: 34)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background(DS.Palette.card.opacity(0.35), in: Circle())
            .personaGlass(in: Circle(), interactive: true)
            .accessibilityIdentifier("message-reader-close")
        }
        .padding(.horizontal, DS.Spacing.gutter)
        .padding(.top, 12)
        .background(alignment: .top) {
            // Scroll-under legibility, same treatment as the app's headers.
            TopHeaderBackdrop()
                .frame(height: 90)
                .ignoresSafeArea(edges: .top)
        }
    }

    private func copyAll() {
        #if canImport(UIKit)
            UIPasteboard.general.string = message.text
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        withAnimation(.snappy(duration: 0.18)) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.easeOut(duration: 0.25)) { copied = false }
        }
    }

    // MARK: Content

    /// One lazily-rendered slice of the message: a run of lines, or a GFM table
    /// (tables come out of `markdownBlocks` whole, so they never split).
    private struct ReaderChunk: Identifiable {
        let id: Int
        /// Whether a blank line preceded this chunk in the original text.
        let newParagraph: Bool
        enum Kind {
            case text(String)
            case table(header: [String], rows: [[String]])
        }
        let kind: Kind
    }

    @ViewBuilder
    private func chunkView(_ chunk: ReaderChunk) -> some View {
        switch chunk.kind {
        case let .text(text):
            Text(message.isUser
                ? ChatBubbleContent.linkified(text, isUser: false)
                : ChatBubbleContent.markdownRendered(text))
                .font(.system(size: 17, weight: .regular))
                .lineSpacing(22 - 20.29) // the bubble's iMessage line pitch
                .foregroundStyle(DS.Palette.ink)
                .tint(Color(light: 0x097FFF, dark: 0x409CFF))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        case let .table(header, rows):
            MarkdownTableView(header: header, rows: rows)
        }
    }

    /// Target size of one text chunk. Big enough that a chunk is cheap to
    /// enumerate, small enough that any single chunk lays out instantly.
    private static let chunkChars = 2400
    private static let chunkLines = 48

    private var chunks: [ReaderChunk] {
        var out: [ReaderChunk] = []
        var newParagraph = false
        func appendText(_ text: String) {
            var buf: [String] = []
            var bufChars = 0
            func flush(nextStartsParagraph: Bool) {
                // Trailing blank lines are dropped — the NEXT chunk's top
                // padding is the paragraph gap.
                while buf.last?.isEmpty == true { buf.removeLast() }
                let joined = buf.joined(separator: "\n")
                if !joined.isEmpty {
                    out.append(ReaderChunk(id: out.count, newParagraph: newParagraph, kind: .text(joined)))
                    newParagraph = nextStartsParagraph
                }
                buf = []
                bufChars = 0
            }
            for line in text.components(separatedBy: "\n") {
                let full = buf.count >= Self.chunkLines || bufChars >= Self.chunkChars
                if full, line.isEmpty {
                    // Preferred split: at a paragraph boundary.
                    flush(nextStartsParagraph: true)
                    continue
                }
                if buf.count >= Self.chunkLines * 2 || bufChars >= Self.chunkChars * 2 {
                    // No blank line in sight — split mid-paragraph rather than
                    // let one wall of text grow unbounded.
                    flush(nextStartsParagraph: false)
                }
                buf.append(line)
                bufChars += line.count + 1
            }
            flush(nextStartsParagraph: true)
        }
        if message.isUser {
            // User text is never reinterpreted as markdown (bubble rule).
            appendText(message.text)
        } else {
            for block in ChatBubbleContent.markdownBlocks(message.text) {
                switch block {
                case let .text(text):
                    appendText(text)
                case let .table(header, rows):
                    out.append(ReaderChunk(
                        id: out.count,
                        newParagraph: true,
                        kind: .table(header: header, rows: rows)
                    ))
                    newParagraph = true
                }
            }
        }
        return out
    }
}
