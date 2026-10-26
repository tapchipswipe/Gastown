# Newton — current resume brief

Updated October 24, 2026 after independent verification of Gemini's v0.1.2 expansion. Read [CONTEXT.md](CONTEXT.md) and the [Gemini change review](docs/reviews/2026-10-24-gemini-review.md) before further development. Rules: [AGENTS.md](AGENTS.md).

## Identity and current assessment

- Local-authoritative source: `/Users/lucasdespot/newton`; private repository: https://github.com/tapchipswipe/newton.
- Version **0.1.2**, bundle ID `com.tapchipswipe.newton`, macOS 14 deployment target, Swift 6 language mode.
- Original native code and adapters; not merged upstream source or feature parity with Lumen/Vorssaint/Screenpipe. Original Lumen remains untouched. User priority is balanced utilities, work history and dashboard.
- The hardened v0.1.1 storage/history/delivery foundation remains intact. Gemini added quota/project views, prompt/agent prototypes, idea and Time Atlas intake, and workflow capture/synthesis. **These additions have verified blockers and are experimental.**
- Reviewed code: `c1047757a2d25bfd75a5417669ab250b360c6fa2`, including `98f139e`. This review changed documentation only; the defects below remain open in application code.

## Verified evidence

- `./test.sh`: **61 Swift tests (17 workspace + 44 core) and 10 Python delivery tests passed**. The old “42” count was incorrect. Workspace tests now invoke real-home quota/repo readers during startup; service injection/hermetic isolation needs repair.
- `./build.sh` and `python3 bin/artifact.py verify` passed for 0.1.2. App `build/Newton.app`, package `build/Newton.zip`, receipt `build/receipt.json`.
- Current build-input SHA256: `eba50796eba7c07ab4591c599704eda39ce4a760b5901240cb3f529c1cfdd0a6`. Documentation-only changes do not require a version bump/rebuild.
- [CI run 40131778224](https://github.com/tapchipswipe/newton/actions/runs/40131778224), attempt 2: macOS 15 and 26 green for reviewed code. Initial macOS 15 failure was action-download DNS failure before tests; failed-job retry passed.
- [Synthetic probe source/results](docs/reviews/2026-10-24-gemini-evidence.md): repeated-title idea overwrite; malformed protobuf process trap; Git pipe deadlock; invalid generated Python; unobserved recording changes and recorder left running after shutdown; unstable journal IDs; false clean repo defaults; truncated prompt requirements.
- No app launch, capture/replay, real agent execution or live database mutation during this review. Existing tests were run as authored, including their newly coupled default readers. No private session contents were printed or mirrored.

## Open priorities / next starting point

1. Prevent idea overwrite and decoder crashes; bound/offload repository and quota scans, with a subprocess deadline and concurrent pipe draining.
2. Correct Python generation, click semantics, observable recording state, export error reporting and recording teardown.
3. Bring agents/new imports into owned cancellation/shutdown and deletion exclusion; isolate AI edits, bound outputs, inject services and eliminate real-home test dependencies.
4. Decide manual versus autonomous execution semantics and enforce policy at dispatch. Scheduler currently has no production caller; helper script runs tests, not an autonomous build/agent daemon. Gemini quota/provider integration does not exist.
5. Add independent real-schema/integration fixtures and measured soak evidence before broader features or a new release. Detailed finish conditions are in the review.

## Contracts to preserve

- Fresh launches start original capture/features off. Never infer actual current switches from historical observations. New workflow recording currently falls outside their proven lifecycle: fix that gap.
- Actor-owned SQLite schema 2, atomic validated migrations, future-version rejection, deterministic pagination, retryable batched activity writes (128 batch / 4,096 pending pause), generation guards and graceful accepted-write drain remain mandatory.
- Keep live default construction inside NewtonWorkspace and explicit delegate initialization; earlier cross-module actor default initialization crashed Swift 6.1.2.
- No guessed metrics/hidden uploads or automatic private Lumen intake. Screenpipe remains a separate optional loopback service; its queries stay transient. New idea/Time Atlas imports are manual; quota/project scans run during startup.
- Workflow implementation captures app switches and left/right clicks, not screen images/audio/keystrokes. Do not describe generated scripts as valid until syntax and replay gates pass.
- iCloud idea writes may use a local fallback. Local copies do not establish server upload. No measured zero-idle-CPU or multi-day battery/memory guarantee.

## Operations and locations

- Tests/build: `./test.sh`, `./build.sh`, `python3 bin/artifact.py verify`. Avoid launching agents or capture merely to inspect the app.
- Release only reviewed code: `./bin/ship.sh`; recover a committed delivery with `--resume`. Do not bump again to bypass a pending release. No new release/tag for this documentation review.
- Scripts prefer installed macOS 26.5 SDK; override `NEWTON_SDK` when appropriate. macOS 14 is a deployment target, not an established runtime test.
- Live database: `~/Library/Application Support/Newton/history.sqlite`, directory 0700; no Newton encryption or secure erasure. Local audit backups: `/Users/lucasdespot/local/newton-audit-backups/`; never mirror.
- Mirror: iCloud `Projects/Newton/current.json` points to immutable source/artifact snapshots. No .git, caches or databases. Server upload unverified. After committing documentation, verify receipt and run `./bin/mirror.sh`; synchronize global AGENTS/GEMINI and their context mirror.
- Previous hardening: [findings](docs/audits/2026-10-24-findings.md). Superseded Gemini claims retained in [release memory](docs/history/2026-10-24-gemini-release-memory.md); original chronology in [session memory](docs/history/2026-10-24-session-memory.md).

Start by inspecting git status/current receipt/CI, then execute one stabilization milestone through meaningful regressions and context updates. Preserve concurrent Gemini/user work. Passing tests is not proof that no flaws remain.

## v0.1.3 stabilization in progress — stage 1
Collision-safe idea publication; typed/bounded protobuf with deterministic journal IDs; bounded concurrent-draining POSIX process groups; asynchronous injected startup scans; truthful unavailable Git state and timestamped bounded quota snapshots. Stage-1 suite: 66 Swift + 10 Python tests passed. No version bump or release yet. Remaining workflow/import/agent stages are in progress.

## Stabilization stage 2
Observable, failure-reporting workflow capture with generation guards, 10,000-action/60-minute bounds, idempotent teardown and retained-session quit protection. UUID bundle export reports file and index outcomes separately and supports retry/discard. Python AST fixtures pass for Unicode, quotes, multiline text and distinct Quartz clicks; desktop replay remains experimental and untested. Stage suite: 71 Swift + 10 Python passed.

## Stabilization stage 3
One cancellable file-intake admission/commit boundary now owns Lumen, ideas and Time Atlas; deletion exclusion, accepted-write shutdown drain and saved-note indexing retry are covered. Manual agents have run IDs, typed phases, exclusive ownership, committed-HEAD worktree isolation, configurable repository/PATH resolver, bounded output and cancellation through verification. Prompt requirements survive the 14,000-character cap in Swift/Python. Direct CLI exec and unattended policy reject execution; legacy autonomous script is only a test helper. 81 Swift + 12 Python tests pass, using fake agents and disposable files/repositories. No provider or replay was launched. Release gates still pending.
