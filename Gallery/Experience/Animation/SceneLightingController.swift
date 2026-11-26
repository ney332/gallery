import Foundation
import RealityKit

/// Controls the PointLights authored in Reality Composer.
@MainActor
final class SceneLightingController {
    private var composerLampLights: [Entity] = []
    private weak var lampPull: Entity?
    private var lampPullHome: Transform?
    private var lampPullTask: Task<Void, Never>?

    private var isLampEnabled = false

    func attach(to root: Entity) {
        lampPullTask?.cancel()
        lampPullTask = nil
        lampPull = nil
        lampPullHome = nil
        composerLampLights = installComposerLampLights(in: root)
        print("Lamp tap controls \(composerLampLights.count) Composer PointLight(s)")
        let disabledLights = removeRoomLights(in: root)
        print("Disabled \(disabledLights) room light(s) so the scene starts dark")
        lampPull = findEntity(named: "PuxadorBolinhas", in: root)
        if lampPull == nil, let shade = findEntity(named: "Topo_do_Abajur", in: root) {
            lampPull = findLampPull(in: shade)
        }
        if lampPull == nil, let lampBase = findEntity(named: "Abajur", in: root) {
            lampPull = findLampPull(in: lampBase)
        }
        print("Lamp pull target: " + (lampPull?.name ?? "not found"))

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
        HapticService.shared.playImpact(intensity: 0.25, sharpness: 0.65)

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
                HapticService.shared.playImpact(intensity: 0.18, sharpness: 0.55)
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

    private func removeRoomLights(in root: Entity) -> Int {
        var count = 0
        func remove(from entity: Entity) {
            // Keep the lamp's separate host so a tap can turn it back on.
            guard !composerLampLights.contains(where: { $0 === entity }) else { return }
            if entity.components[PointLightComponent.self] != nil {
                entity.components.remove(PointLightComponent.self)
                count += 1
            }
            if entity.components[DirectionalLightComponent.self] != nil {
                entity.components.remove(DirectionalLightComponent.self)
                count += 1
            }
            if entity.components[SpotLightComponent.self] != nil {
                entity.components.remove(SpotLightComponent.self)
                count += 1
            }
            for child in entity.children { remove(from: child) }
        }
        remove(from: root)
        return count
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
