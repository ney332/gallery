import Observation
import RealityKit
import simd
import UIKit

/// Presents a selected book photo as a camera-facing 3D card.
@MainActor
@Observable
final class PhotoInteractionController {
    private(set) var selectedPhotoID: String?
    private(set) var isBackVisible = false
    private(set) var isTransitioning = false
    private(set) var isLoadingPhoto = false
    private(set) var photoLoadFailed = false

    @ObservationIgnored private weak var camera: Entity?
    @ObservationIgnored private var card: Entity?
    @ObservationIgnored private var frontSurface: ModelEntity?
    @ObservationIgnored private var cardHome = Transform()
    @ObservationIgnored private var rotation: Float = 0
    @ObservationIgnored private var pitch: Float = 0
    @ObservationIgnored private var dragStartRotation: Float = 0
    @ObservationIgnored private var dragStartPitch: Float = 0
    @ObservationIgnored private var imageTask: Task<Void, Never>?
    @ObservationIgnored private let thumbnails = PhotoThumbnailCache()
    @ObservationIgnored private var presentationID = UUID()

    var isOpen: Bool { selectedPhotoID != nil }

    /// Screen-space height of the physical writing face after its presentation
    /// scale is applied. Keeping PencilKit within this projection makes marks
    /// line up with the back of the 3D card instead of floating around it.
    var annotationCanvasHeightFraction: CGFloat {
        let depth = max(GalleryConfig.albumViewingDistance - 0.17, 0.32)
        let scale = depth / 0.88
        let fieldOfView = camera?.components[PerspectiveCameraComponent.self]?.fieldOfViewInDegrees ?? 50.2
        let faceHeight = 0.69 * 0.92 * scale
        let viewHeightAtCard = 2 * depth * tan(fieldOfView * .pi / 360)
        return CGFloat(faceHeight / viewHeightAtCard)
    }

    func attach(camera: Entity) {
        close()
        self.camera = camera
    }

    func open(photoID: String, from source: Entity) {
        guard !isOpen, let camera else { return }
        selectedPhotoID = photoID
        isBackVisible = false
        isTransitioning = false
        isLoadingPhoto = true
        photoLoadFailed = false
        rotation = 0
        pitch = 0

        let width: Float = 0.54
        let height: Float = 0.69
        let root = Entity()
        root.name = "SelectedPhotoCard"

        let body = ModelEntity(
            mesh: .generateBox(size: [width, height, 0.012]),
            materials: [SimpleMaterial(color: UIColor(red: 0.96, green: 0.94, blue: 0.89, alpha: 1),
                                       roughness: 0.92, isMetallic: false)]
        )
        root.addChild(body)

        let front = ModelEntity(
            mesh: .generatePlane(width: width * 0.92, height: height * 0.92),
            materials: [UnlitMaterial(color: .white)]
        )
        front.name = "PhotoCardFront"
        front.position.z = 0.007
        root.addChild(front)
        frontSurface = front

        let back = ModelEntity(
            mesh: .generatePlane(width: width * 0.92, height: height * 0.92),
            materials: [SimpleMaterial(color: UIColor(red: 0.99, green: 0.98, blue: 0.94, alpha: 1),
                                       roughness: 1, isMetallic: false)]
        )
        back.name = "PhotoCardBack"
        back.position.z = -0.007
        back.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        root.addChild(back)

        let worldCenter = source.visualBounds(relativeTo: nil).center
        let cameraSpace = simd_inverse(camera.transformMatrix(relativeTo: nil))
            * SIMD4<Float>(worldCenter.x, worldCenter.y, worldCenter.z, 1)
        let startPosition = SIMD3<Float>(cameraSpace.x, cameraSpace.y, cameraSpace.z)
        root.position = startPosition
        root.scale = SIMD3(repeating: 0.14)
        camera.addChild(root)
        card = root

        cardHome = root.transform
        var destination = root.transform
        // The album is framed at albumViewingDistance (0.55 m). Put the photo
        // card closer to the camera so it renders in front, while scaling it
        // with depth to preserve its previous on-screen size.
        let previousCardDepth: Float = 0.88
        let foregroundDepth = max(GalleryConfig.albumViewingDistance - 0.17, 0.32)
        destination.translation = [0, 0, -foregroundDepth]
        destination.scale = SIMD3(repeating: foregroundDepth / previousCardDepth)
        root.move(to: destination, relativeTo: camera, duration: 0.48, timingFunction: .easeInOut)

        let token = UUID()
        presentationID = token
        imageTask?.cancel()
        imageTask = Task { [weak self] in
            guard let self else { return }
            let image = await self.thumbnails.thumbnail(
                for: photoID,
                targetSize: GalleryConfig.albumPhotoTargetSize
            ) { [weak self] preview in
                self?.apply(preview, for: token)
            }
            guard self.presentationID == token else { return }
            self.isLoadingPhoto = false
            if let image {
                self.apply(image, for: token)
            } else {
                self.photoLoadFailed = true
            }
        }
    }

