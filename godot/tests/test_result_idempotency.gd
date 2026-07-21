extends RefCounted

const ProfileFactory = preload("res://src/domain/profile_factory.gd")
const LocalProfileService = preload("res://src/domain/local_profile_service.gd")
const SaveRepository = preload("res://src/persistence/save_repository.gd")
const StaticContentRepository = preload("res://src/content/static_content_repository.gd")

func run(t) -> void:
    var profile = ProfileFactory.create_default()
    profile.active_run = {"run_id": "run-1", "quest_id": "1001001"}
    var service = LocalProfileService.new()
    var rewards := {"free_mana": 250, "free_vmoney": 50}
    t.assert_true(service.set_character_level(profile, "141005", 2, 15), "profile service updates character progression")
    t.assert_equal(profile.character_progress["141005"]["level"], 2, "character level mutation is domain-owned")
    t.assert_true(service.set_character_evolution(profile, "141005", 1, 2), "profile service updates evolution and limit break")
    t.assert_equal(profile.character_progress["141005"]["evolution"], 1, "evolution mutation is domain-owned")
    t.assert_true(not service.set_character_level(profile, "141005", 101), "level above recovered curve is rejected")
    t.assert_true(service.set_ability_level(profile, "141005", "1410054", 1), "profile service unlocks an ability")
    t.assert_equal(profile.character_progress["141005"]["ability_levels"]["1410054"], 1, "ability level mutation is domain-owned")
    profile.equipment_inventory["weapon-test"] = {"count": 1, "level": 1, "enhancement_level": 0}
    t.assert_true(service.equip_item(profile, "141005", "weapon_id", "weapon-test"), "owned weapon equips")
    t.assert_equal(profile.character_progress["141005"]["equipment"]["weapon_id"], "weapon-test", "equipment mutation is domain-owned")
    t.assert_true(not service.equip_item(profile, "141005", "weapon_id", "missing-weapon"), "unowned weapon cannot equip")
    t.assert_true(not service.set_character_level(profile, "missing", 1), "unknown character progression cannot mutate")
    var content_repository = StaticContentRepository.new()
    t.assert_equal(content_repository.load_fixture("res://content/fixtures/quest_1001002.json"), OK, "mana-board domain test fixture loads")
    var quest: Dictionary = content_repository.get_quest("1001002")
    profile.inventory["13"] = 3
    var mana_before_node: int = profile.currencies["free_mana"]
    var ability_before_node: int = profile.character_progress["141005"]["ability_levels"]["1410051"]
    t.assert_true(service.unlock_mana_node(profile, quest, "141005", "282010201"), "root mana node unlocks with exact costs")
    t.assert_equal(profile.currencies["free_mana"], mana_before_node - 60, "mana node deducts canonical mana cost")
    t.assert_equal(profile.inventory["13"], 0, "mana node deducts canonical material cost")
    t.assert_equal(profile.character_progress["141005"]["ability_levels"]["1410051"], ability_before_node + 1, "ability node increments its mapped ability slot")
    t.assert_true(not service.unlock_mana_node(profile, quest, "141005", "282010201"), "learned mana node cannot be purchased twice")
    t.assert_true(not service.unlock_mana_node(profile, quest, "141005", "282010207"), "mana node with an unlearned parent is rejected")

    t.assert_true(service.apply_clear_result(profile, "result-1", "1001001", rewards), "first result applies")
    t.assert_equal(profile.currencies["free_mana"], 10190, "mana reward applies once")
    t.assert_equal(profile.currencies["free_vmoney"], 1550, "vmoney reward applies once")
    t.assert_equal(profile.quest_progress["1001001"]["clear_count"], 1, "quest clear count increments")
    t.assert_equal(profile.active_run, {}, "active run clears after result")
    t.assert_true(not service.apply_clear_result(profile, "result-1", "1001001", rewards), "duplicate result is rejected")
    t.assert_equal(profile.currencies["free_mana"], 10190, "duplicate does not add mana")

    var save_path := "user://tests/result-idempotency.json"
    var absolute_save := ProjectSettings.globalize_path(save_path)
    if FileAccess.file_exists(save_path):
        DirAccess.remove_absolute(absolute_save)
    var repository = SaveRepository.new(save_path)
    t.assert_equal(repository.save(profile), OK, "result profile saves")
    var restored = repository.load_profile()
    t.assert_true(not service.apply_clear_result(restored, "result-1", "1001001", rewards), "duplicate remains rejected after reload")
    t.assert_equal(restored.currencies["free_mana"], 10190, "reload duplicate does not add mana")
