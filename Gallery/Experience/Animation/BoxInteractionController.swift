import Foundation
import Observation
import RealityKit
import simd
import UIKit

/// Presents one of the nine shelf boxes and controls its tape and hinged flaps.
@MainActor
@Observable
final class BoxInteractionController {
    enum Phase { case idle, approaching, waitingForTape, removingTape, ready, returning }
    private(set) var phase: Phase = .idle
    var isActive: Bool { phase != .idle }

    static let boxNames = ["P3_Caixa_M"] + (1...8).map { "P3_Caixa_M_00\($0)" }

    private struct Rig {
        let box: Entity
        let tape: Entity
        let left: Entity
        let right: Entity
        let home: Transform
        let tapeHome: Transform
        let leftHome: Transform
        let rightHome: Transform
        let tapeWasEnabled: Bool
        let nonFlapCollisions: [CollisionSnapshot]
    }

    private struct CollisionSnapshot {
        let entity: Entity
        let component: CollisionComponent
    }

    private enum Side {
        case left, right
        var sign: Float { self == .left ? -1 : 1 }
    }

    @ObservationIgnored private weak var camera: Entity?
    @ObservationIgnored private var rigs: [String: Rig] = [:]
    @ObservationIgnored private var selected: Rig?
    @ObservationIgnored private var sequence: Task<Void, Never>?
    @ObservationIgnored private var dragSide: Side?
    @ObservationIgnored private var dragStartProgress: Float = 0
    @ObservationIgnored private var progress: [Side: Float] = [:]
    @ObservationIgnored private var cameraHome: Transform?
    @ObservationIgnored private var isDraggingTape = false
    @ObservationIgnored private var tapeProgress: Float = 0

    /// Downward angle for inspecting a box with its opening facing upward.
    private let inspectionPitchDegrees: Float = 65

    func attach(to root: Entity, camera: Entity) {
        resetPresentation()
        rigs.removeAll()
        self.camera = camera

        for name in Self.boxNames {
            guard let box = root.findEntity(named: name),
                  let tape = box.children.first(where: { $0.name.hasPrefix("Fita") }),
                  let left = box.children.first(where: { $0.name.hasPrefix("Aba_Esquerda") }),
                  let right = box.children.first(where: { $0.name.hasPrefix("AbaDireita") }) else {
                print("Missing box rig or parts: \(name)")
                continue
            }
            applyBlackTapeMaterial(to: tape)
            box.generateCollisionShapes(recursive: true)
            rigs[name] = Rig(
                box: box, tape: tape, left: left, right: right,
                home: box.transform, tapeHome: tape.transform,
                leftHome: left.transform, rightHome: right.transform,
                tapeWasEnabled: tape.isEnabled,
                nonFlapCollisions: collisions(in: box, excluding: [tape, left, right])
            )
            for target in [box, tape, left, right] {
                target.components.set(InputTargetComponent())
            }
        }
        print("Interactive box rigs: \(rigs.count)/9")
    }

    private func applyBlackTapeMaterial(to entity: Entity) {
        if var model = entity.components[ModelComponent.self] {
            let material = SimpleMaterial(color: .black, roughness: 0.65, isMetallic: false)
            model.materials = (0..<max(model.materials.count, 1)).map { _ in material }
            entity.components.set(model)
        }
        for child in entity.children {
            applyBlackTapeMaterial(to: child)
        }
    }

    func box(containing entity: Entity) -> Entity? {
        var current: Entity? = entity
        while let candidate = current {
            if rigs[candidate.name]?.box === candidate { return candidate }
            current = candidate.parent
        }
        return nil
    }

