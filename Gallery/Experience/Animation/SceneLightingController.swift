import RealityKit
import UIKit

enum SceneLightingPreset: Equatable {
    case morning
    case afternoon
    case night

    static func forCurrentTime(date: Date = Date(), calendar: Calendar = .current) -> Self {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 6..<12: return .morning
        case 12..<18: return .afternoon
        default: return .night
        }
    }
}

/// Owns the room's exterior, ceiling/interior, and bedside-lamp lights.
@MainActor
final class SceneLightingController {
    private weak var sceneRoot: Entity?
    private var exteriorLight: Entity?
    private var interiorLight: Entity?
    private var composerLampLights: [Entity] = []
    private weak var lampPull: Entity?
    private var lampPullHome: Transform?
    private var lampPullTask: Task<Void, Never>?

    private var preset: SceneLightingPreset = .forCurrentTime()
    private var isExteriorEnabled = true
    private var isInteriorEnabled = true
    private var isLampEnabled = false

    func attach(to root: Entity, preset: SceneLightingPreset = .forCurrentTime()) {
        lampPullTask?.cancel()
        lampPullTask = nil
        lampPull = nil
        lampPullHome = nil
        sceneRoot = root
        self.preset = preset

        // Luz direcional externa que acompanha o período do dia.
        let exterior = Entity()
        exterior.name = "CodeExteriorLight"
        exterior.orientation = simd_quatf(angle: -.pi / 3, axis: [1, 0, 0])
        let exteriorComponent = DirectionalLightComponent()
        exterior.components.set([
            exteriorComponent,
            DirectionalLightComponent.Shadow()
        ])
        exterior.isEnabled = true
        root.addChild(exterior)
        exteriorLight = exterior

        // Luz de teto / interior com sombra e foco angulado para criar volume.
        let interior = Entity()
        interior.name = "CodeInteriorLight"
        if let ceiling = findEntity(named: "Teto", in: root) {
            let bounds = ceiling.visualBounds(relativeTo: root)
            interior.position = SIMD3<Float>(bounds.center.x, bounds.min.y - 0.12, bounds.center.z)
        } else {
            interior.position = [0, 2.5, 0]
        }
        // Inclina levemente o cone para projetar sombras laterais em móveis e paredes.
        interior.orientation = simd_quatf(angle: -.pi / 6, axis: [0.6, 0, 0.8])
        var interiorComponent = SpotLightComponent()
        interiorComponent.innerAngleInDegrees = 38
        interiorComponent.outerAngleInDegrees = 75
        interiorComponent.attenuationRadius = 4.2
        interior.components.set([
            interiorComponent,
            SpotLightComponent.Shadow()
        ])
        root.addChild(interior)
        interiorLight = interior

        composerLampLights = installComposerLampLights(in: root)
        print("Lamp tap controls \(composerLampLights.count) Composer PointLight(s)")
        lampPull = findEntity(named: "PuxadorBolinhas", in: root)
        if lampPull == nil, let shade = findEntity(named: "Topo_do_Abajur", in: root) {
            lampPull = findLampPull(in: shade)
        }
        if lampPull == nil, let lampBase = findEntity(named: "Abajur", in: root) {
            lampPull = findLampPull(in: lampBase)
        }
        print("Lamp pull target: " + (lampPull?.name ?? "not found"))

        applyPreset()
        print("Installed code lighting: exterior enabled, light shadows enabled")
    }

    func setPreset(_ preset: SceneLightingPreset) {
        self.preset = preset
        applyPreset()
    }

    func refreshForCurrentTime(date: Date = Date(), calendar: Calendar = .current) {
        let currentPreset = SceneLightingPreset.forCurrentTime(date: date, calendar: calendar)
        guard currentPreset != preset else { return }
        setPreset(currentPreset)
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
        for lightHost in composerLampLights {
            lightHost.isEnabled = enabled
        }
    }

    func toggleLamp() {
        let turningOn = !isLampEnabled
        setLampEnabled(turningOn)
        AudioService.shared.playOneShot(
            named: turningOn ? "LigarAbajour" : "DesligarAbajour",
            volume: 0.9
        )
        animateLampPull()
    }

