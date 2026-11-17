/// The first spread starts on the right, leaving the inside cover empty.
/// Subsequent spreads contain up to two photos in chronological order.
struct PhotoPage: Identifiable, Sendable {
    let number: Int
    let photos: [PhotoReference]
    var id: Int { number }
    var startsOnRight: Bool { number == 1 }

    func photoIndex(forSlot slot: Int) -> Int? {
        guard slot == 0 || slot == 1 else { return nil }
        if startsOnRight { return slot == 1 && !photos.isEmpty ? 0 : nil }
        return photos.indices.contains(slot) ? slot : nil
    }

    var firstPhotoNumber: Int { startsOnRight ? 1 : (number - 1) * 2 }

    static func paginate(_ photos: [PhotoReference]) -> [PhotoPage] {
        guard let first = photos.first else { return [] }
        var pages = [PhotoPage(number: 1, photos: [first])]
        for offset in stride(from: 1, to: photos.count, by: 2) {
            pages.append(PhotoPage(number: pages.count + 1,
                                   photos: Array(photos[offset..<min(offset + 2, photos.count)])))
        }
        return pages
    }
}
