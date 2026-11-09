import RealityKit

@MainActor
struct BlenderAnimationController {
    func play(logicalName: String, asset: GalleryAssetID, on root: Entity, catalog: AssetCatalog = .main) -> Bool {
        guard let importedName = catalog.definition(for: asset)?.importedAnimationName(for: logicalName) else {
            print("No manifest mapping for animation \(logicalName) on \(asset.rawValue)")
            return false
        }

        guard let match = findAnimation(named: importedName, in: root) else {
            print("Imported animation \(importedName) unavailable on \(asset.rawValue); keeping procedural state")
            return false
        }

        match.entity.playAnimation(match.animation, transitionDuration: 0.15, startsPaused: false)
        return true
    }

    private func findAnimation(named name: String, in entity: Entity) -> (entity: Entity, animation: AnimationResource)? {
        if let animation = entity.availableAnimations.first(where: { $0.name == name }) {
            return (entity, animation)
        }
        for child in entity.children {
            if let match = findAnimation(named: name, in: child) { return match }
        }
        return nil
    }
}
