extends RefCounted

const SaveRepository = preload("res://src/persistence/save_repository.gd")
const LocalProfileService = preload("res://src/domain/local_profile_service.gd")
const StaticContentRepository = preload("res://src/content/static_content_repository.gd")
const BattleSessionService = preload("res://src/domain/battle_session_service.gd")
const BattleTestDriver = preload("res://tests/battle_test_driver.gd")

class FixedContentRepository:
    extends RefCounted

    var fixture: Dictionary

    func _init(quest_fixture: Dictionary) -> void:
        fixture = quest_fixture

    func get_quest(quest_id: String) -> Dictionary:
        if str(fixture.get("id", "")) != quest_id:
            return {}
        return fixture.duplicate(true)

class ProgressionRewardService:
    extends RefCounted

    const BaseProfileService = preload("res://src/domain/local_profile_service.gd")

    func apply_clear_result(profile, result_id: String, quest_id: String, rewards: Dictionary) -> bool:
        if not BaseProfileService.new().apply_clear_result(profile, result_id, quest_id, rewards):
            return false
        profile.character_progress["141005"]["level"] = 2
        profile.equipment_inventory["1010001"]["level"] = 2
        return true

func run(t) -> void:
    var save_path := "user://tests/full-offline-flow.json"
    var absolute_save := ProjectSettings.globalize_path(save_path)
    for suffix in ["", ".tmp", ".bak"]:
        if FileAccess.file_exists(save_path + suffix):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + suffix))

    var save_repository = SaveRepository.new(save_path)
    var content_repository = StaticContentRepository.new()
    t.assert_equal(content_repository.load_fixture("res://content/fixtures/quest_1001002.json"), OK, "flow fixture loads")
    t.assert_equal(content_repository.load_fixture("res://content/fixtures/quest_1002001.json"), OK, "second flow fixture loads")
    t.assert_equal(content_repository.load_fixture("res://content/fixtures/quest_1002002.json"), OK, "third flow fixture loads")
    var session = BattleSessionService.new(save_repository, LocalProfileService.new(), content_repository)
    var profile = session.load_or_create_profile()
    t.assert_true(profile != null, "missing save creates local profile")
    t.assert_true(FileAccess.file_exists(save_path), "created profile is persisted")

    var battle = session.start_battle(profile, "1001002", "run-1", 6, 1000)
    t.assert_true(battle != null, "valid party and quest start battle")
    t.assert_equal(profile.stamina_state["stored_value"], 44, "battle start deducts stamina in the active-run transaction")
    battle.enemy_actions_enabled = false
    t.assert_equal(profile.active_run["run_id"], "run-1", "active run records id")
    t.assert_equal(profile.active_run["party_snapshot"]["total_atk"], 48, "active run persists the immutable party attack snapshot")
    t.assert_equal(profile.active_run["party_snapshot"]["members"][0]["level"], 1, "active run persists profile-owned character level")
    t.assert_true(profile.active_run["party_snapshot"]["members"][0]["active_abilities"].size() >= 3, "active run persists profile-owned ability unlocks")
    t.assert_equal(battle.party_snapshot["leader_character_id"], "141005", "simulation receives the selected leader snapshot")
    t.assert_equal(battle.get_progress_snapshot()["party_attack"], 48, "simulation exposes the snapshotted party attack")
    t.assert_equal(save_repository.load_profile().active_run["quest_id"], "1001002", "active run persists immediately")
    t.assert_true(session.start_battle(profile, "1001002", "run-overlap") == null, "active run blocks a second battle start")
    t.assert_true(not session.finish_battle(profile, battle, "result-premature"), "running battle cannot apply rewards")
    t.assert_equal(profile.active_run["run_id"], "run-1", "premature finish leaves active run intact")

    var duplicate_profile = load("res://src/domain/profile_data.gd").from_dict(profile.to_dict())
    duplicate_profile.active_run = {}
    duplicate_profile.party.clear()
    duplicate_profile.party.append(141005)
    duplicate_profile.party.append(141005)
    t.assert_true(session.start_battle(duplicate_profile, "1001002", "run-duplicate") == null, "duplicate party members are rejected at session boundary")

    BattleTestDriver.clear_quest(battle)
    t.assert_equal(battle.status, "cleared", "full canonical quest simulation clears")
    t.assert_true(session.finish_battle(profile, battle, "result-run-1"), "cleared battle applies result")

    var restored = save_repository.load_profile()
    t.assert_equal(restored.currencies["free_mana"], 10020, "CN quest mana persists")
    t.assert_equal(restored.currencies["exp_pool"], 13, "CN pooled EXP persists")
    t.assert_equal(restored.character_progress["141005"]["exp"], 13, "CN character EXP applies to the selected party")
    t.assert_equal(int(restored.quest_progress["1001002"]["clear_count"]), 1, "clear progress persists")
    t.assert_equal(restored.active_run, {}, "finished run clears active state")
    t.assert_true(not session.finish_battle(restored, battle, "result-run-1"), "replayed result is rejected")
    t.assert_equal(restored.currencies["free_mana"], 10020, "replayed result gives no reward")
    t.assert_true(session.start_battle(restored, "1001002", "run-1") == null, "completed run id cannot be reused")

    var missing_party_character := content_repository.get_quest("1001002")
    missing_party_character["characters"].erase("141005")
    var missing_party_session = BattleSessionService.new(
        save_repository,
        LocalProfileService.new(),
        FixedContentRepository.new(missing_party_character)
    )
    t.assert_true(missing_party_session.start_battle(restored, "1001002", "run-missing-party-character") == null, "missing selected character rejects battle start")
    t.assert_equal(restored.active_run, {}, "snapshot failure creates no active run")

    var invalid_quest := content_repository.get_quest("1001002")
    invalid_quest["zones"][0]["objective"]["count"] = 0
    var invalid_session = BattleSessionService.new(
        save_repository,
        LocalProfileService.new(),
        FixedContentRepository.new(invalid_quest)
    )
    t.assert_true(invalid_session.start_battle(restored, "1001002", "run-invalid") == null, "simulation init failure rejects battle start")
    t.assert_equal(restored.active_run, {}, "simulation init failure creates no active run")
    t.assert_equal(save_repository.load_profile().active_run, {}, "simulation init failure writes no active run")

    var second_battle = session.start_battle(restored, "1001002", "run-2")
    t.assert_true(second_battle != null, "second run starts")
    second_battle.enemy_actions_enabled = false
    t.assert_true(not session.finish_battle(restored, battle, "result-stale-run-1"), "cleared battle from another run is rejected")
    t.assert_equal(restored.currencies["free_mana"], 10020, "stale battle grants no reward")
    t.assert_equal(restored.active_run["run_id"], "run-2", "stale battle leaves current run active")
    second_battle.time_limit_frames = 3
    second_battle.step()
    second_battle.step()
    second_battle.step()
    t.assert_equal(second_battle.status, "failed", "second run reaches deterministic timeout failure")
    t.assert_true(not session.finish_battle(restored, second_battle, "result-failed-run-2"), "failed battle cannot apply rewards")
    t.assert_equal(restored.active_run["run_id"], "run-2", "failed finish leaves active run intact for abort")
    t.assert_true(session.abort_battle(restored), "failed active run aborts")
    var after_abort = save_repository.load_profile()
    t.assert_equal(after_abort.active_run, {}, "aborted run stays cleared after reload")
    t.assert_equal(after_abort.currencies["free_mana"], 10020, "abort grants no reward")
    t.assert_true(not session.abort_battle(after_abort), "repeated abort is idempotently rejected")

    var second_fixture_battle = session.start_battle(after_abort, "1002001", "run-second-fixture")
    t.assert_true(second_fixture_battle != null, "second converted quest starts through the generic session boundary")
    t.assert_equal(after_abort.active_run["quest_id"], "1002001", "second active run persists its own quest id")
    t.assert_equal(save_repository.load_profile().active_run["quest_id"], "1002001", "second active run survives immediate reload")
    second_fixture_battle.enemy_actions_enabled = false
    BattleTestDriver.clear_quest(second_fixture_battle, 20000)
    t.assert_equal(second_fixture_battle.status, "cleared", "second multi-emitter quest clears through the session flow")
    t.assert_true(session.finish_battle(after_abort, second_fixture_battle, "result-run-second-fixture"), "second quest result applies transactionally")
    var second_restored = save_repository.load_profile()
    t.assert_equal(int(second_restored.quest_progress["1002001"]["clear_count"]), 1, "second quest clear survives save reload")
    t.assert_equal(second_restored.active_run, {}, "second finished run clears active state after reload")
    t.assert_equal(second_restored.currencies["free_mana"], 10040, "second quest reward persists exactly once")
    t.assert_true(not session.finish_battle(second_restored, second_fixture_battle, "result-run-second-fixture"), "second quest result replay is rejected")
    t.assert_equal(second_restored.currencies["free_mana"], 10040, "replayed second result grants no duplicate reward")

    var third_fixture_battle = session.start_battle(second_restored, "1002002", "run-third-fixture")
    t.assert_true(third_fixture_battle != null, "third converted quest starts through the generic session boundary")
    t.assert_equal(second_restored.active_run["quest_id"], "1002002", "third active run persists its own quest id")
    third_fixture_battle.enemy_actions_enabled = false
    BattleTestDriver.clear_quest(third_fixture_battle, 25000)
    t.assert_equal(third_fixture_battle.status, "cleared", "third multi-emitter quest clears through the session flow")
    t.assert_true(session.finish_battle(second_restored, third_fixture_battle, "result-run-third-fixture"), "third quest result applies transactionally")
    var third_restored = save_repository.load_profile()
    t.assert_equal(int(third_restored.quest_progress["1002002"]["clear_count"]), 1, "third quest clear survives save reload")
    t.assert_equal(third_restored.active_run, {}, "third finished run clears active state after reload")
    t.assert_equal(third_restored.currencies["free_mana"], 10060, "third quest reward persists exactly once")
    t.assert_true(not session.finish_battle(third_restored, third_fixture_battle, "result-run-third-fixture"), "third quest result replay is rejected")
    t.assert_equal(third_restored.currencies["free_mana"], 10060, "replayed third result grants no duplicate reward")

    var progression_save_path := "user://tests/progression-result-sync.json"
    for suffix in ["", ".tmp", ".bak"]:
        if FileAccess.file_exists(progression_save_path + suffix):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(progression_save_path + suffix))
    var progression_save = SaveRepository.new(progression_save_path)
    var progression_session = BattleSessionService.new(
        progression_save,
        ProgressionRewardService.new(),
        content_repository
    )
    var progression_profile = progression_session.load_or_create_profile()
    var progression_battle = progression_session.start_battle(
        progression_profile,
        "1001002",
        "run-progression-sync"
    )
    t.assert_true(progression_battle != null, "progression transaction battle starts")
    progression_battle.enemy_actions_enabled = false
    BattleTestDriver.clear_quest(progression_battle)
    t.assert_true(progression_session.finish_battle(progression_profile, progression_battle, "result-run-progression-sync"), "progression transaction applies")
    t.assert_equal(progression_profile.character_progress["141005"]["level"], 2, "live profile receives staged character progress")
    t.assert_equal(progression_profile.equipment_inventory["1010001"]["level"], 2, "live profile receives staged equipment inventory")
    t.assert_equal(progression_save.load_profile().character_progress["141005"]["level"], 2, "persisted character progress matches live profile")
    t.assert_equal(progression_save.load_profile().equipment_inventory["1010001"]["level"], 2, "persisted equipment inventory matches live profile")
