import Foundation
import Combine
import Kingfisher

enum PlaybackQuality: String, CaseIterable {
    case auto = "自动"
    case low = "流畅优先"
    case medium = "均衡"
    case high = "高清优先"
}

enum EPGRefreshInterval: String, CaseIterable {
    case manual = "手动"
    case daily = "每天"
    case every3Days = "每3天"
}

enum AppTheme: String, CaseIterable {
    case system = "跟随系统"
    case light = "浅色"
    case dark = "深色"
}

final class SettingsViewModel: BaseViewModel {

    // MARK: - Playback

    @Published var hardwareDecoding: Bool {
        didSet { save(.hardwareDecoding, value: hardwareDecoding) }
    }
    @Published var preferredQuality: PlaybackQuality {
        didSet { save(.preferredQuality, value: preferredQuality.rawValue) }
    }
    @Published var backgroundPlayback: Bool {
        didSet { save(.backgroundPlayback, value: backgroundPlayback) }
    }
    @Published var autoResume: Bool {
        didSet { save(.autoResume, value: autoResume) }
    }

    // MARK: - EPG

    @Published var epgRefreshInterval: EPGRefreshInterval {
        didSet { save(.epgRefreshInterval, value: epgRefreshInterval.rawValue) }
    }
    @Published var epgCacheDays: Int {
        didSet { save(.epgCacheDays, value: epgCacheDays) }
    }

    // MARK: - Appearance

    @Published var theme: AppTheme {
        didSet { save(.appTheme, value: theme.rawValue) }
    }

    // MARK: - Cache (computed)

    @Published var cacheSizeText: String = "计算中..."

    // MARK: - Stats

    @Published var playlistCount: Int = 0
    @Published var channelCount: Int = 0

    let appVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }()

    private enum Key: String {
        case hardwareDecoding, preferredQuality, backgroundPlayback
        case autoResume, epgRefreshInterval, epgCacheDays, appTheme
    }

    private let defaults = UserDefaults.standard

    override init() {
        self.hardwareDecoding = Self.load(.hardwareDecoding, defaultValue: true)
        self.preferredQuality = Self.loadEnum(.preferredQuality, defaultValue: .auto)
        self.backgroundPlayback = Self.load(.backgroundPlayback, defaultValue: true)
        self.autoResume = Self.load(.autoResume, defaultValue: true)
        self.epgRefreshInterval = Self.loadEnum(.epgRefreshInterval, defaultValue: .daily)
        self.epgCacheDays = Self.load(.epgCacheDays, defaultValue: 3)
        self.theme = Self.loadEnum(.appTheme, defaultValue: .system)
        super.init()
    }

    // MARK: - Public

    func refreshStats() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            do {
                let playlists = try DatabaseManager.shared.fetchAllPlaylists()
                let channels = try DatabaseManager.shared.fetchAllChannels()
                let dbSize = try DatabaseManager.shared.databaseFileSize()
                let imgSize = Self.imageCacheDiskSize()
                let total = dbSize + imgSize
                DispatchQueue.main.async {
                    self.playlistCount = playlists.count
                    self.channelCount = channels.count
                    self.cacheSizeText = Self.formatBytes(total)
                }
            } catch {
                DispatchQueue.main.async {
                    self.cacheSizeText = "无法获取"
                }
            }
        }
    }

    func clearCache() {
        isLoading.send(true)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            do {
                let cutoff = Date().addingTimeInterval(-86400 * 3)
                let deleted = try DatabaseManager.shared.deleteExpiredPrograms(before: cutoff)
                ImageCache.default.clearDiskCache()
                URLCache.shared.removeAllCachedResponses()
                Logger.general.info("缓存已清理, 删除\(deleted)条过期节目")
                DispatchQueue.main.async {
                    self.isLoading.send(false)
                    self.refreshStats()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading.send(false)
                    self.errorMessage.send("清理失败: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Private

    private func save(_ key: Key, value: Any) {
        defaults.set(value, forKey: "settings.\(key.rawValue)")
    }

    private static func load<T>(_ key: Key, defaultValue: T) -> T {
        let k = "settings.\(key.rawValue)"
        if let v = UserDefaults.standard.object(forKey: k) as? T { return v }
        return defaultValue
    }

    private static func loadEnum<T: RawRepresentable>(_ key: Key, defaultValue: T) -> T where T.RawValue == String {
        let k = "settings.\(key.rawValue)"
        guard let raw = UserDefaults.standard.string(forKey: k),
              let v = T(rawValue: raw) else { return defaultValue }
        return v
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private static func imageCacheDiskSize() -> Int64 {
        final class Box { var value: Int64 = 0 }
        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)
        ImageCache.default.calculateDiskStorageSize { r in
            if case .success(let s) = r { box.value = Int64(s) }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
        return box.value
    }
}
