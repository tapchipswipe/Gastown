import Foundation
import Testing
import CSQLite
@testable import NewtonCore

struct StorageHardeningTests {
    @Test func paginationIncludesEveryEqualTimestampEventExactlyOnce() async throws {
        let store = try EventStore(path: ":memory:")
        let events = (0..<1001).map { HistoryEvent(id: String(format: "%05d", $0), timestamp: Date(timeIntervalSince1970: 100), source: "fixture", title: "orbit") }
        try await store.append(events)
        var cursor: HistoryCursor?; var ids: [String] = []
        repeat {
            let page = try await store.page("orbit", after: cursor, limit: 37)
            #expect(page.totalCount == 1001)
            ids += page.events.map(\.id); cursor = page.nextCursor
        } while cursor != nil
        #expect(ids.count == 1001); #expect(Set(ids).count == 1001)
        #expect(ids == events.map(\.id).sorted(by: >))
        try await store.verifyIntegrity()
    }
    @Test func changedQueryCannotReusePaginationCursor() async throws {
        let store = try EventStore(path: ":memory:")
        try await store.append((0..<4).map { HistoryEvent(source: "fixture", title: "orbit \($0)") })
        let first = try await store.page("orbit", limit: 1)
        let cursor = try #require(first.nextCursor)
        await #expect(throws: (any Error).self) { try await store.page("different", after: cursor, limit: 1) }
    }
    @Test func cancelledTransactionDoesNotAddAnyEvents() async throws {
        let store = try EventStore(path: ":memory:")
        let task = Task { try await store.append([HistoryEvent(source: "fixture", title: "cancelled")]) }
        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(try await store.count() == 0)
    }
    @Test func invalidStringsRollBackAndDatabaseRemainsUsable() async throws {
        let store = try EventStore(path: ":memory:")
        for invalid in [HistoryEvent(id: "", source: "fixture", title: "bad"),
                        HistoryEvent(source: "fixture", title: String(repeating: "A", count: 17_000)),
                        HistoryEvent(source: "fixture", title: "bad", detail: String(repeating: "A", count: 70_000))] {
            await #expect(throws: (any Error).self) { try await store.append([HistoryEvent(source: "fixture", title: "must roll back"), invalid]) }
        }
        #expect(try await store.count() == 0)
        try await store.append([HistoryEvent(source: "fixture", title: "still usable")])
        try await store.verifyIntegrity()
    }
    @Test func importerRejectsNonregularAndSymlinkFilesAndOversizedData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: (any Error).self) { try LumenImport.read(root) }
        let file = root.appendingPathComponent("fixture.jsonl"); try Data().write(to: file)
        let link = root.appendingPathComponent("link.jsonl")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(throws: (any Error).self) { try LumenImport.read(link) }
        #expect(throws: (any Error).self) { try LumenImport.parse(Data(repeating: 65, count: LumenImport.maximumBytes + 1)) }
    }
    @Test func importerRejectsMismatchedPayloadAndOversizedLines() throws {
        let mismatch = #"{"ts":"2026-10-24T12:00:00Z","kind":"appFocus","payload":{"type":"receipt","appFocus":{"appName":"wrong"}}}"#
        let batch = try LumenImport.parse(Data((mismatch + "\n" + String(repeating: "A", count: 1024*1024+1)).utf8))
        #expect(batch.events.isEmpty); #expect(batch.skipped == 2)
    }
}
