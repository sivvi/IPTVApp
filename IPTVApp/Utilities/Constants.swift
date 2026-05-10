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

    // DLNA / SSDP
    static let ssdpMulticastAddress = "239.255.255.250"
    static let ssdpPort: UInt16 = 1900
    static let ssdpDiscoveryTimeout: TimeInterval = 5.0
    static let dlnaSoapTimeout: TimeInterval = 10.0
    static let dlnaPositionPollInterval: TimeInterval = 1.0
    static let dlnaMaxReconnectAttempts = 3
    static let cachedDeviceKey = "com.iptvapp.cachedDevice"
}
