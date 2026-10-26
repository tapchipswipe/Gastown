import Testing
import Foundation
@testable import NewtonCore

struct EventStoreTests {
    @Test func testDuplicateImportsDoNotMultiplyHistoryOrSearchResults() async throws {
        let store = try EventStore(path: ":memory:")
        let event = HistoryEvent(id: "stable", source: "Activity", title: "Newton planning", detail: "Design a local timeline")
        let first = try await store.append([event]); let second = try await store.append([event])
        let count = try await store.count(); let results = try await store.search("planning")
        #expect(first == 1); #expect(second == 0); #expect(count == 1)
        #expect(results.map(\.id) == ["stable"])
    }

    @Test func testConcurrentWritersKeepAllEvents() async throws {
        let store = try EventStore(path: ":memory:")
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    try await store.append([HistoryEvent(id: "\(index)", source: "test", title: "Event \(index)")])
                }
            }
            try await group.waitForAll()
        }
        let count = try await store.count()
        #expect(count == 100)
    }

    @Test func testReopenPreservesSearchAndDeleteUpdatesIndex() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("test.sqlite").path
        let first = try EventStore(path: path)
        try await first.append([HistoryEvent(id: "persisted", source: "test", title: "Jupiter orbit")])
        let reopened = try EventStore(path: path)
        let rows = try await reopened.search("Jupiter")
        #expect(rows.count == 1)
        try await reopened.deleteAll()
        let deleted = try await reopened.search("Jupiter"); let count = try await reopened.count()
        #expect(deleted.isEmpty); #expect(count == 0)
    }

    @Test func testSearchTreatsOperatorsAsTextAndBoundsResults() async throws {
        let store = try EventStore(path: ":memory:")
        try await store.append((0..<12).map { HistoryEvent(source: "test", title: "alpha \($0)") })
        let limited = try await store.search("alpha", limit: 3)
        #expect(limited.count == 3)
        // Malformed FTS syntax and SQL-looking strings remain data, never operators.
        for input in ["\"", "OR", "alpha OR missing", "'; DROP TABLE events; --", "("] {
            _ = try await store.search(input)
        }
        let count = try await store.count(); #expect(count == 12)
    }

    @Test func testRecentEventsHaveDeterministicTimestampOrder() async throws {
        let store = try EventStore(path: ":memory:")
        let old = HistoryEvent(id: "old", timestamp: Date(timeIntervalSince1970: 10), source: "test", title: "Old")
        let new = HistoryEvent(id: "new", timestamp: Date(timeIntervalSince1970: 20), source: "test", title: "New")
        try await store.append([new, old])
        let rows = try await store.search()
        #expect(rows.map(\.id) == ["new", "old"])
    }
}
