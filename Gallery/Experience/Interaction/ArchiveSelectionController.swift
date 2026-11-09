//import RealityKit
//
//@MainActor
//final class ArchiveSelectionController {
//    private var boxes: [String: Entity] = [:]
//    private var selectedID: String?
//    private var shelfRoot: Entity?
//    private var boxPrototype: Entity?
//    private var itemIDs: [String] = []
//    private var currentItems: [ArchiveDisplayItem] = []
//
//    func configure(shelfRoot: Entity, boxPrototype: Entity, boxes entities: [Entity], items: [ArchiveDisplayItem]) {
//        self.shelfRoot = shelfRoot
//        self.boxPrototype = boxPrototype
//        currentItems = items
//        itemIDs = items.map(\.id)
//        register(entities)
//    }
//
//    func replaceBoxPrototype(_ prototype: Entity) {
//        boxPrototype = prototype
//        itemIDs = []
//        updateShelf(items: currentItems)
//    }
//
//    func updateShelf(items: [ArchiveDisplayItem]) {
//        let nextIDs = items.map(\.id)
//        guard nextIDs != itemIDs,
//              let shelfRoot,
//              let boxPrototype,
//              let parent = shelfRoot.parent else { return }
//
//        let position = shelfRoot.position
//        shelfRoot.removeFromParent()
//        let result = ArchiveShelfBuilder().build(items: items, boxPrototype: boxPrototype)
//        result.root.position = position
//        parent.addChild(result.root)
//        self.shelfRoot = result.root
//        currentItems = items
//        itemIDs = nextIDs
//        register(result.boxes)
//    }
//
//    private func register(_ entities: [Entity]) {
//        boxes = Dictionary(uniqueKeysWithValues: entities.compactMap { entity in
//            guard entity.name.hasPrefix("ArchiveBox.") else { return nil }
//            return (entity.name, entity)
//        })
//    }
//
//    func select(entity: Entity) {
//        guard let box = archiveBox(for: entity) else { return }
//        selectedID = box.name
//
//        for (name, entity) in boxes {
//            let scale: Float = name == selectedID ? GalleryConfig.archiveSelectedScale : GalleryConfig.archiveBoxScale
//            entity.scale = SIMD3(repeating: scale)
//        }
//    }
//
//    func isArchiveBox(_ entity: Entity) -> Bool {
//        archiveBox(for: entity) != nil
//    }
//
//    private func archiveBox(for entity: Entity) -> Entity? {
//        var current: Entity? = entity
//        while let candidate = current, !candidate.name.hasPrefix("ArchiveBox.") {
//            current = candidate.parent
//        }
//        return current
//    }
//}
