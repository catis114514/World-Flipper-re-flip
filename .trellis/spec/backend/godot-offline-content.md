# Godot Offline Content Contract

## 1. Scope / Trigger

Use this contract whenever original CN master/APK data is converted into a packaged Godot fixture or when a fixture field is consumed by content, simulation, session, or presentation code. Original APK, SWF, CDN dumps, and decompiled sources are read-only inputs. Runtime code must never perform hashed-path lookup, AMF decoding, HTTP, or Node.js calls.

## 2. Signatures

Converter:

```text
python3 godot/tools/convert_core_fixture.py \
  --repo-root <server-emulator-root> \
  --wf-assets-root <wf-assets-cn-root> \
  --apk <client-apk> \
  --quest-id <main-quest-id> \
  --output <fixture-json>
```

Runtime boundary:

```gdscript
StaticContentRepository.load_fixture(path: String) -> Error
StaticContentRepository.get_quest(quest_id: String) -> Dictionary
BattleSimulation.new(quest: Dictionary, session_run_id: String)
BattleSimulation.get_enemy_snapshots() -> Array[Dictionary]
BattleSimulation.build_result(result_id: String) -> Dictionary
ProfileData.replace_from(source: ProfileData) -> void
```

## 3. Contracts

Fixture schema version 2 requires:

- Quest/economy: `id`, `category`, `name`, stamina, rank times, rewards.
- Battle identity: `field_data_id`, `field_id`, terrain logical/hash path, zone master ID, level, corrections.
- Reference graph: `zones[]`, `enemies{}`, and `action_assets[]` with stable CN IDs. Each action asset includes normalized deterministic runtime records for projectile or funnel-spawn commands.
- Party input: `characters{}` and `battle_source_defaults` containing the checked default party, level-one CN stats, single-battle behavior modes, and direct-attack reference ATK.
- Runtime adapter: `arena` and `enemy`; any value not recovered from original terrain must include an explicit fallback status.
- Evidence: source version/revision and SHA-256 for every consumed source file.

A result is valid only when both `quest_id` and `run_id` match the persisted `active_run`. Persistent IDs use random bytes, not process-relative tick counters.

Battle start builds an immutable party snapshot before persisting `active_run`. The snapshot owns the selected member order, leader ID, main/unison stat split, total HP/ATK, and `BattleBehaviorData` modes. Simulation must consume the snapshot rather than rereading mutable profile party state. In the current one-body adapter, collision damage scales by `total_atk / direct_attack_reference_atk`; the checked default party therefore preserves the existing deterministic baseline while later party stats change gameplay.

Domain transactions mutate a staged `ProfileData`, save that staged value, and then call `live_profile.replace_from(staged)`. The replacement must deep-copy every persisted field from one central owner; services must not maintain partial field-copy lists.

Multi-emitter battle ownership:

- Every active objective enemy owns a stable integer `serial`, `SimBody` tag `enemy:<serial>`, HP, conditions, action schedule/state machine, movement state, definition snapshot, and optional `emitter_index`.
- Each zako emitter owns at most one active enemy. Emitters update before skill/poison/collision damage each fixed step, so a death always starts the complete configured cooldown; one damage source must not shorten it by one frame.
- The initial 90-frame original spawn-point subscription animation is not yet ported. Immediate first spawn and deterministic horizontal separation are explicit terrain/presentation adapters; independent 60/120-frame post-death cooldowns are authoritative fixture data.
- Enemy projectiles and funnel spawn events retain their owner serial. Owner death removes only that owner's projectiles/funnels; zone/terminal teardown removes all instances.
- Non-zero enemy Action DSL `Wait` values are retained as `delay_frames`. Due events resolve the owner's and player's current positions on the firing frame, matching the original retained Action DSL environment; owner/funnel/zone/terminal teardown cancels the corresponding queue entries.
- Converter input accepts `Wait` only as a two-slot outer `Event` containing an exact four-slot wait record. Its frame value is a non-boolean JSON integer in `0..2^53-1`, and the accumulated nested delay must remain in that range; floats, strings, extra/missing slots, and overflow fail closed.
- Pending enemy actions own an absolute `due_frame = elapsed_frames + delay_frames`. The main fixed-step loop may schedule and inspect the queue in the same step, so decrementing a newly queued relative counter in that step is forbidden: it makes a `Wait 12` wave fire on relative frame 11.
- Delayed player events snapshot enemy and funnel serials at cast time. They never acquire a later spawn or a new zone generation, and terminal state clears the remaining event queue.
- Legacy fields (`enemy`, `enemy_hp`, `enemy_state_id`, and related diagnostics) are a compatibility view of one primary active instance. New simulation/presentation code consumes `get_enemy_snapshots()` as the authoritative multi-entity boundary.

