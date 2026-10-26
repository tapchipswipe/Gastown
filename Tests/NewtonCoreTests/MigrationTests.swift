import Foundation
import Testing
import CSQLite
@testable import NewtonCore

struct MigrationTests {
    private func withFixture(_ action: (URL, OpaquePointer) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("fixture.sqlite")
        var handle: OpaquePointer?
        try #require(sqlite3_open(url.path, &handle) == SQLITE_OK)
        let db = try #require(handle)
        defer { sqlite3_close(db) }
        try await action(url, db)
    }
    @Test func versionOneHistoryMigratesWithoutLosingEventsOrSearch() async throws {
        try await withFixture { url, db in
            let schema = """
            CREATE TABLE events(id TEXT PRIMARY KEY,timestamp REAL NOT NULL,source TEXT NOT NULL,title TEXT NOT NULL,detail TEXT NOT NULL);
            CREATE INDEX events_time ON events(timestamp DESC);
            CREATE VIRTUAL TABLE events_fts USING fts5(title,detail,source,content='events',content_rowid='rowid');
            CREATE TRIGGER events_insert AFTER INSERT ON events BEGIN
                INSERT INTO events_fts(rowid,title,detail,source) VALUES(new.rowid,new.title,new.detail,new.source);
            END;
            CREATE TRIGGER events_delete AFTER DELETE ON events BEGIN
                INSERT INTO events_fts(events_fts,rowid,title,detail,source) VALUES('delete',old.rowid,old.title,old.detail,old.source);
            END;
            INSERT INTO events VALUES('original',100,'Lumen','original searchable history','keep this');
            PRAGMA user_version=1;
            """
            try #require(sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK)
            let store = try EventStore(path: url.path)
            let backups = try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil).filter { $0.lastPathComponent.contains("pre-migration-v1-") && $0.pathExtension == "sqlite" }
            try #require(backups.count == 1)
            var backup: OpaquePointer?
            try #require(sqlite3_open_v2(backups[0].path, &backup, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
            defer { sqlite3_close(backup) }
            var statement: OpaquePointer?
            let prepared = sqlite3_prepare_v2(backup, "SELECT count(*) FROM events WHERE id='original'", -1, &statement, nil)
            try #require(prepared == SQLITE_OK, "Backup query failed: \(String(cString: sqlite3_errmsg(backup)))")
            defer { sqlite3_finalize(statement) }
            let result = sqlite3_step(statement)
            #expect(result == SQLITE_ROW, "Backup read failed: \(String(cString: sqlite3_errmsg(backup)))")
            #expect(sqlite3_column_int(statement, 0) == 1)
            #expect(try await store.count() == 1)
            #expect(try await store.search("searchable").first?.id == "original")
            try await store.append([HistoryEvent(id: "new", source: "fixture", title: "new searchable history")])
            #expect(try await store.count() == 2)
            try await store.verifyIntegrity()
            try await store.deleteAll(); #expect(try await store.count() == 0)
        }
    }
    @Test func schemaMigrationFailureRollsBackVersionAndNewTables() async throws {
        try await withFixture { url, db in
            try #require(sqlite3_exec(db, "CREATE TABLE events(id TEXT); PRAGMA user_version=1", nil, nil, nil) == SQLITE_OK)
            #expect(throws: (any Error).self) { try EventStore(path: url.path) }
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil)
            defer { sqlite3_finalize(statement) }
            #expect(sqlite3_step(statement) == SQLITE_ROW)
            #expect(sqlite3_column_int(statement, 0) == 1)
            var check: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT count(*) FROM sqlite_master WHERE name='history_stats'", -1, &check, nil)
            defer { sqlite3_finalize(check) }
            #expect(sqlite3_step(check) == SQLITE_ROW); #expect(sqlite3_column_int(check, 0) == 0)
        }
    }
    @Test func failedSQLInsertRollsBackFTSAndCountAsWellAsRows() async throws {
        try await withFixture { url, db in
            let store = try EventStore(path: url.path)
            try #require(sqlite3_exec(db, "CREATE TRIGGER fixture_failure BEFORE INSERT ON events WHEN new.id='blocked' BEGIN SELECT RAISE(ABORT,'fixture full'); END", nil, nil, nil) == SQLITE_OK)
            await #expect(throws: (any Error).self) {
                try await store.append([HistoryEvent(id: "allowed", source: "fixture", title: "atomic"), HistoryEvent(id: "blocked", source: "fixture", title: "atomic")])
            }
            #expect(try await store.count() == 0)
            #expect(try await store.search("atomic").isEmpty)
            try await store.verifyIntegrity()
        }
    }
}
