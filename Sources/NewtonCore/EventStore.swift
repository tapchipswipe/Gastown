import Foundation
import CSQLite
import Darwin

public struct StoreError: Error, LocalizedError, Sendable {
    public let message: String
    public let sqliteCode: Int32?
    public init(message: String, sqliteCode: Int32? = nil) { self.message = message; self.sqliteCode = sqliteCode }
    public var errorDescription: String? { message }
}

public struct HistoryCursor: Sendable, Equatable {
    let timestamp: Double
    let id: String
    let query: String
}

public struct HistoryPage: Sendable {
    public let events: [HistoryEvent]
    public let nextCursor: HistoryCursor?
    public let totalCount: Int
}

// The handle remains inside its owning actor. C callbacks borrow state only during synchronous SQL execution.
final class Database {
    let handle: OpaquePointer
    init(path: String) throws {
        var pointer: OpaquePointer?
        guard sqlite3_open_v2(path, &pointer, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let pointer else {
            let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open database"
            if let pointer { sqlite3_close(pointer) }
            throw StoreError(message: message)
        }
        handle = pointer
        sqlite3_busy_timeout(handle, 100)
    }
    deinit { sqlite3_close(handle) }
    /// SQLite's online backup includes committed WAL pages, unlike copying the main file.
    func backup(to path: String) throws {
        var output: OpaquePointer?
        let destination = URL(fileURLWithPath: path)
        guard let resolved = realpath(destination.deletingLastPathComponent().path, nil) else { throw StoreError(message: "Cannot resolve backup directory") }
        defer { free(resolved) }
        let canonicalPath = String(cString: resolved) + "/" + destination.lastPathComponent
        guard sqlite3_open_v2(canonicalPath, &output, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOFOLLOW, nil) == SQLITE_OK,
              let output else {
            let detail = output.map { String(cString: sqlite3_errmsg($0)) } ?? "no SQLite handle"
            if let output { sqlite3_close(output) }
            throw StoreError(message: "Cannot create pre-migration backup at \(canonicalPath): " + detail)
        }
        defer { sqlite3_close(output) }
        guard let backup = sqlite3_backup_init(output, "main", handle, "main") else { throw StoreError(message: "Cannot initialize pre-migration backup") }
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        var result: Int32
        repeat {
            result = sqlite3_backup_step(backup, 256)
            if result == SQLITE_BUSY || result == SQLITE_LOCKED { Thread.sleep(forTimeInterval: 0.01) }
        } while (result == SQLITE_OK || result == SQLITE_BUSY || result == SQLITE_LOCKED) && ProcessInfo.processInfo.systemUptime < deadline
        let finished = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finished == SQLITE_OK else { throw StoreError(message: "Pre-migration backup failed; migration refused") }
        // A portable backup must not depend on a future -wal/-shm sidecar.
        guard sqlite3_exec(output, "PRAGMA journal_mode=DELETE", nil, nil, nil) == SQLITE_OK else { throw StoreError(message: "Cannot finalize standalone migration backup") }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }
    func execute(_ sql: String, retryBusy: Bool = false) throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while true {
            let result = sqlite3_exec(handle, sql, nil, nil, nil)
            if result == SQLITE_OK { return }
            let primary = result & 0xff
            guard retryBusy, primary == SQLITE_BUSY || primary == SQLITE_LOCKED,
                  ProcessInfo.processInfo.systemUptime < deadline else { throw error("Executing \(sql.prefix(72))") }
            // SQLite cannot always invoke its busy handler when changing journal mode.
            // Release the failed statement and retry only initialization, off the UI actor.
            Thread.sleep(forTimeInterval: 0.01)
        }
    }
    func error(_ operation: String = "SQLite operation") -> any Error {
        if sqlite3_errcode(handle) == SQLITE_INTERRUPT, Task<Never, Never>.isCancelled { return CancellationError() }
        return StoreError(message: "\(operation): \(String(cString: sqlite3_errmsg(handle)))", sqliteCode: sqlite3_errcode(handle))
    }
    func statement(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            if let statement { sqlite3_finalize(statement) }
            throw error("Preparing \(sql.prefix(72))")
        }
        return statement
    }
    func scalar(_ sql: String, retryBusy: Bool = false) throws -> Int {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while true {
            do { return try scalarOnce(sql) }
            catch let error as StoreError {
                guard retryBusy, let code = error.sqliteCode,
                      code & 0xff == SQLITE_BUSY || code & 0xff == SQLITE_LOCKED,
                      ProcessInfo.processInfo.systemUptime < deadline else { throw error }
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
    }
    private func scalarOnce(_ sql: String) throws -> Int {
        let statement = try statement(sql)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else {
            if result == SQLITE_DONE { throw StoreError(message: "A required history metadata row is missing.") }
            throw error("Reading \(sql.prefix(72))")
        }
        return Int(sqlite3_column_int64(statement, 0))
    }
    func validateSchema() throws {
        _ = try scalar("SELECT event_count FROM history_stats WHERE singleton=1")
        guard try scalar("SELECT count(*) FROM sqlite_master WHERE type='trigger' AND name IN ('events_insert','events_delete','count_insert','count_delete')") == 4 else {
            throw StoreError(message: "History schema is incomplete: required index/count triggers are missing.")
        }
        let check = try statement("SELECT e.id,e.timestamp,e.source,e.title,e.detail,f.title FROM events e LEFT JOIN events_fts f ON e.rowid=f.rowid LIMIT 0")
        sqlite3_finalize(check)
    }
    func bind(_ value: String, to statement: OpaquePointer, at index: Int32) throws {
        let result = value.withCString {
            sqlite3_bind_text(statement, index, $0, Int32(value.utf8.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard result == SQLITE_OK else { throw error() }
    }
    func string(_ statement: OpaquePointer, _ column: Int32) -> String {
        guard let bytes = sqlite3_column_text(statement, column) else { return "" }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(statement, column))), as: UTF8.self)
    }
}

private final class QueryBudget {
    let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
}

public actor EventStore {
    private let db: Database
    public init(path: String) throws {
        let database = try Database(path: path)
        let initialVersion = try database.scalar("PRAGMA user_version", retryBusy: true)
        guard (0...2).contains(initialVersion) else {
            throw StoreError(message: "History schema \(initialVersion) is unsupported by this Newton build. No migration was attempted.")
        }
        try database.execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON;", retryBusy: true)
        if initialVersion < 2 {
            if initialVersion > 0, path != ":memory:" {
                try database.backup(to: path + ".pre-migration-v\(initialVersion)-" + UUID().uuidString + ".sqlite")
            }
            try database.execute("BEGIN IMMEDIATE", retryBusy: true)
            do {
                // Another opener may have migrated while this connection waited for the write lock.
                let version = try database.scalar("PRAGMA user_version")
                guard (0...2).contains(version) else { throw StoreError(message: "History schema changed to an unsupported version.") }
                if version == 0 {
                    guard try database.scalar("SELECT count(*) FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'") == 0 else {
                        throw StoreError(message: "The selected database is not a recognized Newton history file.")
                    }
                    try database.execute("""
                    CREATE TABLE events(id TEXT PRIMARY KEY NOT NULL, timestamp REAL NOT NULL,
                        source TEXT NOT NULL, title TEXT NOT NULL, detail TEXT NOT NULL);
                    CREATE VIRTUAL TABLE events_fts USING fts5(title, detail, source, content='events', content_rowid='rowid');
                    CREATE TRIGGER events_insert AFTER INSERT ON events BEGIN
                        INSERT INTO events_fts(rowid,title,detail,source) VALUES(new.rowid,new.title,new.detail,new.source);
                    END;
                    CREATE TRIGGER events_delete AFTER DELETE ON events BEGIN
                        INSERT INTO events_fts(events_fts,rowid,title,detail,source) VALUES('delete',old.rowid,old.title,old.detail,old.source);
                    END;
                    """)
                }
                if version < 2 {
                    try database.execute("""
                    CREATE INDEX events_order ON events(timestamp DESC, id DESC);
                    DROP INDEX IF EXISTS events_time;
                    CREATE TABLE history_stats(singleton INTEGER PRIMARY KEY CHECK(singleton=1), event_count INTEGER NOT NULL);
                    INSERT INTO history_stats SELECT 1,count(*) FROM events;
                    CREATE TRIGGER count_insert AFTER INSERT ON events BEGIN
                        UPDATE history_stats SET event_count=event_count+1 WHERE singleton=1;
                    END;
                    CREATE TRIGGER count_delete AFTER DELETE ON events BEGIN
                        UPDATE history_stats SET event_count=event_count-1 WHERE singleton=1;
                    END;
                    PRAGMA user_version=2;
                    """)
                }
                try database.validateSchema()
                try database.execute("COMMIT")
            } catch { try? database.execute("ROLLBACK"); throw error }
        } else { try database.validateSchema() }
        sqlite3_busy_timeout(database.handle, 1500)
        db = database
    }

    @discardableResult public func append(_ events: [HistoryEvent]) throws -> Int {
        try Task.checkCancellation()
        guard events.count <= 100_000 else { throw StoreError(message: "A history transaction is limited to 100,000 events.") }
        guard !events.isEmpty else { return 0 }
        let statement = try db.statement("INSERT INTO events(id,timestamp,source,title,detail) VALUES(?,?,?,?,?) ON CONFLICT(id) DO NOTHING")
        defer { sqlite3_finalize(statement) }
        try db.execute("BEGIN IMMEDIATE")
        do {
            var inserted = 0
            for event in events {
                try Task.checkCancellation()
                try Self.validate(event)
                sqlite3_reset(statement); sqlite3_clear_bindings(statement)
                try db.bind(event.id, to: statement, at: 1)
                guard sqlite3_bind_double(statement, 2, event.timestamp.timeIntervalSince1970) == SQLITE_OK else { throw db.error() }
                try db.bind(event.source, to: statement, at: 3); try db.bind(event.title, to: statement, at: 4)
                try db.bind(event.detail, to: statement, at: 5)
                guard sqlite3_step(statement) == SQLITE_DONE else { throw db.error() }
                inserted += Int(sqlite3_changes(db.handle))
            }
            try Task.checkCancellation()
            try db.execute("COMMIT")
            return inserted
        } catch {
            try? db.execute("ROLLBACK")
            throw error
        }
    }

    static func validate(_ event: HistoryEvent) throws {
        let time = event.timestamp.timeIntervalSince1970
        guard time.isFinite, (-62_135_596_800...253_402_300_799).contains(time),
              !event.id.isEmpty, event.id.utf8.count <= 512, event.source.utf8.count <= 1024,
              event.title.utf8.count <= 16_384, event.detail.utf8.count <= 65_536 else {
            throw StoreError(message: "History record has an invalid timestamp, identity, or oversized text field.")
        }
    }

    public func search(_ query: String = "", limit: Int = 100) throws -> [HistoryEvent] {
        try page(query, limit: limit).events
    }

    public func page(_ query: String = "", after cursor: HistoryCursor? = nil, limit: Int = 100) throws -> HistoryPage {
        try Task.checkCancellation()
        guard query.utf8.count <= 4096, !query.contains("\0") else { throw StoreError(message: "Search is limited to 4 KB of text without NUL characters.") }
        guard cursor == nil || cursor?.query == query else { throw StoreError(message: "This history page belongs to a different search.") }
        let size = max(1, min(limit, 500))
        let tokens = query.split(whereSeparator: { $0.isWhitespace })
        guard tokens.count <= 32 else { throw StoreError(message: "Use at most 32 search terms.") }
        let match = tokens.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: " AND ")
        var conditions: [String] = []
        if !match.isEmpty { conditions.append("events_fts MATCH ?") }
        if cursor != nil { conditions.append("(e.timestamp < ? OR (e.timestamp = ? AND e.id < ?))") }
        let join = match.isEmpty ? "" : " JOIN events_fts f ON e.rowid=f.rowid"
        let filter = conditions.isEmpty ? "" : " WHERE " + conditions.joined(separator: " AND ")
        let statement = try db.statement("SELECT e.id,e.timestamp,e.source,e.title,e.detail FROM events e\(join)\(filter) ORDER BY e.timestamp DESC,e.id DESC LIMIT ?")
        defer { sqlite3_finalize(statement) }
        var index: Int32 = 1
        if !match.isEmpty { try db.bind(match, to: statement, at: index); index += 1 }
        if let cursor {
            sqlite3_bind_double(statement, index, cursor.timestamp); index += 1
            sqlite3_bind_double(statement, index, cursor.timestamp); index += 1
            try db.bind(cursor.id, to: statement, at: index); index += 1
        }
        sqlite3_bind_int(statement, index, Int32(size + 1))
        let budget = QueryBudget()
        sqlite3_progress_handler(db.handle, 1000, { context in
            guard let context else { return 1 }
            let budget = Unmanaged<QueryBudget>.fromOpaque(context).takeUnretainedValue()
            return Task<Never, Never>.isCancelled || DispatchTime.now().uptimeNanoseconds > budget.deadline ? 1 : 0
        }, Unmanaged.passUnretained(budget).toOpaque())
        defer { sqlite3_progress_handler(db.handle, 0, nil, nil); withExtendedLifetime(budget) {} }
        try db.execute("BEGIN DEFERRED")
        do {
            var events: [HistoryEvent] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { break }
                guard result == SQLITE_ROW else { throw db.error() }
                events.append(HistoryEvent(id: db.string(statement, 0), timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                    source: db.string(statement, 2), title: db.string(statement, 3), detail: db.string(statement, 4)))
            }
            let count = try db.scalar("SELECT event_count FROM history_stats WHERE singleton=1")
            let more = events.count > size
            if more { events.removeLast() }
            let next = more ? events.last.map { HistoryCursor(timestamp: $0.timestamp.timeIntervalSince1970, id: $0.id, query: query) } : nil
            try db.execute("COMMIT")
            return HistoryPage(events: events, nextCursor: next, totalCount: count)
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    /// Half-open intervals preserve local-calendar DST boundaries and deterministic ID ties.
    public func rangePage(from start: Date, to end: Date, query: String = "", after cursor: RangeHistoryCursor? = nil, limit: Int = 500) async throws -> RangeHistoryPage {
        try Task.checkCancellation()
        guard start < end, start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
              query.utf8.count <= 4096, !query.contains("\0") else { throw StoreError(message: "Invalid history range or search") }
        if let cursor, cursor.start != start || cursor.end != end || cursor.query != query {
            throw StoreError(message: "Range cursor belongs to another query")
        }
        let terms = query.split(whereSeparator: { $0.isWhitespace })
        guard terms.count <= 32 else { throw StoreError(message: "Use at most 32 search terms") }
        let match = terms.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: " AND ")
        let join = match.isEmpty ? "" : " JOIN events_fts f ON e.rowid=f.rowid"
        let text = match.isEmpty ? "" : " AND events_fts MATCH ?"
        let next = cursor == nil ? "" : " AND (e.timestamp > ? OR (e.timestamp = ? AND e.id > ?))"
        let size = max(1, min(limit, 500))
        let statement = try db.statement("SELECT e.id,e.timestamp,e.source,e.title,e.detail FROM events e\(join) WHERE e.timestamp >= ? AND e.timestamp < ?\(text)\(next) ORDER BY e.timestamp ASC,e.id ASC LIMIT ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, start.timeIntervalSince1970); sqlite3_bind_double(statement, 2, end.timeIntervalSince1970)
        var index: Int32 = 3
        if !match.isEmpty { try db.bind(match, to: statement, at: index); index += 1 }
        if let cursor {
            sqlite3_bind_double(statement, index, cursor.timestamp); index += 1
            sqlite3_bind_double(statement, index, cursor.timestamp); index += 1
            try db.bind(cursor.id, to: statement, at: index); index += 1
        }
        sqlite3_bind_int(statement, index, Int32(size + 1))
        let budget = QueryBudget()
        sqlite3_progress_handler(db.handle, 1000, { context in
            guard let context else { return 1 }
            return DispatchTime.now().uptimeNanoseconds > Unmanaged<QueryBudget>.fromOpaque(context).takeUnretainedValue().deadline ? 1 : 0
        }, Unmanaged.passUnretained(budget).toOpaque())
        defer { sqlite3_progress_handler(db.handle, 0, nil, nil); withExtendedLifetime(budget) {} }
        var events: [HistoryEvent] = []
        while true {
            try Task.checkCancellation()
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw db.error() }
            events.append(HistoryEvent(id: db.string(statement, 0), timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)), source: db.string(statement, 2), title: db.string(statement, 3), detail: db.string(statement, 4)))
        }
        let more = events.count > size
        if more { events.removeLast() }
        let last = events.last
        return RangeHistoryPage(events: events, nextCursor: more ? last.map { RangeHistoryCursor(start: start, end: end, query: query, timestamp: $0.timestamp.timeIntervalSince1970, id: $0.id) } : nil,
            coverage: ObservationCoverage(start: start, end: end, firstObserved: events.first?.timestamp, lastObserved: last?.timestamp, sources: Array(Set(events.map(\.source))).sorted()))
    }

    public func dayEvents(from start: Date, to end: Date, limit: Int = 50_000) throws -> DailyHistoryResult {
        try Task.checkCancellation()
        guard start < end else { throw StoreError(message: "Invalid daily history range") }
        let size = max(1, min(limit, 50_000))
        let statement = try db.statement("SELECT id,timestamp,source,title,detail FROM events WHERE timestamp >= ? AND timestamp < ? ORDER BY timestamp ASC,id ASC LIMIT ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, end.timeIntervalSince1970)
        sqlite3_bind_int(statement, 3, Int32(size + 1))
        var results: [HistoryEvent] = []
        while true {
            try Task.checkCancellation()
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw db.error() }
            results.append(HistoryEvent(id: db.string(statement, 0), timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                source: db.string(statement, 2), title: db.string(statement, 3), detail: db.string(statement, 4)))
        }
        let complete = results.count <= size
        if !complete { results.removeLast() }
        return DailyHistoryResult(events: results, isComplete: complete)
    }

    public func count() throws -> Int { try db.scalar("SELECT event_count FROM history_stats WHERE singleton=1") }
    public func deleteAll() throws {
        try Task.checkCancellation()
        try db.execute("DELETE FROM events")
    }
    public func verifyIntegrity() throws {
        try Task.checkCancellation()
        // FTS validation is a write command: acquire its lock before opening a read
        // cursor, rather than upgrading a live quick_check read amid other writers.
        try db.execute("BEGIN IMMEDIATE")
        do {
            do {
                let statement = try db.statement("PRAGMA quick_check")
                defer { sqlite3_finalize(statement) }
                guard sqlite3_step(statement) == SQLITE_ROW, db.string(statement, 0) == "ok" else {
                    throw StoreError(message: "SQLite history integrity check failed.")
                }
            }
            try db.execute("INSERT INTO events_fts(events_fts,rank) VALUES('integrity-check',1)")
            guard try db.scalar("SELECT count(*) FROM events") == count() else {
                throw StoreError(message: "History count metadata does not match stored events.")
            }
            try db.execute("COMMIT")
        } catch { try? db.execute("ROLLBACK"); throw error }
    }
}
