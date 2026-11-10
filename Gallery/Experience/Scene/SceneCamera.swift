import RealityKit

@MainActor
enum SceneCamera {
    static func makeOverviewCamera() -> Entity {
        let camera = Entity()
        camera.name = "GalleryCamera"
        let component = PerspectiveCameraComponent(
            near: 0.01,
            far: 100,
            fieldOfViewInDegrees: GalleryConfig.overviewCameraFieldOfView,
            fieldOfViewOrientation: .horizontal
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
