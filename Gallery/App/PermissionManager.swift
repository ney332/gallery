import Photos

@MainActor
final class PermissionManager {
    func requestPhotoLibraryAccess() async -> PhotoLibraryAccess {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let status: PHAuthorizationStatus
        if current == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        } else {
            status = current
        }

        return switch status {
        case .authorized: PhotoLibraryAccess.authorized
        case .limited: PhotoLibraryAccess.limited
        case .denied: PhotoLibraryAccess.denied
        case .restricted: PhotoLibraryAccess.restricted
        case .notDetermined: PhotoLibraryAccess.notDetermined
        @unknown default: PhotoLibraryAccess.restricted
        }
    }
}
