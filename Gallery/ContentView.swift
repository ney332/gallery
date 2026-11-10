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
            content.camera = .virtual
            let loader = BlenderAssetLoader(catalog: .main)
            let roomFallback = loader.fallback(for: .room)
            content.add(roomFallback)

            let camera = SceneCamera.makeOverviewCamera()
            content.add(camera)
            orbitController.attach(camera: camera, viewportSize: viewportSize)

            let light = Entity()
            light.components.set(DirectionalLightComponent(intensity: 1800))
            light.orientation = simd_quatf(angle: -.pi / 4, axis: [1, 0, 0])
            content.add(light)

            let room = await loader.load(.room)
            roomFallback.removeFromParent()
            content.add(room)
        } update: { _ in
            orbitController.updateViewport(viewportSize)
        }
        .overlay {
            Color.clear
                .contentShape(Rectangle())
                .gesture(
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
                        },
                    including: .all
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { orbitController.updateZoom(magnification: $0.magnification) }
                        .onEnded { _ in orbitController.endZoom() }
                )
        }
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
