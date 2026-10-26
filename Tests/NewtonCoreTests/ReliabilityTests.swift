import Testing
import Foundation
import Carbon.HIToolbox
import CoreGraphics
@testable import NewtonCore

@MainActor final class TestHotkeyRegistrar: HotkeyRegistering {
    var installationResult: OSStatus = noErr
    var registrationResult: OSStatus = noErr
    var installed = 0
    var registrations: [UInt32] = []
    var stopped = 0
    var dispatch: (@MainActor (UInt32) -> Void)?
    func install(dispatch: @escaping @MainActor (UInt32) -> Void) -> OSStatus {
        installed += 1; self.dispatch = dispatch; return installationResult
    }
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> OSStatus {
        registrations.append(id); return registrationResult
    }
    func unregister(id: UInt32) {}
    func stop() { stopped += 1; dispatch = nil }
}

@Suite struct ReliabilityTests {
    @Test @MainActor func startupRegistersAllDefaultsAndSurfacesFailures() {
        let registrar = TestHotkeyRegistrar()
        let engine = GlobalHotkeyEngine(registrar: registrar)
        engine.start(); engine.start()
        #expect(registrar.installed == 1)
        #expect(Set(registrar.registrations).count == 10)
        registrar.registrationResult = OSStatus(eventHotKeyExistsErr)
        engine.registerHotKey(action: .snapLeft, keyCode: 123, modifiers: 0) { Issue.record("A failed shortcut must not dispatch") }
        #expect(engine.failures[101] == OSStatus(eventHotKeyExistsErr))
        engine.triggerActionForTesting(.snapLeft)
        engine.stop()
        registrar.installationResult = -1
        engine.start()
        #expect(engine.installationStatus == -1)
        #expect(registrar.registrations.count == 11)
    }
    @Test func missingFinanceInputsRemainUnavailable() {
        let summary = FinancialRunwayEngine.computeSummary(subscriptions: [], deductions: [])
        #expect(summary.projectedAnnualRunway == nil)
        #expect(summary.estimatedTaxSavings == nil)
    }
}

