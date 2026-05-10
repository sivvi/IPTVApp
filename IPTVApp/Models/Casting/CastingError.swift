import Foundation

enum CastingError: Error, Equatable {
    case discoveryTimeout
    case deviceUnreachable
    case connectionFailed(String)
    case soapError(String)
    case unsupportedAction(String)
    case heartbeatLost
    case networkUnavailable
    case airPlayNotAvailable
    case noDeviceSelected

    var localizedDescription: String {
        switch self {
        case .discoveryTimeout:
            return "设备搜索超时，请重试"
        case .deviceUnreachable:
            return "设备无法连接"
        case .connectionFailed(let reason):
            return "连接失败：\(reason)"
        case .soapError(let reason):
            return "控制命令失败：\(reason)"
        case .unsupportedAction(let action):
            return "设备不支持：\(action)"
        case .heartbeatLost:
            return "投屏连接已断开"
        case .networkUnavailable:
            return "网络不可用"
        case .airPlayNotAvailable:
            return "AirPlay 不可用"
        case .noDeviceSelected:
            return "未选择投屏设备"
        }
    }
}