## 4. Validation & Error Matrix

| Condition | Required behavior |
|---|---|
| Missing/wrong-type fixture field | `ERR_INVALID_DATA`; never direct-index and crash |
| Duplicate quest, zone, or action ID | `ERR_ALREADY_EXISTS` for quest duplicate; otherwise `ERR_INVALID_DATA` |
| Zone references missing enemy | `ERR_INVALID_DATA` |
| Enemy references missing action DSL record | `ERR_INVALID_DATA` |
| `SpawnFunnel` runtime has no matching `kind=funnel` definition | `ERR_INVALID_DATA` |
| Enemy Action DSL delay is negative, non-integer-typed, above `2^53-1`, cumulatively overflowing, or structurally malformed | converter exits non-zero; fixture loading rejects invalid normalized values and runtime never flattens valid waits |
| Quest references an enemy without an explicit adapter registry entry | converter exits non-zero |
| Empty/malformed normalized action runtime, projectile distribution, enemy ATK, or schedule | `ERR_INVALID_DATA` |
| Source file missing during conversion | converter exits non-zero |
| Emulator projection differs from CN master row | converter exits non-zero |
| Terrain binary absent | keep verified logical/hash evidence and mark fallback; never invent exact geometry |
| Result `run_id` differs from active run | reject with no save or reward mutation |
| Save fails after clear | keep active run and expose retry; do not report success |
| Staged save succeeds but live profile replacement is incomplete | treat as a transaction bug; persisted and in-memory profiles must be field-equivalent |

## 5. Good / Base / Bad Cases

- Good: deterministic conversion produces byte-identical fixture; all graph references validate; clear result matches active run and persists once; the live profile equals the saved staged profile.
- Base: terrain is unavailable, so documented fallback geometry is allowed while the canonical multi-zone objective/enemy flow remains authoritative.
- Bad: using only `zako_emitters[0]`, sharing one HP/condition/action slot across concurrent enemies, flattening enemy waits, snapshotting a delayed enemy projectile's aim at action start, letting delayed player skills hit later spawns, a generic enemy ID, guessed HP presented as canonical, unmarked fallback coordinates, raw dictionaries edited by UI, result IDs derived from `Time.get_ticks_msec()`, or a service hand-copying only selected profile fields after save.

## 6. Tests Required

- Converter golden byte comparison and two-run determinism; malformed outer/inner event shapes, negative, float, boolean, string, null, non-finite, out-of-range, and cumulatively overflowing Action DSL wait values must fail conversion rather than being coerced.
- Canonical ID/hash/HP assertions for the selected quest.
- Missing enemy, missing action, missing required field, duplicate ID, and malformed type rejection.
- Fixed-step collision tests must distinguish approaching impact from separating overlap and expose normal impact speed.
- Simulation regression: quest `1001002` remains 18 single-emitter zakos with 60-frame respawns followed by the 13009-HP boss; timeout terminal states produce no result.
- Multi-emitter regression: quest `1002001` starts one `slango` and one `spirit`, retains independent 60/120-frame emitter cooldowns, counts exactly 20 objective deaths, then activates the 18295-HP Spirit boss with its 31-state cycle.
- Content-reuse regression: quest `1002002` uses the same independent 60/120-frame emitters for exactly 22 objective deaths, then activates the 12196-HP Slango boss with its 36-state cycle and 210-frame skill charge. This must be fixture-driven, not a quest-ID runtime branch.
- Three-emitter regression: quest `1003002` starts `slango`/`fox`/`one_eyed_rabbit` with 60/120/150-frame cooldowns, counts exactly 20 objective deaths, then activates the 33911-HP Fox boss with its 37-state cycle and 300-frame skill charge.
- Ownership regression: serials change on respawn; killing one enemy leaves the other emitter active; owner teardown removes only owned projectiles/funnels; delayed skills cannot hit enemies/funnels created after cast time.
- Timing regression: poison/delayed-skill deaths start a full emitter cooldown, and a terminal ready event prevents remaining same-frame condition events from mutating cleared/failed state.
- Enemy-wait regression: Fox skill fires 7+2 projectiles at frames 0, 12, and 24; an integrated `BattleSimulation.step()` test must prove frame 12 does not fire on frame 11, because helper-only queue tests do not expose same-step scheduling errors. Delayed waves read current owner/target positions, preserve record order, and disappear when the owner is removed.
- Action regression: the four checked DSL assets normalize to exact projectile/funnel parameters; N-way and circle patterns are deterministic; canonical enemy ATK (19/30) and attack multipliers damage party HP; zero HP terminates with `party_defeated` and no result.
- State regression: the 36-state `slango` boss cycle preserves unconditional next-state links and time/loop/move termination metadata, invokes funnel/shot/skill only from their canonical fire states, and uses explicitly marked fallback frames only for movement states whose terrain markers are unavailable.
- Funnel regression: the level-15 funnel uses canonical 132 HP / 23 ATK evidence, persists while its owner is active, orbits deterministically, fires the canonical zako shot on its configured boundary, and is removed with the owner.
- Session regression: a cleared battle from run A cannot settle run B of the same quest.
- Transaction replacement regression: a staged result that changes character progress and equipment inventory must update both the live profile and the reloaded save.
- Party snapshot regression: canonical CN level-one stats total to 162 HP / 30 ATK, missing selected definitions reject start, profile edits do not mutate a running snapshot, and attack scaling is deterministic.
- Save/reload/idempotency and interrupted-run abort tests.
- Main-flow regression advances through converted `1003002`, completes story `1004001`, blocks explicitly at unconverted `1004002`, and keeps the latest cleared fixture replayable.
- Two clean user-data headless runs, editor scan, main-scene smoke, and Windows export.

