//import RealityKit
//import UIKit
//
//struct ArchiveDisplayItem: Identifiable, Sendable {
//    enum Kind: Sendable { case year(Int), favorites }
//
//    let id: String
//    let title: String
//    let kind: Kind
//
//    static func make(years: [GalleryYear], favorites: [PhotoReference]) -> [ArchiveDisplayItem] {
//        let yearItems = years.prefix(8).map { year in
//            ArchiveDisplayItem(id: "year-\(year.year)", title: String(year.year), kind: .year(year.year))
//        }
//        let favoriteItems = favorites.isEmpty ? [] : [ArchiveDisplayItem(id: "favorites", title: "Favoritos", kind: .favorites)]
//        return Array(yearItems) + favoriteItems
//    }
//}
//
//@MainActor
//struct ArchiveShelfBuilder {
//    func build(items: [ArchiveDisplayItem], boxPrototype: Entity) -> (root: Entity, boxes: [Entity]) {
//        let root = Entity()
//        root.name = "ArchiveShelf"
//
//        let wood = SimpleMaterial(color: UIColor(red: 0.30, green: 0.18, blue: 0.11, alpha: 1), roughness: 0.85, isMetallic: false)
//        let width: Float = 1.15
//        let depth: Float = 0.34
//        let tierYs: [Float] = [0.28, 0.62, 0.96]
//
//        for y in tierYs {
//            let board = ModelEntity(mesh: .generateBox(size: [width, 0.045, depth]), materials: [wood])
//            board.position = [0, y, 0]
//            root.addChild(board)
//        }
//
//        for x: Float in [-width / 2 + 0.035, width / 2 - 0.035] {
//            let side = ModelEntity(mesh: .generateBox(size: [0.07, 1.06, depth]), materials: [wood])
//            side.position = [x, 0.59, 0]
//            root.addChild(side)
//        }
//
//        var boxes: [Entity] = []
//        if GalleryConfig.showsArchiveBoxes {
//            for (index, item) in items.enumerated() {
//                let box = boxPrototype.clone(recursive: true)
//                box.name = "ArchiveBox.\(item.id)"
//                box.scale = SIMD3(repeating: GalleryConfig.archiveBoxScale)
//                box.position = boxPosition(for: index)
//                box.components.set(InputTargetComponent())
//                box.components.set(CollisionComponent(shapes: [.generateBox(size: [1.05, 0.68, 0.76])]))
//
//                let labelMesh = MeshResource.generateText(
//                    item.title,
//                    extrusionDepth: 0.002,
//                    font: .systemFont(ofSize: 12),
//                    containerFrame: CGRect(x: 0, y: 0, width: 0.82, height: 0.18),
//                    alignment: .center
//                )
//                let label = ModelEntity(
//                    mesh: labelMesh,
//                    materials: [SimpleMaterial(color: .black, roughness: 1, isMetallic: false)]
//                )
//                label.name = "ArchiveBoxLabel.\(item.id)"
//                label.position = [-0.41, 0.1, 0.357]
//                box.addChild(label)
//                root.addChild(box)
//                boxes.append(box)
//            }
//        }
//
//        return (root: root, boxes: boxes)
//    }
//
//    private func boxPosition(for index: Int) -> SIMD3<Float> {
//        let column = index % 3
//        let row = index / 3
//        let x: Float = Float(column - 1) * 0.34
//        let baseY: Float = [0.44, 0.78, 1.12].element(at: row) ?? 1.12
//        return [x, baseY, 0]
//    }
//}
//
//private extension Array {
//    func element(at index: Int) -> Element? {
//        indices.contains(index) ? self[index] : nil
//    }
//}
