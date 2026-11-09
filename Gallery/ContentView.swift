import RealityKit
import SwiftUI
import UIKit

struct ContentView: View {
    let libraryModel: GalleryLibraryModel

    @State private var orbitController = OverviewOrbitController()

    var body: some View {
        GeometryReader { geometry in
            scene(viewportSize: geometry.size)
        }
        .ignoresSafeArea()
        .background(Color(red: 0.12, green: 0.10, blue: 0.09))
    }

    private func scene(viewportSize: CGSize) -> some View {
        ZStack {
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
            OrbitPanGesture(
                onBegin: { orbitController.beginDrag() },
                onChange: { orbitController.updateDrag(translation: $0) },
                onEnd: { orbitController.endDrag(velocity: $0) }
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in orbitController.updateZoom(magnification: value.magnification) }
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

@MainActor
private struct OrbitPanGesture: UIViewRepresentable {
    let onBegin: () -> Void
    let onChange: (CGSize) -> Void
    let onEnd: (CGSize) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBegin: onBegin, onChange: onChange, onEnd: onEnd)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isOpaque = false

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onBegin = onBegin
        context.coordinator.onChange = onChange
        context.coordinator.onEnd = onEnd
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onBegin: () -> Void
        var onChange: (CGSize) -> Void
        var onEnd: (CGSize) -> Void

        init(onBegin: @escaping () -> Void, onChange: @escaping (CGSize) -> Void, onEnd: @escaping (CGSize) -> Void) {
            self.onBegin = onBegin
            self.onChange = onChange
            self.onEnd = onEnd
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let translation = recognizer.translation(in: recognizer.view)
            let value = CGSize(width: translation.x, height: translation.y)

            switch recognizer.state {
            case .began:
                onBegin()
                onChange(value)
            case .changed:
                onChange(value)
            case .ended, .cancelled, .failed:
                let velocity = recognizer.velocity(in: recognizer.view)
                onEnd(CGSize(width: velocity.x, height: velocity.y))
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
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
