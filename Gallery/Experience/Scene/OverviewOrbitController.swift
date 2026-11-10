import RealityKit
import SwiftUI

@MainActor
final class OverviewOrbitController {
    private var camera: Entity?
    private let target = GalleryConfig.overviewCameraTarget
    private let yawCenter = GalleryConfig.overviewCameraYaw
    private var yaw = GalleryConfig.overviewCameraYaw
    private var pitch = GalleryConfig.overviewCameraPitch
    private let radius = GalleryConfig.overviewCameraRadius
    // Inner faces measured from the closed Paredes shell in BaseCenario.usdz.
    private let roomLeftWallX: Float = -1.979
    private let roomRightWallX: Float = 2.013
    private let roomBackWallZ: Float = 2.024
    private let roomFrontWallZ: Float = -2.024
    private let wallClearance: Float = 0.015
    private let roomFloorY: Float = 0.02
    private let ceilingFootprintHalfWidth: Float = 2.20
    private let ceilingFrontEdgeZ: Float = -2.20
    private let ceilingBackEdgeZ: Float = 2.20
    // The ceiling mesh starts at Y ~= 2.99 m; retain clearance beneath it.
    private let roomCeilingY: Float = 2.78
    private var yawAtDragStart: Float = 0
    private var pitchAtDragStart: Float = 0
    private var zoomAtDragStart: Float?
    private var viewportSize: CGSize = .zero

    func attach(camera: Entity, viewportSize: CGSize) {
        self.camera = camera
        self.viewportSize = viewportSize
        updateCamera()
    }

    func updateViewport(_ size: CGSize) {
        viewportSize = size
    }

    func beginDrag() {
        yawAtDragStart = yaw
        pitchAtDragStart = pitch
    }

    func updateDrag(translation: CGSize) {
        let sensitivity = viewportSize.width > 0
            ? 2 * Float.pi / Float(viewportSize.width)
            : 0.01

        let yawOffset = Float(translation.width) * sensitivity
        let maximumYawOffset: Float = .pi / 2
        yaw = min(
            max(yawAtDragStart + yawOffset, yawCenter - maximumYawOffset),
            yawCenter + maximumYawOffset
        )

        // Keep the camera looking down enough that the top edge of the
        // vertical frustum does not point into the ceiling.
        let minPitch = Float(20 * Double.pi / 180)
        let maxPitch = Float(75 * Double.pi / 180)
        pitch = min(max(pitchAtDragStart - Float(translation.height) * sensitivity, minPitch), maxPitch)
        updateCamera()
    }

    func endDrag() {}

    func updateZoom(magnification: CGFloat) {
        guard let camera else { return }
        guard var component = camera.components[PerspectiveCameraComponent.self] else { return }
        if zoomAtDragStart == nil { zoomAtDragStart = component.fieldOfViewInDegrees }
        guard let zoomAtDragStart else { return }
        component.fieldOfViewInDegrees = min(
            max(zoomAtDragStart / Float(magnification), 20),
            GalleryConfig.overviewCameraFieldOfView
        )
        camera.components.set(component)
    }

    func endZoom() {
        zoomAtDragStart = nil
    }

    private func updateCamera() {
        guard let camera else { return }
        let horizontalRadius = radius * cos(pitch)
        let requestedPosition = target + SIMD3<Float>(
            horizontalRadius * sin(yaw),
            radius * sin(pitch),
            horizontalRadius * cos(yaw)
        )
        let position = keepCameraOutsideWallShell(requestedPosition)
        let forward = SIMD3<Float>(
            -cos(pitch) * sin(yaw),
            -sin(pitch),
            -cos(pitch) * cos(yaw)
        )
        camera.look(
            at: position + forward,
            from: position,
            upVector: SIMD3<Float>(0, 1, 0),
            relativeTo: nil
        )
    }

    private func keepCameraOutsideWallShell(_ position: SIMD3<Float>) -> SIMD3<Float> {
        var safe = position
        safe.x = min(
            max(safe.x, roomLeftWallX + wallClearance),
            roomRightWallX - wallClearance
        )
        safe.z = min(
            max(safe.z, roomFrontWallZ + wallClearance),
            roomBackWallZ - wallClearance
        )
        safe.y = min(max(safe.y, roomFloorY), roomCeilingY)
        return safe
    }
}
