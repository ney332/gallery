import Foundation
import Observation
import RealityKit
import simd

/// Slides the glass up or down with a vertical drag on the window opening.
@MainActor
@Observable
final class WindowInteractionController {
    private(set) var isDragging = false

    /// A drag covering this fraction of the screen spans the full opening.
    private let dragHeightFraction: Float = 0.35
    private let openingHeightFraction: Float = 0.95

    @ObservationIgnored private weak var glass: Entity?
    @ObservationIgnored private var touchTarget: Entity?
    @ObservationIgnored private var closedTransform = Transform()
    @ObservationIgnored private var liftInParent = SIMD3<Float>.zero
    @ObservationIgnored private var progress: Float = 0
    @ObservationIgnored private var previousTranslationY: Float = 0
    @ObservationIgnored private var dragTravel: Float = 120

    func attach(to glass: Entity?) {
        endDrag()
        touchTarget?.removeFromParent()
        touchTarget = nil
        self.glass = glass
        progress = 0
        guard let glass, let parent = glass.parent else { return }
        closedTransform = glass.transform

        // Convert world-up to the imported parent's coordinates. The asset's
        // Blender axes need not match RealityKit's Y-up convention.
        let height = glass.visualBounds(relativeTo: nil).extents.y
        let parentWorld = parent.transformMatrix(relativeTo: nil)
        let lift = simd_inverse(parentWorld) * SIMD4<Float>(0, height * openingHeightFraction, 0, 0)
        liftInParent = SIMD3<Float>(lift.x, lift.y, lift.z)

        // A sibling stays in the window opening when the visible glass moves.
        let bounds = glass.visualBounds(relativeTo: glass)
        let size = simd_max(bounds.extents, SIMD3<Float>(repeating: 0.025))
        let target = Entity()
        target.name = "WindowDragTarget"
        target.transform = closedTransform
        target.components.set(CollisionComponent(shapes: [
            ShapeResource.generateBox(size: size).offsetBy(translation: bounds.center)
        ]))
        target.components.set(InputTargetComponent())
        parent.addChild(target)
        touchTarget = target
    }

    func contains(_ entity: Entity) -> Bool {
        var current: Entity? = entity
        while let candidate = current {
            if candidate === touchTarget || candidate === glass { return true }
            current = candidate.parent
        }
        return false
    }

    func updateDrag(translation: CGSize, viewportHeight: CGFloat) {
        guard let glass else { return }
        if !isDragging {
            isDragging = true
            previousTranslationY = 0
            dragTravel = max(Float(viewportHeight) * dragHeightFraction, 120)
        }

        // Screen Y decreases upward. Apply deltas so reversing direction at
        // either limit immediately moves the glass again, without dead travel.
        let translationY = Float(translation.height)
        let delta = translationY - previousTranslationY
        previousTranslationY = translationY
        progress = min(max(progress - delta / dragTravel, 0), 1)
        var transform = closedTransform
        transform.translation += liftInParent * progress
        glass.transform = transform
    }

    func endDrag() {
        isDragging = false
        previousTranslationY = 0
        // Keep the current opening when the user releases or cancels the drag.
    }
}
