extends RefCounted

const SCENE_PATH := "res://src/presentation/main_scene.tscn"
const StaticContentRepository = preload("res://src/content/static_content_repository.gd")
const BattleSimulation = preload("res://src/simulation/battle_simulation.gd")
const BattleTestDriver = preload("res://tests/battle_test_driver.gd")
const OfflineGameService = preload("res://src/domain/offline_game_service.gd")
const ProfileFactory = preload("res://src/domain/profile_factory.gd")

class EmptyCatalog:
    extends RefCounted

    var chapters: Array = []
    var stage_nodes: Dictionary = {}
    var quests: Dictionary = {}

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
    t.assert_true(scene.has_node("UI/Menu/ReplayButton"), "main scene keeps the converted battle replayable when progression reaches an unsupported quest")
    t.assert_true(scene.has_node("UI/Menu/Actions/CyclePartyButton"), "main scene has party action")
    t.assert_true(scene.has_node("UI/Menu/Actions/UpgradeButton"), "main scene has progression action")
    t.assert_true(scene.has_node("UI/Menu/GachaButton"), "main scene has offline gacha action")
    t.assert_true(scene.has_node("UI/Menu/SystemLabel"), "main scene exposes catalog and operation status")
    t.assert_true(scene.has_node("UI/BattleHUD"), "main scene has battle HUD")
    t.assert_true(scene.has_node("UI/BattleHUD/SkillButtons/Skill1"), "battle HUD has touch skill one")
    t.assert_true(scene.has_node("UI/BattleHUD/SkillButtons/Skill3"), "battle HUD has touch skill three")
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
    t.assert_true("Boss 1 / 总HP 13009" in scene._battle_status_text(), "HUD text shows canonical boss HP")

    t.assert_equal(repository.load_fixture("res://content/fixtures/quest_1002001.json"), OK, "second presentation fixture loads")
    var second_battle = BattleSimulation.new(repository.get_quest("1002001"), "run-second-presentation")
    scene.battle = second_battle
    var second_status: String = scene._battle_status_text()
    t.assert_true("击破 0/20" in second_status, "HUD text shows the second quest objective")
    t.assert_true("敌人 2 / 总HP 890" in second_status, "HUD text aggregates both concurrent enemies")

    t.assert_equal(repository.load_fixture("res://content/fixtures/quest_1002002.json"), OK, "third presentation fixture loads")
    var third_battle = BattleSimulation.new(repository.get_quest("1002002"), "run-third-presentation")
    scene.battle = third_battle
    var third_status: String = scene._battle_status_text()
    t.assert_true("击破 0/22" in third_status, "HUD text shows the third quest objective")
    t.assert_true("敌人 2 / 总HP 890" in third_status, "third quest HUD retains both concurrent enemies")

    t.assert_equal(repository.load_fixture("res://content/fixtures/quest_1003002.json"), OK, "fourth presentation fixture loads")
    var fourth_battle = BattleSimulation.new(repository.get_quest("1003002"), "run-fourth-presentation")
    scene.battle = fourth_battle
    var fourth_status: String = scene._battle_status_text()
    t.assert_true("击破 0/20" in fourth_status, "HUD text shows the fourth quest objective")
    t.assert_true("敌人 3 / 总HP 4362" in fourth_status, "fourth quest HUD aggregates all three concurrent enemies")

    scene.game_service = OfflineGameService.new()
    scene.catalog_repository = EmptyCatalog.new()
    scene.profile = ProfileFactory.create_default()
    scene.content_repository = repository
    t.assert_equal(scene._resolve_next_quest(), {}, "empty catalog without cleared progress exposes no phantom replay fixture")
    scene.free()
