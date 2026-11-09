import Foundation

protocol PhotoLibraryRepository: Sendable {
    func requestReadAccess() async -> PhotoLibraryAccess
    func fetchPhotos() async throws -> [PhotoReference]
    func fetchFavorites() async throws -> [PhotoReference]
    func photoExists(id: String) async -> Bool
}

enum PhotoLibraryAccess: Sendable, Equatable {
    case notDetermined
    case authorized
    case limited
    case denied
    case restricted
}
