import Observation
import RealityKit
import UIKit

/// Temporary covers and procedural photo pages; independent of Blender clips.
@MainActor
@Observable
final class AlbumBookController {
    private(set) var isPrepared = false
    private(set) var albums: [AlbumContent] = []
    private(set) var selectedAlbumID: String?
    private(set) var activeAlbum: AlbumContent?
    private(set) var pageIndex = 0
    private(set) var isLoadingPage = false
    private(set) var hasUnavailablePhotos = false
    var isReading: Bool { activeAlbum != nil }
    var pageCount: Int { pages.count }
    var canGoBack: Bool { pageIndex > 0 }
    var canGoForward: Bool { pageIndex < pages.count }

    @ObservationIgnored private var prototype: Entity?
    @ObservationIgnored private weak var camera: Entity?
    @ObservationIgnored private weak var box: Entity?
    @ObservationIgnored private var boxWasEnabled = true
    @ObservationIgnored private var tray: Entity?
    @ObservationIgnored private var albumEntities: [String: Entity] = [:]
    @ObservationIgnored private var albumHomes: [String: SIMD3<Float>] = [:]
    @ObservationIgnored private var book: Entity?
    @ObservationIgnored private var bookCover: Entity?
    @ObservationIgnored private var pageRoot: Entity?
    @ObservationIgnored private var photoSurface: ModelEntity?
    @ObservationIgnored private var pageTask: Task<Void, Never>?
    @ObservationIgnored private var pageLoadID = UUID()
    @ObservationIgnored private var pageImages: [UIImage?] = []
    @ObservationIgnored private var pages: [PhotoPage] = []
    @ObservationIgnored private var rememberedPages: [String: Int] = [:]
    @ObservationIgnored private var rememberedSelections: [String: String] = [:]
    @ObservationIgnored private var viewport = CGSize.zero
    @ObservationIgnored private var thumbnails = PhotoThumbnailCache()

    func attach(prototype: Entity, camera: Entity) {
        clearAlbums()
        self.prototype = prototype
        self.camera = camera
        isPrepared = true
    }

