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
                print("Removed \(embeddedCameraCount) embedded cameras from room asset")
                configureShelfInteraction(in: entity)
                configureDrawerInteraction(in: entity)
                configureDeskInteraction(in: entity)
            }
            logAnimationInventory(of: entity, asset: asset)
            return entity
        } catch {
            print("Could not load scene asset \(asset.rawValue): \(error); using procedural fallback")
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

    private func configureShelfInteraction(in root: Entity) {
        guard let shelf = findEntity(named: "Estante", in: root) else {
            print("Shelf interaction target 'Estante' was not found in the Reality scene")
            return
        }

        shelf.generateCollisionShapes(recursive: true)
        shelf.components.set(InputTargetComponent())
        print("Configured shelf tap target: \(shelf.name)")
    }

    private func configureDrawerInteraction(in root: Entity) {
        guard let drawer = findEntity(named: "Gaveta_Cima", in: root) else {
            print("Drawer interaction target 'Gaveta_Cima' was not found in the Reality scene")
            return
        }

        drawer.generateCollisionShapes(recursive: true)
        drawer.components.set(InputTargetComponent())
        print("Configured drawer tap target: \(drawer.name)")
    }

    private func configureDeskInteraction(in root: Entity) {
        guard let desk = findEntity(named: "Mesa", in: root) else {
            print("Desk interaction target 'Mesa' was not found in the Reality scene")
            return
        }

        desk.generateCollisionShapes(recursive: true)
        desk.components.set(InputTargetComponent())
        print("Configured desk tap target: \(desk.name)")
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

    private func logAnimationInventory(of root: Entity, asset: GalleryAssetID) {
        var inventory: [String] = []
        collectAnimationInventory(from: root, into: &inventory)
        print("Scene animation inventory [\(asset.rawValue)]: \(inventory.isEmpty ? "none" : inventory.joined(separator: ", "))")
    }

    private func collectAnimationInventory(from entity: Entity, into inventory: inout [String]) {
        inventory.append(contentsOf: entity.availableAnimations.map { "\(entity.name): \($0.name ?? "<unnamed>")" })
        for child in entity.children {
            collectAnimationInventory(from: child, into: &inventory)
        }
    }
}
