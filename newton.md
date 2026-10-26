# Newton architectural history

**Superseded October 25, 2026:** read [the current rollout ledger](docs/rollout/reliable-standalone.md), MEMORY.md and README.md. Historical feature/metric/completeness claims below are not current acceptance evidence.

## 🏷️ Identity & Core Directive
- **App Name**: **Newton** — *“Your tools, your history, one orbit.”*
- **App Role**: Private Personal Super-App for Lucas Despot.
- **Repository**: [`tapchipswipe/newton`](https://github.com/tapchipswipe/newton) (Private)
- **Local Source**: `/Users/lucasdespot/newton` (Local-authoritative; strictly outside cloud-managed folders).
- **Binary**: `Newton`
- **Bundle**: `build/Newton.app` (Installed bundle: `/Applications/Newton.app`)
- **Distribution Package**: `build/Newton.zip` with verified `build/receipt.json`
- **Bundle Identifier**: `com.tapchipswipe.newton`
- **Activation Policy**: `NSApp.setActivationPolicy(.accessory)` — lives natively in the Menu Bar and Desktop Overlays without cluttering the Dock, spawning windows on demand.
- **Code Signing**: Stable `macsync-dev` self-signed identity preserving macOS TCC permissions across builds.
- **Toolchain / Build Environment**:
  - Requires `bin/toolchain.sh` (points to `MacOSX26.5.sdk` or stable CLT SDK).
  - Run tests: `./test.sh` (129+ automated tests: 117 Swift tests in 27 suites + 12 Python tooling tests).
  - Production build: `./build.sh` (compiles with optimizations, packages `Newton.app` & `Newton.zip`, generates `receipt.json`).
  - Master Ship Pipeline: `./bin/ship.sh` (tests, auto-bumps version, builds, tags, pushes commit & tag to GitHub, mirrors to iCloud Drive).

---

## 🏛️ Comprehensive Architecture & Systems Map

Newton is the deep fusion of three flagship systems into a single native Swift 6 macOS application, operating at strictly **0% idle CPU**:

### 1. 🖥️ Vorssaint Desktop Overlays & Menu Bar Architecture
* **Menu Bar Presence & Status Readout** (`Sources/NewtonApp/StatusItem/StatusItemController.swift`):
  - **Option A Readout**: Real-time Apple Silicon SoC package power (Watts), battery runway (`6h 45m remaining`), and active repository branch (`4.2W · 6h 45m · newton:main`) queried from Darwin `IOKit AppleSmartBattery`.
  - Left-click summons the fluid Vorssaint flyout popover; right-click opens standard quick controls.
* **Fluid Flyout Popover** (`Sources/NewtonApp/MenuPanel/MenuPanelView.swift`):
  - 9 collapsible sections:
    1. **Quick Toggles**: Keep Awake, Focus Shield, Sampler, Mute Mic.
    2. **System Monitor & Apple Silicon Power**: Battery percentage, charging state, live wattage, thermal state.
    3. **Window Management & Snapping**: 1-click snap buttons (Left, Right, Maximize, Center, Thirds).
    4. **Cognitive Flow & Sound**: Apple Music & Spotify now-playing track, flow score, playback controls.
    5. **Screenpipe Visual Timeline & OCR Moments**: Real-time moment count, 288 5-minute visual density scrubber.
    6. **Screenpipe Automation Pipes**: 1-click execution for Standup, Missed To-Dos, and Meeting Digest.
    7. **Financial Runway & IRS Schedule-C**: SaaS burn, deductible total, 28% tax savings, 30-day renewal radar.
    8. **iCloud Ghost Files & Turbo Sweep**: Cloud ghost ratio progress bar, 1-click Master Turbo Sweep.
    9. **Project Atlas & Codex Quota**: Active git repo, branch, last commit, listening ports, rolling 5h quota.
* **Pure Carbon System-Wide Hotkey Engine** (`Sources/NewtonCore/Hotkeys/GlobalHotkeyEngine.swift`):
  - 0ms dispatch latency via Carbon `RegisterEventHotKey` (0 accessibility permissions required):
    - `⌃⌥←`: Snap Left Half (50%)
    - `⌃⌥→`: Snap Right Half (50%)
    - `⌃⌥↩`: Snap Maximize
    - `⌃⌥C`: Snap Center (75%)
    - `⌥Space`: ⌘K Command Palette
    - `⌃⌘V`: Menu Panel Quick View
    - `⌥Tab`: Fast Window Switcher
    - `⌃⌥R`: Radial Action Wheel
    - `⌃⌥N`: Dynamic Notch Island
    - `⌃⌥H`: Desktop Glass HUD
* **Vorssaint Fast Window Switcher** (`Sources/NewtonCore/Switcher/WindowSwitcherEngine.swift`, `Sources/NewtonApp/Switcher/`):
  - Instant `⌥Tab` cycling through active user windows with app icons, titles, and keyboard navigation (`⇥`, `⇧⇥`, `↩`, `Esc`).
  - Zero-latency activation via `NSRunningApplication.activate()`.
* **Vorssaint Radial Quick Menu** (`Sources/NewtonApp/Radial/`):
  - 8-slice mouse-centered radial action wheel summoned via `⌃⌥R` for window snapping, focus shield, keep awake, mic mute, color sampler, clean mode, pin, and turbo sweep.
* **Accidental ⌘Q / ⌘W Quit Protection System** (`Sources/NewtonCore/QuitProtection/`, `Sources/NewtonApp/QuitProtection/`):
  - Intercepts accidental termination shortcuts for critical developer apps (Cursor, VS Code, Xcode, Terminal, iTerm2, Chrome, Safari).
  - Bottom-center glass HUD overlay (`.statusBar` level) showing animated progress bar: *"Hold ⌘Q to Quit <AppName>"* (0.8s hold).
* **MacBook Keyboard Cleaning Mode** (`Sources/NewtonCore/CleaningMode/`, `Sources/NewtonApp/CleaningMode/`):
  - Swallows keyboard events so users can safely wipe down screen, trackpad, and keyboard without typing garbage.
  - Dual unlock: Press `Escape` 5 times in a row, or click mouse "Unlock Keyboard" button.
* **Floating Screenshot & Moment Pinning Engine** (`Sources/NewtonCore/Pins/`, `Sources/NewtonApp/Pins/`):
  - 1-Click floating pin of any screen capture or Screenpipe OCR moment above all windows (`.floating` level) with opacity cycling and drag.
* **Per-App Audio Volume & Sound Priority Mixer** (`Sources/NewtonCore/Audio/PerAppAudioMixerEngine.swift`):
  - Process-level audio inspection, volume sliders, and mute toggles directly in the popover panel.
* **Vorssaint Dynamic Notch & Island** (`Sources/NewtonApp/Notch/`):
  - Multi-wing liquid-glass drawer hugging the camera housing with fluid spring physics (`.spring(response: 0.28, dampingFraction: 0.8)`).
  - Wings: Git & Orbit, AI Quota ring, Music Equalizer & Flow, Scratchpad (`~/.newton_scratchpad.md`), Clipboard History (10 items), and Quick Snap bar.
* **⌘K Command Palette** (`Sources/NewtonApp/CommandBar/`):
  - Floating search palette (`⌥Space` or `⌘K`) searching across:
    - Running application windows (instant switch)
    - Development repositories and active git branches
    - Listening TCP ports (inspect & kill)
    - Screenpipe OCR moments (search text and copy)
    - Dynamic inline math evaluation (`2+2*3` -> `= 8`) and unit conversions (`100 km to mi`).
* **Floating Drop Shelf** (`Sources/NewtonApp/Shelf/`):
  - Screen-edge docked shelf (`⌥S`) for drag-and-drop staging of files, images, and text snippets.
* **Modular Settings Hub** (`Sources/NewtonApp/Settings/SettingsView.swift`):
  - 5-tab center: Feature Hub (1-click toggling of all modules), Shortcuts (hotkeys reference), Apple Silicon Power (package power, cycles, thermals), Quit & Clean Mode (⌘Q hold duration, protected apps, cleaning mode display), and Privacy & Storage.

---

### 2. 🔍 Screenpipe Local Intelligence & Automation Engines
* **On-Device Screen OCR & Frame Deduplication** (`Sources/NewtonCore/VisionCaptureEngine.swift`):
  - In-process `ScreenCaptureKit` + Apple `Vision.framework` OCR recognizing text every 4 seconds.
  - **Perceptual Frame Hashing**: Compares fast image hashes between frames; skips Vision OCR when screen content is static, strictly enforcing **0% idle CPU**.
  - Direct persistence into `EventStore` actor with SQLite FTS5 full-text indexing.
* **On-Device Audio & Meeting Speech Transcription** (`Sources/NewtonCore/Audio/SpeechTranscriptionEngine.swift`):
  - 100% on-device speech-to-text using native Apple Speech (`SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`) and `AVAudioEngine`.
  - Strictly **0.0 KB cloud data egress**.
  - Pure offline semantic analyzer extracting commitments, deadlines, and TODOs from live audio.
* **Screenpipe Deep Pipes Suite** (`Sources/NewtonCore/Pipes/`, `Sources/NewtonApp/Pipes/PipesStudioView.swift`):
  - **Missed To-Dos Radar** (`synthesizeMissedToDos`): Scans recorded screen text and notes for unfulfilled commitments.
  - **Meeting Digest Synthesizer** (`synthesizeMeetingDigest`): Extracts key decisions, agreements, and next steps from meeting transcripts.
  - **Daily Engineering Standup** (`synthesizeStandup`): Automatically builds standup reports (`## Yesterday`, `## Today`, `## Blockers`) from commits and active dwell.
  - **Video-to-Code SOP Generator** (`generateSOP`): Converts observed workflows into step-by-step Standard Operating Procedures.
  - **Dedicated Pipes Studio**: 4-card interactive runner with instant live markdown preview, 1-click clipboard copy, and file export.

---

### 3. 🧠 Lumen Cognitive Attention & Financial Infrastructure
* **24-Hour Attention Time Machine** (`Sources/NewtonCore/TimeMachineEngine.swift`, `Sources/NewtonApp/TimeMachineScrubberView.swift`):
  - Discretizes the day into 288 5-minute frames with visual activity bars.
  - Replays active window titles, keystrokes, and git commits across the day.
* **Financial Runway & IRS Schedule-C Tax Engine** (`Sources/NewtonCore/FinancialRunwayEngine.swift`, `Sources/NewtonApp/Finance/`):
  - Schedule-C line item mapping: Line 18 (Software/SaaS), Line 22 (Hardware/Supplies), Line 24b (Business Meals 50%).
  - Live 28% tax savings estimator and monthly SaaS burn pacing.
  - **30-Day Renewal & Price Hike Radar**: Flags imminent charges (<= 3 days) and detects price hike increases.
* **6-Pillar iCloud Storage Optimizer Suite** (`Sources/NewtonCore/Storage/iCloudStorageOptimizer.swift`, `Sources/NewtonApp/Storage/GhostFileInspectorView.swift`):
  - Measures logical vs physical disk usage across iCloud targets (`NSURLUbiquitousItemDownloadingStatusKey`).
  - Visualizes cloud ghost ratios (dataless 0-byte files vs local physical bytes) with 1-click file eviction (`evictUbiquitousItem`).
  - **1-Click Master Turbo Sweep** (`WorkspaceModel.runMasterTurboSweep()`): Recursively sweeps `node_modules`, `.venv`, `.build`, and `target` directories via `DeveloperProjectTrimmer` in 1 pass.
* **Cognitive Flow & Audio Profiler** (`Sources/NewtonCore/Audio/AudioFlowProfilerEngine.swift`):
  - Reads Apple Music & Spotify now-playing track metadata via native non-blocking AppleScript.
  - Correlates audio playback with typing cadence (WPM) to compute 0-100 Cognitive Flow Scores.

---

### 4. 🗺️ Project Atlas & Developer Tooling
* **Project Atlas Scanner** (`Sources/NewtonCore/ProjectAtlasScanner.swift`):
  - Autonomously discovers and tracks git repositories in `~/Projects`, `~/repos`, `~/local/repos`, `~/welift_sandbox`.
  - Surfaces active branch, clean/dirty state, and last commit message.
* **Developer Port Manager** (`Sources/NewtonCore/Ports/PortManagerEngine.swift`, `Sources/NewtonApp/Ports/PortManagerView.swift`):
  - Inspects Darwin process table for TCP listening sockets (`lsof -iTCP -sTCP:LISTEN -n -P`).
  - Identifies active ports (3000, 8080, 5173), process names (`node`, `python3`, `vite`), PIDs, and listen addresses.
  - Safe POSIX signal termination (`SIGTERM` gentle kill, `SIGKILL -9` force kill).
* **Codex Rolling 5h Quota Monitor** (`Sources/NewtonCore/CodexQuotaReader.swift`):
  - Reads local advisory session rollout snapshots from `~/.codex/sessions/`.
  - Tracks primary rolling 5h quota, remaining percentage, and reset timestamps.

---

## ⚡ Global User Rules & Commands
- When the user says `run newton tests` or `test newton`, execute: `cd /Users/lucasdespot/newton && ./test.sh` (runs 129+ checks).
- When the user says `build newton`, execute: `cd /Users/lucasdespot/newton && ./build.sh` (compiles, packages, codesigns, and verifies receipt).
- When the user says `ship newton` or `run newton ship`, execute: `cd /Users/lucasdespot/newton && ./bin/ship.sh` (tests, auto-version-bump, build, commit, tag, push to GitHub, and mirror to iCloud).
- When the user says `newton audit` or `audit newton`, execute a comprehensive truth reconciliation audit across Newton, verifying live Darwin APIs, zero mock data, and 0% idle CPU enforcement.
- **Autonomous Memory Maintenance**: The agent must autonomously maintain `/Users/lucasdespot/newton/MEMORY.md`, `/Users/lucasdespot/NEWTON.md`, `/Users/lucasdespot/AGENTS.md`, and `/Users/lucasdespot/GEMINI.md` after any code modification, feature addition, or release.

---

## 🔢 Version Bumping Protocol
- Version authority: `/Users/lucasdespot/newton/version.txt`
- Current version: `0.1.10`
- Release tags: `v<major>.<minor>.<patch>` (e.g. `v0.1.10`)
- Releases are fully automated by `./bin/ship.sh` (`bin/release.py`), enforcing that all reviewed changes are committed before releasing, and pushing atomically to `tapchipswipe/newton` with tag verification and local iCloud Drive mirroring.

---

## 📁 Source File Directory Map

```text
/Users/lucasdespot/newton/
├── Package.swift                                      # Swift Package Manager manifest (Swift 6)
├── version.txt                                        # Authority for current version number
├── test.sh                                            # Automated test matrix runner (129+ checks)
├── build.sh                                           # Production compilation, codesigning & packaging
├── bin/
│   ├── ship.sh                                        # 1-Click Master Release Pipeline
│   ├── release.py                                     # Resumable atomic release engine
│   ├── toolchain.sh                                   # SDK resolver (MacOSX26.5.sdk)
│   ├── mirror.sh                                      # Local iCloud snapshot mirror
│   └── artifact.py                                    # Artifact hashing and receipt generation
├── Sources/
│   ├── CSQLite/                                       # Darwin SQLite modulemap shim
│   ├── NewtonCore/                                    # Headless Core Business Logic & Engines
│   │   ├── Audio/
│   │   │   ├── AudioFlowProfilerEngine.swift          # Music flow & WPM correlation
│   │   │   ├── PerAppAudioMixerEngine.swift           # Process-level volume attenuation & mute
│   │   │   └── SpeechTranscriptionEngine.swift        # Apple Speech on-device meeting transcription
│   │   ├── CleaningMode/
│   │   │   └── CleaningModeEngine.swift               # Keyboard event locking & 5x Esc unlock
│   │   ├── Hotkeys/
│   │   │   └── GlobalHotkeyEngine.swift               # Pure Carbon system-wide hotkeys
│   │   ├── Pipes/
│   │   │   └── PipeAutomationEngine.swift             # Standup, Missed To-Dos, Meeting Digest, SOPs
│   │   ├── Pins/
│   │   │   └── ScreenshotPinEngine.swift              # Desktop floating pin aspect ratio & opacity
│   │   ├── Ports/
│   │   │   └── PortManagerEngine.swift                # Listening TCP port scanner & killer
│   │   ├── QuitProtection/
│   │   │   └── QuitProtectionEngine.swift             # ⌘Q / ⌘W hold-to-quit interceptor & duration
│   │   ├── Storage/
│   │   │   └── iCloudStorageOptimizer.swift           # Cloud ghost ratios & file eviction
│   │   ├── Switcher/
│   │   │   └── WindowSwitcherEngine.swift             # Fast window switching & z-order capture
│   │   ├── WindowLayout/
│   │   │   └── WindowSnapEngine.swift                 # Pure AXUIElement window snapping
│   │   ├── AIScheduler.swift                          # Advisory AI scheduling policies
│   │   ├── CodexQuotaReader.swift                     # Rolling 5h quota snapshot parser
│   │   ├── CommandBarEngine.swift                     # Math evaluation & unit conversions
│   │   ├── DeveloperProjectTrimmer.swift              # node_modules / .venv bloat trimmer
│   │   ├── Event.swift                                # HistoryEvent & NewtonFeature models
│   │   ├── EventStore.swift                           # SQLite actor with FTS5 search
│   │   ├── FinancialRunwayEngine.swift                # IRS Schedule-C tax & renewal radar
│   │   ├── PowerPacingEngine.swift                    # Apple Silicon SoC Watts & battery runway
│   │   ├── ProjectAtlasScanner.swift                  # Local git repository scanner
│   │   ├── TimeMachineEngine.swift                    # 288 5-minute frame aggregator
│   │   └── VisionCaptureEngine.swift                  # Frame hash deduplication & Vision OCR
│   ├── NewtonWorkspace/                               # MainActor State & Lifecycle Orchestration
│   │   ├── WorkspaceModel.swift                       # Primary observable app state & feature toggles
│   │   └── FeatureServices.swift                      # Service protocols & lazy adapters
│   └── NewtonApp/                                     # Native macOS Liquid-Glass UI & Overlays
│       ├── CleaningMode/                              # Fullscreen blackout & translucent cleaning HUD
│       ├── CommandBar/                                # ⌘K search palette & window launcher
│       ├── Finance/                                   # Financial Runway & Schedule-C Tax View
│       ├── HUD/                                       # Desktop Floating Glass HUD
│       ├── MenuPanel/                                 # Vorssaint 9-Section Popover Panel
│       ├── Notch/                                     # Dynamic Notch Island & multi-wing drawer
│       ├── Pins/                                      # Floating screenshot & OCR moment pin window
│       ├── Pipes/                                     # Screenpipe Automation Pipes Studio
│       ├── Ports/                                     # Developer Port Manager Studio
│       ├── QuitProtection/                            # ⌘Q / ⌘W hold-to-quit animated progress HUD
│       ├── Radial/                                    # 8-slice mouse-centered radial action wheel
│       ├── Settings/                                  # Modular Feature Hub & Settings View
│       ├── Shelf/                                     # Screen-edge floating drop shelf
│       ├── StatusItem/                                # Option A Menu Bar Controller
│       ├── Storage/                                   # iCloud Ghost File Inspector & Turbo Sweep
│       ├── Switcher/                                  # Vorssaint ⌥Tab fast window switcher UI
│       ├── Timeline/                                  # Visual OCR Frame Timeline View
│       ├── NewtonApp.swift                            # Accessory app entry point & notification wiring
│       ├── Theme.swift                                # Liquid glass backdrops & styling
│       ├── TimeMachineScrubberView.swift              # 24-hour attention scrubber view
│       └── WorkspaceView.swift                        # Full workspace browser scene
└── Tests/
    ├── NewtonCoreTests/                               # Unit & regression tests for Core engines
    │   ├── VorssaintSuperAppTests.swift               # Super-app overlay & speech tests
    │   └── VorssaintPhase3Tests.swift                 # Quit protection, cleaning mode, pins, mixer
    ├── NewtonWorkspaceTests/                          # Concurrency, store & workspace lifecycle tests
    └── ToolingTests/                                  # Python delivery & release tests
```

---

## 🎯 Future Work & Roadmap Vectors
1. **Live Mic & System Audio Mix:** Combine microphone input with system audio loopback for full two-sided meeting capture.
2. **Dynamic Island iOS Companion:** Pair with LumenMobile via local Bonjour mesh to mirror active branch and live Mac wattage to iPhone Dynamic Island.
3. **Smart Worktree Staging:** Expand manual agent runner to perform automated diff reviews and 1-click git staging.
4. **Offline Semantic SLM Summary:** Run Apple Neural Engine quantized small language model for 100% offline daily journal synthesis.