    func showAlbums(_ content: [AlbumContent], in box: Entity, bounds: BoundingBox) {
        guard isPrepared else { return }
        if self.box === box, albums == content { return }
        clearAlbums()
        self.box = box
        albums = content.filter { !$0.photos.isEmpty }
        guard !albums.isEmpty else { return }

        let tray = Entity()
        tray.name = "TemporaryMonthlyAlbums"
        box.addChild(tray)
        self.tray = tray
        let columns = min(albums.count, 3)
        let rows = (albums.count + columns - 1) / columns
        let cellWidth = bounds.extents.y * 0.84 / Float(columns)
        let cellHeight = bounds.extents.x * 0.84 / Float(rows)
        for (index, album) in albums.enumerated() {
            let entity = makeCover()
            entity.name = "TemporaryAlbum.\(album.id)"
            let scale = min(cellWidth / GalleryConfig.albumCoverWidth,
                            cellHeight / GalleryConfig.albumPageHeight) * 0.82
            entity.scale = SIMD3(repeating: scale)
            entity.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 0, 1])
            entity.position = [
                bounds.center.x + (Float(rows - 1) / 2 - Float(index / columns)) * cellHeight,
                bounds.center.y + (Float(columns - 1) / 2 - Float(index % columns)) * cellWidth,
                bounds.max.z - 0.055
            ]
            entity.components.set(CollisionComponent(shapes: [
                .generateBox(size: [GalleryConfig.albumCoverWidth, GalleryConfig.albumPageHeight, 0.065])
            ]))
            entity.components.set(InputTargetComponent())
            tray.addChild(entity)
            albumEntities[album.id] = entity
            albumHomes[album.id] = entity.position
        }
        if let saved = rememberedSelections[box.name], albums.contains(where: { $0.id == saved }) {
            selectedAlbumID = saved
            updateHighlight()
        }
    }

    func albumID(containing entity: Entity) -> String? {
        var current: Entity? = entity
        while let candidate = current {
            if let match = albumEntities.first(where: { $0.value === candidate }) { return match.key }
            current = candidate.parent
        }
        return nil
    }

    func select(_ id: String) {
        guard !isReading, let album = albums.first(where: { $0.id == id }) else { return }
        if selectedAlbumID == id {
            open(album)
        } else {
            selectedAlbumID = id
            if let box { rememberedSelections[box.name] = id }
            updateHighlight()
        }
    }

    func updateViewport(_ size: CGSize) {
        viewport = size
        frameBook()
    }

    func turnPage(by delta: Int) {
        guard isReading else { return }
        let next = min(max(pageIndex + delta, 0), pages.count)
        guard next != pageIndex else { return }
        pageIndex = next
        rememberPage()
        loadPage()
    }

    func retryPage() { if isReading { loadPage() } }

    func closeBook() {
        rememberPage()
        pageTask?.cancel()
        pageLoadID = UUID()
        pageImages = []
        pageTask = nil
        if isReading { box?.isEnabled = boxWasEnabled }
        book?.removeFromParent()
        book = nil
        bookCover = nil
        pageRoot = nil
        photoSurface = nil
        activeAlbum = nil
        pages = []
        pageIndex = 0
        isLoadingPage = false
        hasUnavailablePhotos = false
    }

    func clearAlbums() {
        closeBook()
        tray?.removeFromParent()
        tray = nil
        box = nil
        albums = []
        selectedAlbumID = nil
        albumEntities.removeAll()
        albumHomes.removeAll()
    }

    private func updateHighlight() {
        for (id, entity) in albumEntities {
            guard let home = albumHomes[id] else { continue }
            entity.position = home + SIMD3<Float>(0, 0, id == selectedAlbumID ? 0.045 : 0)
        }
    }

    private func open(_ album: AlbumContent) {
        guard let camera, let box else { return }
        activeAlbum = album
        pages = PhotoPage.paginate(album.photos)
        pageIndex = min(rememberedPages[album.id, default: 0], pages.count)
        boxWasEnabled = box.isEnabled
        box.isEnabled = false
        let book = Entity()
        book.name = "TemporaryPhotoBook"
        camera.addChild(book)
        self.book = book
        let cover = makeCover()
        book.addChild(cover)
        bookCover = cover

        let pageRoot = Entity()
        let paper = ModelEntity(mesh: .generateBox(size: [GalleryConfig.albumCoverWidth, GalleryConfig.albumPageHeight, 0.012]),
                                materials: [SimpleMaterial(color: .init(white: 0.9, alpha: 1), roughness: 1, isMetallic: false)])
        pageRoot.addChild(paper)
        let surface = ModelEntity(mesh: .generatePlane(width: GalleryConfig.albumCoverWidth, height: GalleryConfig.albumPageHeight),
                                  materials: [UnlitMaterial(color: .white)])
        surface.position.z = 0.007
        pageRoot.addChild(surface)
        book.addChild(pageRoot)
        self.pageRoot = pageRoot
        photoSurface = surface
        frameBook()
        loadPage()
    }

    private func makeCover() -> Entity {
        let wrapper = Entity()
        guard let model = prototype?.clone(recursive: true) else { return wrapper }
        // albumteste's local geometry is XY with a Z thickness. Remove the
        // exported root-axis conversion, then center its offset mesh.
        model.transform = Transform()
        removeInteraction(from: model)
        let bounds = model.visualBounds(relativeTo: model)
        let scale = min(GalleryConfig.albumCoverWidth / max(bounds.extents.x, 0.001),
                        GalleryConfig.albumPageHeight / max(bounds.extents.y, 0.001))
        model.scale = SIMD3(repeating: scale)
        model.position = -bounds.center * scale
        wrapper.addChild(model)
        return wrapper
    }

    private func removeInteraction(from entity: Entity) {
        entity.components.remove(CollisionComponent.self)
        entity.components.remove(InputTargetComponent.self)
        entity.components.remove(PerspectiveCameraComponent.self)
        entity.components.remove(OrthographicCameraComponent.self)
        entity.components.remove(DirectionalLightComponent.self)
        entity.components.remove(PointLightComponent.self)
        entity.components.remove(SpotLightComponent.self)
        for child in entity.children { removeInteraction(from: child) }
    }

    private func frameBook() {
        guard let book, let camera else { return }
        let fov = camera.components[PerspectiveCameraComponent.self]?.fieldOfViewInDegrees ?? 50.2
        let distance = GalleryConfig.albumViewingDistance
        let height = 2 * distance * tan(fov * .pi / 360)
        let aspect = Float(viewport.width / max(viewport.height, 1))
        let scale = min(height * max(aspect, 0.25) * 0.82 / GalleryConfig.albumCoverWidth,
                        height * 0.65 / GalleryConfig.albumPageHeight)
        book.scale = SIMD3(repeating: scale)
        book.position = [0, -height * 0.025, -distance]
    }

    private func rememberPage() {
        if let album = activeAlbum { rememberedPages[album.id] = pageIndex }
    }

    private func loadPage() {
        pageTask?.cancel()
        pageLoadID = UUID()
        let loadID = pageLoadID
        pageImages = []
        bookCover?.isEnabled = pageIndex == 0
        pageRoot?.isEnabled = pageIndex > 0
        isLoadingPage = false
        hasUnavailablePhotos = false
        guard pageIndex > 0, pages.indices.contains(pageIndex - 1), let album = activeAlbum else { return }
        let page = pages[pageIndex - 1]
        pageImages = Array(repeating: nil, count: page.photos.count)
        let requestedIndex = pageIndex
        isLoadingPage = true
        setPageTexture(PhotoPageRenderer.image(title: album.title, page: page, images: [], loading: true))
        pageTask = Task { [weak self] in
            guard let self else { return }
            async let first = self.pageThumbnail(for: page.photos.first, slot: 0, page: page, title: album.title, loadID: loadID)
            async let second = self.pageThumbnail(for: page.photos.count > 1 ? page.photos[1] : nil,
                                                 slot: 1, page: page, title: album.title, loadID: loadID)
            let loaded = await (first, second)
            guard !Task.isCancelled, self.pageLoadID == loadID,
                  self.activeAlbum?.id == album.id, self.pageIndex == requestedIndex else { return }
            let images: [UIImage?] = page.photos.count > 1 ? [loaded.0, loaded.1] : [loaded.0]
            self.hasUnavailablePhotos = images.contains(where: { $0 == nil })
            // Keep any preview if a final-quality iCloud request times out.
            self.setPageTexture(PhotoPageRenderer.image(title: album.title, page: page, images: self.pageImages, loading: false))
            self.isLoadingPage = false
        }
    }

    private func pageThumbnail(for photo: PhotoReference?, slot: Int, page: PhotoPage, title: String, loadID: UUID) async -> UIImage? {
        guard let photo else { return nil }
        return await thumbnails.thumbnail(for: photo.id, targetSize: GalleryConfig.albumPhotoTargetSize) { [weak self] image in
            guard let self, self.pageLoadID == loadID, self.pageImages.indices.contains(slot) else { return }
            self.pageImages[slot] = image
            self.setPageTexture(PhotoPageRenderer.image(title: title, page: page, images: self.pageImages, loading: true))
        }
    }

    private func setPageTexture(_ image: UIImage) {
        guard let cgImage = image.cgImage, let surface = photoSurface else { return }
        do {
            let texture = try TextureResource(image: cgImage, options: .init(semantic: .color))
            var material = UnlitMaterial()
            material.color = .init(tint: .white, texture: .init(texture))
            surface.model?.materials = [material]
        } catch {
            hasUnavailablePhotos = true
            print("Could not create photo page texture: \(error)")
        }
    }
}
