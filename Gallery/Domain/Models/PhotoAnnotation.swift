import Foundation

struct PhotoAnnotation: Identifiable, Sendable, Equatable {
    let id: UUID
    let photoIdentifier: String
    var drawingData: Data
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), photoIdentifier: String, drawingData: Data, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.photoIdentifier = photoIdentifier
        self.drawingData = drawingData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
