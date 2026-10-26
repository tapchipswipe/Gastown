import Foundation
import Testing
import NewtonCore
@testable import NewtonWorkspace

@MainActor final class TestActivity: ActivityMonitoring {
    var callbacks: [@MainActor (HistoryEvent) -> Void] = []
    var starts = 0; var stops = 0
    func start(onEvent: @escaping @MainActor (HistoryEvent) -> Void) { starts += 1; callbacks.append(onEvent) }
    func stop() { stops += 1 }
    func emit(_ title: String = "Fixture", callback: Int? = nil) {
        callbacks[callback ?? (callbacks.count - 1)](HistoryEvent(source: "test", title: title))
    }
}
@MainActor final class TestWake: WakePreventing {
    var starts = 0; var stops = 0; var failStart = false; var failStop = false
    func start() throws { if failStart { throw StoreError(message: "fixture start failure") }; starts += 1 }
    func stop() throws { if failStop { throw StoreError(message: "fixture release failure") }; stops += 1 }
}
actor InstrumentedStore: HistoryRepository {
    let base: EventStore
    var failWrites = false; var appends = 0; var pages = 0
    init() throws { base = try EventStore(path: ":memory:") }
    func setFailure(_ value: Bool) { failWrites = value }
    func append(_ events: [HistoryEvent]) async throws -> Int {
        appends += 1
        if failWrites { throw StoreError(message: "fixture disk full") }
        return try await base.append(events)
    }
    func page(_ query: String, after cursor: HistoryCursor?, limit: Int) async throws -> HistoryPage {
        pages += 1; return try await base.page(query, after: cursor, limit: limit)
    }
    func dayEvents(from start: Date, to end: Date, limit: Int) async throws -> DailyHistoryResult {
        try await base.dayEvents(from: start, to: end, limit: limit)
    }
    func count() async throws -> Int { try await base.count() }
    func deleteAll() async throws { try await base.deleteAll() }
}
actor DeferredConnector: ScreenpipeSearching {
    var pending: [String: CheckedContinuation<ScreenpipeResult, any Error>] = [:]
    var waiters: [String: CheckedContinuation<Void, Never>] = [:]
    func search(_ query: String, token: String) async throws -> ScreenpipeResult {
        try await withCheckedThrowingContinuation { continuation in
            pending[query] = continuation; waiters.removeValue(forKey: query)?.resume()
        }
    }
    func started(_ query: String) async {
        if pending[query] != nil { return }
        await withCheckedContinuation { waiters[query] = $0 }
    }
    func finish(_ query: String, events: [HistoryEvent] = []) { pending.removeValue(forKey: query)?.resume(returning: ScreenpipeResult(events: events)) }
}
actor DeferredImport {
    var continuation: CheckedContinuation<ImportBatch, any Error>?
    var waiter: CheckedContinuation<Void, Never>?
    func load(_ url: URL) async throws -> ImportBatch {
        try await withCheckedThrowingContinuation { continuation in self.continuation = continuation; waiter?.resume(); waiter = nil }
    }
    func started() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func finish(_ batch: ImportBatch) { continuation?.resume(returning: batch); continuation = nil }
}

