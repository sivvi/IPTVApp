import Foundation
import GRDB

final class DatabaseManager {
    static let shared = DatabaseManager()

    private var dbQueue: DatabaseQueue?

    private init() {}

    // MARK: - Initialization

    func initialize() throws {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dbPath = documents.appendingPathComponent("iptvapp.sqlite").path
        dbQueue = try DatabaseQueue(path: dbPath)
        try migrator.migrate(dbQueue!)
        Logger.database.info("数据库初始化完成: \(dbPath)")
    }

    func isInitialized() -> Bool {
        dbQueue != nil
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "channel") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("url", .text).notNull()
                t.column("logoUrl", .text)
                t.column("group", .text)
                t.column("epgId", .text)
                t.column("playlistId", .text)
                t.column("isFavorite", .boolean).notNull().defaults(to: false)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "program") { t in
                t.column("id", .text).primaryKey()
                t.column("channelId", .text).notNull().indexed()
                t.column("title", .text).notNull()
                t.column("description", .text)
                t.column("startTime", .datetime).notNull().indexed()
                t.column("endTime", .datetime).notNull()
                t.column("category", .text)
            }
            try db.create(table: "playlist") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("sourceUrl", .text).notNull()
                t.column("lastUpdated", .datetime).notNull()
                t.column("isDefault", .boolean).notNull().defaults(to: false)
            }
        }
        return migrator
    }

    // MARK: - Channel CRUD

    func insertChannels(_ channels: [Channel]) throws {
        guard let dbQueue else { throw AppError.databaseError("数据库未初始化") }
        try dbQueue.write { db in
            for channel in channels {
                try channel.upsert(db)
            }
        }
        Logger.database.info("写入\(channels.count)个频道")
    }

    func fetchAllChannels() throws -> [Channel] {
        guard let dbQueue else { throw AppError.databaseError("数据库未初始化") }
        return try dbQueue.read { db in
            try Channel.order(Channel.Columns.sortOrder, Channel.Columns.name).fetchAll(db)
        }
    }

    func fetchChannels(byGroup group: String) throws -> [Channel] {
        guard let dbQueue else { throw AppError.databaseError("数据库未初始化") }
        return try dbQueue.read { db in
            try Channel
                .filter(Channel.Columns.group == group)
                .order(Channel.Columns.sortOrder, Channel.Columns.name)
                .fetchAll(db)
        }
    }

    func fetchChannels(byPlaylistId playlistId: String) throws -> [Channel] {
        guard let dbQueue else { throw AppError.databaseError("数据库未初始化") }
        return try dbQueue.read { db in
            try Channel
                .filter(Channel.Columns.playlistId == playlistId)
                .order(Channel.Columns.sortOrder, Channel.Columns.name)
                .fetchAll(db)
        }
    }

    func fetchFavoriteChannels() throws -> [Channel] {
        guard let dbQueue else { throw AppError.databaseError("数据库未初始化") }
        return try dbQueue.read { db in
            try Channel
                .filter(Channel.Columns.isFavorite == true)
                .order(Channel.Columns.sortOrder, Channel.Columns.name)
                .fetchAll(db)
        }
    }

    func searchChannels(query: String) throws -> [Channel] {
        guard let dbQueue else { throw AppError.databaseError("数据库未初始化") }
        return try dbQueue.read { db in
            try Channel
                .filter(Channel.Columns.name.like("%\(query)%") || Channel.Columns.group.like("%\(query)%"))
                .order(Channel.Columns.sortOrder, Channel.Columns.name)
                .fetchAll(db)
        }
    }

    func fetchCurrentPrograms(for channelIds: [String]) throws -> [String: Program] {
        guard let dbQueue else { throw AppError.databaseError("数据库未初始化") }
        let now = Date()
        return try dbQueue.read { db in
            let programs = try Program
                .filter(channelIds.contains(Program.Columns.channelId))
                .filter(Program.Columns.startTime <= now && Program.Columns.endTime >= now)
                .order(Program.Columns.startTime)
                .fetchAll(db)
            return Dictionary(grouping: programs, by: { $0.channelId })
                .compactMapValues { $0.first }
        }
    }

    func updateChannel(_ channel: Channel) throws {
        guard let dbQueue else { throw AppError.databaseError("数据库未初始化") }
        try dbQueue.write { db in
            try channel.upsert(db)
        }
    }

    func deleteChannel(id: String) throws {
        guard let dbQueue else { throw AppError.databaseError("数据库未初始化") }
        try dbQueue.write { db in
            try Channel.deleteOne(db, key: id)
        }
    }

    func toggleFavorite(channelId: String) throws {
        guard let dbQueue else { throw AppError.databaseError("数据库未初始化") }
        try dbQueue.write { db in
            if var channel = try Channel.fetchOne(db, key: channelId) {
                channel.isFavorite.toggle()
                try channel.upsert(db)
            }
        }
    }

    // MARK: - Program CRUD

    func insertPrograms(_ programs: [Program]) throws {
        guard let dbQueue else { throw AppError.databaseError("数据库未初始化") }
        try dbQueue.write { db in
            for program in programs {
                try program.upsert(db)
            }
        }
        Logger.database.info("写入\(programs.count)个节目")
    }

    func fetchPrograms(for channelId: String, from startDate: Date, to endDate: Date) throws -> [Program] {
        guard let dbQueue else { throw AppError.databaseError("数据库未初始化") }
        return try dbQueue.read { db in
            try Program
                .filter(Program.Columns.channelId == channelId)
                .filter(Program.Columns.startTime < endDate && Program.Columns.endTime > startDate)
                .order(Program.Columns.startTime)
                .fetchAll(db)
        }
    }

    func fetchCurrentProgram(for channelId: String) throws -> Program? {
        guard let dbQueue else { throw AppError.databaseError("数据库未初始化") }
        let now = Date()
        return try dbQueue.read { db in
            try Program
                .filter(Program.Columns.channelId == channelId)
                .filter(Program.Columns.startTime <= now && Program.Columns.endTime >= now)
                .order(Program.Columns.startTime)
                .fetchOne(db)
        }
    }

    func fetchNextProgram(for channelId: String) throws -> Program? {
        guard let dbQueue else { throw AppError.databaseError("数据库未初始化") }
        let now = Date()
        return try dbQueue.read { db in
            try Program
                .filter(Program.Columns.channelId == channelId)
                .filter(Program.Columns.startTime > now)
                .order(Program.Columns.startTime)
                .fetchOne(db)
        }
    }

    func deleteExpiredPrograms(before date: Date) throws -> Int {
        guard let dbQueue else { throw AppError.databaseError("数据库未初始化") }
        return try dbQueue.write { db in
            try Program
                .filter(Program.Columns.endTime < date)
                .deleteAll(db)
        }
    }

    // MARK: - Playlist CRUD

    func insertPlaylist(_ playlist: Playlist) throws {
        guard let dbQueue else { throw AppError.databaseError("数据库未初始化") }
        try dbQueue.write { db in
            try playlist.insert(db)
        }
    }

    func fetchAllPlaylists() throws -> [Playlist] {
        guard let dbQueue else { throw AppError.databaseError("数据库未初始化") }
        return try dbQueue.read { db in
            try Playlist.order(Playlist.Columns.lastUpdated.desc).fetchAll(db)
        }
    }

    func fetchDefaultPlaylist() throws -> Playlist? {
        guard let dbQueue else { throw AppError.databaseError("数据库未初始化") }
        return try dbQueue.read { db in
            try Playlist.filter(Playlist.Columns.isDefault == true).fetchOne(db)
        }
    }

    func setDefaultPlaylist(id: String) throws {
        guard let dbQueue else { throw AppError.databaseError("数据库未初始化") }
        try dbQueue.write { db in
            // 取消所有默认
            try db.execute(sql: "UPDATE playlist SET isDefault = 0")
            // 设置当前为默认
            try db.execute(sql: "UPDATE playlist SET isDefault = 1 WHERE id = ?", arguments: [id])
        }
    }

    func databaseFileSize() throws -> Int64 {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dbPath = documents.appendingPathComponent("iptvapp.sqlite")
        let attrs = try FileManager.default.attributesOfItem(atPath: dbPath.path)
        return (attrs[.size] as? Int64) ?? 0
    }

    func deletePlaylist(id: String) throws {
        guard let dbQueue else { throw AppError.databaseError("数据库未初始化") }
        try dbQueue.write { db in
            try Playlist.deleteOne(db, key: id)
            // 级联删除相关频道
            try Channel.filter(Channel.Columns.playlistId == id).deleteAll(db)
        }
    }
}

// MARK: - Testing Support

#if DEBUG
extension DatabaseManager {
    func initializeForTesting() throws {
        dbQueue = try DatabaseQueue(path: ":memory:")
        try migrator.migrate(dbQueue!)
    }
}
#endif
