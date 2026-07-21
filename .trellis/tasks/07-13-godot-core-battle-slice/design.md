# Core Battle Slice Design

## Project Layout

Create the native client under `godot/`:

- `godot/project.godot` — project configuration.
- `godot/src/content/` — typed static content and fixture repositories.
- `godot/src/domain/` — profile, party, inventory, quest progress, rewards, and battle-run services.
- `godot/src/persistence/` — versioned save codec, atomic writes, migrations, and recovery.
- `godot/src/simulation/` — fixed-step math, bodies/shapes/collision, flipper, battle entities, actions, damage, and result state.
- `godot/src/presentation/` — scenes, input adapter, rendering, HUD, menus, and result view.
- `godot/content/fixtures/` — converted CN quest/party/enemy/reward fixture with source metadata.
- `godot/tests/` — headless unit, golden-fixture, and flow tests.

## Reference Contracts

- Application/bootstrap structure: `game/wf-2.1.125-cn-decompiled-main/scripts/scripts/PinballClientMain.as` and `pinball/context/Top.as`.
- Battle orchestration: `pinball/scene/battle/BattleScene.as` and its `battle`, `driver`, `state`, `restore`, and `view` packages.
- Physics: `scripts/scripts/physics/dynamics/World.as`, `SmallWorld.as`, `Body.as`, collision/constraint packages, and `physics/pinball/Flipper.as`.
- Battle inputs: `pinball/common/data/battle/BattleSource.as`, `BattleBehaviorData.as`, and restore `SingleBattleSceneValues.as`.
- Quest/static data: `pinball/common/data/quest/repository/QuestRepository.as` and battle/enemy/action/ability source packages.
- Server-state reference: `src/routes/cn/load.ts`, `src/routes/api/party.ts`, `src/routes/api/singleBattleQuest.ts`, and `src/routes/api/storyQuest.ts`.

## Component Boundaries

### StaticContentRepository

Loads only packaged, converted fixture data. It exposes quest, zone, enemy, party/character, action/ability, and reward definitions by stable CN identifiers. Original hashed paths and AMF/ordered-map decoding remain outside runtime.

### LocalProfileService

Creates the predefined profile, edits/selects its party, exposes currencies/inventory/progress, and applies typed domain changes. Presentation never edits save dictionaries directly.

### SaveRepository

Stores a schema-versioned JSON/binary-neutral document in `user://`. Writes use a temporary file plus atomic replacement where supported. Active battle runs and applied result IDs make recovery and rewards idempotent.

### BattleSessionService

Validates quest and party, snapshots inputs, creates an active run ID, starts simulation, and resolves clear/fail/abort. It replaces `single_battle_quest/start`, `finish`, and `abort` responsibilities without reproducing their HTTP payloads.

### BattleSimulation

Runs at an explicit fixed timestep. Simulation state owns positions, velocities, collisions, flipper state, HP, damage, actions, and terminal result. Godot nodes render snapshots and translate input but do not own authoritative game state.

## Determinism and Testing

- Port math/update order before presentation.
- Encode small golden scenarios for gravity/integration, circle/wall collision, flipper hit, enemy damage, and terminal clear/fail.
- Tests feed the same timestep and input sequence and compare normalized state snapshots.
- A full-flow headless test creates a profile, starts a run, drives a deterministic clear, applies rewards, reloads the save, and verifies no duplicate reward on replay.

## Error and Recovery Behavior

- Invalid fixture IDs fail before creating an active run.
- Save decode failure preserves the unreadable save and creates no silent overwrite; recovery is explicit.
- An interrupted active run may be resumed from supported metadata or safely aborted without rewards.
- Result application is transactional and keyed by run/result ID.

## Compatibility

The slice deliberately uses a narrow content fixture, but identifiers, repositories, session contracts, and save schemas must support later CN content expansion. Source version and hashes are stored beside converted fixtures.
