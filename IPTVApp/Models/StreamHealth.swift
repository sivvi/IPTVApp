import Foundation

struct StreamHealth {
    let channelId: String
    let pingMs: Int?
    let httpStatus: Int?
    let contentType: String?
    var thumbnailData: Data?
    let checkedAt: Date

    var isReachable: Bool {
        // TCP ping success is sufficient — many streaming servers don't support HEAD
        // or return 302/403 even though AVPlayer can play the stream just fine.
        pingMs != nil
    }

    var streamType: String {
        guard let ct = contentType else { return "—" }
        if ct.contains("mpegurl") || ct.contains("x-mpegURL") { return "HLS" }
        if ct.contains("mp2t") { return "TS" }
        if ct.contains("rtmp") { return "RTMP" }
        if ct.contains("rtsp") { return "RTSP" }
        return "HTTP"
    }

    // Combined health: 0=dead, 1=degraded, 2=healthy
    var healthLevel: Int {
        guard isReachable else { return 0 }
        if let ms = pingMs, ms < 100 { return 2 }
        return 1
    }
}
