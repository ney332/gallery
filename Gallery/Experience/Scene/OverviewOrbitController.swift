import RealityKit
import SwiftUI

@MainActor
final class OverviewOrbitController {
    private var camera: Entity?
    private let moveCamera = MoveCamera()
    private var target = GalleryConfig.overviewCameraTarget
    private var yawCenter = GalleryConfig.overviewCameraYaw
    private var yaw = GalleryConfig.overviewCameraYaw
    private var pitch = GalleryConfig.overviewCameraPitch
    private var radius = GalleryConfig.overviewCameraRadius
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
    private var savedOrbitState: OrbitState?

    private struct OrbitState {
        let target: SIMD3<Float>
        let yawCenter: Float
        let yaw: Float
        let pitch: Float
        let radius: Float
    }

    func attach(camera: Entity, viewportSize: CGSize) {
        self.camera = camera
        self.viewportSize = viewportSize
        moveCamera.attach(camera: camera)
        updateCamera()
    }

    func toggleFocus(on shelf: Entity) {
        if savedOrbitState != nil {
            restorePreviousView()
            return
        }
        guard let camera else { return }

        savedOrbitState = OrbitState(
            target: target,
            yawCenter: yawCenter,
            yaw: yaw,
            pitch: pitch,
            radius: radius
        )

        let bounds = shelf.visualBounds(relativeTo: nil)
        let shelfCenter = bounds.center
        let shelfHeight = max(bounds.extents.y, 0.5)
        let fieldOfView = camera.components[PerspectiveCameraComponent.self]?.fieldOfViewInDegrees
            ?? GalleryConfig.overviewCameraFieldOfView
        let fieldOfViewRadians = fieldOfView * .pi / 180
        let framingDistance = shelfHeight / (2 * tan(fieldOfViewRadians / 2)) * 1.08
        let focusPitch = Float(20 * Double.pi / 180)
        let focusRadius = max(framingDistance, 1.6)
        let horizontalRadius = focusRadius * cos(focusPitch)

        // The shelf is against the room's right wall; its front faces the room (-X).
        let requestedPosition = shelfCenter + SIMD3<Float>(
            -horizontalRadius,
            focusRadius * sin(focusPitch),
            0
        )
        let position = keepCameraOutsideWallShell(requestedPosition)

        target = shelfCenter
        radius = simd_distance(position, target)
        yaw = atan2(position.x - target.x, position.z - target.z)
        yawCenter = yaw
        pitch = atan2(
            position.y - target.y,
            simd_length(SIMD2(position.x - target.x, position.z - target.z))
        )

        moveCamera.move(to: position, lookingAt: shelfCenter)
    }

    private func restorePreviousView() {
        guard camera != nil, let savedOrbitState else { return }
        target = savedOrbitState.target
        yawCenter = savedOrbitState.yawCenter
        yaw = savedOrbitState.yaw
        pitch = savedOrbitState.pitch
        radius = savedOrbitState.radius
        self.savedOrbitState = nil

        let position = keepCameraOutsideWallShell(requestedCameraPosition())
        moveCamera.move(to: position, lookingAt: position + cameraForward())
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
        let position = keepCameraOutsideWallShell(requestedCameraPosition())
        camera.look(
            at: position + cameraForward(),
            from: position,
            upVector: SIMD3<Float>(0, 1, 0),
            relativeTo: nil
        )
    }

    private func requestedCameraPosition() -> SIMD3<Float> {
        let horizontalRadius = radius * cos(pitch)
        return target + SIMD3<Float>(
            horizontalRadius * sin(yaw),
            radius * sin(pitch),
            horizontalRadius * cos(yaw)
        )
    }

    private func cameraForward() -> SIMD3<Float> {
        SIMD3<Float>(
            -cos(pitch) * sin(yaw),
            -sin(pitch),
            -cos(pitch) * cos(yaw)
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
