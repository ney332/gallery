import Foundation
import Observation
import RealityKit
import simd

/// Toggles the window glass between its closed and open positions on tap.
@MainActor
@Observable
final class WindowInteractionController {
    private(set) var isAnimating = false

    private let openingHeightFraction: Float = 0.95

    @ObservationIgnored private weak var glass: Entity?
    @ObservationIgnored private var touchTarget: Entity?
    @ObservationIgnored private var closedTransform = Transform()
    @ObservationIgnored private var liftInParent = SIMD3<Float>.zero
    @ObservationIgnored private var progress: Float = 0
    @ObservationIgnored private var animationTask: Task<Void, Never>?

    func attach(to glass: Entity?) {
        animationTask?.cancel()
        animationTask = nil
        self.glass?.stopAllAnimations(recursive: false)
        isAnimating = false
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
        target.name = "WindowTapTarget"
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

    func toggle() {
        guard !isAnimating, let glass else { return }
        let opening = progress < 0.5
        let destinationProgress: Float = opening ? 1 : 0
        let soundName = opening ? "AbrirJanela" : "FecharJanela"
        let audioDuration = AudioService.shared.playOneShot(named: soundName, volume: 0.85)
        let duration = max(audioDuration, 0.8)

        progress = destinationProgress
        isAnimating = true
        glass.stopAllAnimations(recursive: false)
        let startTransform = glass.transform
        var destination = closedTransform
        destination.translation += liftInParent * destinationProgress

        animationTask?.cancel()
        animationTask = Task { [weak self, weak glass] in
            let startTime = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                guard let self, let glass else { return }
                let elapsed = ProcessInfo.processInfo.systemUptime - startTime
                let linearProgress = Float(min(elapsed / duration, 1))
                let easedProgress = linearProgress * linearProgress * (3 - 2 * linearProgress)

                var frameTransform = startTransform
                frameTransform.translation = startTransform.translation
                    + (destination.translation - startTransform.translation) * easedProgress
                glass.transform = frameTransform

                guard linearProgress < 1 else {
                    self.isAnimating = false
                    self.animationTask = nil
                    return
                }

                do {
                    try await Task.sleep(for: .milliseconds(16))
                } catch {
                    return
                }
            }
        }
    }
}
