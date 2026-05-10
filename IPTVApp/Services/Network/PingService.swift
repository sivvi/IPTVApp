import Foundation

final class PingService {

    static let shared = PingService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        config.httpMaximumConnectionsPerHost = 1
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config)
    }()

    private init() {}

    struct ProbeResult {
        let latencyMs: Int?
        let contentType: String?
    }

    /// Probes a stream URL via HTTP HEAD, returning latency and Content-Type header.
    /// Fully async — no semaphore blocking on the caller thread.
    func probe(url: URL, timeout: TimeInterval = 3.0, completion: @escaping (ProbeResult) -> Void) {
        let startTime = CFAbsoluteTimeGetCurrent()

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "HEAD"

        let task = session.dataTask(with: request) { _, response, _ in
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(ProbeResult(latencyMs: nil, contentType: nil))
                return
            }
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            let contentType = (httpResponse.allHeaderFields["Content-Type"] as? String)
                ?? (httpResponse.allHeaderFields["content-type"] as? String)
            completion(ProbeResult(latencyMs: Int(elapsed), contentType: contentType))
        }
        task.resume()
    }
}
