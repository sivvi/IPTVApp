import Foundation

protocol PlaylistParser: AnyObject {
    func parse(content: String) throws -> [Channel]
}
