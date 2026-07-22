class_name QuestProgression
extends RefCounted

static func find_next_main_quest(chapters: Array, stage_nodes: Dictionary, quests: Dictionary, progress: Dictionary) -> Dictionary:
    if chapters.is_empty(): return {}
    var chapter := _latest_chapter(chapters)
    if chapter.is_empty(): return {}
    var nodes_value: Variant = stage_nodes.get(str(chapter.get("id", "")), [])
    if not nodes_value is Array: return {}
    var node := _latest_uncleared_node(nodes_value, progress)
    if node.is_empty(): return {}
    var quest_ids_value: Variant = node.get("quest_ids", [])
    if not quest_ids_value is Array: return {}
    for quest_id_value in quest_ids_value:
        var quest_id := str(quest_id_value)
        var quest: Dictionary = quests.get(quest_id, {})
        if quest.is_empty() or not bool(quest.get("viewable", true)) or _is_cleared(progress, quest_id): continue
        return {"chapter": chapter, "stage_node": node, "quest": quest}
    return {}

static func _latest_chapter(chapters: Array) -> Dictionary:
    var best := {}
    var best_id := -1
    for value in chapters:
        if not value is Dictionary: continue
        var chapter: Dictionary = value
        var id := int(chapter.get("id", -1))
        if id > best_id and bool(chapter.get("viewable", true)):
            best_id = id
            best = chapter
    return best

static func _latest_uncleared_node(nodes: Array, progress: Dictionary) -> Dictionary:
    var best := {}
    var best_id := -1
    for value in nodes:
        if not value is Dictionary: continue
        var node: Dictionary = value
        var id := int(node.get("id", -1))
        var node_progress: Dictionary = progress.get("stage_nodes", {}).get(str(id), {})
        if bool(node_progress.get("cleared", false)): continue
        if id > best_id and bool(node.get("viewable", true)):
            best_id = id
            best = node
    return best

static func _is_cleared(progress: Dictionary, quest_id: String) -> bool:
    var quest_progress: Dictionary = progress.get("quests", {})
    if quest_progress.is_empty():
        quest_progress = progress
    return bool(quest_progress.get(quest_id, {}).get("cleared", false))
