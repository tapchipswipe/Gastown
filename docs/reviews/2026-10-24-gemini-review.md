# Newton v0.1.2 — independent review of Gemini changes

Reviewed October 24, 2026. Code under review: `c1047757a2d25bfd75a5417669ab250b360c6fa2` (release 0.1.2), including feature commit `98f139e`, against the previous documented baseline `725439e`. Scope: 23 changed files, 2,161 additions and 9 deletions. This review preserves Gemini's application implementation; it corrects project context and records defects, rather than silently fixing or endorsing the release.

**Assessment: the existing history/storage/delivery foundation remains useful and builds successfully. The expanded AI, mobile-import and workflow features are experimental integration prototypes with confirmed data-loss, crash, hang and code-generation defects. Green tests do not establish readiness for unattended use.** No claim of zero defects, measured zero idle CPU, upstream feature parity or production autonomy is justified.

## Verification actually performed

- `./test.sh`: **61 Swift tests** (17 workspace + 44 core), plus **10 Python delivery tests**, all passed. Gemini added 13 Swift tests; the earlier baseline had 48. The release memory's “42 Swift tests” is incorrect.
- `./build.sh`: release compilation, staged packaging and signature checks succeeded. `python3 bin/artifact.py verify` passed. Version remains 0.1.2; build-input SHA256 is `eba50796eba7c07ab4591c599704eda39ce4a760b5901240cb3f529c1cfdd0a6`. This review rebuilt locally, not shipped or tagged again.
- [CI run 40131778224](https://github.com/tapchipswipe/newton/actions/runs/40131778224), attempt 2: macOS 15 and 26 both passed for `c104775`. Attempt 1 failed in macOS 15 runner setup when downloading an action from codeload.github.com (DNS failure), before checkout/tests. That failure was infrastructure, not evidence of a source regression; retrying the failed job resolved it.
- Disposable compiled Swift probes exercised current modules. Python output was parsed with `ast.parse`, never executed. A malformed-input child process crashed as described below. A pipe-deadlock probe was stopped after four seconds, and its owned process group was terminated/reaped. Fixtures and compiler logs were kept under `/tmp/newton-gemini-review`.
- No app launch, live workflow recording, automation replay, agent dispatch, autonomous script execution or live database mutation was performed. The existing suite ran as authored: workspace startup now invokes default readers of the real home quota/repository directories, even with fixture storage. Thus the suite is no longer fully hermetic; raw private session contents were neither printed nor copied into this report.
- [Reproduction source and synthetic results](2026-10-24-gemini-evidence.md) accompany this report. Runtime demonstrations are distinguished below from additional source-review risks.

## P1 — fix before relying on the additions

### 1. Saving an idea can overwrite an earlier idea

**Demonstrated.** `Sources/NewtonCore/iCloudIdeaStore.swift:79–91` derives a deterministic filename from the first six slug words and atomically writes over it. Saving “Same Idea” and “same idea” returns the same path and replaces the original content. Other slug collisions have the same problem. Content-hash import deduplication does not protect the original note from being overwritten before import.

Fix: collision-safe creation with a stable unique note identity; preserve both notes, including concurrent saves. Test repeated titles, case/punctuation collisions and concurrent writers.

### 2. Malformed protobuf causes a process trap

**Demonstrated.** `Sources/NewtonCore/TimeAtlasReader.swift:91` converts an untrusted UInt64 length to Int before validating its range. A length-delimited field containing UInt64.max traps with “Not enough bits to represent the passed value” (child exit -5/SIGTRAP). Validate conversion and remaining byte count without overflowing addition. Also bound file bytes, field counts and parser work, and reject truncated/invalid encodings. The mapped whole-file read does not itself impose a size limit.

The fixture tests encode the decoder's own schema assumptions; they do not establish compatibility with actual Time Atlas versions or real device timestamps.

### 3. Repository scanning can hang startup/the UI

**Demonstrated.** `Sources/NewtonCore/ProjectAtlasScanner.swift:100` waits for Git to exit before draining stdout. A disposable repository with 3,000 long untracked filenames blocks beyond four seconds when the pipe fills. There is no timeout despite the source comment claiming one. The log helper repeats the wait-before-read pattern; stderr is also piped without draining.

`Sources/NewtonWorkspace/WorkspaceModel.swift:106–107,293–298` invokes quota and project scans synchronously during main-actor startup. A hung Git process can therefore hang the app window. Quota discovery also traverses logs and reads whole files without byte/work bounds (`CodexQuotaReader.swift`). Fix with a shared cancellable process runner that drains both streams, caps output, handles exit status and enforces a deadline; move bounded scans off the main actor and inject them for tests.

### 4. Generated workflow programs are invalid for ordinary inputs

**Demonstrated.** `Sources/NewtonCore/WorkflowSynthesizer.swift` emits multiline click code but indents only its first line when inserting it into the generated function. A normal click fails Python parsing with unexpected indentation. Apostrophes in text and quotes in workflow titles also produce syntax errors because strings are interpolated without proper escaping. The test named `testGeneratePythonScriptIsValidExecutable` checks substrings, not Python syntax.

Right-click and left-click generate identical code (demonstrated); double-click also shares the implementation. Global screen coordinate conversion and multi-display replay correctness remain source-review concerns, not verified replay behavior. Use structured serialization/escaping, correct indentation and event semantics, and syntax-check every fixture. Permissioned real replay remains a separate integration gate.

## P2 — ownership, correctness and evidence gaps

| Finding | Evidence / impact | Required direction |
|---|---|---|
| Workflow state bypasses observation and shutdown | **Demonstrated:** tracking `isRecordingWorkflow` does not notify on start; fixture recorder is still running after `shutdown()`. Computed state reads an observation-ignored non-observable recorder (`WorkspaceModel.swift:32–35`); shutdown at line 427 only handles the original feature set. | Observable owned state, idempotent teardown, start/stop readiness guards and shutdown regression tests. |
| Workflow export reports success after failures | Source: `WorkspaceModel.swift:315–330` swallows directory, script, SOP and database errors with `try?`, then returns a path and reports “saved”. Filename handling only replaces spaces; titles can contain path separators. | Validate filenames, report actual errors and commit success only when required outputs are durable; preserve unsaved drafts. |
| Agent runs lack exclusive ownership | Source: `AgentDispatcher.swift:30–89`; dispatch suspends while streaming, allowing actor reentry and replacing `currentProcess`. Output grows without limit. Verification child is not tracked by cancel; launch error is swallowed before waiting. No timeout/process-group teardown. `WorkspaceModel.swift:335–358` hardcodes one repo path, has no active-run guard or owned task, and queues a UI Task per output line. Shutdown does not stop agents. | One owned run, worktree isolation for concurrent AI tools, bounded output/progress, cancellation through verification and shutdown, injectable executable/root, correct launch-error handling. No agent was run during review. |
| Quota policy is not enforced by execution | `canExecuteAutonomousJob` is declared in `AIScheduler.swift:45` but has no production caller. Neither UI dispatcher nor prompt CLI uses it. Missing quota is allowed at night; freshness and secondary limits are not established. | Define manual versus autonomous semantics, wire policy into autonomous execution, expose unknown/stale states and test policy at the dispatch boundary. |
| “Autonomous daemon” and “dual-AI engine” overstate implementation | `bin/autonomous_build.sh` gates by time, prints quota, counts notes and runs tests. It does not perform code builds/agent work or install a scheduling service. No Gemini quota/provider implementation is present. | Treat as helper/design intent until a separately tested execution and service lifecycle exists. Repository inspection does not determine whether an external scheduler was installed independently. |
| Quota display is a snapshot | Whole-file local log parser; observation time can default to read time; missing/expired/invalid values not robustly distinguished. UI reset labels do not establish a live countdown or live file observation. | Bounded incremental reading, source timestamp/freshness, unavailable states and measured refresh behavior. No provider account semantics were independently verified here. |
| Imports bypass previous operation guards | New idea/Time Atlas reads run synchronously on MainActor with no size/count limits; unlike the original Lumen worker, they are outside importBusy/deleteBusy/task ownership and shutdown draining (`WorkspaceModel.swift:361–404`). They are user-triggered, not automatic startup imports. | Reuse bounded, cancellable import ownership and deletion exclusion; test shutdown/deletion races and blocked cloud reads. |
| Duplicate journal imports | **Demonstrated:** Time Atlas journal without UUID gets a fresh UUID each parse (`TimeAtlasReader.swift:218`). File modification/read fallback dates are not evidence of actual event timestamps. | Deterministic source identity, explicit timestamp provenance and independent real-schema fixtures. |
| Project information can be fabricated by defaults | **Demonstrated:** inspecting a nonexistent path returns a “main”, clean project with current fallback date. `ProjectAtlasAndAgentTests` hardcodes the author's absolute repo path and can pass on CI without that repo. Scanner only recognizes `.git` directories, missing worktrees. | Disposable real Git fixtures, unavailable/error states and proper repository discovery; never label failed status as clean. |
| Long prompt drops execution requirements | **Demonstrated:** Swift prompt truncates after appending requirements; a long objective removes the final execution/test instructions. Character limits do not prove a token limit. UI sends only title/objective; CLI has different context assembly. | Reserve mandatory instruction budget, bound each optional section and test both entry points. |
| Cloud save label overpromises | Idea store can choose a local fallback when the iCloud directory is absent. A local file does not prove cloud upload. | Display actual destination and sync uncertainty. |

## What was actually added

| Addition | Current maturity |
|---|---|
| Codex quota reader and menu labels | Local snapshot parser/UI, not a proven continuous meter |
| Day/night scheduler | Policy helper, not enforced orchestration |
| Prompt builders and Codex process launcher | Manual prototype; no verified safe autonomous lifecycle |
| Project Atlas | Useful discovery direction; blocking process and unavailable-state defects |
| Time Atlas | Handwritten wire/schema prototype; malformed input crash and identity defect |
| Ideas | File discovery/import and quick capture; overwrite defect blocks reliable use |
| Workflow capture | App switches and left/right mouse clicks only; no screen images, audio or keystroke capture in the native implementation |
| SOP/Python synthesis | Text generation exists; generated executable correctness is disproven by syntax probes |
| Existing store/history/keep-awake/loopback adapter/delivery | Previous implementation largely unchanged, original tests retained; earlier hardening evidence still applies within its original scope |

The new surface is substantial integration work, not a combination of three upstream source trees. It adds directions Newton can grow into, but does not establish feature parity or production reliability. No sustained CPU, memory, battery or unattended-work benchmark was performed.

## Stabilization plan and finish conditions

1. **Protect data and process availability:** make note creation collision-safe; harden/bound protobuf decoding; replace Git subprocess waits with bounded draining and off-main scans. Add regressions that fail on this exact release and pass with fixes. Finish: notes preserved, malformed inputs return errors, large/failing repositories complete within deadline without freezing UI.
2. **Make workflow output trustworthy:** fix code escaping/indentation/click semantics, observable state, filename validation and truthful persistence errors. Bring recording into normal shutdown ownership. Finish: Python AST fixtures pass, save failures retain drafts, start/stop/shutdown release monitors reliably; real replay remains opt-in and separately verified.
3. **Own every integration operation:** inject quota/repository/import services, bound work/output, bring new imports and agents under shared operation/shutdown guards. Finish: tests use disposable homes/repos, concurrent operations have defined exclusion, cancelled/terminated jobs leave no child processes or late UI updates.
4. **Define AI execution contract:** separate manual execution from policy-controlled unattended jobs, enforce quota freshness/reserves at dispatch, isolate AI edits from another active tool, verify cancellation through tests. Finish: policy and process fixtures cover missing quota, overlap, timeout and failed launch without starting real agents.
5. **Reconcile product claims and gate the next release:** real schema fixtures, integration/soak evidence, updated documentation and macOS CI. Ship a reviewed patch only after blockers and associated regressions are resolved. Do not use another feature expansion or successful build as the finish criterion.

Review finish: changes mapped, baseline tests/build/CI checked, independent defects reproduced, current context corrected and a concrete repair order recorded. **The defects remain open in application code.** Historical Gemini claims are preserved in [release memory](../history/2026-10-24-gemini-release-memory.md), not silently treated as verified facts.
