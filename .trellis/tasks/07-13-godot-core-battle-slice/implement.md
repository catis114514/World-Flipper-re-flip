# Core Battle Slice Implementation Plan

## 1. Development Baseline

- [x] Load `trellis-before-dev` and the relevant frontend/backend spec indexes before editing implementation files.
- [x] Detect or install a user-local stable Godot 4.x toolchain on `wf-vm`; record the exact version.
- [x] Add `godot/` project structure and a headless smoke command.
- [x] Add a native headless test runner under `godot/tests/` and verify an intentionally failing test fails before implementation.

Validation:

```bash
godot --headless --path godot --quit
godot --headless --path godot --script res://tests/run_tests.gd
```

## 2. Save and Domain Foundation

- [x] Write failing tests for predefined-profile creation, save round-trip, schema version rejection/migration, atomic recovery, and reward idempotency.
- [x] Implement typed profile, party, inventory/currency, quest-progress, active-run, and applied-result models.
- [x] Implement `SaveRepository` and `LocalProfileService` with no raw save-dictionary access from presentation code.

Rollback point: retain only the project/test scaffold if save contracts fail review.

## 3. CN Fixture Conversion

- [x] Select one small CN main quest using CN master/client evidence and document its IDs/source hashes.
- [x] Write failing loader/validation tests for missing references, duplicate IDs, and malformed values.
- [x] Create a minimal offline conversion script and checked fixture for quest, party, character, zone, enemy, action/ability subset, and rewards.
- [x] Implement `StaticContentRepository` over the converted fixture.

Validation: fixture reference graph has no missing identifiers and does not require network or original hashed-path lookup at runtime.

## 4. Fixed-Step Physics Core

- [x] Translate reference math/update-order tests for integration, collision, constraints, and flipper transitions.
- [x] Implement isolated vector/math helpers and fixed-step clock.
- [x] Port the minimum `World`/body/shape/contact/constraint behavior required by the fixture.
- [x] Port flipper pressed/released motion and hit response.
- [x] Add deterministic snapshot/golden tests.

Rollback point: simulation remains independent of Godot nodes; presentation work does not start until golden tests pass.

## 5. Battle Rules and Session

- [x] Write failing tests for session start validation, active-run creation, damage/HP, clear/fail, abort, recovery, and exactly-once result application.
- [x] Implement party-to-battle snapshot construction equivalent to the required `BattleSource` fields.
- [x] Implement the minimum enemy/action/ability subset used by the chosen fixture.
- [x] Implement `BattleSessionService`, reward calculation, quest progress, and save transaction.

## 6. Functional Presentation

- [x] Add profile/party/quest selection scene using the predefined content.
- [x] Add battle scene that renders simulation snapshots and translates keyboard/mouse/touch-compatible input.
- [x] Add minimal HUD, clear/fail result view, and return-to-selection flow.
- [x] Keep rendering and node lifecycle outside authoritative simulation/domain state.

## 7. Full Offline Verification

- [x] Run all headless tests twice from a clean user-data test directory.
- [x] Verify network independence by running with network unavailable and searching runtime code for HTTP/CDN/Node/AIR dependencies.
- [x] Verify clear reward persists once across restart and interrupted-run recovery cannot duplicate it.
- [ ] Launch the Windows project interactively and complete the selected quest.
- [x] Run `trellis-check`, perform code review, update relevant specs, and record remaining parity gaps before expanding scope.

## Latest Verification (2026-07-21)

- Python converter tests: 2 passed. The damaged VM APK input was replaced from the read-only host source after SHA-256 and ZIP integrity verification.
- Godot headless suite: 366 assertions passed twice from clean user-data directories.
- Godot editor scan and 120-frame main-scene smoke passed.
- Runtime static audit found no network, AIR/SWF/ANE, Node.js, external-process, native-extension, debug-log, host-path, or UTF-8 replacement-character dependency.
- Windows debug and release exports succeeded inside `wf-vm`; interactive Windows playthrough remains pending.
- Terrain runtime adapter now includes validated fallback segments and p1/p2/p3 markers, deterministic segment collision, marker-driven boss movement, and functional rendering. Exact recovered terrain and interactive Windows verification remain pending.

## Latest Verification (2026-07-23, second converted battle)

- `convert_core_fixture.py` accepts `--quest-id`; `1001002` remains byte-identical and `1002001` now has a checked schema-2 fixture.
- Added explicit `slango`/`spirit` adapters, complete 31-state Spirit boss conversion, level-threshold `charge1=240`, five checked enemy Action DSL assets, and fixed-point funnel dependency validation.
- `BattleSimulation` now owns multiple serial-tagged enemy instances and one-active-enemy-per-emitter scheduling. Quest `1002001` runs independent 60/120-frame emitters, a 20-kill objective, then the 18295-HP Spirit boss.
- Delayed player events snapshot enemy/funnel serials; owner teardown removes owned projectiles/funnels; poison/delayed kills retain the complete emitter cooldown; terminal events cannot mutate cleared/failed state.
- Main progression now runs `1001001 story -> 1001002 battle -> 1001003 story -> 1002001 battle`; unsupported `1002002` blocks explicitly while replay selects the latest cleared converted fixture.
- Verification: core converter 5/5; offline catalog determinism unchanged; server-security and gacha-position regressions pass; Godot 518 assertions twice from clean data roots; two-battle scene flow, editor scan, and 120-frame main-scene smoke pass.
- Exact terrain/spawn animation, broad enemy adapter coverage, original visual assets, and interactive Windows verification remain pending.

## Risky Areas

- Physics update order and numeric differences between ActionScript/Haxe and GDScript.
- Hidden action/ability dependencies referenced by the selected quest.
- CN fixture extraction from ordered-map/hashed resources.
- Save corruption during schema evolution.
- Presentation code accidentally becoming authoritative gameplay state.
