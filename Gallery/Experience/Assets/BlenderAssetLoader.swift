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
            let loadStart = ContinuousClock.now
            let entity = try await Entity(contentsOf: url)
            let importDuration = loadStart.duration(to: .now)
            entity.name = catalog.definition(for: asset)?.logicalEntityName ?? asset.rawValue
            if case .room = asset {
                removeBlenderCamera(from: entity)
                configureShelfInteraction(in: entity)
            }
            let complexity = sceneComplexity(of: entity)
            print(
                "USDZ load [\(asset.rawValue)]: import=\(importDuration), " +
                "entities=\(complexity.entities), meshes=\(complexity.meshes), " +
                "materials=\(complexity.materials), " +
                "lights(directional/point/spot)=\(complexity.directionalLights)/" +
                "\(complexity.pointLights)/\(complexity.spotLights)"
            )
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

    private func configureShelfInteraction(in root: Entity) {
        guard let shelf = findEntity(named: "Estante", in: root) else {
            print("Shelf interaction target 'Estante' was not found in the room USDZ")
            return
        }

        shelf.generateCollisionShapes(recursive: true)
        shelf.components.set(InputTargetComponent())
        print("Configured shelf tap target: \(shelf.name)")
    }

    private func removeBlenderCamera(from root: Entity) {
        var removed = 0

        func removeCameraEntities(from parent: Entity) {
            for child in parent.children {
                if child.name.compare("Camera", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                    child.removeFromParent()
                    removed += 1
                } else {
                    removeCameraEntities(from: child)
                }
            }
        }

        removeCameraEntities(from: root)
        print("Removed imported Blender cameras: \(removed)")
    }

    private func findEntity(named name: String, in root: Entity) -> Entity? {
        if root.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return root
        }
        for child in root.children {
            if let match = findEntity(named: name, in: child) {
                return match
            }
        }
        return nil
    }

    private func sceneComplexity(of root: Entity) -> (
        entities: Int,
        meshes: Int,
        materials: Int,
        directionalLights: Int,
        pointLights: Int,
        spotLights: Int
    ) {
        var entities = 0
        var meshes = 0
        var materials = 0
        var directionalLights = 0
        var pointLights = 0
        var spotLights = 0

        func visit(_ entity: Entity) {
            entities += 1
            directionalLights += entity.components.has(DirectionalLightComponent.self) ? 1 : 0
            pointLights += entity.components.has(PointLightComponent.self) ? 1 : 0
            spotLights += entity.components.has(SpotLightComponent.self) ? 1 : 0
            if let model = entity.components[ModelComponent.self] {
                meshes += 1
                materials += model.materials.count
            }
            for child in entity.children {
                visit(child)
            }
        }

        visit(root)
        return (entities, meshes, materials, directionalLights, pointLights, spotLights)
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
