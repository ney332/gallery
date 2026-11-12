import RealityKit
import SwiftUI

struct ContentView: View {
    let libraryModel: GalleryLibraryModel
    @State private var orbitController = OverviewOrbitController()
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
            let sceneSetupStart = ContinuousClock.now
            content.camera = .virtual
            let loader = BlenderAssetLoader(catalog: .main)
            let roomFallback = loader.fallback(for: .room)
            content.add(roomFallback)

            let camera = SceneCamera.makeOverviewCamera()
            content.add(camera)
            orbitController.attach(camera: camera, viewportSize: viewportSize)

            let room = await loader.load(.room)
            roomFallback.removeFromParent()
            content.add(room)
            print("RealityView scene setup: \(sceneSetupStart.duration(to: .now))")
        } update: { _ in
            orbitController.updateViewport(viewportSize)
        }
        .simultaneousGesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
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
