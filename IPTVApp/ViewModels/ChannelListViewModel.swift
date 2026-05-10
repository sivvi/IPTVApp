import Foundation
import Combine

final class ChannelListViewModel: BaseViewModel {

    @Published var groupedChannels: [(group: String, channels: [Channel])] = []
    @Published var searchQuery: String = ""
    @Published var playlists: [Playlist] = []
    @Published var streamHealth: [String: StreamHealth] = [:]

    private var currentPrograms: [String: Program] = [:]
    private var allChannels: [Channel] = []
    private var healthRefreshToken = 0

    override init() {
        super.init()
        $searchQuery
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] query in
                self?.applyFilter(query: query)
            }
            .store(in: &cancellables)
    }

    // MARK: - Public

    func loadChannels() {
        isLoading.send(true)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let channels = try DatabaseManager.shared.fetchAllChannels()
                let ids = channels.map(\.id)
                let programs = (try? DatabaseManager.shared.fetchCurrentPrograms(for: ids)) ?? [:]
                DispatchQueue.main.async {
                    self.allChannels = channels
                    self.currentPrograms = programs
                    self.applyGrouping()
                    self.isLoading.send(false)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading.send(false)
                    self.errorMessage.send("加载频道失败: \(error.localizedDescription)")
                    Logger.general.error("加载频道失败: \(error.localizedDescription)")
                }
            }
        }
    }

    func loadPlaylist(from url: URL) {
        isLoading.send(true)

        PlaylistDownloader.shared.download(from: url)
            .tryMap { content -> ([Channel], Playlist) in
                let channels = try M3UParser().parse(content: content)
                let playlist = Playlist(
                    name: url.lastPathComponent,
                    sourceUrl: url.absoluteString,
                    lastUpdated: Date()
                )
                return (channels, playlist)
            }
            .receive(on: DispatchQueue.global(qos: .utility))
            .tryMap { channels, playlist -> Void in
                try DatabaseManager.shared.insertPlaylist(playlist)
                var tagged = channels
                for i in tagged.indices {
                    tagged[i].playlistId = playlist.id
                }
                try DatabaseManager.shared.insertChannels(tagged)
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading.send(false)
                if case .failure(let error) = completion {
                    let msg = (error as? AppError)?.errorDescription ?? error.localizedDescription
                    self?.errorMessage.send(msg)
                }
            } receiveValue: { [weak self] in
                self?.loadChannels()
                self?.loadPlaylists()
            }
            .store(in: &cancellables)
    }

    func loadPlaylistFromLocalFile(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage.send("无法访问文件")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        isLoading.send(true)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let channels = try M3UParser().parse(content: content)
                let playlist = Playlist(
                    name: url.lastPathComponent,
                    sourceUrl: url.lastPathComponent,
                    lastUpdated: Date()
                )
                try DatabaseManager.shared.insertPlaylist(playlist)
                var tagged = channels
                for i in tagged.indices { tagged[i].playlistId = playlist.id }
                try DatabaseManager.shared.insertChannels(tagged)

                DispatchQueue.main.async {
                    self?.isLoading.send(false)
                    self?.loadChannels()
                    self?.loadPlaylists()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isLoading.send(false)
                    let msg = (error as? AppError)?.errorDescription ?? error.localizedDescription
                    self?.errorMessage.send(msg)
                }
            }
        }
    }

    func toggleFavorite(channelId: String) {
        do {
            try DatabaseManager.shared.toggleFavorite(channelId: channelId)
            loadChannels()
        } catch {
            errorMessage.send("操作失败: \(error.localizedDescription)")
        }
    }

    func loadPlaylists() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            do {
                let result = try DatabaseManager.shared.fetchAllPlaylists()
                DispatchQueue.main.async {
                    self?.playlists = result
                }
            } catch {
                Logger.general.error("加载播放列表失败: \(error.localizedDescription)")
            }
        }
    }

    func currentProgram(for channelId: String) -> Program? {
        currentPrograms[channelId]
    }

    func health(for channelId: String) -> StreamHealth? {
        streamHealth[channelId]
    }

    func refreshStreamHealth() {
        let channels = allChannels
        guard !channels.isEmpty else { return }

        let token = healthRefreshToken + 1
        healthRefreshToken = token

        let group = DispatchGroup()
        var results: [String: StreamHealth] = [:]
        let resultsLock = NSLock()

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.healthRefreshToken == token else { return }

            for channel in channels {
                guard let url = URL(string: channel.url) else { continue }
                group.enter()
                StreamHealthService.shared.checkHealth(channelId: channel.id, url: url) { health in
                    resultsLock.lock()
                    results[channel.id] = health
                    resultsLock.unlock()
                    group.leave()
                }
            }

            group.notify(queue: .main) { [weak self] in
                guard let self, self.healthRefreshToken == token else { return }
                resultsLock.lock()
                let snapshot = results
                resultsLock.unlock()
                self.streamHealth.merge(snapshot) { _, new in new }
            }
        }
    }

    // MARK: - Private

    private func applyGrouping() {
        let grouped = Dictionary(grouping: allChannels) { $0.group ?? "未分组" }
        groupedChannels = grouped
            .map { (group: $0.key, channels: $0.value.sorted { $0.sortOrder < $1.sortOrder }) }
            .sorted { $0.group.localizedCompare($1.group) == .orderedAscending }
    }

    private func applyFilter(query: String) {
        if query.isEmpty {
            applyGrouping()
        } else {
            let filtered = allChannels.filter {
                $0.name.localizedCaseInsensitiveContains(query) ||
                ($0.group ?? "").localizedCaseInsensitiveContains(query)
            }
            let grouped = Dictionary(grouping: filtered) { $0.group ?? "搜索结果" }
            groupedChannels = grouped
                .map { (group: $0.key, channels: $0.value) }
                .sorted { $0.group.localizedCompare($1.group) == .orderedAscending }
        }
    }
}
