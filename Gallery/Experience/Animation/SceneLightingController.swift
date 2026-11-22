import RealityKit
import UIKit

enum SceneLightingPreset {
    case morning
    case afternoon
    case night
}

/// Owns the room's exterior, interior, and bedside-lamp lights.
@MainActor
final class SceneLightingController {
    private weak var sceneRoot: Entity?
    private var exteriorLight: Entity?
    private var interiorLight: Entity?
    private var lampLights: [Entity] = []
    private var lampIntensities: [ObjectIdentifier: Float] = [:]

    private var preset: SceneLightingPreset = .afternoon
    private var isExteriorEnabled = true
    private var isInteriorEnabled = true
    private var isLampEnabled = false

    func attach(to root: Entity, preset: SceneLightingPreset = .afternoon) {
        sceneRoot = root
        self.preset = preset

        let exterior = Entity()
        exterior.name = "CodeExteriorLight"
        exterior.orientation = simd_quatf(angle: -.pi / 4, axis: [1, 0, 0])
        exterior.components.set(DirectionalLightComponent())
        root.addChild(exterior)
        exteriorLight = exterior

        let interior = Entity()
        interior.name = "CodeInteriorLight"
        interior.position = [0, 2.5, 0]
        var interiorComponent = PointLightComponent()
        interiorComponent.attenuationRadius = 4.5
        interior.components.set(interiorComponent)
        root.addChild(interior)
        interiorLight = interior

        lampLights = findLampLights(in: root)
        lampIntensities = Dictionary(uniqueKeysWithValues: lampLights.compactMap { entity in
            guard let light = entity.components[PointLightComponent.self] else { return nil }
            return (ObjectIdentifier(entity), light.intensity)
        })
        setLampEnabled(false)

        applyPreset()
        print("Installed code lighting: exterior and interior; found \(lampLights.count) imported lamp point lights")
    }

    func setPreset(_ preset: SceneLightingPreset) {
        self.preset = preset
        applyPreset()
    }

    func setExteriorEnabled(_ enabled: Bool) {
        isExteriorEnabled = enabled
        exteriorLight?.isEnabled = enabled
    }

    func setInteriorEnabled(_ enabled: Bool) {
        isInteriorEnabled = enabled
        interiorLight?.isEnabled = enabled
    }

    func setLampEnabled(_ enabled: Bool) {
        isLampEnabled = enabled
        for entity in lampLights {
            guard var light = entity.components[PointLightComponent.self] else { continue }
            let originalIntensity = lampIntensities[ObjectIdentifier(entity)] ?? light.intensity
            light.intensity = enabled ? originalIntensity : 0
            entity.components.set(light)
        }
    }

    func toggleLamp() {
        setLampEnabled(!isLampEnabled)
    }

    private func applyPreset() {
        let exteriorIntensity: Float
        let exteriorColor: UIColor
        let interiorIntensity: Float
        let interiorColor: UIColor

        switch preset {
        case .morning:
            exteriorIntensity = 1_400
            exteriorColor = UIColor(red: 1.0, green: 0.84, blue: 0.68, alpha: 1)
            interiorIntensity = 190
            interiorColor = UIColor(red: 1.0, green: 0.91, blue: 0.78, alpha: 1)
        case .afternoon:
            exteriorIntensity = 1_800
            exteriorColor = .white
            interiorIntensity = 1200
            interiorColor = .white
        case .night:
            exteriorIntensity = 8
            exteriorColor = UIColor(red: 0.25, green: 0.35, blue: 0.62, alpha: 1)
            interiorIntensity = 1
            interiorColor = UIColor(red: 0.45, green: 0.50, blue: 0.65, alpha: 1)
        }

        if var light = exteriorLight?.components[DirectionalLightComponent.self] {
            light.intensity = exteriorIntensity
            light.color = exteriorColor
            exteriorLight?.components.set(light)
            exteriorLight?.isEnabled = isExteriorEnabled
        }

        if var light = interiorLight?.components[PointLightComponent.self] {
            light.intensity = interiorIntensity
            light.color = interiorColor
            interiorLight?.components.set(light)
            interiorLight?.isEnabled = isInteriorEnabled
        }

    }

    private func findLampLights(in root: Entity) -> [Entity] {
        var matches: [Entity] = []
        func visit(_ entity: Entity, insideLamp: Bool) {
            let isLampPart = insideLamp || ["Abajur", "Topo_do_Abajur"].contains {
                entity.name.compare($0, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
            if isLampPart, let light = entity.components[PointLightComponent.self] {
                matches.append(entity)
            }
            for child in entity.children { visit(child, insideLamp: isLampPart) }
        }
        visit(root, insideLamp: false)
        return matches
    }

    private func findEntity(named name: String, in root: Entity) -> Entity? {
        if root.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return root
        }
        for child in root.children {
            if let match = findEntity(named: name, in: child) { return match }
        }
        return nil
    }
}
