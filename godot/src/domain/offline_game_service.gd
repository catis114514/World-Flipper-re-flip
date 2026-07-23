class_name OfflineGameService
extends RefCounted

const MAX_CURRENCY := 2147483647
const QuestProgression = preload("res://src/domain/quest_progression.gd")

func settle_stamina(profile: ProfileData, now_unix: int, cap: int = 50, interval_seconds: int = 300) -> int:
    var state := profile.stamina_state
    var value := int(state.get("stored_value", cap))
    var anchor := int(state.get("heal_anchor_unix", 0))
    if anchor <= 0:
        state["heal_anchor_unix"] = now_unix
        state["stored_value"] = value
        return value
    if value >= cap or now_unix <= anchor:
        return value
    var recovered := int((now_unix - anchor) / interval_seconds)
    if recovered <= 0: return value
    var applied := mini(recovered, cap - value)
    state["stored_value"] = value + applied
    state["heal_anchor_unix"] = now_unix if value + applied >= cap else anchor + applied * interval_seconds
    return int(state["stored_value"])

func spend_stamina(profile: ProfileData, cost: int, now_unix: int) -> bool:
    var settled := settle_stamina(profile, now_unix)
    if cost < 0 or settled < cost: return false
    profile.stamina_state["stored_value"] = settled - cost
    if settled >= 50 and int(profile.stamina_state["stored_value"]) < 50:
        profile.stamina_state["heal_anchor_unix"] = now_unix
    return true

func save_party(profile: ProfileData, members: Array) -> bool:
    if members.is_empty() or members.size() > 3: return false
    var normalized: Array[int] = []
    for value in members:
        var character_id := int(value)
        if character_id <= 0 or not profile.roster.has(character_id) or normalized.has(character_id): return false
        normalized.append(character_id)
    profile.party = normalized
    return true

func get_next_main_quest(
    chapters: Array,
    stage_nodes: Dictionary,
    quests: Dictionary,
    progress: Dictionary,
    roster: Array = [],
    now_unix: int = 0
) -> Dictionary:
    var resolved: Dictionary = QuestProgression.find_next_main_quest(
        chapters, stage_nodes, quests, progress, roster, now_unix
    )
    if resolved.is_empty():
        return {}
    var quest_value: Variant = resolved.get("quest", null)
    if not quest_value is Dictionary:
        return {}
    var result: Dictionary = quest_value.duplicate(true)
    result["resolved_chapter"] = resolved.get("chapter", {}).duplicate(true)
    result["resolved_stage_node"] = resolved.get("stage_node", {}).duplicate(true)
    return result

func complete_story(profile: ProfileData, quest: Dictionary, operation_id: String) -> Dictionary:
    if operation_id.is_empty() or str(quest.get("kind", "")) != "story": return {}
    var quest_id := str(quest.get("id", ""))
    var replay := _ledger_response(profile, operation_id, "story", quest_id)
    if not replay.is_empty(): return replay
    if profile.operation_ledger.has(operation_id) or bool(profile.quest_progress.get(quest_id, {}).get("cleared", false)): return {}
    profile.quest_progress[quest_id] = {"cleared": true, "clear_count": 1, "last_result_id": operation_id}
    var response := {"quest_id": quest_id, "name": str(quest.get("name", "")), "summary": str(quest.get("summary", ""))}
    profile.operation_ledger[operation_id] = {"kind": "story", "fingerprint": quest_id, "response": response.duplicate(true)}
    profile.applied_result_ids.append(operation_id)
    return response

