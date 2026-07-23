# Journal - catis114514 (Part 1)

> AI development session journal
> Started: 2026-06-26

---

## 2026-07-14 - Godot core battle slice

- Recovered canonical CN quest `1001002` graph from `wf-assets-cn` 1.4.54 and the supplied 1.8.1 APK curve tables.
- Fixture schema 2 now records field/terrain hash, two zones, slango zako/boss, action DSL hashes, and exact HP calculations (148 / 13009).
- Terrain binary remains absent from the APK bootstrap bundle; runtime still uses documented fallback geometry and a representative first-zone enemy.
- Added deterministic converter golden tests and strengthened fixture graph validation.
- Bound results to active `run_id`, added stale-run regression, random persistent IDs, settlement retry UI, and normal-impact collision damage.
- Final checks: Python 2 tests, Godot 115 assertions twice, editor scan, headless smoke, and Windows debug export passed.

- Continued core slice: simulation now runs the complete two-zone objective skeleton (18 zakos, 60-frame respawns, boss, timeout/fail), removes inactive enemy bodies, exposes HUD progress, and aborts failed runs without rewards.

- Re-ran the final gate after controller/service fixes: converter tests passed (2), Godot passed 165 assertions twice, editor scan and main-scene smoke passed.
- Exported Windows debug and release builds only inside `wf-vm`; release artifact is 109077888 bytes with SHA-256 `dc2dfd97cec0ff4a7c89536b7795e16412fd5ad423f8c0fd0a8647f3f78b5e45`.
- Static runtime audit found no network/AIR/Node/external-process/native-extension dependency, no debug logging, host absolute paths, or UTF-8 corruption.
- Remaining core-slice work is party-to-battle snapshot construction, minimum action/ability execution, and an interactive Windows playthrough.

- Added the immutable Party → BattleSource snapshot boundary using canonical CN level-one data for 西微、水善、梅媞斯 (162 HP / 30 ATK total).
- Persisted the snapshot in `active_run`, passed it into `BattleSimulation`, and made deterministic collision damage scale from the snapshotted party ATK without changing the default-party baseline.
- Extended converter/fixture validation and tests for missing/malformed character definitions, snapshot immutability, session handoff, and attack scaling. Current gate: converter 2 tests; Godot 192 assertions twice; editor scan and headless smoke passed. Fixture SHA-256 `2e899c9a8f05b27056beaebe1d6db4ff3c2d3516cd3528fcc815901ee792566b`.
- Re-exported the updated Windows release in `wf-vm`: 109084848 bytes, SHA-256 `24bf492bcbade5df5150aba50a4311d1f66c91d92739f5256b026cd88227fce4`.

- Ported canonical enemy ATK curves (zako 19 / boss 30) and normalized all four quest Action DSL assets into deterministic projectile/funnel runtime records.
- Added `EnemyActionExecutor`, automatic per-enemy schedules, N-way/circle projectile movement, party HP damage, `party_defeated`, generic projectile rendering, HUD HP/bullet counts, and funnel spawn events.
- Added malformed runtime validation and action regressions. Current gate: converter 2 tests; Godot 213 assertions twice; editor scan and main-scene smoke passed. Fixture SHA-256 `45b0981185b3e939e9ff9939825481ec13a217839c3dc6388e2e7324f0eb4a92`.
- Re-exported the Action DSL runtime Windows release in `wf-vm`: 109098616 bytes, SHA-256 `08fd18a6e65f96c7108041bb9d4ec8cc5b9ce5215c9189dff2ef57b62ffa11b0`.

- Replaced the temporary Boss action cycle with the recovered 36-state `slango` chain; canonical fire states now invoke funnel, normal-shot, and skill DSL records. Only terrain-marker movement states retain explicit 90-frame adapters.
- Upgraded funnel spawn events into orbiting level-15 entities backed by canonical 132 HP / 23 ATK calculations and periodic zako-shot attacks; HUD/rendering expose active funnels.
- Current gate: converter 2 tests; Godot 231 assertions twice; editor scan and main-scene smoke passed. Fixture SHA-256 `00a3d535518413f1010a20c6a4c5bdbd48e98151cb1a0888d6bc5cef4bcff160`.
- Re-exported the state-machine/funnel Windows release in `wf-vm`: 109117368 bytes, SHA-256 `a0bc20a831844f6d2c647bdda906cc3b150ab4e6e520e04021fcc81a9ba490f1`.

