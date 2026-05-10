import Foundation
import Combine

final class EPGService {
    static let shared = EPGService()

    private let session: URLSession
    private let parser = XMLTVParser()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Constants.apiTimeout
        config.timeoutIntervalForResource = 120
        session = URLSession(configuration: config)
    }

    // MARK: - Public

    func loadEPG(from url: URL) -> AnyPublisher<Void, AppError> {
        Logger.parser.info("开始加载EPG: \(url.absoluteString)")

        return session.dataTaskPublisher(for: url)
            .tryMap { [weak self] data, response -> EPGData in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AppError.networkError("无效响应")
                }
                guard (200...299).contains(httpResponse.statusCode) else {
                    throw AppError.networkError("HTTP \(httpResponse.statusCode)")
                }
                guard let self else { throw AppError.networkError("服务已释放") }
                return try self.parser.parse(xml: data)
            }
            .tryMap { epgData -> Void in
                do {
                    try DatabaseManager.shared.insertPrograms(epgData.programs)
                    let lastKey = "epg_last_updated_\(url.absoluteString.hashValue)"
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastKey)
                    UserDefaults.standard.set(url.absoluteString, forKey: "epg_source_url")
                    Logger.parser.info("EPG加载完成: \(epgData.programs.count)个节目")
                } catch {
                    Logger.parser.error("EPG写入数据库失败: \(error.localizedDescription)")
                    throw AppError.databaseError(error.localizedDescription)
                }
            }
            .mapError { error in
                (error as? AppError) ?? AppError.networkError(error.localizedDescription)
            }
            .eraseToAnyPublisher()
    }

    func fetchPrograms(for channelIds: [String], date: Date) throws -> [String: [Program]] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        var result: [String: [Program]] = [:]
        for channelId in channelIds {
            let programs = try DatabaseManager.shared.fetchPrograms(
                for: channelId,
                from: startOfDay,
                to: endOfDay
            )
            if !programs.isEmpty {
                result[channelId] = programs
            }
        }
        return result
    }

    func fetchCurrentProgram(for channelId: String) throws -> Program? {
        try DatabaseManager.shared.fetchCurrentProgram(for: channelId)
    }

    func fetchNextProgram(for channelId: String) throws -> Program? {
        try DatabaseManager.shared.fetchNextProgram(for: channelId)
    }

    func cleanupExpired() {
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
        do {
            let count = try DatabaseManager.shared.deleteExpiredPrograms(before: threeDaysAgo)
            if count > 0 {
                Logger.database.info("清理了\(count)个过期节目")
            }
        } catch {
            Logger.database.error("清理过期节目失败: \(error.localizedDescription)")
        }
    }

    func lastUpdated(for url: URL) -> Date? {
        let key = "epg_last_updated_\(url.absoluteString.hashValue)"
        let interval = UserDefaults.standard.double(forKey: key)
        guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    var epgSourceURL: URL? {
        guard let str = UserDefaults.standard.string(forKey: "epg_source_url") else { return nil }
        return URL(string: str)
    }
}
