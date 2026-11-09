import Foundation

struct PhotoReference: Identifiable, Hashable, Sendable {
    let id: String
    let creationDate: Date?
    let isFavorite: Bool

    var year: Int? {
        creationDate.map { Calendar.current.component(.year, from: $0) }
    }

    var month: Int? {
        creationDate.map { Calendar.current.component(.month, from: $0) }
    }
}
