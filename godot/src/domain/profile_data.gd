class_name ProfileData
extends RefCounted

const CURRENT_SCHEMA_VERSION := 6

var schema_version: int = CURRENT_SCHEMA_VERSION
var profile_id: String = ""
var display_name: String = ""
var roster: Array[int] = []
var party: Array[int] = []
var currencies: Dictionary = {}
var inventory: Dictionary = {}
var character_progress: Dictionary = {}
var equipment_inventory: Dictionary = {}
var quest_progress: Dictionary = {}
var active_run: Dictionary = {}
var applied_result_ids: Array[String] = []
var rank_points: int = 0
var stamina_state: Dictionary = {}
var gacha_state: Dictionary = {}
var operation_ledger: Dictionary = {}
var inbox: Array = []

func replace_from(source: ProfileData) -> void:
    schema_version = source.schema_version
    profile_id = source.profile_id
    display_name = source.display_name
    roster = source.roster.duplicate()
    party = source.party.duplicate()
    currencies = source.currencies.duplicate(true)
    inventory = source.inventory.duplicate(true)
    character_progress = source.character_progress.duplicate(true)
    equipment_inventory = source.equipment_inventory.duplicate(true)
    quest_progress = source.quest_progress.duplicate(true)
    active_run = source.active_run.duplicate(true)
    applied_result_ids = source.applied_result_ids.duplicate()
    rank_points = source.rank_points
    stamina_state = source.stamina_state.duplicate(true)
    gacha_state = source.gacha_state.duplicate(true)
    operation_ledger = source.operation_ledger.duplicate(true)
    inbox = source.inbox.duplicate(true)

func to_dict() -> Dictionary:
    return {
        "schema_version": schema_version,
        "profile_id": profile_id,
        "display_name": display_name,
        "roster": roster.duplicate(),
        "party": party.duplicate(),
        "currencies": currencies.duplicate(true),
        "inventory": inventory.duplicate(true),
        "character_progress": character_progress.duplicate(true),
        "equipment_inventory": equipment_inventory.duplicate(true),
        "quest_progress": quest_progress.duplicate(true),
        "active_run": active_run.duplicate(true),
        "applied_result_ids": applied_result_ids.duplicate(),
        "rank_points": rank_points,
        "stamina_state": stamina_state.duplicate(true),
        "gacha_state": gacha_state.duplicate(true),
        "operation_ledger": operation_ledger.duplicate(true),
        "inbox": inbox.duplicate(true),
    }

static func from_dict(data: Dictionary) -> ProfileData:
    var profile := ProfileData.new()
    profile.schema_version = int(data.get("schema_version", 0))
    profile.profile_id = str(data.get("profile_id", ""))
    profile.display_name = str(data.get("display_name", ""))
    profile.roster = _to_int_array(data.get("roster", []))
    profile.party = _to_int_array(data.get("party", []))
    profile.currencies = _to_int_dictionary(data.get("currencies", {}))
    profile.inventory = _to_dictionary(data.get("inventory", {}))
    profile.character_progress = _to_dictionary(data.get("character_progress", {}))
    profile.equipment_inventory = _to_dictionary(data.get("equipment_inventory", {}))
    profile.quest_progress = _to_dictionary(data.get("quest_progress", {}))
    profile.active_run = _to_dictionary(data.get("active_run", {}))
    profile.applied_result_ids = _to_string_array(data.get("applied_result_ids", []))
    profile.rank_points = int(data.get("rank_points", 0))
    profile.stamina_state = _to_dictionary(data.get("stamina_state", {}))
    profile.gacha_state = _to_dictionary(data.get("gacha_state", {}))
    profile.operation_ledger = _to_dictionary(data.get("operation_ledger", {}))
    profile.inbox = data.get("inbox", []).duplicate(true) if data.get("inbox", []) is Array else []
    return profile

static func _to_int_array(value: Variant) -> Array[int]:
    var result: Array[int] = []
    if value is Array:
        for item in value:
            result.append(int(item))
    return result

static func _to_string_array(value: Variant) -> Array[String]:
    var result: Array[String] = []
    if value is Array:
        for item in value:
            result.append(str(item))
    return result

static func _to_int_dictionary(value: Variant) -> Dictionary:
    var result := {}
    if value is Dictionary:
        for key in value:
            result[str(key)] = int(value[key])
    return result

static func _to_dictionary(value: Variant) -> Dictionary:
    if value is Dictionary:
        return value.duplicate(true)
    return {}
