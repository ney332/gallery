import Observation
import CoreMotion
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
    private(set) var photoAspectRatio: CGFloat = 0.54 / 0.69

    @ObservationIgnored private weak var camera: Entity?
    @ObservationIgnored private var card: Entity?
    @ObservationIgnored private var motionPivot: Entity?
    @ObservationIgnored private var cardContent: Entity?
    @ObservationIgnored private var cardBody: ModelEntity?
    @ObservationIgnored private var frontSurface: ModelEntity?
    @ObservationIgnored private var backSurface: ModelEntity?
    @ObservationIgnored private var cardHome = Transform()
    @ObservationIgnored private var pendingOpenDestination: Transform?
    @ObservationIgnored private var hasPresentedPhoto = false
    @ObservationIgnored private var viewportSize = CGSize(width: 1, height: 1)
    @ObservationIgnored private var cardWidth: Float = 0.54
    @ObservationIgnored private var cardHeight: Float = 0.69
    @ObservationIgnored private var contentFitScale: Float = 1
    @ObservationIgnored private var rotation: Float = 0
    @ObservationIgnored private var pitch: Float = 0
    @ObservationIgnored private var dragStartRotation: Float = 0
    @ObservationIgnored private var dragStartPitch: Float = 0
    @ObservationIgnored private var imageTask: Task<Void, Never>?
    @ObservationIgnored private let thumbnails = PhotoThumbnailCache()
    @ObservationIgnored private var presentationID = UUID()
    @ObservationIgnored private let motionManager = CMMotionManager()
    @ObservationIgnored private var motionReferenceAttitude: CMAttitude?
    @ObservationIgnored private var motionYaw: Float = 0
    @ObservationIgnored private var motionPitch: Float = 0
    @ObservationIgnored private var dragYaw: Float = 0
    @ObservationIgnored private var dragPitch: Float = 0
    @ObservationIgnored private var motionUpdateTask: Task<Void, Never>?

    var isOpen: Bool { selectedPhotoID != nil }

    /// Screen-space height of the physical writing face after its presentation
    /// scale is applied. Keeping PencilKit within this projection makes marks
    /// line up with the back of the 3D card instead of floating around it.
    var annotationCanvasHeightFraction: CGFloat {
        let depth = max(GalleryConfig.albumViewingDistance - 0.17, 0.32)
        let scale = depth / 0.88
        let fieldOfView = camera?.components[PerspectiveCameraComponent.self]?.fieldOfViewInDegrees ?? 50.2
        let faceHeight = cardHeight * 0.92 * scale * contentFitScale
        let viewHeightAtCard = 2 * depth * tan(fieldOfView * .pi / 360)
        return CGFloat(faceHeight / viewHeightAtCard)
    }

    func attach(camera: Entity, viewportSize: CGSize) {
        close()
        self.camera = camera
        updateViewport(viewportSize)
    }

    func updateViewport(_ viewportSize: CGSize) {
        self.viewportSize = viewportSize
        updateContentFitScale()
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
        dragYaw = 0
        dragPitch = 0
        motionYaw = 0
        motionPitch = 0
        startMotionTracking()
        photoAspectRatio = 0.54 / 0.69
        cardWidth = 0.54
        cardHeight = 0.69
        contentFitScale = 1

        let width: Float = 0.54
        let height: Float = 0.69
        let root = Entity()
        root.name = "SelectedPhotoCard"
        let motionPivot = Entity()
        motionPivot.name = "PhotoCardMotionPivot"
        root.addChild(motionPivot)
        self.motionPivot = motionPivot

        let content = Entity()
        content.name = "PhotoCardContent"
        motionPivot.addChild(content)
        cardContent = content

        let body = ModelEntity(
            mesh: .generateBox(size: [width, height, 0.012]),
            materials: [SimpleMaterial(color: UIColor(red: 0.96, green: 0.94, blue: 0.89, alpha: 1),
                                       roughness: 0.92, isMetallic: false)]
        )
        content.addChild(body)
        cardBody = body

        let front = ModelEntity(
            mesh: .generatePlane(width: width * 0.92, height: height * 0.92),
            materials: [UnlitMaterial(color: .white)]
        )
        front.name = "PhotoCardFront"
        front.position.z = 0.007
        content.addChild(front)
        frontSurface = front

        let back = ModelEntity(
            mesh: .generatePlane(width: width * 0.92, height: height * 0.92),
            materials: [SimpleMaterial(color: UIColor(red: 0.99, green: 0.98, blue: 0.94, alpha: 1),
                                       roughness: 1, isMetallic: false)]
        )
        back.name = "PhotoCardBack"
        back.position.z = -0.007
        back.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        content.addChild(back)
        backSurface = back

        let worldCenter = source.visualBounds(relativeTo: nil).center
        let cameraSpace = simd_inverse(camera.transformMatrix(relativeTo: nil))
            * SIMD4<Float>(worldCenter.x, worldCenter.y, worldCenter.z, 1)
        var startPosition = SIMD3<Float>(cameraSpace.x, cameraSpace.y, cameraSpace.z)
        // The printed photo occupies an inset rectangle in the page texture
        // (520×610 in a 600×780 layout). Match that visible rectangle so the
        // real photo appears to lift from the page instead of popping in small.
        let pageBounds = source.visualBounds(relativeTo: camera)
        let photoWidthOnPage = pageBounds.extents.x * (520.0 / 600.0)
        let photoHeightOnPage = pageBounds.extents.y * (610.0 / 780.0)
        let extractionScale = min(photoWidthOnPage / width, photoHeightOnPage / height)
        root.scale = SIMD3(repeating: max(extractionScale, 0.001))
        // Move it just off the paper toward the camera to prevent z-fighting.
        startPosition.z += 0.004
        root.position = startPosition
        root.isEnabled = false
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
        pendingOpenDestination = destination
        hasPresentedPhoto = false

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
        guard isOpen, !isTransitioning else { return }

        // Keep the card anchored at its presentation point. Drag rotates the
        // card around its own center on both local axes, like a floating card.
        let width = max(viewportSize.width, 1)
        let height = max(viewportSize.height, 1)
        let yaw = Float(translation.width / width) * 2 * .pi
        let pitchDelta = Float(translation.height / height) * 2 * .pi
        rotation = dragStartRotation + yaw
        pitch = min(max(dragStartPitch + pitchDelta, -.pi / 2), .pi / 2)
        dragYaw = dragStartRotation + yaw
        dragPitch = min(max(dragStartPitch + pitchDelta, -.pi / 2), .pi / 2)
        applyDragOrientation()
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
        stopMotionTracking()
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
            self.motionPivot = nil
            self.cardContent = nil
            self.cardBody = nil
            self.frontSurface = nil
            self.backSurface = nil
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
            self.dragYaw = targetAngle
            self.dragPitch = 0
            self.motionReferenceAttitude = nil
            self.motionYaw = 0
            self.motionPitch = 0
            self.motionPivot?.orientation = simd_quatf()
            self.isBackVisible = toBack
            self.isTransitioning = false
            self.applyDragOrientation()
        }
    }

    private func startMotionTracking() {
        guard motionManager.isDeviceMotionAvailable else { return }
        stopMotionTracking()
        motionManager.deviceMotionUpdateInterval = GalleryConfig.motionUpdateInterval
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        motionReferenceAttitude = nil
        motionYaw = 0
        motionPitch = 0
        motionUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isOpen, !self.isTransitioning,
                      !self.isBackVisible,
                      let attitude = self.motionManager.deviceMotion?.attitude else {
                    try? await Task.sleep(for: .milliseconds(40))
                    continue
                }

                if self.motionReferenceAttitude == nil {
                    self.motionReferenceAttitude = attitude.copy() as? CMAttitude
                } else if let reference = self.motionReferenceAttitude {
                    let relative = attitude.copy() as! CMAttitude
                    relative.multiply(byInverseOf: reference)
                    // A small, bounded response gives a subtle parallax tilt
                    // without changing the card's anchored position.
                    self.motionYaw = min(max(Float(relative.yaw) * 0.55, -0.48), 0.48)
                    self.motionPitch = min(max(Float(relative.pitch) * 0.55, -0.48), 0.48)
                    self.applyMotionOrientation()
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func stopMotionTracking() {
        motionUpdateTask?.cancel()
        motionUpdateTask = nil
        motionManager.stopDeviceMotionUpdates()
        motionReferenceAttitude = nil
        motionYaw = 0
        motionPitch = 0
    }

    private func applyDragOrientation() {
        guard let card else { return }
        rotation = dragYaw
        pitch = dragPitch
        let yawRotation = simd_quatf(angle: dragYaw, axis: [0, 1, 0])
        let pitchRotation = simd_quatf(angle: dragPitch, axis: [1, 0, 0])
        card.orientation = yawRotation * pitchRotation
    }

    private func applyMotionOrientation() {
        let motionYawRotation = simd_quatf(angle: motionYaw, axis: [0, 1, 0])
        let motionPitchRotation = simd_quatf(angle: motionPitch, axis: [1, 0, 0])
        motionPivot?.orientation = motionYawRotation * motionPitchRotation
    }

    private func apply(_ image: UIImage, for token: UUID) {
        guard presentationID == token, let frontSurface else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let normalizedImage = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        guard let cgImage = normalizedImage.cgImage,
              let texture = try? TextureResource(image: cgImage, options: .init(semantic: .color)) else { return }
        updateCardGeometry(for: normalizedImage)
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        frontSurface.model?.materials = [material]
        guard !hasPresentedPhoto, let card, let camera,
              let destination = pendingOpenDestination else { return }
        // Do not show the default portrait card while PhotoKit is still
        // resolving the image orientation. Start the extraction only after
        // the real photo and its matching geometry are ready.
        hasPresentedPhoto = true
        pendingOpenDestination = nil
        card.isEnabled = true
        card.move(to: destination, relativeTo: camera, duration: 0.48, timingFunction: .easeInOut)
    }

    private func updateCardGeometry(for image: UIImage) {
        let ratio = max(image.size.width / max(image.size.height, 1), 0.1)
        photoAspectRatio = ratio

        // Keep the longest edge at the existing card size. The animated root
        // and its depth stay untouched; only the inner model changes shape.
        let longSide: Float = 0.69
        if ratio >= 1 {
            cardWidth = longSide
            cardHeight = longSide / Float(ratio)
        } else {
            cardHeight = longSide
            cardWidth = longSide * Float(ratio)
        }
        cardBody?.model?.mesh = .generateBox(size: [cardWidth, cardHeight, 0.012])
        frontSurface?.model?.mesh = .generatePlane(width: cardWidth * 0.92, height: cardHeight * 0.92)
        backSurface?.model?.mesh = .generatePlane(width: cardWidth * 0.92, height: cardHeight * 0.92)
        updateContentFitScale()
    }

    private func updateContentFitScale() {
        let depth = max(GalleryConfig.albumViewingDistance - 0.17, 0.32)
        let baseScale = depth / 0.88
        let fov = camera?.components[PerspectiveCameraComponent.self]?.fieldOfViewInDegrees ?? 50.2
        let visibleHeight = 2 * depth * tan(fov * .pi / 360)
        let visibleWidth = visibleHeight * Float(viewportSize.width / max(viewportSize.height, 1))
        let widthFit = visibleWidth * 0.88 / max(cardWidth * baseScale, 0.001)
        let heightFit = visibleHeight * 0.88 / max(cardHeight * baseScale, 0.001)
        contentFitScale = min(1, min(widthFit, heightFit))
        cardContent?.scale = [contentFitScale, contentFitScale, 1]
    }

    private func resetState() {
        stopMotionTracking()
        selectedPhotoID = nil
        pendingOpenDestination = nil
        hasPresentedPhoto = false
        isBackVisible = false
        isTransitioning = false
        isLoadingPhoto = false
        photoLoadFailed = false
        photoAspectRatio = 0.54 / 0.69
        cardWidth = 0.54
        cardHeight = 0.69
        contentFitScale = 1
        motionPivot?.orientation = simd_quatf()
        motionPivot = nil
        rotation = 0
        pitch = 0
        dragYaw = 0
        dragPitch = 0
    }
}
