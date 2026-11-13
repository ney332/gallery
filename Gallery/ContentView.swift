import RealityKit
import SwiftUI

struct ContentView: View {
    let libraryModel: GalleryLibraryModel
    @State private var orbitController = OverviewOrbitController()
    @State private var scenarioAnimationController = ScenarioAnimationController()
    @State private var sceneLightingController = SceneLightingController()
    @State private var isDragging = false

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
            scenarioAnimationController.attach(to: room)
            sceneLightingController.attach(to: room, preset: .afternoon)
            roomFallback.removeFromParent()
            content.add(room)
        } update: { _ in
            orbitController.updateViewport(viewportSize)
        }
        .simultaneousGesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
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
                            pitchDegrees: 55,
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
            DragGesture(minimumDistance: 1, coordinateSpace: .local)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        orbitController.beginDrag()
                    }
                    orbitController.updateDrag(translation: value.translation)
                }
                .onEnded { _ in
                    isDragging = false
                    orbitController.endDrag()
                }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { orbitController.updateZoom(magnification: $0.magnification) }
                .onEnded { _ in orbitController.endZoom() }
        )
        .overlay(alignment: .bottom) {
            if libraryModel.access == .denied || libraryModel.access == .restricted {
                Text("gallery.permission.denied")
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
            }
        }
        .task { await libraryModel.load() }
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
    ))
}

private struct PreviewAnnotationRepository: AnnotationRepository {
    func save(_ annotation: PhotoAnnotation) async throws {}
    func find(for photoID: String) async throws -> PhotoAnnotation? { nil }
    func delete(for photoID: String) async throws {}
}
