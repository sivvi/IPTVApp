import Foundation

struct EPGData {
    var sourceUrl: String
    var channels: [EPGChannel]
    var programs: [Program]
    var lastUpdated: Date
}

extension EPGData: Codable {}
extension EPGData: Equatable {}
