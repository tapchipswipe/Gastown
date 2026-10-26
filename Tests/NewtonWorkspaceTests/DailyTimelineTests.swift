import Foundation
import Testing
import NewtonCore
@testable import NewtonWorkspace

actor GatedDayStore: HistoryRepository {
    let base: EventStore
    var held: CheckedContinuation<Void, Never>?
    var waiter: CheckedContinuation<Void, Never>?
    var blockNext = false
    init() throws { base = try EventStore(path: ":memory:") }
    func append(_ events: [HistoryEvent]) async throws -> Int { try await base.append(events) }
    func page(_ query: String, after cursor: HistoryCursor?, limit: Int) async throws -> HistoryPage { try await base.page(query, after: cursor, limit: limit) }
    func count() async throws -> Int { try await base.count() }
    func deleteAll() async throws { try await base.deleteAll() }
    func holdNext() { blockNext = true }
    func dayEvents(from start: Date, to end: Date, limit: Int) async throws -> DailyHistoryResult {
        let snapshot = try await base.dayEvents(from: start, to: end, limit: limit)
        if blockNext {
            blockNext = false
            await withCheckedContinuation { held = $0; waiter?.resume(); waiter = nil }
        }
        return snapshot
    }
    func started() async { if held != nil { return }; await withCheckedContinuation { waiter = $0 } }
    func release() { held?.resume(); held = nil }
}

@MainActor struct DailyTimelineTests {
    @Test func dailyHistoryIsIndependentOfSearchAndPaging() async throws {
        let store = try EventStore(path: ":memory:")
        try await store.append((0..<220).map { HistoryEvent(timestamp: Date(), source: "Activity", title: "event \($0)") })
        let model = WorkspaceModel(storeFactory: { store })
        await model.open(); await model.waitForTimeline()
        #expect(model.events.count == 100)
        #expect(model.timelineSummary.observationCount == 220)
        model.query = "no matches"; await model.refresh()
        #expect(model.events.isEmpty)
        #expect(model.timelineSummary.observationCount == 220)
        try await model.shutdown()
    }
    @Test func oldDayResultsCannotPublishAfterDateChangeOrDeletion() async throws {
        let store = try GatedDayStore()
        _ = try await store.append([HistoryEvent(source: "Activity", title: "old")])
        let model = WorkspaceModel(storeFactory: { store })
        await model.open(); await model.waitForTimeline()
        await store.holdNext(); model.requestTimeline(); await store.started()
        #expect(model.timelineSummary.observationCount == 1) // Same-day refresh retains accepted cache.
        let supersededWait = Task { await model.waitForTimeline() }
        model.timelineDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        await model.waitForTimeline(); await store.release(); await supersededWait.value
        #expect(model.timelineSummary.observationCount == 0)
        model.timelineDate = Date(); await model.waitForTimeline()
        await store.holdNext(); model.requestTimeline(); await store.started()
        await model.deleteHistory(); await model.waitForTimeline(); await store.release()
        #expect(model.timelineSummary.observationCount == 0)
        try await model.shutdown()
    }
    @Test func shutdownRejectsOutstandingDailyResult() async throws {
        let store = try GatedDayStore()
        _ = try await store.append([HistoryEvent(source: "Activity", title: "fixture")])
        let model = WorkspaceModel(storeFactory: { store })
        await model.open(); await model.waitForTimeline()
        await store.holdNext(); model.requestTimeline(); await store.started()
        try await model.shutdown(); await store.release()
        for _ in 0..<10 { await Task.yield() }
        #expect(model.timeline.isEmpty)
        #expect(model.timelineBusy == false)
    }
}
