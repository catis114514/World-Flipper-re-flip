class_name ProfileMigrator
extends RefCounted

const CURRENT_SCHEMA_VERSION := 6

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
            if not progress_value[character_id] is Dictionary:
                return {}
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
            if not board_progress_value[character_id] is Dictionary:
                return {}
            var progress: Dictionary = board_progress_value[character_id]
            progress["learned_mana_nodes"] = progress.get("learned_mana_nodes", [])
            progress["action_skill_level"] = int(progress.get("action_skill_level", 1))
            progress["action_skill_evolution"] = int(progress.get("action_skill_evolution", 1))
        data["schema_version"] = 5
        version = 5
    if version == 5:
        var currencies_value: Variant = data.get("currencies", {})
        if not currencies_value is Dictionary:
            return {}
        var currencies: Dictionary = currencies_value
        currencies["paid_vmoney"] = int(currencies.get("paid_vmoney", 0))
        currencies["paid_mana"] = int(currencies.get("paid_mana", 0))
        currencies["star_crumb"] = int(currencies.get("star_crumb", 0))
        currencies["bond_token"] = int(currencies.get("bond_token", 0))
        currencies["exp_pool"] = int(currencies.get("exp_pool", 0))
        data["rank_points"] = int(data.get("rank_points", 0))
        data["stamina_state"] = data.get("stamina_state", {"stored_value": 50, "heal_anchor_unix": 0})
        data["gacha_state"] = data.get("gacha_state", {"rng_state": 114514, "banners": {}})
        data["operation_ledger"] = data.get("operation_ledger", {})
        data["inbox"] = data.get("inbox", [])
        data["schema_version"] = 6
        version = 6
    if version != CURRENT_SCHEMA_VERSION:
        return {}
    if not data.get("operation_ledger", {}) is Dictionary or not data.get("inbox", []) is Array:
        return {}
    for ledger_value in data.get("operation_ledger", {}).values():
        if not ledger_value is Dictionary:
            return {}
    for inbox_value in data.get("inbox", []):
        if not inbox_value is Dictionary:
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
            var levels := {}
            for ability_id in default_abilities.get(character_id, []):
                levels[ability_id] = 1
            var current_value: Variant = result.get(character_id, {})
            if not current_value is Dictionary:
                return {}
            var current: Dictionary = current_value
            current["level"] = int(current.get("level", 1))
            current["exp"] = int(current.get("exp", 0))
            current["evolution"] = int(current.get("evolution", 0))
            current["limit_break"] = int(current.get("limit_break", 0))
            current["learned_mana_nodes"] = current.get("learned_mana_nodes", []) if current.get("learned_mana_nodes", []) is Array else []
            current["action_skill_level"] = int(current.get("action_skill_level", 1))
            current["action_skill_evolution"] = int(current.get("action_skill_evolution", 1))
            current["ability_levels"] = current.get("ability_levels", levels) if current.get("ability_levels", levels) is Dictionary else levels
            current["equipment"] = current.get("equipment", {"weapon_id": "", "soul_id": ""}) if current.get("equipment", {}) is Dictionary else {"weapon_id": "", "soul_id": ""}
            result[character_id] = current
    return result
