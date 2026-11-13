import Foundation
import RealityKit
import simd

/// Named top-level objects in the Reality Composer scene.
/// Use `entity(at:)` for individual mesh parts and nested components.
enum ScenarioAnimationTarget: String, CaseIterable, Sendable {
    case carpet = "Tapete"
    case middleDrawer = "Gaveta_Meio"
    case middleDrawerHandle = "Puxador_Meio"
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
    case knob = "Puxador_"
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
    case bottomDrawer = "Gaveta_Baixo"
    case floor = "Piso"
    case box004 = "P3_Caixa_M_004"
    case box001 = "P3_Caixa_M_001"
    case smallHeadboard = "Cabeceira_Menor"
    case morningLight = "Manha"
    case leftDrawer = "Gaveta_Esquerda"
    case topDrawer = "Gaveta_Cima"
    case desk = "Mesa"
    case walls = "Paredes"
    case smallHeadboardRight = "Cabeceira_Menor_Direita"
    case eveningLight = "Tarde"
    case blanket = "Coberta"
    case box005 = "P3_Caixa_M_005"
}

/// Indexes scene entities and provides transform animations for code-authored motion.
@MainActor
final class ScenarioAnimationController {
    private weak var sceneRoot: Entity?
    private var entitiesByName: [String: [Entity]] = [:]
    private var entitiesByPath: [String: Entity] = [:]
    private var topDrawerClosedTransform: Transform?
    private var isTopDrawerOpen = false

    var mappedEntityCount: Int { entitiesByPath.count }
    var mappedPaths: [String] { entitiesByPath.keys.sorted() }

    func attach(to root: Entity) {
        sceneRoot = root
        entitiesByName.removeAll(keepingCapacity: true)
        entitiesByPath.removeAll(keepingCapacity: true)
        topDrawerClosedTransform = nil
        isTopDrawerOpen = false
        index(root, path: [])
        topDrawerClosedTransform = entity(for: .topDrawer)?.transform
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
    /// `BaseScenario/BaseCenario/root/Gaveta_Cima/Puxador_cima/Cylinder_001`.
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

    /// Opens or closes the Reality Composer top drawer with a short slide.
    /// In this imported scene, the drawer's front points along its local +Y axis.
    @discardableResult
    func toggleTopDrawer(duration: TimeInterval = 0.65) -> Bool {
        guard let drawer = entity(for: .topDrawer),
              var destination = topDrawerClosedTransform else { return false }

        isTopDrawerOpen.toggle()
        if isTopDrawerOpen {
            destination.translation.y += 0.28
        }
        animate(drawer, to: destination, duration: duration)
        return true
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
