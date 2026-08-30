import PersonaCore
import PersonaDesign
import PersonaService
import PhotosUI
// Explicit: `.quickLookPreview` used to reach this file from PersonaRootView's
// import, and that file is not part of this trial.
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// What a composer has staged for its next send — the photos and the one
/// document — plus the picker presentation it drives.
///
/// This exists because the wiring is identical on every chat surface and was
/// present on exactly one of them: the main chat owns a bespoke version (it
/// also folds long pastes into attachments and hops pages), and every OTHER
/// host inherited `PersonaComposer`'s no-op handlers, so the + menu offered
/// Camera / Photos / Files and swallowed every tap. A host now holds one of
/// these, hands its values to the composer, and applies
/// `.composerAttachments(_:)` — eleven lines instead of sixty, with the cap,
/// the normalization and the preview living in ONE place.
@MainActor
@Observable
final class ComposerAttachmentStaging {
    /// The most photos one send can carry — the backend's per-turn inline-image
    /// cap (`imageDatas` accepts at most 5).
    static let maxImages = 5

    private(set) var images: [Data] = []
    var file: ChatFileAttachment?

    /// Picker presentation, driven by the menu handlers below and consumed by
    /// the `.composerAttachments(_:)` modifier.
    var showingCamera = false
    var showingLibrary = false
    var showingFiles = false
    var pickerItems: [PhotosPickerItem] = []
    /// The staged document open in QuickLook (tap on its tile).
    var previewURL: URL?

    var isEmpty: Bool { images.isEmpty && file == nil }

    /// How many more photos this turn can take — what the library picker is
    /// allowed to select.
    var remainingImageSlots: Int { max(1, Self.maxImages - images.count) }

    // MARK: Menu handlers (handed straight to PersonaComposer)

    func openCamera() { showingCamera = true }
    func openLibrary() { showingLibrary = true }
    func openFiles() { showingFiles = true }

    /// Stage a photo, dropping anything past the cap — every entry point
    /// (camera, library, paste) funnels through here so the limit lives in one
    /// place.
    func stage(_ data: Data) {
        guard images.count < Self.maxImages else { return }
        images.append(data)
    }

    /// A picture pasted into the bar (see `ComposerImagePaste`), staged with
    /// the main chat's feedback: the tile animates in, and the light tap fires
    /// only if it actually landed — a paste past the cap is dropped, and a
    /// haptic for nothing reads as something that happened.
    func stagePasted(_ data: Data) {
        let before = images.count
        withAnimation(.snappy(duration: 0.2)) { stage(data) }
        guard images.count > before else { return }
        DSHaptics.tap(.light)
    }

    func removeImage(at index: Int) {
        guard images.indices.contains(index) else { return }
        images.remove(at: index)
    }

    func clearFile() { file = nil }

    /// Tap on the staged document tile: open it in QuickLook, so what is about
    /// to be sent is never a mystery blob.
    func previewFile() {
        guard let file else { return }
        DSHaptics.tap(.light)
        previewURL = Self.tempFileURL(for: file.filename, data: file.data)
    }

    /// Stage bytes as a real file with a real name, which is what QuickLook
    /// needs for its title. Lifted verbatim from `ChatScreen.tempFileURL` —
    /// the chat screen isn't part of this trial.
    static func tempFileURL(for filename: String, data: Data) -> URL? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("user-attachments", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(filename.isEmpty ? "file" : filename)
        do {
            try data.write(to: dest, options: .atomic)
            return dest
        } catch {
            return nil
        }
    }

    /// Consume everything staged, clearing the composer — a send takes the
    /// attachments with it exactly once.
    @discardableResult
    func take() -> (images: [Data], file: ChatFileAttachment?) {
        let taken = (images, file)
        images = []
        file = nil
        return taken
    }
}

extension View {
    /// Installs the three pickers (camera, photo library, document) and the
    /// staged-document preview behind a `ComposerAttachmentStaging`. Pair it
    /// with a `PersonaComposer` reading the same object; `onStaged` fires after
    /// something lands (hosts use it to take focus back from the picker).
    func composerAttachments(
        _ staging: ComposerAttachmentStaging,
        onStaged: @escaping () -> Void = {}
    ) -> some View {
        modifier(ComposerAttachmentsModifier(staging: staging, onStaged: onStaged))
    }
}

private struct ComposerAttachmentsModifier: ViewModifier {
    @Bindable var staging: ComposerAttachmentStaging
    let onStaged: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $staging.showingCamera) {
                CameraSheet(
                    onDismiss: { staging.showingCamera = false },
                    onCapture: { data in
                        staging.stage(data)
                        onStaged()
                    }
                )
            }
            // Up to 5 photos per send, so the picker only offers the slots
            // still open.
            .photosPicker(
                isPresented: $staging.showingLibrary,
                selection: $staging.pickerItems,
                maxSelectionCount: staging.remainingImageSlots,
                matching: .images
            )
            .onChange(of: staging.pickerItems) { _, items in
                guard !items.isEmpty else { return }
                staging.pickerItems = []
                Task {
                    for item in items {
                        guard let data = try? await item.loadTransferable(type: Data.self),
                              let image = UIImage(data: data),
                              let normalized = CameraSheet.normalizedJPEG(image)
                        else { continue }
                        staging.stage(normalized)
                    }
                    guard !staging.images.isEmpty else { return }
                    onStaged()
                }
            }
            .fileImporter(
                isPresented: $staging.showingFiles,
                allowedContentTypes: [.pdf, .plainText, .commaSeparatedText, .json, .image],
                allowsMultipleSelection: false
            ) { result in
                guard case let .success(urls) = result, let url = urls.first else { return }
                let secured = url.startAccessingSecurityScopedResource()
                defer { if secured { url.stopAccessingSecurityScopedResource() } }
                // 8 MB: the same ceiling the main chat's importer holds the
                // inline-upload budget to.
                guard let data = try? Data(contentsOf: url), data.count <= 8 * 1024 * 1024 else { return }
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                staging.file = ChatFileAttachment(filename: url.lastPathComponent, mimeType: mime, data: data)
                onStaged()
            }
            .quickLookPreview($staging.previewURL)
    }
}
