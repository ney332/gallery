import RealityKit

@MainActor
enum SceneCamera {
    static func makeOverviewCamera() -> Entity {
        let camera = Entity()
        camera.name = "GalleryCamera"
        let component = PerspectiveCameraComponent(
            near: 0.005,
            far: 20,
            fieldOfViewInDegrees: GalleryConfig.overviewCameraFieldOfView,
            fieldOfViewOrientation: .vertical
        )
        camera.components.set(component)

        camera.look(
            at: GalleryConfig.overviewCameraTarget,
            from: GalleryConfig.overviewCameraPosition,
            upVector: SIMD3<Float>(0, 1, 0),
            relativeTo: nil
        )
        return camera
    }
}
