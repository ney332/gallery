import Observation
import RealityKit
import UIKit

/// Monthly albums, photo loading and bounded navigation through a reusable page rig.
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
    private(set) var isTurningPage = false
    var canGoBack: Bool { !isTurningPage && pageIndex > 0 }
    var canGoForward: Bool { !isTurningPage && pageIndex < pages.count }

    @ObservationIgnored private var prototype: Entity?
    @ObservationIgnored private weak var camera: Entity?
    @ObservationIgnored private weak var box: Entity?
    @ObservationIgnored private var boxWasEnabled = true
    @ObservationIgnored private var tray: Entity?
    @ObservationIgnored private var albumEntities: [String: Entity] = [:]
    @ObservationIgnored private var albumHomes: [String: SIMD3<Float>] = [:]
    @ObservationIgnored private var book: Entity?
    @ObservationIgnored private var animationRig: AlbumAnimationController?
    @ObservationIgnored private var turnTask: Task<Void, Never>?
    @ObservationIgnored private var pageTask: Task<Void, Never>?
    @ObservationIgnored private var readingSessionID = UUID()
    @ObservationIgnored private var pageCache = AlbumPageCache()
    @ObservationIgnored private var pendingContent: [AlbumContent]?
    @ObservationIgnored private var boxBounds: BoundingBox?
    @ObservationIgnored private var failedTurnTarget: Int?
    @ObservationIgnored private var pages: [PhotoPage] = []
    @ObservationIgnored private var rememberedPages: [String: Int] = [:]
    @ObservationIgnored private var rememberedSelections: [String: String] = [:]
    @ObservationIgnored private var viewport = CGSize.zero

    func attach(prototype: Entity, camera: Entity) {
        clearAlbums()
        self.prototype = prototype
        self.camera = camera
        isPrepared = true
    }

    func showAlbums(_ content: [AlbumContent], in box: Entity, bounds: BoundingBox) {
        guard isPrepared else { return }
        if self.box === box, albums == content {
            pendingContent = nil
            return
        }
        if self.box === box, isReading, !content.isEmpty {
            // A PhotoKit refresh must not dismantle the book during reading.
            pendingContent = content
            return
        }
        clearAlbums()
        self.box = box
        boxBounds = bounds
        albums = content.filter { !$0.photos.isEmpty }
        guard !albums.isEmpty else { return }

        let tray = Entity()
        tray.name = "MonthlyAlbums"
        box.addChild(tray)
        self.tray = tray
        let sample = makeCover().visualBounds(relativeTo: nil)
        let thickness = max(sample.extents.z, 0.005)
        let slotWidth = bounds.extents.y * 0.86 / Float(max(12, albums.count))
        let scale = min(bounds.extents.x * 0.86 / max(sample.extents.y, 0.001),
                        bounds.extents.z * 0.84 / max(sample.extents.x, 0.001),
                        slotWidth * 0.9 / thickness)
        let spacing = thickness * scale + slotWidth * 0.1
        // Box local +Y points screen-left; +Z is up. Put the spine on top,
        // the long edge along box X and the thickness along box Y.
        let orientation = simd_quatf(simd_float3x3(columns: (
            SIMD3<Float>(0, 0, -1), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, -1, 0)
        )))
        for (index, album) in albums.enumerated() {
            let entity = makeCover()
            entity.name = "MonthlyAlbum.\(album.id)"
            entity.scale = SIMD3(repeating: scale)
            entity.orientation = orientation
            entity.position = [
                bounds.center.x,
                bounds.center.y + (Float(albums.count - 1) / 2 - Float(index)) * spacing,
                bounds.min.z + bounds.extents.z * 0.08 + sample.extents.x * scale / 2
            ]
            entity.components.set(CollisionComponent(shapes: [
                .generateBox(size: sample.extents)
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
        guard viewport != size else { return }
        viewport = size
        frameBook()
    }

    func turnPage(by delta: Int) {
        guard isReading, !isTurningPage, delta != 0, let rig = animationRig else { return }
        let direction = delta > 0 ? 1 : -1
        let next = min(max(pageIndex + direction, 0), pages.count)
        guard next != pageIndex else { return }
        let previous = pageIndex
        let session = readingSessionID
        failedTurnTarget = nil
        pageTask?.cancel()
        isTurningPage = true
        pageCache.keepWindow(around: next)
        isLoadingPage = next > 0 && pageCache.materials(at: next) == nil
        turnTask = Task { [weak self] in
            guard let self else { return }
            // Keep the current photos, geometry and camera framing visible while
            // waiting for the target. A ready cached spread needs no PhotoKit wait.
            let materials = next > 0 ? await self.pageCache.preparedMaterials(at: next) : nil
            guard !Task.isCancelled, self.readingSessionID == session else { return }
            self.isLoadingPage = false
            if next > 0 && materials == nil {
                self.failedTurnTarget = next
                self.hasUnavailablePhotos = true
                self.isTurningPage = false
                self.turnTask = nil
                return
            }
            self.pageCache.setAnimationActive(true)
            if previous > 0 && next > 0 { rig.beginTurn(by: direction) }
            if let materials { rig.setPhotos(materials) }
            if previous == 0 || next == 0 {
                // Framing changes only when opening/closing the cover.
                self.frameBook(open: next > 0, animated: true)
                await rig.animateCover(open: next > 0)
            } else {
                await rig.animateTurn()
            }
            guard !Task.isCancelled, self.readingSessionID == session else { return }
            self.pageIndex = next
            self.rememberPage()
            self.isTurningPage = false
            self.turnTask = nil
            self.pageCache.setAnimationActive(false)
            self.applyPreparedPage(next)
            self.pageCache.keepWindow(around: next)
        }
    }

    func retryPage() {
        guard isReading, !isTurningPage else { return }
        if let target = failedTurnTarget {
            pageCache.retry(target)
            turnPage(by: target - pageIndex)
            return
        }
        guard pageIndex > 0 else { return }
        pageCache.retry(pageIndex)
        loadPage()
    }

    func closeBook() {
        rememberPage()
        turnTask?.cancel()
        turnTask = nil
        isTurningPage = false
        failedTurnTarget = nil
        book?.stopAllAnimations(recursive: true)
        pageTask?.cancel()
        readingSessionID = UUID()
        pageCache.clear()
        pageTask = nil
        if isReading { box?.isEnabled = boxWasEnabled }
        book?.removeFromParent()
        book = nil
        animationRig = nil
        activeAlbum = nil
        pages = []
        pageIndex = 0
        isLoadingPage = false
        hasUnavailablePhotos = false
        if let content = pendingContent, let box, let bounds = boxBounds {
            pendingContent = nil
            showAlbums(content, in: box, bounds: bounds)
        }
    }

    func clearAlbums() {
        pendingContent = nil
        closeBook()
        tray?.removeFromParent()
        tray = nil
        box = nil
        boxBounds = nil
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
        guard let camera, let box, let prototype else { return }
        activeAlbum = album
        readingSessionID = UUID()
        pages = PhotoPage.paginate(album.photos)
        pageCache.configure(title: album.title, pages: pages)
        pageCache.onUpdate = { [weak self] index in self?.applyPreparedPage(index) }
        pageIndex = min(rememberedPages[album.id, default: 0], pages.count)
        boxWasEnabled = box.isEnabled
        box.isEnabled = false
        let rig = AlbumAnimationController(prototype: prototype)
        animationRig = rig
        let book = Entity()
        book.name = "PhotoAlbum"
        camera.addChild(book)
        book.addChild(rig.root)
        self.book = book
        rig.setOpen(pageIndex > 0)
        frameBook()
        loadPage()
    }

    private func makeCover() -> Entity {
        guard let prototype else { return Entity() }
        return AlbumAnimationController.normalizedModel(from: prototype)
    }

    private func frameBook(open: Bool? = nil, animated: Bool = false) {
        guard let book, let camera, let rig = animationRig else { return }
        let fov = camera.components[PerspectiveCameraComponent.self]?.fieldOfViewInDegrees ?? 50.2
        let distance = GalleryConfig.albumViewingDistance
        let height = 2 * distance * tan(fov * .pi / 360)
        let aspect = Float(viewport.width / max(viewport.height, 1))
        let isOpen = open ?? (pageIndex > 0)
        let width = isOpen ? rig.readingWidth : rig.closedBounds.extents.x
        let scale = min(height * max(aspect, 0.25) * 0.82 / max(width, 0.001),
                        height * 0.65 / GalleryConfig.albumPageHeight)
        let center = isOpen ? rig.readingCenter : SIMD3<Float>.zero
        let destination = Transform(scale: SIMD3(repeating: scale), rotation: simd_quatf(angle: 0, axis: [0, 1, 0]),
                                    translation: SIMD3<Float>(0, -height * 0.025, -distance) - center * scale)
        if animated {
            book.move(to: destination, relativeTo: camera,
                      duration: GalleryConfig.albumCoverOpenDuration, timingFunction: .easeInOut)
        } else {
            book.transform = destination
        }
    }

    private func rememberPage() {
        if let album = activeAlbum { rememberedPages[album.id] = pageIndex }
    }

    private func loadPage() {
        pageTask?.cancel()
        pageCache.keepWindow(around: pageIndex)
        guard pageIndex > 0 else {
            isLoadingPage = false
            hasUnavailablePhotos = false
            return
        }
        if pageCache.materials(at: pageIndex) != nil {
            applyPreparedPage(pageIndex)
            return
        }
        isLoadingPage = true
        let index = pageIndex
        let session = readingSessionID
        pageTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.pageCache.preparedMaterials(at: index)
            guard !Task.isCancelled, self.readingSessionID == session, self.pageIndex == index else { return }
            self.isLoadingPage = false
            self.applyPreparedPage(index)
        }
    }

    private func applyPreparedPage(_ index: Int) {
        guard isReading, !isTurningPage, index == pageIndex, index > 0 else { return }
        if let materials = pageCache.materials(at: index) {
            animationRig?.setPhotos(materials)
            isLoadingPage = false
        }
        hasUnavailablePhotos = pageCache.hasUnavailablePhotos(at: index)
    }
}
