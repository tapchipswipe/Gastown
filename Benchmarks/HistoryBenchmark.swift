import Foundation
import NewtonCore

@main
struct HistoryBenchmark {
    static func main() async throws {
        let count = min(50_000, max(100, Int(ProcessInfo.processInfo.environment["NEWTON_BENCH_EVENTS"] ?? "10000") ?? 10_000))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("newton-benchmark-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try EventStore(path: root.appendingPathComponent("history.sqlite").path)
        let events = (0..<count).map {
            HistoryEvent(id: "event-\($0)", timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double($0)),
                         source: "benchmark", title: "Project \($0 % 50) work session", detail: "commit \($0) indexed evidence")
        }
        let clock = ContinuousClock()
        let appendTime = try await clock.measure { try await store.append(events) }
        let duplicateTime = try await clock.measure { try await store.append(events) }
        var queryTimes: [Double] = []
        for query in ["", "commit", "Project 17", "evidence missingterm"] {
            let elapsed = try await clock.measure { _ = try await store.search(query) }
            queryTimes.append(milliseconds(elapsed))
        }
        guard try await store.count() == count else { throw StoreError(message: "Benchmark count mismatch") }
        let sizes = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])
        let diskBytes = try sizes.reduce(0) { $0 + (try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        let result: [String: Any] = ["events": count, "append_ms": milliseconds(appendTime),
            "duplicate_append_ms": milliseconds(duplicateTime), "query_ms": queryTimes,
            "queries": ["recent", "common term", "project conjunction", "no matches"], "database_and_wal_bytes": diskBytes,
            "note": "Single local release-build sample; synthetic disposable history, not a battery or UI benchmark"]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }
}
