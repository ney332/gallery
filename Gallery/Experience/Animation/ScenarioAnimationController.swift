import Foundation
import RealityKit
import simd

/// Named top-level objects in the Reality Composer scene.
/// Use `entity(at:)` for individual mesh parts and nested components.
enum ScenarioAnimationTarget: String, CaseIterable, Sendable {
    case carpet = "Tapete"
    case middleDrawer = "Gaveta_Meio"
    case middleDrawerHandle = "Puxador_baixo_005"
    case leftDrawerHandle = "Puxador_baixo_003"
    case rightDrawerHandle = "Puxador_baixo_004"
    case shelfUnit = "Prateleira"
    case smallHeadboardLeft = "Cabeceira_Menor_Esquerda"
    case morningLightUpper = "Manha_001"
    case box008 = "P3_Caixa_M_008"
    case blanketUpper = "Coberta_001"
    case frontPillow = "Travesseiro_Frente"
    case planterSaucer = "Prato_do_vaso"
    case box007 = "P3_Caixa_M_007"
    case box003 = "P3_Caixa_M_003"
    case bed = "Cama"
    case archiveShelf = "Estante"
    case windowGlass = "Vidro"
    case largeHeadboard = "Cabeceira_Maior"
    case knob = "PuxadorBolinhas"
    case lampBase = "Abajur"
    case planterSoil = "Terra"
    case backPillow = "Travesseiro_Fundo"
    case mattress = "Colchao"
    case rightDrawer = "Gaveta_Direita"
    case cross = "Cruz"
    case largeHeadboardLeft = "Cabeceira_Maior_Esquerda"
    case box002 = "P3_Caixa_M_002"
    case lampShade = "Topo_do_Abajur"
    case box006 = "P3_Caixa_M_006"
    case headboard = "Cabiceira"
    case mainBox = "P3_Caixa_M"
    case chair = "Cube_006"
    case ceiling = "Teto"
    case planter = "Vaso"
    case largeHeadboardRight = "Cabeceira_Maior_Direita"
    case floor = "Piso"
    case box004 = "P3_Caixa_M_004"
    case box001 = "P3_Caixa_M_001"
    case smallHeadboard = "Cabeceira_Menor"
    case morningLight = "Manha"
    case leftDrawer = "Gaveta_Esquerda"
    case desk = "Mesa"
    case walls = "Paredes"
    case smallHeadboardRight = "Cabeceira_Menor_Direita"
    case eveningLight = "Tarde"
    case blanket = "Coberta"
    case box005 = "P3_Caixa_M_005"
}

enum ScenarioDrawer: String, CaseIterable, Sendable {
    case left = "Gaveta_Esquerda"
    case middle = "Gaveta_Meio"
    case right = "Gaveta_Direita"

    static func matches(_ name: String) -> Bool {
        allCases.contains {
            $0.rawValue.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }
}

/// Indexes scene entities and provides transform animations for code-authored motion.
@MainActor
final class ScenarioAnimationController {
    static let drawerAnimationDuration: TimeInterval = 0.65

    private weak var sceneRoot: Entity?
    private var entitiesByName: [String: [Entity]] = [:]
    private var entitiesByPath: [String: Entity] = [:]
    private struct DrawerState {
        let entity: Entity
        var closedTransform: Transform
        var outwardDirection: SIMD3<Float>
        var isOpen = false
        var isAnimating = false
        var dragStartTransform: Transform?
        var dragStartProgress: Float = 0
        var hasCapturedClosedPose = false
    }
    private var drawersByName: [String: DrawerState] = [:]

    var mappedEntityCount: Int { entitiesByPath.count }
    var mappedPaths: [String] { entitiesByPath.keys.sorted() }

    func attach(to root: Entity) {
        sceneRoot = root
        entitiesByName.removeAll(keepingCapacity: true)
        entitiesByPath.removeAll(keepingCapacity: true)
        drawersByName.removeAll(keepingCapacity: true)
        index(root, path: [])
        for drawer in ScenarioDrawer.allCases {
            guard let entity = entity(named: drawer.rawValue) else { continue }
            drawersByName[normalized(drawer.rawValue)] = DrawerState(
                entity: entity,
                closedTransform: entity.transform,
                outwardDirection: .zero
            )
        }
        print("Scenario animation map: indexed \(mappedEntityCount) entities")

        let missingTargets = ScenarioAnimationTarget.allCases
            .filter { entity(named: $0.rawValue) == nil }
            .map(\.rawValue)
        if !missingTargets.isEmpty {
            print("Scenario animation targets not found: \(missingTargets.joined(separator: ", "))")
        }
    }

    func entity(for target: ScenarioAnimationTarget) -> Entity? {
        entity(named: target.rawValue)
    }

    func entity(named name: String) -> Entity? {
        entitiesByName[normalized(name)]?.first
    }

    func entities(named name: String) -> [Entity] {
        entitiesByName[normalized(name)] ?? []
    }

    /// Paths are slash-separated from the loaded Reality scene root, for example
    /// `world/BaseCenario/root/Gaveta_Meio/Puxador_baixo_005/Cylinder_024`.
    func entity(at path: String) -> Entity? {
        entitiesByPath[normalizedPath(path)]
    }

    @discardableResult
    func animate(
        _ target: ScenarioAnimationTarget,
        to transform: Transform,
        duration: TimeInterval = 1.0
    ) -> Bool {
        guard let entity = entity(for: target) else { return false }
        animate(entity, to: transform, duration: duration)
        return true
    }

