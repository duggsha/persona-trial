import UIKit

/// A pasted image lands in the composer as a PICTURE, not as its filename.
///
/// The bar's field is a plain-text `UITextView` (SwiftUI's
/// `TextField(axis: .vertical)`), and plain text is all it can take. Copy a
/// photo in Messages — whose clipboard item carries the image AND a text
/// representation of the file — and the field takes the only part it
/// understands: the name. So "paste" typed `IMG_4213.HEIC` into the bar and
/// the picture stayed on the clipboard ("if I paste from
/// the clipboard it should be pasting the full image").
///
/// The fix is UIKit's own hook for exactly this. `UITextPasteDelegate` runs
/// every pasteboard item through `transform` before the field commits it, so
/// an item that can load a `UIImage` is taken OUT of the text (`setNoResult`)
/// and handed to the composer's photo staging instead — the same tile the
/// camera and the library picker fill, and the same send path. Anything else
/// pastes exactly as it always did (`setDefaultResult`).
///
/// Only hosts that can actually stage a photo install this (the handler is
/// optional on `PersonaComposer`): a text-only composer swallowing the image
/// and showing nothing would be worse than the filename.
enum ComposerImagePaste {
    /// Point the live focused field at `onImage` for pasted pictures.
    ///
    /// Idempotent and cheap, because it has to be called more than once: the
    /// backing text view is SwiftUI's, created on focus and replaced whenever
    /// it feels like it, so the composer re-asserts this on every focus and
    /// again each time it summons the edit menu (the pill Paste is tapped on).
    /// A field that isn't a text view — or no responder at all — is a no-op.
    @MainActor
    static func install(onImage: @escaping (Data) -> Void) {
        guard let field = PersonaFirstResponder.current() as? UITextView else { return }
        ComposerImagePasteDelegate.shared.onImage = onImage
        field.pasteDelegate = ComposerImagePasteDelegate.shared
        // The delegate only ever sees items the field ACCEPTS, and a plain
        // text view accepts none of the image types: an image-only clipboard
        // (a screenshot, Photos' own Copy) doesn't even light Paste up in the
        // menu. Widening the configuration to images ON TOP of the text types
        // is what puts those items in front of `transform` at all — which
        // representation UIKit would have preferred doesn't matter, since the
        // transform reads the item's provider itself.
        field.pasteConfiguration = imageAndTextPasteConfiguration
        field.allowsEditingTextAttributes = isClipboardImageOnly
    }

    /// Whether the clipboard holds a picture and NOTHING the field would take
    /// as text — a screenshot, Photos' own Copy.
    ///
    /// This is the one case the transform above can't rescue on its own:
    /// UIKit decides whether "Paste" appears at all from what the field can
    /// accept, and a plain-text view accepts no image, so the menu came up
    /// without a Paste command and there was nothing to intercept.
    /// `allowsEditingTextAttributes` is what makes a text view admit images —
    /// so it is turned on for exactly that clipboard and left off for every
    /// other, because it would ALSO let styled text paste in with the source's
    /// fonts and colors, and the composer is plain text. The image never
    /// reaches the document either way: the transform takes it out first.
    ///
    /// (Checked at install, which runs on focus and again as the edit menu is
    /// summoned — the last moment before Paste is on screen. `hasImages` /
    /// `hasStrings` are content DETECTION, so none of this reads the clipboard
    /// or trips the "Allow Paste?" alert.)
    @MainActor
    private static var isClipboardImageOnly: Bool {
        let pasteboard = UIPasteboard.general
        return pasteboard.hasImages && !pasteboard.hasStrings && !pasteboard.hasURLs
    }

    @MainActor
    private static let imageAndTextPasteConfiguration: UIPasteConfiguration = {
        let configuration = UIPasteConfiguration(forAccepting: UIImage.self)
        configuration.addTypeIdentifiers(forAccepting: NSAttributedString.self)
        configuration.addTypeIdentifiers(forAccepting: NSString.self)
        configuration.addTypeIdentifiers(forAccepting: NSURL.self)
        return configuration
    }()
}

/// Stateless but for the one handler, so the shared instance is safe: exactly
/// one composer field is first responder at a time, and `install` re-points
/// the handler at whichever one that is.
private final class ComposerImagePasteDelegate: NSObject, UITextPasteDelegate {
    @MainActor static let shared = ComposerImagePasteDelegate()
    @MainActor var onImage: ((Data) -> Void)?

    func textPasteConfigurationSupporting(
        _: UITextPasteConfigurationSupporting,
        transform item: UITextPasteItem
    ) {
        let provider = item.itemProvider
        guard onImage != nil, provider.canLoadObject(ofClass: UIImage.self) else {
            item.setDefaultResult()
            return
        }
        // Nothing goes into the text — the picture IS the paste. The load is
        // asynchronous (the item can be a file the provider still has to
        // read), and UIKit is explicit that a result may be set either way, so
        // the field commits an empty paste now and the tile appears when the
        // bytes arrive.
        //
        // @Sendable is load-bearing. This completion runs on the provider's
        // own background queue for a FILE-BACKED item — which is what Messages
        // puts on the clipboard — while an in-memory item (any same-process
        // copy, and the original smoke's seeded pasteboard) completes on the
        // main thread. Without the annotation the closure silently inherits
        // the delegate method's MainActor isolation, and the runtime kills the
        // app at the first isolation check on the background hop. That was the
        // a buildpaste crash (build 238): green in every Debug smoke,
        // dead on a real Messages paste.
        item.setNoResult()
        provider.loadObject(ofClass: UIImage.self) { @Sendable object, _ in
            // Downscale off the main thread, through the same normalizer the
            // camera and the picker use, so a 12-megapixel paste stages at the
            // size the backend actually accepts.
            guard let image = object as? UIImage,
                  let data = CameraSheet.normalizedJPEG(image)
            else { return }
            Task { @MainActor in ComposerImagePasteDelegate.shared.onImage?(data) }
        }
    }
}
