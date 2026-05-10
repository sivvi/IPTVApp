import XCTest
@testable import IPTVApp

final class DatabaseManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        try? DatabaseManager.shared.initializeForTesting()
    }

    // MARK: - Channel Tests

    func testInsertAndFetchChannel() throws {
        let channel = Channel(
            id: "test1",
            name: "测试频道",
            url: "http://stream.com/test.m3u8",
            group: "测试组"
        )

        try DatabaseManager.shared.insertChannels([channel])
        let channels = try DatabaseManager.shared.fetchAllChannels()

        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0].name, "测试频道")
        XCTAssertEqual(channels[0].group, "测试组")
    }

    func testBatchInsertChannels() throws {
        let channels = (0..<50).map { i in
            Channel(
                id: "ch\(i)",
                name: "频道\(i)",
                url: "http://stream.com/ch\(i).m3u8"
            )
        }

        try DatabaseManager.shared.insertChannels(channels)
        let fetched = try DatabaseManager.shared.fetchAllChannels()

        XCTAssertEqual(fetched.count, 50)
    }

    func testSearchChannels() throws {
        let channels = [
            Channel(id: "1", name: "CCTV-1", url: "http://s.com/1.m3u8", group: "央视"),
            Channel(id: "2", name: "湖南卫视", url: "http://s.com/2.m3u8", group: "卫视"),
            Channel(id: "3", name: "CCTV-2", url: "http://s.com/3.m3u8", group: "央视"),
        ]
        try DatabaseManager.shared.insertChannels(channels)

        let results = try DatabaseManager.shared.searchChannels(query: "CCTV")
        XCTAssertEqual(results.count, 2)
    }

    func testToggleFavorite() throws {
        let channel = Channel(id: "fav1", name: "收藏频道", url: "http://stream.com/fav.m3u8")
        try DatabaseManager.shared.insertChannels([channel])

        try DatabaseManager.shared.toggleFavorite(channelId: "fav1")
        let favorites = try DatabaseManager.shared.fetchFavoriteChannels()
        XCTAssertEqual(favorites.count, 1)
        XCTAssertTrue(favorites[0].isFavorite)

        try DatabaseManager.shared.toggleFavorite(channelId: "fav1")
        let after = try DatabaseManager.shared.fetchFavoriteChannels()
        XCTAssertTrue(after.isEmpty)
    }

    func testFetchByGroup() throws {
        let channels = [
            Channel(id: "g1", name: "频道1", url: "http://s.com/1.m3u8", group: "央视"),
            Channel(id: "g2", name: "频道2", url: "http://s.com/2.m3u8", group: "卫视"),
            Channel(id: "g3", name: "频道3", url: "http://s.com/3.m3u8", group: "央视"),
        ]
        try DatabaseManager.shared.insertChannels(channels)

        let cctv = try DatabaseManager.shared.fetchChannels(byGroup: "央视")
        XCTAssertEqual(cctv.count, 2)
    }

    func testFetchByPlaylistId() throws {
        let channels = [
            Channel(id: "p1", name: "列表1频道", url: "http://s.com/1.m3u8", playlistId: "playlist1"),
            Channel(id: "p2", name: "列表2频道", url: "http://s.com/2.m3u8", playlistId: "playlist2"),
            Channel(id: "p3", name: "列表1频道2", url: "http://s.com/3.m3u8", playlistId: "playlist1"),
        ]
        try DatabaseManager.shared.insertChannels(channels)

        let result = try DatabaseManager.shared.fetchChannels(byPlaylistId: "playlist1")
        XCTAssertEqual(result.count, 2)
    }

    func testDeleteChannel() throws {
        let channel = Channel(id: "del1", name: "待删除", url: "http://s.com/del.m3u8")
        try DatabaseManager.shared.insertChannels([channel])

        try DatabaseManager.shared.deleteChannel(id: "del1")
        let all = try DatabaseManager.shared.fetchAllChannels()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - Program Tests

    func testInsertAndFetchProgram() throws {
        let now = Date()
        let program = Program(
            id: "prog1",
            channelId: "cctv1",
            title: "新闻联播",
            description: "今日要闻",
            startTime: now,
            endTime: now.addingTimeInterval(1800),
            category: "新闻"
        )

        try DatabaseManager.shared.insertPrograms([program])
        let programs = try DatabaseManager.shared.fetchPrograms(for: "cctv1", from: now.addingTimeInterval(-3600), to: now.addingTimeInterval(3600))

        XCTAssertEqual(programs.count, 1)
        XCTAssertEqual(programs[0].title, "新闻联播")
        XCTAssertEqual(programs[0].category, "新闻")
    }

    func testFetchCurrentProgram() throws {
        let now = Date()
        let current = Program(
            id: "cur1",
            channelId: "cctv1",
            title: "当前节目",
            startTime: now.addingTimeInterval(-300),
            endTime: now.addingTimeInterval(600)
        )

        try DatabaseManager.shared.insertPrograms([current])
        let fetched = try DatabaseManager.shared.fetchCurrentProgram(for: "cctv1")

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.title, "当前节目")
    }

    func testDeleteExpiredPrograms() throws {
        let now = Date()
        let programs: [Program] = [
            Program(id: "e1", channelId: "ch1", title: "过期1", startTime: now.addingTimeInterval(-7200), endTime: now.addingTimeInterval(-3600)),
            Program(id: "e2", channelId: "ch1", title: "过期2", startTime: now.addingTimeInterval(-5400), endTime: now.addingTimeInterval(-1800)),
            Program(id: "f1", channelId: "ch1", title: "未来1", startTime: now.addingTimeInterval(1800), endTime: now.addingTimeInterval(3600)),
            Program(id: "f2", channelId: "ch1", title: "未来2", startTime: now.addingTimeInterval(3600), endTime: now.addingTimeInterval(5400)),
        ]
        try DatabaseManager.shared.insertPrograms(programs)

        let deleted = try DatabaseManager.shared.deleteExpiredPrograms(before: now)
        XCTAssertEqual(deleted, 2)

        let remaining = try DatabaseManager.shared.fetchPrograms(for: "ch1", from: now.addingTimeInterval(-10000), to: now.addingTimeInterval(10000))
        XCTAssertEqual(remaining.count, 2)
    }

    // MARK: - Playlist Tests

    func testInsertAndFetchPlaylist() throws {
        let playlist = Playlist(id: "pl1", name: "我的列表", sourceUrl: "http://source.com/list.m3u")

        try DatabaseManager.shared.insertPlaylist(playlist)
        let playlists = try DatabaseManager.shared.fetchAllPlaylists()

        XCTAssertEqual(playlists.count, 1)
        XCTAssertEqual(playlists[0].name, "我的列表")
    }

    func testSetDefaultPlaylist() throws {
        let p1 = Playlist(id: "pl_a", name: "列表A", sourceUrl: "http://s.com/a.m3u")
        let p2 = Playlist(id: "pl_b", name: "列表B", sourceUrl: "http://s.com/b.m3u")

        try DatabaseManager.shared.insertPlaylist(p1)
        try DatabaseManager.shared.insertPlaylist(p2)

        try DatabaseManager.shared.setDefaultPlaylist(id: "pl_a")
        let default_ = try DatabaseManager.shared.fetchDefaultPlaylist()
        XCTAssertNotNil(default_)
        XCTAssertEqual(default_?.id, "pl_a")
    }

    func testDeletePlaylistCascadesChannels() throws {
        let playlist = Playlist(id: "pl_cascade", name: "级联删除", sourceUrl: "http://s.com/cascade.m3u")
        try DatabaseManager.shared.insertPlaylist(playlist)

        let channel = Channel(id: "ch_cascade", name: "级联频道", url: "http://s.com/c.m3u8", playlistId: "pl_cascade")
        try DatabaseManager.shared.insertChannels([channel])

        try DatabaseManager.shared.deletePlaylist(id: "pl_cascade")

        let playlists = try DatabaseManager.shared.fetchAllPlaylists()
        XCTAssertTrue(playlists.isEmpty)

        let channels = try DatabaseManager.shared.fetchChannels(byPlaylistId: "pl_cascade")
        XCTAssertTrue(channels.isEmpty)
    }

    func testUpdateChannel() throws {
        var channel = Channel(id: "up1", name: "原始名", url: "http://s.com/old.m3u8")
        try DatabaseManager.shared.insertChannels([channel])

        channel.name = "新名字"
        try DatabaseManager.shared.updateChannel(channel)

        let fetched = try DatabaseManager.shared.fetchAllChannels()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].name, "新名字")
    }
}
