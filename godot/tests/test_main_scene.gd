extends RefCounted

const SCENE_PATH := "res://src/presentation/main_scene.tscn"
const StaticContentRepository = preload("res://src/content/static_content_repository.gd")
const BattleSimulation = preload("res://src/simulation/battle_simulation.gd")
const BattleTestDriver = preload("res://tests/battle_test_driver.gd")

func run(t) -> void:
    t.assert_true(ResourceLoader.exists(SCENE_PATH), "functional main scene exists")
    if not ResourceLoader.exists(SCENE_PATH):
        return
    var packed = load(SCENE_PATH)
    var scene = packed.instantiate()
    var controller_script = scene.get_script()
    t.assert_true(controller_script != null, "main scene has controller script")
    t.assert_true(controller_script.can_instantiate(), "main controller script parses and instantiates")
    t.assert_true(scene.has_node("UI/Menu"), "main scene has offline menu")
    t.assert_true(scene.has_node("UI/Menu/StartButton"), "main scene has start button")
    t.assert_true(scene.has_node("UI/BattleHUD"), "main scene has battle HUD")
    t.assert_true(scene.has_node("UI/ResultPanel"), "main scene has result panel")

    var repository = StaticContentRepository.new()
    t.assert_equal(repository.load_fixture("res://content/fixtures/quest_1001002.json"), OK, "presentation fixture loads")
    var battle = BattleSimulation.new(repository.get_quest("1001002"), "run-presentation")
    scene.battle = battle
    t.assert_true("区域 1/2" in scene._battle_status_text(), "HUD text shows the first zone")
    t.assert_true("击破 0/18" in scene._battle_status_text(), "HUD text shows the zako objective")
    while battle.get_progress_snapshot()["zone_index"] == 0 and battle.status == "running":
        if battle.enemy_active:
            BattleTestDriver.defeat_active_enemy(battle)
        else:
            BattleTestDriver.wait_for_enemy(battle)
    t.assert_true("区域 2/2" in scene._battle_status_text(), "HUD text shows the boss zone")
    t.assert_true("Boss HP 13009" in scene._battle_status_text(), "HUD text shows canonical boss HP")
    scene.free()
