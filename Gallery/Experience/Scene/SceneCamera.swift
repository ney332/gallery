import RealityKit
import SwiftUI

@MainActor
enum SceneCamera {
    static func makeOverviewCamera(viewportSize: CGSize) -> Entity {
        let camera = Entity()
        camera.name = "GalleryCamera"
        var component = OrthographicCameraComponent()
        component.scale = GalleryConfig.overviewCameraScale(for: viewportSize)
        component.near = 0.01
        component.far = 100
        component.scaleDirection = .vertical
        camera.components.set(component)
        return camera
    }
}
