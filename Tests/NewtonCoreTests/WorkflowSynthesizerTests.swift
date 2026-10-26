import Testing
import Foundation
@testable import NewtonCore

struct WorkflowSynthesizerTests {

    @Test func testDistillStepsCoalescesTextAndTracksAppFocus() {
        let actions = [
            CapturedAction(type: .appSwitch, appName: "Terminal", windowTitle: "zsh"),
            CapturedAction(type: .textInput, appName: "Terminal", details: "npm "),
            CapturedAction(type: .textInput, appName: "Terminal", details: "run dev"),
            
            CapturedAction(type: .appSwitch, appName: "Safari", windowTitle: "Localhost"),
            CapturedAction(type: .click, appName: "Safari", coordinateX: 120, coordinateY: 240, details: "Submit button")
        ]

        let session = WorkflowSession(title: "Dev Server & Browser Test", actions: actions)
        let steps = WorkflowSynthesizer.distillSteps(from: session)

        #expect(steps.count == 4)
        #expect(steps[0].title == "Focus Terminal")
        #expect(steps[1].title.contains("Type Text into Terminal"))
        #expect(steps[1].actionDescription.contains("npm run dev"))
        #expect(steps[2].title == "Focus Safari")
        #expect(steps[3].title.contains("Click at (120.0, 240.0)"))
    }

    @Test func testGenerateSOPContainsStepsAndMetadata() {
        let actions = [
            CapturedAction(type: .appSwitch, appName: "Xcode", windowTitle: "Newton"),
            CapturedAction(type: .click, appName: "Xcode", coordinateX: 50, coordinateY: 50, details: "Run button")
        ]

        let session = WorkflowSession(title: "Build Newton in Xcode", actions: actions)
        let sop = WorkflowSynthesizer.generateSOP(for: session)

        #expect(sop.contains("# Standard Operating Procedure: Build Newton in Xcode"))
        #expect(sop.contains("### Step 1: Focus Xcode"))
        #expect(sop.contains("### Step 2: Click at (50.0, 50.0)"))
    }

    @Test func testGeneratePythonScriptIsValidExecutable() {
        let actions = [
            CapturedAction(type: .appSwitch, appName: "Notes", windowTitle: "Ideas"),
            CapturedAction(type: .textInput, appName: "Notes", details: "New idea note")
        ]

        let session = WorkflowSession(title: "Create Note", actions: actions)
        let script = WorkflowSynthesizer.generatePythonScript(for: session)

        #expect(script.contains("#!/usr/bin/env python3"))
        #expect(script.contains("def run_workflow():"))
        // Escaping and Python syntax are verified by generatedPythonParsesWithoutReplaying.
        #expect(script.contains("subprocess.run"))
        #expect(script.contains("type_text"))
    }
}
