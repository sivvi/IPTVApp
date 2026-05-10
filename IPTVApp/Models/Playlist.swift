import Foundation
import GRDB

struct Playlist {
    var id: String = UUID().uuidString
    var name: String
    var sourceUrl: String
    var lastUpdated: Date = Date()
    var isDefault: Bool = false
}

extension Playlist: Codable {}
extension Playlist: Equatable {}
extension Playlist: Hashable {}
extension Playlist: Identifiable {}

extension Playlist: FetchableRecord, PersistableRecord {
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let sourceUrl = Column(CodingKeys.sourceUrl)
        static let lastUpdated = Column(CodingKeys.lastUpdated)
        static let isDefault = Column(CodingKeys.isDefault)
    }
}
