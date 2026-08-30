import PersonaDesign
import PersonaService
import Photos
import SwiftUI
import UIKit

/// Renders a photo straight from the device photo library — the client half of
/// a `ph:<localIdentifier>` chat asset ref (search_photo_gallery matches on
/// device-indexed photos whose bytes never went to the server). The asset
/// path arrives as "/v1/assets/ph:<localIdentifier>"; anything else is a
/// normal remote asset and doesn't come through here.
struct PhotoLibraryImageView: View {
    let localIdentifier: String
    var targetSide: CGFloat = 512

    @State private var image: UIImage?
    @State private var missing = false

    /// "/v1/assets/ph:ABC…/L0/001" → "ABC…/L0/001". In the real app this is
    /// shared with the promoter that uploads these photos once they surface;
    /// that uploader is a backend path this trial doesn't carry.
    static func localIdentifier(fromAssetPath path: String) -> String? {
        guard let range = path.range(of: "/v1/assets/ph:") else { return nil }
        let id = String(path[range.upperBound...])
        return id.isEmpty ? nil : id
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if missing {
                // Deleted from the library since indexing (or access revoked).
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(DS.Palette.ink.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DS.Palette.card)
            } else {
                ShimmerTile()
            }
        }
        .task(id: localIdentifier) { await load() }
    }

    private func load() async {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = fetch.firstObject else {
            missing = true
            return
        }
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .opportunistic
        opts.resizeMode = .fast
        opts.isNetworkAccessAllowed = true
        let side = targetSide * UIScreen.main.scale
        image = await withCheckedContinuation { cont in
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: side, height: side),
                contentMode: .aspectFill,
                options: opts
            ) { img, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if let img, !resumed {
                    // Opportunistic delivery: paint the degraded thumb fast…
                    if degraded {
                        Task { @MainActor in if image == nil { image = img } }
                        return
                    }
                    resumed = true
                    cont.resume(returning: img)
                } else if !degraded, !resumed {
                    resumed = true
                    cont.resume(returning: nil)
                }
            }
        } ?? image
        if image == nil { missing = true }
    }
}