- Added the typed fallback terrain runtime: deterministic circle-vs-segment collision, approaching-only impact contacts, validated `p1`/`p2`/`p3` markers, boss movement interpolation, and debug terrain rendering. Exact AMF3 geometry remains unrecovered and is not claimed as canonical.
- Current gate: converter 2 tests; Godot 246 assertions twice from clean data directories; editor scan, 120-frame smoke, and Windows release export passed. Fixture SHA-256 `3be1567416c0ccbd8fbd4e86d1b639f5f80b7a2ab2e583f1526977287dae86a3`. Release: 109120600 bytes, SHA-256 `7f556bafc597baf7ae559d15f56f04d67bdc60c20bcd5ca16bf58f5998c790e3`.
- Upgraded funnels from presentation-only dictionaries to damageable fixed-step entities. Each spawned funnel now owns its canonical 132 HP, a static collision body tagged by stable serial, independent collision damage, and ghost-free removal without advancing the boss objective. Funnel bodies are also removed on owner/zone cleanup, while presentation snapshots hide simulation object references.
- Verification: converter 2 tests; Godot 253 assertions twice from clean data directories; editor scan, 120-frame smoke, and Windows release export passed. Release: 109121704 bytes, SHA-256 `b34aadd9cbc194e79f59eda1ceab878da1bcbf38584f0d0b7f117094d75852a6`.
- Recovered the default CN party's level-1 skill masters and Action DSL evidence: 西微「精灵风暴」(530 gauge, 175 radius, 24-hit core, 0.5x), 水善「彷如紫水蛊毒之咒」(600 gauge, 200 radius, 10-hit core, 1.1666667x), and 梅媞斯「雷箭之雨」(490 gauge, 200 radius, 5-hit core, 4.9x).
- Party snapshots now own skill contracts. Battle runtime now tracks three gauges, direct-attack combo, explicit 9/15/39 Power Flip thresholds, one-impact Power Flip consumption, keyboard skill activation (1/2/3), gauge consumption, and deterministic skill damage. Exact DSL timing/effects/conditions and exact skill-point gain events remain marked adapter work rather than canonical parity.
- Verification: converter 2 tests; Godot 271 assertions twice; editor scan, 120-frame smoke, and Windows release export passed. Fixture SHA-256 `2d157a5e524edec6169a7c10dde481e5b952ab67f37c5a43e908aeebd0c0ab06`. Release: 109128776 bytes, SHA-256 `308e9a0149cda13012763adc42596618c846b202e4421d4d6e162f7e2c1ba69d`.
- Extended player skill conversion with recursive Action DSL `Wait` timing and `CreateCondition` payloads. Canonical delays are now retained: 西微 0 frames, 水善 3 frames, 梅媞斯 80 frames (nested 60+20). Recovered conditions include 480-frame Flying, 960-frame +0.8 AttackPoint, and 2400-frame Poison with raw strength 1500 / interval 1.
- Added a fixed-step player skill event queue and condition lifetimes. Flying toggles gravity, attack-up participates in direct/skill damage, poison is attached to the active enemy and ticks deterministically. The 60-frame poison tick unit remains explicitly marked as an adapter pending exact interval-unit recovery.
- Verification: converter 2 tests; Godot 288 assertions twice; editor scan, smoke, and Windows release export passed. Fixture SHA-256 `52d6a00d5ceaa4d379d84e8303ddd33c81cd80c28701dd5ea9b70646550e0706`. Release: 109132872 bytes, SHA-256 `2bf46b2baf7c67f8750639f6fe70112b077a5c20b1bb6d87256a880aebd2f4f5`.
- Decoded all ability rows referenced by the three default CN characters using `AbilityValues` field positions plus the generated instant/during content and trigger enums. The fixture now retains ability ID, row, unisonability, statue group, trigger/content codes and names, target, raw/scaled power, and trigger threshold.
- Default test-party ability levels are explicit in `battle_source_defaults` and immutable party snapshots carry active ability rows. The one-body combat adapter now applies supported passive `DirectDamage`, `SkillMax` direct-damage, and `PowerFlipDamageUpExtend` modifiers. Unsupported slayers, fever, resistance, heal, multiball, and additional-attack behaviors remain packaged but are not silently executed with guessed semantics.
- Verification: converter 2 tests; Godot 293 assertions twice; editor scan, smoke, and Windows release export passed. Fixture SHA-256 `e27d3788f62090cb847d16922dae581958becc750be9a4a12e0812f20b7b3d56`. Release: 109149960 bytes, SHA-256 `51716b76ec70c9371456c722994dca82c45e8f41b552e88390bb7fe866932f4d`.
- Extended the ability runtime with direct/skill condition slayers, the recovered DamageCount threshold for skill damage, skill-linked fixed heal, skill-linked fever gain, and SkillMax additional direct-attack extension. Direct-attack count and fever points are now explicit simulation state.
- `FixedHeal` and `AddFeverPoint` are currently connected to owner skill activation based on their statue-group/use context; this boundary remains documented as an adapter until the complete original ability gear dispatch is ported. Frozen/paralysis slayers consume explicit enemy condition state and do not activate generically.
- Verification: converter 2 tests; Godot 300 assertions twice; editor scan, smoke, and Windows release export passed. Release: 109151368 bytes, SHA-256 `08ab369bcaefa59d4aa263d50139fb2eddb54fb2fd31f0d7bcfaa50a7d199386`.
- Upgraded local saves to schema 2 with `character_progress`: level, EXP, per-ability levels, and weapon/soul equipment slots. Added deterministic v0→v1→v2 migration; legacy roster IDs are normalized from JSON numeric values before progress creation.
- `LocalProfileService` now owns character-level, ability-level, and equipment mutations, including owned-item checks. Battle snapshots consume profile-owned progression/equipment rather than fixture ability defaults and remain immutable after later edits.
- Level-dependent stats and equipment stat calculation are not fabricated: snapshots explicitly report that they still use level-one CN base stats until the original curve/board/weapon calculator is ported.
- Verification: converter 2 tests; Godot 318 assertions twice; editor scan, smoke, and Windows release export passed. Release: 109154136 bytes, SHA-256 `d047c3eaebc39b0b06a5e7df6afef89e45cfcfa347de3fd6ca015aa6d6d7da95`.
- Upgraded saves to schema 3 with evolution and limit-break state. Added v2→v3 migration and domain validation for level 1–100, evolution 0–2, and limit break 0–4.
- Recovered each default character's CN status keys at levels 1/10/80/100, cumulative EXP curve 1–100, and rarity-5 evolution bonus (+60 ATK/+300 HP at evolution 1). Ported the original `CharacterBaseStatusLogic` calculation exactly: locate surrounding keys, linearly interpolate, then `ceil` HP/ATK.
- Battle snapshots now use calculated level/evolution stats. Example: level-10 evolved 西微 is 818 HP / 167 ATK, and party totals update accordingly. Board and weapon modifiers remain pending rather than being fabricated.
- Verification: converter 2 tests; Godot 333 assertions twice; editor scan, smoke, and Windows release export passed. Fixture SHA-256 `7bc52cc830ed9d5514a45efb3ab6b64912722e0a41c709e36724e2260d17a9c1`. Release: 109164360 bytes, SHA-256 `75d69be397bcb134206493767d178d56d5d1dbdac6f41927617d3f6e8bb699a2`.
- Upgraded saves to schema 4 with structured `equipment_inventory` entries (`count`, `level`, `enhancement_level`) and v3→v4 migration. The default leader now owns/equips level-1 老旧短剑 and 精灵的微笑魂珠; other members remain unequipped.
- Recovered equipment master/status curves and ported original `EquipmentStatusLogic` ceil interpolation. 老旧短剑 contributes 47 HP/18 ATK at level 1 and interpolates to 59 HP/22 ATK at level 3. Weapon stats now participate in immutable party totals and battle damage/HP.
- Normalized checked ability-soul rows: the weapon carries `ResistanceWhite` 0.175 and the orb carries party `FixedHeal` 0.1. Equipped ability rows enter the party snapshot; the supported orb heal executes on skill activation. Unsupported resistance semantics remain data-only.
- Verification: converter 2 tests; Godot 347 assertions twice; editor scan, smoke, and Windows release export passed. Fixture SHA-256 `29a62e751756cecc665ab04283be6e2a1966ce591ff56577589f7c57c82f0eaa`. Release: 109169800 bytes, SHA-256 `cd3892dc609b91d4f059f6e9f0c9e8c1b97b83335afc3c94d8e1ac4965c84f7f`.

