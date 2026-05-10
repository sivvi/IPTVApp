import Foundation
import Combine

final class PlaylistDownloader {
    static let shared = PlaylistDownloader()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Constants.apiTimeout
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
    }

    private static let supportedEncodings: [String.Encoding] = [
        .utf8,
        .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))),
        .windowsCP1252,
        .isoLatin1,
        .japaneseEUC,
        .windowsCP1250,
        .windowsCP1251,
    ]

    func download(from url: URL) -> AnyPublisher<String, AppError> {
        session.dataTaskPublisher(for: url)
            .tryMap { data, response -> String in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AppError.networkError("无效响应")
                }
                guard (200...299).contains(httpResponse.statusCode) else {
                    throw AppError.networkError("HTTP \(httpResponse.statusCode)")
                }
                for encoding in Self.supportedEncodings {
                    if let str = String(data: data, encoding: encoding) {
                        return str
                    }
                }
                throw AppError.networkError("无法解码播放列表内容")
            }
            .mapError { error in
                (error as? AppError) ?? AppError.networkError(error.localizedDescription)
            }
            .eraseToAnyPublisher()
    }
}
