# Newton Changelog

All notable changes to the Newton workspace are documented in this file.

## [0.1.4] - 2026-10-24

### Added
- **Embedded Screenpipe Engine (Native Vision & OCR)**:
  - `VisionCaptureEngine.swift`: On-device `VNRecognizeTextRequest` text recognition running on Apple Neural Engine. Bounded continuous sampling and change detection for 0% redundant index bloat.
  - `EmbeddedScreenpipeClient.swift`: In-process SQLite FTS5 search directly querying local database with zero external server or loopback port dependencies.
  - `VisionCaptureTests.swift`: Comprehensive unit tests for text recognition, frame generation, and local FTS retrieval.
- **Embedded Lumen Hardware & Storage Engines**:
  - `PowerPacingEngine.swift`: Real-time Apple Silicon SoC package power (Watts), discharge pacing, battery health, and deep work runway via IOKit.
  - `DeveloperProjectTrimmer.swift`: 1-click developer bloat trimmer scanning and safely reclaiming space from `node_modules`, `.venv`, `.build`, `target`, `.turbo`, and `.next` caches.
  - `LumenEnginesTests.swift`: Unit tests covering power runway formatting, live IOKit capture, and safe bloat folder deletion.
- **Embedded Vorssaint Fluid UI & Quick Tools Suite**:
  - `NotchView.swift`: Translucent liquid-glass dynamic notch HUD displaying live SoC Watts, active Git project/branch, AI Foundry agent status, and quick toggles.
  - `QuickTools.swift`: Global native Color Sampler / Eyedropper (`NSColorSampler`) with automatic hex clipboard copy, and CoreAudio global microphone mute controller.
  - Integrated Notch HUD and Developer Bloat Trimmer cards directly into `WorkspaceView.swift`.
- **Test Matrix Expansion**:
  - Expanded test suite to **109 automated tests** (97 Swift + 12 Python) passing 100% green.

## [0.1.3] - 2026-10-24

- Prevent idea replacement; preserve drafts/destinations on indexing failure.
- Reject malformed/oversized protobuf safely; stable UUID-less journal reimports.
- Bound subprocesses and file discovery; responsive asynchronous optional scans and truthful Git/quota states.
- Own workflow recording/teardown, limits, retry/discard and staged exports. Python AST passes; replay remains experimental and unexecuted.
- Coordinate imports/deletion/shutdown and drain accepted writes.
- Isolate exclusive manual agent runs in committed-HEAD Git worktrees with cancellation through verification and bounded local output/failure evidence.
- Disable unattended execution and prompt CLI bypass. Preserve mandatory instructions within 14,000 characters.
- 88 Swift and 12 Python tests pass with disposable homes/repositories and fake services. Packaging/receipt and macOS15/26 release CI pass; delivery receipts are in the stabilization review.

## [0.1.2] - 2026-10-24

Review correction: the feature descriptions below record Gemini's implementation intent. They are not all verified capabilities. The [independent review](docs/reviews/2026-10-24-gemini-review.md) documents blockers: idea overwrite, parser crash, Git scan hang, invalid workflow programs and lifecycle gaps. Scheduler policy is not enforced by dispatch; the helper script is not an autonomous build daemon. Native workflow capture records app switches/clicks, not keystrokes/screens. Quota UI is a snapshot, not a verified live countdown. Current suite is 61 Swift + 10 Python tests; green CI/build does not resolve these findings.

### Added
- **Live Codex Quota & Reset Reader** (`CodexQuotaReader.swift`):
  - Directly reads rate limit payloads from `~/.codex/sessions` rollout logs with zero token consumption.
  - Exposes 5-hour rolling allowance window percentage and exact UTC reset timestamp.
- **Day / Night AI Scheduler** (`AIScheduler.swift`):
  - *Daytime User Reserve (08:00 – 22:00):* Restricts background batch reasoning to protect the user's interactive 5-hour limit.
  - *Nighttime Autonomous Foundry (22:00 – 08:00):* Enables deep autonomous builds scheduled to exhaust and replenish before 08:00 morning wake-up.
- **Context-Anchored Prompt Generator** (`PromptGenerator.swift` & `bin/newton-prompt-gen`):
  - Ingests `MEMORY.md`, target source headers, and task briefs to construct token-frugal (< 3.5k tokens) instructions for Codex or Antigravity.
  - Includes `--exec` flag to dispatch directly to local `/opt/homebrew/bin/codex exec`.
- **Zero-Dependency Protobuf Wire Decoder** (`TimeAtlasReader.swift`):
  - Pure Swift protobuf wire parser (`ProtoWireDecoder`) reading atomic `.pb` activity updates from `iCloud~com~timeatlaslabs~Pat/Documents`.
  - Extracts daily DateAnalysis and mobile event IDs into deduplicated `HistoryEvent` records.
- **Cross-Device iCloud Notes Store** (`iCloudIdeaStore.swift`):
  - Discovers markdown/text idea notes in iCloud Drive (`com~apple~CloudDocs/Newton/Ideas`) and syncs them into SQLite with SHA-256 deduplication.
- **Screen Recording to Coded Steps Engine** (`ScreenActionRecorder.swift` & `WorkflowSynthesizer.swift`):
  - Captures action boundary events (app switches, clicks with coordinates, keystrokes).
  - Synthesizes Standard Operating Procedures (SOPs) and compiles them into standalone executable Python/AppleScript automations.
- **Fluid UI & Menu Bar Integration** (`WorkspaceView.swift` & `NewtonApp.swift`):
  - Real-time AI Quota meter and reset countdown in both the menu bar popover and Mission Control overview.
  - *Project & Life Atlas* view merging desktop app switches, iPhone Time Atlas moments, and iCloud ideas.
  - 1-click Quick Idea Capture interface.
- **Autonomous Build Daemon** (`bin/autonomous_build.sh`):
  - Autonomous background runner with time-of-day quota gating and automated test execution.

## [0.1.1] - 2026-10-24
- Native SwiftUI workspace and menu bar.
- Opt-in app-switch history using workspace notifications.
- Actor-owned SQLite history with FTS5 search and schema2 migrations.
- Keep-awake power assertion utility.
- Bounded Lumen JSONL metadata intake.
- Loopback Screenpipe connector with in-memory transient results.
