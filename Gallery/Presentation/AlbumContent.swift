import Foundation

struct AlbumContent: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let photos: [PhotoReference]
}

extension GalleryLibraryModel {
    /// Temporary mapping: slots 0...7 are recent years; slot 8 is Favorites.
    /// Model names and spatial placement remain an Experience concern.
    func albums(forBoxSlot slot: Int) -> [AlbumContent] {
        if slot == 8 {
            guard !favorites.isEmpty else { return [] }
            return [AlbumContent(id: "favorites", title: String(localized: "album.favorites"), photos: favorites)]
        }
        guard years.indices.contains(slot) else { return [] }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        let months = formatter.monthSymbols ?? []
        return years[slot].albums.map { album in
            let month = months.indices.contains(album.month - 1) ? months[album.month - 1].capitalized : "\(album.month)"
            return AlbumContent(id: album.id, title: "\(month) · \(album.year)", photos: album.photos)
        }
    }
}
