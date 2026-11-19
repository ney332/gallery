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
    private var leftPageHinge: Entity?
    private var leftSurface: ModelEntity?
    private var rightSurface: ModelEntity?
    private var turningFront: ModelEntity?
    private var turningBack: ModelEntity?
    private var turningLeaf: Entity?
    private var currentLeft = UnlitMaterial(color: .white)
    private var currentRight = UnlitMaterial(color: .white)
    private var turnDirection = 0
    private var showsLeftPage = false
    private var outgoingShowsLeftPage = false
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
        setOpen(false)
    }

    func setOpen(_ open: Bool) {
        if let skeleton { skeleton.jointTransforms = coverPose(open: open) }
        leftPageHinge?.orientation = simd_quatf(angle: open ? -openAngle : 0, axis: [0, 1, 0])
        paperRoot.isEnabled = open
    }

    func animateCover(open: Bool, duration: TimeInterval = GalleryConfig.albumCoverOpenDuration) async {
        // Both photo textures are assigned before this starts. The left leaf
        // unfolds with the cover instead of appearing flat at the final frame.
        paperRoot.isEnabled = true
        async let paperAnimation: Void = animatePaperCover(open: open, duration: duration)
        if let skeleton, coverJoint != nil {
            let animation = FromToByAnimation<JointTransforms>(
                jointNames: skeleton.jointNames,
                from: JointTransforms(skeleton.jointTransforms),
                to: JointTransforms(coverPose(open: open)),
                duration: duration,
                timing: .easeInOut, bindTarget: .jointTransforms
            )
            if let resource = try? AnimationResource.generate(with: animation) {
                let playback = skeleton.playAnimation(resource)
                await waitForPlayback(playback, on: skeleton, duration: duration)
            }
        }
        await paperAnimation
        guard !Task.isCancelled else { return }
        skeleton?.stopAllAnimations(recursive: false)
        setOpen(open)
    }

    private func animatePaperCover(open: Bool, duration: TimeInterval) async {
        guard let leftPageHinge else { return }
        var destination = leftPageHinge.transform
        destination.rotation = simd_quatf(angle: open ? -openAngle : 0, axis: [0, 1, 0])
        // The first spread has no left page. An invisible leaf needs no
        // playback (and must not hold input until its completion timeout).
        guard leftPageHinge.isEnabled else {
            leftPageHinge.transform = destination
            return
        }
        await move(leftPageHinge, to: destination, relativeTo: paperRoot, duration: duration)
    }

    /// The left page is positioned above the open cover plane. Hide its whole
    /// imported page hierarchy before the lid starts moving so neither the
    /// photo quad nor the underlying mesh can render across the outside cover.
    func maskLeftPageForClosing() {
        leftPageHinge?.isEnabled = false
    }

    /// Snapshot the outgoing face before asynchronous target photos arrive.
    func beginTurn(by direction: Int) {
        outgoingShowsLeftPage = showsLeftPage
        turnDirection = direction > 0 ? 1 : -1
        turningFront?.model?.materials = [currentRight]
        turningBack?.model?.materials = [currentLeft]
        setTurnProgress(0)
        turningLeaf?.isEnabled = true
    }

    func setTurnProgress(_ progress: Float) {
        let amount = min(max(progress, 0), 1)
        let angle = turnDirection > 0 ? -openAngle * amount : -openAngle * (1 - amount)
        turningLeaf?.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
    }

    func setCoverProgress(_ amount: Float) {
        var pose = restJoints
        if let index = coverJoint, pose.indices.contains(index) {
            pose[index].rotation *= simd_quatf(angle: -openAngle * min(max(amount, 0), 1), axis: [1, 0, 0])
            skeleton?.jointTransforms = pose
        }
        leftPageHinge?.orientation = simd_quatf(angle: -openAngle * min(max(amount, 0), 1), axis: [0, 1, 0])
        paperRoot.isEnabled = amount > 0
    }

    func finishTurn(commit: Bool, progress: Float, original: AlbumPageMaterials?) async {
        guard let turningLeaf else { return }
        let end: Float = commit ? 1 : 0
        let amount = turnDirection > 0 ? end : 1 - end
        var destination = turningLeaf.transform
        destination.rotation = simd_quatf(angle: -openAngle * amount, axis: [0, 1, 0])
        let duration = max(0.12, GalleryConfig.albumPageTurnDuration * Double(abs(end - progress)))
        await move(turningLeaf, to: destination, relativeTo: paperRoot, duration: duration)
        guard !Task.isCancelled else { return }
        resetTurn(materials: commit ? nil : original)
    }

    func resetTurn(materials: AlbumPageMaterials?) {
        turningLeaf?.stopAllAnimations(recursive: false)
        turningLeaf?.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        turningLeaf?.isEnabled = false
        turnDirection = 0
        outgoingShowsLeftPage = false
        if let materials { setPhotos(materials) } else { applyMaterials() }
    }

    func move(_ entity: Entity, to destination: Transform, relativeTo parent: Entity, duration: TimeInterval) async {
        let playback = entity.move(to: destination, relativeTo: parent,
                                   duration: duration, timingFunction: .easeInOut)
        await waitForPlayback(playback, on: entity, duration: duration)
        guard !Task.isCancelled else { return }
        entity.stopAllAnimations(recursive: false)
        entity.transform = destination
    }

    /// Plays consecutive transform legs as one RealityKit playback. Keeping a
    /// single playback avoids task/event handoffs between legs, which can show
    /// up as brief pauses when the renderer is busy.
    func moveSequence(_ entity: Entity, through poses: [Transform], relativeTo parent: Entity,
                      durations: [TimeInterval]) async {
        guard poses.count == durations.count, !poses.isEmpty else { return }
        var start = entity.transform
        var resources: [AnimationResource] = []
        resources.reserveCapacity(poses.count)
        for (pose, duration) in zip(poses, durations) {
            let animation = FromToByAnimation<Transform>(
                from: start,
                to: pose,
                duration: duration,
                timing: .linear,
                bindTarget: .transform
            )
            guard let resource = try? AnimationResource.generate(with: animation) else { return }
            resources.append(resource)
            start = pose
        }
        guard let sequence = try? AnimationResource.sequence(with: resources) else { return }
        let playback = entity.playAnimation(sequence)
        await waitForPlayback(playback, on: entity, duration: durations.reduce(0, +))
        guard !Task.isCancelled else { return }
        entity.stopAllAnimations(recursive: false)
        entity.transform = poses[poses.count - 1]
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
                    // PlaybackCompleted normally wins. Keep a short safety
                    // margin instead of allowing a missed event to stall the
                    // interaction for several seconds.
                    do { try await Task.sleep(for: .seconds(duration + 0.15)) } catch { return }
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
        showsLeftPage = materials.showsLeftPage
        applyMaterials()
    }

    func photoSlot(containing entity: Entity) -> Int? {
        var current: Entity? = entity
        while let candidate = current {
            if candidate === leftSurface { return 0 }
            if candidate === rightSurface { return 1 }
            current = candidate.parent
        }
        return nil
    }

    private func applyMaterials() {
        // No synthetic paper or photo lies on the inside cover in spread one.
        // During a forward turn, the left page arrives with the moving leaf.
        leftPageHinge?.isEnabled = turnDirection > 0 ? outgoingShowsLeftPage : showsLeftPage
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
        // Keep the paper beneath the CLOSED front cover. Using max.z + an
        // offset placed the photo planes outside the album, on top of its cover
        // as soon as paperRoot became visible during opening.
        let coverInset = max(closedBounds.extents.z * 0.12, 0.002)
        let interiorTop = min(validBounds?.max.z ?? closedBounds.center.z,
                              closedBounds.max.z - coverInset)
        // Keep the right page at its original interior depth. The turning
        // leaf and its left-hand resting page share a fixed plane above the
        // opened cover, without changing depth during the rotation.
        let leftPaperHeight = max(interiorTop, closedBounds.max.z + 0.003)
        let hinge = SIMD3<Float>(hingeX, validBounds?.center.y ?? 0, interiorTop)
        readingCenter = [hingeX, hinge.y, 0]
        readingWidth = max(width * 2 + 0.04, GalleryConfig.albumCoverWidth * 2)

        for index in 0..<3 {
            let pivot = Entity()
            pivot.name = ["LeftPageHinge", "RightPageHinge", "TurningPageHinge"][index]
            paperRoot.addChild(pivot)
            pivot.position = hinge
            pivot.position.z = index == 1 ? interiorTop : leftPaperHeight + (index == 2 ? 0.0005 : 0)
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
            front.name = index == 0 ? "AlbumPhotoFace.Left" : "AlbumPhotoFace.Right"
            back.name = "AlbumPhotoFace.Back.\(index)"
            let photoHitArea = ShapeResource.generateBox(size: [width * 0.88, height * 0.80, 0.012])
            for face in [front, back] {
                face.components.set(CollisionComponent(shapes: [photoHitArea]))
                face.components.set(InputTargetComponent())
            }
            pivot.addChild(front)
            pivot.addChild(back)
            if index == 0 {
                pivot.orientation = simd_quatf(angle: -openAngle, axis: [0, 1, 0])
                leftPageHinge = pivot
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
