import Foundation
import Observation
import RealityKit
import simd
import UIKit

@MainActor
@Observable
final class BoxInteractionController {
    enum Phase { case idle, approaching, waitingForTape, removingTape, ready, returning }
    private(set) var phase: Phase = .idle
    var isActive: Bool { phase != .idle }
    var canAccessAlbums: Bool {
        phase == .ready && dragSide == nil
            && progress[.left, default: 0] >= 0.99 && progress[.right, default: 0] >= 0.99
    }
    var selectedBox: Entity? { selected?.box }
    var selectedBoxBounds: BoundingBox? { selected?.closedBounds }

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
        let closedBounds: BoundingBox
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
        var hapticKey: String { self == .left ? "flap_left" : "flap_right" }
    }

    @ObservationIgnored private weak var camera: Entity?
    @ObservationIgnored private var rigs: [String: Rig] = [:]
    @ObservationIgnored private var selected: Rig?
    @ObservationIgnored private var sequence: Task<Void, Never>?
    private var dragSide: Side?
    @ObservationIgnored private var dragStartProgress: Float = 0
    @ObservationIgnored private var flapGestureSoundPlayed = false
    private var progress: [Side: Float] = [:]
    @ObservationIgnored private var cameraHome: Transform?
    @ObservationIgnored private var isDraggingTape = false
    @ObservationIgnored private var tapeProgress: Float = 0
    private let session: BoxSessionState

    init(session: BoxSessionState) {
        self.session = session
    }

    private let inspectionPitchDegrees: Float = 65

    func attach(to root: Entity, camera: Entity) {
        resetPresentation()
        let previousRigs = rigs
        rigs.removeAll()
        self.camera = camera

        for name in Self.boxNames {
            guard let box = root.findEntity(named: name),
                  let tape = box.children.first(where: { $0.name.hasPrefix("Fita") }),
                  let left = box.children.first(where: { $0.name.hasPrefix("Aba_Esquerda") }),
                  let right = box.children.first(where: { $0.name.hasPrefix("AbaDireita") }) else {
                continue
            }
            if let existing = previousRigs[name], existing.box === box {
                rigs[name] = existing
                restoreToShelf(existing)
                continue
            }
            applyBlackTapeMaterial(to: tape)
            box.generateCollisionShapes(recursive: true)
            let rig = Rig(
                box: box, tape: tape, left: left, right: right,
                home: box.transform, tapeHome: tape.transform,
                leftHome: left.transform, rightHome: right.transform,
                closedBounds: box.visualBounds(relativeTo: box),
                tapeWasEnabled: tape.isEnabled,
                nonFlapCollisions: collisions(in: box, excluding: [tape, left, right])
            )
            rigs[name] = rig
            applySessionState(to: rig)
            for target in [box, tape, left, right] {
                target.components.set(InputTargetComponent())
            }
        }
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

        AudioService.shared.playOneShot(named: "CaixaSaindodaEstante", volume: 0.9)
        HapticService.shared.playImpact(intensity: 0.65, sharpness: 0.45)

        let state = session[rig.box.name]
        progress = [.left: state.leftOpenAmount, .right: state.rightOpenAmount]
        applySessionState(to: rig)
        dragSide = nil
        isDraggingTape = false
        tapeProgress = 0
        for collision in rig.nonFlapCollisions {
            collision.entity.components.remove(CollisionComponent.self)
        }

        cameraHome = camera.transform
        camera.stopAllAnimations(recursive: false)
        var cameraWorld = Transform(matrix: camera.transformMatrix(relativeTo: nil))
        let forward = cameraWorld.rotation.act(SIMD3<Float>(0, 0, -1))
        let heading = atan2(-forward.x, -forward.z)
        let inspectionPitch = inspectionPitchDegrees * .pi / 180
        cameraWorld.rotation = simd_quatf(angle: heading, axis: [0, 1, 0])
            * simd_quatf(angle: -inspectionPitch, axis: [1, 0, 0])
        camera.move(to: cameraWorld, relativeTo: nil, duration: 0.95, timingFunction: .easeInOut)

        let tilt = simd_quatf(angle: inspectionPitch - .pi / 2, axis: [1, 0, 0])
        let turn = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        var destination = Transform(matrix: box.transformMatrix(relativeTo: nil))
        destination.rotation = cameraWorld.rotation * tilt * turn

        let bounds = rig.closedBounds
        let fov = camera.components[PerspectiveCameraComponent.self]?.fieldOfViewInDegrees ?? 50.2
        let tanVertical = tan(fov * .pi / 360)
        let aspect = max(Float(viewport.width / max(viewport.height, 1)), 0.25)
        let openWidth = bounds.extents.y * abs(destination.scale.y) * 2
        let height = bounds.extents.x * abs(destination.scale.x)
            + bounds.extents.z * abs(destination.scale.z) * 0.4
        let distance = max(openWidth / (2 * tanVertical * aspect * 0.80),
                           height / (2 * tanVertical * 0.78))
            + bounds.extents.z * abs(destination.scale.z) / 2
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
                self.phase = self.session[rig.box.name].isTapeRemoved ? .ready : .waitingForTape
            } catch {}
        }
    }

    func updateDrag(on entity: Entity, translation: CGSize, viewport: CGSize) {
        if phase == .waitingForTape, let rig = selected {
            if !isDraggingTape {
                guard belongsToTape(entity, rig: rig) else { return }
                isDraggingTape = true
                rig.tape.stopAllAnimations(recursive: false)
                AudioService.shared.playOneShot(named: "FitaCaixa", volume: 0.95)
                HapticService.shared.resetGestureTexture(key: "tape")
            }
            let travel = max(Float(viewport.height) * 0.25, 120)
            let newProgress = min(max(-Float(translation.height) / travel, 0), 1)
            tapeProgress = newProgress
            rig.tape.transform = tapeTransform(amount: tapeProgress, rig: rig)

            HapticService.shared.updateGestureTexture(
                key: "tape",
                progress: tapeProgress,
                step: 0.05,
                intensityRange: 0.35...0.85,
                sharpness: 0.75
            )
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
        HapticService.shared.resetGestureTexture(key: "tape")

        guard tapeProgress >= 0.65 else {
            tapeProgress = 0
            rig.tape.move(to: rig.tapeHome, relativeTo: rig.box, duration: 0.2, timingFunction: .easeInOut)
            return
        }

        session[rig.box.name].isTapeRemoved = true
        phase = .removingTape
        HapticService.shared.playImpact(intensity: 0.9, sharpness: 0.85)
        rig.tape.move(to: tapeTransform(amount: 1, rig: rig), relativeTo: rig.box,
                      duration: 0.25, timingFunction: .easeOut)
        sequence = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(0.25))
                guard let self else { return }
                rig.tape.isEnabled = false
                self.phase = .ready
            } catch {}
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
            flapGestureSoundPlayed = false
            flap(side, rig: rig).stopAllAnimations(recursive: false)
            HapticService.shared.resetGestureTexture(key: side.hapticKey)
        }
        guard dragSide == side else { return }
        let travel = max(Float(viewportWidth) * 0.20, 100)
        let previousAmount = progress[side, default: 0]
        let amount = min(max(dragStartProgress + Float(translation.width) * side.sign / travel, 0), 1)
        let delta = amount - previousAmount
        if !flapGestureSoundPlayed, abs(delta) > 0.001 {
            if delta > 0 {
                AudioService.shared.playOneShot(
                    named: side == .left ? "Abrindocaixa" : "Abrindocaixa2",
                    volume: 0.9
                )
                flapGestureSoundPlayed = true
            }
        }
        progress[side] = amount
        saveFlapProgress(side, amount: amount, rig: rig)
        flap(side, rig: rig).transform = flapTransform(side, amount: amount, rig: rig)

        HapticService.shared.updateGestureTexture(
            key: side.hapticKey,
            progress: amount,
            step: 0.08,
            intensityRange: 0.25...0.60,
            sharpness: 0.45
        )
    }

    func endFlapDrag() {
        guard let side = dragSide, let rig = selected else { return }
        HapticService.shared.resetGestureTexture(key: side.hapticKey)

        let startingAmount = dragStartProgress
        let wasOpened = progress[side, default: 0] >= 0.35
        let amount: Float = wasOpened ? 1 : 0
        progress[side] = amount
        saveFlapProgress(side, amount: amount, rig: rig)

        if abs(amount - startingAmount) > 0.01 {
            HapticService.shared.playImpact(intensity: amount > 0.5 ? 0.55 : 0.35, sharpness: 0.4)
        }
        flap(side, rig: rig).move(
            to: flapTransform(side, amount: amount, rig: rig),
            relativeTo: rig.box, duration: 0.22, timingFunction: .easeInOut
        )
        dragSide = nil
        flapGestureSoundPlayed = false
    }

    func returnToShelf() {
        guard let rig = selected, phase != .returning else { return }
        sequence?.cancel()
        dragSide = nil
        isDraggingTape = false
        phase = .returning
        rig.box.stopAllAnimations(recursive: true)
        let closingBothFlaps = progress[.left, default: 0] > 0.01
            || progress[.right, default: 0] > 0.01
        if closingBothFlaps {
            AudioService.shared.playOneShot(named: "FechandoCaixa", volume: 0.9)
        }
        markFlapsClosed(in: rig)
        rig.tape.transform = rig.tapeHome
        rig.tape.isEnabled = rig.tapeWasEnabled && !session[rig.box.name].isTapeRemoved
        rig.left.move(to: rig.leftHome, relativeTo: rig.box, duration: 0.25, timingFunction: .easeInOut)
        rig.right.move(to: rig.rightHome, relativeTo: rig.box, duration: 0.25, timingFunction: .easeInOut)
        sequence = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(0.25))
                guard let self else { return }
                rig.box.move(to: rig.home, relativeTo: rig.box.parent, duration: 0.9, timingFunction: .easeInOut)
                if let camera = self.camera, let home = self.cameraHome {
                    camera.stopAllAnimations(recursive: false)
                    camera.move(to: home, relativeTo: camera.parent, duration: 0.9, timingFunction: .easeInOut)
                }
                try await Task.sleep(for: .seconds(0.9))
                self.restoreToShelf(rig)
                self.restoreCamera()
                self.selected = nil
                self.phase = .idle
            } catch {}
        }
    }

    func resetPresentation() {
        sequence?.cancel()
        sequence = nil
        if let selected {
            markFlapsClosed(in: selected)
            restoreToShelf(selected)
        }
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

    private func saveFlapProgress(_ side: Side, amount: Float, rig: Rig) {
        if side == .left {
            session[rig.box.name].leftOpenAmount = amount
        } else {
            session[rig.box.name].rightOpenAmount = amount
        }
    }

    private func markFlapsClosed(in rig: Rig) {
        session[rig.box.name].leftOpenAmount = 0
        session[rig.box.name].rightOpenAmount = 0
        progress = [.left: 0, .right: 0]
    }

    private func applySessionState(to rig: Rig) {
        let state = session[rig.box.name]
        rig.tape.transform = rig.tapeHome
        rig.tape.isEnabled = rig.tapeWasEnabled && !state.isTapeRemoved
        rig.left.transform = flapTransform(.left, amount: state.leftOpenAmount, rig: rig)
        rig.right.transform = flapTransform(.right, amount: state.rightOpenAmount, rig: rig)
    }

    private func restoreToShelf(_ rig: Rig) {
        rig.box.stopAllAnimations(recursive: true)
        rig.box.transform = rig.home
        applySessionState(to: rig)
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
