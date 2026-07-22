extends RefCounted

const StaticContentRepository = preload("res://src/content/static_content_repository.gd")
const BattleSimulation = preload("res://src/simulation/battle_simulation.gd")
const BattleTestDriver = preload("res://tests/battle_test_driver.gd")
const ProfileFactory = preload("res://src/domain/profile_factory.gd")
const BattlePartySnapshot = preload("res://src/domain/battle_party_snapshot.gd")

func run(t) -> void:
    var repository = StaticContentRepository.new()
    t.assert_equal(repository.load_fixture("res://content/fixtures/quest_1001002.json"), OK, "battle fixture loads")
    var quest := repository.get_quest("1001002")
    var battle = BattleSimulation.new(quest, "run-battle-1")
    battle.enemy_actions_enabled = false
    var initial: Dictionary = battle.get_progress_snapshot()
    t.assert_equal(battle.status, "running", "battle starts running")
    t.assert_equal(initial["zone_index"], 0, "battle starts in the first zone")
    t.assert_equal(initial["zone_count"], 2, "canonical battle has two zones")
    t.assert_equal(initial["objective_kind"], "zako_kill", "first objective is zako kill")
    t.assert_equal(initial["objective_target"], 18, "first objective requires 18 zakos")
    t.assert_equal(initial["objective_progress"], 0, "first objective starts empty")
    t.assert_equal(initial["enemy_kind"], "zako", "first active enemy is a zako")
    t.assert_equal(battle.enemy_hp, 148, "zako HP comes from original CN curve calculation")

    var reference_battle = BattleSimulation.new(quest, "run-reference-atk", {"total_atk": 30, "direct_attack_reference_atk": 30})
    var doubled_battle = BattleSimulation.new(quest, "run-doubled-atk", {"total_atk": 60, "direct_attack_reference_atk": 30})
    BattleTestDriver.impact_once(reference_battle, 10.0)
    BattleTestDriver.impact_once(doubled_battle, 10.0)
    var reference_damage: int = 148 - int(reference_battle.enemy_hp)
    var doubled_damage: int = 148 - int(doubled_battle.enemy_hp)
    t.assert_true(reference_damage > 0, "reference party attack causes collision damage")
    t.assert_equal(doubled_damage, reference_damage * 2, "snapshotted party attack scales deterministic collision damage")

    var combat_battle = BattleSimulation.new(quest, "run-player-combat", {"total_atk": 30, "direct_attack_reference_atk": 30})
    t.assert_equal(combat_battle.skill_slots.size(), 3, "battle builds three player skill slots")
    for hit in range(11): combat_battle._record_direct_attack()
    t.assert_equal(combat_battle.combo_count, 11, "direct attacks build combo")
    t.assert_equal(combat_battle.power_flip_level, 1, "nine-combo threshold charges level-one power flip")
    t.assert_equal(combat_battle.skill_slots[0]["skill_point"], 530, "skill gauge clamps at canonical maximum")
    var hp_before_skill: int = combat_battle.enemy_hp
    t.assert_true(combat_battle.activate_skill(0), "full leader gauge activates skill")
    t.assert_true(combat_battle.enemy_hp < hp_before_skill, "leader skill damages the active enemy")
    t.assert_equal(combat_battle.skill_slots[0]["skill_point"], 0, "skill activation consumes the full gauge")
    t.assert_true(not combat_battle.activate_skill(0), "empty skill gauge cannot activate twice")
    combat_battle._record_movement_skill_points(20.0)
    t.assert_equal(combat_battle.skill_slots[0]["skill_point"], 1, "ball travel contributes to the original movement-based skill gauge")

    var condition_battle = BattleSimulation.new(quest, "run-skill-conditions", {"total_atk": 30, "direct_attack_reference_atk": 30})
    condition_battle.enemy_actions_enabled = false
    condition_battle.skill_slots[0]["skill_point"] = condition_battle.skill_slots[0]["max_skill_point"]
    t.assert_true(condition_battle.activate_skill(0), "leader skill activates for condition test")
    t.assert_true(condition_battle.party_conditions.has("flying"), "leader skill applies flying immediately")
    t.assert_true(condition_battle.player.disable_gravity, "flying condition disables ball gravity")

    var poison_battle = BattleSimulation.new(quest, "run-poison-skill", {"total_atk": 30, "direct_attack_reference_atk": 30})
    poison_battle.enemy_actions_enabled = false
    poison_battle.skill_slots[1]["skill_point"] = poison_battle.skill_slots[1]["max_skill_point"]
    var onmyoji_hp_before: int = poison_battle.enemy_hp
    t.assert_true(poison_battle.activate_skill(1), "onmyoji skill activates")
    t.assert_true(poison_battle.party_conditions.has("attack_up"), "onmyoji skill applies party attack up immediately")
    poison_battle.step()
    poison_battle.step()
    t.assert_equal(poison_battle.enemy_hp, onmyoji_hp_before, "onmyoji delayed hit does not fire one frame early")
    poison_battle.step()
    t.assert_true(poison_battle.enemy_hp < onmyoji_hp_before, "onmyoji hit fires after canonical three-frame wait")
    t.assert_true(poison_battle.enemy_conditions.has("poison"), "onmyoji delayed hit applies poison")
    var hp_before_poison_tick: int = poison_battle.enemy_hp
    for frame in range(59): poison_battle.step()
    t.assert_equal(poison_battle.enemy_hp, hp_before_poison_tick, "poison does not tick before its adapter interval")
    poison_battle.step()
    t.assert_true(poison_battle.enemy_hp < hp_before_poison_tick, "poison condition deals periodic damage")

    var delayed_battle = BattleSimulation.new(quest, "run-delayed-skill", {"total_atk": 30, "direct_attack_reference_atk": 30})
    delayed_battle.enemy_actions_enabled = false
    delayed_battle.skill_slots[2]["skill_point"] = delayed_battle.skill_slots[2]["max_skill_point"]
    var archer_hp_before: int = delayed_battle.enemy_hp
    t.assert_true(delayed_battle.activate_skill(2), "archer skill activates")
    for frame in range(79): delayed_battle.step()
    t.assert_equal(delayed_battle.enemy_hp, archer_hp_before, "archer nested wait remains pending through frame 79")
    delayed_battle.step()
    t.assert_true(delayed_battle.enemy_hp < archer_hp_before, "archer hit fires after canonical 80-frame delay")

    var normal_power_battle = BattleSimulation.new(quest, "run-normal-power", {"total_atk": 30, "direct_attack_reference_atk": 30})
    var level_three_battle = BattleSimulation.new(quest, "run-level-three-power", {"total_atk": 30, "direct_attack_reference_atk": 30})
    level_three_battle.armed_power_flip_level = 3
    BattleTestDriver.impact_once(normal_power_battle, 10.0)
    BattleTestDriver.impact_once(level_three_battle, 10.0)
    var normal_power_damage: int = 148 - normal_power_battle.enemy_hp
    var expected_power_damage := roundi(float(normal_power_damage) * (3.0 + level_three_battle._ability_power_flip_bonus()))
    t.assert_equal(148 - level_three_battle.enemy_hp, expected_power_damage, "level-three power flip includes the active ability extension")
    t.assert_equal(level_three_battle.armed_power_flip_level, 0, "power flip is consumed by one direct impact")
    t.assert_true(normal_power_battle._ability_direct_damage_multiplier() > 1.0, "active passive abilities modify direct damage")

    var equipped_profile = ProfileFactory.create_default()
    var equipped_snapshot = BattlePartySnapshot.build(equipped_profile, quest, "run-equipped-ability")
    var equipped_battle = BattleSimulation.new(quest, "run-equipped-ability", equipped_snapshot)
    equipped_battle.player_hp = 100
    equipped_battle.skill_slots[0]["skill_point"] = equipped_battle.skill_slots[0]["max_skill_point"]
    t.assert_true(equipped_battle.activate_skill(0), "equipped leader skill activates")
    t.assert_equal(equipped_battle.player_hp, 120, "equipped orb fixed heal restores ten percent of equipment-adjusted party HP")

    var ability_battle = BattleSimulation.new(quest, "run-ability-effects", {"total_hp": 162, "total_atk": 30, "direct_attack_reference_atk": 30})
    ability_battle.enemy_actions_enabled = false
    ability_battle.player_hp = 100
    ability_battle.skill_slots[1]["skill_point"] = ability_battle.skill_slots[1]["max_skill_point"]
    t.assert_true(ability_battle.activate_skill(1), "onmyoji skill activates fixed-heal ability")
    t.assert_equal(ability_battle.player_hp, 116, "fixed heal restores ten percent of canonical party max HP")

    var base_direct_multiplier := ability_battle._ability_direct_damage_multiplier()
    ability_battle.enemy_conditions["paralysis"] = {"remaining_frames": 60}
    t.assert_true(ability_battle._ability_direct_damage_multiplier() > base_direct_multiplier, "paralysis slayer abilities increase direct damage against a paralyzed enemy")
    ability_battle.enemy_conditions.erase("paralysis")
    for hit in range(10): ability_battle._record_direct_attack()
    t.assert_true(ability_battle._ability_skill_damage_multiplier() > 1.0, "damage-count ability increases skill damage after its recovered threshold")

    var leader_abilities: Array = quest["characters"]["141005"]["abilities"]
    for ability in leader_abilities:
        if str(ability["content_kind"]) == "AddFeverPoint":
            ability_battle.skill_slots[0]["active_abilities"].append(ability.duplicate(true))
        if str(ability["content_kind"]) == "AdditionalDirectAtttackExtend":
            ability_battle.skill_slots[0]["active_abilities"].append(ability.duplicate(true))
    ability_battle.skill_slots[0]["skill_point"] = ability_battle.skill_slots[0]["max_skill_point"]
    var multiplier_before_additional := ability_battle._ability_direct_damage_multiplier()
    t.assert_true(ability_battle.activate_skill(0), "leader skill activates fever ability test")
    t.assert_equal(ability_battle.fever_points, 25, "skill-linked fever ability adds its recovered 0.25 value as 25 points")
    ability_battle._add_fever_points(975)
    t.assert_true(ability_battle.fever_active, "full fever gauge enters fever state")
    t.assert_equal(ability_battle.fever_remaining_frames, 900, "fever uses the original 900-frame base duration")
    for frame in range(900): ability_battle._step_fever()
    t.assert_true(not ability_battle.fever_active, "fever ends after its duration")
    t.assert_equal(ability_battle.fever_points, 0, "expired fever resets its gauge")
    ability_battle.skill_slots[0]["skill_point"] = ability_battle.skill_slots[0]["max_skill_point"]
    t.assert_true(ability_battle._ability_direct_damage_multiplier() > base_direct_multiplier, "skill-max additional attack ability extends direct impact damage")

    BattleTestDriver.defeat_active_enemy(battle)
    var after_first: Dictionary = battle.get_progress_snapshot()
    t.assert_equal(battle.status, "running", "first zako does not clear the quest")
    t.assert_equal(after_first["objective_progress"], 1, "first zako advances the objective once")
    t.assert_true(not battle.enemy_active, "defeated zako is inactive during emitter interval")
    t.assert_true(not battle.world.bodies.has(battle.enemy), "defeated zako body is removed from the world")
    t.assert_equal(battle.frames_until_spawn, 60, "next zako uses the canonical 60-frame interval")
    battle._apply_enemy_damage(99999)
    t.assert_equal(battle.get_progress_snapshot()["objective_progress"], 1, "inactive enemy cannot be counted twice")
    t.assert_equal(battle.frames_until_spawn, 60, "duplicate damage does not alter spawn countdown")
    for frame in range(59):
        battle.step()
    t.assert_true(not battle.enemy_active, "next zako does not spawn one frame early")
    t.assert_equal(battle.frames_until_spawn, 1, "spawn countdown reaches one frame")
    battle.step()
    t.assert_true(battle.enemy_active, "next zako spawns on the sixtieth frame")
    t.assert_true(battle.world.bodies.has(battle.enemy), "respawned zako body returns to the world")
    t.assert_equal(battle.enemy_hp, 148, "respawned zako resets canonical HP")

    while battle.status == "running" and battle.get_progress_snapshot()["zone_index"] == 0:
        if battle.enemy_active:
            BattleTestDriver.defeat_active_enemy(battle)
        else:
            BattleTestDriver.wait_for_enemy(battle)
    var boss_phase: Dictionary = battle.get_progress_snapshot()
    t.assert_equal(battle.status, "running", "eighteenth zako transitions instead of clearing")
    t.assert_equal(boss_phase["zone_index"], 1, "battle advances to the second zone")
    t.assert_equal(boss_phase["objective_kind"], "boss_clear", "second objective is boss clear")
    t.assert_equal(boss_phase["enemy_kind"], "general_boss", "second zone spawns the canonical boss")
    t.assert_equal(battle.enemy_hp, 13009, "boss HP comes from original CN curve calculation")

    var markers: Dictionary = quest["terrain_runtime"]["markers"]
    battle._enter_enemy_state("move1")
    for frame in range(90): battle._step_enemy_state_machine()
    t.assert_near(battle.enemy.position.x, float(markers["p1"][0]), 0.000001, "move1 reaches terrain marker p1")
    t.assert_near(battle.enemy.position.y, float(markers["p1"][1]), 0.000001, "move1 reaches terrain marker p1 vertically")
    battle._enter_enemy_state("move2")
    for frame in range(90): battle._step_enemy_state_machine()
    t.assert_near(battle.enemy.position.x, float(markers["p2"][0]), 0.000001, "move2 reaches terrain marker p2")
    battle._enter_enemy_state("move3")
    for frame in range(90): battle._step_enemy_state_machine()
    t.assert_near(battle.enemy.position.x, float(markers["p3"][0]), 0.000001, "move3 reaches terrain marker p3")

    BattleTestDriver.defeat_active_enemy(battle)
    t.assert_equal(battle.status, "cleared", "boss defeat clears the complete quest")
    t.assert_equal(battle.status_reason, "boss_defeated", "clear reason records the boss defeat")
    var result: Dictionary = battle.build_result("result-battle-1")
    t.assert_equal(result["result_id"], "result-battle-1", "battle result keeps idempotency id")
    t.assert_equal(result["run_id"], "run-battle-1", "battle result is bound to its active run")
    t.assert_equal(result["quest_id"], "1001002", "battle result keeps quest id")
    t.assert_equal(result["rewards"]["free_mana"], 20, "battle result uses CN fixture rewards")
    var cleared_elapsed: int = battle.elapsed_frames
    battle.step()
    t.assert_equal(battle.elapsed_frames, cleared_elapsed, "cleared battle is terminal and immutable")

    var timeout_quest := quest.duplicate(true)
    timeout_quest["battle"]["time_limit_frames"] = 3
    var timeout_battle = BattleSimulation.new(timeout_quest, "run-timeout")
    timeout_battle.step()
    timeout_battle.step()
    t.assert_equal(timeout_battle.status, "running", "battle runs before the exact timeout frame")
    timeout_battle.step()
    t.assert_equal(timeout_battle.status, "failed", "battle fails on the exact timeout frame")
    t.assert_equal(timeout_battle.status_reason, "timeout", "failed battle records timeout reason")
    t.assert_equal(timeout_battle.build_result("result-timeout"), {}, "failed battle produces no clear result")
    var failed_snapshot: Dictionary = timeout_battle.get_progress_snapshot()
    timeout_battle.step()
    t.assert_equal(timeout_battle.get_progress_snapshot(), failed_snapshot, "failed battle is terminal and immutable")
