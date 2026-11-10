import RealityKit
import SwiftUI

struct ContentView: View {
    let libraryModel: GalleryLibraryModel

    @State private var orbitController = OverviewOrbitController()
    @State private var isDraggingBackground = false
    @State private var dragDelta: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            scene(viewportSize: geometry.size)
        }
        .ignoresSafeArea()
        .background(Color(red: 0.12, green: 0.10, blue: 0.09))
    }

    private func scene(viewportSize: CGSize) -> some View {
        RealityView { content in
            let loader = BlenderAssetLoader(catalog: .main)
            let roomFallback = loader.fallback(for: .room)
            content.add(roomFallback)

            let camera = SceneCamera.makeOverviewCamera(viewportSize: viewportSize)
            orbitController.attach(camera: camera, viewportSize: viewportSize)
            content.add(camera)

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
            CameraGestureSurface(
                onDragChanged: { translation in
                    if !isDraggingBackground {
                        isDraggingBackground = true
                        dragDelta = .zero
                        orbitController.beginDrag()
                    }
                    dragDelta = translation
                    orbitController.updateDrag(translation: translation)
                },
                onDragEnded: { velocity in
                    isDraggingBackground = false
                    orbitController.endDrag(velocity: velocity)
                },
                onMagnificationChanged: orbitController.updateZoom(magnification:),
                onMagnificationEnded: { orbitController.endZoom() }
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
        .overlay(alignment: .topLeading) {
            if isDraggingBackground {
                Text("Arraste: \(Int(dragDelta.width)) px")
                    .font(.caption.monospacedDigit())
                    .padding(8)
                    .background(.black.opacity(0.65), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.top, 12)
                    .padding(.leading, 12)
                    .allowsHitTesting(false)
            }
        }
        .task { await libraryModel.load() }
    }
}

private struct CameraGestureSurface: View {
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize) -> Void
    let onMagnificationChanged: (CGFloat) -> Void
    let onMagnificationEnded: () -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .local)
                    .onChanged { onDragChanged($0.translation) }
                    .onEnded { onDragEnded($0.velocity) },
                including: .all
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { onMagnificationChanged($0.magnification) }
                    .onEnded { _ in onMagnificationEnded() }
            )
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
