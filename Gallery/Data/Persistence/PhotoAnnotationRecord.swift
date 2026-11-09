import Foundation
import SwiftData

@Model
final class PhotoAnnotationRecord {
    @Attribute(.unique) var photoIdentifier: String
    var id: UUID
    var drawingData: Data
    var createdAt: Date
    var updatedAt: Date

    init(annotation: PhotoAnnotation) {
        photoIdentifier = annotation.photoIdentifier
        id = annotation.id
        drawingData = annotation.drawingData
        createdAt = annotation.createdAt
        updatedAt = annotation.updatedAt
    }

    @MainActor
    var value: PhotoAnnotation {
        PhotoAnnotation(id: id, photoIdentifier: photoIdentifier, drawingData: drawingData, createdAt: createdAt, updatedAt: updatedAt)
    }
}
