class_name QuestProgression
extends RefCounted

static func find_next_main_quest(
    chapters: Array,
    stage_nodes: Dictionary,
    quests: Dictionary,
    progress: Dictionary,
    roster: Array = [],
    now_unix: int = 0
) -> Dictionary:
    var released_chapters: Array = []
    for chapter_value in chapters:
        if not chapter_value is Dictionary:
            continue
        var chapter: Dictionary = chapter_value
        if _chapter_is_released(chapter, stage_nodes, quests, progress, roster, now_unix):
            released_chapters.append(chapter)
    if released_chapters.is_empty():
        return {}
    released_chapters.sort_custom(func(a, b): return int(a.get("id", 0)) < int(b.get("id", 0)))
    var latest_chapter: Dictionary = released_chapters.back()
    var nodes := _chapter_nodes(latest_chapter, stage_nodes)
    nodes.sort_custom(func(a, b): return int(a.get("stage_index", 0)) < int(b.get("stage_index", 0)))
    nodes.reverse()
    for node_value in nodes:
        if not node_value is Dictionary:
            continue
        var node: Dictionary = node_value
        if not _stage_node_is_viewable(node, stage_nodes, quests, progress, roster, now_unix):
            continue
        if _stage_node_is_cleared(node, progress):
            continue
        var quest_ids: Variant = node.get("quest_ids", [])
        if not quest_ids is Array:
            return {}
        for quest_id_value in quest_ids:
            var quest_id := str(quest_id_value)
            var quest_value: Variant = quests.get(quest_id, null)
            if not quest_value is Dictionary:
                continue
            var quest: Dictionary = quest_value
            if _quest_is_viewable(quest, progress, roster, now_unix) and not _quest_is_cleared(quest_id, progress):
                return {
                    "chapter": latest_chapter.duplicate(true),
                    "stage_node": node.duplicate(true),
                    "quest": quest.duplicate(true),
                }
        return {}
    return {}

static func _chapter_is_released(
    chapter: Dictionary,
    stage_nodes: Dictionary,
    quests: Dictionary,
    progress: Dictionary,
    roster: Array,
    now_unix: int
) -> bool:
    for node_value in _chapter_nodes(chapter, stage_nodes):
        if node_value is Dictionary and _stage_node_is_viewable(
            node_value, stage_nodes, quests, progress, roster, now_unix
        ):
            return true
    return false

static func _chapter_nodes(chapter: Dictionary, stage_nodes: Dictionary) -> Array:
    var value: Variant = stage_nodes.get(str(int(chapter.get("id", 0))), [])
    return value.duplicate(true) if value is Array else []

static func _stage_node_is_viewable(
    node: Dictionary,
    stage_nodes: Dictionary,
    quests: Dictionary,
    progress: Dictionary,
    roster: Array,
    now_unix: int
) -> bool:
    if not bool(node.get("viewable", true)):
        return false
    var requirement := str(node.get("need_stage_node_id", ""))
    if not requirement.is_empty():
        var required_node := _find_stage_node(requirement, stage_nodes)
        if required_node.is_empty() or not _stage_node_is_cleared(required_node, progress):
            return false
    var quest_ids: Variant = node.get("quest_ids", [])
    if not quest_ids is Array:
        return false
    for quest_id_value in quest_ids:
        var quest_value: Variant = quests.get(str(quest_id_value), null)
        if quest_value is Dictionary and _quest_is_viewable(quest_value, progress, roster, now_unix):
            return true
    return false

static func _find_stage_node(stage_node_id: String, stage_nodes: Dictionary) -> Dictionary:
    for chapter_nodes_value in stage_nodes.values():
        if not chapter_nodes_value is Array:
            continue
        for node_value in chapter_nodes_value:
            if node_value is Dictionary and str(int(node_value.get("id", 0))) == stage_node_id:
                return node_value
    return {}

static func _stage_node_is_cleared(node: Dictionary, progress: Dictionary) -> bool:
    var quest_ids: Variant = node.get("quest_ids", [])
    if not quest_ids is Array or quest_ids.is_empty():
        return false
    for quest_id_value in quest_ids:
        if not _quest_is_cleared(str(quest_id_value), progress):
            return false
    return true

static func _quest_is_viewable(quest: Dictionary, progress: Dictionary, roster: Array, now_unix: int) -> bool:
    if not bool(quest.get("viewable", true)):
        return false
    if now_unix > 0:
        var start_unix := int(quest.get("start_unix", 0))
        var end_unix := int(quest.get("end_unix", 0))
        if start_unix > 0 and now_unix < start_unix:
            return false
        if end_unix > 0 and now_unix > end_unix:
            return false
    var prerequisites: Variant = quest.get("viewable_prerequisite_ids", [])
    if not prerequisites is Array:
        return false
    for prerequisite_value in prerequisites:
        if not _quest_is_cleared(str(prerequisite_value), progress):
            return false
    var required_characters: Variant = quest.get("viewable_character_ids", [])
    if not required_characters is Array:
        return false
    for character_id_value in required_characters:
        if not roster.has(int(character_id_value)):
            return false
    return true

static func _quest_is_cleared(quest_id: String, progress: Dictionary) -> bool:
    var value: Variant = progress.get(quest_id, null)
    return value is Dictionary and bool(value.get("cleared", false))
