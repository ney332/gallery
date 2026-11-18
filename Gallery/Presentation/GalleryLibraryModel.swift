import Foundation
import Observation

@MainActor
@Observable
final class GalleryLibraryModel {
    private let photoRepository: any PhotoLibraryRepository
    private let annotationRepository: any AnnotationRepository
    private var changeObserver: PhotoLibraryChangeObserver?
    private var previousPhotoIDs: Set<String> = []

    private(set) var access: PhotoLibraryAccess = .notDetermined
    private(set) var years: [GalleryYear] = []
    private(set) var favorites: [PhotoReference] = []
    private(set) var isLoading = false
    private(set) var loadFailed = false

    init(photoRepository: any PhotoLibraryRepository, annotationRepository: any AnnotationRepository) {
        self.photoRepository = photoRepository
        self.annotationRepository = annotationRepository
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        access = await photoRepository.requestReadAccess()
        guard access == .authorized || access == .limited else { return }
        await refreshLibrary(isConfirmedFullAccess: access == .authorized)
        if changeObserver == nil {
            changeObserver = PhotoLibraryChangeObserver { [weak self] in
                Task { @MainActor in await self?.reloadAfterChange() }
            }
        }
    }

    func annotation(for photoID: String) async throws -> PhotoAnnotation? {
        try await annotationRepository.find(for: photoID)
    }

    func saveAnnotationDrawing(_ drawingData: Data, for photoID: String) async throws {
        guard !drawingData.isEmpty else {
            try await annotationRepository.delete(for: photoID)
            return
        }
        let existing = try await annotationRepository.find(for: photoID)
        let annotation = PhotoAnnotation(
            id: existing?.id ?? UUID(),
            photoIdentifier: photoID,
            drawingData: drawingData,
            createdAt: existing?.createdAt ?? .now,
            updatedAt: .now
        )
        try await annotationRepository.save(annotation)
    }

    private func reloadAfterChange() async {
        let currentAccess = await photoRepository.requestReadAccess()
        access = currentAccess
        guard currentAccess == .authorized || currentAccess == .limited else { return }
        await refreshLibrary(isConfirmedFullAccess: currentAccess == .authorized)
    }

    private func refreshLibrary(isConfirmedFullAccess: Bool) async {
        do {
            let photos = try await photoRepository.fetchPhotos()
            let favoritePhotos = try await photoRepository.fetchFavorites()
            let currentIDs = Set(photos.map(\.id))

            if isConfirmedFullAccess, !previousPhotoIDs.isEmpty {
                let removedIDs = previousPhotoIDs.subtracting(currentIDs)
                for photoID in removedIDs {
                    try await annotationRepository.delete(for: photoID)
                }
            }

            if isConfirmedFullAccess {
                previousPhotoIDs = currentIDs
            }
            years = GalleryOrganizer.organize(photos)
            favorites = GalleryOrganizer.favorites(from: favoritePhotos)
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }
}
