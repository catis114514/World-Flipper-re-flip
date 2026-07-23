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
var counts: Dictionary = {}

func load_catalog(path: String) -> Error:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null: return FileAccess.get_open_error()
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 2: return ERR_PARSE_ERROR
    var parsed_counts: Variant = parsed.get("counts", null)
    var parsed_chapters: Variant = parsed.get("chapters", null)
    var parsed_stage_nodes: Variant = parsed.get("stage_nodes", null)
    var parsed_quests: Variant = parsed.get("quests", null)
    var parsed_characters: Variant = parsed.get("characters", null)
    var parsed_equipments: Variant = parsed.get("equipments", null)
    var parsed_gacha_banners: Variant = parsed.get("gacha_banners", null)
    var parsed_gachas: Variant = parsed.get("gachas", null)
    if not parsed_counts is Dictionary or not parsed_chapters is Array or not parsed_stage_nodes is Dictionary:
        return ERR_INVALID_DATA
    if not parsed_quests is Dictionary or not parsed_characters is Dictionary or not parsed_equipments is Dictionary:
        return ERR_INVALID_DATA
    if not parsed_gacha_banners is Dictionary or not parsed_gachas is Dictionary:
        return ERR_INVALID_DATA
    var stage_node_count := 0
    for chapter_nodes_value in parsed_stage_nodes.values():
        if not chapter_nodes_value is Array:
            return ERR_INVALID_DATA
        stage_node_count += chapter_nodes_value.size()
    if int(parsed_counts.get("chapters", 0)) != 12 or int(parsed_counts.get("stage_nodes", 0)) != 139:
        return ERR_INVALID_DATA
    if int(parsed_counts.get("quests", 0)) != 419 or int(parsed_counts.get("characters", 0)) != 505:
        return ERR_INVALID_DATA
    if int(parsed_counts.get("equipments", 0)) != 436 or int(parsed_counts.get("gacha_banners", 0)) != 584 or int(parsed_counts.get("gacha_pools", 0)) != 581:
        return ERR_INVALID_DATA
    if parsed_chapters.size() != 12 or stage_node_count != 139:
        return ERR_INVALID_DATA
    if parsed_quests.size() != 419 or parsed_characters.size() != 505:
        return ERR_INVALID_DATA
    if parsed_equipments.size() != 436 or parsed_gacha_banners.size() != 584 or parsed_gachas.size() != 581:
        return ERR_INVALID_DATA
    if not _validate_progression_graph(parsed_chapters, parsed_stage_nodes, parsed_quests, parsed_characters):
        return ERR_INVALID_DATA
    counts = parsed_counts.duplicate(true)
    chapters = parsed_chapters.duplicate(true)
    stage_nodes = parsed_stage_nodes.duplicate(true)
    quests = parsed_quests.duplicate(true)
    characters = parsed_characters.duplicate(true)
    equipments = parsed_equipments.duplicate(true)
    gacha_banners = parsed_gacha_banners.duplicate(true)
    gachas = parsed_gachas.duplicate(true)
    source = parsed.get("source", {}).duplicate(true)
    return OK

func _validate_progression_graph(
    parsed_chapters: Array,
    parsed_stage_nodes: Dictionary,
    parsed_quests: Dictionary,
    parsed_characters: Dictionary
) -> bool:
    var chapter_ids: Dictionary = {}
    var node_ids: Dictionary = {}
    var quest_node_ids: Dictionary = {}
    for chapter_value in parsed_chapters:
        if not chapter_value is Dictionary:
            return false
        var chapter: Dictionary = chapter_value
        var chapter_id := int(chapter.get("id", 0))
        if chapter_id <= 0 or chapter_ids.has(str(chapter_id)):
            return false
        chapter_ids[str(chapter_id)] = true
        var listed_node_ids: Variant = chapter.get("stage_node_ids", null)
        var chapter_nodes: Variant = parsed_stage_nodes.get(str(chapter_id), null)
        if not listed_node_ids is Array or not chapter_nodes is Array:
            return false
        if listed_node_ids.size() != chapter_nodes.size():
            return false
        var listed_node_id_set: Dictionary = {}
        for listed_node_id_value in listed_node_ids:
            listed_node_id_set[str(int(listed_node_id_value))] = true
        for node_value in chapter_nodes:
            if not node_value is Dictionary:
                return false
            var node: Dictionary = node_value
            var node_id := int(node.get("id", 0))
            if node_id <= 0 or int(node.get("chapter_id", 0)) != chapter_id:
                return false
            if node_ids.has(str(node_id)) or not listed_node_id_set.has(str(node_id)):
                return false
            node_ids[str(node_id)] = node
            var quest_ids: Variant = node.get("quest_ids", null)
            if not quest_ids is Array or quest_ids.is_empty():
                return false
            for quest_id_value in quest_ids:
                var quest_id := str(quest_id_value)
                var quest_value: Variant = parsed_quests.get(quest_id, null)
                if not quest_value is Dictionary or quest_node_ids.has(quest_id):
                    return false
                if int(quest_value.get("chapter_id", 0)) != chapter_id or int(quest_value.get("stage_node_id", 0)) != node_id:
                    return false
                quest_node_ids[quest_id] = node_id
    if parsed_stage_nodes.size() != chapter_ids.size() or quest_node_ids.size() != parsed_quests.size():
        return false
    for node_value in node_ids.values():
        var requirement := str(node_value.get("need_stage_node_id", ""))
        if not requirement.is_empty() and not node_ids.has(requirement):
            return false
    for quest_value in parsed_quests.values():
        if not quest_value is Dictionary:
            return false
        var prerequisites: Variant = quest_value.get("viewable_prerequisite_ids", null)
        var required_characters: Variant = quest_value.get("viewable_character_ids", null)
        if not prerequisites is Array or not required_characters is Array:
            return false
        for prerequisite_value in prerequisites:
            if not parsed_quests.has(str(prerequisite_value)):
                return false
        for character_id_value in required_characters:
            if not parsed_characters.has(str(int(character_id_value))):
                return false
    return true

func get_character(character_id: String) -> Dictionary:
    return characters.get(character_id, {}).duplicate(true)

func get_equipment(equipment_id: String) -> Dictionary:
    return equipments.get(equipment_id, {}).duplicate(true)

func get_gacha(gacha_id: String) -> Dictionary:
    var result: Dictionary = gachas.get(gacha_id, {}).duplicate(true)
    if not result.is_empty(): result["id"] = gacha_id
    return result
