# Newton

Your tools, your history, one orbit. A private native macOS workspace for local work history, utilities and manually initiated tools.

## Unreleased reliability work

The [rollout ledger](docs/rollout/reliable-standalone.md) is the current implementation and acceptance status. Newton is being stabilized before automatic intelligence is enabled. Mail finance, scheduled reports and unattended agents are unavailable. Current release v0.1.10 stays intact; no installation or release is implied by a staged build.

Hotkey startup no longer recursively acquires a lock. Capabilities are selected once, persisted and resumed; Pause All and lock/sleep stop collection. Global keyboard tools and microphone-only local transcription have visible controls and permission/error states. Their live acceptance and the 24-hour soak are still required.

## Daily-use tools

- Independent daily history, separate from search and pagination. SQL reads `[dayStart, nextDayStart)` in timestamp/ID order; the first 50,000 records are shown with an explicit incomplete label if more exist. Five-minute intervals follow actual local elapsed time, including 23/25-hour daylight-saving days. Empty intervals say “No observations.” All records are retained in their interval.
- Counts describe records and observed intervals. There are no inferred keystrokes, focus minutes, productivity scores or keyword-based meeting claims. Project badges are “Latest known commit,” with incomplete coverage. Time Atlas's unverified schema/timestamp fidelity stays visible.
- **Screen OCR — Experimental**, off until selected during setup: ScreenCaptureKit main-display snapshots and Vision text recognition, sampled every four seconds without overlapping recognition. Only bounded text is saved locally; screenshots are transient. Permission/start errors are visible. Lock/sleep pauses sampling; it resumes only while enabled. Native permission/capture behavior awaits a separate explicitly initiated integration session.
- Local indexed search never falls through to a network service. External Screenpipe remains a separate manual loopback connection; its results/token are transient.
- **Manual providers — Experimental**: select Codex (`exec`) or Gemini (`-p`). Dual orchestration is unavailable. One owned run at a time uses an isolated committed-HEAD worktree, deadlines, cancellation through verification and bounded output. Both `newton.md` and `MEMORY.md` are read there, at most 64 KiB/file and 6,000 combined characters. Mandatory instructions fit inside the 14,000-character prompt budget. No token guarantee. Changed/failed worktrees remain for review; the runner never merges or pushes.
- Quota snapshots are advisory, bounded and timestamped. They do not establish provider availability or guarantee morning capacity. **Unattended execution remains disabled.**
- Battery/charging/thermal/cycle fields show available system readings or unavailable states. **SoC watts is unavailable**; there is no privileged measurement helper.
- Developer cleanup runs off MainActor under workspace ownership. Discovery is bounded to 10,000 entries; sizing to 100,000 entries/candidate, with incomplete diagnostics. Review every selected path before confirming deletion. Only current-scan candidates with unchanged canonical roots/directory identities are accepted; descriptor-relative removal does not traverse symlinks. Per-directory successes/failures/cancellations are shown. Sizes are estimated removed directory sizes, not guaranteed free-space gains. Cancellation stops before the next directory and cannot roll back an in-progress deletion.

Other tools include opt-in app-switch history, keep-awake assertions, user-selected Lumen JSONL intake, idea files, project status, Time Atlas intake, workflow app-switch/click export, color sampling and microphone controls. This is original Newton code, not complete upstream feature parity. Python replay remains experimental and is not run automatically.

## Build and verification

Requires macOS 14+ and Swift 6 tooling; no external package dependencies.

```sh
./test.sh
./build.sh
python3 bin/artifact.py verify
open build/Newton.app
```

Automated checks use disposable homes, databases, repositories and fake executables. They never start a real provider, capture the desktop or replay workflows. See [v0.1.6 findings and regressions](docs/reviews/2026-10-24-v016-daily-tools.md) for acceptance receipts. Real capture permissions, provider compatibility, replay and multi-day sleep/resource/database-growth soak require separate explicit validation. Experimental labels remain until those checks pass.

Builds use macsync-dev when available and an explicitly labeled ad-hoc fallback otherwise; the receipt records signing mode. The app is not notarized. Scripts prefer the installed macOS 26.5 SDK; override with `NEWTON_SDK`. Schema remains 2. Existing IDs and original notes are preserved; no live user history is opened by tests.

## Data and delivery

History lives in `~/Library/Application Support/Newton/history.sqlite`, unencrypted. Capture starts off on first launch; saved selections resume after setup. Pause All persists across relaunch. Logical deletion stops app-switch/OCR capture and drains accepted writes; it is not secure erasure. File intake remains manual and originals are preserved. No unattended scheduler or automatic merge/push is installed.

Release: commit reviewed changes, then `./bin/ship.sh` to test, bump once, build/sign/package/verify, commit/tag, atomic push and mirror committed source plus verified artifacts locally to iCloud. After a committed delivery failure, use `./bin/ship.sh --resume`; do not bump again. Read iCloud `Projects/Newton/current.json` for the exact immutable snapshot. A local mirror does not prove server upload.

Read [MEMORY](MEMORY.md), [CONTEXT](CONTEXT.md) and [agent instructions](AGENTS.md). Prior reviews and [historical v0.1.5 claims](docs/history/2026-10-24-v015-claims.md) remain preserved; current docs supersede their broader capability/metric claims.
