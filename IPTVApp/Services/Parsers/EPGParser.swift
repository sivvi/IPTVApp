import Foundation

protocol EPGParser: AnyObject {
    func parse(xml: Data) throws -> EPGData
}
