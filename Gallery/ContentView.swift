import RealityKit
import SwiftUI

struct ContentView: View {
    let libraryModel: GalleryLibraryModel
    @State private var orbitController = OverviewOrbitController()
    @State private var scenarioAnimationController = ScenarioAnimationController()
    @State private var sceneLightingController = SceneLightingController()
    @State private var boxInteractionController: BoxInteractionController
    @State private var albumController = AlbumBookController()
    @State private var windowInteractionController = WindowInteractionController()
    @GestureState private var isPressingWindow = false
    @GestureState private var isPageGestureActive = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var isDragging = false

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

            let room = await loader.load(.room)
            albumController.clearAlbums()
            scenarioAnimationController.attach(to: room)
            windowInteractionController.attach(to: scenarioAnimationController.entity(for: .windowGlass))
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
        }
        .simultaneousGesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    if albumController.isReading { return }
                    if boxInteractionController.canAccessAlbums,
                       let id = albumController.albumID(containing: value.entity) {
                        albumController.select(id)
                        return
                    }
                    guard !boxInteractionController.isActive,
                          !windowInteractionController.isDragging,
                          !windowInteractionController.contains(value.entity) else { return }
                    if let box = boxInteractionController.box(containing: value.entity) {
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
                    if let drawer = drawerAncestor(from: value.entity) {
                        guard scenarioAnimationController.toggleTopDrawer() else { return }
                        orbitController.toggleFocus(
                            on: drawer,
                            lookingFromFront: true,
                            pitchDegrees: 32,
                            minimumRadius: 0.75
                        )
                        return
                    }
                    if let desk = deskAncestor(from: value.entity) {
                        orbitController.toggleFocus(
                            on: desk,
                            lookingFromFront: true,
                            pitchDegrees: 75,
                            minimumRadius: 1.15
                        )
                        return
                    }
                    if lampAncestor(from: value.entity) != nil {
                        sceneLightingController.toggleLamp()
                        return
                    }
                    guard let shelf = shelfAncestor(from: value.entity) else { return }
                    orbitController.toggleFocus(on: shelf)
                }
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
                .onChanged { value in
                    if albumController.isReading {
                        albumController.updatePageDrag(translation: value.translation)
                        return
                    }
                    guard !boxInteractionController.isActive,
                          !isPressingWindow, !windowInteractionController.isDragging else { return }
                    if !isDragging {
                        isDragging = true
                        orbitController.beginDrag()
                    }
                    orbitController.updateDrag(translation: value.translation)
                }
                .onEnded { value in
                    if albumController.isReading {
                        albumController.endPageDrag(predictedTranslation: value.predictedEndTranslation)
                        return
                    }
                    isDragging = false
                    orbitController.endDrag()
                }
        )
        .simultaneousGesture(
            MagnifyGesture() //permite zoom em pinça
                .onChanged {
                    guard !boxInteractionController.isActive,
                          !isPressingWindow, !windowInteractionController.isDragging else { return }
                    orbitController.updateZoom(magnification: $0.magnification)
                }
                .onEnded { _ in orbitController.endZoom() }
        )
        .overlay(alignment: .topLeading) {
            if albumController.isReading {
                HStack(spacing: 16) {
                    Button { albumController.closeBook() } label: {
                        Label("album.back.box", systemImage: "arrow.left")
                    }
                    .disabled(albumController.phase == .returning)
                    Text(albumController.activeAlbum?.title ?? "")
                        .font(.headline)
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
                        Label("Voltar à estante", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(boxInteractionController.phase == .returning)
                    if boxInteractionController.phase == .waitingForTape {
                        Text("Arraste a fita para cima")
                            .font(.callout)
                    } else if boxInteractionController.phase == .ready {
                        Text("")
                            .font(.callout)
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
                    Label("Voltar ao quarto", systemImage: "arrow.left")
                        .padding(12)
                        .frame(minHeight: 44)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .padding(.top, 52)
            }
        }
        .overlay(alignment: .bottom) {
            if albumController.isReading {
                bookStatus
            } else if boxInteractionController.canAccessAlbums {
                albumLibraryStatus
            } else if libraryModel.access == .denied || libraryModel.access == .restricted {
                Text("gallery.permission.denied")
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
            }
        }
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
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                windowInteractionController.endDrag()
                albumController.cancelPageDrag()
            }
        }
        .onDisappear {
            windowInteractionController.endDrag()
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

    @ViewBuilder
    private var albumLibraryStatus: some View {
        if libraryModel.isLoading || !albumController.isPrepared
            || libraryModel.access == .denied || libraryModel.access == .restricted
            || libraryModel.loadFailed || albumController.albums.isEmpty {
            VStack(spacing: 10) {
                if libraryModel.isLoading || !albumController.isPrepared {
                    ProgressView("album.loading")
                } else if libraryModel.access == .denied || libraryModel.access == .restricted {
                    Text("gallery.permission.denied")
                } else if libraryModel.loadFailed {
                    Text("album.library.failed")
                    Button("album.retry") { Task { await libraryModel.load() } }
                } else {
                    Text("album.box.empty")
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    @ViewBuilder
    private var bookStatus: some View {
        if albumController.isLoadingPage || albumController.hasUnavailablePhotos {
            VStack(spacing: 8) {
                if albumController.isLoadingPage { ProgressView("album.loading") }
                if albumController.hasUnavailablePhotos {
                    Button("album.retry") { albumController.retryPage() }
                        .disabled(albumController.isTurningPage)
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
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
            if candidate.name.compare("Gaveta_Cima", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
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
