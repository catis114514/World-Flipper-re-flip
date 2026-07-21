# Server-to-Local Domain Migration

Date: 2026-07-21

## Decision

The shipped game remains one native Godot process. Server responsibilities are migrated as typed in-process domain services; Node.js, Fastify, MsgPack, HTTP, localhost sockets, account sessions, CDN lookup, and service lifecycle management are not runtime dependencies.

The existing Node emulator is a behavioral and schema reference, not code to bundle. Endpoint request/response captures may remain as migration fixtures, but wire DTOs must stop at the conversion/test boundary and must not become the save or simulation model.

## Why

- The target must work offline and later export to Android.
- The current Godot slice already proves local profile, battle start/finish/abort, rewards, recovery, and exactly-once result application without network access.
- Bundling Node would require Node >=20, native better-sqlite3 deployment, process supervision, ports, logs, firewall handling, and a second platform lifecycle.
- Several emulator flows are not transactionally safe or authoritative enough to copy directly.

## Runtime Responsibility Mapping

| Legacy responsibility | Offline owner |
|---|---|
| /load and aggregate client DTO | SaveRepository + ProfileData |
| player/profile state | LocalProfileService and focused domain services |
| party/edit | PartyService with ownership and slot validation |
| quest start/finish/abort/recovery | QuestSessionService / BattleSessionService |
| quest, character, enemy, action, reward definitions | StaticContentRepository and versioned fixtures |
| client-submitted battle statistics | authoritative BattleSimulation terminal result |
| asset/version/CDN endpoints | packaged Godot content with source version/hash metadata |
| options | local settings repository |
| account SDK, payment, social, multiplayer, ranking | omitted from offline runtime |

## Emulator Defects That Must Not Be Preserved

- Normal single-battle start does not persist its active quest through the provided helper.
- Reload exposes an unfinished quest but does not restore the in-memory object required by finish.
- Finish removes the active run before applying all rewards and progress, leaving a partial-commit crash window.
- Finish lacks a durable result/run idempotency ledger.
- A progress row can be mistaken for a completed quest even when it only represents unlock state.
- Failure paths can still enter reward branches.
- Start performs several cost mutations without one encompassing transaction.
- New-profile defaults are dummy compatibility data rather than verified CN onboarding behavior.

Relevant references:

- src/routes/api/singleBattleQuest.ts
- src/routes/cn/load.ts
- src/routes/api/storyQuest.ts
- src/routes/api/questUnlock.ts
- src/data/domains/quest.ts
- src/data/domains/quest_active.ts

## Local Transaction Contract

A quest run uses persisted phases:

Idle -> Starting -> Active -> TerminalClear or TerminalFail -> ApplyingResult -> Applied -> Idle

Recovery may enter from Active, Terminal, or ApplyingResult. A persisted run owns at least:

- run_id and result_id
- quest id/category and content version/hash
- immutable party snapshot
- entry-cost snapshot
- deterministic seed/checkpoint where supported
- terminal result
- applied result ledger

Applying a clear result must atomically update costs, currencies, inventory, character/pool EXP, quest progress, next unlock, last main quest, result ledger, and active-run removal. Replaying an applied result is a no-op.

Transactions mutate a staged ProfileData, save it, then synchronize the live instance only through ProfileData.replace_from(). Services must not hand-copy selected fields.

## Current Coverage

The core battle slice already owns:

- schema-versioned local profile and migrations
- atomic temp-to-primary save replacement
- local roster, party, inventory, currencies, character/equipment progress
- persisted active run and applied result ids
- immutable party snapshot
- authoritative fixed-step battle result
- transactional clear reward and quest clear count
- abort/reload behavior
- no HTTP, Node, AIR, CDN, or external-process runtime dependency

The 2026-07-21 verification passes converter tests and two clean Godot runs with 366 assertions each.

## Missing Local Server Responsibilities

- stamina settlement, entry costs, refund policy, boosts, rank, EXP pool
- typed multi-party/group/slot model and unison/equipment assignment
- battle/story alternating quest chain, unlock prerequisites, last_main_quest_id
- character EXP injection and mana-board learning
- item/drop/reward-table application beyond currency-only rewards
- shop, gacha, mail, missions, events, and deterministic offline calendar/RNG
- durable active-run checkpoint/resume beyond safe abort
- content catalogs and selectors for more than one quest

## Recommended Delivery Order

1. Local quest progression chain:
   1001002 -> 1001003 -> 1002001 -> 1002002 -> 1003001 -> 1003002.
   This proves battle/story alternation, stamina, unlocks, first-clear rewards, last-main-quest tracking, reload, and result idempotency.
2. Functional Home plus character EXP and one mana-board node.
   Rewards gain a local use and the upgraded stats must affect the next battle snapshot.
3. Typed party groups, unison members, equipment/soul assignment, and ownership validation.
4. Equipment upgrade and richer reward/inventory transactions.
5. Deterministic offline gacha/shop/mail with versioned rules, save-owned RNG streams, and explicit calendar periods.
6. Broader content conversion, visuals/audio, events, and Android packaging.

## Economy and Time Rules

Offline operations must not silently follow wall-clock live-service behavior. Future time-gated systems use a save-owned world time/calendar version and explicit period ids. Randomized systems persist RNG algorithm version, seed, stream, and counter so results are reproducible and migrations are testable. CN static data remains canonical; inherited international-server logic and stubs must be labeled and disabled until verified.
