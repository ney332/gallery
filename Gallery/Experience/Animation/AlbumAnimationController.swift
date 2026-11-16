import RealityKit
import UIKit
import Combine

/// Rig adapter for album.usdz. The cover retains its Blender skeleton;
/// the three paper meshes are independent in the prepared runtime asset.
@MainActor
final class AlbumAnimationController {
    let root: Entity
    let closedBounds: BoundingBox
    private(set) var readingWidth: Float = GalleryConfig.albumCoverWidth * 2
    private(set) var readingCenter: SIMD3<Float> = .zero
    private let paperRoot = Entity()
    private var skeleton: ModelEntity?
    private var restJoints: [Transform] = []
    private var coverJoint: Int?
    private var leftSurface: ModelEntity?
    private var rightSurface: ModelEntity?
    private var turningFront: ModelEntity?
    private var turningBack: ModelEntity?
    private var turningLeaf: Entity?
    private var currentLeft = UnlitMaterial(color: .white)
    private var currentRight = UnlitMaterial(color: .white)
    private var turnDirection = 0
    // A tiny margin avoids quaternion interpolation choosing the downward
    // half-turn when floating-point rounding makes cos(pi / 2) negative.
    private let openAngle: Float = .pi - 0.001

    static func normalizedModel(from prototype: Entity) -> Entity {
        let root = Entity()
        let model = prototype.clone(recursive: true)
        model.transform = Transform()
        model.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 0, 1])
        sanitize(model)
        root.addChild(model)
        let bounds = model.visualBounds(relativeTo: root)
        guard bounds.extents.y.isFinite, bounds.extents.y > 0 else { return root }
        let scale = GalleryConfig.albumPageHeight / bounds.extents.y
        model.scale = SIMD3(repeating: scale)
        model.position = -bounds.center * scale
        return root
    }

    init(prototype: Entity) {
        root = Self.normalizedModel(from: prototype)
        closedBounds = root.visualBounds(relativeTo: root)
        skeleton = Self.findSkeleton(in: root)
        if let skeleton {
            restJoints = skeleton.jointTransforms
            coverJoint = skeleton.jointNames.firstIndex { $0.hasSuffix("/Capa") }
        }
        root.addChild(paperRoot)
        configurePages()
        paperRoot.isEnabled = false
    }

    func setOpen(_ open: Bool) {
        if let skeleton { skeleton.jointTransforms = coverPose(open: open) }
        paperRoot.isEnabled = open
    }

    func animateCover(open: Bool) async {
        paperRoot.isEnabled = false
        if let skeleton, coverJoint != nil {
            let animation = FromToByAnimation<JointTransforms>(
                jointNames: skeleton.jointNames,
                from: JointTransforms(skeleton.jointTransforms),
                to: JointTransforms(coverPose(open: open)),
                duration: GalleryConfig.albumCoverOpenDuration,
                timing: .easeInOut, bindTarget: .jointTransforms
            )
            if let resource = try? AnimationResource.generate(with: animation) {
                let playback = skeleton.playAnimation(resource)
                await waitForPlayback(playback, on: skeleton, duration: GalleryConfig.albumCoverOpenDuration)
            }
        }
        guard !Task.isCancelled else { return }
        skeleton?.stopAllAnimations(recursive: false)
        setOpen(open)
    }

    /// Snapshot the outgoing face before asynchronous target photos arrive.
    func beginTurn(by direction: Int) {
        turnDirection = direction > 0 ? 1 : -1
        turningFront?.model?.materials = [currentRight]
        turningBack?.model?.materials = [currentLeft]
        turningLeaf?.orientation = simd_quatf(angle: direction > 0 ? 0 : -openAngle, axis: [0, 1, 0])
        turningLeaf?.isEnabled = true
    }

    func animateTurn() async {
        guard let turningLeaf else { return }
        var destination = turningLeaf.transform
        destination.rotation = simd_quatf(angle: turnDirection > 0 ? -openAngle : 0, axis: [0, 1, 0])
        let playback = turningLeaf.move(to: destination, relativeTo: paperRoot,
                                        duration: GalleryConfig.albumPageTurnDuration, timingFunction: .easeInOut)
        await waitForPlayback(playback, on: turningLeaf, duration: GalleryConfig.albumPageTurnDuration)
        guard !Task.isCancelled else { return }
        turningLeaf.stopAllAnimations(recursive: false)
        turningLeaf.transform = destination
        turningLeaf.isEnabled = false
        turnDirection = 0
        applyMaterials()
    }

    /// A wall-clock sleep could hide the sheet before RealityKit finished
    /// drawing it under load. Complete the turn on the renderer's event.
    private func waitForPlayback(_ playback: AnimationPlaybackController, on entity: Entity, duration: TimeInterval) async {
        let waiter = PlaybackWaiter()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled, !playback.isComplete else {
                    continuation.resume()
                    return
                }
                waiter.continuation = continuation
                waiter.subscription = entity.scene?.subscribe(to: AnimationEvents.PlaybackCompleted.self, on: entity) { @Sendable event in
                    guard event.playbackController == playback else { return }
                    Task { @MainActor in waiter.finish() }
                }
                waiter.timeout = Task {
                    do { try await Task.sleep(for: .seconds(duration + 3)) } catch { return }
                    waiter.finish()
                }
            }
        } onCancel: {
            Task { @MainActor in
                playback.stop()
                waiter.finish()
            }
        }
    }

    private final class PlaybackWaiter {
        var continuation: CheckedContinuation<Void, Never>?
        var subscription: (any Cancellable)?
        var timeout: Task<Void, Never>?

        func finish() {
            subscription?.cancel()
            subscription = nil
            timeout?.cancel()
            timeout = nil
            let pending = continuation
            continuation = nil
            pending?.resume()
        }
    }

    func setPhotos(_ materials: AlbumPageMaterials) {
        currentLeft = materials.left
        currentRight = materials.right
        applyMaterials()
    }

    private func applyMaterials() {
        if turnDirection > 0 {
            rightSurface?.model?.materials = [currentRight]
            turningBack?.model?.materials = [currentLeft]
        } else if turnDirection < 0 {
            leftSurface?.model?.materials = [currentLeft]
            turningFront?.model?.materials = [currentRight]
        } else {
            leftSurface?.model?.materials = [currentLeft]
            rightSurface?.model?.materials = [currentRight]
            turningFront?.model?.materials = [currentRight]
            turningBack?.model?.materials = [currentLeft]
        }
    }

    private func coverPose(open: Bool) -> [Transform] {
        var pose = restJoints
        if let index = coverJoint, pose.indices.contains(index), open {
            // Blender's Capa local X points opposite the model's hinge axis.
            pose[index].rotation = pose[index].rotation
                * simd_quatf(angle: -openAngle, axis: [1, 0, 0])
        }
        return pose
    }

    private func configurePages() {
        let names = ["PaginaBaixo", "PaginaMeio", "PaginaTopo"]
        let meshes = names.compactMap { root.findEntity(named: $0) }.filter {
            let bounds = $0.visualBounds(relativeTo: root)
            return bounds.extents.x.isFinite && bounds.extents.x > 0
        }
        let bounds = meshes.first?.visualBounds(relativeTo: root)
        let validBounds = bounds.flatMap { $0.extents.x.isFinite && $0.extents.x > 0 ? $0 : nil }
        let width = validBounds?.extents.x ?? GalleryConfig.albumCoverWidth * 0.94
        let height = validBounds?.extents.y ?? GalleryConfig.albumPageHeight * 0.94
        let hingeX = validBounds?.min.x ?? -width / 2
        // Pages rest just above the opened cover; the small separation avoids z-fighting.
        let hinge = SIMD3<Float>(hingeX, validBounds?.center.y ?? 0, closedBounds.max.z + 0.003)
        readingCenter = [hingeX, hinge.y, 0]
        readingWidth = max(width * 2 + 0.04, GalleryConfig.albumCoverWidth * 2)

        for index in 0..<3 {
            let pivot = Entity()
            pivot.name = ["LeftPageHinge", "RightPageHinge", "TurningPageHinge"][index]
            paperRoot.addChild(pivot)
            pivot.position = hinge + SIMD3<Float>(0, 0, index == 2 ? 0.003 : 0)
            if meshes.indices.contains(index) {
                let page = meshes[index]
                let oldBounds = page.visualBounds(relativeTo: root)
                let oldPosition = page.position(relativeTo: root)
                page.setParent(pivot, preservingWorldTransform: true)
                let offset = SIMD3<Float>(hingeX - oldBounds.min.x,
                                          hinge.y - oldBounds.center.y,
                                          pivot.position.z - oldBounds.max.z)
                page.setPosition(oldPosition + offset, relativeTo: root)
            } else {
                let page = ModelEntity(mesh: .generateBox(size: [width, height, 0.001]),
                                       materials: [SimpleMaterial(color: .white, roughness: 1, isMetallic: false)])
                page.position.x = width / 2
                pivot.addChild(page)
            }
            let front = Self.surface(width: width, height: height, back: false)
            let back = Self.surface(width: width, height: height, back: true)
            pivot.addChild(front)
            pivot.addChild(back)
            if index == 0 {
                pivot.orientation = simd_quatf(angle: -openAngle, axis: [0, 1, 0])
                leftSurface = back
            } else if index == 1 {
                rightSurface = front
            } else {
                turningLeaf = pivot
                turningFront = front
                turningBack = back
                pivot.isEnabled = false
            }
        }
    }

    private static func surface(width: Float, height: Float, back: Bool) -> ModelEntity {
        let entity = ModelEntity(mesh: .generatePlane(width: width * 0.96, height: height * 0.96),
                                 materials: [UnlitMaterial(color: .white)])
        entity.position = [width / 2, 0, back ? -0.0015 : 0.0005]
        if back { entity.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0]) }
        return entity
    }

    private static func findSkeleton(in entity: Entity) -> ModelEntity? {
        if let model = entity as? ModelEntity, model.jointNames.contains(where: { $0.hasSuffix("/Capa") }) {
            return model
        }
        for child in entity.children {
            if let match = findSkeleton(in: child) { return match }
        }
        return nil
    }

    private static func sanitize(_ entity: Entity) {
        entity.stopAllAnimations(recursive: false)
        entity.components.remove(CollisionComponent.self)
        entity.components.remove(InputTargetComponent.self)
        entity.components.remove(PerspectiveCameraComponent.self)
        entity.components.remove(OrthographicCameraComponent.self)
        entity.components.remove(ProjectiveTransformCameraComponent.self)
        entity.components.remove(DirectionalLightComponent.self)
        entity.components.remove(PointLightComponent.self)
        entity.components.remove(SpotLightComponent.self)
        for child in entity.children { sanitize(child) }
    }
}
