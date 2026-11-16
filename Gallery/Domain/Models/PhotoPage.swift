/// The cover is a separate navigation position, never an empty photo page.
struct PhotoPage: Identifiable, Sendable {
    let number: Int
    let photos: [PhotoReference]
    var id: Int { number }

    static func paginate(_ photos: [PhotoReference]) -> [PhotoPage] {
        stride(from: 0, to: photos.count, by: 2).map { offset in
            PhotoPage(number: offset / 2 + 1,
                      photos: Array(photos[offset..<min(offset + 2, photos.count)]))
        }
    }
}
