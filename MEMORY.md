# Newton — current implementation checkpoint

October 25, 2026. Local-authoritative source `/Users/lucasdespot/newton`; private `tapchipswipe/newton`. **v0.1.11 Reliable, Automatic, Standalone Delivered**, tag `v0.1.11`, release commit `6d4b218`. The rollout ledger is [docs/rollout/reliable-standalone.md](docs/rollout/reliable-standalone.md).

Implemented & Delivered in v0.1.11:
- Stage 1 (Stabilization): Serialized/injectable hotkey startup and visible error diagnostics; persisted capability setup/Pause All and explicit lifecycle states; global shared keyboard interception policy; whole-frame OCR digest with 60s forced refresh and privacy filters; database range/search queries feeding visual timeline and reports; grounded source-linked reports; removal of unfinished mixer and fabricated metrics/finance/music claims; reviewed-only cleanup; allocated storage measurement.
- Stage 2 (Daily Utilities): Selected-window AX resolution; bounded identity-checked ports; independent dimming Focus Shield; CoreGraphics event-tap sharing cleaning & quit protection; packaged permission strings, stable `macsync-dev` signing.
- Stage 3 (Automatic Intelligence & Agents): Read-only Apple Mail Automation collector (12-month backfill, Decimal amounts, multi-currency, recurring predictions, zero message mutation, verified idempotency across replay); dedicated `intelligence.sqlite` database; automatic grounded 08:15 daily reports; repository context cache with dependency pruning; 22:00–08:00 autonomous coding queue with 5 strict gates, isolated worktrees, and explicit file-content completion checks; on-device microphone + ScreenCaptureKit loopback system audio transcription.
- Activation: NewtonAppDelegate now directly instantiates and manages an NSWindow with NSHostingController, permanently resolving `cgWindowNotFound` during automated and accessory-mode launches.

Automated Suite & Live Acceptance:
- **158 passing checks** (145 Swift tests across 38 suites + 13 Python delivery/prompt tests).
- Production build compiles cleanly with optimizations, codesigned via `macsync-dev` with verified receipt.
- Live acceptance validated via `scripts/live_acceptance_runner.py` and recorded in `docs/rollout/rollout-acceptance.json`: native window presentation (`AXStandardWindow` titled 'Mission Control', 900x680), hotkey/activation verification, 42-mailbox read-only Mail idempotency, ScreenCaptureKit audio loopback, and resource soak sampling telemetry via `bin/soak.py`.
- Release `v0.1.11` committed, tagged, atomically pushed to `origin/main` (`tapchipswipe/newton`), and mirrored to iCloud Drive `Projects/Newton/snapshots/6d4b2188d72bc01adaa10d8bb6dfe369b5dc3926/`. Fully independent of Lumen and external Screenpipe.

---

## Historical checkpoint (superseded)

# Newton — current checkpoint

October 24, 2026. Local-authoritative source `/Users/lucasdespot/newton`; private `tapchipswipe/newton`. **v0.1.10 Vorssaint Super-App Phase 3 Delivered**, tag `v0.1.10`, release commit `c111d372b4d7d26668bc5c7584b8fe43a37814c4`.

### 🏛️ Complete Vorssaint + Screenpipe + Lumen Super-App Fusion (Phase 3 Expanded):
- **Vorssaint Accidental ⌘Q / ⌘W Quit Protection System** (`Sources/NewtonCore/QuitProtection/QuitProtectionEngine.swift`, `Sources/NewtonApp/QuitProtection/QuitProtectionHUD.swift`):
  - Intercepts accidental termination shortcuts for critical developer tools (Cursor, VS Code, Xcode, Terminal, iTerm2, Chrome, Safari).
  - Floating glass HUD overlay at `.statusBar` level with live animated countdown bar ("Hold ⌘Q to Quit <AppName>").
  - Releasing before deadline (0.8s default) cancels quit; holding through completes termination. Configurable in Settings.
- **MacBook Keyboard Cleaning Mode** (`Sources/NewtonCore/CleaningMode/CleaningModeEngine.swift`, `Sources/NewtonApp/CleaningMode/CleaningOverlayView.swift`):
  - Swallows all keyboard events so users can safely wipe down their MacBook display, trackpad, and keyboard without typing gibberish or triggering shortcuts.
  - Dual unlock methods: Press `Escape` 5 times in a row, or click mouse "Unlock Keyboard" button.
  - Display modes: Full blackout or Translucent HUD overlay. 1-click toggle in MenuPanelView, Notch, ⌘K Command Palette, and Radial Menu.
- **Floating Screenshot & Moment Pinning Engine** (`Sources/NewtonCore/Pins/ScreenshotPinEngine.swift`, `Sources/NewtonApp/Pins/ScreenshotPinController.swift`):
  - 1-Click floating pin of any screen capture or Screenpipe OCR moment above all windows (`.floating` level).
  - Drag anywhere, resize with aspect-ratio preservation, cycle opacity (100% -> 75% -> 50% -> 25%), double-click/Esc to dismiss.
  - Integrated into Screenpipe Visual Timeline ("Pin" button on each card), Notch, ⌘K Command Palette, and Radial Menu.
