class_name OfflineCatalogRepository
extends RefCounted

var chapters: Array = []
var stage_nodes: Dictionary = {}
var quests: Dictionary = {}
var characters: Dictionary = {}
var equipments: Dictionary = {}
var gacha_banners: Dictionary = {}
var gachas: Dictionary = {}
var source: Dictionary = {}

func load_catalog(path: String) -> Error:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null: return FileAccess.get_open_error()
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1: return ERR_PARSE_ERROR
    var counts: Dictionary = parsed.get("counts", {})
    if int(counts.get("quests", 0)) != 419 or int(counts.get("characters", 0)) != 505:
        return ERR_INVALID_DATA
    if int(counts.get("equipments", 0)) != 436 or int(counts.get("gacha_banners", 0)) != 584 or int(counts.get("gacha_pools", 0)) != 581:
        return ERR_INVALID_DATA
    if parsed.get("quests", {}).size() != 419 or parsed.get("characters", {}).size() != 505:
        return ERR_INVALID_DATA
    if parsed.get("equipments", {}).size() != 436 or parsed.get("gacha_banners", {}).size() != 584 or parsed.get("gachas", {}).size() != 581:
        return ERR_INVALID_DATA
    chapters = parsed.get("chapters", []).duplicate(true)
    stage_nodes = parsed.get("stage_nodes", {}).duplicate(true)
    quests = parsed.get("quests", {}).duplicate(true)
    characters = parsed.get("characters", {}).duplicate(true)
    equipments = parsed.get("equipments", {}).duplicate(true)
    gacha_banners = parsed.get("gacha_banners", {}).duplicate(true)
    gachas = parsed.get("gachas", {}).duplicate(true)
    source = parsed.get("source", {}).duplicate(true)
    return OK

func get_character(character_id: String) -> Dictionary:
    return characters.get(character_id, {}).duplicate(true)

func get_equipment(equipment_id: String) -> Dictionary:
    return equipments.get(equipment_id, {}).duplicate(true)

func get_gacha(gacha_id: String) -> Dictionary:
    var result: Dictionary = gachas.get(gacha_id, {}).duplicate(true)
    if not result.is_empty(): result["id"] = gacha_id
    return result
