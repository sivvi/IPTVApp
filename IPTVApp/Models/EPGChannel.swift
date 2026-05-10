import Foundation

struct EPGChannel {
    var id: String
    var displayName: String
    var iconUrl: String?
}

extension EPGChannel: Codable {}
extension EPGChannel: Equatable {}
extension EPGChannel: Hashable {}
extension EPGChannel: Identifiable {}
