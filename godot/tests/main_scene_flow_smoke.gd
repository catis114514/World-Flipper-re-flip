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
    scene._start_battle()
    BattleTestDriver.clear_quest(scene.battle)
    scene._finish_battle()
    scene._return_to_menu()
    await process_frame
    if not "旅途的开始" in scene.start_button.text:
        push_error("battle clear did not advance to the following CN story")
        quit(1); return
    scene._start_battle()
    scene._return_to_menu()
    await process_frame
    if not scene.replay_button.visible or not scene.start_button.disabled:
        push_error("unsupported next battle does not preserve replay access")
        quit(1); return
    print("PASS main scene story-to-battle flow smoke")
    quit(0)
