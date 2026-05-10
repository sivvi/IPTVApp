import Foundation
import GRDB

struct Channel {
    var id: String
    var name: String
    var url: String
    var logoUrl: String?
    var group: String?
    var epgId: String?
    var playlistId: String?
    var isFavorite: Bool = false
    var sortOrder: Int = 0
}

extension Channel: Codable {}
extension Channel: Equatable {}
extension Channel: Hashable {}
extension Channel: Identifiable {}

extension Channel: FetchableRecord, PersistableRecord {
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let url = Column(CodingKeys.url)
        static let logoUrl = Column(CodingKeys.logoUrl)
        static let group = Column(CodingKeys.group)
        static let epgId = Column(CodingKeys.epgId)
        static let playlistId = Column(CodingKeys.playlistId)
        static let isFavorite = Column(CodingKeys.isFavorite)
        static let sortOrder = Column(CodingKeys.sortOrder)
    }
}

extension Channel {
    static func generateId(from url: String) -> String {
        String(format: "%016lx", UInt64(bitPattern: Int64(url.hashValue)))
    }
}
