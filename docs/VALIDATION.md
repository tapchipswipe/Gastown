# Historical v0.1.0 validation — 2026-10-24

Current v0.1.1 evidence supersedes this baseline: see `audits/2026-10-24-findings.md`.

## Verified locally

- `./test.sh`: nine Swift Testing tests pass across two suites.
- Database: 100 concurrent actor writes retained; repeated stable IDs do not duplicate rows or full-text results; reopened file remains searchable; deletion updates the index; literal user query escaping and result bounds checked.
- Lumen adapter: malformed lines skipped, stable canonical JSON identity independent of key order, expected title/source parsed. Uses synthetic fixtures in isolated tests, never real user history.
- Screenpipe adapter: OCR/audio fixture decoding, missing-timestamp omission and unexpected-envelope rejection. No live Screenpipe history requested.
- `./build.sh`: optimized native binary, app bundle, generated original icon, ad-hoc codesign, strict signature verification, ZIP packaging.
- Running native UI: Mission Control shows zero events, all three feature switches off, recording off. Work History shows its empty state. Dashboard screenshot visually inspected.
- Keep-awake lifecycle: UI toggle on created a `Newton Keep Awake` assertion visible in `pmset -g assertions`; toggle off removed that assertion. Other applications' assertions were left alone.
- Shell syntax: build/test/release/mirror/toolchain scripts checked with `bash -n`.

## Not established

- Live app-switch collection has not been exercised against the user's actual history; its notification-based implementation is present.
- Live Screenpipe service compatibility/auth, source Lumen file intake through the native picker, prolonged capture, power use, battery/runtime benchmarks and multi-Mac compatibility remain unverified.
- App is locally ad-hoc signed, not notarized. No installer, public GitHub release or automatic login agent.
- CI workflow is configured; a local pass is not proof of hosted CI success.
- iCloud source/artifact copies do not prove server upload.

## Toolchain

Apple Swift 6.4 command-line tools, Swift 6 language mode, macOS 26.5 SDK selected locally, macOS 14 deployment target. Default preview macOS 27 SDK references a missing SwiftUI macro plugin. Swift Testing also required explicit discovery of the installed TestingMacros library. Test/build scripts encode these local workarounds without global toolchain changes.
