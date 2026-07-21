# Bug Analysis: First Gacha Draw Forced Into Special Movie

Date: 2026-07-21

## 1. Root Cause Category

- Category: E - Implicit Assumption, with D - Test Coverage Gap.
- Specific cause: the client condition that prevents skipping the base ball movie at draw index zero was interpreted as a requirement that the first seed must have `moviePlayable=true`.
- The emulator therefore selected a client-verified `play=1` seed for position zero on every multi-draw.
- The incorrect interpretation was then recorded as completed behavior in protocol/status documentation, which made the regression look intentional.

## 2. Why Earlier Fixes Failed

1. The investigation focused on preventing C3032 rarity mismatches, so a known-safe playable seed looked preferable to behavioral fidelity.
2. `moviePlayable`, base movie visibility, character rarity guarantee, and ten-pull presentation order were treated as one concept.
3. No position-distribution test existed. Validation checked seed safety and rarity, not whether positions had equal special-movie probability.
4. Documentation repeated the implementation claim instead of citing the exact client branch: `!moviePlayable && drawIndex > 0` only skips later movies.

## 3. Prevention Mechanisms

| Priority | Mechanism | Specific action | Status |
|---|---|---|---|
| P0 | Architecture | Derive the special rate from each movie's `threshold.playMovie` | Done |
| P0 | Test coverage | Reject any `drawIndex === 0` special-seed override | Done |
| P0 | Test coverage | Monte Carlo all ten positions for every movie configuration | Done |
| P0 | Correctness | Increment `drawIndex` in the skipped-physics rarity-5 branch | Done |
| P1 | Documentation | Add the gacha movie selection code-spec | Done |
| P1 | Integration | Capture one real `draw[]` response with client PLAY beacons and displayed indices | Pending |
| P2 | Tooling | Add a full TypeScript test runner on `wf-vm` | Pending |

## 4. Systematic Expansion

- Similar issues: the fixed tenth-pull rarity guarantee must not be treated as a movie guarantee.
- Similar issues: the client's visual 6/7 slot swap must not affect server-side seed probabilities.
- Design improvement: keep four independent values in tests and APIs: result rarity, movie id, movie playable flag, and presentation index.
- Process improvement: claims of parity must cite the exact client branch and include a negative assertion for behavior that must not be forced.
- Data improvement: use both client-confirmed `verifiedPool` and compatible tagged `playPool` seeds as special candidates.

## 5. Knowledge Capture

- Updated `.trellis/spec/backend/gacha-movie-selection.md`.
- Updated backend spec index.
- Corrected `docs/status/test-progress.md`.
- Corrected `docs/protocol/gacha-c3032.md`.
- Corrected `docs/protocol/seed-verification.md`.
- Added `scripts/test_gacha_movie_selection.py`.

