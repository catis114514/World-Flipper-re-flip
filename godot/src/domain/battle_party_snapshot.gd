class_name BattlePartySnapshot
extends RefCounted

static func build(profile: ProfileData, quest: Dictionary, run_id: String) -> Dictionary:
    if run_id.is_empty():
        return {}
    var characters_value: Variant = quest.get("characters", {})
    var defaults_value: Variant = quest.get("battle_source_defaults", {})
    if not characters_value is Dictionary or not defaults_value is Dictionary:
        return {}
    var characters: Dictionary = characters_value
    var defaults: Dictionary = defaults_value
    var behavior_value: Variant = defaults.get("battle_behavior_data", {})
    if not behavior_value is Dictionary:
        return {}
    var behavior: Dictionary = behavior_value
    if profile.party.is_empty() or profile.party.size() > 3:
        return {}

    var members: Array = []
    var total_hp := 0
    var total_atk := 0
    for slot_index in range(profile.party.size()):
        var character_id := str(profile.party[slot_index])
        if not characters.has(character_id):
            return {}
        var definition_value: Variant = characters[character_id]
        if not definition_value is Dictionary:
            return {}
        var definition: Dictionary = definition_value
        var progress_value: Variant = profile.character_progress.get(character_id, {})
        if not progress_value is Dictionary:
            return {}
        var progress: Dictionary = progress_value
        var character_level := int(progress.get("level", 0))
        var ability_levels_value: Variant = progress.get("ability_levels", {})
        var equipment_value: Variant = progress.get("equipment", {})
        if character_level <= 0 or not ability_levels_value is Dictionary or not equipment_value is Dictionary:
            return {}
        if character_level > int(definition.get("max_level", 0)):
            return {}
        var calculated := _calculate_character_stats(definition, character_level, int(progress.get("evolution", 0)))
        var hp := int(calculated.get("hp", 0))
        var atk := int(calculated.get("atk", 0))
        var equipment_snapshot := _build_equipment_snapshot(profile, quest, equipment_value)
        if equipment_snapshot.is_empty() and (not str(equipment_value.get("weapon_id", "")).is_empty() or not str(equipment_value.get("soul_id", "")).is_empty()):
            return {}
        hp += int(equipment_snapshot.get("hp", 0))
        atk += int(equipment_snapshot.get("atk", 0))
        if hp <= 0 or atk <= 0:
            return {}
        total_hp += hp
        total_atk += atk
        var active_abilities: Array[Dictionary] = []
        var default_levels: Dictionary = ability_levels_value
        for ability in definition.get("abilities", []):
            var ability_id := str(ability.get("ability_id", ""))
            var level := int(default_levels.get(ability_id, 0))
            if level <= 0:
                continue
            var active: Dictionary = ability.duplicate(true)
            active["level"] = level
            active_abilities.append(active)
        for equipment_part_name in ["weapon", "soul"]:
            var equipment_part: Dictionary = equipment_snapshot.get(equipment_part_name, {})
            for equipment_ability in equipment_part.get("ability_soul", []):
                var active_equipment_ability: Dictionary = equipment_ability.duplicate(true)
                active_equipment_ability["origin"] = equipment_part_name
                active_equipment_ability["equipment_id"] = str(equipment_part.get("id", ""))
                active_abilities.append(active_equipment_ability)
        members.append({
            "slot": slot_index,
            "main_character_id": character_id,
            "unison_character_id": "",
            "name": str(definition.get("name", "")),
            "level": character_level,
            "exp": int(progress.get("exp", 0)),
            "evolution": int(progress.get("evolution", 0)),
            "limit_break": int(progress.get("limit_break", 0)),
            "learned_mana_nodes": progress.get("learned_mana_nodes", []).duplicate(),
            "action_skill_level": int(progress.get("action_skill_level", 1)),
            "action_skill_evolution": int(progress.get("action_skill_evolution", 1)),
            "rarity": int(definition.get("rarity", 0)),
            "element": int(definition.get("element", 0)),
            "hp": hp,
            "atk": atk,
            "main_hp": hp,
            "unison_hp": int(definition.get("unison_hp", 0)),
            "main_atk": atk,
            "unison_atk": int(definition.get("unison_atk", 0)),
            "skill": definition.get("skill", {}).duplicate(true),
            "active_abilities": active_abilities,
            "equipment": equipment_snapshot,
            "stat_source_status": "canonical interpolated CN level/evolution/equipment stats with checked equipment ability rows; board pending",
        })

    return {
        "id": run_id,
        "is_host": true,
        "username": profile.display_name,
        "player_role_kind": int(defaults.get("player_role_kind", 1)),
        "player_rank": int(defaults.get("player_rank", 1)),
        "degree_id": int(defaults.get("degree_id", 1)),
        "allow_heal_from_other_players": bool(defaults.get("allow_heal_from_other_players", true)),
        "battle_behavior_data": {
            "skill_ability_behavior_mode": int(behavior.get("skill_ability_behavior_mode", 1)),
            "dash_behavior_mode": int(behavior.get("dash_behavior_mode", 1)),
        },
        "leader_character_id": str(profile.party[0]),
        "members": members,
        "total_hp": total_hp,
        "total_atk": total_atk,
        "direct_attack_reference_atk": int(defaults.get("direct_attack_reference_atk", total_atk)),
        "skill_point_gain_per_direct_attack": int(defaults.get("skill_point_gain_per_direct_attack", 50)),
        "power_flip_combo_thresholds": defaults.get("power_flip_combo_thresholds", [9, 15, 39]).duplicate(),
    }