    @discardableResult
    func animate(
        named name: String,
        to transform: Transform,
        duration: TimeInterval = 1.0
    ) -> Bool {
        guard let entity = entity(named: name) else { return false }
        animate(entity, to: transform, duration: duration)
        return true
    }

    @discardableResult
    func animate(
        at path: String,
        to transform: Transform,
        duration: TimeInterval = 1.0
    ) -> Bool {
        guard let entity = entity(at: path) else { return false }
        animate(entity, to: transform, duration: duration)
        return true
    }

    @discardableResult
    func move(
        _ target: ScenarioAnimationTarget,
        to position: SIMD3<Float>,
        duration: TimeInterval = 1.0
    ) -> Bool {
        guard let entity = entity(for: target) else { return false }
        var destination = entity.transform
        destination.translation = position
        animate(entity, to: destination, duration: duration)
        return true
    }

    /// Pulls the drawer in response to the user's vertical drag. Positive
    /// screen-space movement pulls it toward the user; releasing preserves its
    /// current position, including a partial opening.
    func dragDrawer(named name: String, verticalTranslation: CGFloat, viewportHeight: CGFloat) {
        let key = normalized(name)
        guard var state = drawersByName[key] else { return }
        if state.dragStartTransform == nil {
            if !state.hasCapturedClosedPose {
                state.closedTransform = state.entity.transform
                state.hasCapturedClosedPose = true
            }
            state.dragStartTransform = state.entity.transform
            state.outwardDirection = outwardDirection(for: state.entity)
            state.dragStartProgress = drawerProgress(state)
        }

        let maxTravel = drawerTravel(for: state)
        guard maxTravel > 0 else { return }
        let dragSpan = max(Float(viewportHeight) * 0.20, 1)
        let progress = min(max(state.dragStartProgress + Float(verticalTranslation) / dragSpan, 0), 1)
        var destination = state.closedTransform
        let front = parentSpaceFront(for: state)
        destination.translation += front * maxTravel * progress
        state.entity.transform = destination
        state.isOpen = progress > 0.02
        drawersByName[key] = state
    }

    func endDrawerDrag(named name: String) {
        let key = normalized(name)
        guard var state = drawersByName[key] else { return }
        state.dragStartTransform = nil
        state.dragStartProgress = 0
        drawersByName[key] = state
    }

    private func outwardDirection(for drawer: Entity) -> SIMD3<Float> {
        // The imported cabinet faces world -X. Its drawers open toward the
        // room along that same direction; using a fixed world vector avoids
        // inheriting the reversed local axis from the Reality Composer rig.
        SIMD3<Float>(-1, 0, 0)
    }

    private func drawerTravel(for state: DrawerState) -> Float {
        let bounds = state.entity.visualBounds(relativeTo: state.entity.parent)
        let parentFront = parentSpaceFront(for: state)
        let depth = simd_dot(simd_abs(parentFront), bounds.extents)
        return min(max(depth * 1.72, 0.24), 0.42)
    }

    private func parentSpaceFront(for state: DrawerState) -> SIMD3<Float> {
        let worldFront = state.outwardDirection
        let parentTransform = state.entity.parent?.transformMatrix(relativeTo: nil) ?? matrix_identity_float4x4
        let parentInverse = simd_inverse(parentTransform)
        let parentFront4 = parentInverse * SIMD4<Float>(worldFront.x, worldFront.y, worldFront.z, 0)
        return simd_normalize(SIMD3<Float>(parentFront4.x, parentFront4.y, parentFront4.z))
    }

    private func drawerProgress(_ state: DrawerState) -> Float {
        let travel = drawerTravel(for: state)
        guard travel > 0 else { return 0 }
        let offset = state.entity.transform.translation - state.closedTransform.translation
        return min(max(simd_dot(offset, parentSpaceFront(for: state)) / travel, 0), 1)
    }

    @discardableResult
    func rotate(
        _ target: ScenarioAnimationTarget,
        to orientation: simd_quatf,
        duration: TimeInterval = 1.0
    ) -> Bool {
        guard let entity = entity(for: target) else { return false }
        var destination = entity.transform
        destination.rotation = orientation
        animate(entity, to: destination, duration: duration)
        return true
    }

    @discardableResult
    func scale(
        _ target: ScenarioAnimationTarget,
        to scale: SIMD3<Float>,
        duration: TimeInterval = 1.0
    ) -> Bool {
        guard let entity = entity(for: target) else { return false }
        var destination = entity.transform
        destination.scale = scale
        animate(entity, to: destination, duration: duration)
        return true
    }

    private func animate(_ entity: Entity, to transform: Transform, duration: TimeInterval) {
        entity.move(
            to: transform,
            relativeTo: entity.parent,
            duration: max(duration, 0),
            timingFunction: .easeInOut
        )
    }

    private func index(_ entity: Entity, path: [String]) {
        let name = entity.name.isEmpty ? "<unnamed>" : entity.name
        let currentPath = path + [name]
        entitiesByPath[normalizedPath(currentPath.joined(separator: "/"))] = entity
        entitiesByName[normalized(name), default: []].append(entity)

        for child in entity.children {
            index(child, path: currentPath)
        }
    }

    private func normalizedPath(_ path: String) -> String {
        path.split(separator: "/")
            .map { normalized(String($0)) }
            .joined(separator: "/")
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