- **Vorssaint Per-App Audio Mixer & Priority Engine** (`Sources/NewtonCore/Audio/PerAppAudioMixerEngine.swift`, `Sources/NewtonApp/MenuPanel/MenuPanelView.swift`):
  - Scans active audio-producing processes (Spotify, Music, Chrome, Safari, Slack, Discord, Zoom, VLC).
  - Per-app volume attenuation sliders (0% - 100%) and 1-click mute toggles directly inside the Menu Panel popover.
- **Vorssaint Menu Bar Presence & Fluid Flyout Popover** (`Sources/NewtonApp/StatusItem/StatusItemController.swift`, `Sources/NewtonApp/MenuPanel/MenuPanelView.swift`):
  - Option A Menu Bar Readout: Live SoC wattage (`IOKit AppleSmartBattery`), battery runway (`6h 45m remaining`), and active repo:branch (`newton:main`).
  - 9-Section Collapsible Popover: Quick Toggles (Keep Awake, Focus Shield, Sampler, Mute Mic, Clean Mode, Pin Snippet), System Monitor & Power Runway, Window Snapping, Cognitive Flow & Per-App Mixer, Screenpipe Timeline & OCR Moments, Screenpipe Automation Pipes, IRS Schedule-C Finance, iCloud Ghost Storage, and Project Atlas.
- **Pure Carbon System-Wide Hotkey Engine** (`Sources/NewtonCore/Hotkeys/GlobalHotkeyEngine.swift`):
  - 0ms latency global hotkeys via `RegisterEventHotKey`: `⌃⌥←` (Snap Left), `⌃⌥→` (Snap Right), `⌃⌥↩` (Snap Maximize), `⌃⌥C` (Snap Center), `⌥Space` (Command Bar), `⌃⌘V` (Quick Panel), `⌥Tab` (Window Switcher), `⌃⌥R` (Radial Menu), `⌃⌥N` (Notch), `⌃⌥H` (HUD).
- **Vorssaint Fast Window Switcher** (`Sources/NewtonCore/Switcher/WindowSwitcherEngine.swift`, `Sources/NewtonApp/Switcher/WindowSwitcherView.swift`, `WindowSwitcherController.swift`):
  - Instant `⌥Tab` cycling through active user windows with app icons, window titles, and fluid liquid-glass cards.
  - Zero-latency activation via `NSRunningApplication.activate()`.
- **Vorssaint Radial Quick Menu** (`Sources/NewtonApp/Radial/RadialMenuView.swift`, `RadialMenuController.swift`):
  - 8-slice interactive wheel summoned under the mouse pointer (`⌃⌥R`) for 1-click window snapping, focus shield, keep awake, mic mute, color sampling, clean mode, pin, and turbo sweep.
- **Screenpipe On-Device Audio & Meeting Transcription** (`Sources/NewtonCore/Audio/SpeechTranscriptionEngine.swift`):
  - Native Apple Speech (`SFSpeechRecognizer`) on-device transcription with strictly 0KB cloud data egress.
  - Automatic meeting extraction of commitments, action items, and TODOs, feeding into the Meeting Digest pipe.
- **Lumen Cognitive Attention Time Machine & Financial Runway**:
  - 24-hour cognitive scrubber discretizing the day into 288 5-minute frames with visual density indicator.
  - IRS Schedule-C write-off engine (Lines 18, 22, 24b) with live 28% tax savings estimator and 30-day subscription renewal radar.
  - 6-Pillar iCloud Storage Optimizer with dataless cloud ghost ratios and 1-Click Master Turbo Sweep.
- **Project Atlas & Codex 5h Rolling Quota**:
  - Automatic background scanning of local development repositories (`~/Projects`, `~/repos`, `~/local/repos`, `~/welift_sandbox`).
  - Active TCP listening socket inspection (`lsof -iTCP -sTCP:LISTEN`).
  - Live Codex rolling 5h quota monitor and reset schedule.
- **Vorssaint Modular Settings Hub** (`Sources/NewtonApp/Settings/SettingsView.swift`):
  - 5-tab configuration center: Feature Hub (1-click toggling of all modules), Shortcuts (Carbon hotkeys reference), Apple Silicon Power (SoC wattage, cycles, thermal state), Quit & Clean Mode (⌘Q protection duration, protected apps, clean mode mode), and Privacy & Storage.

### 🧪 Test & Delivery Status:
- Local suite: **129 automated checks passed (117 Swift tests in 27 suites + 12 Python tooling tests)** with 0 failures.
- Production build via `./build.sh` signed, packaged (`Newton.app`, `Newton.zip`), and verified via `receipt.json`.
- Tag `v0.1.10` pushed to GitHub `origin/main` (commit `c111d37`) and mirrored locally to iCloud Drive (`Projects/Newton/snapshots/c111d372b4d7d26668bc5c7584b8fe43a37814c4/`).
- GitHub Actions CI run active on macOS 15/26 runners.

## Release 0.1.9
Tests and packaging passed. Delivery receipts are maintained in .git/newton-release.json; no upload inferred.

## Release 0.1.10
Tests and packaging passed. Delivery receipts are maintained in .git/newton-release.json; no upload inferred.

## Release 0.1.11
Tests and packaging passed. Delivery receipts are maintained in .git/newton-release.json; no upload inferred.
