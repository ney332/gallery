import RealityKit
import SwiftUI

@MainActor
final class OverviewOrbitController {
    private var camera: Entity?
    private let target = GalleryConfig.overviewCameraTarget
    private var yaw = GalleryConfig.overviewCameraYaw
    private var pitch = GalleryConfig.overviewCameraPitch
    private let radius = GalleryConfig.overviewCameraRadius
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
        yaw = yawAtDragStart + Float(translation.width) * sensitivity

        let minPitchOffset = Float(-5 * Double.pi / 180)
        let maxPitchOffset = Float(55 * Double.pi / 180)
        pitch = min(max(pitchAtDragStart - Float(translation.height) * sensitivity, minPitchOffset), maxPitchOffset)
        updateCamera()
    }

    func endDrag() {}

    func updateZoom(magnification: CGFloat) {
        guard let camera else { return }
        guard var component = camera.components[PerspectiveCameraComponent.self] else { return }
        if zoomAtDragStart == nil { zoomAtDragStart = component.fieldOfViewInDegrees }
        guard let zoomAtDragStart else { return }
        component.fieldOfViewInDegrees = min(max(zoomAtDragStart / Float(magnification), 25), 85)
        camera.components.set(component)
    }

    func endZoom() {
        zoomAtDragStart = nil
    }

    private func updateCamera() {
        guard let camera else { return }
        let horizontalRadius = radius * cos(pitch)
        let position = target + SIMD3<Float>(
            horizontalRadius * sin(yaw),
            radius * sin(pitch),
            horizontalRadius * cos(yaw)
        )
        camera.look(at: target, from: position, upVector: SIMD3<Float>(0, 1, 0), relativeTo: nil)
    }
}
