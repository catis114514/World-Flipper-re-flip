# Offline Migration Batch — 2026-07-22

## Delivered

- Generated deterministic schema-1 offline catalog from CN sources:
  - 419 main quests (197 story, 221 battle, 1 special battle)
  - 505 characters
  - 436 equipments
  - 584 CN banner definitions
  - 581 server-projected reward pools, explicitly distinguished from CN banner metadata
- Extended local profile to schema 6 with stamina anchor, rank points, RNG state, operation ledger, and inbox.
- Implemented staged local operations for stamina, party, story progression, gacha and inbox rewards.
- Home flow follows `1001001 story -> 1001002 battle -> 1001003 story`; unsupported `1002001` blocks explicitly and keeps `1001002` replayable.
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
