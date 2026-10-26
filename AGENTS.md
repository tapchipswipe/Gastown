# Newton

Read MEMORY.md before work, then CONTEXT.md for the detailed current-state handoff. This is an original native macOS app combining utilities, local work history, and a personal dashboard. The user's priority is balanced across all three.

- Swift 6 language mode; macOS 14+; explicit @MainActor for UI/services and an actor for database access. No global default actor isolation.
- Build: ./build.sh. Tests: ./test.sh. Release: ./bin/ship.sh.
- Capture is opt-in. Start with all features off. Stopping a feature must release its resources. No screenshot, key, clipboard or audio capture added without visible user controls.
- No guessed metrics, fake health scores, sample history, hidden network uploads or periodic whole-history recomputation.
- Screenpipe is an optional separately running loopback service. Do not vendor its current commercially restricted source. Vorssaint code cannot be copied without a deliberate GPL distribution decision. Keep provenance in docs/SOURCES.md.
- Never import private Lumen history automatically. Use a user-selected file and stable IDs.
- Keep .git/dependency caches and databases out of iCloud. Mirror committed source/docs/artifact using bin/mirror.sh; a local copy does not prove server upload.
- Update MEMORY.md after code/config changes and maintain the global AGENTS.md/GEMINI.md checkpoint. Do not change Lumen's files or versions for Newton changes.

## Hardening contract
- Read docs/audits/2026-10-24-findings.md before changing concurrency/storage/delivery boundaries. Tests run Swift Testing plus Python delivery fixtures.
- Schema version 2; migrations must validate before committing. Do not downgrade unknown versions or reset corrupt user data.
- No per-event full-history rebuild. Preserve accepted events when disabling capture; retain write failures for retry. Respect query/request generations and import/deletion exclusivity.
- Use staged build outputs and build/receipt.json; do not mirror stale ZIPs. Release resume uses .git/newton-release.json. Do not bypass locks without checking their owners.

## Current expansion review
- Before extending v0.1.2 AI, workflow, project or mobile/idea integrations, read docs/reviews/2026-10-24-gemini-review.md and CONTEXT §14. The original review is historical; stabilization status and regressions are in CONTEXT §15 and docs/reviews/2026-10-24-v013-stabilization.md. Preserve concurrent Gemini edits. Unattended execution stays disabled until a separately authorized integration/soak milestone.

## v0.1.6 daily-use contract
- Read CONTEXT §16 and docs/reviews/2026-10-24-v016-daily-tools.md first. Historical v0.1.4/5 feature/metric claims are superseded.
- Daily range queries require explicit completeness; preserve DST elapsed frames, all observations and deterministic ID ties. No page/filter fallback or inferred keystroke/focus/productivity/meeting metrics.
- Separate opt-in experimental Screen OCR and external Screenpipe. All capture starts off; stop/lock/sleep/deletion/shutdown invalidate callbacks. Drain accepted writes. No persisted screenshots.
- Manual Codex/Gemini runs only; committed bounded context, owned cancellation through verification. Dual unavailable. Quota advisory; no unattended jobs or morning-capacity guarantee. Tests use fake executables and injected capture; real integrations/replay require a separate explicit session.
- Power unavailable stays optional; SoC watts unavailable. Cleanup accepts only current-scan unchanged canonical/identity-checked candidates. Keep descriptor-relative no-follow removal and per-directory outcomes; cancellation cannot roll back a deletion. Review paths before confirmation; estimated sizes are not measured free-space gains.
