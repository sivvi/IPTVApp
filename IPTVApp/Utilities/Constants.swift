import Foundation

enum Constants {
    static let apiTimeout: TimeInterval = 30
    static let imageCacheExpiry: TimeInterval = 86400 * 7
    static let epgCacheExpiry: TimeInterval = 86400 * 3
    static let defaultBufferSize = 3000
    static let appName = "IPTVApp"
    static let maxRetryCount = 3
    static let bufferingTimeout: TimeInterval = 15
    static let streamTimeout: TimeInterval = 60
    static let castingHeartbeatInterval: TimeInterval = 10
    static let controlBarAutoHideDelay: TimeInterval = 3
}
