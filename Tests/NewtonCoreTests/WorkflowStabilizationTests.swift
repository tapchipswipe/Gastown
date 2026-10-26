import Foundation
import Testing
@testable import NewtonCore

struct WorkflowStabilizationTests {
    @Test func generatedPythonParsesWithoutReplaying() async throws {
        let title = "Quotes '\"\\\n雪" + "\"\"\""
        var actions = [CapturedAction(type: .appSwitch, appName: title), CapturedAction(type: .textInput, appName: title, details: "it's \\\n雪")]
        for kind: ActionType in [.click, .rightClick, .doubleClick, .keypress] {
            actions.append(CapturedAction(type: kind, appName: title, coordinateX: -100, coordinateY: 200, details: "unsupported"))
        }
        let script = WorkflowSynthesizer.generatePythonScript(for: WorkflowSession(title: title, actions: actions))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".py")
        defer { try? FileManager.default.removeItem(at: url) }
        try script.write(to: url, atomically: true, encoding: .utf8)
        let result = try await ProcessRunner().run("/usr/bin/python3", ["-c", "import ast,sys; ast.parse(open(sys.argv[1]).read())", url.path], directory: url.deletingLastPathComponent())
        #expect(result.exitCode == 0)
        #expect(script.contains("kCGMouseButtonRight")); #expect(script.contains("click_count=2"))
        #expect(script.contains("Unsupported action"))
    }
}

struct WorkflowBudgetTests {
    @Test func actionAndDurationLimitsRetainSessionAndDoubleClicksReplaceSingle() {
        let now = Date()
        var buffer = WorkflowCaptureBuffer(title: "fixture", startedAt: now, maximumActions: 2, maximumSeconds: 10)
        let accepted1 = buffer.append(CapturedAction(timestamp: now, type: .click, appName: "Fixture", coordinateX: 1, coordinateY: 2), now: now)
        #expect(accepted1)
        let accepted2 = buffer.append(CapturedAction(timestamp: now, type: .doubleClick, appName: "Fixture", coordinateX: 1, coordinateY: 2), now: now)
        #expect(accepted2)
        #expect(buffer.session.actions.count == 1)
        let accepted3 = !buffer.append(CapturedAction(type: .appSwitch, appName: "Fixture"), now: now)
        #expect(accepted3)
        let accepted4 = !buffer.append(CapturedAction(type: .appSwitch, appName: "Fixture"), now: now)
        #expect(accepted4)
        #expect(buffer.session.actions.count == 2)
        var expired = WorkflowCaptureBuffer(title: "fixture", startedAt: now)
        let accepted5 = !expired.append(CapturedAction(type: .click, appName: "Fixture"), now: now.addingTimeInterval(3600))
        #expect(accepted5)
        #expect(expired.session.actions.isEmpty)
    }
    @Test func exportPublishesBothFilesUnderSafeUUIDAndReportsFailure() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let session = WorkflowSession(title: "../../a/b\n雪")
        let bundle = try WorkflowExporter.save(session, in: dir)
        #expect(UUID(uuidString: bundle.lastPathComponent) != nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: bundle.path).sorted() == ["SOP.md", "replay.py"])
        #expect(throws: (any Error).self) { try WorkflowExporter.save(session, in: bundle.appendingPathComponent("SOP.md")) }
    }
}
