import Foundation

struct PhotoGroup: Identifiable, Hashable, Sendable {
    let year: Int
    let month: Int?
    let photos: [PhotoReference]

    var id: String { month.map { "\(year)-\($0)" } ?? "\(year)" }
}

struct MonthlyAlbum: Identifiable, Hashable, Sendable {
    let year: Int
    let month: Int
    let photos: [PhotoReference]

    var id: String { "\(year)-\(month)" }
    var count: Int { photos.count }
}

struct GalleryYear: Identifiable, Hashable, Sendable {
    let year: Int
    let albums: [MonthlyAlbum]

    var id: Int { year }
    var count: Int { albums.reduce(0) { $0 + $1.count } }
}
