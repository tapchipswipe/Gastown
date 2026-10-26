# Newton — current resume brief

Updated October 24, 2026. **Read [CONTEXT.md](CONTEXT.md) for the full project layout, implementation contracts, evidence, limits and next milestones.** Working rules remain in [AGENTS.md](AGENTS.md).

## Current identity

- Local-authoritative source: `/Users/lucasdespot/newton`.
- Private repository: https://github.com/tapchipswipe/newton.
- Version: **0.1.1**; bundle ID `com.tapchipswipe.newton`; macOS 14 deployment target, Swift 6 language mode.
- App: `build/Newton.app`; package: `build/Newton.zip`; provenance: `build/receipt.json`.
- User chose a balanced utility/work-history/personal-dashboard direction and prefers a plan followed by autonomous, verified execution without routine approval pauses.
- This is **original code with adapters**, not merged upstream source or feature parity with Lumen, Vorssaint or Screenpipe. Original Lumen was left unchanged. See [source boundaries](docs/SOURCES.md).

## What works

Native SwiftUI workspace/menu bar; opt-in app-switch history; actor-owned SQLite/FTS5 with schema2 migrations and deterministic pagination; batched/retryable activity persistence; keep-awake utility; bounded selected Lumen metadata intake; manual, bounded loopback Screenpipe searches with transient results; live Codex rate-limit & 5-hour reset reader (`~/.codex/sessions`); day/night AI scheduler protecting daytime user quota while permitting midnight autonomous builds; token-bounded prompt generator (`bin/newton-prompt-gen`); zero-dependency wire protobuf decoder (`TimeAtlasReader`) reading iPhone activity updates from iCloud; cross-device `iCloudIdeaStore` with SHA-256 deduplication; `WorkflowSynthesizer` compiling desktop action sessions into Standard Operating Procedures (SOPs) and executable Python automation scripts; menu-bar live AI quota meter and Project & Life Atlas view.

## Rules that must survive future changes

- Fresh launches start every feature off. Last audit restored the user's three enabled switches; never treat that historical observation as a persisted preference or assume current state without reading it.
- Activity notifications are generation-guarded. One worker batches 128; failures remain retryable; capture pauses at 4,096 pending records. Disabling stops new capture without discarding accepted work. Quit drains active writes and fails visibly if saving/release cannot finish.
- Unknown schema versions are rejected. Migration validates before commit. SQLite startup retries and transactional integrity checking preserve the fixes found by concurrency stress.
- Keep live default construction inside NewtonWorkspace and explicit delegate initialization: Swift6.1.2 crashed with the earlier cross-module actor/default-argument stored-property initializer.
- No guessed metrics, hidden uploads, automatic Lumen history intake or restricted upstream source imports. Screenpipe runs independently and its own policies still apply.

## Evidence and remaining limits

- **42 Swift (10 suites) + 10 Python delivery tests passed locally.** Verified clean build under Swift 6 language mode. All 3 new suites (`AIOrchestratorTests`, `TimeAtlasAndIdeaTests`, `WorkflowSynthesizerTests`) passed with zero failures.
- Rate-limit parser verified against live `~/.codex` rollout sessions; daytime schedule gate blocks background batches to protect user interactive work; nighttime foundry enables autonomous runs.
- Time Atlas wire decoder verified extracting DateAnalysis and mobile event IDs from local iCloud protobuf updates without external dependencies.
- Workflow synthesizer generates valid Python scripts and markdown SOPs from captured action streams.
- Five lock-stress repetitions passed: 1,280 opener/verification attempts across 160 disposable databases. Native history migration/capture, power assertions and quit-after-window-close verified; user data preserved.
- Build-input SHA: `fc029f284260fb0cad4c8b5c5524f10ea3d3d9e16c3179320d530e734522c359`. Documentation-only checkpoint edits do not change this digest or the app version/tag.
- 10k-record samples show similar query speed and modest write overhead, not a general speedup. No multi-day CPU/battery/memory claim.
- Live Screenpipe deployment/auth, real Lumen picker intake, multi-day soak, retention/encryption/production backup recovery and notarization remain unverified/absent. Passing the scoped audit is not proof of zero future bugs.
- Detailed fixes/evidence: [audit findings](docs/audits/2026-10-24-findings.md). The full prior chronological memory is preserved in [session history](docs/history/2026-10-24-session-memory.md); its earlier entries are historical.

## Operations and locations

- `./test.sh`; `./build.sh`; `open build/Newton.app`; `python3 bin/artifact.py verify`; `./bin/benchmark.sh`.
- Actual release: clean reviewed commit, then `./bin/ship.sh`; delivery retry after a committed release: `./bin/ship.sh --resume`. Do not bump again to bypass a pending release.
- Local preview CLT Swift6.4 lacks the default macOS27 SwiftUI macro plugin; scripts prefer installed macOS26.5 SDK and discover TestingMacros explicitly. Override with `NEWTON_SDK` when appropriate.
- Live DB: `~/Library/Application Support/Newton/history.sqlite`, directory0700, no Newton encryption. Logical deletion is not secure erasure. Local audit backups: `/Users/lucasdespot/local/newton-audit-backups/`; never mirror these.
- iCloud mirror: `Projects/Newton/current.json` → immutable `snapshots/<commit>/<archive SHA>/`; source and `_artifacts` only. Legacy top-level copies are not current. Server upload unverified.
- After documentation-only commits, verify receipt then `./bin/mirror.sh`; no rebuild/version bump is necessary. Keep global AGENTS/GEMINI synchronized.

## Next starting point

See CONTEXT §11 for phased work and finish criteria. Recommended next milestone: disposable live integration checks and a measured capture soak, then retention/export/backup lifecycle before richer recording or broad feature expansion. This is a proposal, not a claim that future phases are implemented.

At session start, read AGENTS → MEMORY → CONTEXT and inspect git status/current receipt/CI before editing. Preserve dirty user work and actual history. Update current context after verified milestones; keep historical evidence separate.

## Release 0.1.2
Tests and packaging passed. Delivery receipts are maintained in .git/newton-release.json; no upload inferred.