@MainActor struct WorkspaceTests {
    @Test func featuresAreLazyAndRepeatedToggleIsIdempotent() async throws {
        let store = try EventStore(path: ":memory:"); let activity = TestActivity(); let wake = TestWake()
        var activityCreations = 0; var wakeCreations = 0
        let model = WorkspaceModel(storeFactory: { store }, activityFactory: { activityCreations += 1; return activity },
                                   wakeFactory: { wakeCreations += 1; return wake })
        await model.open()
        #expect(model.enabled.isEmpty); #expect(activityCreations == 0); #expect(wakeCreations == 0)
        model.toggle(.activity, enabled: true); model.toggle(.activity, enabled: true)
        model.toggle(.keepAwake, enabled: true); model.toggle(.keepAwake, enabled: true)
        #expect(activity.starts == 1); #expect(wake.starts == 1)
        model.toggle(.activity, enabled: false); model.toggle(.activity, enabled: false)
        model.toggle(.keepAwake, enabled: false)
        #expect(activity.stops == 1); #expect(wake.stops == 1)
        try await model.shutdown()
    }
    @Test func disablingCaptureFlushesAcceptedEventsAndIgnoresOldCallbacksAfterRestart() async throws {
        let store = try EventStore(path: ":memory:"); let activity = TestActivity()
        let model = WorkspaceModel(storeFactory: { store }, activityFactory: { activity })
        await model.open(); model.toggle(.activity, enabled: true)
        activity.emit("accepted"); model.toggle(.activity, enabled: false)
        await model.flushActivity()
        model.toggle(.activity, enabled: true)
        activity.emit("stale", callback: 0); activity.emit("new", callback: 1)
        await model.flushActivity()
        let rows = try await store.search()
        #expect(Set(rows.map(\.title)) == Set(["accepted", "new"]))
        try await model.shutdown()
    }
    @Test func activityBurstBatchesWritesWithoutRepeatedHiddenHistoryQueries() async throws {
        let store = try InstrumentedStore(); let activity = TestActivity()
        let model = WorkspaceModel(storeFactory: { store }, activityFactory: { activity })
        await model.open(); model.toggle(.activity, enabled: true)
        for i in 0..<2000 { activity.emit("app \(i)") }
        await model.flushActivity()
        #expect(try await store.count() == 2000)
        #expect(await store.appends == 16)
        #expect(await store.pages == 1)
        #expect(model.pendingWriteCount == 0)
        try await model.shutdown()
    }
    @Test func failedWritesRemainRetryableAndBlockSilentQuit() async throws {
        let store = try InstrumentedStore(); let activity = TestActivity()
        let model = WorkspaceModel(storeFactory: { store }, activityFactory: { activity })
        await model.open(); await store.setFailure(true)
        model.toggle(.activity, enabled: true); activity.emit()
        await model.flushActivity()
        #expect(model.pendingWriteCount == 1); #expect(!model.enabled.contains(.activity))
        await #expect(throws: (any Error).self) { try await model.shutdown() }
        #expect(!model.isStopping)
        await store.setFailure(false); await model.retryPendingWrites()
        #expect(model.pendingWriteCount == 0); #expect(try await store.count() == 1)
        try await model.shutdown()
    }
    @Test func shutdownFlushesQueuedActivityInsteadOfDroppingIt() async throws {
        let store = try EventStore(path: ":memory:"); let activity = TestActivity()
        let model = WorkspaceModel(storeFactory: { store }, activityFactory: { activity })
        await model.open(); model.toggle(.activity, enabled: true); activity.emit("last event")
        try await model.shutdown()
        #expect(try await store.count() == 1); #expect(model.enabled.isEmpty)
    }
    @Test func staleNetworkTaskCannotClearNewTaskBusyStateOrPublishOldResults() async throws {
        let store = try EventStore(path: ":memory:"); let connector = DeferredConnector()
        let model = WorkspaceModel(storeFactory: { store }, connector: connector)
        await model.open(); model.toggle(.screenpipe, enabled: true)
        model.screenpipeQuery = "old"; let old = try #require(model.searchScreenpipe())
        await connector.started("old")
        model.toggle(.screenpipe, enabled: false); model.toggle(.screenpipe, enabled: true)
        model.screenpipeQuery = "new"; let new = try #require(model.searchScreenpipe())
        await connector.started("new")
        await connector.finish("old", events: [HistoryEvent(source: "test", title: "old")]); await old.value
        #expect(model.screenpipeBusy); #expect(model.screenpipeResults.isEmpty)
        await connector.finish("new", events: [HistoryEvent(source: "test", title: "new")]); await new.value
        #expect(!model.screenpipeBusy); #expect(model.screenpipeResults.first?.title == "new")
        try await model.shutdown()
    }
    @Test func cancelledImportCannotWriteAfterLoaderEventuallyReturns() async throws {
        let store = try EventStore(path: ":memory:"); let loader = DeferredImport()
        let model = WorkspaceModel(storeFactory: { store }, importLoader: { try await loader.load($0) })
        await model.open()
        let task = try #require(model.importFile(URL(fileURLWithPath: "/fixture")))
        await loader.started(); model.cancelImport()
        await loader.finish(ImportBatch(events: [HistoryEvent(source: "test", title: "cancelled")]))
        _ = await task.value
        #expect(try await store.count() == 0); #expect(!model.importBusy)
        try await model.shutdown()
    }
    @Test func deleteCannotRaceAnImportAndNewCaptureIsBlockedDuringDeletion() async throws {
        let store = try EventStore(path: ":memory:"); let loader = DeferredImport()
        try await store.append([HistoryEvent(source: "test", title: "existing")])
        let model = WorkspaceModel(storeFactory: { store }, importLoader: { try await loader.load($0) })
        await model.open()
        let task = try #require(model.importFile(URL(fileURLWithPath: "/fixture")))
        await loader.started(); await model.deleteHistory()
        #expect(try await store.count() == 1)
        await loader.finish(ImportBatch(events: [HistoryEvent(source: "test", title: "imported")]))
        _ = await task.value; await model.deleteHistory()
        #expect(try await store.count() == 0); #expect(!model.deleteBusy)
        try await model.shutdown()
    }
    @Test func failedPowerReleaseDoesNotPretendFeatureIsOff() async throws {
        let store = try EventStore(path: ":memory:"); let wake = TestWake()
        let model = WorkspaceModel(storeFactory: { store }, wakeFactory: { wake })
        await model.open(); model.toggle(.keepAwake, enabled: true)
        wake.failStop = true; model.toggle(.keepAwake, enabled: false)
        #expect(model.enabled.contains(.keepAwake)); #expect(model.errorMessage != nil)
        wake.failStop = false; model.toggle(.keepAwake, enabled: false)
        #expect(!model.enabled.contains(.keepAwake)); try await model.shutdown()
    }
    @Test func failedStartupCanBeRetriedWithoutStartingFeatures() async throws {
        actor Factory {
            var attempts = 0
            func open() throws -> EventStore { attempts += 1; if attempts == 1 { throw StoreError(message: "fixture unavailable") }; return try EventStore(path: ":memory:") }
        }
        let factory = Factory(); let model = WorkspaceModel(storeFactory: { try await factory.open() })
        await model.open(); #expect(!model.ready); #expect(!model.opening)
        await model.open(); #expect(model.ready); #expect(model.enabled.isEmpty)
        try await model.shutdown()
    }
}

