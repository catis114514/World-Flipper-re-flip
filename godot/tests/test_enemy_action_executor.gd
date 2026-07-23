extends RefCounted

const StaticContentRepository = preload("res://src/content/static_content_repository.gd")
const BattleSimulation = preload("res://src/simulation/battle_simulation.gd")
const EnemyActionExecutor = preload("res://src/simulation/enemy_action_executor.gd")

func run(t) -> void:
    var repository = StaticContentRepository.new()
    t.assert_equal(repository.load_fixture("res://content/fixtures/quest_1001002.json"), OK, "enemy action fixture loads")
    t.assert_equal(repository.load_fixture("res://content/fixtures/quest_1003002.json"), OK, "delayed Fox action fixture loads")
    var quest: Dictionary = repository.get_quest("1001002")
    var actions := {}
    for action_variant in quest["action_assets"]:
        var action: Dictionary = action_variant
        actions[str(action["id"])] = action

    var executor = EnemyActionExecutor.new(Rect2(0.0, 0.0, 720.0, 1280.0))
    var shot_id := "battle/action/enemy/action/general_boss/boss_slango$difficulity10_shot1"
    var created: int = executor.start_action(actions[shot_id], Vector2(360.0, 200.0), Vector2(360.0, 400.0), 30, 1.0)
    t.assert_equal(created, 3, "boss N-way DSL creates three projectiles")
    t.assert_equal(executor.projectiles.size(), 3, "created projectiles are tracked")
    t.assert_equal(executor.projectiles[0]["damage"], 27, "boss shot uses canonical 30 ATK and 0.9 multiplier")
    var damage := 0
    for frame in range(30):
        damage += executor.step(Vector2(360.0, 400.0), 16.0)
    t.assert_equal(damage, 27, "center N-way projectile deterministically hits the target once")

    executor.projectiles.clear()
    executor.projectiles.append({"position": Vector2.ZERO, "velocity": Vector2.ZERO, "remaining_frames": 2, "radius": 8.0, "damage": 10})
    executor.projectiles.append({"position": Vector2.ZERO, "velocity": Vector2.ZERO, "remaining_frames": 2, "radius": 8.0, "damage": 20})
    t.assert_equal(executor.step(Vector2.ZERO, 16.0), 20, "overlapping projectile ring applies only the strongest hit in one interval")

    executor.clear()
    var skill_id := "battle/action/enemy/action/general_boss/boss_slango$difficulity10_skill_shot1"
    t.assert_equal(executor.start_action(actions[skill_id], Vector2(360.0, 200.0), Vector2(360.0, 400.0), 30, 1.0), 30, "boss skill DSL creates five six-way rings")
    t.assert_equal(executor.projectiles[0]["damage"], 86, "heavy cannon uses the canonical 2.875 multiplier")

    executor.clear()
    var funnel_id := "battle/action/enemy/action/general_boss/boss_slango$difficulity10_funnel_shot1_single"
    t.assert_equal(executor.start_action(actions[funnel_id], Vector2.ZERO, Vector2.ZERO, 30, 1.0), 0, "funnel DSL creates a spawn event rather than a projectile")
    var funnel_events := executor.consume_spawn_events()
    t.assert_equal(funnel_events.size(), 1, "funnel spawn event is retained")
    t.assert_equal(funnel_events[0]["enemy_id"], "slango", "funnel event keeps the canonical enemy id")
    t.assert_equal(funnel_events[0]["level"], 15, "funnel event keeps the canonical level")

    var fragile_party := {"total_hp": 1, "total_atk": 30, "direct_attack_reference_atk": 30}
    var battle = BattleSimulation.new(quest, "run-enemy-action", fragile_party)
    battle.enemy_action_frames_until_fire = 1
    battle.set_player_state(Vector2(360.0, 400.0), Vector2.ZERO)
    battle.step()
    t.assert_true(not battle.last_enemy_action_id.is_empty(), "enemy schedule invokes its Action DSL")
    t.assert_true(battle.get_progress_snapshot()["projectile_count"] > 0, "scheduled action exposes active projectiles")
    for frame in range(30):
        if battle.status != "running":
            break
        battle.set_player_state(Vector2(360.0, 400.0), Vector2.ZERO)
        battle.step()
    t.assert_equal(battle.status, "failed", "enemy projectile damage can defeat the party")
    t.assert_equal(battle.status_reason, "party_defeated", "party defeat has a distinct terminal reason")
    t.assert_equal(battle.player_hp, 0, "party defeat clamps HP to zero")
    t.assert_equal(battle.build_result("result-defeated"), {}, "defeated party produces no clear result")

    var durable_party := {"total_hp": 999999, "total_atk": 30, "direct_attack_reference_atk": 30}
    var fox_quest: Dictionary = repository.get_quest("1003002")
    var fox_actions := {}
    for action_variant in fox_quest["action_assets"]:
        var fox_action: Dictionary = action_variant
        fox_actions[str(fox_action["id"])] = fox_action
    var fox_skill_id := "battle/action/enemy/action/general_boss/boss_fox$difficulity10_skill_shot1"
    executor.clear()
    t.assert_equal(executor.start_action(fox_actions[fox_skill_id], Vector2(120.0, 300.0), Vector2(520.0, 300.0), 51, 1.0), 9, "starting the Fox skill emits only its frame-zero waves")
    t.assert_equal(executor.projectiles.size(), 9, "delayed Fox waves are not flattened into immediate projectiles")

    var timing_battle = BattleSimulation.new(fox_quest, "run-integrated-fox-timing", durable_party)
    timing_battle._enter_zone(1)
    timing_battle.action_executor.clear()
    var timing_serial := int(timing_battle.get_progress_snapshot()["enemies"][0]["serial"])
    var timing_actor: Dictionary = timing_battle._find_enemy_instance(timing_serial)
    timing_actor["state_machine"] = {}
    timing_actor["action_sequence"] = [fox_skill_id]
    timing_actor["action_index"] = 0
    timing_actor["action_frames_until_fire"] = 1
    var timing_definition: Dictionary = timing_actor["definition"].duplicate(true)
    timing_definition["action_schedule"] = {"interval_frames": 10000}
    timing_actor["definition"] = timing_definition
    timing_battle.enemy_action_frames_until_fire = 1
    timing_battle.set_player_state(Vector2(520.0, 300.0), Vector2.ZERO)
    timing_battle.step()
    t.assert_equal(timing_battle.pending_enemy_action_events.size(), 4, "integrated Fox action queues its delayed waves")
    for frame in range(11):
        timing_battle.set_player_state(Vector2(520.0, 300.0), Vector2.ZERO)
        timing_battle.step()
    t.assert_equal(timing_battle.pending_enemy_action_events.size(), 4, "integrated frame-12 Fox wave does not fire on frame 11")
    timing_battle.set_player_state(Vector2(520.0, 300.0), Vector2.ZERO)
    timing_battle.step()
    t.assert_equal(timing_battle.pending_enemy_action_events.size(), 2, "integrated frame-12 Fox wave fires on frame 12")

    var delayed_battle = BattleSimulation.new(fox_quest, "run-delayed-fox-action", durable_party)
    delayed_battle._enter_zone(1)
    delayed_battle.enemy_actions_enabled = false
    delayed_battle.action_executor.clear()
    var fox_serial := int(delayed_battle.get_progress_snapshot()["enemies"][0]["serial"])
    var fox_actor: Dictionary = delayed_battle._find_enemy_instance(fox_serial)
    var fox_body = fox_actor["body"]
    fox_body.position = Vector2(120.0, 300.0)
    delayed_battle.set_player_state(Vector2(520.0, 300.0), Vector2.ZERO)
    delayed_battle._invoke_enemy_action(fox_actor, fox_skill_id)
    t.assert_equal(delayed_battle.action_executor.projectiles.size(), 9, "Fox skill creates the frame-zero 7+2 projectiles immediately")
    t.assert_equal(delayed_battle.pending_enemy_action_events.size(), 4, "Fox skill queues its two frame-12 and two frame-24 patterns")
    for frame in range(11):
        delayed_battle.elapsed_frames += 1
        delayed_battle._step_pending_enemy_action_events()
    t.assert_equal(delayed_battle.action_executor.projectiles.size(), 9, "frame-12 Fox wave does not fire one frame early")
    fox_body.position = Vector2(180.0, 360.0)
    var moved_player_position: Vector2 = Vector2(540.0, 480.0)
    delayed_battle.set_player_state(moved_player_position, Vector2.ZERO)
    delayed_battle.elapsed_frames += 1
    delayed_battle._step_pending_enemy_action_events()
    t.assert_equal(delayed_battle.action_executor.projectiles.size(), 18, "frame-12 Fox wave adds its canonical 7+2 projectiles")
    t.assert_equal(delayed_battle.action_executor.projectiles[12]["position"], fox_body.position, "delayed Fox wave reads the owner's current position")
    var expected_aim: Vector2 = (moved_player_position - Vector2(fox_body.position)).normalized()
    var actual_aim: Vector2 = Vector2(delayed_battle.action_executor.projectiles[12]["velocity"]).normalized()
    t.assert_near(actual_aim.x, expected_aim.x, 0.000001, "delayed Fox wave reads the player's current horizontal aim")
    t.assert_near(actual_aim.y, expected_aim.y, 0.000001, "delayed Fox wave reads the player's current vertical aim")
    for frame in range(11):
        delayed_battle.elapsed_frames += 1
        delayed_battle._step_pending_enemy_action_events()
    t.assert_equal(delayed_battle.action_executor.projectiles.size(), 18, "frame-24 Fox wave does not fire one frame early")
    delayed_battle.elapsed_frames += 1
    delayed_battle._step_pending_enemy_action_events()
    t.assert_equal(delayed_battle.action_executor.projectiles.size(), 27, "frame-24 Fox wave adds its canonical 7+2 projectiles")
    t.assert_equal(delayed_battle.pending_enemy_action_events.size(), 0, "all Fox skill waves leave no stale pending event")
    delayed_battle._invoke_enemy_action(fox_actor, fox_skill_id)
    t.assert_equal(delayed_battle.pending_enemy_action_events.size(), 4, "a repeated Fox skill queues a fresh delayed sequence")
    delayed_battle._deactivate_enemy_instance(fox_serial)
    t.assert_equal(delayed_battle.pending_enemy_action_events.size(), 0, "enemy teardown cancels its delayed Fox waves")

    var fox_state_battle = BattleSimulation.new(fox_quest, "run-fox-state-cycle", durable_party)
    fox_state_battle._enter_zone(1)
    var fox_states_seen := {}
    var left_fox_neutral := false
    var fox_cycle_frames := 0
    while fox_state_battle.status == "running" and fox_cycle_frames < 4000:
        fox_states_seen[fox_state_battle.enemy_state_id] = true
        if fox_state_battle.enemy_state_id != "neutral1":
            left_fox_neutral = true
        fox_state_battle.step()
        fox_cycle_frames += 1
        if left_fox_neutral and fox_state_battle.enemy_state_id == "neutral1":
            break
    t.assert_true(fox_cycle_frames < 4000, "Fox state machine completes one full cycle")
    t.assert_equal(fox_states_seen.size(), 37, "Fox cycle visits every canonical state")
    t.assert_equal(fox_state_battle.status, "running", "Fox p0-p4 fallback movement does not fail the battle")

    var state_battle = BattleSimulation.new(quest, "run-boss-state-machine", durable_party)
    state_battle._enter_zone(1)
    t.assert_equal(state_battle.enemy_state_id, "neutral1", "boss starts in its canonical neutral1 state")
    t.assert_equal(state_battle.enemy_state_frames_remaining, 30, "neutral1 uses the canonical 30-frame duration")
    for frame in range(62):
        state_battle.step()
    var funnel_action_id := "battle/action/enemy/action/general_boss/boss_slango$difficulity10_funnel_shot1_single"
    t.assert_equal(state_battle.last_enemy_action_id, funnel_action_id, "canonical state chain invokes funnel1_fire first")
    t.assert_equal(state_battle.enemy_state_id, "funnel_fire1", "boss reaches the first funnel fire state")
    t.assert_equal(state_battle.funnel_spawn_count, 1, "first funnel fire executes one spawn command")
    t.assert_equal(state_battle.funnel_entities.size(), 1, "funnel command creates one active entity")
    t.assert_equal(state_battle.funnel_entities[0]["atk"], 23, "level-15 funnel uses canonical ATK")
    state_battle.action_executor.clear()
    for frame in range(118):
        state_battle._step_funnel_entities()
    t.assert_equal(state_battle.last_funnel_action_id, "", "funnel does not fire one frame early")
    state_battle._step_funnel_entities()
    t.assert_equal(state_battle.last_funnel_action_id, "battle/action/enemy/action/zako/zako_slango$difficulity10_shot1", "funnel fires the canonical zako shot")
    t.assert_equal(state_battle.action_executor.projectiles.size(), 1, "funnel attack creates a projectile")

    var normal_action_id := "battle/action/enemy/action/general_boss/boss_slango$difficulity10_shot1"
    var frames_to_normal := 0
    while state_battle.status == "running" and state_battle.last_enemy_action_id != normal_action_id and frames_to_normal < 300:
        state_battle.step()
        frames_to_normal += 1
    t.assert_equal(state_battle.last_enemy_action_id, normal_action_id, "state chain reaches shot1_fire after the movement adapter")
    t.assert_equal(state_battle.enemy_state_id, "shot1_fire1", "normal attack is bound to the canonical fire state")

    var skill_action_id := "battle/action/enemy/action/general_boss/boss_slango$difficulity10_skill_shot1"
    var frames_to_skill := 0
    while state_battle.status == "running" and state_battle.last_enemy_action_id != skill_action_id and frames_to_skill < 1200:
        state_battle.step()
        frames_to_skill += 1
    t.assert_equal(state_battle.last_enemy_action_id, skill_action_id, "state chain eventually reaches skill1_fire")
    t.assert_equal(state_battle.enemy_state_id, "skill1_fire1", "skill action is bound to the canonical fire state")

    var funnel_battle = BattleSimulation.new(quest, "run-damageable-funnel", durable_party)
    funnel_battle._enter_zone(1)
    funnel_battle.enemy_actions_enabled = false
    funnel_battle._invoke_enemy_action(funnel_action_id)
    t.assert_equal(funnel_battle.funnel_entities.size(), 1, "funnel damage test starts with one entity")
    var damageable_funnel: Dictionary = funnel_battle.funnel_entities[0]
    t.assert_equal(damageable_funnel["hp"], 132, "funnel entity owns canonical HP")
    t.assert_true(funnel_battle.world.bodies.has(damageable_funnel["body"]), "funnel owns a collision body in the fixed-step world")
    funnel_battle._apply_funnel_damage(int(damageable_funnel["serial"]), 122)
    t.assert_equal(funnel_battle.funnel_entities[0]["hp"], 10, "funnel damage is tracked independently from boss HP")
    var funnel_body = funnel_battle.funnel_entities[0]["body"]
    funnel_body.position = Vector2(120.0, 500.0)
    funnel_battle.funnel_entities[0]["position"] = funnel_body.position
    funnel_battle.set_player_state(funnel_body.position + Vector2(-31.0, 0.0), Vector2(15.0, 0.0))
    funnel_battle.step()
    t.assert_equal(funnel_battle.funnel_entities.size(), 0, "player impact can destroy a funnel")
    t.assert_true(not funnel_battle.world.bodies.has(funnel_body), "destroyed funnel body is removed without a ghost collider")
    t.assert_equal(funnel_battle.enemy_hp, 13009, "destroying a funnel does not damage or complete the boss objective")
