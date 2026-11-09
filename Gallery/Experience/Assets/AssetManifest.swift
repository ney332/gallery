import Foundation

enum GalleryAssetID: String, CaseIterable, Sendable {
    case room
    case cardboardBox
}

struct AssetDefinition: Sendable {
    let fileName: String
    let version: Int
    let logicalEntityName: String
    let animationNames: [String: String]

    func importedAnimationName(for logicalName: String) -> String? {
        animationNames[logicalName]
    }
}

enum AssetManifest {
    static let definitions: [GalleryAssetID: AssetDefinition] = [
        .room: AssetDefinition(
            fileName: "BaseCenario",
            version: 2,
            logicalEntityName: "BaseScenario",
            animationNames: [:]
        ),
        .cardboardBox: AssetDefinition(
            fileName: "Cardboard_box-placeholder",
            version: 1,
            logicalEntityName: "ArchiveBox",
            animationNames: [:]
        )
    ]
}
