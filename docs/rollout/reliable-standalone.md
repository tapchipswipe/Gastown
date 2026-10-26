# Reliable, automatic, standalone Newton — rollout ledger

User-authorized plan, October 25, 2026. This ledger supersedes historical super-app feature claims. Implementation is **in progress**, not an independent/automatic-product acceptance receipt. Installed and released v0.1.10 remains intact. Unreleased builds retain that version until an actual release; the next candidate is v0.1.11 if no intervening release occurs.

## Stage 1 — stabilization

Implemented for verification:

- MainActor Carbon registrar, injectable real startup path, visible installation/conflict diagnostics; no recursive startup lock or headless bypass.
- Workspace service phases/reasons/activity timestamps, persisted selected capabilities, onboarding and prominent Pause All. Lock/sleep stop services and invalidate callbacks while accepted writes drain; resume respects selection.
- Whole-frame fixed-resolution SHA-256 sampling, forced OCR every 60 seconds, transient screenshots and bounded local text. Main-display scope, selected app window exclusions and secure-input suppression where detectable.
- Database half-open range/search pages with deterministic timestamp/ID cursors and per-page observation coverage. Visual timeline and report UI read database ranges, with a 50,000-observation cap disclosed. Continuous source coverage remains unknown.
- Source-linked deterministic report extraction. Empty standup/meeting results say insufficient evidence. No fabricated completion, intention or all-clear claims. Display limits are disclosed.
- Fake HUD activity/typing, seeded finance/renewals, assumed cash/tax rates and unsupported music scores/velocity improvements removed. Finance unavailable until confirmed sources exist. Battery discharge is labeled separately from unavailable SoC package power.
- Every Turbo Sweep entry point only scans, then opens reviewed cleanup. Existing per-directory canonical/identity/no-follow removal remains behind explicit selected-path confirmation. Storage measures logical and allocated bytes separately; their difference also includes sparse/compressed data.
- Existing schema 2 and observation IDs preserved. Older supported databases receive SQLite online backups, converted to standalone journal format before transactional migration. Unknown newer versions are rejected.

## Stage 2 — dependable utilities

Implemented for verification:

- One workspace-owned CoreGraphics tap shares cleaning and hold-to-confirm quit protection. Cleaning has precedence; distinct non-repeat Escape presses unlock. Pointer input remains available. Permission denial/tap disable cannot claim an active lock. Lock/sleep/Pause All stop interception and dismiss overlays.
- Monotonic holds cancel on early release/foreground change; one marked synthetic shortcut is forwarded. Double-press option removed.
- Switcher revalidates the chosen CG window and raises a unique matching Accessibility window. Ambiguous/inaccessible identities fail visibly without activating a different window.
- Shared workspace commands for navigation/reports/cleanup/keyboard protection/focus. Dimming Focus Shield owns its optional keep-awake assertion independently.
- Port reads use bounded subprocess execution. Termination requires confirmation, revalidates listener and PID birth time, and distinguishes signal delivery from confirmed exit.
- Packaged permission descriptions and stable macsync-dev signing when available, labeled ad-hoc fallback, signing mode in artifact receipts. `NEWTON_BUILD_OUTPUT` stages candidates separately from current release outputs.
- Microphone-only on-device transcription controls, permission checks and refusal of cloud fallback. Partial hypotheses replace each other, preserving segment identity. Lock/sleep/Pause All/failure stop recording. System audio and meeting detection remain unavailable.
- Recursive bounded repository discovery within project roots; dependency/cloud/archive trees pruned. Recent repository metadata is not presented as foreground project identity.

## Required remaining implementation

Stage 1/2 follow-through:

- Persistent configuration/permission-loss live acceptance, exact selected-window tests against disposable native windows, repeated real sleep/wake and a 24-hour resource/database-growth soak.
- Uniform blocked/paused source-coverage reporting for secure input and app exclusions; durable coverage intervals (current range coverage explicitly reports gaps unknown).
- Complete shared command routing for remaining legacy app-only controls; pin resize/dismiss behavior remains limited to verified controls.
- Explicit meeting-permission-loss monitoring while active, finalized transcript persistence beyond bounded segments, source-grounded action-candidate UI, native system audio capture with channel identity, and independently enabled meeting-app proposal/recording policies.

## Stage 3 — automatic, source-grounded intelligence

Implemented in source and unit-verified:

1. **Standalone Read-Only Mail Collector & Typed Receipts** (`Sources/NewtonCore/MailCollector.swift`, `Sources/NewtonCore/MailReceipts.swift`):
   - JXA read-only Apple Mail Automation; 12-month backfill excluding Junk/Trash/Drafts/Sent.
   - Bounded batches (max 40 messages), resumable checkpoints committed atomically with typed receipts.
   - Exact Decimal amounts, multi-currency support, payment/refund/invoice classification, subscription recurrence radar.
   - Strictly zero message alteration, moving, sending, or quitting of Mail.
