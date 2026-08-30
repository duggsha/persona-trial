import SwiftUI
#if os(iOS)
    import AVFoundation
    import PhotosUI
    import UIKit
    import UniformTypeIdentifiers
#endif

/// Photo capture for chat. The viewfinder is APPLE'S OWN camera UI —
/// `UIImagePickerController` with `sourceType: .camera`, hosted inside the
/// app — so the flash toggle, pinch zoom, tap-to-focus, HDR and the lens
/// selector all come from the system and keep pace with iOS, rather than
/// being re-implemented on a hand-rolled `AVCaptureSession` (which shipped
/// with none of them: one fixed wide-angle lens and a silent auto flash the
/// user could neither see nor override).
///
/// There is no API that hands off to Camera.app and gives the photo back —
/// this controller is as native as a hosted camera gets.
struct CameraSheet: View {
    let onDismiss: () -> Void
    var onCapture: (Data) -> Void = { _ in }

    var body: some View {
        #if os(iOS)
            CameraSheetIOS(onDismiss: onDismiss, onCapture: onCapture)
        #else
            ZStack {
                Color.black.ignoresSafeArea()
                Text("Camera is available on device.")
                    .foregroundStyle(.white)
            }
        #endif
    }

    #if os(iOS)
        /// Downscale to a bounded JPEG so the chat upload stays small and the
        /// mime type is always image/jpeg (what the backend tells the model).
        /// Shared by the capture flow and the attach menu's library pick.
        ///
        /// `nonisolated`, and it must stay that way: `View` conformance makes
        /// the enclosing type MainActor, and the paste path runs this on the
        /// pasteboard provider's own background queue — an inherited MainActor
        /// assumption there is a runtime isolation abort at the first draw
        /// (EXC_BREAKPOINT in dispatch_assert_queue, TF build 238 on device).
        nonisolated static func normalizedJPEG(_ image: UIImage, maxDimension: CGFloat = 1536, quality: CGFloat = 0.7) -> Data? {
            let size = image.size
            let scale = min(1, maxDimension / max(size.width, size.height))
            guard scale < 1 else { return image.jpegData(compressionQuality: quality) }
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            let resized = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
            return resized.jpegData(compressionQuality: quality)
        }
    #endif
}

