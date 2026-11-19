import RealityKit
import PencilKit
import SwiftUI

struct ContentView: View {
    let libraryModel: GalleryLibraryModel
    @State private var orbitController = OverviewOrbitController()
    @State private var scenarioAnimationController = ScenarioAnimationController()
    @State private var sceneLightingController = SceneLightingController()
    @State private var boxInteractionController: BoxInteractionController
    @State private var albumController = AlbumBookController()
    @State private var photoInteractionController = PhotoInteractionController()
    @State private var windowInteractionController = WindowInteractionController()
    @GestureState private var isPressingWindow = false
    @GestureState private var isPageGestureActive = false
    @GestureState private var isDrawerDragGestureActive = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var isDragging = false
    @State private var isDraggingPhotoCard = false
    @State private var isDraggingPhotoCardFromBack = false
    @State private var selectedPhotoMarkupTool: PhotoMarkupTool = .pen
    @State private var isPhotoMarkupToolbarExpanded = false
    @State private var photoDrawingData = Data()
    @State private var annotationSaveTask: Task<Void, Never>?
    @State private var annotationSaveFailed = false
    @State private var isLoadingAnnotation = false

    init(libraryModel: GalleryLibraryModel, boxSessionState: BoxSessionState) {
        self.libraryModel = libraryModel
        _boxInteractionController = State(initialValue: BoxInteractionController(session: boxSessionState))
    }

    var body: some View {
        GeometryReader { geometry in
            scene(viewportSize: geometry.size)
        }
            .ignoresSafeArea()
            .background(Color(red: 0.12, green: 0.10, blue: 0.09))
    }

