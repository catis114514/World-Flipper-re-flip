class_name LocalProfileService
extends RefCounted

func apply_clear_result(
    profile: ProfileData,
    result_id: String,
    quest_id: String,
    rewards: Dictionary
) -> bool:
    if result_id.is_empty() or profile.applied_result_ids.has(result_id):
        return false

    for currency_name in rewards:
        var current_amount := int(profile.currencies.get(currency_name, 0))
        profile.currencies[str(currency_name)] = current_amount + int(rewards[currency_name])

    var progress: Dictionary = profile.quest_progress.get(quest_id, {})
    progress["cleared"] = true
    progress["clear_count"] = int(progress.get("clear_count", 0)) + 1
    progress["last_result_id"] = result_id
    profile.quest_progress[quest_id] = progress
    profile.applied_result_ids.append(result_id)
    profile.active_run = {}
    return true

func set_character_level(profile: ProfileData, character_id: String, level: int, exp: int = 0) -> bool:
    if level <= 0 or level > 100 or exp < 0 or not profile.character_progress.has(character_id):
        return false
    var progress: Dictionary = profile.character_progress[character_id]
    progress["level"] = level
    progress["exp"] = exp
    return true

func set_ability_level(profile: ProfileData, character_id: String, ability_id: String, level: int) -> bool:
    if level < 0 or ability_id.is_empty() or not profile.character_progress.has(character_id):
        return false
    var progress: Dictionary = profile.character_progress[character_id]
    var levels_value: Variant = progress.get("ability_levels", {})
    if not levels_value is Dictionary:
        return false
    var levels: Dictionary = levels_value
    levels[ability_id] = level
    return true

func equip_item(profile: ProfileData, character_id: String, slot: String, item_id: String) -> bool:
    if slot not in ["weapon_id", "soul_id"] or not profile.character_progress.has(character_id):
        return false
    if not item_id.is_empty():
        var owned_value: Variant = profile.equipment_inventory.get(item_id, {})
        if not owned_value is Dictionary or int(owned_value.get("count", 0)) <= 0:
            return false
    var progress: Dictionary = profile.character_progress[character_id]
    var equipment_value: Variant = progress.get("equipment", {})
    if not equipment_value is Dictionary:
        return false
    var equipment: Dictionary = equipment_value
    equipment[slot] = item_id
    return true

func set_character_evolution(profile: ProfileData, character_id: String, evolution: int, limit_break: int = 0) -> bool:
    if evolution < 0 or evolution > 2 or limit_break < 0 or limit_break > 4 or not profile.character_progress.has(character_id):
        return false
    var progress: Dictionary = profile.character_progress[character_id]
    progress["evolution"] = evolution
    progress["limit_break"] = limit_break
    return true

func set_equipment_level(profile: ProfileData, item_id: String, level: int, enhancement_level: int = 0) -> bool:
    if level <= 0 or enhancement_level < 0 or not profile.equipment_inventory.has(item_id):
        return false
    var owned: Dictionary = profile.equipment_inventory[item_id]
    owned["level"] = level
    owned["enhancement_level"] = enhancement_level
    return true

func unlock_mana_node(profile: ProfileData, quest: Dictionary, character_id: String, node_id: String) -> bool:
    if not profile.character_progress.has(character_id) or not quest.get("characters", {}).has(character_id):
        return false
    var progress: Dictionary = profile.character_progress[character_id]
    var learned_value: Variant = progress.get("learned_mana_nodes", [])
    if not learned_value is Array or learned_value.has(node_id):
        return false
    var definition: Dictionary = quest["characters"][character_id]
    var node := _find_mana_node(definition, node_id)
    if node.is_empty() or str(node.get("kind", "")) != "ability":
        return false
    var parent_value: Variant = node.get("parent_id", null)
    if parent_value != null and not learned_value.has(str(parent_value)):
        return false
    var required_level_value: Variant = node.get("required_level", null)
    if required_level_value != null and int(progress.get("level", 0)) < int(required_level_value):
        return false
    var required_mana := int(node.get("required_mana", 0))
    if int(profile.currencies.get("free_mana", 0)) < required_mana:
        return false
    var required_items: Dictionary = node.get("required_items", {})
    for item_id in required_items:
        if int(profile.inventory.get(str(item_id), 0)) < int(required_items[item_id]):
            return false
    profile.currencies["free_mana"] = int(profile.currencies.get("free_mana", 0)) - required_mana
    for item_id in required_items:
        profile.inventory[str(item_id)] = int(profile.inventory.get(str(item_id), 0)) - int(required_items[item_id])
    learned_value.append(node_id)
    var effect_kind := str(node.get("effect_kind", ""))
    if effect_kind == "ability":
        var slot := int(node.get("ability_slot", 0))
        var ability_ids: Array = definition.get("ability_ids", [])
        if slot > 0 and slot <= ability_ids.size():
            var levels: Dictionary = progress.get("ability_levels", {})
            var ability_id := str(ability_ids[slot - 1])
            levels[ability_id] = int(levels.get(ability_id, 0)) + 1
    elif effect_kind == "action_skill_level":
        progress["action_skill_level"] = int(progress.get("action_skill_level", 1)) + 1
    elif effect_kind == "action_skill_evolution":
        progress["action_skill_evolution"] = int(progress.get("action_skill_evolution", 1)) + 1
    return true

func _find_mana_node(definition: Dictionary, node_id: String) -> Dictionary:
    var boards: Dictionary = definition.get("mana_boards", {})
    for nodes_value in boards.values():
        if not nodes_value is Array:
            continue
        for node in nodes_value:
            if str(node.get("id", "")) == node_id:
                return node
    return {}
