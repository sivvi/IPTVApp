import Foundation
import GRDB

struct Program {
    var id: String
    var channelId: String
    var title: String
    var description: String?
    var startTime: Date
    var endTime: Date
    var category: String?
}

extension Program: Codable {}
extension Program: Equatable {}
extension Program: Hashable {}
extension Program: Identifiable {}

extension Program: FetchableRecord, PersistableRecord {
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let channelId = Column(CodingKeys.channelId)
        static let title = Column(CodingKeys.title)
        static let description = Column(CodingKeys.description)
        static let startTime = Column(CodingKeys.startTime)
        static let endTime = Column(CodingKeys.endTime)
        static let category = Column(CodingKeys.category)
    }
}

extension Program {
    static func generateId(channelId: String, startTime: Date) -> String {
        "\(channelId)_\(Int(startTime.timeIntervalSince1970))"
    }
}