    private func scene(viewportSize: CGSize) -> some View {
        RealityView { content in
            content.camera = .virtual
            let loader = BlenderAssetLoader(catalog: .main)
            let roomFallback = loader.fallback(for: .room)
            content.add(roomFallback)

            let camera = SceneCamera.makeOverviewCamera()
            content.add(camera)
            orbitController.attach(camera: camera, viewportSize: viewportSize)
            photoInteractionController.attach(camera: camera, viewportSize: viewportSize)

            let room = await loader.load(.room)
            
            albumController.clearAlbums()
            
            scenarioAnimationController.attach(to: room)
            
            windowInteractionController.attach(to: scenarioAnimationController.entity(for: .windowGlass))
            //controler de luz no ambiente 
            sceneLightingController.attach(to: room, preset: .afternoon)
            
            boxInteractionController.attach(to: room, camera: camera)
            
            roomFallback.removeFromParent()
            
            content.add(room)
            
            let albumPrototype = await loader.load(.albumCover)
            
            albumController.attach(prototype: albumPrototype, camera: camera)
            
            albumController.updateViewport(viewportSize)
        } update: { _ in
            orbitController.updateViewport(viewportSize)
            albumController.updateViewport(viewportSize)
            photoInteractionController.updateViewport(viewportSize)
        }
        .simultaneousGesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in handleEntityTap(value.entity, viewportSize: viewportSize) }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .targetedToAnyEntity()
                .updating($isPressingWindow) { value, state, _ in
                    state = !boxInteractionController.isActive
                        && windowInteractionController.contains(value.entity)
                }
                .onChanged { value in
                    guard !boxInteractionController.isActive,
                          windowInteractionController.contains(value.entity) else { return }
                    windowInteractionController.updateDrag(
                        translation: value.translation,
                        viewportHeight: viewportSize.height
                    )
                }
                .onEnded { _ in windowInteractionController.endDrag() }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .local)
                .targetedToAnyEntity()
                .updating($isDrawerDragGestureActive) { value, state, _ in
                    state = drawerAncestor(from: value.entity) != nil
                }
                .onChanged { value in
                    guard let drawer = drawerAncestor(from: value.entity),
                          !boxInteractionController.isActive else { return }
                    scenarioAnimationController.dragDrawer(
                        named: drawer.name,
                        verticalTranslation: value.translation.height,
                        viewportHeight: viewportSize.height
                    )
                }
                .onEnded { value in
                    guard let drawer = drawerAncestor(from: value.entity) else { return }
                    scenarioAnimationController.endDrawerDrag(named: drawer.name)
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .local)
                .targetedToAnyEntity()
                .onChanged { value in
                    guard !albumController.isReading else { return }
                    boxInteractionController.updateDrag(
                        on: value.entity,
                        translation: value.translation,
                        viewport: viewportSize
                    )
                }
                .onEnded { _ in
                    if !albumController.isReading { boxInteractionController.endDrag() }
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .local)
                .updating($isPageGestureActive) { _, state, _ in
                    state = albumController.isReading
                }
                .onChanged { value in handleContinuousDrag(value.translation, viewportSize: viewportSize) }
                .onEnded { value in handleContinuousDragEnd(value) }
        )
        .simultaneousGesture(
            MagnifyGesture() //permite zoom em pinça
                .onChanged {
                    guard !boxInteractionController.isActive,
                          !photoInteractionController.isOpen,
                          !isPressingWindow, !windowInteractionController.isDragging else { return }
                    orbitController.updateZoom(magnification: $0.magnification)
                }
                .onEnded { _ in orbitController.endZoom() }
        )
        // Keep the full-screen annotation gesture below navigation controls so
        // the back and close buttons remain tappable while the card is flipped.
        .overlay { photoAnnotationOverlay(viewportSize: viewportSize) }
        .overlay(alignment: .topLeading) {
            if albumController.isReading {
                HStack(spacing: 16) {
                    Button {
                        if photoInteractionController.isOpen { closePhotoCard() }
                        else { albumController.closeBook() }
                    } label: {
                        Label(photoInteractionController.isOpen ? "photo.back.book" : "album.back.box",
                              systemImage: "arrow.left")
                    }
//                    .disabled(albumController.phase == .returning || photoInteractionController.isTransitioning)
//                    Text(albumController.activeAlbum?.title ?? "")
//                        .font(.headline)
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 24)
                .padding(.top, 52)
            } else if boxInteractionController.isActive {
                HStack(spacing: 16) {
                    Button {
                        albumController.clearAlbums()
                        boxInteractionController.returnToShelf()
                    } label: {
                        Label("voltar", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(boxInteractionController.phase == .returning)
                    if boxInteractionController.phase == .waitingForTape {
//                        Text("Arraste a fita para cima")
//                            .font(.callout)
                    }
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 24)
                .padding(.top, 52)
            } else if orbitController.isShelfFocused {
                Button {
                    orbitController.returnFromShelf()
                } label: {
                    Label("voltar", systemImage: "arrow.left")//voltar ao quarto
                        .padding(12)
                        .frame(minHeight: 44)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
                .padding(.horizontal, 24)
                .padding(.top, 52)
            }
        }
        .overlay(alignment: .topTrailing) { photoCardControls }
        .overlay(alignment: .bottom) {
            if photoInteractionController.isOpen {
                photoCardStatus
            } else if albumController.isReading {
                bookStatus
            } else if boxInteractionController.canAccessAlbums {
                albumLibraryStatus
            } else if libraryModel.access == .denied || libraryModel.access == .restricted {
                Text("gallery permission denied")
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
            }
        }
        .overlay(alignment: .bottom) { photoMarkupToolbar }
        .task { await libraryModel.load() }
        .onChange(of: boxInteractionController.phase) { _, _ in refreshAlbums() }
        .onChange(of: boxInteractionController.canAccessAlbums) { _, _ in refreshAlbums() }
        .onChange(of: albumController.isPrepared) { _, _ in refreshAlbums() }
        .onChange(of: libraryModel.years) { _, _ in refreshAlbums() }
        .onChange(of: libraryModel.favorites) { _, _ in refreshAlbums() }
        .onChange(of: libraryModel.access) { _, _ in refreshAlbums() }
        .onChange(of: isPressingWindow) { _, isPressed in
            if !isPressed { windowInteractionController.endDrag() }
        }
        .onChange(of: isPageGestureActive) { _, active in
            if !active {
                // Give onEnded a chance to settle a completed gesture first.
                Task { @MainActor in
                    await Task.yield()
                    if !isPageGestureActive { albumController.cancelPageDrag() }
                }
            }
        }
        .onChange(of: photoDrawingData) { _, _ in
            guard photoInteractionController.isBackVisible else { return }
            scheduleAnnotationSave()
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhaseChange(phase)
        }
        .onDisappear {
            windowInteractionController.endDrag()
            annotationSaveTask?.cancel()
            if let photoID = photoInteractionController.selectedPhotoID {
                let drawingData = photoDrawingData
                Task { try? await libraryModel.saveAnnotationDrawing(drawingData, for: photoID) }
            }
            photoInteractionController.close()
            albumController.clearAlbums()
            boxInteractionController.resetPresentation()
        }
    }

    private func refreshAlbums() {
        guard boxInteractionController.isActive,
              boxInteractionController.phase != .returning,
              let box = boxInteractionController.selectedBox,
              let bounds = boxInteractionController.selectedBoxBounds,
              let slot = BoxInteractionController.boxNames.firstIndex(of: box.name) else {
            albumController.clearAlbums()
            return
        }
        let hasAccess = libraryModel.access == .authorized || libraryModel.access == .limited
        albumController.showAlbums(hasAccess ? libraryModel.albums(forBoxSlot: slot) : [], in: box, bounds: bounds)
        albumController.setInteractionEnabled(boxInteractionController.canAccessAlbums && hasAccess)
    }

    private func handleEntityTap(_ entity: Entity, viewportSize: CGSize) {
        if albumController.isReading {
            guard !photoInteractionController.isOpen,
                  let photoID = albumController.photoID(containing: entity) else { return }
            photoDrawingData = Data()
            selectedPhotoMarkupTool = .pen
            isPhotoMarkupToolbarExpanded = false
            annotationSaveFailed = false
            isLoadingAnnotation = true
            photoInteractionController.open(photoID: photoID, from: entity)
            Task {
                let annotation = try? await libraryModel.annotation(for: photoID)
                guard photoInteractionController.selectedPhotoID == photoID else { return }
                photoDrawingData = annotation?.drawingData ?? Data()
                isLoadingAnnotation = false
            }
            return
        } 
        if boxInteractionController.canAccessAlbums,
           let id = albumController.albumID(containing: entity) {
            albumController.select(id)
            return
        }
        guard !boxInteractionController.isActive,
              !windowInteractionController.isDragging,
              !windowInteractionController.contains(entity) else { return }
        if let box = boxInteractionController.box(containing: entity) {
            if !orbitController.isShelfFocused {
                if let shelf = scenarioAnimationController.entity(for: .archiveShelf) {
                    orbitController.toggleFocus(on: shelf)
                }
            } else if orbitController.isShelfFocusReady {
                boxInteractionController.present(box, viewport: viewportSize)
                refreshAlbums()
            }
            return
        }
        if let drawer = drawerAncestor(from: entity) {
            orbitController.toggleFocus(on: drawer, lookingFromFront: true, pitchDegrees: 32, minimumRadius: 2.1)
            return
        }
        if let desk = deskAncestor(from: entity) {
            orbitController.toggleFocus(on: desk, lookingFromFront: true, pitchDegrees: 75, minimumRadius: 1.15)
            return
        }
        if lampAncestor(from: entity) != nil {
            sceneLightingController.toggleLamp()
            return
        }
        guard let shelf = shelfAncestor(from: entity) else { return }
        orbitController.toggleFocus(on: shelf)
    }

    private func handleContinuousDrag(_ translation: CGSize, viewportSize: CGSize) {
        if albumController.isReading {
            if photoInteractionController.isOpen {
                // While the back is visible, let PencilKit own drags on the
                // page. Tapping outside it flips the card back to the photo.
                guard !photoInteractionController.isBackVisible else { return }
                if !isDraggingPhotoCard {
                    isDraggingPhotoCard = true
                    photoInteractionController.beginDrag()
                }
                photoInteractionController.updateDrag(
                    translation: translation,
                    viewportSize: viewportSize
                )
            } else {
                albumController.updatePageDrag(translation: translation)
            }
            return
        }
        guard !isDrawerDragGestureActive,
              !boxInteractionController.isActive,
              !isPressingWindow, !windowInteractionController.isDragging else { return }
        if !isDragging {
            isDragging = true
            orbitController.beginDrag()
        }
        orbitController.updateDrag(translation: translation)
    }

    private func handleContinuousDragEnd(_ value: DragGesture.Value) {
        if albumController.isReading {
            if photoInteractionController.isOpen {
                if isDraggingPhotoCard {
                    isDraggingPhotoCard = false
                    photoInteractionController.endDrag()
                }
            } else {
                albumController.endPageDrag(predictedTranslation: value.predictedEndTranslation)
            }
            return
        }
        isDragging = false
        orbitController.endDrag()
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        guard phase != .active else { return }
        windowInteractionController.endDrag()
        albumController.cancelPageDrag()
        if photoInteractionController.isOpen { closePhotoCard() }
    }

    private func scheduleAnnotationSave() {
        guard let photoID = photoInteractionController.selectedPhotoID else { return }
        annotationSaveTask?.cancel()
        annotationSaveFailed = false
        let drawingData = photoDrawingData
        annotationSaveTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(500))
                try await libraryModel.saveAnnotationDrawing(drawingData, for: photoID)
                guard !Task.isCancelled else { return }
                annotationSaveFailed = false
            } catch {
                guard !Task.isCancelled else { return }
                annotationSaveFailed = true
            }
        }
    }

    private func saveAnnotationNow() {
        guard let photoID = photoInteractionController.selectedPhotoID else { return }
        annotationSaveTask?.cancel()
        let drawingData = photoDrawingData
        annotationSaveTask = Task {
            do {
                try await libraryModel.saveAnnotationDrawing(drawingData, for: photoID)
                annotationSaveFailed = false
            } catch {
                annotationSaveFailed = true
            }
        }
    }

    private func closePhotoCard() {
        guard let photoID = photoInteractionController.selectedPhotoID else {
            photoInteractionController.close()
            return
        }
        annotationSaveTask?.cancel()
        let drawingData = photoDrawingData
        Task {
            do {
                try await libraryModel.saveAnnotationDrawing(drawingData, for: photoID)
                annotationSaveFailed = false
            } catch {
                annotationSaveFailed = true
                return
            }
            photoInteractionController.close()
            photoDrawingData = Data()
            isLoadingAnnotation = false
        }
    }

    @ViewBuilder
    private var albumLibraryStatus: some View {
        if libraryModel.isLoading || !albumController.isPrepared
            || libraryModel.access == .denied || libraryModel.access == .restricted
            || libraryModel.loadFailed || albumController.albums.isEmpty {
            VStack(spacing: 10) {
                if libraryModel.isLoading || !albumController.isPrepared {
//                    ProgressView("album.loading")
                } else if libraryModel.access == .denied || libraryModel.access == .restricted {
                    Text("gallery permission denied")
                } else if libraryModel.loadFailed {
                    Text("")
                    Button("album retry") { Task { await libraryModel.load() } }
                } else {
                    Text("Não há fotos no periodo")
                }
            }
//
        }
    }

    @ViewBuilder
    private var bookStatus: some View {
        if albumController.isLoadingPage || albumController.hasUnavailablePhotos {
            VStack(spacing: 8) {
                if albumController.isLoadingPage { ProgressView("album.loading") }
                if albumController.hasUnavailablePhotos {
                    Button("album retry") { albumController.retryPage() }
                        .disabled(albumController.isTurningPage)
                }
            }
//            .padding(12)
//            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
//            .padding(.horizontal, 24)
//            .padding(.bottom, 28)
        }
    }

    @ViewBuilder
    private var photoCardControls: some View {
//        if photoInteractionController.isOpen {
//            Button { closePhotoCard() } label: {
//                Image(systemName: "xmark").frame(width: 44, height: 44)
//            }
//            .accessibilityLabel("photo.close")
//            .disabled(photoInteractionController.isTransitioning || isLoadingAnnotation)
//            .padding(12)
//            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
//            .padding(.horizontal, 24)
//            .padding(.top, 52)
//        }
    }

    @ViewBuilder
    private func photoAnnotationOverlay(viewportSize: CGSize) -> some View {
        if photoInteractionController.isBackVisible {
            ZStack {
                if !isLoadingAnnotation,
                   !photoInteractionController.isTransitioning,
                   !isDraggingPhotoCardFromBack {
                    let canvasHeight = viewportSize.height * photoInteractionController.annotationCanvasHeightFraction
                    PhotoAnnotationCanvas(
                        drawingData: $photoDrawingData,
                        selectedTool: selectedPhotoMarkupTool
                    )
                        .frame(width: canvasHeight * photoInteractionController.photoAspectRatio, height: canvasHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .local)
                    .onEnded { value in
                        guard photoInteractionController.isBackVisible else { return }
                        // Leave the top navigation controls their own tap action.
                        let topControls = CGRect(x: 0, y: 0, width: viewportSize.width, height: 150)
                        if !photoPageRect(in: viewportSize).contains(value.location)
                            && !topControls.contains(value.location) {
                            photoInteractionController.flip()
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .local)
                    .onChanged { value in
                        let topControls = CGRect(x: 0, y: 0, width: viewportSize.width, height: 150)
                        guard !photoPageRect(in: viewportSize).contains(value.startLocation),
                              !topControls.contains(value.startLocation),
                              !photoInteractionController.isTransitioning else { return }
                        if !isDraggingPhotoCardFromBack {
                            isDraggingPhotoCardFromBack = true
                            photoInteractionController.beginDrag()
                        }
                        photoInteractionController.updateDrag(
                            translation: value.translation,
                            viewportSize: viewportSize
                        )
                    }
                    .onEnded { _ in
                        if isDraggingPhotoCardFromBack {
                            isDraggingPhotoCardFromBack = false
                            photoInteractionController.endDrag()
                        }
                    }
            )
        }
    }

    private func photoPageRect(in viewportSize: CGSize) -> CGRect {
        let pageHeight = viewportSize.height * photoInteractionController.annotationCanvasHeightFraction
        let pageWidth = pageHeight * photoInteractionController.photoAspectRatio
        return CGRect(
            x: (viewportSize.width - pageWidth) / 2,
            y: (viewportSize.height - pageHeight) / 2,
            width: pageWidth,
            height: pageHeight
        )
    }

    private var photoCardStatus: some View {
        Group {
            if photoInteractionController.photoLoadFailed || annotationSaveFailed {
                VStack(spacing: 8) {
                    if photoInteractionController.photoLoadFailed { Text("photo.load.failed") }
                    if annotationSaveFailed {
                        Button("photo.annotation.retry") { saveAnnotationNow() }
                    }
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(photoInteractionController.photoLoadFailed || annotationSaveFailed)
    }

    @ViewBuilder
    private var photoMarkupToolbar: some View {
        if photoInteractionController.isBackVisible,
           !photoInteractionController.isTransitioning {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                        isPhotoMarkupToolbarExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isPhotoMarkupToolbarExpanded ? "xmark" : "square.and.pencil")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(isPhotoMarkupToolbarExpanded ? "Fechar ferramentas" : "Editar anotação")

                if isPhotoMarkupToolbarExpanded {
                    Rectangle().fill(.white.opacity(0.22)).frame(width: 1, height: 26)
                        .transition(.scale.combined(with: .opacity))

                    ForEach(PhotoMarkupTool.allCases) { tool in
                        Button {
                            selectedPhotoMarkupTool = tool
                        } label: {
                            Image(systemName: tool.symbol)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(selectedPhotoMarkupTool == tool ? .black : .white)
                                .frame(width: 40, height: 40)
                                .background {
                                    if selectedPhotoMarkupTool == tool { Circle().fill(.white) }
                                }
                        }
                        .accessibilityLabel(tool.accessibilityTitle)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(6)
            .foregroundStyle(.white)
            .background(.ultraThinMaterial.opacity(0.96), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
            .padding(.bottom, 26)
            .frame(maxWidth: .infinity)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func shelfAncestor(from entity: Entity) -> Entity? {
        var current: Entity? = entity
        while let candidate = current {
            if candidate.name.compare("Estante", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                return candidate
            }
            current = candidate.parent
        }
        return nil
    }

    private func drawerAncestor(from entity: Entity) -> Entity? {
        var current: Entity? = entity
        while let candidate = current {
            if ScenarioDrawer.matches(candidate.name) {
                return candidate
            }
            current = candidate.parent
        }
        return nil
    }

    private func deskAncestor(from entity: Entity) -> Entity? {
        var current: Entity? = entity
        while let candidate = current {
            if candidate.name.compare("Mesa", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                return candidate
            }
            current = candidate.parent
        }
        return nil
    }

    private func lampAncestor(from entity: Entity) -> Entity? {
        var current: Entity? = entity
        while let candidate = current {
            if ["Abajur", "Topo_do_Abajur"].contains(where: {
                candidate.name.compare($0, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                return candidate
            }
            current = candidate.parent
        }
        return nil
    }
}

#Preview {
    ContentView(libraryModel: GalleryLibraryModel(
        photoRepository: PhotoKitLibraryRepository(),
        annotationRepository: PreviewAnnotationRepository()
    ), boxSessionState: BoxSessionState())
}

private struct PreviewAnnotationRepository: AnnotationRepository {
    func save(_ annotation: PhotoAnnotation) async throws {}
    func find(for photoID: String) async throws -> PhotoAnnotation? { nil }
    func delete(for photoID: String) async throws {}
}
