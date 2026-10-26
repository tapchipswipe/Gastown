# Newton v0.1.3 stabilization evidence

October 24, 2026. Target: reliable manual daily use while preserving schema 2 and existing data. This report supersedes the open-fix status of the [original Gemini review](2026-10-24-gemini-review.md); that review and its synthetic reproduction evidence remain unchanged as historical records.

## Reviewable implementation

- `77db159`: safe ideas, typed/bounded protobuf and deterministic journal IDs; concurrent-draining process groups, asynchronous injected scans, truthful Git/quota states.
- `53fb245`: observable recording, teardown and retained export sessions, staged script/SOP bundles, escaped Python and distinct Quartz clicks.
- `8155343`: shared intake admission/cancellation/deletion boundary; isolated owned manual agents, prompts and disabled unattended/direct CLI execution.
- Final acceptance follow-up adds the injectable capture source, accepted-write shutdown race fix, timeout/cancellation output evidence, disposable test HOME and expanded limits/validity fixtures. Its source is the commit containing this report.

The worktree was checked between stages; no concurrent Gemini changes were present. No upstream code, new recording capability, Gemini integration, scheduler, destructive migration, original-note rewrite or historical duplicate deletion was introduced. No live Newton database was opened during this work.

## Defect-to-regression mapping

| Reproduced defect / required boundary | Implementation and evidence |
|---|---|
| Idea overwrite/collisions | Staged same-volume exclusive hard-link publication, sanitized bounded slug + UUID. `repeatedConcurrentIdeasNeverReplaceNotes` keeps 20 concurrent collisions and rejects a non-directory destination. Existing filenames/hash import IDs are preserved. |
| Failed save/index loses draft or lies about iCloud | UI clears only after successful indexing; actual saved destination is shown. `ideaIndexFailureKeepsDestinationAndRetryReusesSavedFile` injects indexing failure and verifies same-file retry. File and cloud upload are distinguished. |
| Malformed protobuf trap/partial intake | Throwing typed decoder validates keys, ten-byte varint overflow/truncation, lengths against remaining bytes, supported wires and aggregate decoded-field budget. `malformedProtobufThrowsAndJournalIdentityIsStable` rejects adversarial inputs; valid sibling file survives malformed-file rejection. |
| Duplicate UUID-less journals | Hash source-relative filename + entry position + canonical fields. Explicit source UUIDs retain prior ID format. `repeatedJournalImportsAddNothingAndLimitsAreExplicit` verifies second database append adds zero. No historical duplicate cleanup. |
| Unbounded files/parsing | Defaults 100 files, 4 MiB/file, 16 MiB total, 10,000 decoded fields/file, 10,000 discovered entries; descriptor-based regular-file/no-follow reads. A cumulative read budget also accounts for failed/growing-file reads. Limit, oversize, missing-directory, unreadable-subtree and malformed-file diagnostics are asserted, never reported as complete intake. |
| Git pipe deadlock/unavailable fabrication/worktrees | Shared runner drains stdout/stderr concurrently and bounds retained output/deadlines. Flood test exceeds pipe capacity on both streams; `gitRepositoryAndWorktreeTruth` inspects clean/dirty fixtures, 3,000 long untracked filenames and a real disposable worktree. Missing repo reports unavailable with no invented date. |
| Slow optional startup work | Injected asynchronous quota/projects load after history readiness; cancelled generations reject late results. `optionalStalledServicesDoNotDelayOpenOrShutdown` leaves both services deliberately suspended while open/shutdown complete. This is model-readiness evidence, not a native frame-time benchmark. |
| Quota is not live/valid/fresh | Bounded discovery and tail reads preserve source record timestamp. Invalid values, missing/future/expired/older-than-15-minute observations and discovery/read limits have regressions in `quotaDiscoveryAndTimestampAreBounded` and `invalidMissingExpiredAndStaleQuotaAreExplicit`. No provider capacity guarantee. |
| Workflow observation/lifecycle | Observable owned state, start failure, generation guard, 10,000-action/60-minute limit, idempotent stop and shutdown teardown. Workspace tests cover observation, failure and stale model callbacks. `RecordingAdapterTests` exercise the actual recording service with injected sources, including partial-start failure, old source callbacks, action cap and timed stop; no desktop monitors are installed in tests. |
| Invalid Python/click semantics | Escaped string literals and structured indentation; Quartz coordinates and left/right/double-click variants. Double-click capture replaces preceding single click. AST parsing covers quotes, Unicode, multiline text and clicks without importing Quartz or replaying. Unsupported keypresses/invalid coordinates raise diagnostics. |
| Misleading/partial workflow export | UUID directory stages replay.py + SOP.md as one bundle. `exportPublishesBothFilesUnderSafeUUIDAndReportsFailure` checks both files/path safety. `failedExportAndIndexingRetainSessionForRetry` proves filesystem and index outcomes, retained retry and reuse of published bundle. Quit requires export or explicit discard for unsaved sessions. |
| Import/delete/shutdown races | All file sources share admission/task/generation state; parsing is off MainActor, deletion excluded, cancellation checked before append. `allFileIntakeExcludesDeleteAndCancellationPreventsCommit` covers ideas/Time Atlas. `shutdownDrainsAcceptedFileWrites` exposed cancellation propagating into an accepted append; cancellation now stops precommit intake and allows accepted writes to drain. |
| Agent overlap/ownership/isolation | Injected manual interface with run-ID phases, exclusive admission and configured root/executable. `ManualAgentTests` use only fake executables and disposable committed repositories; verify uncommitted source exclusion, changed-worktree preservation, unchanged-success removal, overlap rejection, cancellation during verification, failed launch, test exit 7, timeout evidence and 1 MiB output. Workspace test ignores late progress and joins cancellation on shutdown. |
| Process timeout/cancellation failure evidence | TERM then two-second grace, KILL and reap for owned process group. Error results retain bounded stdout/stderr. Spawn closes unrelated inherited descriptors; group teardown also runs after leader/pipe exit. `cancellationKillsDescendantEvenAfterLeaderAndPipesExit` checks that a TERM-ignoring silent descendant is terminated. Failed/cancelled worktrees and bounded local JSON receipts remain outside repository/mirror. Tests run no AI providers. |
| Truncated mandatory prompt rules | Swift/Python reserve requirements before dividing optional context within 14,000 characters. Long-prompt regressions assert dependency/concurrency/default-off/test/no-push instructions survive. This is not a token-count guarantee. |
| Unattended/direct bypass policy | Scheduler and dispatcher reject unattended runs. Quota is advisory for explicit manual runs. Python CLI `--exec` errors with the owned-runner action; fake-provider-free test asserts rejection. Legacy autonomous script is a test helper, installs no schedule and invokes no provider. |

