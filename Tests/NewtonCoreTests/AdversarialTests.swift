import Foundation
import Testing
@testable import NewtonCore

struct AdversarialTests {
    @Test func deterministicPunctuationAndUnicodeSearchInputsCannotChangeData() async throws {
        let store = try EventStore(path: ":memory:")
        try await store.append([HistoryEvent(id: "retained", timestamp: Date(timeIntervalSince1970: 100), source: "fixture", title: "Café 日本語 launch", detail: "before\0after")])
        let alphabet = Array("ab\"'(){}:;*+-_ café日本語\n\t")
        var state: UInt64 = 0x12345678
        for _ in 0..<250 {
            let query = String((0..<12).map { _ in state = state &* 6364136223846793005 &+ 1; return alphabet[Int((state >> 32) % UInt64(alphabet.count))] })
            _ = try await store.search(query, limit: 10)
        }
        #expect(try await store.count() == 1)
        #expect(try await store.search("after").first?.id == "retained")
        try await store.verifyIntegrity()
    }
    @Test func concurrentFirstOpenersShareOneValidMigration() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for iteration in 0..<32 {
            let path = directory.appendingPathComponent("history-\(iteration).sqlite").path
            try await withThrowingTaskGroup(of: EventStore.self) { group in
                for _ in 0..<8 { group.addTask { try EventStore(path: path) } }
                for try await store in group { try await store.verifyIntegrity() }
            }
        }
    }
}
