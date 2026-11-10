import RealityKit
import UIKit

@MainActor
struct BlenderAssetLoader {
    let catalog: AssetCatalog

    func load(_ asset: GalleryAssetID) async -> Entity {
        guard let url = catalog.url(for: asset) else {
            print("USDZ missing for asset \(asset.rawValue); using procedural fallback")
            return fallback(for: asset)
        }

        do {
            let entity = try await Entity(contentsOf: url)
            entity.name = catalog.definition(for: asset)?.logicalEntityName ?? asset.rawValue
            if case .room = asset {
                let embeddedCameraCount = removeEmbeddedCameras(from: entity)
                print("Removed \(embeddedCameraCount) embedded USDZ cameras from room asset")
                applyScenarioMaterials(
                    to: entity,
                    inheritedColor: UIColor(red: 0.72, green: 0.68, blue: 0.61, alpha: 1)
                )
            }
            logAnimationInventory(of: entity, asset: asset)
            return entity
        } catch {
            print("Could not load USDZ asset \(asset.rawValue): \(error); using procedural fallback")
            return fallback(for: asset)
        }
    }

    func fallback(for asset: GalleryAssetID) -> Entity {
        switch asset {
        case .room:
            return makeFallbackRoom()
        case .cardboardBox:
            return makeFallbackBox()
        }
    }

    private func makeFallbackRoom() -> Entity {
        let root = Entity()
        root.name = "PlaceholderRoomFallback"

        let floor = ModelEntity(
            mesh: .generateBox(size: [3.5, 0.08, 3.5]),
            materials: [SimpleMaterial(color: UIColor(white: 0.42, alpha: 1), roughness: 1, isMetallic: false)]
        )
        floor.position.y = -0.05
        root.addChild(floor)

        let backWall = ModelEntity(
            mesh: .generateBox(size: [3.5, 2.3, 0.08]),
            materials: [SimpleMaterial(color: UIColor(white: 0.72, alpha: 1), roughness: 1, isMetallic: false)]
        )
        backWall.position = [0, 1.1, -1.7]
        root.addChild(backWall)
        return root
    }

    private func makeFallbackBox() -> Entity {
        let root = ModelEntity(
            mesh: .generateBox(size: [0.95, 0.56, 0.7]),
            materials: [SimpleMaterial(color: UIColor(red: 0.58, green: 0.36, blue: 0.19, alpha: 1), roughness: 0.95, isMetallic: false)]
        )
        root.name = "CardboardBoxFallback"
        return root
    }

    private func applyScenarioMaterials(to entity: Entity, inheritedColor: UIColor) {
        let color = scenarioColor(for: entity.name) ?? inheritedColor
        if var model = entity.components[ModelComponent.self] {
            model.materials = [SimpleMaterial(color: color, roughness: 0.92, isMetallic: false)]
            entity.components.set(model)
        }

        for child in entity.children {
            applyScenarioMaterials(to: child, inheritedColor: color)
        }
    }

    private func removeEmbeddedCameras(from entity: Entity) -> Int {
        var removedCount = 0
        if entity.components.has(PerspectiveCameraComponent.self) {
            entity.components.remove(PerspectiveCameraComponent.self)
            removedCount += 1
        }
        if entity.components.has(OrthographicCameraComponent.self) {
            entity.components.remove(OrthographicCameraComponent.self)
            removedCount += 1
        }
        if entity.components.has(ProjectiveTransformCameraComponent.self) {
            entity.components.remove(ProjectiveTransformCameraComponent.self)
            removedCount += 1
        }

        for child in entity.children {
            removedCount += removeEmbeddedCameras(from: child)
        }
        return removedCount
    }

    private func scenarioColor(for name: String) -> UIColor? {
        return switch name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) {
        case "paredes": UIColor(red: 0.77, green: 0.72, blue: 0.65, alpha: 1)
        case "piso", "teto": UIColor(red: 0.62, green: 0.55, blue: 0.45, alpha: 1)
        case "cama", "cabiceira": UIColor(red: 0.44, green: 0.53, blue: 0.63, alpha: 1)
        case "armario", "mesa": UIColor(red: 0.48, green: 0.31, blue: 0.20, alpha: 1)
        case "tapete": UIColor(red: 0.67, green: 0.61, blue: 0.50, alpha: 1)
        case "vaso": UIColor(red: 0.39, green: 0.57, blue: 0.53, alpha: 1)
        default: nil
        }
    }

    private func logAnimationInventory(of root: Entity, asset: GalleryAssetID) {
        var inventory: [String] = []
        collectAnimationInventory(from: root, into: &inventory)
        print("USDZ animation inventory [\(asset.rawValue)]: \(inventory.isEmpty ? "none" : inventory.joined(separator: ", "))")
    }

    private func collectAnimationInventory(from entity: Entity, into inventory: inout [String]) {
        inventory.append(contentsOf: entity.availableAnimations.map { "\(entity.name): \($0.name ?? "<unnamed>")" })
        for child in entity.children {
            collectAnimationInventory(from: child, into: &inventory)
        }
    }
}
