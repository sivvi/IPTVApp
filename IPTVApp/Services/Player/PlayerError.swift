import Foundation

enum PlayerError: Error, Equatable {
    case streamNotFound
    case playbackFailed(String)
    case networkUnavailable
    case bufferingTimeout
    case castFailed(String)
    case unknown

    var localizedDescription: String {
        switch self {
        case .streamNotFound:    return "无法找到流地址"
        case .playbackFailed(let msg): return "播放失败：\(msg)"
        case .networkUnavailable: return "网络不可用"
        case .bufferingTimeout:  return "缓冲超时"
        case .castFailed(let msg): return "投屏失败：\(msg)"
        case .unknown:           return "未知错误"
        }
    }
}
