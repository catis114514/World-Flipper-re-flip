# Godot Offline Migration Design

## Architecture

The final product is a native Godot application with no AIR, Flash projector, Node.js server, HTTP API, CDN, SDK login, or ANE dependency at runtime.

The project is divided into five boundaries:

1. **Import pipeline** converts CN APK/CDN assets and master data into stable intermediate data and Godot-native resources at build time.
2. **Static content repositories** expose typed quests, characters, equipment, enemies, abilities, rewards, and asset references without knowing their original hashed storage layout.
3. **Local profile/domain services** own save slots, party state, inventory, quest progression, rewards, economy, and active-run recovery. They replace only the authoritative responsibilities previously supplied by server endpoints.
4. **Battle simulation** ports the client-owned fixed-step physics, flipper behavior, battle entities, action DSL, abilities, damage, clear/fail state, and deterministic session data. Rendering is separated from simulation state.
5. **Godot presentation** provides input, scenes, UI, audio, animation, and platform adaptation. Functional presentation is sufficient before original visual parity is restored.

## Source Priority

1. CN APK, CN bundle/master assets, and verified CN runtime behavior.
2. `game/wf-2.1.125-cn-decompiled-main` as the primary complete structural reference.
3. `game/wfd-full` and the supplied 1.8.1 APK for version-specific comparison.
4. This repository's CN service emulator for server-authoritative state transitions that are verified against the CN client.
5. JP/global sources only for documented gaps; they must not overwrite CN content or balance silently.

## Runtime Data Flow

On startup, the application loads or creates a local profile and loads packaged static content. A quest selection produces a battle session equivalent to the original `BattleSource` and `SingleBattleSceneValues`. The simulation consumes only typed static content and profile/party snapshots. On clear, fail, abort, or recovery, a local domain service applies rewards and progression atomically to the save slot.

No runtime component calls the old API. Original response-delta parsing is used as a schema/behavior reference, not reproduced as an HTTP compatibility layer.

## Asset Strategy

- Reproduce the CN salted SHA-1 path resolver and file-list parsing in offline conversion tooling.
- Convert PNG and MP3 to Godot-importable assets.
- Decode ordered-map master data into a versioned intermediate representation.
- Decode `.movie`, `.timeline`, `.frame`, and `.parts` AMF3 data incrementally after the core battle slice.
- Treat ATF and file-faker transformations as explicit conversion risks.
- Never load the 879 MiB `TypePackerResource2.pcode` wholesale; use targeted/streaming lookup only if no smaller authoritative index exists.

## Battle Strategy

The original battle simulation is client-owned and uses a custom physics stack. The migration ports its fixed-step math, collision order, constraints, flipper state, and gameplay rules into isolated Godot scripts/resources. Godot Physics2D may be used for visualization or debugging but is not the compatibility authority.

The first slice limits content to one known quest and the minimum action/ability DSL subset needed by that quest. Interfaces must permit later expansion without hard-coding that quest into the simulation.

## Save and Recovery

Save data is local, versioned, and written atomically. The first version contains profile identity, roster, party, inventory/currencies, quest progress, options, and optional active battle metadata. New profiles use a defined CN-oriented preset rather than copying the emulator's incomplete tutorial/unlock chain.

## Compatibility and Rollback

- Original APK/SWF/decompiled sources remain untouched reference artifacts.
- Generated assets and Godot output live in separate directories.
- Converter outputs carry source version/hash metadata so they can be regenerated.
- Migration phases are independently testable; later visual/content work must not rewrite the stable simulation/save contracts without a versioned migration.
