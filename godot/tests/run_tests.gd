extends SceneTree

var failures: Array[String] = []
var assertions := 0

func assert_equal(actual: Variant, expected: Variant, message: String) -> void:
    assertions += 1
    if actual != expected:
        failures.append("%s | expected=%s actual=%s" % [message, str(expected), str(actual)])

func assert_near(actual: float, expected: float, tolerance: float, message: String) -> void:
    assertions += 1
    if absf(actual - expected) > tolerance:
        failures.append("%s | expected=%s actual=%s tolerance=%s" % [message, str(expected), str(actual), str(tolerance)])

func assert_true(value: bool, message: String) -> void:
    assertions += 1
    if not value:
        failures.append(message)

func _initialize() -> void:
    var suites: Array = [
        preload("res://tests/test_profile_factory.gd").new(),
        preload("res://tests/test_profile_serialization.gd").new(),
        preload("res://tests/test_save_repository.gd").new(),
        preload("res://tests/test_corrupt_save_recovery.gd").new(),
        preload("res://tests/test_save_migration.gd").new(),
        preload("res://tests/test_result_idempotency.gd").new(),
        preload("res://tests/test_static_content_repository.gd").new(),
        preload("res://tests/test_battle_party_snapshot.gd").new(),
        preload("res://tests/test_fixed_step_physics.gd").new(),
        preload("res://tests/test_collision_world.gd").new(),
        preload("res://tests/test_flipper_collision.gd").new(),
        preload("res://tests/test_battle_simulation.gd").new(),
        preload("res://tests/test_multi_emitter_battle.gd").new(),
        preload("res://tests/test_enemy_action_executor.gd").new(),
        preload("res://tests/test_battle_session_service.gd").new(),
        preload("res://tests/test_main_scene.gd").new(),
        preload("res://tests/test_quest_progression.gd").new(),
        preload("res://tests/test_offline_catalog_repository.gd").new(),
        preload("res://tests/test_offline_game_service.gd").new(),
        preload("res://tests/test_playable_replay.gd").new(),
    ]
    for suite in suites:
        suite.run(self)
    if failures.is_empty():
        print("PASS %d assertions" % assertions)
        quit(0)
        return
    for failure in failures:
        push_error("FAIL %s" % failure)
    print("FAIL %d/%d assertions" % [failures.size(), assertions])
    quit(1)
