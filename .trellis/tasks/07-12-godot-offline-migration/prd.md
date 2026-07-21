# Godot 单机迁移

## Goal

Create a Godot-based, offline single-player successor to the CN Android client so core gameplay can run without starting the existing Node.js service emulator or depending on the discontinued upstream service.

The preferred outcome would originally have been continued direct use of the Adobe AIR client, but AIR runtime, tooling, ANE/native-extension, platform-support, and user-deployment constraints make it unsuitable as the long-term deliverable. Preserve it as a behavioral/reference build rather than the target runtime.

## Confirmed Facts

- The CN release is a materially distinct product variant, not merely a localized JP/global client. It includes faster bug fixes, a more generous player-facing economy, deliberate divergence from JP power-creep decisions, and CN-original weapons created in the original visual style to rebalance progression.
- This repository is a CN service emulator with implemented account, time, quest, gacha, progression, shop, mail, and selected multiplayer/NPC-coop behavior.
- The supplied Android APK is an Adobe AIR application. Its 27.7 MiB main SWF is `assets/worldflipper_android_release.swf`; its 77 MiB `assets/bundle.zip` contains 3002 hashed resource files.
- The SWF uses uncompressed `FWS` format and is suitable for ActionScript bytecode decompilation. A related CN ActionScript decompilation repository is referenced by this repository.
- The current JPEXS export at `game/wfd` contains 77 ActionScript files, limited to Starling/bit101 support libraries; no `pinball` gameplay classes were exported. Its `symbols.csv` contains only a small set of bootstrap/splash symbols. Treat this export as incomplete until a full script export is produced.
- A CLI export on `wf-vm` produced `game/wfd-full` with 1,634 ActionScript files, including 998 `pinball` business/gameplay files. The export process timed out after 30 minutes but yielded usable battle, asset, configuration, scene, and data-layer sources. The partial GUI export in `game/wfd` is superseded for analysis purposes.
- The existing `game/wf-2.1.125-cn-decompiled-main` reference is substantially more complete: 11,908 ActionScript files, including 11,143 `pinball` files. It contains key runtime classes absent from the 1.8.1 partial export, including `Top`, `BattleScene`, `Remote`, and concrete quest start/finish remotes. Use this repository as the primary structural reference and the 1.8.1 export/APK for version-specific comparison.
- The current client patch bypasses the SDK login and redirects the original client to this service emulator.
- The CN release materially diverged from the Japanese/global releases in bug fixes, operations, rewards, and potentially gameplay behavior. Treat CN client code, CN assets/data, and verified CN behavior as canonical; do not overwrite CN behavior with assumptions from other regions.
- The service emulator has unresolved new-profile behavior. Current playable testing requires a save that has already completed the main story.
- Some service endpoints deliberately return placeholder responses. Confirmed examples include gift-code redemption, PassCard reward claims, social/notification calls, and payment SDK responses.
- `story_quest/finish` persists individual story-quest completion and grants rewards, but does not update `last_main_quest_id` or implement chapter-driven feature unlocks. The single-battle start response returns `last_main_quest_id` without persisting it.
- `TypePackerResource2.pcode` is an approximately 879 MiB resource listing. Do not fully open or load it; use streaming or targeted search only when essential.

## Requirements

- Never delete files on the Windows host. Any cleanup or deletion is permitted only inside the dedicated `wf-vm` virtual machine.
- The delivered game must launch and be playable without a running service emulator or network connection.
- Preserve core single-player gameplay behavior using the ActionScript client and emulator as behavioral references.
- Treat CN behavior, balance values, original CN equipment/content, progression decisions, and player-friendly economy as canonical. JP/global sources may fill documented implementation gaps only and must not silently override CN rules or data.
- Replace server-dependent state with a local data model and persistent local save data.
- Reuse the supplied client assets only after their formats, licensing, and extraction path have been documented.
- Establish a small playable vertical slice before attempting broad feature parity, then incrementally pursue as much practical single-player feature completeness as the available client logic and assets permit.
- Target Windows desktop for the first playable build, while keeping input and layout suitable for later Android export.
- Do not treat new-profile behavior in the service emulator as an authoritative implementation reference until it has been independently verified.
- Treat existing service-side stubs and missing progression unlock behavior as evidence of what the original client expects, not as behavior to reproduce in the offline game.
- Any service-emulator implementation inherited from the international server must be verified against CN client contracts or captures before being used as offline-game behavior.
- Keep the original AIR client, APK, and decompiled sources intact as reference artifacts; do not make the Godot game depend on an installed AIR runtime or Flash projector.
- The long-term target is a complete native Godot migration. Do not ship a hybrid Godot shell that embeds, launches, or depends on the original AIR/SWF runtime.

## Acceptance Criteria

- [ ] A Godot project launches without Node.js, the service emulator, or network access.
- [ ] The first approved vertical slice supports starting a local profile, entering gameplay, resolving its core loop, and saving/reloading progress locally.
- [ ] The migration plan identifies which current client/server responsibilities are required by that slice and their source references.
- [ ] The plan excludes direct full-file inspection of `TypePackerResource2.pcode`.
- [ ] The initial local-profile flow is defined independently of the emulator's unresolved new-profile behavior.

## Out of Scope

- Live-service operations, payment, push notifications, account SDKs, and online multiplayer are out of scope for the first migration slice. Single-player equivalents may be considered after the core offline architecture is proven.
- GUI tooling for operating or repairing the existing Node.js service emulator is not part of this migration task.

## Product Decisions

- The first playable slice is `fixed local profile -> party selection -> one fixed main quest -> client-owned battle simulation -> result/reward -> local save reload`.
- Use functional Godot UI first; restore original visual fidelity incrementally after the asset conversion pipeline is stable.
- Start with a predefined unlocked roster/party and skip the original tutorial/unlock chain in the first slice.
- Preserve CN-specific balance, original weapons, bug fixes, and economy decisions as canonical behavior.

## Delivery Map

- `07-13-godot-core-battle-slice`: first implementation child; establishes the native Godot project, offline local state, one faithful battle loop, result persistence, and Windows/headless verification.
- Later children will separately cover broader progression/home systems, gacha/economy, content and visual parity, and Android export after the core architecture is proven.
