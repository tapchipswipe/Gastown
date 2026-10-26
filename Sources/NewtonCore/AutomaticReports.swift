import Foundation
import CryptoKit

public struct CaptureCoverageRecord: Codable, Sendable, Identifiable {
    public let id: String
    public let source: String
    public let start: Date
    public var end: Date?
    public let state: String
    public let reason: String
    public init(source: String, state: String, reason: String, at: Date = Date()) {
        id = UUID().uuidString; self.source = source; start = at; end = nil; self.state = state; self.reason = reason
    }
}
public struct StoredDailyReport: Codable, Sendable, Identifiable {
    public let id: String
    public let from: Date
    public let to: Date
    public let generatedAt: Date
    public let inputDigest: String
    public let observationCount: Int
    public let databaseRangeComplete: Bool
    public let sources: [String]
    public let sourceIDs: [String]
    public let markdown: String
    public let engine: String
    public let coverage: [CaptureCoverageRecord]
}
/// Local semantic engines may rank/select existing observations. Factual prose and citations
/// are rendered from those records, so a model cannot authorize invented report assertions.
public protocol LocalReportSummarizing: Sendable {
    var name: String { get }
    func selectObservationIDs(events: [HistoryEvent]) async throws -> [String]
}
public struct DeterministicReportSummarizer: LocalReportSummarizing {
    public let name = "Deterministic local extraction"
    public init() {}
    public func selectObservationIDs(events: [HistoryEvent]) async throws -> [String] { events.map(\.id) }
}
public actor DailyReportService {
    private let history: any HistoryRepository
    private let store: IntelligenceStore
    private let summarizer: any LocalReportSummarizing
    private var busy = false
    public init(history: any HistoryRepository, store: IntelligenceStore, summarizer: any LocalReportSummarizing = DeterministicReportSummarizer()) {
        self.history = history; self.store = store; self.summarizer = summarizer
    }
    public static func dueRange(now: Date, calendar: Calendar = .current) -> DateInterval? {
        let start = calendar.startOfDay(for: now)
        guard let due = calendar.date(bySettingHour: 8, minute: 15, second: 0, of: start), now >= due,
              let yesterday = calendar.date(byAdding: .day,value: -1,to: start) else { return nil }
        return DateInterval(start: yesterday, end: start)
    }
    public func generateIfDue(now: Date = Date(), projects: [TrackedProject] = [], calendar: Calendar = .current) async throws -> StoredDailyReport? {
        guard !busy, let range = Self.dueRange(now: now, calendar: calendar) else { return nil }
        busy = true; defer { busy = false }
        var events: [HistoryEvent] = [], cursor: RangeHistoryCursor?
        repeat {
            try Task.checkCancellation()
            let page = try await history.rangePage(from: range.start,to: range.end,query: "",after: cursor,limit: min(500,50_000-events.count))
            events += page.events; cursor = page.nextCursor
        } while cursor != nil && events.count < 50_000
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var digest = SHA256()
        for event in events { digest.update(data: try encoder.encode(event)) }
        let coverage = try await store.coverageIntervals(from: range.start,to: range.end)
        digest.update(data: try encoder.encode(coverage.sorted { $0.id < $1.id }))
        let hash = digest.finalize().map { String(format: "%02x",$0) }.joined()
        let id = range.start.ISO8601Format()
        if let previous = try await store.load(StoredDailyReport.self,namespace: "reports",id: id), previous.inputDigest == hash { return previous }
        var selected = events, engine = "Deterministic local extraction"
        if let ids = try? await summarizer.selectObservationIDs(events: events), !ids.isEmpty {
            let available = Dictionary(events.map { ($0.id,$0) },uniquingKeysWith: { first,_ in first })
            if ids.count <= 50_000,Set(ids).count == ids.count,ids.allSatisfy({ available[$0] != nil }) {
                selected = ids.compactMap { available[$0] }; engine = summarizer.name
            }
        }
        let text = PipeAutomationEngine.synthesizeStandup(events: selected,projects: projects).fullMarkdown
        let report = StoredDailyReport(id: id,from: range.start,to: range.end,generatedAt: now,inputDigest: hash,observationCount: events.count,databaseRangeComplete: cursor == nil,sources: Array(Set(events.map(\.source))).sorted(),sourceIDs: selected.prefix(100).map(\.id),markdown: "Database range \(cursor == nil ? "complete" : "truncated at 50,000"); source coverage depends on enabled capabilities. Coverage before Newton's coverage journal is unknown.\n\n" + text,engine: engine,coverage: coverage)
        try Task.checkCancellation(); try await store.save(report,namespace: "reports",id: id)
        return report
    }
}
