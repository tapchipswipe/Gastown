# Newton v0.1.7 Super-App Merger Verification & Architecture Report

Date: October 24, 2026
Release Tag: `v0.1.7`
Source Commit: `fd22ae8b73814a47488573439ad3dd3f444083b1`
Artifact SHA256: `2127b9b3908efde2a536bceb56d1e969f4bd68c0cd7f0a05d79128f26f269dc5`

---

## 🏛️ Executive Summary

Newton v0.1.7 completes the foundational merger of **Vorssaint**, **Screenpipe**, and **Lumen** into a singular, high-performance macOS super-app.

All 3 systems have been synthesized directly into native Swift 6 code with zero external daemon requirements (0% idle polling), compiling into a unified desktop studio with 4 floating glass overlay panels.

---

## 🪟 Implemented Systems Map

### 1. 🖥️ Desktop Overlays (Vorssaint & Lumen)
- **Vorssaint Dynamic Notch & Island** (`Sources/NewtonApp/Notch/`):
  - Non-activating, borderless `NSPanel` (`.statusBar` + 1 level, `canJoinAllSpaces`, `fullScreenAuxiliary`).
  - Auto-detects physical MacBook display notch geometry or floats as an island on external displays.
  - Interactive compact pill expands into a 3-column drawer:
    - **Dwell & Git Wing**: Active repo name, branch, clean/dirty badge, last commit message.
    - **AI Foundry Status Wing**: Live agent phase indicator and 5h rolling quota ring.
    - **Now Playing Strip**: Animated music equalizer bars and playback controls.
    - **Quick Scratchpad**: Local auto-saving markdown editor (`~/.newton_scratchpad.md`).
    - **Quick Tools**: Eyedropper screen color sampler, Mic Mute toggle, Keep-Awake toggle, and ⌘K trigger.
- **Vorssaint ⌘K Command Palette** (`Sources/NewtonApp/CommandBar/`):
  - Centered floating glass palette (`.floating` level) triggered globally via `⌘K`.
  - On-device inline math evaluator (`2 + 2 * 3` -> `= 8`, division, multiplication).
  - On-device unit converter (`100 km to mi`, `0 c to f`, `2048 mb to gb`, `10 kg to lbs`).
  - Quick action launcher (Standup pipe, developer bloat trimmer, keep awake, eyedropper).
  - Quick project switcher across tracked repositories.
- **Vorssaint Floating Drop Shelf** (`Sources/NewtonApp/Shelf/`):
  - Screen-edge docked sliding drawer (`.floating` level, 304px wide).
  - Drag-and-drop staging tray for files, images, and text snippets.
  - 1-click clipboard paste and cross-application file dragging.
- **Lumen Desktop Glass HUD** (`Sources/NewtonApp/HUD/`):
  - Draggable glassmorphic desktop overlay (`.floating` level).
  - Displays live active focus minutes, real-time typing cadence (keystrokes), active branch, and 1-click **Focus Shield** distraction blocker.

### 2. 🪟 Newton Studio (Vorssaint Liquid Glass Theme)
- **Vorssaint Design System** (`Sources/NewtonApp/Theme.swift`):
  - `Theme.spaceGradient` (near-black gradient), `PanelSurface` (baseFill, cardFill, controlFill, elevated borders), `HUDBackdrop` (layer-clipped visual effect blur), and `.panelCard(cornerRadius:)` modifier.
  - Upgraded all cards and containers across Overview, Work History, Atlas, Utilities, and Connections away from stock macOS `GroupBox`es into fluid glass cards.
- **Screenpipe Visual Frame Timeline** (`Sources/NewtonApp/Timeline/VisualTimelineView.swift`):
  - Interactive visual scrubber with on-device OCR text search and highlight markers.
  - Side-by-side OCR text extractor with 1-click clipboard copy.
- **Screenpipe Pipe Automation Engine** (`Sources/NewtonCore/Pipes/PipeAutomationEngine.swift`):
  - **Daily Standup Synthesizer**: Transforms daily commits, active window dwell, and errors into copy-paste-ready engineering standup reports (`## Yesterday`, `## Today`, `## Blockers`).
  - **Video-to-Code SOP Generator**: Converts recorded app switches and screen moments into step-by-step Standard Operating Procedures.
- **Lumen Financial Runway & IRS Schedule-C Tax Engine** (`Sources/NewtonCore/FinancialRunwayEngine.swift`, `Sources/NewtonApp/Finance/FinancialRunwayView.swift`):
  - Line 18 (Software/SaaS), Line 22 (Hardware), Line 24b (Business Meals 50%), Line 17 (Legal/Prof), Line 8 (Advertising).
  - 28% estimated blended tax savings calculator.
  - 30-Day predictive subscription renewal radar with imminent charge flags (<= 3 days) and stealth price hike alerts.

---

## 🧪 Verification Matrix

- **NewtonCore Tests**: 94 tests in 24 suites (PASSED).
- **NewtonWorkspace Tests**: 36 tests in 10 suites (PASSED).
- **Python Tooling & Delivery Tests**: 12 tests (PASSED).
- **Total Automated Checks**: **142/142 tests passing 100%**.
- Production build via `./build.sh` verified with strict code signing and SHA256 receipt.
- Release delivery via `./bin/ship.sh`:
  - Tag: `v0.1.7`
  - Push: Verified on GitHub `origin/main`
  - Mirror: Verified local iCloud Drive snapshot
