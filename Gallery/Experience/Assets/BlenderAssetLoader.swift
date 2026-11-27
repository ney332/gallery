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
                let embeddedAlbumCount = removeEmbeddedAlbums(from: entity)
                print("Removed \(embeddedAlbumCount) embedded albums from room asset")
                removeTimeOfDayObjects(from: entity)
                configureShelfInteraction(in: entity)
                configureDrawerInteraction(in: entity)
                configureDeskInteraction(in: entity)
                configureLampInteraction(in: entity)
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
        case .albumCover:
            return ModelEntity(
                mesh: .generateBox(size: [0.36, 0.285, 0.025]),
                materials: [SimpleMaterial(color: .brown, roughness: 0.8, isMetallic: false)]
            )
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

    /// The scene contains static `Album_…` display models positioned around
    /// the boxes. Albums used by the app are loaded dynamically, so remove the
    /// static scene copies while keeping every other imported object intact.
    private func removeEmbeddedAlbums(from root: Entity) -> Int {
        var albums: [Entity] = []
        func collect(from entity: Entity) {
            for child in entity.children {
                if child.name.lowercased().hasPrefix("album_") {
                    albums.append(child)
                } else {
                    collect(from: child)
                }
            }
        }
        collect(from: root)

        for album in albums {
            album.removeFromParent()
        }
        return albums.count
    }

    /// Removes the Blender time-of-day props from the imported `world` scene,
    /// leaving the room geometry intact so exterior light can reach the window.
    private func removeTimeOfDayObjects(from root: Entity) {
        // Entity(contentsOf:) may return `world` itself as the root; the loader
        // assigns that root the logical name `BaseScenario` before this runs.
        let world = findEntity(named: "world", in: root) ?? root

        let targetNames: Set<String> = ["manha", "manha_001", "tarde", "noite"]
        var objectsToRemove: [Entity] = []
        func collect(from parent: Entity) {
            for child in parent.children {
                let normalizedName = child.name.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                )
                if targetNames.contains(normalizedName) {
                    objectsToRemove.append(child)
                } else {
                    collect(from: child)
                }
            }
        }
        collect(from: world)

        for object in objectsToRemove {
            // The Composer spotlight is nested under "Manha". Keep it when
            // removing the time-of-day geometry, without changing its pose.
            if let sun = object.findEntity(named: "sol"),
               sun.components[SpotLightComponent.self] != nil {
                sun.setParent(world, preservingWorldTransform: true)
                print("Preserved Composer spotlight 'sol' from \(object.name)")
            }
            object.removeFromParent()
        }
        print("Removed \(objectsToRemove.count) time-of-day objects from world: \(objectsToRemove.map(\.name).joined(separator: ", "))")
    }

    private func configureShelfInteraction(in root: Entity) {
        guard let shelf = findEntity(named: "Estante", in: root) else {
            print("Shelf interaction target 'Estante' was not found in the Reality scene")
            return
        }

        // A convex hull of the entire shelf covers its openings and intercepts
        // taps intended for boxes. Use the back panel as the shelf tap target.
        removeCollisionShapes(from: shelf)
        let bounds = shelf.visualBounds(relativeTo: shelf)
        let thickness: Float = 0.02
        let panel = ShapeResource.generateBox(size: [thickness, bounds.extents.y, bounds.extents.z])
            .offsetBy(translation: [bounds.max.x - thickness / 2, bounds.center.y, bounds.center.z])
        shelf.components.set(CollisionComponent(shapes: [panel]))
        shelf.components.set(InputTargetComponent())
        print("Configured shelf tap target: \(shelf.name)")
    }

    private func configureDrawerInteraction(in root: Entity) {
        var configuredDrawers = 0
        for drawerName in ScenarioDrawer.allCases.map(\.rawValue) {
            guard let drawer = findEntity(named: drawerName, in: root) else {
                print("Drawer interaction target '\(drawerName)' was not found in the Reality scene")
                continue
            }

            drawer.generateCollisionShapes(recursive: true)
            drawer.components.set(InputTargetComponent())
            configuredDrawers += 1
            print("Configured drawer tap target: \(drawer.name)")
        }
        print("Configured drawer tap targets: \(configuredDrawers)/\(ScenarioDrawer.allCases.count)")
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

    private func configureLampInteraction(in root: Entity) {
        let lampPartNames = ["Abajur", "Topo_do_Abajur", "PuxadorBolinhas"]
        var configuredParts = 0
        for name in lampPartNames {
            guard let part = findEntity(named: name, in: root) else { continue }
            part.generateCollisionShapes(recursive: true)
            part.components.set(InputTargetComponent())
            configuredParts += 1
        }

        if configuredParts == 0 {
            print("Lamp interaction targets were not found in the Reality scene")
        } else {
            print("Configured lamp tap targets: \(configuredParts)")
        }
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

    private func removeCollisionShapes(from entity: Entity) {
        entity.components.remove(CollisionComponent.self)
        for child in entity.children { removeCollisionShapes(from: child) }
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
