# Synthetic review evidence — October 24, 2026

Code tested: `c1047757a2d25bfd75a5417669ab250b360c6fa2`. See [assessment and scope](2026-10-24-gemini-review.md). All data below is synthetic. These are independent probes, not additions to the passing production suite.

## Results

```json
{
  "idea_original_overwritten": true,
  "idea_same_path": true,
  "journal_without_uuid_unstable_id": true,
  "long_prompt_drops_execution_instructions": true,
  "missing_repo_reported_as_project": true,
  "missing_repo_reported_clean_main": true,
  "recorder_still_running_after_shutdown": true,
  "recording_change_observation_notified": false,
  "recording_state_true": true,
  "right_click_uses_left_click_code": true,
  "generated_python": {
    "click": {
      "syntax_valid": false,
      "error": "unexpected indent",
      "line": 22
    },
    "apostrophe": {
      "syntax_valid": false,
      "error": "invalid syntax",
      "line": 20
    },
    "quoted_title": {
      "syntax_valid": false,
      "error": "invalid syntax",
      "line": 12
    }
  },
  "malformed_protobuf": {
    "exit_code": -5,
    "crashed": true,
    "first_error_line": "Swift/arm64e-apple-macos.swiftinterface:13309: Fatal error: Not enough bits to represent the passed value"
  },
  "git_pipe_probe": {
    "timed_out": true,
    "seconds": 4,
    "fixture_files": 3000,
    "cleanup": "owned probe process group terminated"
  }
}
```

`true` denotes an observed defect for the defect-named fields. The generated Python was only syntax-parsed. No automation replay or agent execution occurred.

## Compiled probe source

Compile after `./test.sh` with the selected SDK, module objects and system SQLite:

```sh
source bin/toolchain.sh
swiftc -swift-version 6 -sdk "$newton_sdk" -parse-as-library \
  -I .build/out/Products/Debug -I Sources/CSQLite \
  /tmp/newton-gemini-review/Probe.swift \
  .build/out/Products/Debug/NewtonWorkspace.o \
  .build/out/Products/Debug/NewtonCore.o \
  -lsqlite3 -o /tmp/newton-gemini-review/probe
```

Create a fresh disposable fixture directory before passing its absolute path as the normal probe's first argument. The model is never opened, avoiding live startup readers. Shutdown is tested using an injected recorder.

```swift
import Foundation
import Observation
import os
import NewtonCore
import NewtonWorkspace

@MainActor final class FixtureRecorder: WorkflowRecording {
    var isRecording = false
    var stops = 0
    func start(sessionTitle: String) { isRecording = true }
    func stop() -> WorkflowSession? { isRecording = false; stops += 1; return nil }
}
@main struct Probe {
    @MainActor static func main() async throws {
        if CommandLine.arguments[1] == "repo-pipe-hang" {
            _ = ProjectAtlasScanner.inspectRepo(at:URL(fileURLWithPath:CommandLine.arguments[2]))
            return
        }
        if CommandLine.arguments.contains("protobuf-overflow") {
            _ = ProtoWireDecoder.decodeFields(from: Data([0x0a] + Array(repeating: 0xff, count: 9) + [0x01]))
            return
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let ideas = root.appendingPathComponent("ideas")
        let first = try iCloudIdeaStore.saveIdea(title: "Same Idea", detail: "first content", in: ideas)
        let second = try iCloudIdeaStore.saveIdea(title: "same idea", detail: "replacement content", in: ideas)
        var facts: [String: Any] = ["idea_same_path":first == second,
            "idea_original_overwritten":try String(contentsOf:first,encoding:.utf8).contains("replacement content")]
        let click = CapturedAction(type:.click,appName:"Fixture",coordinateX:10,coordinateY:20)
        let right = CapturedAction(type:.rightClick,appName:"Fixture",coordinateX:10,coordinateY:20)
        facts["right_click_uses_left_click_code"] = WorkflowSynthesizer.distillSteps(from:WorkflowSession(title:"Left",actions:[click])).last?.codeSnippet == WorkflowSynthesizer.distillSteps(from:WorkflowSession(title:"Right",actions:[right])).last?.codeSnippet
        let fixtures = ["click":WorkflowSession(title:"Click",actions:[click]),
                        "apostrophe":WorkflowSession(title:"Text",actions:[CapturedAction(type:.textInput,appName:"Fixture",details:"don't")]),
                        "quoted_title":WorkflowSession(title:"A \"quoted\" title",actions:[])]
        for (name,session) in fixtures {
            try WorkflowSynthesizer.generatePythonScript(for:session).write(to:root.appendingPathComponent(name+".py"),atomically:true,encoding:.utf8)
        }
        let missing = ProjectAtlasScanner.inspectRepo(at:root.appendingPathComponent("does-not-exist"))
        facts["missing_repo_reported_as_project"] = missing != nil
        facts["missing_repo_reported_clean_main"] = missing?.isDirty == false && missing?.activeBranch == "main"
        let text = Data("journal without UUID".utf8)
        let body = Data([0x22,UInt8(text.count)]) + text
        let journal = Data([0x12,UInt8(body.count)]) + body
        let a = TimeAtlasReader.parseData(journal,fallbackDate:Date(timeIntervalSince1970:100))
        let b = TimeAtlasReader.parseData(journal,fallbackDate:Date(timeIntervalSince1970:100))
        facts["journal_without_uuid_unstable_id"] = a.first?.id != b.first?.id
        let longPrompt = PromptGenerator.generatePrompt(for:PromptTask(title:"fixture",objective:String(repeating:"X",count:20_000)))
        facts["long_prompt_drops_execution_instructions"] = !longPrompt.contains("## Execution Instructions")
        let recorder=FixtureRecorder()
        let model=WorkspaceModel(directory:root,workflowRecorder:recorder)
        let notified=OSAllocatedUnfairLock(initialState:false)
        withObservationTracking { _=model.isRecordingWorkflow } onChange: { notified.withLock { $0=true } }
        model.startWorkflowRecording(title:"fixture")
        facts["recording_state_true"] = model.isRecordingWorkflow
        facts["recording_change_observation_notified"] = notified.withLock { $0 }
        try await model.shutdown()
        facts["recorder_still_running_after_shutdown"] = recorder.isRecording
        print(String(decoding:try JSONSerialization.data(withJSONObject:facts,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
    }
}
```

## Python syntax and crash checks

For each of `click.py`, `apostrophe.py`, `quoted_title.py` emitted into the disposable fixture directory, parse `ast.parse(path.read_text())`; record SyntaxError message and line. Never execute the generated scripts.

For crash reproduction, run the probe with argument `protobuf-overflow` in a separate subprocess with core dumps disabled (`resource.setrlimit(resource.RLIMIT_CORE, (0, 0))`), capturing stderr. It returns -5/SIGTRAP; first diagnostic is preserved above. This is not an app launch or a real iCloud file.

## Git pipe fixture

Use a fresh temporary directory and environment `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`. Run `/usr/bin/git init` there. Create 3,000 empty, untracked files with long unique names (for example `f"{index:04d}-" + "x"*120`). Launch `probe repo-pipe-hang <repo>` using Python `subprocess.Popen(..., start_new_session=True)`, capturing output. `communicate(timeout=4)` times out. Terminate only that owned subprocess group with `os.killpg(child.pid, signal.SIGKILL)`, then `communicate()` to reap. Do not kill unrelated Git or app processes.

This demonstrates pipe backpressure deadlock, not a four-second production performance target. Process creation failure/default status and Observation/lifecycle defects are separately demonstrated by the normal fixture probe.
