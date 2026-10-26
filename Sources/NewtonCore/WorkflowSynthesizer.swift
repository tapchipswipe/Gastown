import Foundation

public struct WorkflowStep: Sendable, Equatable, Identifiable {
    public let id: String
    public let stepNumber: Int
    public let title: String
    public let targetApp: String
    public let actionDescription: String
    public let codeSnippet: String

    public init(id: String = UUID().uuidString,
                stepNumber: Int,
                title: String,
                targetApp: String,
                actionDescription: String,
                codeSnippet: String) {
        self.id = id
        self.stepNumber = stepNumber
        self.title = title
        self.targetApp = targetApp
        self.actionDescription = actionDescription
        self.codeSnippet = codeSnippet
    }
}

public struct WorkflowSynthesizer: Sendable {
    static func literal(_ text: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
    static func appleLiteral(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    public static func distillSteps(from session: WorkflowSession) -> [WorkflowStep] {
        var steps: [WorkflowStep] = [], app = "", pending = ""
        func add(_ title: String, _ code: String) {
            steps.append(WorkflowStep(stepNumber: steps.count + 1, title: title, targetApp: app, actionDescription: title, codeSnippet: code))
        }
        func flush() {
            guard !pending.isEmpty else { return }
            let text = pending; pending = ""
            steps.append(WorkflowStep(stepNumber: steps.count + 1, title: "Type Text into \(app)", targetApp: app, actionDescription: "Enter string: \(text)", codeSnippet: "type_text(\(literal(text)))"))
        }
        for action in session.actions {
            if !action.appName.isEmpty && action.appName != app {
                flush(); app = action.appName
                // Reject multiline AppleScript app identifiers rather than constructing ambiguous programs.
                let code = app.contains("\n") || app.contains("\r") ? "raise RuntimeError(\(literal("Unsupported action: multiline app name")))" :
                    "subprocess.run(['osascript', '-e', \(literal("tell application " + appleLiteral(app) + " to activate"))], check=True)"
                add("Focus \(app)", code)
            }
            switch action.type {
            case .textInput: pending += action.details
            case .keypress:
                flush(); add("Unsupported keypress", "raise RuntimeError(\(literal("Unsupported action: keypress " + action.details)))")
            case .appSwitch: flush()
            case .click, .rightClick, .doubleClick:
                flush()
                guard let x = action.coordinateX, let y = action.coordinateY, x.isFinite, y.isFinite else {
                    add("Unsupported click", "raise RuntimeError('Unsupported action: missing or invalid Quartz coordinates')"); continue
                }
                let button = action.type == .rightClick ? "kCGMouseButtonRight" : "kCGMouseButtonLeft"
                let count = action.type == .doubleClick ? 2 : 1
                add("\(action.type == .click ? "Click" : action.type.rawValue) at (\(x), \(y))", "click(\(x), \(y), Quartz.\(button), click_count=\(count))")
            }
        }
        flush(); return steps
    }
    public static func generateSOP(for session: WorkflowSession) -> String {
        var lines = ["# Standard Operating Procedure: \(session.title)", "Experimental replay; inspect before running.", "Recorded: \(session.startedAt)"]
        for step in distillSteps(from: session) { lines += ["### Step \(step.stepNumber): \(step.title)", "- \(step.actionDescription)"] }
        return lines.joined(separator: "\n\n")
    }
    public static func generatePythonScript(for session: WorkflowSession) -> String {
        var lines = ["#!/usr/bin/env python3", "# Experimental Newton replay. Requires PyObjC Quartz and explicit user permissions.", "import subprocess", "import time", "import Quartz", "", "def click(x, y, button, click_count=1):", "    right = button == Quartz.kCGMouseButtonRight", "    down = Quartz.kCGEventRightMouseDown if right else Quartz.kCGEventLeftMouseDown", "    up = Quartz.kCGEventRightMouseUp if right else Quartz.kCGEventLeftMouseUp", "    for count in range(1, click_count + 1):", "        for kind in (down, up):", "            event = Quartz.CGEventCreateMouseEvent(None, kind, (x, y), button)", "            Quartz.CGEventSetIntegerValueField(event, Quartz.kCGMouseEventClickState, count)", "            Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)", "", "def type_text(text):", "    for down in (True, False):", "        event = Quartz.CGEventCreateKeyboardEvent(None, 0, down)", "        Quartz.CGEventKeyboardSetUnicodeString(event, len(text.encode('utf-16-le')) // 2, text)", "        Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)", "", "def run_workflow():", "    print(\(literal("Experimental workflow: " + session.title)))"]
        for step in distillSteps(from: session) {
            lines.append("    print(\(literal(step.title)))")
            lines += step.codeSnippet.components(separatedBy: "\n").map { "    " + $0 }
            lines.append("    time.sleep(0.5)")
        }
        lines += ["", "if __name__ == '__main__':", "    run_workflow()", ""]
        return lines.joined(separator: "\n")
    }
}

public enum WorkflowExporter {
    /// Both files are staged on the destination volume and published as one UUID directory.
    public static func save(_ session: WorkflowSession, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let staging = directory.appendingPathComponent(".staging-" + id)
        let destination = directory.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        try generatePython(session).write(to: staging.appendingPathComponent("replay.py"), atomically: true, encoding: .utf8)
        try WorkflowSynthesizer.generateSOP(for: session).write(to: staging.appendingPathComponent("SOP.md"), atomically: true, encoding: .utf8)
        try FileManager.default.moveItem(at: staging, to: destination)
        return destination
    }
    private static func generatePython(_ session: WorkflowSession) -> String { WorkflowSynthesizer.generatePythonScript(for: session) }
}
