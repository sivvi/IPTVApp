import Foundation
import AVKit

final class StreamHealthService {

    static let shared = StreamHealthService()

    private let thumbnailCache = NSCache<NSString, NSData>()

    private let healthQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 4
        q.qualityOfService = .utility
        return q
    }()

    private init() {}

    // MARK: - Public

    /// Checks stream health and optionally generates a thumbnail.
    /// Completion is called exactly once with all available data.
    func checkHealth(channelId: String, url: URL,
                     completion: @escaping (StreamHealth) -> Void) {
        healthQueue.addOperation { [weak self] in
            // 1. HTTP HEAD probe
            let probeGroup = DispatchGroup()
            var probeResult: PingService.ProbeResult?

            probeGroup.enter()
            PingService.shared.probe(url: url) { result in
                probeResult = result
                probeGroup.leave()
            }
            _ = probeGroup.wait(timeout: .now() + 5)

            let result = probeResult ?? PingService.ProbeResult(latencyMs: nil, contentType: nil)

            // 2. Check thumbnail cache
            var thumbnailData: Data?
            if let cached = self?.thumbnailCache.object(forKey: channelId as NSString) as Data? {
                thumbnailData = cached
            }

            // 3. Generate thumbnail inline if reachable and not cached
            if result.latencyMs != nil, thumbnailData == nil {
                thumbnailData = self?.captureThumbnail(url: url, channelId: channelId)
            }

            // 4. Single completion with all data
            let health = StreamHealth(
                channelId: channelId,
                pingMs: result.latencyMs,
                httpStatus: result.latencyMs != nil ? 200 : nil,
                contentType: result.contentType,
                thumbnailData: thumbnailData,
                checkedAt: Date()
            )
            completion(health)
        }
    }

    // MARK: - Thumbnail

    /// Captures a frame from the stream. For HLS (.m3u8), downloads the playlist first to find
    /// a direct TS segment URL, then generates an image from that segment.
    private func captureThumbnail(url: URL, channelId: String) -> Data? {
        // Try direct capture first (works for direct TS/MP4 links)
        if let data = captureFromAsset(url: url, channelId: channelId) {
            return data
        }

        // If the URL looks like HLS, try downloading the playlist and grabbing the first segment
        let path = url.lastPathComponent.lowercased()
        if path.hasSuffix(".m3u8") || path.hasSuffix("m3u") || path.contains("m3u8") {
            return captureFromHLSSegment(playlistURL: url, channelId: channelId)
        }

        return nil
    }

    private func captureFromAsset(url: URL, channelId: String) -> Data? {
        let asset = AVURLAsset(url: url)
        let loadGroup = DispatchGroup()
        var hasVideo = false

        loadGroup.enter()
        asset.loadValuesAsynchronously(forKeys: ["tracks", "playable"]) {
            hasVideo = (asset.tracks(withMediaType: .video).first != nil)
            loadGroup.leave()
        }

        guard loadGroup.wait(timeout: .now() + 4) == .success, hasVideo else { return nil }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 90)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return encodeAndCache(cgImage, channelId: channelId)
    }

    private func captureFromHLSSegment(playlistURL: URL, channelId: String) -> Data? {
        // Download the M3U8 playlist
        let playlistGroup = DispatchGroup()
        var playlistData: Data?

        playlistGroup.enter()
        URLSession.shared.dataTask(with: playlistURL) { data, _, _ in
            playlistData = data
            playlistGroup.leave()
        }.resume()

        guard playlistGroup.wait(timeout: .now() + 4) == .success,
              let data = playlistData,
              let text = String(data: data, encoding: .utf8) else { return nil }

        // Find the first media segment URL (non-comment line after #EXTINF)
        let lines = text.components(separatedBy: .newlines)
        var foundExtinf = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#EXTINF:") {
                foundExtinf = true
            } else if foundExtinf, !trimmed.isEmpty, !trimmed.hasPrefix("#") {
                // Resolve relative URL
                guard let segmentURL = URL(string: trimmed, relativeTo: playlistURL)?.absoluteURL else {
                    foundExtinf = false
                    continue
                }
                return captureFromAsset(url: segmentURL, channelId: channelId)
            }
        }

        return nil
    }

    private func encodeAndCache(_ cgImage: CGImage, channelId: String) -> Data? {
        let uiImage = UIImage(cgImage: cgImage)
        guard let data = uiImage.jpegData(compressionQuality: 0.7) else { return nil }
        thumbnailCache.setObject(data as NSData, forKey: channelId as NSString)
        return data
    }
}