    func present(_ box: Entity, viewport: CGSize) {
        guard phase == .idle, let rig = rigs[box.name], let camera else { return }
        selected = rig
        phase = .approaching
        progress = [.left: 0, .right: 0]
        dragSide = nil
        isDraggingTape = false
        tapeProgress = 0
        for collision in rig.nonFlapCollisions {
            collision.entity.components.remove(CollisionComponent.self)
        }

        // Keep the camera inside the room and turn downward at its current
        // position. Save the shelf view so leaving inspection restores it.
        cameraHome = camera.transform
        camera.stopAllAnimations(recursive: false)
        var cameraWorld = Transform(matrix: camera.transformMatrix(relativeTo: nil))
        let forward = cameraWorld.rotation.act(SIMD3<Float>(0, 0, -1))
        let heading = atan2(-forward.x, -forward.z)
        let inspectionPitch = inspectionPitchDegrees * .pi / 180
        cameraWorld.rotation = simd_quatf(angle: heading, axis: [0, 1, 0])
            * simd_quatf(angle: -inspectionPitch, axis: [1, 0, 0])
        camera.move(to: cameraWorld, relativeTo: nil, duration: 0.95, timingFunction: .easeInOut)

        // Blender +Z is the opening normal. Keep it world-up, with +Y
        // on screen-left, while the camera looks down into the box.
        let tilt = simd_quatf(angle: inspectionPitch - .pi / 2, axis: [1, 0, 0])
        let turn = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        var destination = Transform(matrix: box.transformMatrix(relativeTo: nil))
        destination.rotation = cameraWorld.rotation * tilt * turn

        // Reserve enough screen width for both fully opened flaps, including
        // portrait layouts and the user's current camera field of view.
        let bounds = box.visualBounds(relativeTo: box)
        let fov = camera.components[PerspectiveCameraComponent.self]?.fieldOfViewInDegrees ?? 50.2
        let tanVertical = tan(fov * .pi / 360)
        let aspect = max(Float(viewport.width / max(viewport.height, 1)), 0.25)
        let openWidth = bounds.extents.y * abs(destination.scale.y) * 2
        let height = bounds.extents.x * abs(destination.scale.x)
            + bounds.extents.z * abs(destination.scale.z) * 0.4
        let distance = max(openWidth / (2 * tanVertical * aspect * 0.80),
                           height / (2 * tanVertical * 0.78))
            + bounds.extents.z * abs(destination.scale.z) / 2
        // Keep the box close to the viewer even on narrow screens. Fitting by
        // distance alone could put it back behind the shelf or outside the room.
        let presentationDistance = min(max(distance, 0.75), 1.15)
        destination.scale *= min(presentationDistance / max(distance, 0.001), 1)
        let openingCenter = SIMD3<Float>(bounds.center.x, bounds.center.y, bounds.max.z)
        let viewCenter = cameraWorld.translation
            + cameraWorld.rotation.act(SIMD3<Float>(0, -0.035, -presentationDistance))
        destination.translation = viewCenter - destination.rotation.act(openingCenter * destination.scale)
        box.move(to: destination, relativeTo: nil, duration: 0.95, timingFunction: .easeInOut)

        sequence = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(0.95))
                guard let self else { return }
                self.phase = .waitingForTape
            } catch { /* A return or a scene reload cancels the sequence. */ }
        }
    }

    func updateDrag(on entity: Entity, translation: CGSize, viewport: CGSize) {
        if phase == .waitingForTape, let rig = selected {
            if !isDraggingTape {
                guard belongsToTape(entity, rig: rig) else { return }
                isDraggingTape = true
                rig.tape.stopAllAnimations(recursive: false)
            }
            let travel = max(Float(viewport.height) * 0.25, 120)
            tapeProgress = min(max(-Float(translation.height) / travel, 0), 1)
            rig.tape.transform = tapeTransform(amount: tapeProgress, rig: rig)
        } else {
            updateFlapDrag(on: entity, translation: translation, viewportWidth: viewport.width)
        }
    }

    func endDrag() {
        guard isDraggingTape, phase == .waitingForTape, let rig = selected else {
            endFlapDrag()
            return
        }
        isDraggingTape = false
        guard tapeProgress >= 0.65 else {
            tapeProgress = 0
            rig.tape.move(to: rig.tapeHome, relativeTo: rig.box, duration: 0.2, timingFunction: .easeInOut)
            return
        }
        phase = .removingTape
        rig.tape.move(to: tapeTransform(amount: 1, rig: rig), relativeTo: rig.box,
                      duration: 0.25, timingFunction: .easeOut)
        sequence = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(0.25))
                guard let self else { return }
                rig.tape.isEnabled = false
                self.phase = .ready
            } catch { }
        }
    }

    private func belongsToTape(_ entity: Entity, rig: Rig) -> Bool {
        var current: Entity? = entity
        while let candidate = current {
            if candidate === rig.tape { return true }
            if candidate === rig.box { break }
            current = candidate.parent
        }
        return false
    }

    private func tapeTransform(amount: Float, rig: Rig) -> Transform {
        var transform = rig.tapeHome
        // Local +X projects upward in the inspection view; +Z lifts the tape
        // away from the lid as the user's finger pulls toward the top edge.
        transform.translation += SIMD3<Float>(0.45, 0, 0.35) * amount
        transform.rotation = simd_quatf(angle: -.pi / 3 * amount, axis: [0, 1, 0])
            * rig.tapeHome.rotation
        return transform
    }

    func updateFlapDrag(on entity: Entity, translation: CGSize, viewportWidth: CGFloat) {
        guard phase == .ready, let rig = selected,
              let side = side(containing: entity, rig: rig) else { return }
        if dragSide == nil {
            dragSide = side
            dragStartProgress = progress[side, default: 0]
            flap(side, rig: rig).stopAllAnimations(recursive: false)
        }
        guard dragSide == side else { return }
        let travel = max(Float(viewportWidth) * 0.20, 100)
        let amount = min(max(dragStartProgress + Float(translation.width) * side.sign / travel, 0), 1)
        progress[side] = amount
        flap(side, rig: rig).transform = flapTransform(side, amount: amount, rig: rig)
    }

    func endFlapDrag() {
        guard let side = dragSide, let rig = selected else { return }
        let amount: Float = progress[side, default: 0] >= 0.35 ? 1 : 0
        progress[side] = amount
        flap(side, rig: rig).move(
            to: flapTransform(side, amount: amount, rig: rig),
            relativeTo: rig.box, duration: 0.22, timingFunction: .easeInOut
        )
        dragSide = nil
    }

    func returnToShelf() {
        guard let rig = selected, phase != .returning else { return }
        sequence?.cancel()
        dragSide = nil
        isDraggingTape = false
        phase = .returning
        rig.box.stopAllAnimations(recursive: true)
        rig.left.move(to: rig.leftHome, relativeTo: rig.box, duration: 0.25, timingFunction: .easeInOut)
        rig.right.move(to: rig.rightHome, relativeTo: rig.box, duration: 0.25, timingFunction: .easeInOut)
        sequence = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(0.25))
                rig.tape.transform = rig.tapeHome
                rig.tape.isEnabled = rig.tapeWasEnabled
                rig.box.move(to: rig.home, relativeTo: rig.box.parent, duration: 0.9, timingFunction: .easeInOut)
                if let self, let camera = self.camera, let home = self.cameraHome {
                    camera.stopAllAnimations(recursive: false)
                    camera.move(to: home, relativeTo: camera.parent, duration: 0.9, timingFunction: .easeInOut)
                }
                try await Task.sleep(for: .seconds(0.9))
                guard let self else { return }
                self.restoreImmediately(rig)
                self.restoreCamera()
                self.selected = nil
                self.phase = .idle
            } catch { }
        }
    }

    func resetPresentation() {
        sequence?.cancel()
        sequence = nil
        if let selected { restoreImmediately(selected) }
        restoreCamera()
        selected = nil
        dragSide = nil
        isDraggingTape = false
        tapeProgress = 0
        progress.removeAll()
        phase = .idle
    }

    private func restoreCamera() {
        if let camera, let cameraHome {
            camera.stopAllAnimations(recursive: false)
            camera.transform = cameraHome
        }
        cameraHome = nil
    }

    private func side(containing entity: Entity, rig: Rig) -> Side? {
        var current: Entity? = entity
        while let candidate = current {
            if candidate === rig.left { return .left }
            if candidate === rig.right { return .right }
            if candidate === rig.box { break }
            current = candidate.parent
        }
        return nil
    }

    private func flap(_ side: Side, rig: Rig) -> Entity {
        side == .left ? rig.left : rig.right
    }

    private func flapTransform(_ side: Side, amount: Float, rig: Rig) -> Transform {
        var transform = side == .left ? rig.leftHome : rig.rightHome
        let angle = side.sign * amount * 155 * .pi / 180
        transform.rotation = simd_quatf(angle: angle, axis: [1, 0, 0]) * transform.rotation
        return transform
    }

    private func restoreImmediately(_ rig: Rig) {
        rig.box.stopAllAnimations(recursive: true)
        rig.box.transform = rig.home
        rig.tape.transform = rig.tapeHome
        rig.tape.isEnabled = rig.tapeWasEnabled
        rig.left.transform = rig.leftHome
        rig.right.transform = rig.rightHome
        for collision in rig.nonFlapCollisions {
            collision.entity.components.set(collision.component)
        }
    }

    private func collisions(in entity: Entity, excluding excluded: [Entity]) -> [CollisionSnapshot] {
        guard !excluded.contains(where: { $0 === entity }) else { return [] }
        var result: [CollisionSnapshot] = []
        if let component = entity.components[CollisionComponent.self] {
            result.append(CollisionSnapshot(entity: entity, component: component))
        }
        for child in entity.children { result += collisions(in: child, excluding: excluded) }
        return result
    }
}