#if os(iOS)
    private struct CameraSheetIOS: View {
        let onDismiss: () -> Void
        let onCapture: (Data) -> Void

        /// Whether the system viewfinder can be shown at all.
        private enum Access {
            /// Still deciding — the permission prompt may be up. Black, briefly.
            case checking
            case granted
            /// A hard no. Settings is the only way back.
            case denied
            /// No capture hardware — every simulator lands here.
            case noCamera
        }

        @State private var access: Access = .checking
        @State private var libraryItem: PhotosPickerItem?

        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                switch access {
                case .checking:
                    EmptyView()
                case .granted:
                    SystemCameraPicker(onCapture: finish, onDismiss: onDismiss)
                        .ignoresSafeArea()
                case .denied, .noCamera:
                    unavailable
                }
            }
            .preferredColorScheme(.dark)
            .task { resolveAccess() }
            .onChange(of: libraryItem) { _, item in loadFromLibrary(item) }
        }

        /// `.notDetermined` is deliberately not handed to the picker. Letting
        /// `UIImagePickerController` run the prompt itself leaves a black
        /// viewfinder with live shutter controls sitting behind a denial, so
        /// the prompt is resolved out here and a denial goes straight to the
        /// explanation.
        private func resolveAccess() {
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                access = .noCamera
                return
            }
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                access = .granted
            case .notDetermined:
                // The async form, never the completion handler. This closure
                // is written inside a main-actor View, so the compiler hands
                // @preconcurrency AVFoundation a main-actor-isolated closure
                // and inserts an isolation check that TRAPS the moment
                // AVFoundation calls it back on its own queue — the shape that
                // killed the photo viewer's Save and the ID-number OCR. The
                // inner main-queue hop does not save it; the outer closure is
                // what gets checked.
                Task { access = await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied }
            default:
                access = .denied
            }
        }

        private func finish(with data: Data) {
            onCapture(data)
            onDismiss()
        }

        /// The camera is unreachable — but this sheet is still the "add a
        /// picture" surface, so the library stays one tap away instead of
        /// making the user back out and find Photos in the attach menu. It is
        /// also the only way to stage a photo on a simulator.
        private var unavailable: some View {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: 0x101318), Color(hex: 0x020305)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 14) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.78))
                    Text(access == .denied ? "Camera access is off" : "No camera on this device")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.74))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 34)

                    PhotosPicker(selection: $libraryItem, matching: .images) {
                        CapsuleLabel(title: "Choose from Library", filled: true)
                    }
                    .buttonStyle(.plain)

                    if access == .denied {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            CapsuleLabel(title: "Open Settings", filled: false)
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack {
                    HStack {
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay { Circle().stroke(.white.opacity(0.18), lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    Spacer()
                }
            }
        }

        private func loadFromLibrary(_ item: PhotosPickerItem?) {
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let jpeg = CameraSheet.normalizedJPEG(image)
                else { return }
                finish(with: jpeg)
            }
        }
    }

    /// A view, not a method on the enclosing view: `PhotosPicker`'s label is a
    /// Sendable closure, so a MainActor-isolated builder can't be called from
    /// inside it (the same rule the old chrome's thumbnail worked around).
    private struct CapsuleLabel: View {
        let title: String
        let filled: Bool

        var body: some View {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(filled ? Color.black : Color.white.opacity(0.9))
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background {
                    Capsule().fill(filled ? AnyShapeStyle(Color.white.opacity(0.92)) : AnyShapeStyle(.ultraThinMaterial))
                }
                .overlay { Capsule().stroke(.white.opacity(filled ? 0 : 0.32), lineWidth: 1) }
        }
    }

    /// Apple's camera UI, hosted. Everything visible inside it — shutter,
    /// FLASH toggle, front/back flip, zoom, lens picker, tap-to-focus — is the
    /// system's own chrome, so nothing here configures it beyond pointing it
    /// at the camera and taking the result.
    private struct SystemCameraPicker: UIViewControllerRepresentable {
        let onCapture: (Data) -> Void
        let onDismiss: () -> Void

        func makeUIViewController(context: Context) -> UIImagePickerController {
            let picker = UIImagePickerController()
            // The caller gates on `isSourceTypeAvailable` before this view is
            // ever built — assigning an unavailable source type is a documented
            // exception, not a silent no-op.
            picker.sourceType = .camera
            picker.mediaTypes = [UTType.image.identifier]
            picker.cameraCaptureMode = .photo
            // Flash is left at the system default (`.auto`) on purpose: the
            // picker's own flash button both reflects and drives it, and
            // forcing a mode here would fight the control the user just got.
            picker.allowsEditing = false
            picker.delegate = context.coordinator
            return picker
        }

        func updateUIViewController(_: UIImagePickerController, context _: Context) {}

        func makeCoordinator() -> Coordinator {
            Coordinator(onCapture: onCapture, onDismiss: onDismiss)
        }

        @MainActor
        final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
            private let onCapture: (Data) -> Void
            private let onDismiss: () -> Void

            init(onCapture: @escaping (Data) -> Void, onDismiss: @escaping () -> Void) {
                self.onCapture = onCapture
                self.onDismiss = onDismiss
            }

            nonisolated func imagePickerController(
                _: UIImagePickerController,
                didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
            ) {
                // Encode out here, in the nonisolated context UIKit called us
                // on — `normalizedJPEG` is nonisolated precisely so it can run
                // off the main actor, and it means only Sendable `Data` has to
                // cross over. Neither `info` nor the `UIImage` is Sendable, so
                // capturing either one into the hop below is a compile error.
                let encoded = (info[.originalImage] as? UIImage).flatMap { CameraSheet.normalizedJPEG($0) }
                // UIKit delivers this on the main thread, so assume the
                // isolation rather than scheduling a hop the sheet would
                // outlive.
                MainActor.assumeIsolated {
                    // A shot we can't encode still closes the sheet — returning
                    // silently to a live viewfinder reads as a dead shutter.
                    guard let encoded else {
                        onDismiss()
                        return
                    }
                    onCapture(encoded)
                }
            }

            nonisolated func imagePickerControllerDidCancel(_: UIImagePickerController) {
                MainActor.assumeIsolated { onDismiss() }
            }
        }
    }
#endif