    private func animateLampPull() {
        guard let pull = lampPull else { return }
        lampPullTask?.cancel()
        pull.stopAllAnimations(recursive: false)

        let home = lampPullHome ?? pull.transform
        lampPullHome = home
        var pulled = home
        let parentWorld = pull.parent?.transformMatrix(relativeTo: nil) ?? matrix_identity_float4x4
        let localDown = simd_inverse(parentWorld) * SIMD4<Float>(0, -0.055, 0, 0)
        pulled.translation += SIMD3<Float>(localDown.x, localDown.y, localDown.z)
        pull.move(to: pulled, relativeTo: pull.parent, duration: 0.12, timingFunction: .easeOut)

        lampPullTask = Task { [weak pull] in
            do {
                try await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled, let pull else { return }
                pull.move(to: home, relativeTo: pull.parent, duration: 0.20, timingFunction: .easeOut)
            } catch {}
        }
    }

    private func findLampPull(in shade: Entity) -> Entity? {
        let likelyNames = ["bolinha", "puxador", "cordao", "cordão", "pendulo", "pêndulo"]
        func search(_ entity: Entity) -> Entity? {
            let name = entity.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if entity !== shade, likelyNames.contains(where: { name.contains($0) }) {
                return entity
            }
            for child in entity.children {
                if let match = search(child) { return match }
            }
            return nil
        }
        return search(shade)
    }

    private func applyPreset() {
        let exteriorIntensity: Float
        let exteriorColor: UIColor
        let interiorIntensity: Float
        let interiorColor: UIColor

        switch preset {
        case .morning:
            exteriorIntensity = 600
            exteriorColor = UIColor(red: 1.0, green: 0.82, blue: 0.62, alpha: 1)
            interiorIntensity = 4_200
            interiorColor = UIColor(red: 1.0, green: 0.82, blue: 0.64, alpha: 1)
        case .afternoon:
            exteriorIntensity = 800
            exteriorColor = UIColor(red: 0.92, green: 0.95, blue: 1.0, alpha: 1)
            interiorIntensity = 5_500
            interiorColor = UIColor(red: 1.0, green: 0.84, blue: 0.67, alpha: 1)
        case .night:
            exteriorIntensity = 50
            exteriorColor = UIColor(red: 0.22, green: 0.32, blue: 0.65, alpha: 1)
            interiorIntensity = 1_400
            interiorColor = UIColor(red: 1.0, green: 0.80, blue: 0.58, alpha: 1)
        }

        if var light = exteriorLight?.components[DirectionalLightComponent.self] {
            light.intensity = exteriorIntensity
            light.color = exteriorColor
            exteriorLight?.components.set(light)
            exteriorLight?.isEnabled = isExteriorEnabled
        }

        if var light = interiorLight?.components[SpotLightComponent.self] {
            light.intensity = interiorIntensity
            light.color = interiorColor
            interiorLight?.components.set(light)
            interiorLight?.isEnabled = isInteriorEnabled
        }

    }

    /// Moves each Composer-authored lamp light onto an empty child entity.
    /// This lets the app toggle the light entity without disabling the shade
    /// mesh that originally carries its PointLightComponent.
    private func installComposerLampLights(in root: Entity) -> [Entity] {
        var sourceEntities: [Entity] = []

        func collect(_ entity: Entity, insideLamp: Bool) {
            let isLampPart = insideLamp || ["Abajur", "Topo_do_Abajur"].contains {
                entity.name.compare($0, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
            if isLampPart, entity.components[PointLightComponent.self] != nil {
                sourceEntities.append(entity)
            }
            for child in entity.children {
                collect(child, insideLamp: isLampPart)
            }
        }
        collect(root, insideLamp: false)

        return sourceEntities.enumerated().compactMap { index, source in
            guard let component = source.components[PointLightComponent.self] else { return nil }
            source.components.remove(PointLightComponent.self)

            let lightHost = Entity()
            lightHost.name = "ComposerLampPointLight_\(index + 1)"
            lightHost.components.set(component)
            lightHost.isEnabled = false
            source.addChild(lightHost)
            return lightHost
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
