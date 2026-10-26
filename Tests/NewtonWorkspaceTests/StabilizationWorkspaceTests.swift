import Foundation
import Observation
import Testing
import NewtonCore
@testable import NewtonWorkspace

@MainActor final class FixtureRecorder: WorkflowRecording {
    var isRecording = false
    var starts = 0; var stops = 0; var fails = false
    var handlers: [@MainActor (WorkflowSession) -> Void] = []
    func start(sessionTitle: String, onLimit: @escaping @MainActor (WorkflowSession) -> Void) throws {
        if fails { throw StoreError(message: "fixture monitor unavailable") }
        starts += 1; isRecording = true; handlers.append(onLimit)
    }
    func stop() -> WorkflowSession? {
        stops += 1
        guard isRecording else { return nil }
        isRecording = false
        return WorkflowSession(title: "fixture")
    }
}
@MainActor final class ObservationFlag { var changed = false }
@Suite(.timeLimit(.minutes(1)))
@MainActor struct StabilizationWorkspaceTests {
    @Test func recordingIsObservedFailsTruthfullyAndShutdownTearsDown() async throws {
        let store = try EventStore(path: ":memory:"), recorder = FixtureRecorder()
        let model = WorkspaceModel(storeFactory: { store }, workflowRecorder: recorder)
        model.startWorkflowRecording(); #expect(recorder.starts == 0)
        await model.open()
        let flag = ObservationFlag()
        withObservationTracking { _ = model.isRecordingWorkflow } onChange: {
            Task { @MainActor in flag.changed = true }
        }
        model.startWorkflowRecording(); await Task.yield()
        #expect(flag.changed); #expect(model.isRecordingWorkflow)
        await #expect(throws: (any Error).self) { try await model.shutdown() }
        #expect(!recorder.isRecording); #expect(!model.isRecordingWorkflow)
        #expect(model.pendingWorkflow != nil)
        model.discardWorkflow(); recorder.fails = true
        model.startWorkflowRecording(); #expect(!model.isRecordingWorkflow)
        recorder.fails = false; model.startWorkflowRecording()
        recorder.handlers[0](WorkflowSession(title: "stale"))
        #expect(model.pendingWorkflow == nil); #expect(model.isRecordingWorkflow)
        recorder.isRecording = false // Native service tears down before delivering a limit session.
        recorder.handlers.last?(WorkflowSession(title: "limit"))
        #expect(!model.isRecordingWorkflow); #expect(model.pendingWorkflow?.title == "limit")
        model.discardWorkflow(); try await model.shutdown()
    }
    @Test func failedExportAndIndexingRetainSessionForRetry() async throws {
        let store = try InstrumentedStore(), recorder = FixtureRecorder()
        var calls = 0
        let fixture = ExportFixture()
        let model = WorkspaceModel(storeFactory: { store }, workflowRecorder: recorder, workflowExporter: { session, directory in try await fixture.save(session, directory) })
        await model.open(); model.startWorkflowRecording()
        #expect(await model.stopWorkflowRecording() == nil)
        #expect(model.pendingWorkflow != nil); #expect(model.status.contains("failed"))
        await fixture.allow(); await store.setFailure(true)
        #expect(await model.stopWorkflowRecording() == nil)
        #expect(model.status.contains("indexing failed")); #expect(model.pendingWorkflow != nil)
        await store.setFailure(false)
        #expect(await model.stopWorkflowRecording() != nil)
        calls = await fixture.calls
        #expect(calls == 2); #expect(model.pendingWorkflow == nil)
        #expect(try await store.count() == 1)
        try await model.shutdown()
    }
}
actor ExportFixture {
    var fail = true; var calls = 0
    func allow() { fail = false }
    func save(_ session: WorkflowSession, _ directory: URL) throws -> URL {
        calls += 1
        if fail { throw StoreError(message: "fixture unwritable export") }
        return URL(fileURLWithPath: "/disposable-export-fixture")
    }
}

