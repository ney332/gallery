import Foundation

protocol AnnotationRepository: Sendable {
    func save(_ annotation: PhotoAnnotation) async throws
    func find(for photoID: String) async throws -> PhotoAnnotation?
    func delete(for photoID: String) async throws
}
