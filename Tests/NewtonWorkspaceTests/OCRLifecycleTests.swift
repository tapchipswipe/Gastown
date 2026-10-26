import Foundation
import Testing
import NewtonCore
@testable import NewtonWorkspace

@MainActor final class FixtureOCR: ScreenOCRCapturing {
    var callbacks: [@MainActor (HistoryEvent) -> Void] = []
    var states: [@MainActor (OCRCaptureState) -> Void] = []
    var stops = 0
    func start(onState: @escaping @MainActor (OCRCaptureState) -> Void, onEvent: @escaping @MainActor (HistoryEvent) -> Void) {
        callbacks.append(onEvent); states.append(onState); onState(.starting)
    }
    func stop() { stops += 1 }
    func emit(_ index: Int) { callbacks[index](HistoryEvent(source: "Screenpipe · ocr", title: "fixture", detail: "observed")) }
}
actor GatedOCRSample {
    var pending: [CheckedContinuation<HistoryEvent?, any Error>] = []
    var waiter: CheckedContinuation<Void, Never>?
    func sample() async throws -> HistoryEvent? {
        try await withCheckedThrowingContinuation { pending.append($0); waiter?.resume(); waiter = nil }
    }
    func started() async { if !pending.isEmpty { return }; await withCheckedContinuation { waiter = $0 } }
    func finish() { pending.removeFirst().resume(returning: HistoryEvent(source: "screen_ocr", title: "fixture", detail: "text")) }
}
actor SlowCancelAgent: ManualAgentRunning {
    var runContinuation: CheckedContinuation<AgentTaskStatus, Never>?
    var startWaiter: CheckedContinuation<Void, Never>?
    var cancelWaiter: CheckedContinuation<Void, Never>?
    var cancelled = false
    var id = UUID()
    func run(id: UUID, task: PromptTask, repository: URL, provider: AIModelProvider, unattended: Bool,
             progress: @escaping @Sendable (AgentTaskStatus) -> Void) async -> AgentTaskStatus {
        self.id = id
        return await withCheckedContinuation { runContinuation = $0; startWaiter?.resume(); startWaiter = nil }
    }
    func started() async { if runContinuation != nil { return }; await withCheckedContinuation { startWaiter = $0 } }
    func cancel(id: UUID) { cancelled = true; cancelWaiter?.resume(); cancelWaiter = nil }
    func cancellationStarted() async { if cancelled { return }; await withCheckedContinuation { cancelWaiter = $0 } }
    func finish() { runContinuation?.resume(returning: AgentTaskStatus(taskTitle: "fixture", runID: id, phase: .cancelled)); runContinuation = nil }
}
@MainActor struct OCRLifecycleTests {
    @Test func workspaceRejectsLateCallbacksDrainsAcceptedWritesAndStopsForDeleteQuit() async throws {
        let store = try EventStore(path: ":memory:"), capture = FixtureOCR()
        let model = WorkspaceModel(storeFactory: { store }, ocrCapture: capture)
        await model.open()
        #expect(model.enabled.contains(.screenOCR) == false)
        model.toggle(.screenOCR, enabled: true); capture.emit(0)
        model.toggle(.screenOCR, enabled: false); capture.emit(0)
        await model.flushActivity()
        #expect(try await store.count() == 1)
        model.toggle(.screenOCR, enabled: true); capture.emit(0); capture.emit(1)
        await model.flushActivity(); #expect(try await store.count() == 2)
        await model.deleteHistory(); capture.emit(1)
        #expect(try await store.count() == 0)
        #expect(model.isPaused)
        model.resumeAll()
        model.toggle(.screenOCR, enabled: true); capture.emit(2)
        try await model.shutdown(); capture.emit(2)
        #expect(try await store.count() == 1)
        #expect(capture.stops == 3)
    }
    @Test func permissionFailureVisibleAndRestartPossible() async throws {
        let capture = FixtureOCR(), store = try EventStore(path: ":memory:")
        let model = WorkspaceModel(storeFactory: { store }, ocrCapture: capture)
        await model.open(); model.toggle(.screenOCR, enabled: true)
        capture.states[0](.failed("Screen Recording permission denied"))
        #expect(model.ocrState == .failed("Screen Recording permission denied"))
        #expect(model.enabled.contains(.screenOCR) == false)
        #expect(model.errorMessage?.contains("permission") == true)
        model.toggle(.screenOCR, enabled: true); capture.emit(0); capture.emit(1)
        await model.flushActivity(); #expect(try await store.count() == 1)
        try await model.shutdown()
    }
    @Test func serviceSleepLockAndStopRejectStaleSamples() async throws {
        let sampler = GatedOCRSample()
        let service = ScreenOCRService(sample: { try await sampler.sample() }, interval: .seconds(100))
        var events: [HistoryEvent] = [], states: [OCRCaptureState] = []
        service.start(onState: { states.append($0) }, onEvent: { events.append($0) })
        await sampler.started(); service.setSuspended(true, reason: "sleep")
        service.setSuspended(true, reason: "lock")
        await sampler.finish()
        service.setSuspended(false, reason: "sleep")
        #expect(states.last == .paused)
        service.setSuspended(false, reason: "lock"); await sampler.started()
        service.stop(); await sampler.finish()
        for _ in 0..<10 { await Task.yield() }
        #expect(events.isEmpty)
        #expect(states.last == .stopped)
        service.start(onState: { states.append($0) }, onEvent: { events.append($0) })
        await sampler.started(); service.stop(); await sampler.finish()
    }
    @Test func serviceStartErrorIsObservable() async {
        let service = ScreenOCRService(sample: { throw StoreError(message: "permission fixture") })
        let (stream, continuation) = AsyncStream<OCRCaptureState>.makeStream()
        service.start(onState: { continuation.yield($0) }, onEvent: { _ in Issue.record("Unexpected OCR record") })
        for await state in stream {
            if case .failed(let message) = state { #expect(message.contains("permission fixture")); break }
        }
        continuation.finish(); service.stop()
    }
    @Test func nativeServiceFailureCannotBeOverwrittenByStoppingNotifications() async throws {
        let capture = ScreenOCRService(sample: { throw StoreError(message: "permission denied fixture") })
        let store = try EventStore(path: ":memory:")
        let model = WorkspaceModel(storeFactory: { store }, ocrCapture: capture)
        await model.open(); model.toggle(.screenOCR, enabled: true)
        for _ in 0..<100 where model.enabled.contains(.screenOCR) { await Task.yield() }
        guard case .failed(let message) = model.ocrState else { Issue.record("Capture failure state was lost"); return }
        #expect(message.contains("permission denied"))
        try await model.shutdown()
    }
    @Test func shutdownStopsCaptureBeforeJoiningSlowProcessTeardown() async throws {
        let capture = FixtureOCR(), store = try EventStore(path: ":memory:"), agent = SlowCancelAgent()
        let model = WorkspaceModel(storeFactory: { store }, ocrCapture: capture, manualAgent: agent)
        await model.open(); model.agentRepositoryPath = "/fixture"
        model.toggle(.screenOCR, enabled: true)
        let run = Task { await model.dispatchIdeaToCodex(title: "fixture") }
        await agent.started()
        let shutdown = Task { try await model.shutdown() }
        await agent.cancellationStarted()
        #expect(capture.stops == 1)
        #expect(model.enabled.contains(.screenOCR) == false)
        capture.emit(0)
        await agent.finish(); try await shutdown.value; await run.value
        #expect(try await store.count() == 0)
    }
}
