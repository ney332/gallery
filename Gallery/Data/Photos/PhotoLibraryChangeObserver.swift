import Photos
import Foundation

@MainActor
final class PhotoLibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
    private nonisolated let onChange: @Sendable () -> Void

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    // PhotoKit invokes this Objective-C delegate on PHChange-queue. It must
    // not inherit the project's default MainActor isolation. The Sendable
    // callback schedules the model refresh on MainActor without passing PHChange.
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange()
    }

    func stopObserving() {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
}
