import Foundation
import SwiftData

@MainActor
final class SwiftDataAnnotationRepository: AnnotationRepository {
    private let context: ModelContext

    init(container: ModelContainer) {
        context = ModelContext(container)
    }

    func save(_ annotation: PhotoAnnotation) async throws {
        let photoID = annotation.photoIdentifier
        let descriptor = FetchDescriptor<PhotoAnnotationRecord>(predicate: #Predicate { $0.photoIdentifier == photoID })
        if let existing = try context.fetch(descriptor).first {
            existing.id = annotation.id
            existing.drawingData = annotation.drawingData
            existing.updatedAt = annotation.updatedAt
        } else {
            context.insert(PhotoAnnotationRecord(annotation: annotation))
        }
        try context.save()
    }

    func find(for photoID: String) async throws -> PhotoAnnotation? {
        let descriptor = FetchDescriptor<PhotoAnnotationRecord>(predicate: #Predicate { $0.photoIdentifier == photoID })
        return try context.fetch(descriptor).first?.value
    }

    func delete(for photoID: String) async throws {
        let descriptor = FetchDescriptor<PhotoAnnotationRecord>(predicate: #Predicate { $0.photoIdentifier == photoID })
        for record in try context.fetch(descriptor) { context.delete(record) }
        try context.save()
    }
}
