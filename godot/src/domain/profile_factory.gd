class_name ProfileFactory
extends RefCounted

const ProfileDataScript = preload("res://src/domain/profile_data.gd")

static func create_default() -> ProfileData:
    var profile := ProfileDataScript.new()
    profile.profile_id = "local-1"
    profile.display_name = "离线玩家"
    profile.roster = [141005, 121002, 131004]
    profile.party = [141005, 121002, 131004]
    profile.currencies = {
        "free_vmoney": 1500,
        "free_mana": 10000,
    }
    profile.inventory = {}
    profile.equipment_inventory = {
        "1010001": {"count": 1, "level": 1, "enhancement_level": 0},
        "100001": {"count": 1, "level": 1, "enhancement_level": 0},
    }
    profile.character_progress = {
        "141005": _default_character_progress(["1410051", "1410052", "1410053"]),
        "121002": _default_character_progress(["1210021", "1210022", "1210023"]),
        "131004": _default_character_progress(["1310041", "1310042", "1310043"]),
    }
    profile.character_progress["141005"]["equipment"] = {"weapon_id": "1010001", "soul_id": "100001"}
    profile.quest_progress = {}
    profile.active_run = {}
    profile.applied_result_ids = []
    return profile

static func _default_character_progress(unlocked_abilities: Array[String]) -> Dictionary:
    var ability_levels := {}
    for ability_id in unlocked_abilities:
        ability_levels[ability_id] = 1
    return {
        "level": 1,
        "exp": 0,
        "evolution": 0,
        "limit_break": 0,
        "learned_mana_nodes": [],
        "action_skill_level": 1,
        "action_skill_evolution": 1,
        "ability_levels": ability_levels,
        "equipment": {"weapon_id": "", "soul_id": ""},
    }