## 2026-07-23 - Second converted battle

- Added checked quest `1002001`, multi-enemy/emitter battle runtime, and `1001001 -> 1001002 -> 1001003 -> 1002001` offline progression; pushed work commit `6a7e44c968566fd030daab0e16d7145d04de9758`.
- Gate: core converter 5/5; offline catalog determinism `ab9bfdbcd0600e752a31e2fed8d5705161608329964c2c7ca448de519e2a6ab6`; Godot 518 assertions; two-battle flow, editor scan, and 120-frame smoke passed. Task remains in progress pending interactive Windows playthrough and exact terrain/spawn/visual parity.

## 2026-07-23 - Third converted battle

- Added checked quest `1002002`, reused the multi-emitter/Slango runtime without a quest-ID branch, and advanced offline progression through story `1003001`; pushed work commit `24bf2b502d0d9b6454f73b6d64262b71a98da6a6`.
- Gate: core converter 5/5; offline catalog determinism `ab9bfdbcd0600e752a31e2fed8d5705161608329964c2c7ca448de519e2a6ab6`; Godot 556 assertions twice; three-battle flow, editor scan, 120-frame smoke, server/gacha regressions, and runtime dependency audit passed. Task remains in progress at unconverted battle `1003002` and pending exact terrain/spawn/visual parity plus interactive Windows playthrough.

