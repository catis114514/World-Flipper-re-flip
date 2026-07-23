# Godot Offline Domain Contract

## 1. Scope / Trigger

Use this contract for profile schema changes and all local replacements for account, stamina, party, gacha, inbox, shop, or reward endpoints. These operations run in the Godot process and must not require HTTP, Node.js, AIR, CDN, or account SDK state.

## 2. Signatures

```gdscript
OfflineCatalogRepository.load_catalog(path: String) -> Error
OfflineGameService.settle_stamina(profile, now_unix, cap, interval_seconds) -> int
OfflineGameService.spend_stamina(profile, cost, now_unix) -> bool
OfflineGameService.save_party(profile, members) -> bool
OfflineGameService.get_next_main_quest(chapters, stage_nodes, quests, progress, roster, now_unix) -> Dictionary
OfflineGameService.complete_story(profile, quest, operation_id) -> Dictionary
OfflineGameService.draw_gacha(profile, gacha, count, operation_id) -> Dictionary
OfflineGameService.add_inbox_reward(profile, grant_id, subject, rewards) -> bool
OfflineGameService.claim_inbox_reward(profile, grant_id, operation_id) -> Dictionary
BattleSessionService.start_battle(profile, quest_id, run_id, entry_cost, now_unix)
MainController._handle_battle_key_event(event: InputEvent) -> bool
BattleSimulation.set_flippers_pressed(is_pressed: bool) -> void
BattleSimulation.activate_skill(slot_index: int) -> bool
```

Converter:

```text
python3 godot/tools/convert_offline_catalogs.py
```

## 3. Contracts

- Catalog schema 2 contains exactly 12 CN main chapters, 139 stage nodes, 419 main quests, 505 characters, 436 equipments, 584 CN gacha banners, and 581 available projected reward pools. Chapter/stage-node records retain the original multiplied IDs and predecessor graph; quest records retain viewability prerequisites, release timestamps, and required-character conditions. It records SHA-256 for every consumed CN master file and the explicitly identified server projection.
- Profile schema 6 adds `rank_points`, `stamina_state`, `gacha_state`, `operation_ledger`, and `inbox`.
- `stamina_state` owns `stored_value` and `heal_anchor_unix`; elapsed recovery is settled before spending.
- `gacha_state.rng_state` is persisted. A draw advances it, deducts currency, grants results, and writes `operation_ledger[operation_id]` as one staged mutation.
- Every draw result owns `id`, `rank`, `movie_id`, `seed`, and an independently sampled `play_movie`. Movie selection never changes reward rank or item selection.
- Party members are owned, unique, ordered, non-zero, and limited to three.
- Main progression follows the CN client order: latest released chapter, latest viewable uncleared stage node in reverse order, then the first viewable uncleared quest in that node. Story completion is an idempotent local operation using the CN summary; an unavailable battle graph must stop progression explicitly while leaving converted battles replayable.
- Battle start deducts stamina and persists `active_run` in the same staged save.
- Inbox grant IDs are unique. Claim validates all currency caps before mutating any balance and is idempotent by operation ID.
- Presentation actions mutate a cloned `ProfileData`, save it, and only then call `live_profile.replace_from(staged)`.
- Keyboard battle input is owned by presentation. Space and Down Arrow are independent held inputs whose OR state drives both flippers; releasing one must not release the other. Left/Up/Right Arrow activate skill slots 0/1/2 on the first non-echo press, while 1/2/3 remain compatibility aliases. Handled battle keys are consumed in `_input` before GUI focus navigation; mouse and touch retain the skill-button exclusion boundary.
- Active keyboard/touch press state is cleared when a battle starts, finishes, fails, or returns to the menu. Simulation receives only `set_flippers_pressed(bool)` and `activate_skill(slot)`, never raw platform events.

## 4. Validation & Error Matrix

| Condition | Behavior |
|---|---|
| Catalog count or schema mismatch | `ERR_INVALID_DATA` / `ERR_PARSE_ERROR` |
| Missing gacha rank pool | empty result, no currency/RNG mutation |
| Unsupported draw count | empty result; only 1 or 10 are accepted |
| Insufficient currency or stamina | reject with no staged save |
| Duplicate operation ID | return the committed result without a second charge/grant |
| Duplicate/unowned party member | reject and preserve party |
| Inbox result would overflow signed client-safe integer | reject entire claim |
| Save failure | keep the live profile unchanged |
| Keyboard echo or key release for a skill shortcut | consume without activating a skill again |
| Battle input while no battle is running | ignore without mutating held-key state or simulation |

## 5. Good / Base / Bad Cases

- Good: ten-pull cost, RNG counter, all rewards, movie metadata, and ledger entry are saved together.
- Base: all catalog metadata is browseable while only quests with converted battle graphs are playable.
- Bad: calling a server endpoint, using current time as random output, changing live profile before save, selecting a special movie only at positions 1/7, silently substituting JP/GL values for missing CN content, polling skill keys every frame, or letting arrow shortcuts leak into GUI focus navigation.

## 6. Tests Required

- Catalog conversion runs twice byte-identically and enforces `12/139/419/505/436/584/581` for schema 2.
- Schema v0 migrates through v6 and round-trips all new dictionaries.
- Stamina settlement/spend and battle-start atomic deduction.
- Party ownership, uniqueness, and order.
- Fresh profile resolves `1001001`; story completion resolves `1001002`; clearing it and completing `1001003` resolves `1002001`; clearing `1002001` resolves `1002002`; clearing it and completing `1003001` resolves `1003002`; clearing it resolves story `1004001`; completing that story exposes unsupported `1004002` while replay remains on cleared `1003002`.
- Gacha returns exactly 1/10 items, tenth draw is 4-star-or-higher, cost is charged once, RNG state persists, repeated operation IDs return the same result, and `play_movie` exists per position.
- Inbox unique grant, atomic claim, idempotent replay, and overflow rejection.
- Scene exposes keyboard/mouse and touch controls. Unit coverage asserts Space/Down held-key composition, arrow and numeric skill mappings, echo/release suppression, terminal-state rejection, and cleanup. A live scene smoke must inject viewport key events and prove flipper state plus per-slot skill consumption through the real input pipeline.
- Godot headless suite, editor scan, main-scene smoke, and current Windows export.

## 7. Wrong vs Correct

### Wrong

```gdscript
var result = draw(profile)
save_repository.save(profile) # failure leaves mutated live state
```

### Correct

```gdscript
var staged = ProfileData.from_dict(profile.to_dict())
var result = game_service.draw_gacha(staged, banner, 10, operation_id)
if not result.is_empty() and save_repository.save(staged) == OK:
    profile.replace_from(staged)
```

Battle keyboard dispatch:

```gdscript
# Wrong: holding a skill key retries every rendered frame and arrows can also move GUI focus.
if Input.is_key_pressed(KEY_LEFT):
    battle.activate_skill(0)

# Correct: consume the first press before GUI routing and keep held flipper keys independent.
if keycode in [KEY_SPACE, KEY_DOWN]:
    if event.pressed:
        active_flipper_keys[keycode] = true
    else:
        active_flipper_keys.erase(keycode)
elif event.pressed and not event.echo:
    battle.activate_skill(_skill_slot_for_key(keycode))
get_viewport().set_input_as_handled()
```
