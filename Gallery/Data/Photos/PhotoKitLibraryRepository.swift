@preconcurrency import Photos

actor PhotoKitLibraryRepository: PhotoLibraryRepository {
    func requestReadAccess() async -> PhotoLibraryAccess {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let status = current == .notDetermined
            ? await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            : current

        return switch status {
        case .authorized: .authorized
        case .limited: .limited
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .restricted
        }
    }

    func fetchPhotos() async throws -> [PhotoReference] {
        let result = PHAsset.fetchAssets(with: .image, options: nil)
        return references(from: result)
    }

    func fetchFavorites() async throws -> [PhotoReference] {
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumFavorites,
            options: nil
        )
        guard let favorites = collections.firstObject else { return [] }
        return references(from: PHAsset.fetchAssets(in: favorites, options: nil))
    }

    func photoExists(id: String) async -> Bool {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).count > 0
    }

    private func references(from assets: PHFetchResult<PHAsset>) -> [PhotoReference] {
        var result: [PhotoReference] = []
        result.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            guard !asset.mediaSubtypes.contains(.photoScreenshot) else { return }
            result.append(PhotoReference(
                id: asset.localIdentifier,
                creationDate: asset.creationDate,
                isFavorite: asset.isFavorite
            ))
        }
        return result
    }
}
