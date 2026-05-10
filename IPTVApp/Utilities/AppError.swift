import Foundation

enum AppError: Error, LocalizedError {
    case parseError(String)
    case databaseError(String)
    case notFound(String)
    case invalidData(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .parseError(let msg):     return "解析错误：\(msg)"
        case .databaseError(let msg):  return "数据库错误：\(msg)"
        case .notFound(let msg):       return "未找到：\(msg)"
        case .invalidData(let msg):    return "数据无效：\(msg)"
        case .networkError(let msg):   return "网络错误：\(msg)"
        }
    }
}