func draw_gacha(profile: ProfileData, gacha: Dictionary, count: int, operation_id: String) -> Dictionary:
    if operation_id.is_empty() or count not in [1, 10] or gacha.is_empty(): return {}
    var fingerprint := "%s:%d" % [str(gacha.get("id", "")), count]
    var replay := _ledger_response(profile, operation_id, "gacha", fingerprint)
    if not replay.is_empty(): return replay
    if profile.operation_ledger.has(operation_id): return {}
    var cost_key := "multiCost" if count == 10 else "singleCost"
    var cost := int(gacha.get(cost_key, 0))
    var balance := int(profile.currencies.get("free_vmoney", 0))
    if cost <= 0 or balance < cost: return {}
    var pool: Dictionary = gacha.get("pool", {})
    if not pool.has("1") or not pool.has("2") or not pool.has("3"): return {}
    for rank_key in ["1", "2", "3"]:
        if not pool[rank_key] is Array or pool[rank_key].is_empty(): return {}
        for entry_value in pool[rank_key]:
            if not entry_value is Dictionary or int(entry_value.get("id", 0)) <= 0: return {}
    var state := int(profile.gacha_state.get("rng_state", 114514))
    var results: Array = []
    for index in range(count):
        state = _next_rng(state)
        var rank_roll := state % 100
        var rank_key := "1" if rank_roll < 5 else ("2" if rank_roll < 30 else "3")
        if count == 10 and index == 9 and rank_key == "3": rank_key = "2"
        var entries: Array = pool[rank_key]
        state = _next_rng(state)
        var entry: Dictionary = entries[state % entries.size()]
        var item_id := int(entry.get("id", 0))
        state = _next_rng(state)
        var play_movie := (state % 10000) < 1005
        _grant_gacha_item(profile, item_id, int(entry.get("rank", 3)), int(gacha.get("type", 0)))
        results.append({"id": item_id, "rank": int(entry.get("rank", 3)), "movie_id": str(gacha.get("movieName", "normal")), "seed": state, "play_movie": play_movie})
    profile.currencies["free_vmoney"] = balance - cost
    profile.gacha_state["rng_state"] = state
    var response := {"cost": cost, "results": results, "rng_state": state}
    profile.operation_ledger[operation_id] = {"kind": "gacha", "fingerprint": fingerprint, "response": response.duplicate(true)}
    return response

func add_inbox_reward(profile: ProfileData, grant_id: String, subject: String, rewards: Dictionary) -> bool:
    if grant_id.is_empty() or rewards.is_empty(): return false
    for entry in profile.inbox:
        if str(entry.get("grant_id", "")) == grant_id: return false
    profile.inbox.append({"grant_id": grant_id, "subject": subject, "rewards": rewards.duplicate(true), "claimed": false})
    return true

func claim_inbox_reward(profile: ProfileData, grant_id: String, operation_id: String) -> Dictionary:
    if operation_id.is_empty(): return {}
    var fingerprint := grant_id
    var replay := _ledger_response(profile, operation_id, "inbox", fingerprint)
    if not replay.is_empty(): return replay
    if profile.operation_ledger.has(operation_id): return {}
    for entry in profile.inbox:
        if str(entry.get("grant_id", "")) != grant_id or bool(entry.get("claimed", false)): continue
        var rewards: Dictionary = entry.get("rewards", {})
        for currency_name in rewards:
            var new_value := int(profile.currencies.get(str(currency_name), 0)) + int(rewards[currency_name])
            if new_value < 0 or new_value > MAX_CURRENCY: return {}
        for currency_name in rewards:
            profile.currencies[str(currency_name)] = int(profile.currencies.get(str(currency_name), 0)) + int(rewards[currency_name])
        entry["claimed"] = true
        var response := {"grant_id": grant_id, "rewards": rewards.duplicate(true)}
        profile.operation_ledger[operation_id] = {"kind": "inbox", "fingerprint": fingerprint, "response": response.duplicate(true)}
        return response
    return {}

func _ledger_response(profile: ProfileData, operation_id: String, kind: String, fingerprint: String) -> Dictionary:
    var value: Variant = profile.operation_ledger.get(operation_id, null)
    if not value is Dictionary: return {}
    var entry: Dictionary = value
    if str(entry.get("kind", "")) != kind or str(entry.get("fingerprint", "")) != fingerprint: return {}
    var response: Variant = entry.get("response", {})
    return response.duplicate(true) if response is Dictionary else {}

func _grant_gacha_item(profile: ProfileData, item_id: int, rank: int, gacha_type: int) -> void:
    if gacha_type == 0:
        if not profile.roster.has(item_id): profile.roster.append(item_id)
        var key := str(item_id)
        var progress: Dictionary = profile.character_progress.get(key, {"level": 1, "exp": 0, "evolution": 0, "limit_break": 0, "learned_mana_nodes": [], "action_skill_level": 1, "action_skill_evolution": 1, "ability_levels": {}, "equipment": {"weapon_id": "", "soul_id": ""}, "entry_count": 0})
        progress["entry_count"] = int(progress.get("entry_count", 0)) + 1
        profile.character_progress[key] = progress
    else:
        var key := str(item_id)
        var owned: Dictionary = profile.equipment_inventory.get(key, {"count": 0, "level": 1, "enhancement_level": 0})
        owned["count"] = mini(MAX_CURRENCY, int(owned.get("count", 0)) + 1)
        profile.equipment_inventory[key] = owned

func _next_rng(state: int) -> int:
    return int((state * 1103515245 + 12345) & 0x7fffffff)