## 2026-07-23 - Fourth converted battle

- Added checked quest `1003002` with three independent Slango/Fox/one-eyed-rabbit emitters, the complete 37-state Fox boss graph, absolute delayed enemy Action DSL events, and offline progression through story `1004001`; pushed work commit `816b80292796f1c25abca20ce489163f172a0a98`.
- Final review fixed same-step delayed-wave decrementing and fail-open `Wait` coercion. Converter input now validates exact event shape, integer type/range, and nested accumulation; integrated tests prove frames 0/12/24 and current owner/player aiming.
- Gate: core converter 7/7; offline catalog determinism `ab9bfdbcd0600e752a31e2fed8d5705161608329964c2c7ca448de519e2a6ab6`; Godot `PASS 624 assertions` independently in two clean roots; four-battle E2E, editor scan, 120-frame smoke, server/gacha regressions, and runtime dependency audit passed. Task remains in progress at unconverted battle `1004002`, with exact terrain/spawn/visual parity and interactive Windows playthrough still pending.

## 2026-07-23 - Windows playtest controls

- Added Space/Down held-key composition for both flippers and Left/Up/Right skill shortcuts, while retaining numeric 1/2/3 aliases; pushed work commit `9c3a2961ca7207560285086b500f512cab0f0fcd`.
- Gate: Godot `PASS 641 assertions` independently in two clean roots; real viewport key injection passes through the four-battle scene flow; editor scan, 120-frame smoke, server/gacha regressions, and runtime dependency audit passed.
- Exported Windows x86-64 playtest builds to `/home/codex/artifacts/starpoint-windows-playtest.Zz9Nsx`. Release SHA-256 is `9010589ee7a4860e9619b76022b8a05fa0d4a383a7bd7136e01351f95bd08974`; it starts successfully for 120 headless frames under isolated Wine. Task remains in progress at `1004002`; user-owned Windows playthrough feedback is pending.
