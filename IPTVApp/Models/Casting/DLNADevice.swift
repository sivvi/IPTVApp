import Foundation

struct DLNADevice {
    let id: String
    let friendlyName: String
    let manufacturer: String?
    let modelName: String?
    let iconUrl: String?
    let avTransportURL: URL
    let renderingControlURL: URL?
    let baseURL: URL
    let discoveryTimestamp: Date
    var isCached: Bool = false

    var brand: DLNABrand {
        let m = (manufacturer ?? "").lowercased()
        if m.contains("xiaomi") || m.contains("小米") { return .xiaomi }
        if m.contains("hisense") || m.contains("海信") { return .hisense }
        if m.contains("tcl") { return .tcl }
        if m.contains("skyworth") || m.contains("创维") { return .skyworth }
        if m.contains("sony") || m.contains("索尼") { return .sony }
        return .generic
    }
}

enum DLNABrand: String {
    case xiaomi
    case hisense
    case tcl
    case skyworth
    case sony
    case generic
}

extension DLNADevice: Codable {}
extension DLNADevice: Equatable {}
extension DLNADevice: Hashable {}
extension DLNADevice: Identifiable {}
