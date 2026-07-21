class_name ProfileMigrator
extends RefCounted

const CURRENT_SCHEMA_VERSION := 5

static func migrate(input: Dictionary) -> Dictionary:
    var data := input.duplicate(true)
    var version := int(data.get("schema_version", 0))
    if version == 0:
        data["currencies"] = {
            "free_mana": int(data.get("free_mana", 0)),
            "free_vmoney": int(data.get("free_vmoney", 0)),
        }
        data.erase("free_mana")
        data.erase("free_vmoney")
        data["active_run"] = data.get("active_run", {})
        data["applied_result_ids"] = data.get("applied_result_ids", [])
        data["schema_version"] = 1
        version = 1
    if version == 1:
        data["character_progress"] = _migrate_character_progress(data.get("roster", []), data.get("character_progress", {}))
        data["schema_version"] = 2
        version = 2
    if version == 2:
        var progress_value: Variant = data.get("character_progress", {})
        if not progress_value is Dictionary:
            return {}
        for character_id in progress_value:
            var progress: Dictionary = progress_value[character_id]
            progress["evolution"] = int(progress.get("evolution", 0))
            progress["limit_break"] = int(progress.get("limit_break", 0))
        data["schema_version"] = 3
        version = 3
    if version == 3:
        data["equipment_inventory"] = data.get("equipment_inventory", {
            "1010001": {"count": 1, "level": 1, "enhancement_level": 0},
            "100001": {"count": 1, "level": 1, "enhancement_level": 0},
        })
        data["schema_version"] = 4
        version = 4
    if version == 4:
        var board_progress_value: Variant = data.get("character_progress", {})
        if not board_progress_value is Dictionary:
            return {}
        for character_id in board_progress_value:
            var progress: Dictionary = board_progress_value[character_id]
            progress["learned_mana_nodes"] = progress.get("learned_mana_nodes", [])
            progress["action_skill_level"] = int(progress.get("action_skill_level", 1))
            progress["action_skill_evolution"] = int(progress.get("action_skill_evolution", 1))
        data["schema_version"] = 5
        version = 5
    if version != CURRENT_SCHEMA_VERSION:
        return {}
    return data

static func _migrate_character_progress(roster_value: Variant, existing_value: Variant) -> Dictionary:
    var result: Dictionary = existing_value.duplicate(true) if existing_value is Dictionary else {}
    var default_abilities := {
        "141005": ["1410051", "1410052", "1410053"],
        "121002": ["1210021", "1210022", "1210023"],
        "131004": ["1310041", "1310042", "1310043"],
    }
    if roster_value is Array:
        for character_id_variant in roster_value:
            var character_id := str(int(character_id_variant))
            if result.has(character_id):
                continue
            var levels := {}
            for ability_id in default_abilities.get(character_id, []):
                levels[ability_id] = 1
            result[character_id] = {"level": 1, "exp": 0, "evolution": 0, "limit_break": 0, "learned_mana_nodes": [], "action_skill_level": 1, "action_skill_evolution": 1, "ability_levels": levels, "equipment": {"weapon_id": "", "soul_id": ""}}
    return result
