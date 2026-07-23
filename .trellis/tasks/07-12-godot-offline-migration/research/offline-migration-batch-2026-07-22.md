# Offline Migration Batch — 2026-07-22

## Delivered

- Generated deterministic schema-2 offline catalog from CN sources:
  - 12 main chapters and 139 main stage nodes, preserving CN multiplied IDs and predecessor graph
  - 419 main quests (197 story, 221 battle, 1 special battle)
  - 505 characters
  - 436 equipments
  - 584 CN banner definitions
  - 581 server-projected reward pools, explicitly distinguished from CN banner metadata
- Extended local profile to schema 6 with stamina anchor, rank points, RNG state, operation ledger, and inbox.
- Implemented staged local operations for stamina, party, story progression, gacha and inbox rewards.
- Home flow now resolves the original client order (latest released chapter -> latest viewable uncleared stage node -> first viewable uncleared quest): `1001001 story -> 1001002 battle -> 1001003 story`; unsupported `1002001` blocks explicitly and keeps `1001002` replayable.
- Added touch flippers, three touch skill buttons, CN bundled font, leader upgrade and compatible-party rotation.
- Added fixed-step Fever duration, movement-based skill charging, outhole relaunch fallback, projectile hit-window handling, and reference-party HP damage scaling.
- A fixed normal-input replay now clears the canonical quest with enemy actions enabled and without teleporting the ball.
- Hardened the compatibility server: random viewer sessions, authenticated load lookup, no account-1 fallback, reflected-XSS removal, invalid-JSON 400, explicit missing-player response, loopback default.

## Explicit non-parity / unavailable inputs

- Only `1001002` has a complete validated battle graph. The converter remains specialized to the recovered slango field/state/action graph; other battle quests are cataloged but not falsely marked playable.
- Original terrain collision AMF3, most CN CDN images/audio, and `.parts/.frame/.movie/.timeline` animation assets are unavailable in directly consumable form. The arena, outhole, some enemy timing, skill distance coefficient and presentation remain documented adapters.
- The 581 reward pools are a server projection. CN master has 584 banner metadata rows; the missing three projected holiday pools are retained in metadata with `has_projected_pool=false`.
- Android export is not validated because the VM has no Android SDK/JDK configuration. Windows release and native Linux headless runtime are validated.

## Quality evidence

- `godot/tools/test_convert_core_fixture.py`: 2/2
- `godot/tools/test_convert_offline_catalogs.py`: deterministic
- `scripts/test_server_security_fixes.py`: PASS
- `scripts/test_gacha_movie_selection.py`: all positions statistically unbiased
- Godot headless: two consecutive full passes
- Main scene story/battle/replay smoke: PASS
- Editor scan and native main-scene smoke: PASS
- Windows release exported with SHA-256 recorded in `docs/status/test-progress.md`

## 2026-07-23 progression follow-up

- `QuestProgression` now evaluates stage-node predecessors, quest clear prerequisites, release timestamps, and owned-character visibility conditions instead of globally sorting quest rows.
- `OfflineCatalogRepository` validates the complete chapter/stage/quest reference graph and rejects missing predecessors or quest references before exposing any catalog state.
- Godot headless suite increased to 457 assertions; catalog determinism hash is `ab9bfdbcd0600e752a31e2fed8d5705161608329964c2c7ca448de519e2a6ab6`.

## 2026-07-23 second-battle follow-up

- The earlier `1002001` block is superseded: `追蘑菇1` now has a checked fixture and is playable after `1001003`.
- The converter accepts `--quest-id` and uses explicit `slango`/`spirit` adapters; unknown enemy masters still fail closed.
- Battle runtime supports one active enemy per emitter with independent serial/state/cooldown ownership. Quest `1002001` runs concurrent 60-frame `slango` and 120-frame `spirit` emitters, then the 31-state Spirit boss.
- Progress now blocks at unconverted `1002002`; replay selects the latest cleared converted quest.
- Current gate: core converter 5/5, Godot 518 assertions twice, two-battle scene flow, normal-input replay for both fixtures, editor scan, and 120-frame smoke.
