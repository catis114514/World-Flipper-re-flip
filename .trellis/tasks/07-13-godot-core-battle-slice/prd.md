# Godot Offline Core Battle Slice

## Goal

Create the first native Godot vertical slice of the CN game: a predefined local profile selects a party, enters one documented CN main quest, completes a client-owned battle, receives rewards, and reloads the persisted result without AIR, Node.js, HTTP, CDN, or network access.

## Background

- The complete structural reference is `game/wf-2.1.125-cn-decompiled-main` (11,908 ActionScript files).
- The supplied 1.8.1 APK and `game/wfd-full` provide version-specific comparison.
- Original battle physics and gameplay are client-owned and implemented under the ActionScript `physics`, `pinball.scene.battle`, and battle data/action packages.
- Existing server responsibilities needed for this slice are limited to local profile/party state, battle start/run state, result/reward calculation, quest progress, and persistence.

## Requirements

- Create a Godot 4 project in a new repository directory without modifying or deleting original client/reference artifacts.
- Support Windows desktop as the first interactive target and headless execution for automated validation.
- Create/load a versioned local save slot with a predefined CN-oriented roster, party, inventory, currencies, and unlocked test quest.
- Package one selected CN main-quest fixture and its minimum party, enemy, zone, ability/action, and reward data.
- Port the minimum original fixed-step physics and flipper behavior needed for the selected battle; Godot Physics2D is not the compatibility authority.
- Separate simulation, domain state, static content, persistence, and presentation.
- Support battle start, input, damage/HP, clear/fail, abort/recovery, result application, and save reload.
- Use functional Godot presentation; original UI/animation parity is deferred.
- Never delete files on the Windows host. Any temporary cleanup is allowed only on `wf-vm`.

## Acceptance Criteria

- [ ] The project launches headlessly and as a Windows desktop project without starting Node.js or making network requests.
- [ ] A missing save creates the predefined local profile and a subsequent launch reloads it.
- [ ] The player can select the predefined party and enter the documented quest fixture.
- [ ] The battle uses a fixed-step simulation with flipper input, collision, at least one enemy, HP/damage, and deterministic clear/fail state.
- [ ] Clearing the quest grants its configured reward and persists quest progress exactly once.
- [ ] Aborting or recovering an interrupted run cannot duplicate rewards or corrupt the save.
- [ ] Automated headless tests cover save migration/round-trip, deterministic simulation fixtures, reward idempotency, and the complete offline flow.
- [ ] The implementation contains no AIR runtime, Flash projector, Node.js server, HTTP API, CDN, account SDK, payment, ANE, or multiplayer dependency.

## Out of Scope

- Original tutorial/unlock chain, full home screen, full roster/content parity, gacha, shop, mail, events, multiplayer, Android export, and original UI/animation fidelity.
