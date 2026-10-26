import Testing
import CSQLite
import Foundation
import CoreGraphics
import NewtonCore
@testable import NewtonWorkspace

@MainActor final class DeniedKeyboardTap: KeyboardTapInstalling {
    var attempts = 0
    func install(_ intercept: @escaping @MainActor (CGEventType, CGEvent) -> Bool) -> Bool { attempts += 1; return false }
    func stop() {}
}
@MainActor @Suite struct ReliabilityWorkspaceTests {
    @Test func permissionDenialCannotClaimKeyboardLock() {
        let driver = DeniedKeyboardTap(), service = KeyboardProtectionService(driver: DeniedKeyboardTap())
        #expect(!service.startCleaning())
        #expect(!service.cleaningActive)
        #expect(service.state.phase == .blocked)
        let other = KeyboardProtectionService(driver: driver)
        other.setSuspended(true)
        #expect(!other.startCleaning() && driver.attempts == 0)
    }
    @Test func workspaceRangeUsesDatabaseBeyondPresentationPage() async throws {
        let store = try EventStore(path: ":memory:")
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.append((0..<1201).map { HistoryEvent(id: "event-\($0)", timestamp: start, source: "fixture", title: "TODO: evidence \($0)") })
        let model = WorkspaceModel(storeFactory: { store }, quotaLoader: { QuotaSnapshot(quota: nil, diagnostic: "fixture") }, projectLoader: { [] })
        await model.open()
        #expect(model.events.count == 100)
        let all = try await model.observations(from: start, to: start.addingTimeInterval(1))
        #expect(all.isComplete && all.events.count == 1201)
        let limited = try await model.observations(from: start, to: start.addingTimeInterval(1), limit: 50)
        #expect(!limited.isComplete && limited.events.count == 50)
        try await model.shutdown()
    }
    @Test func pausePreservesSelectionAndRejectsOldOCRCallbacks() async throws {
        let store = try EventStore(path: ":memory:"), capture = FixtureOCR()
        let model = WorkspaceModel(storeFactory: { store }, ocrCapture: capture, quotaLoader: { QuotaSnapshot(quota: nil, diagnostic: "fixture") }, projectLoader: { [] })
        await model.open(); model.toggle(.screenOCR, enabled: true)
        capture.emit(0)
        model.pauseAll()
        #expect(model.selectedFeatures.contains(.screenOCR) && !model.enabled.contains(.screenOCR))
        capture.emit(0)
        model.resumeAll()
        try #require(model.enabled.contains(.screenOCR))
        try #require(capture.callbacks.count == 2)
        capture.emit(0) // previous session stays invalid after resume
        capture.emit(1)
        model.setSuspended(true, reason: "lock")
        capture.emit(1)
        model.toggle(.screenOCR, enabled: false)
        model.setSuspended(false, reason: "lock")
        #expect(!model.enabled.contains(.screenOCR) && !model.selectedFeatures.contains(.screenOCR))
        await model.retryPendingWrites()
        #expect(try await store.count() == 2)
        try await model.shutdown()
    }
    @Test func turboSweepOnlyScansAndNeverDeletes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = root.appendingPathComponent("project"), cache = project.appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{}".utf8).write(to: project.appendingPathComponent("package.json"))
        try Data(repeating: 1, count: 1_100_000).write(to: cache.appendingPathComponent("payload"))
        let store = try EventStore(path: ":memory:")
        let model = WorkspaceModel(storeFactory: { store }, cleanupService: DeveloperProjectTrimmer(), quotaLoader: { QuotaSnapshot(quota: nil, diagnostic: "fixture") }, projectLoader: { [] })
        await model.open()
        await model.scanCleanup(roots: [root.path])?.value
        #expect(model.cleanupScan.candidates.count == 1)
        // The public sweep can refresh candidates but cannot call trim, regardless of scan results.
        await model.runMasterTurboSweep()?.value
        #expect(FileManager.default.fileExists(atPath: cache.path))
        #expect(model.cleanupOutcomes.isEmpty)
        try await model.shutdown()
    }
}

@MainActor struct CapabilityPersistenceTests {
    @Test func readingPreferencesNeverOverwritesSavedSelectionOnRepeatedLaunches() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for iteration in 0..<3 {
            let history = try EventStore(path: ":memory:")
            let model = WorkspaceModel(directory: directory,storeFactory: { history },quotaLoader: { QuotaSnapshot(quota: nil,diagnostic: "fixture") },projectLoader: { [] },persistCapabilities: true)
            await model.open()
            if iteration == 0 { model.toggle(.screenpipe,enabled: true); model.completeSetup() }
            #expect(model.selectedFeatures.contains(.screenpipe))
            #expect(model.enabled.contains(.screenpipe))
            try await model.shutdown()
            let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("capabilities.json"))) as? [String:Any]
            #expect((saved?["selected"] as? [String]) == ["screenpipe"])
        }
    }
    @Test func privacyBlockedOCRRetriesWithoutClaimingCaptureOrDisablingSelection() async {
        let service = ScreenOCRService(sample: { throw CapturePrivacyBlocked("Excluded source") },interval: .milliseconds(2))
        var state: OCRCaptureState = .stopped
        await withCheckedContinuation { continuation in
            var signalled = false
            service.start(onState: {
                state = $0
                if state == .blocked("Excluded source") && !signalled { signalled = true; continuation.resume() }
            },onEvent: { _ in Issue.record("No event expected during privacy block") })
        }
        #expect(state == .blocked("Excluded source"))
        service.stop()
    }
}

@MainActor struct TranscriptDurabilityTests {
    @Test func shutdownRetainsFailedTranscriptAndRetriesBeforeClosing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = AutomaticServices(), history = try EventStore(path: ":memory:")
        try await service.open(history: history,directory: root,repository: root)
        var connection: OpaquePointer?
        try #require(sqlite3_open(root.appendingPathComponent("intelligence.sqlite").path,&connection) == SQLITE_OK)
        defer { sqlite3_close(connection) }
        sqlite3_busy_timeout(connection,1500)
        try #require(sqlite3_exec(connection,"CREATE TRIGGER reject_transcript BEFORE INSERT ON records WHEN new.namespace='transcripts' BEGIN SELECT RAISE(ABORT,'fixture write failure'); END",nil,nil,nil) == SQLITE_OK)
        service.recordTranscript(MeetingTranscriptRecord(meetingTitle: "Fixture",fullTranscript: "Observed fixture transcript"))
        await #expect(throws: StoreError.self) { try await service.stop() }
        #expect(service.transcriptWriteDiagnostic.contains("retained"))
        try #require(sqlite3_exec(connection,"DROP TRIGGER reject_transcript",nil,nil,nil) == SQLITE_OK)
        try await service.stop()
        let store = try IntelligenceStore(path: root.appendingPathComponent("intelligence.sqlite").path)
        #expect(try await store.list(MeetingTranscriptRecord.self,namespace: "transcripts").count == 1)
    }
}