static func _calculate_character_stats(definition: Dictionary, level: int, evolution: int) -> Dictionary:
    var curve: Dictionary = definition.get("status_curve", {})
    var levels: Array[int] = []
    for key in curve.keys(): levels.append(int(key))
    levels.sort()
    if levels.is_empty() or level < levels[0] or level > levels[-1]: return {}
    var lower := levels[0]
    var upper := levels[-1]
    for index in range(levels.size()):
        if levels[index] <= level: lower = levels[index]
        if levels[index] >= level:
            upper = levels[index]
            break
    var lower_row: Dictionary = curve[str(lower)]
    var upper_row: Dictionary = curve[str(upper)]
    var ratio := 0.0 if lower == upper else float(level - lower) / float(upper - lower)
    var hp := ceili(float(lower_row["hp"]) * (1.0 - ratio) + float(upper_row["hp"]) * ratio)
    var atk := ceili(float(lower_row["atk"]) * (1.0 - ratio) + float(upper_row["atk"]) * ratio)
    var bonus: Dictionary = definition.get("evolution_bonus", {})
    if evolution >= 1:
        hp += int(bonus.get("hp_1", 0)); atk += int(bonus.get("atk_1", 0))
    if evolution >= 2:
        hp += int(bonus.get("hp_2", 0)); atk += int(bonus.get("atk_2", 0))
    return {"hp": hp, "atk": atk}

static func _build_equipment_snapshot(profile: ProfileData, quest: Dictionary, slots: Dictionary) -> Dictionary:
    var result := {"weapon_id": str(slots.get("weapon_id", "")), "soul_id": str(slots.get("soul_id", "")), "hp": 0, "atk": 0, "weapon": {}, "soul": {}}
    var equipments: Dictionary = quest.get("equipments", {})
    var weapon_id: String = result["weapon_id"]
    if not weapon_id.is_empty():
        if not equipments.has(weapon_id) or not profile.equipment_inventory.has(weapon_id): return {}
        var definition: Dictionary = equipments[weapon_id]
        var owned: Dictionary = profile.equipment_inventory[weapon_id]
        if str(definition.get("kind", "")) != "weapon" or int(owned.get("count", 0)) <= 0: return {}
        var stats := _calculate_equipment_stats(definition, int(owned.get("level", 0)))
        if stats.is_empty(): return {}
        result["hp"] = int(stats["hp"]); result["atk"] = int(stats["atk"])
        result["weapon"] = {"id": weapon_id, "name": definition["name"], "level": int(owned["level"]), "enhancement_level": int(owned.get("enhancement_level", 0)), "hp": int(stats["hp"]), "atk": int(stats["atk"]), "ability_soul": definition.get("ability_soul", []).duplicate(true)}
    var soul_id: String = result["soul_id"]
    if not soul_id.is_empty():
        if not equipments.has(soul_id) or not profile.equipment_inventory.has(soul_id): return {}
        var soul_definition: Dictionary = equipments[soul_id]
        var soul_owned: Dictionary = profile.equipment_inventory[soul_id]
        if str(soul_definition.get("kind", "")) != "orb" or int(soul_owned.get("count", 0)) <= 0: return {}
        result["soul"] = {"id": soul_id, "name": soul_definition["name"], "level": int(soul_owned.get("level", 1)), "ability_soul_id": soul_definition["ability_soul_id"], "ability_soul": soul_definition.get("ability_soul", []).duplicate(true)}
    return result

static func _calculate_equipment_stats(definition: Dictionary, level: int) -> Dictionary:
    var curve: Dictionary = definition.get("status_curve", {})
    var levels: Array[int] = []
    for key in curve.keys(): levels.append(int(key))
    levels.sort()
    if levels.is_empty() or level < levels[0] or level > int(definition.get("max_level", 0)): return {}
    var lower := levels[0]; var upper := levels[-1]
    for value in levels:
        if value <= level: lower = value
        if value >= level:
            upper = value
            break
    var a: Dictionary = curve[str(lower)]; var b: Dictionary = curve[str(upper)]
    var ratio := 0.0 if lower == upper else float(level - lower) / float(upper - lower)
    return {"hp": ceili(float(a["hp"]) * (1.0 - ratio) + float(b["hp"]) * ratio), "atk": ceili(float(a["atk"]) * (1.0 - ratio) + float(b["atk"]) * ratio)}
