import Foundation
import Testing
import CSQLite
@testable import NewtonCore

struct AuditRegressionTests {
    @Test func embeddedNULTextRoundTripsWithoutIDCollision() async throws {
        let store = try EventStore(path: ":memory:")
        let a = HistoryEvent(id: "same\0one", timestamp: Date(timeIntervalSince1970: 100), source: "A\0B", title: "before\0after", detail: "detail\0tail")
        let b = HistoryEvent(id: "same\0two", timestamp: Date(timeIntervalSince1970: 101), source: "test", title: "second")
        let inserted = try await store.append([a, b])
        let rows = try await store.search()
        #expect(inserted == 2)
        #expect(rows.contains(a))
        #expect(rows.contains(b))
    }
    @Test func invalidEventRollsBackWholeBatchInsteadOfBeingSilentlyIgnored() async throws {
        let store = try EventStore(path: ":memory:")
        let valid = HistoryEvent(id: "valid", source: "test", title: "Valid")
        let invalid = HistoryEvent(id: "bad", timestamp: Date(timeIntervalSince1970: .nan), source: "test", title: "Invalid")
        await #expect(throws: (any Error).self) { try await store.append([valid, invalid]) }
        let count = try await store.count()
        #expect(count == 0)
    }
    @Test func futureSchemaIsRejectedWithoutDowngradingIt() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        guard let db else { return }
        defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "PRAGMA user_version=99", nil, nil, nil) == SQLITE_OK)
        #expect(throws: (any Error).self) { try EventStore(path: url.path) }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        #expect(sqlite3_column_int(statement, 0) == 99)
    }
    @Test func screenpipeDuplicateRowsDoNotProduceDuplicateListIDs() throws {
        let row = #"{"type":"OCR","content":{"frame_id":42,"timestamp":"2026-10-24T12:00:00Z","text":"evidence"}}"#
        let result = try ScreenpipeClient.decode(Data(("{\"data\":[" + row + "," + row + "]}").utf8))
        #expect(result.count == 1)
    }
    @Test func screenpipeRejectsObjectAsRecordIdentity() throws {
        let json = #"{"data":[{"type":"OCR","content":{"frame_id":{"invalid":42},"timestamp":"2026-10-24T12:00:00Z"}}]}"#
        #expect(try ScreenpipeClient.decode(Data(json.utf8)).isEmpty)
    }
}
