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

    func loadPlaylist(from url: URL, manualEpgURL: URL? = nil) {
        isLoading.send(true)

        var extractedEpgUrl: String?

        PlaylistDownloader.shared.download(from: url)
            .tryMap { content -> ([Channel], Playlist) in
                let parser = M3UParser()
                let channels = try parser.parse(content: content)
                extractedEpgUrl = parser.epgUrl
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
                if case .failure(let error) = completion {
                    self?.isLoading.send(false)
                    let msg = (error as? AppError)?.errorDescription ?? error.localizedDescription
                    self?.errorMessage.send(msg)
                }
            } receiveValue: { [weak self] in
                self?.loadChannels()
                self?.loadPlaylists()
                // Determine EPG URL: manual > extracted header > auto-discover
                let epgURL: URL? = manualEpgURL
                    ?? extractedEpgUrl.flatMap { URL(string: $0) }
                if let epgURL {
                    self?.loadEPG(from: epgURL, finishLoading: true)
                } else {
                    self?.autoDiscoverEPG(fromPlaylistURL: url)
                }
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
                let parser = M3UParser()
                let channels = try parser.parse(content: content)
                let playlist = Playlist(
                    name: url.lastPathComponent,
                    sourceUrl: url.lastPathComponent,
                    lastUpdated: Date()
                )
                try DatabaseManager.shared.insertPlaylist(playlist)
                var tagged = channels
                for i in tagged.indices { tagged[i].playlistId = playlist.id }
                try DatabaseManager.shared.insertChannels(tagged)

                let epgUrl = parser.epgUrl

                DispatchQueue.main.async {
                    self?.loadChannels()
                    self?.loadPlaylists()
                    if let epgUrlStr = epgUrl, let u = URL(string: epgUrlStr) {
                        self?.loadEPG(from: u, finishLoading: true)
                    } else {
                        self?.isLoading.send(false)
                    }
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

    func loadEPG(from url: URL, finishLoading: Bool = false) {
        EPGService.shared.loadEPG(from: url)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case .failure(let error) = completion {
                    let msg = "EPG加载失败: \((error as? AppError)?.errorDescription ?? error.localizedDescription)"
                    Logger.parser.error("\(msg)")
                    self?.errorMessage.send(msg)
                }
                if finishLoading { self?.isLoading.send(false) }
            } receiveValue: { [weak self] in
                Logger.parser.info("EPG加载成功")
                self?.loadChannels()
                if finishLoading { self?.isLoading.send(false) }
            }
            .store(in: &cancellables)
    }

    // MARK: - EPG Auto-Discovery

    /// When the m3u header doesn't contain `url-tvg`, derive candidate EPG URLs
    /// from the playlist URL by guessing common paths on the same server.
    private func autoDiscoverEPG(fromPlaylistURL playlistURL: URL) {
        let candidates = deriveEPGCandidates(from: playlistURL)
        guard !candidates.isEmpty else {
            errorMessage.send("未找到EPG源，请在添加播放源时手动填写EPG地址")
            isLoading.send(false)
            return
        }
        Logger.parser.info("自动推导EPG地址, 共\(candidates.count)个候选")
        tryLoadEPGCandidate(candidates)
    }

    private func tryLoadEPGCandidate(_ candidates: [URL]) {
        guard let url = candidates.first else {
            errorMessage.send("未找到EPG源，请在添加播放源时手动填写EPG地址")
            isLoading.send(false)
            return
        }
        EPGService.shared.loadEPGFast(from: url)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case .failure = completion {
                    // Try next candidate
                    self?.tryLoadEPGCandidate(Array(candidates.dropFirst()))
                } else {
                    self?.isLoading.send(false)
                }
            } receiveValue: { [weak self] in
                Logger.parser.info("EPG自动推导成功: \(url.absoluteString)")
                self?.loadChannels()
            }
            .store(in: &cancellables)
    }

    /// Generates candidate EPG XMLTV URLs derived from a playlist URL.
    ///
    /// Common Chinese IPTV patterns covered:
    /// - `http://s.com/iptv/playlist.m3u` → `http://s.com/iptv/epg.xml` etc.
    /// - `http://s.com:8080/get.php?type=m3u` → `http://s.com:8080/get.php?type=xml`
    /// - `http://s.com/m3u.php?id=x` → `http://s.com/epg.php?id=x`
    /// - `http://s.com/api/?action=m3u` → `http://s.com/api/?action=epg`
    private func deriveEPGCandidates(from playlistURL: URL) -> [URL] {
        guard var components = URLComponents(url: playlistURL, resolvingAgainstBaseURL: false),
              components.host != nil else { return [] }

        var candidates: [URL] = []

        // 1. Path-based: same directory, common EPG filenames
        let dirPath = (components.path as NSString).deletingLastPathComponent
        let commonNames = [
            "epg.xml", "xmltv.xml", "guide.xml", "e.xml", "epg.php",
            "xmltv.php", "xml2.php", "epg.txt", "channel.php"
        ]

        for name in commonNames {
            var comps = components
            let path = dirPath + "/" + name
            comps.path = path.hasPrefix("/") ? path : "/" + path
            if let url = comps.url { candidates.append(url) }
        }

        // 2. Extension / filename replacement
        let lastPath = components.path
        let replacements: [(String, String)] = [
            (".m3u", ".xml"), (".m3u8", ".xml"), (".txt", ".xml"), (".php", ".xml"),
            ("m3u.php", "epg.php"), ("m3u.php", "xmltv.php"), ("m3u.php", "xml2.php"),
            ("channel.php", "epg.php"), ("live.txt", "epg.xml"),
        ]

        for (old, new) in replacements {
            if lastPath.hasSuffix(old) {
                var comps = components
                let base = String(lastPath.dropLast(old.count))
                comps.path = base + new
                if let url = comps.url { candidates.append(url) }
            }
        }

        // 3. Query-param value replacement: type=m3u → type=xml / type=epg etc.
        if var queryItems = components.queryItems {
            let valueMappings: [(String, [String])] = [
                ("type", ["xml", "epg", "xmltv"]),
                ("action", ["epg", "xmltv", "xml"]),
                ("output", ["xml", "epg"]),
                ("format", ["xml", "xmltv"]),
            ]

            for (i, item) in queryItems.enumerated() {
                for (paramName, newValues) in valueMappings {
                    if item.name.lowercased() == paramName,
                       item.value?.lowercased() == "m3u" || item.value?.lowercased() == "m3u8"
                        || item.value?.lowercased() == "m3u_plus" {
                        for newValue in newValues {
                            var comps = components
                            var items = queryItems
                            items[i].value = newValue
                            comps.queryItems = items
                            if let url = comps.url { candidates.append(url) }
                        }
                    }
                }
            }
        }

        // 4. Subdomain: try epg.<host>
        if let host = components.host, !host.hasPrefix("epg.") {
            var comps = components
            comps.host = "epg." + host
            comps.path = "/e.xml"
            if let url = comps.url { candidates.append(url) }
            comps.path = "/epg.xml"
            if let url = comps.url { candidates.append(url) }
        }

        return candidates
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

    func refreshStreamHealth(channelIds: [String]? = nil) {
        let channels: [Channel]
        if let ids = channelIds {
            channels = allChannels.filter { ids.contains($0.id) }
        } else {
            channels = allChannels
        }
        guard !channels.isEmpty else { return }

        let token = healthRefreshToken + 1
        healthRefreshToken = token

        let group = DispatchGroup()
        var results: [String: StreamHealth] = [:]
        let resultsLock = NSLock()

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

    func startHealthCheck(for channelId: String) {
        // Skip if checked within last 60 seconds
        if let existing = streamHealth[channelId],
           Date().timeIntervalSince(existing.checkedAt) < 60 {
            return
        }
        guard let channel = allChannels.first(where: { $0.id == channelId }),
              let url = URL(string: channel.url) else { return }

        StreamHealthService.shared.checkHealth(channelId: channelId, url: url) { [weak self] health in
            DispatchQueue.main.async {
                self?.streamHealth[channelId] = health
            }
        }
    }

    func cancelHealthCheck(for channelId: String) {
        StreamHealthService.shared.cancelHealthCheck(for: channelId)
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
