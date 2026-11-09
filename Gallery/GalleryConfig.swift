import Foundation
import CoreGraphics

enum GalleryConfig {
    static let minimumSupportedOS = "26.0"
    static let overviewCameraScale: Float = 3.8
    static let overviewMinScale: Float = 2.4
    static let overviewMaxScale: Float = 8.0
    static let overviewPitchRange: ClosedRange<Float> = 15...75
    static let overviewDamping: Float = 5.5
    static let overviewOrbitRadiansPerScreenWidth: Float = 2 * .pi
    // Blender camera pose converted from Z-up coordinates to RealityKit's Y-up coordinates.
    static let overviewCameraTarget = SIMD3<Float>(-0.8307, 1.5751, -0.4731)
    static let overviewCameraYaw: Float = -142.73296 * .pi / 180
    static let overviewCameraPitch: Float = 20 * .pi / 180
    static let overviewCameraRadius: Float = 2.0
    static let archiveBoxScale: Float = 0.12
    static let archiveSelectedScale: Float = 0.25
    static let showsArchiveBoxes = false
    static let archiveShelfPosition = SIMD3<Float>(-0.85, 0.05, 0.65)
    static let motionUpdateInterval: TimeInterval = 1.0 / 60.0
    static let shakeCooldown: TimeInterval = 1.2

    static func overviewCameraScale(for viewportSize: CGSize) -> Float {
        let aspectRatio = min(viewportSize.width, viewportSize.height) / max(viewportSize.width, viewportSize.height)
        let portraitMultiplier = Float(1 + (1 - aspectRatio) * 0.75)
        return overviewCameraScale * (aspectRatio < 1 ? min(portraitMultiplier, 1.55) : 1)
    }
}
