extends RefCounted

const SaveRepository = preload("res://src/persistence/save_repository.gd")

func run(t) -> void:
    var save_path := "user://tests/profile-v0.json"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
    var legacy := {
        "schema_version": 0,
        "profile_id": "legacy-local",
        "display_name": "旧存档",
        "roster": [141005, 121002, 131004],
        "party": [141005, 121002, 131004],
        "free_mana": 4321,
        "free_vmoney": 765,
        "inventory": {},
        "quest_progress": {"1001002": {"clear_count": 2}},
    }
    var file := FileAccess.open(save_path, FileAccess.WRITE)
    file.store_string(JSON.stringify(legacy))
    file.close()

    var restored = SaveRepository.new(save_path).load_profile()
    t.assert_true(restored != null, "legacy v0 save migrates")
    if restored == null:
        return
    t.assert_equal(restored.schema_version, 6, "legacy save reaches current schema")
    t.assert_equal(restored.profile_id, "legacy-local", "migration preserves profile id")
    t.assert_equal(restored.currencies["free_mana"], 4321, "migration preserves mana")
    t.assert_equal(restored.currencies["free_vmoney"], 765, "migration preserves vmoney")
    t.assert_equal(int(restored.quest_progress["1001002"]["clear_count"]), 2, "migration preserves progress")
    t.assert_equal(restored.character_progress["141005"]["level"], 1, "legacy migration creates character level progress")
    t.assert_equal(restored.character_progress["141005"]["evolution"], 0, "legacy migration creates evolution state")
    t.assert_equal(restored.character_progress["141005"]["learned_mana_nodes"], [], "legacy migration creates board progress")
    t.assert_equal(restored.character_progress["121002"]["ability_levels"]["1210023"], 1, "legacy migration preserves playable default ability unlocks")
    t.assert_equal(restored.stamina_state["stored_value"], 50, "legacy migration creates stamina state")
    t.assert_equal(restored.gacha_state["rng_state"], 114514, "legacy migration creates deterministic RNG state")

    var partial_v1 := {"schema_version": 1, "profile_id": "partial", "display_name": "partial", "roster": [141005], "party": [141005], "currencies": {"free_mana": 0, "free_vmoney": 0}, "inventory": {}, "quest_progress": {}, "character_progress": {"141005": {"level": 2}}}
    var migrated_partial = load("res://src/persistence/profile_migrator.gd").migrate(partial_v1)
    t.assert_true(migrated_partial["character_progress"]["141005"]["ability_levels"] is Dictionary, "partial v1 progress gains missing ability levels")
    t.assert_true(migrated_partial["character_progress"]["141005"]["equipment"] is Dictionary, "partial v1 progress gains missing equipment slots")
    var corrupt_v6 := restored.to_dict()
    corrupt_v6["inbox"] = [7]
    t.assert_equal(load("res://src/persistence/profile_migrator.gd").migrate(corrupt_v6), {}, "semantic inbox corruption is rejected")
