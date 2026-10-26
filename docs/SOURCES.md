# Source boundaries

Newton is independently authored. No upstream application code or binary is vendored in this initial repository. Compatible data formats and a documented local HTTP endpoint are used for optional adapters.

| Reference | Audited snapshot | Boundary |
|---|---|---|
| tapchipswipe/lumen | GitHub 899ab95b0a9f1528b18df50e300f52bd590b7488; existing local worktree separately audited | User-selected JSONL import only; no original files changed |
| vorssaint/vorssaint-utils | 4f510c075bea4dc1d1724411ea38cf9b6d458b90 | Study modular utility lifecycle; no GPL source imported |
| screenpipe/screenpipe | 5d84243ab130270c951543846f87fdec367cf19a | Optional separately installed local service; no restricted source imported |

Vorssaint's audited source is GPL-3.0-or-later. Current Screenpipe source has a commercial license covering the current/later versions and preserves MIT terms for previously MIT-released versions. Any future code reuse needs a documented provenance and licensing decision. Merely publishing a private repository does not settle those questions. Newton's adapter is a technical integration, not a grant of rights to use Screenpipe in any particular deployment; the separate service remains subject to its own terms.

Original Newton code is not assigned a public open-source license in this initial private repository. Repository visibility and distribution license are separate decisions. Third-party Apple/system libraries and tooling retain their own terms.

Primary references:
- https://github.com/tapchipswipe/lumen
- https://github.com/vorssaint/vorssaint-utils/blob/4f510c075bea4dc1d1724411ea38cf9b6d458b90/LICENSE
- https://github.com/screenpipe/screenpipe/blob/5d84243ab130270c951543846f87fdec367cf19a/LICENSE.md