## 7. Wrong vs Correct

### Wrong

```gdscript
active_run_id = "run-%d" % Time.get_ticks_msec()
if result["quest_id"] == active_run["quest_id"]:
    apply_rewards(result)
```

### Correct

```gdscript
active_run_id = "run-%s" % Crypto.new().generate_random_bytes(16).hex_encode()
if result["quest_id"] != active_run["quest_id"]:
    return false
if result["run_id"] != active_run["run_id"]:
    return false
apply_rewards_once(result)
```

Profile transaction replacement:

```gdscript
# Wrong: future schema fields can be silently omitted.
target.currencies = staged.currencies.duplicate(true)
target.quest_progress = staged.quest_progress.duplicate(true)

# Correct: ProfileData owns the exhaustive replacement contract.
target.replace_from(staged)
```

Delayed enemy scheduling:

```gdscript
# Wrong: a Wait 12 queued earlier in this step is immediately reduced to 11.
event["frames_remaining"] = int(event["frames_remaining"]) - 1

# Correct: compare against the absolute simulation frame on which it is due.
pending_enemy_action_events.append({
    "due_frame": elapsed_frames + delay_frames,
    "runtime": runtime.duplicate(true),
})
if elapsed_frames >= int(event["due_frame"]):
    _start_enemy_action_runtime(
        event["runtime"],
        int(event["source_serial"]),
        int(event["enemy_atk"]),
        float(event["quest_correction"]),
        int(event["reference_party_hp"]),
    )
```

Terrain runtime additions:

- `terrain_runtime.status` is either `fallback` or `recovered`.
- `terrain_runtime.segments[]` owns validated IDs, two-point endpoints, and restitution; simulation converts these once at its content boundary.
- `terrain_runtime.markers` owns validated two-number coordinates; every boss move-state target must resolve to one of these shared markers rather than embedding presentation coordinates. Missing fallback entries fail conversion or fixture loading.
- Segment contacts correct penetration for both approaching and separating overlap, but reflect and report normal impact speed only while approaching.
- Fallback coordinates must remain explicitly labeled and must be replaced by recovered terrain data rather than presented as canonical geometry.
Damageable funnel contract:

- Every active funnel owns one `SimBody`, stable serial, current/max HP, ATK, orbit state, and action schedule.
- Player collision damage routes by body tag: `enemy` advances the active objective only on death; `funnel:<serial>` mutates only that funnel.
- Funnel death and owner teardown must remove the body from `FixedStepWorld` before removing the domain record.
- Presentation snapshots must erase internal `SimBody` references.
Player combat contract:

- Character fixture rows own a validated `skill` record with master gauge, action ID/hash, and normalized core hit runtime.
- Party snapshots copy skill definitions so a running battle never rereads mutable profile party state.
- Each slot caps skill points at its own master maximum and consumes the full gauge atomically on activation.
- Combo thresholds are an ordered three-value fixture contract; Power Flip is armed by flipper contact and consumed by one subsequent direct impact.
- Fields marked as deterministic adapters must not be described as canonical until their original event/timing/multiplier evidence is recovered.
Skill event/condition contract:

