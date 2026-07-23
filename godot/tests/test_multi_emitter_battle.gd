extends RefCounted

const StaticContentRepository = preload("res://src/content/static_content_repository.gd")
const BattleSimulation = preload("res://src/simulation/battle_simulation.gd")

func run(t) -> void:
    var repository = StaticContentRepository.new()
    t.assert_equal(repository.load_fixture("res://content/fixtures/quest_1001002.json"), OK, "single-emitter compatibility fixture loads")
    t.assert_equal(repository.load_fixture("res://content/fixtures/quest_1002001.json"), OK, "multi-emitter fixture loads")
    t.assert_equal(repository.load_fixture("res://content/fixtures/quest_1002002.json"), OK, "third multi-emitter fixture loads")
    t.assert_equal(repository.load_fixture("res://content/fixtures/quest_1003002.json"), OK, "fourth multi-emitter fixture loads")
    var quest: Dictionary = repository.get_quest("1002001")

    var poison_cooldown_battle = BattleSimulation.new(quest, "run-poison-cooldown", {"total_hp": 162, "total_atk": 30, "direct_attack_reference_atk": 30})
    poison_cooldown_battle.enemy_actions_enabled = false
    var poison_target: Dictionary = poison_cooldown_battle.get_progress_snapshot()["enemies"][0]
    poison_cooldown_battle._apply_enemy_damage_to_serial(int(poison_target["serial"]), int(poison_target["hp"]) - 1)
    var poison_actor: Dictionary = poison_cooldown_battle._find_enemy_instance(int(poison_target["serial"]))
    poison_actor["conditions"]["poison"] = {"remaining_frames": 60, "frames_until_tick": 1, "tick_frames": 60, "source_atk": 1, "strength_raw": 1000.0}
    poison_cooldown_battle.step()
    t.assert_equal(poison_cooldown_battle.get_progress_snapshot()["emitters"][0]["frames_until_spawn"], 60, "poison kill starts a full emitter cooldown after the emitter phase")

    var single_quest: Dictionary = repository.get_quest("1001002")
    var delayed_funnel_battle = BattleSimulation.new(single_quest, "run-delayed-funnel-target", {"total_hp": 162, "total_atk": 30, "direct_attack_reference_atk": 30})
    delayed_funnel_battle._enter_zone(1)
    delayed_funnel_battle.enemy_actions_enabled = false
    delayed_funnel_battle.skill_slots[2]["skill_point"] = delayed_funnel_battle.skill_slots[2]["max_skill_point"]
    t.assert_true(delayed_funnel_battle.activate_skill(2), "delayed skill captures targets before a funnel exists")
    delayed_funnel_battle._invoke_enemy_action("battle/action/enemy/action/general_boss/boss_slango$difficulity10_funnel_shot1_single")
    var late_funnel_hp := int(delayed_funnel_battle.funnel_entities[0]["hp"])
    delayed_funnel_battle.funnel_entities[0]["position"] = delayed_funnel_battle.player.position
    delayed_funnel_battle.funnel_entities[0]["body"].position = delayed_funnel_battle.player.position
    for frame in range(80):
        delayed_funnel_battle.step()
    t.assert_equal(delayed_funnel_battle.funnel_entities[0]["hp"], late_funnel_hp, "delayed skill does not acquire a funnel spawned after cast time")

    var terminal_event_battle = BattleSimulation.new(single_quest, "run-terminal-skill-events", {"total_hp": 162, "total_atk": 30, "direct_attack_reference_atk": 30})
    terminal_event_battle._enter_zone(1)
    var terminal_serial := int(terminal_event_battle.get_progress_snapshot()["enemies"][0]["serial"])
    terminal_event_battle._apply_enemy_damage_to_serial(terminal_serial, terminal_event_battle.enemy_hp - 1)
    terminal_event_battle.pending_player_skill_events.clear()
    terminal_event_battle.pending_player_skill_events.append({"kind": "condition", "frames_remaining": 0, "slot": 0, "target_serials": [terminal_serial], "condition": {"kind": "flying", "duration_frames": 60}})
    terminal_event_battle.pending_player_skill_events.append({"kind": "damage", "frames_remaining": 0, "slot": 0, "target_serials": [terminal_serial], "target_funnel_serials": []})
    terminal_event_battle._flush_ready_player_skill_events()
    t.assert_equal(terminal_event_battle.status, "cleared", "ready damage event can clear the terminal boss")
    t.assert_true(not terminal_event_battle.party_conditions.has("flying"), "ready condition events do not mutate state after terminal clear")
    t.assert_equal(terminal_event_battle.pending_player_skill_events.size(), 0, "terminal clear discards remaining player events")
    t.assert_equal(terminal_event_battle.current_enemy_id, "", "terminal facade clears stale enemy identity")
    t.assert_equal(terminal_event_battle.enemy.position, Vector2.ZERO, "terminal facade clears stale enemy position")

    var battle = BattleSimulation.new(quest, "run-multi-emitter", {"total_hp": 162, "total_atk": 30, "direct_attack_reference_atk": 30})
    battle.enemy_actions_enabled = false

    var initial: Dictionary = battle.get_progress_snapshot()
    t.assert_equal(initial["active_enemy_count"], 2, "both zone emitters own an active enemy")
    t.assert_equal(initial["enemies"].size(), 2, "multi-emitter snapshot exposes both bodies")
    t.assert_equal(initial["enemies"][0]["enemy_id"], "slango", "first emitter remains the first deterministic body")
    t.assert_equal(initial["enemies"][1]["enemy_id"], "spirit", "second emitter creates Spirit concurrently")
    t.assert_true(initial["enemies"][0]["position"] != initial["enemies"][1]["position"], "fallback adapter separates concurrent spawn bodies")

    var slango_serial := int(initial["enemies"][0]["serial"])
    var spirit_serial := int(initial["enemies"][1]["serial"])
    battle._apply_enemy_damage_to_serial(slango_serial, 999999)
    var after_slango: Dictionary = battle.get_progress_snapshot()
    t.assert_equal(after_slango["objective_progress"], 1, "defeating one concurrent enemy advances the objective once")
    t.assert_equal(after_slango["active_enemy_count"], 1, "the other emitter enemy remains active")
    t.assert_equal(after_slango["enemies"][0]["enemy_id"], "spirit", "the surviving body keeps its owner identity")
    t.assert_equal(after_slango["emitters"][0]["frames_until_spawn"], 60, "first emitter enters its own 60-frame cooldown")
    t.assert_equal(after_slango["emitters"][1]["active_serial"], spirit_serial, "second emitter remains subscribed to Spirit")

    for frame in range(59):
        battle.step()
    t.assert_equal(battle.get_progress_snapshot()["active_enemy_count"], 1, "first emitter does not respawn early")
    battle.step()
    var after_respawn: Dictionary = battle.get_progress_snapshot()
    t.assert_equal(after_respawn["active_enemy_count"], 2, "first emitter respawns independently on frame sixty")
    t.assert_true(int(after_respawn["emitters"][0]["active_serial"]) != slango_serial, "respawn receives a stable new serial")

    battle._apply_enemy_damage_to_serial(spirit_serial, 999999)
    t.assert_equal(battle.get_progress_snapshot()["objective_progress"], 2, "Spirit defeat is counted exactly once")
    t.assert_equal(battle.get_progress_snapshot()["emitters"][1]["frames_until_spawn"], 120, "second emitter keeps its 120-frame cooldown")

    var guard := _clear_zako_zone(battle, 2000)
    t.assert_true(guard < 2000, "multi-emitter objective completes without a runaway scheduler")
    t.assert_equal(battle.current_zone_index, 1, "twenty concurrent/respawned enemies transition to the boss zone")
    t.assert_equal(battle.current_enemy_id, "spirit", "second quest enters the Spirit boss")
    t.assert_equal(battle.enemy_hp, 18295, "Spirit boss HP uses the canonical CN curve")
    t.assert_equal(battle.enemy_state_machine["states"].size(), 31, "Spirit boss state machine is active in simulation")
    t.assert_equal(battle.enemy_state_frames_remaining, 60, "Spirit neutral state resolves its canonical time")

    battle._apply_enemy_damage_to_serial(int(battle.get_progress_snapshot()["enemies"][0]["serial"]), 99999999)
    t.assert_equal(battle.status, "cleared", "Spirit boss defeat clears the second quest")
    t.assert_equal(battle.build_result("result-multi-emitter")["quest_id"], "1002001", "second quest result keeps its quest id")

    var third_battle = BattleSimulation.new(repository.get_quest("1002002"), "run-third-multi-emitter", {"total_hp": 162, "total_atk": 30, "direct_attack_reference_atk": 30})
    third_battle.enemy_actions_enabled = false
    var third_initial: Dictionary = third_battle.get_progress_snapshot()
    t.assert_equal(third_initial["objective_target"], 22, "third quest exposes its twenty-two-enemy objective")
    t.assert_equal(third_initial["active_enemy_count"], 2, "third quest starts both checked emitters")
    var third_guard := _clear_zako_zone(third_battle, 2500)
    t.assert_true(third_guard < 2500, "third multi-emitter objective completes without a runaway scheduler")
    t.assert_equal(third_battle.current_zone_index, 1, "twenty-two defeats transition to the third quest boss")
    t.assert_equal(third_battle.current_enemy_id, "slango", "third quest activates the Slango boss")
    t.assert_equal(third_battle.enemy_hp, 12196, "third quest applies its canonical Slango boss HP")
    t.assert_equal(third_battle.enemy_state_machine["states"].size(), 36, "third quest activates the complete Slango state machine")
    third_battle._apply_enemy_damage_to_serial(int(third_battle.get_progress_snapshot()["enemies"][0]["serial"]), 99999999)
    t.assert_equal(third_battle.status, "cleared", "Slango boss defeat clears the third quest")
    t.assert_equal(third_battle.build_result("result-third-multi-emitter")["quest_id"], "1002002", "third quest result keeps its quest id")

    var fourth_battle = BattleSimulation.new(repository.get_quest("1003002"), "run-fourth-multi-emitter", {"total_hp": 162, "total_atk": 30, "direct_attack_reference_atk": 30})
    fourth_battle.enemy_actions_enabled = false
    var fourth_initial: Dictionary = fourth_battle.get_progress_snapshot()
    t.assert_equal(fourth_initial["objective_target"], 20, "fourth quest exposes its twenty-enemy objective")
    t.assert_equal(fourth_initial["active_enemy_count"], 3, "fourth quest starts all three checked emitters")
    t.assert_equal(fourth_initial["enemies"].map(func(enemy): return str(enemy["enemy_id"])), ["slango", "fox", "one_eyed_rabbit"], "fourth quest keeps deterministic emitter ownership order")
    t.assert_equal(fourth_initial["emitters"].map(func(emitter): return int(emitter["interval_frames"])), [60, 120, 150], "fourth quest keeps all canonical emitter cooldowns")
    var fourth_guard := _clear_zako_zone(fourth_battle, 2500)
    t.assert_true(fourth_guard < 2500, "three-emitter objective completes without a runaway scheduler")
    t.assert_equal(fourth_battle.current_zone_index, 1, "twenty defeats transition to the Fox boss")
    t.assert_equal(fourth_battle.current_enemy_id, "fox", "fourth quest activates the Fox boss")
    t.assert_equal(fourth_battle.enemy_hp, 33911, "fourth quest applies canonical Fox boss HP")
    t.assert_equal(fourth_battle.enemy_state_machine["states"].size(), 37, "fourth quest activates the complete Fox state machine")
    t.assert_equal(fourth_battle.enemy_state_frames_remaining, 1, "Fox neutral state keeps its canonical one-frame duration")
    fourth_battle._apply_enemy_damage_to_serial(int(fourth_battle.get_progress_snapshot()["enemies"][0]["serial"]), 99999999)
    t.assert_equal(fourth_battle.status, "cleared", "Fox boss defeat clears the fourth quest")
    t.assert_equal(fourth_battle.build_result("result-fourth-multi-emitter")["quest_id"], "1003002", "fourth quest result keeps its quest id")

func _clear_zako_zone(battle, max_steps: int) -> int:
    var steps := 0
    while battle.status == "running" and battle.current_zone_index == 0 and steps < max_steps:
        var active_enemies: Array = battle.get_progress_snapshot()["enemies"]
        for enemy_snapshot in active_enemies:
            battle._apply_enemy_damage_to_serial(int(enemy_snapshot["serial"]), 999999)
        if battle.status == "running" and battle.current_zone_index == 0 and battle.enemy_instances.is_empty():
            battle.step()
        steps += 1
    return steps
