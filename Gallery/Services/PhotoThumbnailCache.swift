import Photos
import UIKit

@MainActor
final class PhotoThumbnailCache {
    private let manager = PHCachingImageManager()
    private var cachedIdentifiers: Set<String> = []

    func thumbnail(for identifier: String, targetSize: CGSize) async -> UIImage? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = result.firstObject else { return nil }

        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                continuation.resume(returning: image)
            }
        }
    }

    func startCaching(identifiers: [String], targetSize: CGSize) {
        let ids = identifiers.filter { !cachedIdentifiers.contains($0) }
        guard !ids.isEmpty else { return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        manager.startCachingImages(for: assets.objects(at: IndexSet(integersIn: 0..<assets.count)), targetSize: targetSize, contentMode: .aspectFill, options: nil)
        cachedIdentifiers.formUnion(ids)
    }

    func stopCaching(identifiers: [String], targetSize: CGSize) {
        let ids = identifiers.filter(cachedIdentifiers.contains)
        guard !ids.isEmpty else { return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        manager.stopCachingImages(for: assets.objects(at: IndexSet(integersIn: 0..<assets.count)), targetSize: targetSize, contentMode: .aspectFill, options: nil)
        cachedIdentifiers.subtract(ids)
    }

    func stopAllCaching() {
        manager.stopCachingImagesForAllAssets()
        cachedIdentifiers.removeAll()
    }
}
