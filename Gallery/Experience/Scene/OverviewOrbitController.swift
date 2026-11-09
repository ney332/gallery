import RealityKit
import SwiftUI

@MainActor
final class OverviewOrbitController {
    private(set) var camera: Entity?
    private var target = GalleryConfig.overviewCameraTarget
    private var yaw: Float = GalleryConfig.overviewCameraYaw
    private var pitch: Float = GalleryConfig.overviewCameraPitch
    private var radius: Float = GalleryConfig.overviewCameraRadius
    private var yawOrigin: Float = 0
    private var pitchOrigin: Float = 0
    private var zoomOrigin: Float?
    private var viewportSize: CGSize = .zero
    private var yawVelocity: Float = 0
    private var pitchVelocity: Float = 0
    private var inertiaTask: Task<Void, Never>?

    func attach(camera: Entity, viewportSize: CGSize) {
        self.camera = camera
        self.viewportSize = viewportSize
        updateCamera()
    }

    func updateViewport(_ size: CGSize) {
        guard size != viewportSize else { return }
        viewportSize = size
        setCameraScale(GalleryConfig.overviewCameraScale(for: size))
    }

    func beginDrag() {
        inertiaTask?.cancel()
        yawVelocity = 0
        pitchVelocity = 0
        yawOrigin = yaw
        pitchOrigin = pitch
    }

    func updateDrag(translation: CGSize) {
        let sensitivity = orbitSensitivity
        yaw = yawOrigin - Float(translation.width) * sensitivity
        let range = GalleryConfig.overviewPitchRange
        let lower = range.lowerBound * .pi / 180
        let upper = range.upperBound * .pi / 180
        pitch = min(max(pitchOrigin + Float(translation.height) * sensitivity, lower), upper)
        updateCamera()
    }

    func endDrag(velocity: CGSize) {
        let sensitivity = orbitSensitivity
        yawVelocity = -Float(velocity.width) * sensitivity
        pitchVelocity = Float(velocity.height) * sensitivity
        startInertia()
    }

    func updateZoom(magnification: CGFloat) {
        if zoomOrigin == nil { zoomOrigin = cameraScale }
        guard let zoomOrigin else { return }
        setCameraScale(zoomOrigin / max(Float(magnification), 0.1))
    }

    func endZoom() {
        zoomOrigin = nil
    }

    private var cameraScale: Float {
        camera?.components[OrthographicCameraComponent.self]?.scale ?? GalleryConfig.overviewCameraScale
    }

    private var orbitSensitivity: Float {
        guard viewportSize.width > 0 else { return GalleryConfig.overviewOrbitRadiansPerScreenWidth }
        return GalleryConfig.overviewOrbitRadiansPerScreenWidth / Float(viewportSize.width)
    }

    private func setCameraScale(_ scale: Float) {
        guard let camera, var component = camera.components[OrthographicCameraComponent.self] else { return }
        component.scale = min(max(scale, GalleryConfig.overviewMinScale), GalleryConfig.overviewMaxScale)
        camera.components.set(component)
    }

    private func startInertia() {
        inertiaTask?.cancel()
        inertiaTask = Task { [weak self] in
            guard let self else { return }
            let dt: Float = 1.0 / 60.0
            while !Task.isCancelled && (abs(yawVelocity) > 0.0005 || abs(pitchVelocity) > 0.0005) {
                yaw += yawVelocity * dt
                let minPitch = GalleryConfig.overviewPitchRange.lowerBound * .pi / 180
                let maxPitch = GalleryConfig.overviewPitchRange.upperBound * .pi / 180
                pitch = min(max(pitch + pitchVelocity * dt, minPitch), maxPitch)
                let damping = max(0, 1 - dt * GalleryConfig.overviewDamping)
                yawVelocity *= damping
                pitchVelocity *= damping
                updateCamera()
                try? await Task.sleep(for: .seconds(Double(dt)))
            }
            yawVelocity = 0
            pitchVelocity = 0
        }
    }

    private func updateCamera() {
        guard let camera else { return }
        let horizontalRadius = radius * cos(pitch)
        let position = target + SIMD3<Float>(horizontalRadius * sin(yaw), radius * sin(pitch), horizontalRadius * cos(yaw))
        camera.look(at: target, from: position, relativeTo: nil)
    }
}
