extends RefCounted

const QuestProgressionScript = preload("res://src/domain/quest_progression.gd")

func run(t) -> void:
    var passed := 0
    var failed: Array[String] = []
    var chapters := [{"id": 1}, {"id": 2, "viewable": true}, {"id": 3, "viewable": false}]
    var nodes := {"2": [{"id": 20, "quest_ids": ["2002", "2001"]}, {"id": 21, "quest_ids": ["2101"]}]}
    var quests := {"2001": {"id": "2001"}, "2002": {"id": "2002", "viewable": false}, "2101": {"id": "2101"}}
    var result := QuestProgressionScript.find_next_main_quest(chapters, nodes, quests, {"stage_nodes": {"21": {"cleared": true}}, "quests": {"2001": {"cleared": false}}})
    t.assert_equal(str(result.get("quest", {}).get("id", "")), "2001", "selects first viewable uncleared quest")
    result = QuestProgressionScript.find_next_main_quest(chapters, nodes, quests, {"stage_nodes": {"20": {"cleared": true}, "21": {"cleared": true}}, "quests": {}})
    t.assert_true(result.is_empty(), "returns empty when all nodes are cleared")