private actor DelayedHistory: HistoryRepository {
    let base: EventStore
    var held: CheckedContinuation<Void, Never>?
    var waiter: CheckedContinuation<Void, Never>?
    init() throws { base = try EventStore(path: ":memory:") }
    func append(_ events: [HistoryEvent]) async throws -> Int { try await base.append(events) }
    func dayEvents(from start: Date, to end: Date, limit: Int) async throws -> DailyHistoryResult {
        try await base.dayEvents(from: start, to: end, limit: limit)
    }
    func count() async throws -> Int { try await base.count() }
    func deleteAll() async throws { try await base.deleteAll() }
    func page(_ query: String, after cursor: HistoryCursor?, limit: Int) async throws -> HistoryPage {
        let snapshot = try await base.page(query, after: cursor, limit: limit)
        if query == "old" { await withCheckedContinuation { held = $0; waiter?.resume(); waiter = nil } }
        return snapshot
    }
    func started() async { if held != nil { return }; await withCheckedContinuation { waiter = $0 } }
    func release() { held?.resume(); held = nil }
}

@MainActor struct WorkspaceAuditTests {
    @Test func changedQueryInvalidatesOldResultsBeforeDebounceExpires() async throws {
        let store = try DelayedHistory()
        let model = WorkspaceModel(storeFactory: { store })
        await model.open()
        _ = try await store.append([HistoryEvent(source: "test", title: "old")])
        model.query = "old"
        let refresh = Task { await model.refresh() }
        await store.started(); model.query = "new"
        await store.release(); await refresh.value
        #expect(model.events.first?.title != "old")
        try await model.shutdown()
    }
    @Test func shutdownDoesNotHangOnCancelledLoaderWhichCannotCommit() async throws {
        let store = try EventStore(path: ":memory:"); let loader = DeferredImport()
        let model = WorkspaceModel(storeFactory: { store }, importLoader: { try await loader.load($0) })
        await model.open(); let importTask = try #require(model.importFile(URL(fileURLWithPath: "/fixture")))
        await loader.started()
        try await model.shutdown()
        await loader.finish(ImportBatch(events: [HistoryEvent(source: "test", title: "must not persist")]))
        _ = await importTask.value
        #expect(try await store.count() == 0)
    }
    @Test func historyPaginationReachesEventsBeyondFirstHundred() async throws {
        let store = try EventStore(path: ":memory:")
        try await store.append((0..<251).map { HistoryEvent(source: "test", title: "event \($0)") })
        let model = WorkspaceModel(storeFactory: { store })
        await model.open(); #expect(model.events.count == 100); #expect(model.hasMoreHistory)
        await model.loadMore(); await model.loadMore()
        #expect(model.events.count == 251); #expect(!model.hasMoreHistory)
        #expect(Set(model.events.map(\.id)).count == 251)
        try await model.shutdown()
    }
    @Test func existingDataDirectoryIsMadePrivate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = WorkspaceModel(directory: directory)
        await model.open(); #expect(model.ready)
        let mode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o700)
        try await model.shutdown()
    }
}

@MainActor struct RequestOwnershipTests {
    @Test func editingQueryInvalidatesInFlightScreenpipeResult() async throws {
        let store = try EventStore(path: ":memory:"); let connector = DeferredConnector()
        let model = WorkspaceModel(storeFactory: { store }, connector: connector)
        await model.open(); model.toggle(.screenpipe, enabled: true); model.screenpipeQuery = "old"
        let task = try #require(model.searchScreenpipe()); await connector.started("old")
        model.screenpipeQuery = "new"
        #expect(!model.screenpipeBusy)
        await connector.finish("old", events: [HistoryEvent(source: "test", title: "stale")]); await task.value
        #expect(model.screenpipeResults.isEmpty)
        try await model.shutdown()
    }
    @Test func concurrentShutdownCallsJoinTheSameDrain() async throws {
        let store = try EventStore(path: ":memory:"); let activity = TestActivity(); let wake = TestWake()
        let model = WorkspaceModel(storeFactory: { store }, activityFactory: { activity }, wakeFactory: { wake })
        await model.open(); model.toggle(.activity, enabled: true); model.toggle(.keepAwake, enabled: true)
        activity.emit("last")
        async let first: Void = model.shutdown()
        async let second: Void = model.shutdown()
        try await first; try await second
        #expect(wake.stops == 1); #expect(activity.stops == 1)
        #expect(try await store.count() == 1)
    }
}
