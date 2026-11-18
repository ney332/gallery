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
    private var lampLight: Entity?

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

        let lamp = Entity()
        lamp.name = "CodeBedsideLampLight"
        if let shade = findEntity(named: "Topo_do_Abajur", in: root) {
            let shadeBounds = shade.visualBounds(relativeTo: root)
            lamp.position = shadeBounds.center - SIMD3<Float>(0, shadeBounds.extents.y * 0.65, 0)
        }
        var lampComponent = PointLightComponent()
        lampComponent.attenuationRadius = 2.0
        lamp.components.set(lampComponent)
        lamp.isEnabled = false
        root.addChild(lamp)
        lampLight = lamp

        applyPreset()
        print("Installed code lighting: exterior, interior, and bedside lamp")
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
        lampLight?.isEnabled = enabled
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

        if var light = lampLight?.components[PointLightComponent.self] {
            light.intensity = 420
            light.color = UIColor(red: 1.0, green: 0.68, blue: 0.38, alpha: 1)
            lampLight?.components.set(light)
            lampLight?.isEnabled = isLampEnabled
        }
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
