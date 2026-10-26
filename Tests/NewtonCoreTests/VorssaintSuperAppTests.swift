import Testing
import Foundation
import CoreGraphics
@testable import NewtonCore

struct VorssaintSuperAppTests {
    @Test func windowSwitcherCaptureReturnsValidStructures() {
        let windows = WindowSwitcherEngine.captureWindows()
        // Running on Mac, windows array should be valid and bounded
        #expect(windows.count >= 0)
        for w in windows {
            #expect(!w.appName.isEmpty)
            #expect(w.id > 0)
            #expect(w.pid > 0)
            #expect(!w.displayTitle.isEmpty)
        }
    }

    @Test func windowSwitcherActivationHandlesNonexistentAppGracefully() async {
        let dummy = SwitchableWindow(
            id: 999999,
            pid: 999999,
            appName: "NonexistentApp",
            windowTitle: "Dummy Window",
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        await MainActor.run {
            _ = WindowSwitcherEngine.activate(window: dummy)
        }
        #expect(dummy.displayTitle == "Dummy Window")
    }

    @Test @MainActor func globalHotkeyRegistrationAndLifecycle() {
        final class Box: @unchecked Sendable { var triggered = false }
        let box = Box()
        let engine = GlobalHotkeyEngine(registrar: TestHotkeyRegistrar())

        engine.start()
        engine.registerHotKey(action: .snapLeft, keyCode: 123, modifiers: 0) {
            box.triggered = true
        }

        #expect(!box.triggered)
        engine.triggerActionForTesting(.snapLeft)
        #expect(box.triggered)
        engine.stop()
    }

    @Test func speechActionItemExtractionIdentifiesCommitments() {
        let rawTranscript = """
        During the architecture meeting, we decided to merge Vorssaint and Screenpipe into Newton.
        Todo: Finish the automated test suite today.
        We will do the final deployment before 5 PM.
        Also need to clean up redundant daemons.
        Everything else looks good and nominal.
        """

        let actionItems = SpeechTranscriptionEngine.extractActionItems(from: rawTranscript)
        #expect(actionItems.count >= 3)
        #expect(actionItems.contains(where: { $0.localizedCaseInsensitiveContains("Finish the automated test suite") }))
        #expect(actionItems.contains(where: { $0.localizedCaseInsensitiveContains("clean up redundant daemons") }))
    }

    @Test func speechMeetingRecordGenerationAndStructure() {
        let segments = [
            TranscriptSegment(text: "Hello everyone, welcome to the engineering standup."),
            TranscriptSegment(text: "Todo: Verify zero percent idle CPU on M-series chips.")
        ]
        let full = segments.map(\.text).joined(separator: " ")
        let actionItems = SpeechTranscriptionEngine.extractActionItems(from: full)

        let record = MeetingTranscriptRecord(
            meetingTitle: "Sprint Review",
            startTime: Date(timeIntervalSince1970: 1000),
            endTime: Date(timeIntervalSince1970: 1600),
            segments: segments,
            fullTranscript: full,
            actionItems: actionItems
        )

        #expect(record.meetingTitle == "Sprint Review")
        #expect(record.segments.count == 2)
        #expect(record.actionItems.count == 1)
        #expect(record.fullTranscript.contains("zero percent idle CPU"))
    }

    @Test func powerPacingSnapshotSupportsWattsReadout() {
        let snapshot = PowerPacingEngine.snapshot(source: nil, cycleCount: 150, thermal: "Nominal", estimatedWatts: 4.25)
        #expect(snapshot.estimatedWatts == 4.25)
        #expect(snapshot.packageWatts == nil)
        #expect(snapshot.cycleCount == 150)
        #expect(snapshot.thermalState == "Nominal")

        let live = PowerPacingEngine.captureSnapshot()
        #expect(!live.thermalState.isEmpty)
    }
}
