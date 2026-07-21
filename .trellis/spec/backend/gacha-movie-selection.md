# Gacha Movie Selection Contract

## 1. Scope / Trigger

Use this contract whenever the CN gacha emulator or the future offline Godot gacha selects a `movie_id`, seed, or special ball-movie outcome. The client entry animation, seed-driven `moviePlayable` result, and character rarity are separate concepts and must not be collapsed into one flag.

## 2. Signatures

```ts
SeedValidator.getSeed(
  movieId: string,
  rarity: number,
  pool: number[],
  characterId: number,
  drawIndex?: number,
  naturalPlayRate?: number
): number

naturalPlayRate = clamp(1 - MOVIE_CONFIGS[movieId].threshold.playMovie, 0, 1)
```

The current canonical rates are approximately:

| Movie | Special movie rate |
|---|---:|
| `normal` | 0.100479 |
| `fes` | 0.100502 |
| `normal_guarantee` | 0.070061 |
| `fes_guarantee` | 0.100502 |
| `rarity_5_guarantee` | no physics movie |

## 3. Contracts

- Every draw position uses the same movie-specific probability. Position zero has no special-rate override.
- The original client always enters the base ball-movie flow for `drawIndex == 0`; this does not imply `moviePlayable == true`.
- A special seed must come from client-confirmed `play=1` evidence: `verifiedPool` or a compatible tagged `playPool` entry.
- A normal outcome should use a rarity-compatible `confirmPool` seed when available.
- The server chooses `movie_id` first, then derives the probability from that movie configuration.
- `rarity_5_guarantee` skips physics but still consumes one response position and increments `drawIndex`.
- Client ten-pull presentation ordering, including its 6/7 visual swap, is presentation behavior and must not change server probability by position.
- Seed selection and character rarity selection are independent. The tenth-pull rarity guarantee does not imply a special ball movie.

## 4. Validation & Error Matrix

| Condition | Required behavior |
|---|---|
| Missing movie configuration | fall back to `normal` configuration |
| Threshold below 0 or above 1 | clamp the derived rate to `[0, 1]` |
| No compatible play seed | select a normal/confirmed seed; never force an unrelated rarity |
| No compatible confirmed seed | continue through pending/unknown fallback with diagnostics |
| First draw | use the same special rate as every other position |
| `rarity_5_guarantee` | skip physics, append result, increment index exactly once |
| Reused seed in one multi-draw | exclude through `sentSeeds` |
| Seed evidence disagrees with client beacon | client PLAY/C3032 evidence wins and the pool is updated |

## 5. Good / Base / Bad Cases

- Good: ten-pull simulations converge to the configured rate at every position, with no first/seventh bias.
- Base: a movie has sparse verified play seeds, so special outcomes are less diverse but retain the correct probability when candidates exist.
- Bad: forcing position zero into `play=1`, using a fixed seventh-position branch, confusing the tenth-pull rarity guarantee with movie playback, or failing to advance the response index on a skipped-physics draw.

## 6. Tests Required

- Static regression: the natural-mode block contains no `drawIndex === 0` or `isFirst` special selection.
- Source regression: `gacha.ts` passes the derived movie rate into `getSeed`.
- Position distribution: seeded Monte Carlo covers all ten positions for every movie configuration and rejects first-position bias.
- Pool regression: natural mode accepts both verified and tagged client-confirmed play seeds.
- Data regression: every reachable movie/rarity combination has at least one verified play seed.
- Skip regression: `rarity_5_guarantee` increments `drawIndex` before `continue`.
- TypeScript syntax parsing for `seed-validator.ts` and `gacha.ts`.
- Integration capture: compare one `/gacha/exec` `draw[]` response with client PLAY beacons and displayed positions.

## 7. Wrong vs Correct

### Wrong

```ts
if (drawIndex === 0) {
  return randomVerifiedPlaySeed();
}
```

This confuses "the client cannot skip the first base movie" with "the first seed must trigger the special movie."

### Correct

```ts
const playRate = clamp(1 - movieConfig.threshold.playMovie, 0, 1);
if (playCandidates.length > 0 && Math.random() < playRate) {
  return random(playCandidates);
}
return random(normalCandidates);
```