    func beginDrag() {
        guard isOpen, !isTransitioning else { return }
        dragStartRotation = rotation
        dragStartPitch = pitch
        card?.stopAllAnimations(recursive: true)
    }

    func updateDrag(translation: CGSize, viewportSize: CGSize) {
        guard isOpen, !isTransitioning, let card else { return }

        // Keep the card anchored at its presentation point. Drag rotates the
        // card around its own center on both local axes, like a floating card.
        let width = max(viewportSize.width, 1)
        let height = max(viewportSize.height, 1)
        let yaw = Float(translation.width / width) * 2 * .pi
        let pitchDelta = Float(translation.height / height) * 2 * .pi
        rotation = dragStartRotation + yaw
        pitch = min(max(dragStartPitch + pitchDelta, -.pi / 2), .pi / 2)
        let yawRotation = simd_quatf(angle: rotation, axis: [0, 1, 0])
        let pitchRotation = simd_quatf(angle: pitch, axis: [1, 0, 0])
        card.orientation = yawRotation * pitchRotation
    }

    func endDrag() {
        guard isOpen, !isTransitioning else { return }
        let normalizedRotation = atan2(sin(rotation), cos(rotation))
        settleCard(toBack: abs(normalizedRotation) >= .pi / 2)
    }

    func flip() {
        guard isOpen, !isTransitioning else { return }
        settleCard(toBack: !isBackVisible)
    }

    func close() {
        imageTask?.cancel()
        imageTask = nil
        presentationID = UUID()
        guard let card else {
            resetState()
            return
        }
        isTransitioning = true
        card.move(to: cardHome, relativeTo: camera, duration: 0.3, timingFunction: .easeInOut)
        Task { [weak self, weak card] in
            try? await Task.sleep(for: .milliseconds(320))
            guard let self else { return }
            card?.removeFromParent()
            self.card = nil
            self.frontSurface = nil
            self.resetState()
        }
    }

    private func settleCard(toBack: Bool) {
        guard let card else { return }
        isTransitioning = true
        if !toBack {
            // Remove the SwiftUI annotation layer as soon as the card starts
            // turning to its photo side, so the drawing never overlays the
            // front during the animation.
            isBackVisible = false
        }
        let targetAngle: Float = toBack ? (rotation < 0 ? -.pi : .pi) : 0
        var target = card.transform
        target.rotation = simd_quatf(angle: targetAngle, axis: [0, 1, 0])
        card.move(to: target, relativeTo: camera, duration: 0.32, timingFunction: .easeInOut)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(340))
            guard let self, self.card === card else { return }
            self.rotation = targetAngle
            self.pitch = 0
            self.isBackVisible = toBack
            self.isTransitioning = false
        }
    }

    private func apply(_ image: UIImage, for token: UUID) {
        guard presentationID == token, let cgImage = image.cgImage,
              let frontSurface,
              let texture = try? TextureResource(image: cgImage, options: .init(semantic: .color)) else { return }
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        frontSurface.model?.materials = [material]
    }

    private func resetState() {
        selectedPhotoID = nil
        isBackVisible = false
        isTransitioning = false
        isLoadingPhoto = false
        photoLoadFailed = false
        rotation = 0
        pitch = 0
    }
}
