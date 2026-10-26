# ADR 0001 — Original native workspace with explicit adapters

Status: accepted for the v0.1.1 foundation; revisit only with a concrete feature or licensing decision.

## Context

The user's ambition combines Lumen's personal dashboard, Vorssaint's Mac utilities and Screenpipe's searchable work evidence. Their products have different workloads, event loops, storage models, platform coverage and reuse terms. Combining their repositories directly would not remove overlap or make the resulting lifecycle coherent.

## Decision

Build original Swift code for a native Mac workspace. Divide responsibility into NewtonCore (Sendable data and actor-owned persistence), NewtonWorkspace (injected main-actor lifecycle/orchestration), and NewtonApp (presentation and application delegate). Use system SQLite/FTS5 for indexed history, NSWorkspace notifications for the first opt-in activity feature and an IOKit assertion for the first utility.

Integrate Lumen only through user-selected metadata files. Integrate Screenpipe only through an explicit separately running loopback service. No upstream application code or binary is vendored at this checkpoint. Track upstream snapshots and rights in SOURCES.md. Keep privacy controls and service start/stop behavior explicit before adding capture breadth.

## Consequences

- A small functioning foundation can be tested and hardened independently.
- A shared shell does not imply upstream feature parity, a recorder, neural search or mobile support.
- Adapters can be replaced or expanded behind interfaces; they still require actual end-to-end compatibility evidence.
- Richer capture creates new storage/privacy and processing obligations; it is not a shortcut to better analytics.
- Newton does not inherit a public distribution license merely by using original code. Third-party reuse and distribution remain separate decisions.
- The relevant performance comparison is measured work, not language choice or feature count. Extra correctness checks may add cost.

## Evidence

See CONTEXT.md, the v0.1.1 audit and the passing macOS15/26 run linked there. A future change should update this ADR or create a new decision record rather than silently treating the repository as a source merger.
