import Foundation

enum GalleryConfig {
    static let albumCoverWidth: Float = 0.285
    static let albumPageHeight: Float = 0.36
    static let albumPageTurnDuration: TimeInterval = 0.65
    static let albumCoverOpenDuration: TimeInterval = 0.8
    static let albumViewingDistance: Float = 0.55
    static let albumTravelDuration: TimeInterval = 0.75
    static let albumExtractionDuration: TimeInterval = 0.45
    static let albumDragWidthFraction: CGFloat = 0.55
    static let albumTurnCommitProgress: Float = 0.4
    static let albumPageTextureWidth: CGFloat = 2048
    static let albumPhotoTargetSize = CGSize(width: 1200, height: 1600)
    static let minimumSupportedOS = "26.0"
    // Vertical field of view stays bounded in portrait, preventing the upper
    // edge of the image from looking through the nearby ceiling geometry.
    static let overviewCameraFieldOfView: Float = 45.2
    // Blender Z-up camera location converted to RealityKit's Y-up coordinates.
    static let overviewCameraPosition = SIMD3<Float>(-1.9687666, 2.2591279, -1.9687669)
    // Orbit target converted from Blender Z-up coordinates to RealityKit's Y-up coordinates.
    static let overviewCameraTarget = SIMD3<Float>(-0.7047, 1.5751, -0.5780)
    static let overviewCameraYaw: Float = -137.73296 * .pi / 180
    static let overviewCameraPitch: Float = 20 * .pi / 180
    static let overviewCameraRadius: Float = 2.0
    static let archiveBoxScale: Float = 0.12
    static let archiveSelectedScale: Float = 0.25
    static let showsArchiveBoxes = false
    static let archiveShelfPosition = SIMD3<Float>(-0.85, 0.05, 0.65)
    static let motionUpdateInterval: TimeInterval = 1.0 / 60.0
    static let shakeCooldown: TimeInterval = 1.2
}
