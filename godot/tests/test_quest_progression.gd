extends RefCounted

const QuestProgressionScript = preload("res://src/domain/quest_progression.gd")

func run(t) -> void:
    var chapters := [
        {"id": 1, "stage_node_ids": [1001, 1002]},
        {"id": 2, "stage_node_ids": [2001]},
    ]
    var nodes := {
        "1": [
            {"id": 1001, "stage_index": 1, "need_stage_node_id": "", "quest_ids": ["1001001", "1001002"]},
            {"id": 1002, "stage_index": 2, "need_stage_node_id": "1001", "quest_ids": ["1002001"]},
        ],
        "2": [
            {"id": 2001, "stage_index": 1, "need_stage_node_id": "1002", "quest_ids": ["2001001"]},
        ],
    }
    var quests := {
        "1001001": _quest("1001001"),
        "1001002": _quest("1001002", ["1001001"]),
        "1002001": _quest("1002001", ["1001002"], [99]),
        "2001001": _quest("2001001", ["1002001"], [], 200, 300),
    }
    var progress := {}
    var result := QuestProgressionScript.find_next_main_quest(chapters, nodes, quests, progress, [], 100)
    t.assert_equal(result["quest"]["id"], "1001001", "fresh progress selects the first quest in the released chapter")
    progress["1001001"] = {"cleared": true}
    result = QuestProgressionScript.find_next_main_quest(chapters, nodes, quests, progress, [], 100)
    t.assert_equal(result["quest"]["id"], "1001002", "quests remain ordered inside the current stage node")
    progress["1001002"] = {"cleared": true}
    result = QuestProgressionScript.find_next_main_quest(chapters, nodes, quests, progress, [], 100)
    t.assert_true(result.is_empty(), "a stage node stays hidden until all original visibility conditions pass")
    result = QuestProgressionScript.find_next_main_quest(chapters, nodes, quests, progress, [99], 100)
    t.assert_equal(result["stage_node"]["id"], 1002, "latest viewable uncleared stage node is selected in reverse order")
    t.assert_equal(result["quest"]["id"], "1002001", "owned-character visibility condition unlocks the next quest")
    progress["1002001"] = {"cleared": true}
    result = QuestProgressionScript.find_next_main_quest(chapters, nodes, quests, progress, [99], 100)
    t.assert_true(result.is_empty(), "future chapters are not released before their source start time")
    result = QuestProgressionScript.find_next_main_quest(chapters, nodes, quests, progress, [99], 200)
    t.assert_equal(result["chapter"]["id"], 2, "latest released chapter is selected after its first quest becomes viewable")
    t.assert_equal(result["quest"]["id"], "2001001", "released chapter resolves its first viewable uncleared quest")
    result = QuestProgressionScript.find_next_main_quest(chapters, nodes, quests, progress, [99], 300)
    t.assert_equal(result["quest"]["id"], "2001001", "quest release end time is inclusive like the original TimeRange")
    result = QuestProgressionScript.find_next_main_quest(chapters, nodes, quests, progress, [99], 301)
    t.assert_true(result.is_empty(), "quest becomes hidden after the inclusive release end time")

func _quest(
    quest_id: String,
    prerequisites: Array = [],
    required_characters: Array = [],
    start_unix: int = 0,
    end_unix: int = 0
) -> Dictionary:
    return {
        "id": quest_id,
        "viewable": true,
        "viewable_prerequisite_ids": prerequisites,
        "viewable_character_ids": required_characters,
        "start_unix": start_unix,
        "end_unix": end_unix,
    }