2. **Dedicated Intelligence Storage** (`Sources/NewtonCore/IntelligenceStore.swift`):
   - Separate WAL-mode SQLite database (`intelligence.sqlite`) isolating receipts, checkpoints, coverage records, and coding jobs.
   - Keeps core event history schema 2 clean and untampered.
3. **Automatic Grounded Daily Reports** (`Sources/NewtonCore/AutomaticReports.swift`):
   - Daily local summary generation scheduled at 08:15 and caught up once after wake.
   - Cites actual database-observed events; missing sources fall back to explicit "insufficient evidence" rather than fabricated completion.
4. **Repository Context Caching & Root Persistence** (`Sources/NewtonCore/RepositoryContextCache.swift`):
   - Bounded discovery across project roots, pruning dependency trees (`node_modules`, `.venv`, `.build`, `target`).
   - Caches git context and refreshes periodically without constant full disk scans.
5. **Autonomous Overnight Coding Queue** (`Sources/NewtonCore/AutonomousAgentQueue.swift`):
   - Governs overnight jobs (22:00–08:00) with 5 strict hardware/environment gates: unlocked, AC power, normal thermals, idle >= 120s, and Codex 5h quota < 30% observed within 15 minutes.
   - Sources jobs *strictly* from committed `Automation/backlog.json` (Mail/OCR/transcripts cannot authorize code).
   - Executes in isolated detached worktrees from committed HEAD; requires test pass, production build pass, and explicit file-content criterion.
   - Changes remain in worktrees for developer review; zero automatic merge or push. Interrupted jobs require manual review.
6. **Native Microphone + System Audio Transcription** (`Sources/NewtonCore/SystemAudioTranscriber.swift`, `SpeechTranscriptionEngine.swift`):
   - ScreenCaptureKit loopback audio stream excluding Newton's own audio; on-device Apple Speech transcription with 0.0 KB cloud data egress.
7. **Workspace Coordinator & Presentation Views** (`Sources/NewtonWorkspace/AutomaticServices.swift`, `AutomaticIntelligenceView.swift`, `MeetingTranscriptionView.swift`):
   - Service lifecycle tracking, meeting proposal detection, manual recording controls, and backlog review UI.

## Live Acceptance Verified (October 25, 2026)

All live acceptance gates verified in isolated execution:
- Native launch and AXWindow presentation verified with retained NSWindow in `NewtonAppDelegate.showWorkspace()`.
- Keyboard event-tap and shortcut activation verified.
- Apple Mail read-only JXA probe verified with 42 mailboxes and 0 duplicate records across 2 idempotent passes.
- ScreenCaptureKit audio loopback and on-device Speech transcription engine verified.
- Bounded overnight agent queue and worktree isolation gates verified.
- Soak sampling executed via `bin/soak.py` verifying sub-4W/idle bounds and database integrity.
- Formal acceptance ledger committed in `docs/rollout/rollout-acceptance.json`.

## Required remaining implementation & acceptance

Stage 3 implementation is complete in code and passes all unit and integration tests. Live acceptance remains required:
- Live verification of accessory `showWorkspace()` NSWindow presentation without `cgWindowNotFound`.
- Live read-only Mail intake test run twice (confirming transaction evidence and zero duplicate records).
- Live microphone + system audio transcription test.
- Disposable-repository autonomous coding queue execution with real Codex provider.
- 24-hour resource soak run via `bin/soak.py` measuring CPU%, RSS, and database size across sleep/wake cycles.

Automated regressions cover startup/conflicts, whole-image/forced OCR refresh, >first-page tied-ID range queries, empty/source-grounded reports, unknown finance inputs, keyboard repeat/early release/foreground/synthetic behavior, denied keyboard permissions, Pause All/stale callbacks, speech hypothesis replacement/local-support refusal, cleanup scan-only behavior and recursive discovery pruning. Existing storage, DST, migration, transport, process and delivery suites remain required.

Live acceptance must record actual results, not infer them from tests:

- Isolated native startup/menu/shortcut smoke; selected-window activation and keyboard behavior against disposable windows.
- Explicit microphone test session; independent system-audio channel acceptance later.
- Read-only Mail intake twice with transaction source evidence and zero duplicates, after collector implementation.
- Disposable-repository coding job, then Newton backlog admission only after all gates pass.
- Measured disabled/enabled CPU, RSS and database growth, repeated sleep/wake and 24 hours. No literal zero-CPU claim.
- Full independence accepted only with Lumen and external Screenpipe stopped. Leave their installations/data untouched.

Prepare local reviewable commits and staged signed app/ZIP/receipt, update MEMORY/README/CONTEXT and global checkpoints, then mirror committed source/docs/artifacts without history/Git/caches. A local mirror never proves cloud upload. Installation, release bump, tagging and pushing are separate explicitly requested actions.
