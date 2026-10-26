# Newton — living state

## Identity
- Project: Newton, a balanced Mac utility/work-history/personal-dashboard app.
- Repository: https://github.com/tapchipswipe/newton (private initially).
- Local-authoritative path: /Users/lucasdespot/newton.
- Version: 0.1.1. Bundle ID: com.tapchipswipe.newton.
- First milestone: original native Swift 6 macOS app; no upstream source vendored.

## Architecture
- NewtonCore: EventStore actor owns SQLite/FTS5, stable HistoryEvent values, duplicate-safe Lumen JSONL importer, explicit loopback Screenpipe connector.
- NewtonWorkspace: injected service/repository orchestration, one batched ingestion worker, retryable pending events, request ownership, exclusive import/deletion and graceful quit. NewtonApp provides SwiftUI and NSApplicationDelegate lifecycle.
- All features off at launch. No screen/audio/key/clipboard capture. No cloud uploads. No automatic reading of Lumen or Screenpipe history.
- Database: ~/Library/Application Support/Newton/history.sqlite; directory 0700, no app encryption. Deletion is logical, not secure erasure.
- See docs/ARCHITECTURE.md for roadmap and docs/SOURCES.md for license/provenance boundaries.

## Build and delivery
- ./test.sh; ./build.sh; open build/Newton.app.
- ./bin/ship.sh requires a clean reviewed commit, tests, bumps patch, packages, commits/tags, atomically pushes and mirrors.
- Source and packaged app mirror: iCloud Drive/Projects/Newton, excluding Git/build caches/live data. Local copy does not prove upload.
- Current preview CLT's default macOS 27 SDK lacks SwiftUIMacros. Scripts prefer installed macOS 26.5 SDK; the installed TestingMacros library is loaded explicitly when present.

## Session — 2026-10-24
User requested new tapchipswipe/newton repository combining Lumen, Vorssaint and Screenpipe. User explicitly selected balanced utilities, work history and dashboard priority. Current Screenpipe source restricts competing/commercial use; Vorssaint is GPL. Initial app uses original code and a separate local-service adapter, not an unauthorized source merger. Original Lumen worktree left unchanged.

Validation: nine Swift Testing tests passed; release app packaged and strict codesign verified. Native UI checked with all features off and zero events. Keep-awake assertion creation/release verified using UI plus pmset. Live Screenpipe, real Lumen picker intake and prolonged app activity capture remain unverified. See docs/VALIDATION.md. First milestone does not include screen/audio recording, finance, hardware monitoring, window management or mobile parity.

## Initial delivery checkpoint (v0.1.0)
Initial source, architecture, roadmap and build pipeline are committed to the private GitHub repository. The working app is build/Newton.app with build/Newton.zip for transfer. A source/artifact mirror is written to iCloud Drive/Projects/Newton; server upload unverified. No source or settings in Lumen/Vorssaint/Screenpipe changed.

## Deep hardening audit — 2026-10-24 / v0.1.1
- User requested plan-then-execute auditing with no approval pauses. Plan and detailed findings: docs/audits/2026-10-24-{plan,findings}.md. This was a scoped repeated audit, not a claim of zero possible future flaws.
- Baseline reproductions showed NUL truncation/ID collision, silently ignored invalid timestamps, future-schema downgrade, duplicate list IDs and object-shaped identities. Storage now uses exact byte bindings, validated atomic inserts, schema-v2 migration, metadata counts, deterministic pagination and cancellable/budgeted search.
- Network receives a bounded stream, checks header/body sizes, disallows redirects/proxies/cookies, and uses explicit request identities. File intake is descriptor-based, bounded, cancellable, metadata-only and user selected.
- Activity queues batch up to 128; failed writes remain retryable, capture pauses on failure/capacity, accepted events drain before quit, and native resource wrappers release observers/power assertions. A 2,000-event burst used 16 writes and no hidden page refresh beyond startup.
- 48 Swift tests and 10 Python delivery tests pass locally. Fixtures cover migration/rollback, concurrent opening/writes/shutdown, stale callbacks/results, failure/retry, bounded HTTP, cancellation, paging and actual isolated notification adaptation. Delivery fixtures use disposable repos and reject signing/publication/mirror/push failures safely.
- Three local 10k-event release-binary samples per revision show similar query performance and slightly higher insertion cost (median 117.77→124.17 ms). No battery/CPU/soak claim; raw samples in docs/audits/2026-10-24-benchmarks.json.
- Build emits a source/version/binary/ZIP receipt and preserves prior outputs on failure. Release journal supports --resume; mirror publishes immutable commit/archive snapshots under iCloud Projects/Newton/snapshots and current.json. No server upload inference.
- Remaining: actual Screenpipe/user-file integration, multi-day capture/resource profiling, retention/encryption/backup recovery, notarization and future richer features. Original Lumen untouched. Hosted CI checks macOS15/26 separately from local results.

Native smoke receipt: protected local-only backup made before relaunch; both existing events retained after in-place schema2 migration, opt-in native capture persisted a new event, keep-awake assertion created/released, and quit worked after closing the workspace window. User's three switches restored on the new app. User history and its backup were excluded from GitHub/iCloud.

Hosted follow-up: the first macOS26 audit job passed. Hosted CI warned about the deprecated runtime in pinned v4 actions; verified official checkout v7.0.1 and upload-artifact v7.0.2 commit pins replace them. The CI-only follow-up retains the same v0.1.1 app build-input digest.

The first macOS15 hosted job exposed a Swift 6.1 compiler signal10 in the NSObject delegate's stored-property call to cross-module actor-isolated default arguments. Added an explicit live convenience initializer inside NewtonWorkspace and explicit delegate initialization; this is a compatibility fix, not a suppressed CI test. macOS26 had passed the original audit job.

Hosted second-pass follow-up: the Swift6.1 delegate fix passed macOS15. macOS26 then exposed an intermittent concurrent first-open WAL lock, despite prior local passes. Added bounded initialization-only BUSY/LOCKED retries (normal runtime busy timeout unchanged) and strengthened the opener stress fixture to eight fresh databases × eight simultaneous openers. This is a real race fix; the failing test was retained.

Additional lock hardening: preserve SQLite result codes/operation context, retry the initial schema read as well as journal-mode setup, and run integrity verification in one immediate transaction with the quick-check cursor closed before FTS validation. This removes a read-to-write lock-upgrade hazard in the verifier itself. Final stress uses 32 fresh databases × 8 concurrent openers; no failure is waived as a flaky test.

Targeted lock stress receipt: five consecutive repetitions passed after the final fix, exercising 1,280 concurrent opener/verification attempts across 160 fresh disposable databases. Full suite remains 48 Swift + 10 Python tests.

## Final verification receipt
- Code revision: `9414305063edc22a7d125f257a9322ac7ca164c3`. Both macOS15 and macOS26 hosted test/build/package jobs passed: https://github.com/tapchipswipe/newton/actions/runs/40117984162.
- Local build-input SHA-256: `fc029f284260fb0cad4c8b5c5524f10ea3d3d9e16c3179320d530e734522c359`. Subsequent checkpoint changes are documentation only and retain that exact build-input digest.
- Latest native app relaunched successfully, retained existing history, and restored the user's three feature switches. Protected backups remain local-only.
- Full local suite: 48 Swift + 10 Python tests. Five additional targeted stress repetitions passed. No further reproducible failure was found in the final exercised scope; live Screenpipe integration and multi-day resource/retention/recovery work remain explicit limits.
