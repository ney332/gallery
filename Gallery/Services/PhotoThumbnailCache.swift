import Photos
import UIKit

@MainActor
final class PhotoThumbnailCache {
    private let manager = PHCachingImageManager()
    private var cachedIdentifiers: Set<String> = []

    @MainActor
    private final class Request {
        var continuation: CheckedContinuation<UIImage?, Never>?
        var identifier: PHImageRequestID?
        var isFinished = false
        var timeoutTask: Task<Void, Never>?

        func finish(_ image: UIImage?) {
            guard !isFinished else { return }
            isFinished = true
            timeoutTask?.cancel()
            timeoutTask = nil
            continuation?.resume(returning: image)
            continuation = nil
        }
    }

    func thumbnail(
        for identifier: String,
        targetSize: CGSize,
        onImage: @escaping @MainActor @Sendable (UIImage) -> Void = { _ in }
    ) async -> UIImage? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = result.firstObject else { return nil }

        let request = Request()
        let manager = manager
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled, !request.isFinished else {
                    continuation.resume(returning: nil)
                    return
                }
                request.continuation = continuation
                let options = PHImageRequestOptions()
                // Show a cached preview immediately, then keep the request
                // alive for the final image at the requested pixel size.
                options.deliveryMode = .opportunistic
                options.resizeMode = .exact
                options.isNetworkAccessAllowed = true
                request.identifier = manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options) { @Sendable image, info in
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                    let failed = (info?[PHImageCancelledKey] as? Bool) == true
                        || info?[PHImageErrorKey] != nil
                    Task { @MainActor in
                        guard !request.isFinished else { return }
                        if let image { onImage(image) }
                        guard !isDegraded || failed else { return }
                        request.finish(failed ? nil : image)
                        if let identifier = request.identifier { manager.cancelImageRequest(identifier) }
                    }
                }
                request.timeoutTask = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(12)) } catch { return }
                    guard !request.isFinished else { return }
                    request.finish(nil)
                    if let identifier = request.identifier { manager.cancelImageRequest(identifier) }
                    print("Photo thumbnail request timed out; retry remains available")
                }
            }
        } onCancel: {
            Task { @MainActor in
                if let identifier = request.identifier { manager.cancelImageRequest(identifier) }
                request.finish(nil)
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
