import Foundation
import AVKit
import CoreImage

final class StreamHealthService {

    static let shared = StreamHealthService()

    private let thumbnailCache = NSCache<NSString, NSData>()
    private var pendingOperations: [String: Operation] = [:]

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
        var op: BlockOperation!
        op = BlockOperation { [weak self] in
            guard !op.isCancelled else { return }
            // 1. HTTP HEAD probe
            let probeGroup = DispatchGroup()
            var probeResult: PingService.ProbeResult?

            probeGroup.enter()
            PingService.shared.probe(url: url) { result in
                probeResult = result
                probeGroup.leave()
            }
            _ = probeGroup.wait(timeout: .now() + 5)

            if op.isCancelled { return }
            let result = probeResult ?? PingService.ProbeResult(latencyMs: nil, contentType: nil)

            // 2. Check thumbnail cache
            var thumbnailData: Data?
            if let cached = self?.thumbnailCache.object(forKey: channelId as NSString) as Data? {
                thumbnailData = cached
            }

            // 3. Generate thumbnail inline if reachable and not cached
            if result.latencyMs != nil, thumbnailData == nil {
                if op.isCancelled { return }
                thumbnailData = self?.captureThumbnail(url: url, channelId: channelId)
            }

            if op.isCancelled { return }

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
        pendingOperations[channelId] = op
        op.completionBlock = { [weak self] in
            self?.pendingOperations.removeValue(forKey: channelId)
        }
        healthQueue.addOperation(op)
    }

    func cancelHealthCheck(for channelId: String) {
        pendingOperations[channelId]?.cancel()
        pendingOperations.removeValue(forKey: channelId)
    }

    // MARK: - Thumbnail

    private func captureThumbnail(url: URL, channelId: String) -> Data? {
        if isHLSStream(url) {
            return captureViaPlayer(url: url, channelId: channelId)
        }
        return captureFromAsset(url: url, channelId: channelId, timeout: 4)
    }

    private func isHLSStream(_ url: URL) -> Bool {
        let urlString = url.absoluteString.lowercased()
        let path = url.lastPathComponent.lowercased()
        if path.hasSuffix(".m3u8") || path.hasSuffix(".m3u") { return true }
        if urlString.contains(".m3u8") || urlString.contains("application/x-mpegurl")
            || urlString.contains("application/vnd.apple.mpegurl") { return true }
        return false
    }

    private func captureFromAsset(url: URL, channelId: String, timeout: Int = 4) -> Data? {
        let asset = AVURLAsset(url: url)
        let trackKey = "tracks"

        let semaphore = DispatchSemaphore(value: 0)
        var hasVideo = false
        asset.loadValuesAsynchronously(forKeys: [trackKey]) {
            hasVideo = (asset.tracks(withMediaType: .video).first != nil)
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + .seconds(timeout)) == .success, hasVideo else { return nil }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 180)
        // Use loose tolerances — let the generator pick any nearby keyframe.
        generator.requestedTimeToleranceBefore = .init(seconds: 10, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = .init(seconds: 3, preferredTimescale: 600)

        // Live streams often have no frame at .zero. Try several times.
        let tryTimes: [CMTime] = [
            CMTime(seconds: 2, preferredTimescale: 600),
            CMTime(seconds: 5, preferredTimescale: 600),
            .zero
        ]
        for time in tryTimes {
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                return encodeAndCache(cgImage, channelId: channelId)
            }
        }
        return nil
    }

    /// Plays a muted AVPlayer for up to 12 seconds, captures the first decoded video frame
    /// via AVPlayerItemVideoOutput, then stops. Returns JPEG data or nil on timeout/failure.
    private func captureViaPlayer(url: URL, channelId: String) -> Data? {
        let player = AVPlayer()
        player.isMuted = true
        player.volume = 0

        let item = AVPlayerItem(url: url)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 320
        ])
        item.add(output)

        player.replaceCurrentItem(with: item)
        player.play()

        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.3)
            let time = item.currentTime()
            guard time.isValid else { continue }
            // Poll until a new pixel buffer is available, then copy it.
            guard output.hasNewPixelBuffer(forItemTime: time) else { continue }
            guard let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { continue }

            player.pause()
            player.replaceCurrentItem(with: nil)

            let ciImage = CIImage(cvPixelBuffer: buffer)
            let context = CIContext()
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { break }
            return encodeAndCache(cgImage, channelId: channelId)
        }

        player.pause()
        player.replaceCurrentItem(with: nil)
        return nil
    }

    private func encodeAndCache(_ cgImage: CGImage, channelId: String) -> Data? {
        let uiImage = UIImage(cgImage: cgImage)
        guard let data = uiImage.jpegData(compressionQuality: 0.7) else { return nil }
        thumbnailCache.setObject(data as NSData, forKey: channelId as NSString)
        return data
    }
}