- Nested `Wait` commands must accumulate into deterministic `delay_frames`; they must not be flattened.
- Normalized conditions retain source kind, target, duration, and raw strength/interval values.
- Delayed damage and condition application are fixed-step events and must not execute early.
- Party and enemy condition lifetimes are owned by simulation; enemy teardown clears enemy-bound conditions.
- Any unproven raw-unit mapping, including the current poison tick interval, remains explicitly marked as an adapter.
Ability contract:

- Ability conversion retains every row, not merely one row per ability ID.
- Store both numeric codes and decoded generated-enum names, raw powers, scaled powers, targets, and trigger thresholds.
- Active ability rows are snapshotted at battle start according to explicit profile/fixture ability levels.
- Runtime applies only content/trigger combinations with implemented semantics; unsupported records remain available and must not be silently treated as generic attack bonuses.
Extended ability rules:

- Slayer content activates only when the named enemy condition exists.
- DamageCount and SkillMax triggers read explicit simulation counters/gauges.
- Healing clamps to max HP; fever gain clamps to the fever meter.
- Skill-linked dispatch inferred from statue-group context remains marked as adapter until original Gear trigger routing is ported.

Playable fallback loop:

- The unavailable CN terrain includes an outhole/transit-pod flow. The fallback arena must relaunch a ball that reaches the recorded floor/outhole boundary when the player presses the flippers; it must not leave the ball permanently decaying on the bottom bound.
- Outhole relaunch remains an explicit adapter and is replaced when the original terrain/object animation data is recovered.
- Enemy projectile rings honor one damage application per fixed-step hit interval. Overlapping projectiles in the same ring/window apply the strongest hit, never the sum of every overlap.
- Enemy raw attack values are scaled from the recovered `atk_formula.party_hp_level_1` reference to the actual snapshotted party max HP, preserving intended damage percentage rather than treating the reference-party raw value as absolute damage.
- Player skill gauges gain from ball travel distance as in the AS3 member update; the current conversion factor is an explicit deterministic adapter until the exact distance coefficient is recovered.
- Fixed input replays must clear every registered converted fixture, including `1003002`, with enemy actions enabled, skills activated through normal gauge readiness, and no direct position/HP mutation by the test.
Save schema 2 progression contract:

- `character_progress[character_id]` owns level, EXP, ability levels, and `{weapon_id,soul_id}`.
- v0/v1 migration creates progression for every roster entry and normalizes numeric JSON IDs before keying dictionaries.
- UI/presentation must mutate progression through `LocalProfileService`, never by editing save dictionaries directly.
- Battle start snapshots profile progression and equipment; subsequent profile edits cannot alter the active run.
- Until stat curves are ported, stored higher levels/equipment must not be presented as already affecting canonical stats.
Character stat contract:

- Store CN status key rows and cumulative EXP values; do not precompute guessed growth formulas.
- Between key levels, calculate `ceil(lower*(1-ratio)+upper*ratio)` independently for HP and ATK.
- Apply evolution bonuses after base interpolation in the original ATK/HP field order.
- Reject levels outside the recovered curve.
- Limit-break, board, weapon, and soul state may persist before their modifiers are supported, but unsupported modifiers must remain explicitly absent from authoritative stats.
Equipment contract:

- Ownership state stores count, level, and enhancement level separately from character equipment slots.
- Battle start rejects unowned, wrong-kind, or out-of-range equipped IDs.
- Weapon HP/ATK uses original surrounding-key linear interpolation followed by `ceil`.
- Soul/orb slots contribute ability-soul content but not weapon base stats.
- Equipment abilities are snapshotted with origin/equipment ID and use the same supported-content gate as character abilities.

Multi-emitter ownership:

```gdscript
# Wrong: the first emitter and one global HP slot silently discard content.
var emitter: Dictionary = zone["zako_emitters"][0]
enemy_hp = int(definition["max_hp"])

# Correct: each emitter and enemy instance owns stable identity and state.
for emitter_index in range(zone["zako_emitters"].size()):
    emitter_states.append({"index": emitter_index, "active_serial": 0})
    _spawn_emitter_enemy(emitter_index)

for enemy_snapshot in battle.get_enemy_snapshots():
    render_enemy(enemy_snapshot["serial"], enemy_snapshot["position"], enemy_snapshot["hp"])
```
