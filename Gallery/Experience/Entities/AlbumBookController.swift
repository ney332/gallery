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
    enum Phase { case idle, entering, reading, preparing, dragging, settling, returning }
    private(set) var phase: Phase = .idle
    var isTurningPage: Bool { phase == .preparing || phase == .dragging || phase == .settling }
    var canGoBack: Bool { !isTurningPage && pageIndex > 0 }
    var canGoForward: Bool { !isTurningPage && pageIndex < pages.count }

    @ObservationIgnored private var transitionTask: Task<Void, Never>?
    @ObservationIgnored private var turnID = UUID()
    @ObservationIgnored private var turnTarget = 0
    @ObservationIgnored private var turnDirection = 0
    @ObservationIgnored private var dragProgress: Float = 0
    @ObservationIgnored private var commitWhenPrepared = false
    @ObservationIgnored private var outgoingMaterials: AlbumPageMaterials?
    @ObservationIgnored private weak var sourceAlbum: Entity?
    @ObservationIgnored private var travelModel: Entity?
    @ObservationIgnored private var extractionPose: Transform?
    @ObservationIgnored private var approachPose: Transform?
    @ObservationIgnored private var hasClearedBox = false
    @ObservationIgnored private var prototype: Entity?
    @ObservationIgnored private weak var camera: Entity?
    @ObservationIgnored private weak var box: Entity?
    @ObservationIgnored private var boxWasEnabled = true
    @ObservationIgnored private var tray: Entity?
    @ObservationIgnored private var albumEntities: [String: Entity] = [:]
    @ObservationIgnored private var albumHomes: [String: SIMD3<Float>] = [:]
    @ObservationIgnored private var albumCollisions: [String: CollisionComponent] = [:]
    @ObservationIgnored private var interactionEnabled = false
    @ObservationIgnored private var book: Entity?
    @ObservationIgnored private var animationRig: AlbumAnimationController?
    @ObservationIgnored private var turnTask: Task<Void, Never>?
    @ObservationIgnored private var pageTask: Task<Void, Never>?
    @ObservationIgnored private var readingSessionID = UUID()
    @ObservationIgnored private var pageCache = AlbumPageCache()
    @ObservationIgnored private var cachedAlbum: AlbumContent?
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
        let slotWidth = bounds.extents.y * 0.94 / Float(max(12, albums.count))
        // Preserve the cover's proportions while fitting thickness separately:
        // twelve slots must not shrink the whole album.
        let bodyScale = min(bounds.extents.x * 0.94 / max(sample.extents.y, 0.001),
                            bounds.extents.z * 0.90 / max(sample.extents.x, 0.001))
        let thicknessScale = min(bodyScale, slotWidth * 0.94 / thickness)
        let spacing = thickness * thicknessScale + slotWidth * 0.06
        let albumScale = SIMD3<Float>(bodyScale, bodyScale, thicknessScale)
        let bottomInset = bounds.extents.z * 0.04
        // Box local +Y points screen-left; +Z is up. Put the spine on top,
        // the long edge along box X and the thickness along box Y.
        let orientation = simd_quatf(simd_float3x3(columns: (
            SIMD3<Float>(0, 0, -1), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, -1, 0)
        )))
        for (index, album) in albums.enumerated() {
            let entity = makeCover()
            entity.name = "MonthlyAlbum.\(album.id)"
            entity.scale = albumScale
            entity.orientation = orientation
            entity.position = [
                bounds.center.x,
                bounds.center.y + (Float(albums.count - 1) / 2 - Float(index)) * spacing,
                bounds.min.z + bottomInset + sample.extents.x * bodyScale / 2
            ]
            // Geometry is ready inside the closed box; hit targets are enabled
            // only after both flaps finish opening.
            albumCollisions[album.id] = CollisionComponent(shapes: [
                .generateBox(size: sample.extents)
            ])
            tray.addChild(entity)
            albumEntities[album.id] = entity
            albumHomes[album.id] = entity.position
        }
        if let saved = rememberedSelections[box.name], albums.contains(where: { $0.id == saved }) {
            selectedAlbumID = saved
            updateHighlight()
        }
    }

    func setInteractionEnabled(_ enabled: Bool) {
        interactionEnabled = enabled
        for (id, entity) in albumEntities {
            if enabled, let collision = albumCollisions[id] {
                entity.components.set(collision)
                entity.components.set(InputTargetComponent())
            } else {
                entity.components.remove(CollisionComponent.self)
                entity.components.remove(InputTargetComponent.self)
            }
        }
        updateHighlight()
    }

    func albumID(containing entity: Entity) -> String? {
        guard interactionEnabled else { return nil }
        var current: Entity? = entity
        while let candidate = current {
            if let match = albumEntities.first(where: { $0.value === candidate }) { return match.key }
            current = candidate.parent
        }
        return nil
    }

    func photoID(containing entity: Entity) -> String? {
        guard phase == .reading, pageIndex > 0, pages.indices.contains(pageIndex - 1),
              let slot = animationRig?.photoSlot(containing: entity),
              let photoIndex = pages[pageIndex - 1].photoIndex(forSlot: slot),
              pages[pageIndex - 1].photos.indices.contains(photoIndex) else { return nil }
        return pages[pageIndex - 1].photos[photoIndex].id
    }

    func select(_ id: String) {
        guard interactionEnabled, !isReading, let album = albums.first(where: { $0.id == id }) else { return }
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
        if phase == .reading { frameBook() }
        else if phase == .dragging || phase == .preparing { cancelPageDrag() }
    }

    func updatePageDrag(translation: CGSize) {
        if phase == .reading {
            guard abs(translation.width) >= 8,
                  abs(translation.width) > abs(translation.height) else { return }
            beginTurn(by: translation.width < 0 ? 1 : -1)
        }
        guard phase == .preparing || phase == .dragging else { return }
        let distance = max(viewport.width * GalleryConfig.albumDragWidthFraction, 100)
        dragProgress = min(max(Float(-translation.width * CGFloat(turnDirection) / distance), 0), 1)
        if phase == .dragging { updateTurnPose() }
    }

    func endPageDrag(predictedTranslation: CGSize) {
        let distance = max(viewport.width * GalleryConfig.albumDragWidthFraction, 100)
        let predicted = Float(-predictedTranslation.width * CGFloat(turnDirection) / distance)
        let commit = dragProgress >= GalleryConfig.albumTurnCommitProgress
            || (dragProgress > 0.08 && predicted >= 0.65)
        if phase == .preparing {
            // Keep a completed user gesture while the target spread finishes
            // loading. The page turn starts as soon as its textures are ready.
            commitWhenPrepared = commit
            if !commit { cancelPageDrag() }
            return
        }
        guard phase == .dragging else { return }
        settleTurn(commit: commit)
    }

    func cancelPageDrag() {
        if phase == .dragging {
            settleTurn(commit: false)
        } else if phase == .preparing {
            commitWhenPrepared = false
            turnID = UUID()
            turnTask?.cancel()
            turnTask = nil
            phase = .reading
            outgoingMaterials = nil
            isLoadingPage = false
            pageCache.keepWindow(around: pageIndex)
            loadPage()
        }
    }

    func turnPage(by delta: Int) {
        beginTurn(by: delta, automaticallyComplete: true)
    }

    private func beginTurn(by delta: Int, automaticallyComplete: Bool = false) {
        guard phase == .reading, delta != 0, let rig = animationRig else { return }
        let direction = delta > 0 ? 1 : -1
        let next = min(max(pageIndex + direction, 0), pages.count)
        guard next != pageIndex else { return }
        // Never turn an outgoing spread that is still being prepared.
        guard pageIndex == 0 || pageCache.materials(at: pageIndex) != nil else { return }
        failedTurnTarget = nil
        pageTask?.cancel()
        turnTarget = next
        turnDirection = direction
        dragProgress = 0
        commitWhenPrepared = automaticallyComplete
        outgoingMaterials = pageCache.materials(at: pageIndex)
        turnID = UUID()
        let token = turnID
        let session = readingSessionID
        phase = .preparing
        pageCache.keepWindow(around: pageIndex)
        isLoadingPage = next > 0 && pageCache.materials(at: next) == nil

        func prepare(_ materials: AlbumPageMaterials?) {
            isLoadingPage = false
            if next > 0 && materials == nil {
                failedTurnTarget = next
                hasUnavailablePhotos = true
                phase = .reading
                return
            }
            pageCache.setAnimationActive(true)
            if pageIndex > 0 && next > 0 { rig.beginTurn(by: direction) }
            if let materials { rig.setPhotos(materials) }
            phase = .dragging
            updateTurnPose()
            if self.commitWhenPrepared { settleTurn(commit: true) }
        }

        if next == 0 || pageCache.materials(at: next) != nil {
            prepare(pageCache.materials(at: next))
        } else {
            turnTask = Task { [weak self] in
                guard let self else { return }
                let materials = await self.pageCache.preparedMaterials(at: next)
                guard !Task.isCancelled, self.readingSessionID == session,
                      self.turnID == token, self.phase == .preparing else { return }
                prepare(materials)
            }
        }
    }

    private func updateTurnPose() {
        if pageIndex == 0 || turnTarget == 0 {
            let amount = pageIndex == 0 ? dragProgress : 1 - dragProgress
            animationRig?.setCoverProgress(amount)
            frameCoverProgress(amount)
        } else {
            animationRig?.setTurnProgress(dragProgress)
        }
    }

    private func settleTurn(commit: Bool) {
        guard phase == .dragging, let rig = animationRig else { return }
        phase = .settling
        commitWhenPrepared = false
        let session = readingSessionID
        let token = turnID
        let target = commit ? turnTarget : pageIndex
        let progress = dragProgress
        let original = outgoingMaterials
        turnTask = Task { [weak self] in
            guard let self else { return }
            if self.pageIndex == 0 || self.turnTarget == 0 {
                self.frameBook(open: target > 0, animated: true)
                await rig.animateCover(open: target > 0)
                if !commit, let original { rig.setPhotos(original) }
            } else {
                await rig.finishTurn(commit: commit, progress: progress, original: original)
            }
            guard !Task.isCancelled, self.readingSessionID == session, self.turnID == token else { return }
            self.pageIndex = target
            self.rememberPage()
            self.phase = .reading
            self.turnTask = nil
            self.outgoingMaterials = nil
            self.pageCache.setAnimationActive(false)
            self.pageCache.keepWindow(around: target)
            self.applyPreparedPage(target)
            self.frameBook()
        }
    }

    func retryPage() {
        guard phase == .reading else { return }
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
        guard isReading, phase != .returning, let book, let camera, let rig = animationRig else { return }
        rememberPage()
        transitionTask?.cancel()
        turnTask?.cancel()
        pageTask?.cancel()
        readingSessionID = UUID()
        let session = readingSessionID
        turnID = UUID()
        phase = .returning
        book.stopAllAnimations(recursive: true)
        rig.resetTurn(materials: pageCache.materials(at: pageIndex))
        pageCache.clear()
        cachedAlbum = nil
        isLoadingPage = false
        hasUnavailablePhotos = false
        transitionTask = Task { [weak self] in
            guard let self else { return }
            if rig.root.isEnabled { await rig.animateCover(open: false) }
            guard !Task.isCancelled, self.readingSessionID == session else { return }
            rig.root.isEnabled = false
            self.travelModel?.isEnabled = true
            self.box?.isEnabled = self.boxWasEnabled
            if let source = self.sourceAlbum {
                if self.hasClearedBox {
                    if let approach = self.approachPose {
                        await rig.move(book, to: approach, relativeTo: camera, duration: 0.2)
                        guard !Task.isCancelled, self.readingSessionID == session else { return }
                    }
                    if let extraction = self.extractionPose {
                        await rig.move(book, to: extraction, relativeTo: camera,
                                       duration: GalleryConfig.albumTravelDuration)
                        guard !Task.isCancelled, self.readingSessionID == session else { return }
                    }
                }
                // Return to the original parent before inserting. Keeping the
                // slot's local transform avoids decomposing its nonuniform scale
                // next to the walls of the box.
                if let parent = source.parent {
                    book.setParent(parent, preservingWorldTransform: true)
                    var aligned = source.transform
                    aligned.translation = book.position
                    book.transform = aligned
                    await rig.move(book, to: source.transform, relativeTo: parent,
                                   duration: GalleryConfig.albumExtractionDuration)
                }
            }
            guard !Task.isCancelled, self.readingSessionID == session else { return }
            self.transitionTask = nil
            self.removeBook()
        }
    }

    private func removeBook() {
        rememberPage()
        turnTask?.cancel()
        turnTask = nil
        transitionTask?.cancel()
        transitionTask = nil
        turnID = UUID()
        phase = .idle
        commitWhenPrepared = false
        outgoingMaterials = nil
        failedTurnTarget = nil
        book?.stopAllAnimations(recursive: true)
        pageTask?.cancel()
        readingSessionID = UUID()
        pageCache.clear()
        cachedAlbum = nil
        pageTask = nil
        if isReading { box?.isEnabled = boxWasEnabled }
        sourceAlbum?.isEnabled = true
        sourceAlbum = nil
        travelModel = nil
        extractionPose = nil
        approachPose = nil
        hasClearedBox = false
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
            let wasInteractive = interactionEnabled
            showAlbums(content, in: box, bounds: bounds)
            setInteractionEnabled(wasInteractive)
        }
    }

    func clearAlbums() {
        pendingContent = nil
        removeBook()
        tray?.removeFromParent()
        tray = nil
        box = nil
        boxBounds = nil
        albums = []
        selectedAlbumID = nil
        albumEntities.removeAll()
        albumHomes.removeAll()
        albumCollisions.removeAll()
        interactionEnabled = false
    }

    private func updateHighlight() {
        for (id, entity) in albumEntities {
            guard let home = albumHomes[id] else { continue }
            entity.position = home + SIMD3<Float>(0, 0, interactionEnabled && id == selectedAlbumID ? 0.045 : 0)
        }
    }

    /// Opening prioritizes the initial spread. As soon as it is prepared,
    /// warm its neighbors during the remaining flight/cover animation.
    private func prepareAlbum(_ album: AlbumContent) {
        guard cachedAlbum != album else { return }
        pages = PhotoPage.paginate(album.photos)
        pageCache.configure(title: album.title, pages: pages)
        cachedAlbum = album
        pageCache.onUpdate = { [weak self] index in
            guard let self else { return }
            let initialPage = max(1, self.pageIndex)
            if self.phase == .entering, self.pageCache.materials(at: initialPage) != nil {
                self.pageCache.keepWindow(around: initialPage)
            }
            self.applyPreparedPage(index)
        }
        let initialPage = min(rememberedPages[album.id, default: 1], pages.count)
        pageCache.keepWindow(around: max(1, initialPage), includeNeighbors: false)
    }

    private func open(_ album: AlbumContent) {
        guard let camera, let box, let prototype, let source = albumEntities[album.id] else { return }
        activeAlbum = album
        phase = .entering
        readingSessionID = UUID()
        let session = readingSessionID
        prepareAlbum(album)
        pageIndex = min(rememberedPages[album.id, default: 1], pages.count)
        boxWasEnabled = box.isEnabled
        sourceAlbum = source
        let rig = AlbumAnimationController(prototype: prototype)
        animationRig = rig
        let book = Entity()
        book.name = "PhotoAlbum"
        // Start in exactly the same parent/pose as the visible slot model.
        // Do not convert a thin, nonuniformly scaled album to camera space
        // while it is still inside the box.
        guard let slotParent = source.parent else { return }
        slotParent.addChild(book)
        book.transform = source.transform
        let travel = makeCover()
        book.addChild(travel)
        travelModel = travel
        book.addChild(rig.root)
        rig.root.isEnabled = false
        source.isEnabled = false
        self.book = book
        rig.setOpen(false)
        hasClearedBox = false
        configureExtractionPath(source: Transform(matrix: book.transformMatrix(relativeTo: camera)), rig: rig)
        transitionTask = Task { [weak self] in
            guard let self, let destination = self.bookPose(open: false) else { return }
            if let extraction = self.extractionPose {
                // Keep the album upright and at its slot scale until its entire
                // body is above the rim; only then rotate towards the reader.
                var localExtraction = book.transform
                let cameraToSlot = camera.transformMatrix(relativeTo: slotParent)
                let point = cameraToSlot * SIMD4<Float>(extraction.translation.x, extraction.translation.y,
                                                       extraction.translation.z, 1)
                localExtraction.translation = SIMD3<Float>(point.x, point.y, point.z)
                await rig.move(book, to: localExtraction, relativeTo: slotParent,
                               duration: GalleryConfig.albumExtractionDuration)
                guard !Task.isCancelled, self.readingSessionID == session else { return }
                self.hasClearedBox = true
                book.setParent(camera, preservingWorldTransform: true)
            }
            await rig.move(book, to: self.approachPose ?? destination, relativeTo: camera,
                           duration: GalleryConfig.albumTravelDuration)
            guard !Task.isCancelled, self.readingSessionID == session else { return }
            await rig.move(book, to: destination, relativeTo: camera, duration: 0.2)
            guard !Task.isCancelled, self.readingSessionID == session else { return }
            // Keep the box and remaining albums visible behind the book.
            travel.isEnabled = false
            rig.root.isEnabled = true
            if self.pageIndex > 0 {
                self.isLoadingPage = self.pageCache.materials(at: self.pageIndex) == nil
                let materials = await self.pageCache.preparedMaterials(at: self.pageIndex)
                guard !Task.isCancelled, self.readingSessionID == session else { return }
                if let materials { rig.setPhotos(materials) }
                self.isLoadingPage = false
                self.pageCache.setAnimationActive(true)
                self.frameBook(open: true, animated: true)
                await rig.animateCover(open: true)
                guard !Task.isCancelled, self.readingSessionID == session else { return }
            }
            self.phase = .reading
            self.transitionTask = nil
            self.pageCache.setAnimationActive(false)
            self.frameBook()
            self.loadPage()
        }
    }

    private func configureExtractionPath(source: Transform, rig: AlbumAnimationController) {
        guard let box, let camera, let bounds = boxBounds,
              let destination = bookPose(open: false) else { return }
        // The opening is box-local +Z (Blender axes), not camera/world Y.
        let boxToCamera = box.transformMatrix(relativeTo: camera)
        let axis = SIMD3<Float>(boxToCamera.columns.2.x, boxToCamera.columns.2.y, boxToCamera.columns.2.z)
        let normal = simd_normalize(axis)
        let rim4 = boxToCamera * SIMD4<Float>(bounds.center.x, bounds.center.y, bounds.max.z, 1)
        let rim = SIMD3<Float>(rim4.x, rim4.y, rim4.z)
        let sourceRadius = simd_length(rig.closedBounds.extents * source.scale) / 2
        let destinationRadius = simd_length(rig.closedBounds.extents * destination.scale) / 2
        // A bounding sphere clears the rim throughout the rotation/scale blend.
        let clearance = max(sourceRadius, destinationRadius)
            + bounds.extents.z * simd_length(axis) * 0.06
        func raised(_ pose: Transform) -> Transform {
            var result = pose
            let height = simd_dot(pose.translation - rim, normal)
            result.translation += normal * max(0, clearance - height)
            return result
        }
        extractionPose = raised(source)
        approachPose = raised(destination)
    }

    private func makeCover() -> Entity {
        guard let prototype else { return Entity() }
        return AlbumAnimationController.normalizedModel(from: prototype)
    }

    private func bookPose(open: Bool) -> Transform? {
        guard let camera, let rig = animationRig else { return nil }
        let fov = camera.components[PerspectiveCameraComponent.self]?.fieldOfViewInDegrees ?? 50.2
        let distance = GalleryConfig.albumViewingDistance
        let height = 2 * distance * tan(fov * .pi / 360)
        let aspect = Float(viewport.width / max(viewport.height, 1))
        let isOpen = open
        let width = isOpen ? rig.readingWidth : rig.closedBounds.extents.x
        let scale = min(height * max(aspect, 0.25) * 0.82 / max(width, 0.001),
                        height * 0.65 / GalleryConfig.albumPageHeight)
        let center = isOpen ? rig.readingCenter : SIMD3<Float>.zero
        return Transform(scale: SIMD3(repeating: scale), rotation: simd_quatf(angle: 0, axis: [0, 1, 0]),
                                    translation: SIMD3<Float>(0, -height * 0.025, -distance) - center * scale)
    }

    private func frameBook(open: Bool? = nil, animated: Bool = false) {
        guard let book, let camera, let destination = bookPose(open: open ?? (pageIndex > 0)) else { return }
        if animated {
            book.move(to: destination, relativeTo: camera,
                      duration: GalleryConfig.albumCoverOpenDuration, timingFunction: .easeInOut)
        } else {
            book.transform = destination
        }
    }

    private func frameCoverProgress(_ amount: Float) {
        guard let book, let closed = bookPose(open: false), let opened = bookPose(open: true) else { return }
        var pose = closed
        pose.scale = closed.scale + (opened.scale - closed.scale) * amount
        pose.translation = closed.translation + (opened.translation - closed.translation) * amount
        book.transform = pose
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
        guard phase == .reading, index == pageIndex, index > 0 else { return }
        if let materials = pageCache.materials(at: index) {
            animationRig?.setPhotos(materials)
            isLoadingPage = false
        }
        hasUnavailablePhotos = pageCache.hasUnavailablePhotos(at: index)
    }
}