@Suite struct ObservationReliabilityTests {
    final class Uptime: @unchecked Sendable {
        private let lock = NSLock()
        private var time: TimeInterval = 0
        func get() -> TimeInterval { lock.withLock { time } }
        func set(_ value: TimeInterval) { lock.withLock { time = value } }
    }
    func image(markY: Int? = nil) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 2400, height: 1600, bitsPerComponent: 8, bytesPerRow: 2400 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1600))
        if let markY { context.setFillColor(CGColor(gray: 0, alpha: 1)); context.fill(CGRect(x: 1100, y: markY, width: 200, height: 80)) }
        return try #require(context.makeImage())
    }
    @Test func digestSeesCenterAndBottomAndBoundsDuplicateSuppression() async throws {
        let baseline = try image(), center = try image(markY: 800), bottom = try image(markY: 30)
        let clock = Uptime()
        let engine = VisionCaptureEngine(recognizer: VisionCaptureTests.MockRecognizer(), frameProvider: VisionCaptureTests.MockFrameProvider(image: baseline), uptime: { clock.get() })
        let hash = await engine.computeFrameDigest(for: baseline)
        #expect(hash != nil)
        #expect(await engine.computeFrameDigest(for: center) != hash)
        #expect(await engine.computeFrameDigest(for: bottom) != hash)
        #expect(try await engine.captureFrame() != nil)
        clock.set(59)
        #expect(try await engine.captureFrame() == nil)
        clock.set(60)
        #expect(try await engine.captureFrame() != nil)
        #expect(await engine.skippedDuplicateFramesCount == 1)
    }
    @Test func rangeSearchPagesAllTiedIDsAndRejectsForeignCursors() async throws {
        let store = try EventStore(path: ":memory:")
        let start = Date(timeIntervalSince1970: 1_700_000_000), end = start.addingTimeInterval(86400)
        try await store.append((0..<1201).map { HistoryEvent(id: String(format: "%04d", $0), timestamp: start, source: "fixture", title: "needle \($0)") })
        var cursor: RangeHistoryCursor?, ids: [String] = []
        repeat {
            let page = try await store.rangePage(from: start, to: end, query: "needle", after: cursor, limit: 100)
            #expect(page.coverage.continuity.contains("unknown"))
            ids += page.events.map(\.id); cursor = page.nextCursor
        } while cursor != nil
        #expect(ids.count == 1201 && Set(ids).count == 1201)
        #expect(ids == ids.sorted())
        let page = try await store.rangePage(from: start, to: end, limit: 10)
        #expect(page.isTruncated)
        await #expect(throws: StoreError.self) { try await store.rangePage(from: start, to: end.addingTimeInterval(1), after: page.nextCursor) }
        #expect(try await store.rangePage(from: end, to: end.addingTimeInterval(1)).events.isEmpty)
    }
    @Test func emptyReportsNeverInventWorkOrMeetings() {
        let standup = PipeAutomationEngine.synthesizeStandup(events: [], projects: [])
        #expect(standup.yesterday == ["Insufficient evidence"])
        #expect(standup.blockers == ["Insufficient evidence"])
        let todos = PipeAutomationEngine.synthesizeMissedToDos(events: [])
        #expect(todos.quickWins.isEmpty && !todos.fullMarkdown.contains("in sync"))
        let digest = PipeAutomationEngine.synthesizeMeetingDigest(title: "No evidence", notes: "")
        #expect(digest.decisions.isEmpty && digest.actionItems.isEmpty && digest.summary == "Insufficient evidence")
        let event = HistoryEvent(id: "observed-1", source: "fixture", title: "TODO: verify build")
        let report = PipeAutomationEngine.synthesizeMissedToDos(events: [event])
        #expect(report.fullMarkdown.contains("[observation](#observation-"))
        #expect(report.fullMarkdown.contains("**observed-1**"))
    }
    @Test func speechReplacesPartialHypothesesAndRequiresLocalSupport() throws {
        var accumulator = TranscriptAccumulator()
        accumulator.update("We need", isFinal: false)
        let id = accumulator.segments.first?.id
        accumulator.update("We need to verify", isFinal: false)
        accumulator.update("We need to verify the build.", isFinal: true)
        #expect(accumulator.segments.count == 1)
        #expect(accumulator.segments.first?.id == id)
        #expect(accumulator.segments.first?.isFinal == true)
        #expect(accumulator.segments.first?.text == "We need to verify the build.")
        #expect(throws: StoreError.self) { try SpeechTranscriptionEngine.requireLocalSupport(authorized: true, available: true, onDevice: false) }
        #expect(throws: StoreError.self) { try SpeechTranscriptionEngine.requireLocalSupport(authorized: false, available: true, onDevice: true) }
    }
    @Test func keyboardHoldCancellationRepeatAndSyntheticBypass() {
        var policy = KeyboardPolicy()
        func press(_ policy: inout KeyboardPolicy, down: Bool = true, repeatKey: Bool = false, bundle: String = "editor", synthetic: Bool = false) -> KeyboardPolicy.Result {
            policy.handle(key: 12, down: down, command: true, repeatKey: repeatKey, synthetic: synthetic, bundle: bundle, protected: true, now: 10, duration: 0.8)
        }
        #expect(press(&policy) == .holdStarted)
        #expect(press(&policy, repeatKey: true) == .swallow)
        #expect(policy.complete(now: 10.7, bundle: "editor") == nil)
        #expect(press(&policy, down: false) == .holdCancelled)
        #expect(policy.complete(now: 11, bundle: "editor") == nil)
        #expect(press(&policy) == .holdStarted)
        #expect(policy.complete(now: 11, bundle: "editor") == 12)
        #expect(policy.complete(now: 12, bundle: "editor") == nil)
        #expect(press(&policy, synthetic: true) == .pass)
        _ = press(&policy, down: false)
        _ = press(&policy)
        #expect(policy.complete(now: 11, bundle: "other") == nil)
        policy.cancel()
        #expect(policy.complete(now: 11, bundle: "editor") == nil)
    }
    @Test func cleaningTakesPrecedenceAndRequiresDistinctEscapePresses() {
        var policy = KeyboardPolicy(); policy.cleaning = true
        for _ in 0..<10 {
            #expect(policy.handle(key: 53, down: true, command: false, repeatKey: true, synthetic: false, bundle: nil, protected: false, now: 0, duration: 1) == .swallow)
        }
        #expect(policy.escapePresses == 0)
        for index in 1...5 {
            let result = policy.handle(key: 53, down: true, command: false, repeatKey: false, synthetic: false, bundle: nil, protected: false, now: 0, duration: 1)
            #expect(result == (index == 5 ? .unlock : .swallow))
            _ = policy.handle(key: 53, down: false, command: false, repeatKey: false, synthetic: false, bundle: nil, protected: false, now: 0, duration: 1)
        }
        #expect(!policy.cleaning)
    }
}

@Suite struct RepositoryDiscoveryReliabilityTests {
    @Test func recursiveDiscoveryPrunesDependencyTreesAndIncludesRootRepos() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("team/tools/project")
        let dependency = root.appendingPathComponent("node_modules/vendor")
        for url in [nested, dependency] {
            try FileManager.default.createDirectory(at: url.appendingPathComponent(".git"), withIntermediateDirectories: true)
        }
        let found = await ProjectAtlasScanner.scanProjects(in: [root])
        #expect(found.count == 1)
        #expect(found.first?.path.hasSuffix("/team/tools/project") == true)
        let direct = await ProjectAtlasScanner.scanProjects(in: [nested])
        #expect(direct.map(\.path) == [nested.path])
    }
}