## Local acceptance

- `./test.sh`: **88 Swift tests** (27 workspace + 61 core) and **12 Python tests** passed on October 24. Output logs are local `/tmp/newton-tests-final.log`; no private inputs are included.
- Tests use a disposable HOME/CODEX_HOME, isolated Git config, disposable repositories/databases/files, injected event sources/optional services and fake executables. Existing storage/transport/delivery regressions remain enabled. No desktop recording, automation replay, provider launch or real session-log read occurred.
- Local candidate build/signature/source receipt passed; macOS 15/26 CI remains pending at this checkpoint. Delivery version is still 0.1.2 until the existing release pipeline bumps once to 0.1.3. Acceptance/delivery receipts will be appended below.

## Remaining explicit integration limits

The code/schema prototype is not evidence of compatibility with real Time Atlas exports or exact device event timestamps. Live Screenpipe/native picker, permissioned capture on multi-display desktops, actual Quartz replay and external provider CLI behavior need separately initiated checks. No real agent was launched; no merge/push was performed by the manual runner. No multi-day battery/memory/CPU, sleep/recovery or automation reliability claim is established. Ad-hoc signing is not notarization.

Next milestone is **integration and soak validation before reconsidering unattended execution**. Retain this boundary even after local and hosted gates pass. Source/artifact mirrors exclude databases, private logs and agent worktrees; a local iCloud copy does not prove server upload.

Candidate local receipt: build-input SHA256 `ac00e5580ce3`. Signature, ZIP and source receipt verification passed for the version-0.1.2 candidate before the one-time release bump. This is not the final 0.1.3 artifact receipt.

Hosted candidate [CI40136026080](https://github.com/tapchipswipe/newton/actions/runs/40136026080): macOS15 passed; macOS26 passed all87 Swift tests then exposed a Python test-loader API removal (load_module). Fixture now uses spec_from_loader/module_from_spec/exec_module; assertions remain unchanged. A fresh hosted run is required before release.

[CI40136155392](https://github.com/tapchipswipe/newton/actions/runs/40136155392) passed both hosted platforms after the Python loader repair. A final injected-clock regression now verifies quota warnings age on access without rereading source files; this source follow-up requires its own hosted gate before release.

Final quota-age follow-up: 88 Swift tests (27 workspace +61 core) and12 Python tests pass locally; build/signature/receipt verify input `e46488db2ed0`. `quotaWarningAgesWithoutReadingAnyMoreFiles` advances an injected clock across15 minutes. Visible quota warning labels update every30 seconds using a UI clock only; manual dispatch evaluates current age directly. No periodic file/provider reads were added.

## Final source acceptance gate

[CI40136485728](https://github.com/tapchipswipe/newton/actions/runs/40136485728) passed macOS15 and macOS26 tests, packaging and artifact steps for `7b28ea9d23a920431090124bcb006fe2dae1f7f9`. Final local suite is88 Swift (27 workspace +61 core) and12 Python, with signed packaging/source receipt verified. Documentation preparation does not change the tested build inputs. Release pipeline may now bump once to0.1.3; delivery receipts follow.

## Verified release delivery

- Version0.1.3, immutable tag v0.1.3, release commit `359c2ba0fbfa6f70903f3281b7ba9bbba43a6b9d`. Existing bin/ship.sh bumped exactly once, tested/built/packaged, atomically pushed main/tag, verified remote refs and mirrored. No delivery failure/resume was needed.
- [Release CI40136634296](https://github.com/tapchipswipe/newton/actions/runs/40136634296): macOS15 and macOS26 tests, release build and artifact jobs all passed.88 Swift tests and12 Python tests; the final source acceptance CI40136485728 also passed both platforms before the bump.
- Strict signature, bundle short/build versions0.1.3, ZIP and source receipt verified locally. Source SHA256 `e4826edb15f22e5d9ead5f936fc10ae5aab3685f5c0dfbb2fa9c0b6bc2bc652a`; ZIP SHA256 `9a67438ba97ca2d054e7ef6cfa3a7f0cef3de4c8253194adc27cba3061017f1f`.
- Immutable committed source/artifact snapshot mirrored locally to iCloud Projects/Newton/current.json. Snapshot/ZIP checks verified exclusion of databases, private logs and agent worktrees. Global context files synchronized and mirrored. These checks do not establish server upload.
- MEMORY, CONTEXT, README and agent context point to this handoff. Original review remains unchanged. Final documentation may advance main after the release tag with the same build inputs/artifact.

Verified stabilization is bounded by the regressions above. Replay/provider/native-permission/real-schema/live-service and multi-day integration limits remain explicit; next milestone is integration/soak before unattended execution is reconsidered.
