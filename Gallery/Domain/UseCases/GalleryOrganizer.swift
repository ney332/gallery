import Foundation

enum GalleryOrganizer {
    private struct YearMonth: Hashable {
        let year: Int
        let month: Int
    }

    static func organize(_ photos: [PhotoReference], recentYearLimit: Int = 8, calendar: Calendar = .current) -> [GalleryYear] {
        let dated = photos.filter { $0.creationDate != nil }
        let grouped = Dictionary(grouping: dated) { photo in
            let date = photo.creationDate!
            return YearMonth(year: calendar.component(.year, from: date), month: calendar.component(.month, from: date))
        }

        let albums = grouped.map { key, values in
            MonthlyAlbum(year: key.year, month: key.month, photos: values.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) })
        }
        let years = Dictionary(grouping: albums, by: \.year).map { year, albums in
            GalleryYear(year: year, albums: albums.sorted { $0.month < $1.month })
        }.sorted { $0.year > $1.year }
        return Array(years.prefix(max(0, recentYearLimit)))
    }

    static func favorites(from photos: [PhotoReference]) -> [PhotoReference] {
        photos.filter(\.isFavorite).sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
    }
}
