@preconcurrency import Photos
import Foundation

final class PhotoLibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    private let onChange: @Sendable () -> Void

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange()
    }

    func stopObserving() {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
}
