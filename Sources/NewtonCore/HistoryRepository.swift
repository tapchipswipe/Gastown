import Foundation

public protocol HistoryRepository: Sendable {
    @discardableResult func append(_ events: [HistoryEvent]) async throws -> Int
    func page(_ query: String, after cursor: HistoryCursor?, limit: Int) async throws -> HistoryPage
    func rangePage(from: Date, to: Date, query: String, after: RangeHistoryCursor?, limit: Int) async throws -> RangeHistoryPage
    func count() async throws -> Int
    func deleteAll() async throws
    func dayEvents(from start: Date, to end: Date, limit: Int) async throws -> DailyHistoryResult
}

public struct DailyHistoryResult: Sendable, Equatable {
    public let events: [HistoryEvent]
    public let isComplete: Bool
    public init(events: [HistoryEvent], isComplete: Bool) {
        self.events = events; self.isComplete = isComplete
    }
}

extension EventStore: HistoryRepository {}

/// Coverage describes returned observations, not proof of continuous recording.
public struct ObservationCoverage: Sendable, Equatable {
    public let start: Date
    public let end: Date
    public let firstObserved: Date?
    public let lastObserved: Date?
    public let sources: [String]
    public let continuity = "Capture gaps unknown; disabled or excluded sources are not observed"
}
public struct RangeHistoryCursor: Sendable, Equatable {
    let start: Date
    let end: Date
    let query: String
    let timestamp: Double
    let id: String
}
public struct RangeHistoryPage: Sendable {
    public let events: [HistoryEvent]
    public let nextCursor: RangeHistoryCursor?
    public let coverage: ObservationCoverage
    public var isTruncated: Bool { nextCursor != nil }
}
public extension HistoryRepository {
    func rangePage(from: Date, to: Date, query: String, after: RangeHistoryCursor?, limit: Int) async throws -> RangeHistoryPage {
        throw StoreError(message: "This history source does not support range queries")
    }
}
