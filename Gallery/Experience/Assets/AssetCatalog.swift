import Foundation

struct AssetCatalog {
    let bundle: Bundle
    let manifest: [GalleryAssetID: AssetDefinition]

    static let main = AssetCatalog(bundle: .main, manifest: AssetManifest.definitions)

    func definition(for asset: GalleryAssetID) -> AssetDefinition? {
        manifest[asset]
    }

    func url(for asset: GalleryAssetID) -> URL? {
        guard let definition = definition(for: asset) else { return nil }
        return bundle.url(forResource: definition.fileName, withExtension: "usdz")
    }
}