actor StalledQuota {
    var continuation: CheckedContinuation<QuotaSnapshot, Never>?
    var waiter: CheckedContinuation<Void, Never>?
    func load() async -> QuotaSnapshot {
        await withCheckedContinuation { continuation = $0; waiter?.resume(); waiter = nil }
    }
    func started() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release() { continuation?.resume(returning: QuotaSnapshot(quota: nil, diagnostic: "late fixture")); continuation = nil }
}
actor DeferredFileIntake {
    var continuation: CheckedContinuation<FileIntakeResult, any Error>?
    var waiter: CheckedContinuation<Void, Never>?
    func load(_ request: FileIntakeRequest) async throws -> FileIntakeResult {
        try await withCheckedThrowingContinuation { continuation = $0; waiter?.resume(); waiter = nil }
    }
    func started() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release() {
        var report = IntakeReport(); report.events = [HistoryEvent(id: "cancelled", source: "fixture", title: "must not commit")]
        continuation?.resume(returning: FileIntakeResult(report: report)); continuation = nil
    }
}
actor IdeaIntakeFixture {
    var calls = 0; var reused = false
    func load(_ request: FileIntakeRequest) throws -> FileIntakeResult {
        calls += 1
        guard case let .saveIdea(_, _, _, existing) = request else { throw StoreError(message: "Wrong source") }
        reused = existing != nil
        var report = IntakeReport(); report.events = [HistoryEvent(id: "stable-idea", source: "fixture", title: "idea")]
        return FileIntakeResult(report: report, savedURL: URL(fileURLWithPath: "/disposable-fixture/idea.md"))
    }
}
@Suite(.timeLimit(.minutes(1)))
@MainActor struct IntakeAndStartupTests {
    @Test func optionalStalledServicesDoNotDelayOpenOrShutdown() async throws {
        let store = try EventStore(path: ":memory:"), quota = StalledQuota(), projects = StalledQuota()
        let model = WorkspaceModel(storeFactory: { store }, quotaLoader: { await quota.load() }, projectLoader: { _ = await projects.load(); return [] })
        await model.open(); #expect(model.ready)
        await quota.started(); await projects.started()
        try await model.shutdown() // Completes while both optional services remain suspended.
        await quota.release(); await projects.release(); await Task.yield()
        #expect(model.quotaDescription != "late fixture"); #expect(model.trackedProjects.isEmpty)
    }
    @Test func allFileIntakeExcludesDeleteAndCancellationPreventsCommit() async throws {
        for useAtlas in [false, true] {
            let store = try EventStore(path: ":memory:"), loader = DeferredFileIntake()
            try await store.append([HistoryEvent(source: "fixture", title: "preserve")])
            let model = WorkspaceModel(storeFactory: { store }, fileIntake: { try await loader.load($0) })
            await model.open()
            let task = Task { if useAtlas { await model.importTimeAtlas() } else { await model.importICloudIdeas() } }
            await loader.started(); #expect(model.importBusy)
            await model.deleteHistory(); #expect(try await store.count() == 1)
            #expect(model.importFile(URL(fileURLWithPath: "/no-fixture-read")) == nil)
            model.cancelImport(); try await model.shutdown()
            await loader.release(); await task.value
            #expect(try await store.count() == 1)
        }
    }
    @Test func ideaIndexFailureKeepsDestinationAndRetryReusesSavedFile() async throws {
        let store = try InstrumentedStore(), fixture = IdeaIntakeFixture()
        let model = WorkspaceModel(storeFactory: { store }, fileIntake: { try await fixture.load($0) })
        await model.open(); await store.setFailure(true)
        #expect(await model.saveQuickIdea(title: "fixture") == false)
        #expect(model.lastIdeaDestination == "/disposable-fixture/idea.md")
        #expect(model.status.contains("File retained"))
        await store.setFailure(false)
        #expect(await model.saveQuickIdea(title: "fixture"))
        #expect(await fixture.reused); #expect(try await store.count() == 1)
        try await model.shutdown()
    }
}

actor GatedAppendStore: HistoryRepository {
    let base: EventStore
    var continuation: CheckedContinuation<Void, Never>?
    var waiter: CheckedContinuation<Void, Never>?
    init() throws { base = try EventStore(path: ":memory:") }
    func append(_ events: [HistoryEvent]) async throws -> Int {
        await withCheckedContinuation { continuation = $0; waiter?.resume(); waiter = nil }
        return try await base.append(events)
    }
    func started() async { if continuation != nil { return }; await withCheckedContinuation { waiter = $0 } }
    func release() { continuation?.resume(); continuation = nil }
    func page(_ query: String, after cursor: HistoryCursor?, limit: Int) async throws -> HistoryPage { try await base.page(query, after: cursor, limit: limit) }
    func dayEvents(from start: Date, to end: Date, limit: Int) async throws -> DailyHistoryResult {
        try await base.dayEvents(from: start, to: end, limit: limit)
    }
    func count() async throws -> Int { try await base.count() }
    func deleteAll() async throws { try await base.deleteAll() }
}
actor FixtureManualAgent: ManualAgentRunning {
    var continuation: CheckedContinuation<AgentTaskStatus, Never>?
    var waiter: CheckedContinuation<Void, Never>?
    var callback: (@Sendable (AgentTaskStatus) -> Void)?
    var id: UUID?; var calls = 0
    func run(id: UUID, task: PromptTask, repository: URL, provider: AIModelProvider, unattended: Bool, progress: @escaping @Sendable (AgentTaskStatus) -> Void) async -> AgentTaskStatus {
        self.id = id; calls += 1; callback = progress
        return await withCheckedContinuation { continuation = $0; waiter?.resume(); waiter = nil }
    }
    func started() async { if continuation != nil { return }; await withCheckedContinuation { waiter = $0 } }
    func cancel(id: UUID) {
        guard self.id == id else { return }
        continuation?.resume(returning: AgentTaskStatus(taskTitle: "fixture", runID: id, phase: .cancelled)); continuation = nil
    }
    func lateProgress() { if let id { callback?(AgentTaskStatus(taskTitle: "late", runID: id, phase: .running)) } }
}
@Suite(.timeLimit(.minutes(1)))
@MainActor struct OperationDrainTests {
    @Test func shutdownDrainsAcceptedFileWrites() async throws {
        let store = try GatedAppendStore()
        let model = WorkspaceModel(storeFactory: { store }, importLoader: { _ in ImportBatch(events: [HistoryEvent(source: "fixture", title: "accepted")]) })
        await model.open()
        let intake = try #require(model.importFile(URL(fileURLWithPath: "/disposable-fixture")))
        await store.started()
        let shutdown = Task { try await model.shutdown() }
        await Task.yield(); #expect(model.importBusy)
        await store.release(); _ = await intake.value; try await shutdown.value
        #expect(try await store.count() == 1)
    }
    @Test func workspaceOwnsOverlapCancellationAndLateAgentProgress() async throws {
        let store = try EventStore(path: ":memory:"), agent = FixtureManualAgent()
        let model = WorkspaceModel(storeFactory: { store }, manualAgent: agent)
        await model.open(); model.agentRepositoryPath = "/disposable-fixture"
        let first = Task { await model.dispatchIdeaToCodex(title: "fixture") }
        await agent.started()
        await model.dispatchIdeaToCodex(title: "overlap")
        #expect(await agent.calls == 1)
        try await model.shutdown(); await first.value
        #expect(model.activeAgentStatus?.phase == .cancelled)
        await agent.lateProgress(); await Task.yield()
        #expect(model.activeAgentStatus?.phase == .cancelled)
    }
}

