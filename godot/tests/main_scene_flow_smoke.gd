extends SceneTree

const BattleTestDriver = preload("res://tests/battle_test_driver.gd")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var save_path := "user://tests/main-scene-flow-smoke.json"
    for suffix in ["", ".tmp", ".bak"]:
        if FileAccess.file_exists(save_path + suffix):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + suffix))
    OS.set_environment("STARPOINT_SAVE_PATH", save_path)
    var scene = load("res://src/presentation/main_scene.tscn").instantiate()
    root.add_child(scene)
    await process_frame
    if not "降落于世界" in scene.start_button.text:
        push_error("fresh menu did not resolve the first CN story")
        quit(1); return
    scene._start_battle()
    await process_frame
    if not scene.result_panel.visible or not bool(scene.profile.quest_progress.get("1001001", {}).get("cleared", false)):
        push_error("story completion did not persist and show its result")
        quit(1); return
    scene._return_to_menu()
    await process_frame
    if not "1001002" in scene.start_button.text:
        push_error("story completion did not advance to the first battle")
        quit(1); return
    var first_stamina_before := int(scene.profile.stamina_state["stored_value"])
    scene._start_battle()
    var first_run_id := str(scene.profile.active_run.get("run_id", ""))
    var first_reloaded = scene.save_repository.load_profile()
    if str(scene.profile.active_run.get("quest_id", "")) != "1001002" or not first_run_id.begins_with("run-") or str(first_reloaded.active_run.get("run_id", "")) != first_run_id:
        push_error("first scene battle did not persist its generated run identity")
        quit(1); return
    if int(scene.profile.stamina_state["stored_value"]) != first_stamina_before - 6:
        push_error("first scene battle did not deduct canonical stamina")
        quit(1); return
    BattleTestDriver.clear_quest(scene.battle)
    scene._finish_battle()
    var first_finished = scene.save_repository.load_profile()
    if not first_finished.active_run.is_empty() or int(first_finished.quest_progress.get("1001002", {}).get("clear_count", 0)) != 1:
        push_error("first scene result did not persist and clear active run")
        quit(1); return
    scene._return_to_menu()
    await process_frame
    if not "旅途的开始" in scene.start_button.text:
        push_error("battle clear did not advance to the following CN story")
        quit(1); return
    scene._start_battle()
    scene._return_to_menu()
    await process_frame
    if not "1002001" in scene.start_button.text or scene.start_button.disabled:
        push_error("following story did not advance to the converted second battle")
        quit(1); return
    var second_stamina_before := int(scene.profile.stamina_state["stored_value"])
    scene._start_battle()
    var second_run_id := str(scene.profile.active_run.get("run_id", ""))
    var second_reloaded = scene.save_repository.load_profile()
    if str(scene.profile.active_run.get("quest_id", "")) != "1002001" or not second_run_id.begins_with("run-") or second_run_id == first_run_id or str(second_reloaded.active_run.get("run_id", "")) != second_run_id:
        push_error("second scene battle did not persist a distinct generated run identity")
        quit(1); return
    if int(scene.profile.stamina_state["stored_value"]) != second_stamina_before - 6:
        push_error("second scene battle did not deduct canonical stamina")
        quit(1); return
    scene.battle.enemy_actions_enabled = false
    BattleTestDriver.clear_quest(scene.battle, 20000)
    if scene.battle.status != "cleared":
        push_error("multi-emitter second battle did not clear through the scene flow")
        quit(1); return
    scene._finish_battle()
    var second_finished = scene.save_repository.load_profile()
    if not second_finished.active_run.is_empty() or int(second_finished.quest_progress.get("1002001", {}).get("clear_count", 0)) != 1:
        push_error("second scene result did not survive reload")
        quit(1); return
    scene._return_to_menu()
    await process_frame
    if not "1002002" in scene.start_button.text or scene.start_button.disabled:
        push_error("second clear did not advance to the converted third battle")
        quit(1); return
    var third_stamina_before := int(scene.profile.stamina_state["stored_value"])
    scene._start_battle()
    var third_run_id := str(scene.profile.active_run.get("run_id", ""))
    var third_reloaded = scene.save_repository.load_profile()
    if str(scene.profile.active_run.get("quest_id", "")) != "1002002" or not third_run_id.begins_with("run-") or third_run_id in [first_run_id, second_run_id] or str(third_reloaded.active_run.get("run_id", "")) != third_run_id:
        push_error("third scene battle did not persist a distinct generated run identity")
        quit(1); return
    if int(scene.profile.stamina_state["stored_value"]) != third_stamina_before - 6:
        push_error("third scene battle did not deduct canonical stamina")
        quit(1); return
    scene.battle.enemy_actions_enabled = false
    BattleTestDriver.clear_quest(scene.battle, 25000)
    if scene.battle.status != "cleared":
        push_error("multi-emitter third battle did not clear through the scene flow")
        quit(1); return
    scene._finish_battle()
    var third_finished = scene.save_repository.load_profile()
    if not third_finished.active_run.is_empty() or int(third_finished.quest_progress.get("1002002", {}).get("clear_count", 0)) != 1:
        push_error("third scene result did not survive reload")
        quit(1); return
    scene._return_to_menu()
    await process_frame
    if not "1003001" in scene.quest_label.text or scene.start_button.disabled:
        push_error("third battle did not advance to the following CN story")
        quit(1); return
    scene._start_battle()
    scene._return_to_menu()
    await process_frame
    if not "1003002" in scene.start_button.text or scene.start_button.disabled:
        push_error("following story did not advance to the converted fourth battle")
        quit(1); return
    var fourth_stamina_before := int(scene.profile.stamina_state["stored_value"])
    scene._start_battle()
    var fourth_run_id := str(scene.profile.active_run.get("run_id", ""))
    var fourth_reloaded = scene.save_repository.load_profile()
    if str(scene.profile.active_run.get("quest_id", "")) != "1003002" or not fourth_run_id.begins_with("run-") or fourth_run_id in [first_run_id, second_run_id, third_run_id] or str(fourth_reloaded.active_run.get("run_id", "")) != fourth_run_id:
        push_error("fourth scene battle did not persist a distinct generated run identity")
        quit(1); return
    if int(scene.profile.stamina_state["stored_value"]) != fourth_stamina_before - 7:
        push_error("fourth scene battle did not deduct canonical stamina")
        quit(1); return
    scene.battle.enemy_actions_enabled = false
    BattleTestDriver.clear_quest(scene.battle, 30000)
    if scene.battle.status != "cleared":
        push_error("three-emitter fourth battle did not clear through the scene flow")
        quit(1); return
    scene._finish_battle()
    var fourth_finished = scene.save_repository.load_profile()
    if not fourth_finished.active_run.is_empty() or int(fourth_finished.quest_progress.get("1003002", {}).get("clear_count", 0)) != 1:
        push_error("fourth scene result did not survive reload")
        quit(1); return
    scene._return_to_menu()
    await process_frame
    if not "1004001" in scene.quest_label.text or scene.start_button.disabled:
        push_error("fourth battle did not advance to the forest-spirit story")
        quit(1); return
    scene._start_battle()
    scene._return_to_menu()
    await process_frame
    if not "1004002" in scene.quest_label.text or not scene.replay_button.visible or not scene.start_button.disabled:
        push_error("unsupported fifth battle does not preserve fourth-battle replay access")
        quit(1); return
    if not "1003002" in scene.replay_button.text:
        push_error("replay fallback did not select the fourth cleared fixture")
        quit(1); return
    print("PASS main scene four-battle progression flow smoke")
    quit(0)