@MainActor final class FixtureActionSource: WorkflowEventSource {
    var handlers: [@MainActor (CapturedAction) -> Void] = []
    var resources = 0; var fail = false
    func start(onAction: @escaping @MainActor (CapturedAction) -> Void) throws {
        resources = 2; handlers.append(onAction)
        if fail { throw StoreError(message: "fixture partial monitor failure") }
    }
    func stop() { resources = 0 }
    func emit(_ title: String = "current", index: Int? = nil) { handlers[index ?? handlers.count - 1](CapturedAction(type: .appSwitch, appName: title)) }
}
@Suite(.timeLimit(.minutes(1)))
@MainActor struct RecordingAdapterTests {
    @Test func realServiceIgnoresOldCallbacksAndRemovesInjectedMonitors() throws {
        let source = FixtureActionSource()
        let service = ScreenActionCaptureService(source: source)
        try service.start(sessionTitle: "first") { _ in }
        source.emit(); #expect(source.resources == 2)
        let first = service.stop(); #expect(first?.actions.count == 1)
        #expect(service.stop() == nil); #expect(source.resources == 0)
        try service.start(sessionTitle: "second") { _ in }
        source.emit("stale", index: 0); source.emit("fresh")
        #expect(service.stop()?.actions.map(\.appName) == ["fresh"])
        source.fail = true
        #expect(throws: (any Error).self) { try service.start(sessionTitle: "failure") { _ in } }
        #expect(!service.isRecording); #expect(source.resources == 0)
    }
    @Test func actionLimitAndDeadlineStopNativeServiceWithoutCapturingDesktop() async throws {
        let source = FixtureActionSource()
        let limited = ScreenActionCaptureService(source: source, maximumActions: 2)
        var session: WorkflowSession?
        try limited.start(sessionTitle: "limited") { session = $0 }
        source.emit(); source.emit(); source.emit()
        #expect(!limited.isRecording); #expect(source.resources == 0); #expect(session?.actions.count == 2)
        let timedSource = FixtureActionSource()
        let deadlineService = ScreenActionCaptureService(source: timedSource, maximumSeconds: 0.02)
        let (stream, continuation) = AsyncStream<WorkflowSession>.makeStream()
        try deadlineService.start(sessionTitle: "deadline") { continuation.yield($0); continuation.finish() }
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next()?.title == "deadline")
        #expect(!deadlineService.isRecording); #expect(timedSource.resources == 0)
    }
}

@MainActor final class FixtureQuotaClock { var now = Date() }
@Suite(.timeLimit(.minutes(1)))
@MainActor struct QuotaAgeWorkspaceTests {
    @Test func quotaWarningAgesWithoutReadingAnyMoreFiles() async throws {
        let clock = FixtureQuotaClock(), store = try EventStore(path: ":memory:")
        let snapshot = QuotaSnapshot(quota: CodexQuota(planType: "fixture", primary: QuotaWindow(usedPercent: 1, windowMinutes: 300, resetsAt: clock.now.addingTimeInterval(3600)), observedAt: clock.now), diagnostic: "fixture")
        let model = WorkspaceModel(storeFactory: { store }, quotaLoader: { snapshot }, quotaNow: { clock.now })
        await model.open()
        for _ in 0..<1000 { if model.codexQuota != nil { break }; await Task.yield() }
        #expect(model.quotaDescription.contains("Recent"))
        clock.now = clock.now.addingTimeInterval(901)
        #expect(model.quotaDescription.contains("Stale"))
        try await model.shutdown()
    }
}
