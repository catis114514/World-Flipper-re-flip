class_name BattleSimulation
extends RefCounted

const SimBodyScript = preload("res://src/simulation/sim_body.gd")
const FixedStepWorldScript = preload("res://src/simulation/fixed_step_world.gd")
const FlipperStateScript = preload("res://src/simulation/flipper_state.gd")
const FlipperColliderScript = preload("res://src/simulation/flipper_collider.gd")
const EnemyActionExecutorScript = preload("res://src/simulation/enemy_action_executor.gd")

var quest: Dictionary
var run_id: String
var party_snapshot: Dictionary
var party_attack := 1
var direct_attack_reference_atk := 1
var player_hp := 1
var player_max_hp := 1
var world: FixedStepWorld
var action_executor
var enemy_actions_enabled := true
var enemy_action_frames_until_fire := 0
var enemy_action_sequence: Array = []
var enemy_action_index := 0
var enemy_state_machine: Dictionary = {}
var enemy_state_id := ""
var enemy_state_frames_remaining := 0
var last_enemy_action_id := ""
var funnel_spawn_count := 0
var funnel_entities: Array[Dictionary] = []
var next_funnel_serial := 1
var last_funnel_action_id := ""
var current_enemy_definition: Dictionary = {}
var player: SimBody
var enemy: SimBody
var left_flipper: FlipperState
var right_flipper: FlipperState
var left_collider: FlipperCollider
var right_collider: FlipperCollider
var enemy_hp: int
var status := "running"
var status_reason := ""
var elapsed_frames := 0
var time_limit_frames := 0
var current_zone_index := -1
var objective_kind := ""
var objective_target := 0
var objective_progress := 0
var current_enemy_id := ""
var current_enemy_kind := ""
var enemy_active := false
var enemy_spawn_serial := 0
var frames_until_spawn := 0
var spawn_interval_frames := 0
var enemy_move_start := Vector2.ZERO
var enemy_move_target := Vector2.ZERO
var enemy_move_total_frames := 0
var enemy_move_elapsed_frames := 0
var skill_slots: Array[Dictionary] = []
var combo_count := 0
var power_flip_level := 0
var armed_power_flip_level := 0
var skill_point_gain_per_direct_attack := 50
var power_flip_combo_thresholds: Array = [9, 15, 39]
var pending_player_skill_events: Array[Dictionary] = []
var party_conditions: Dictionary = {}
var enemy_conditions: Dictionary = {}
var direct_attack_count := 0
var fever_points := 0

func _init(quest_data: Dictionary, session_run_id: String, battle_party: Dictionary = {}) -> void:
    quest = quest_data.duplicate(true)
    run_id = session_run_id
    party_snapshot = battle_party.duplicate(true)
    party_attack = maxi(1, int(party_snapshot.get("total_atk", 1)))
    direct_attack_reference_atk = maxi(1, int(party_snapshot.get("direct_attack_reference_atk", party_attack)))
    var arena: Dictionary = quest["arena"]
    var arena_size := Vector2(float(arena["width"]), float(arena["height"]))
    var gravity_per_step := Vector2(0.0, float(arena["gravity_y"]) / 3600.0)
    var arena_bounds := Rect2(Vector2.ZERO, arena_size)
    world = FixedStepWorldScript.new(gravity_per_step, arena_bounds)
    world.set_terrain_segments(quest["terrain_runtime"]["segments"])
    action_executor = EnemyActionExecutorScript.new(arena_bounds)
    player_max_hp = maxi(1, int(party_snapshot.get("total_hp", _default_party_hp())))
    player_hp = player_max_hp
    skill_point_gain_per_direct_attack = maxi(1, int(party_snapshot.get("skill_point_gain_per_direct_attack", quest["battle_source_defaults"].get("skill_point_gain_per_direct_attack", 50))))
    power_flip_combo_thresholds = party_snapshot.get("power_flip_combo_thresholds", quest["battle_source_defaults"].get("power_flip_combo_thresholds", [9, 15, 39])).duplicate()
    _build_skill_slots()

    player = SimBodyScript.new()
    player.tag = "player"
    player.position = Vector2(arena_size.x * 0.5, arena_size.y * 0.72)
    player.radius = 16.0
    player.restitution = 0.9
    player.limit_max_linear_velocity = true
    player.max_linear_velocity = 80.0

    enemy = SimBodyScript.new()
    enemy.tag = "enemy"
    enemy.dynamic = false
    enemy.radius = 0.0
    enemy.restitution = 0.9

    world.add_body(player)

    left_flipper = FlipperStateScript.new(true, 0.05, 0.02, 0.10, 0.65)
    right_flipper = FlipperStateScript.new(false, 0.05, 0.02, 0.10, 0.65)
    left_collider = FlipperColliderScript.new(
        left_flipper, Vector2(arena_size.x * 0.35, arena_size.y * 0.82), Vector2.RIGHT, 130.0, 12.0
    )
    right_collider = FlipperColliderScript.new(
        right_flipper, Vector2(arena_size.x * 0.65, arena_size.y * 0.82), Vector2.LEFT, 130.0, 12.0
    )

    time_limit_frames = int(quest["battle"]["time_limit_frames"])
    _enter_zone(0)

func set_player_state(new_position: Vector2, new_velocity: Vector2) -> void:
    if status != "running":
        return
    player.position = new_position
    player.velocity = new_velocity

func set_flippers_pressed(is_pressed: bool) -> void:
    if status != "running":
        return
    if is_pressed:
        left_flipper.on_pressed()
        right_flipper.on_pressed()
    else:
        left_flipper.on_released()
        right_flipper.on_released()

func step() -> void:
    if status != "running":
        return
    elapsed_frames += 1
    _step_player_skill_runtime()
    if status != "running":
        return
    if elapsed_frames >= time_limit_frames:
        _fail("timeout")
        return

    left_flipper.update()
    right_flipper.update()
    left_flipper.integrate(1.0)
    right_flipper.integrate(1.0)
    var hit_flipper := left_collider.resolve_ball(player)
    hit_flipper = right_collider.resolve_ball(player) or hit_flipper
    if hit_flipper and combo_count > 0:
        armed_power_flip_level = _power_flip_level_for_combo(combo_count)
        power_flip_level = armed_power_flip_level
        combo_count = 0

    if frames_until_spawn > 0:
        frames_until_spawn -= 1
        if frames_until_spawn == 0:
            _spawn_zone_enemy()

    world.step(1.0)
    if enemy_active:
        for contact in world.contacts:
            var first: SimBody = contact[0]
            var second: SimBody = contact[1]
            var other: SimBody = second if first.tag == "player" else first if second.tag == "player" else null
            if other == null:
                continue
            var impact_damage := maxi(1, roundi(float(contact[2]) * float(party_attack) * _party_attack_multiplier() * _ability_direct_damage_multiplier() / float(direct_attack_reference_atk)))
            if armed_power_flip_level > 0:
                var power_flip_multipliers := [1.0, 1.5, 2.0, 3.0]
                impact_damage = maxi(1, roundi(float(impact_damage) * (float(power_flip_multipliers[armed_power_flip_level]) + _ability_power_flip_bonus())))
                armed_power_flip_level = 0
            if other.tag == "enemy":
                _apply_enemy_damage(impact_damage)
                _record_direct_attack()
                break
            if other.tag.begins_with("funnel:"):
                _apply_funnel_damage(int(other.tag.trim_prefix("funnel:")), impact_damage)
                _record_direct_attack()
    if status != "running":
        return
    if enemy_active and enemy_actions_enabled:
        _step_enemy_actions()
        _step_funnel_entities()
    var projectile_damage: int = action_executor.step(player.position, player.radius)
    if projectile_damage > 0:
        player_hp = maxi(0, player_hp - projectile_damage)
        if player_hp == 0:
            _fail("party_defeated")

func get_progress_snapshot() -> Dictionary:
    return {
        "status": status,
        "status_reason": status_reason,
        "elapsed_frames": elapsed_frames,
        "zone_index": current_zone_index,
        "zone_count": quest["zones"].size(),
        "objective_kind": objective_kind,
        "objective_progress": objective_progress,
        "objective_target": objective_target,
        "enemy_active": enemy_active,
        "enemy_id": current_enemy_id,
        "enemy_kind": current_enemy_kind,
        "enemy_hp": enemy_hp,
        "frames_until_spawn": frames_until_spawn,
        "party_attack": party_attack,
        "player_hp": player_hp,
        "player_max_hp": player_max_hp,
        "projectile_count": action_executor.projectiles.size(),
        "last_enemy_action_id": last_enemy_action_id,
        "enemy_state_id": enemy_state_id,
        "enemy_state_frames_remaining": enemy_state_frames_remaining,
        "funnel_spawn_count": funnel_spawn_count,
        "active_funnel_count": funnel_entities.size(),
        "last_funnel_action_id": last_funnel_action_id,
        "enemy_position": [enemy.position.x, enemy.position.y],
        "combo_count": combo_count,
        "power_flip_level": power_flip_level,
        "armed_power_flip_level": armed_power_flip_level,
        "skill_slots": get_skill_snapshots(),
        "party_conditions": party_conditions.duplicate(true),
        "enemy_conditions": enemy_conditions.duplicate(true),
        "pending_player_skill_event_count": pending_player_skill_events.size(),
        "direct_attack_count": direct_attack_count,
        "fever_points": fever_points,
    }

func get_skill_snapshots() -> Array[Dictionary]:
    return skill_slots.duplicate(true)

func activate_skill(slot_index: int) -> bool:
    if status != "running" or slot_index < 0 or slot_index >= skill_slots.size():
        return false
    var slot: Dictionary = skill_slots[slot_index]
    if int(slot["skill_point"]) < int(slot["max_skill_point"]):
        return false
    slot["skill_point"] = 0
    _apply_skill_activation_abilities(slot_index)
    var runtime: Dictionary = slot["runtime"]
    pending_player_skill_events.append({"kind": "damage", "frames_remaining": int(runtime.get("delay_frames", 0)), "slot": slot_index})
    for condition in runtime.get("conditions", []):
        pending_player_skill_events.append({"kind": "condition", "frames_remaining": int(condition.get("delay_frames", 0)), "slot": slot_index, "condition": condition.duplicate(true)})
    _flush_ready_player_skill_events()
    return true

func _step_player_skill_runtime() -> void:
    for key in party_conditions.keys():
        var condition: Dictionary = party_conditions[key]
        condition["remaining_frames"] = int(condition["remaining_frames"]) - 1
        if int(condition["remaining_frames"]) <= 0:
            party_conditions.erase(key)
    player.disable_gravity = party_conditions.has("flying")
    if enemy_conditions.has("poison") and enemy_active:
        var poison: Dictionary = enemy_conditions["poison"]
        poison["remaining_frames"] = int(poison["remaining_frames"]) - 1
        poison["frames_until_tick"] = int(poison["frames_until_tick"]) - 1
        if int(poison["frames_until_tick"]) <= 0:
            var poison_damage := maxi(1, floori(float(poison["source_atk"]) * float(poison["strength_raw"]) / 1000.0))
            _apply_enemy_damage(poison_damage)
            poison["frames_until_tick"] = int(poison["tick_frames"])
        if int(poison["remaining_frames"]) <= 0:
            enemy_conditions.erase("poison")
    for event in pending_player_skill_events:
        event["frames_remaining"] = int(event["frames_remaining"]) - 1
    _flush_ready_player_skill_events()

func _flush_ready_player_skill_events() -> void:
    for index in range(pending_player_skill_events.size() - 1, -1, -1):
        var event: Dictionary = pending_player_skill_events[index]
        if int(event["frames_remaining"]) > 0:
            continue
        var slot_index := int(event["slot"])
        if slot_index >= 0 and slot_index < skill_slots.size():
            if str(event["kind"]) == "damage":
                _execute_player_skill_damage(slot_index)
            elif str(event["kind"]) == "condition":
                _apply_player_skill_condition(slot_index, event["condition"])
        pending_player_skill_events.remove_at(index)

func _execute_player_skill_damage(slot_index: int) -> void:
    var slot: Dictionary = skill_slots[slot_index]
    var runtime: Dictionary = slot["runtime"]
    var damage := maxi(1, floori(float(slot["atk"]) * _party_attack_multiplier() * _ability_skill_damage_multiplier() * float(runtime["attack_multiplier"]) * float(runtime["max_hits"])))
    if enemy_active:
        _apply_enemy_damage(damage)
    for index in range(funnel_entities.size() - 1, -1, -1):
        var funnel: Dictionary = funnel_entities[index]
        if Vector2(funnel["position"]).distance_to(player.position) <= float(runtime["radius"]):
            _apply_funnel_damage(int(funnel["serial"]), damage)

func _apply_player_skill_condition(slot_index: int, condition: Dictionary) -> void:
    var kind := str(condition.get("kind", ""))
    if kind == "flying":
        party_conditions["flying"] = {"remaining_frames": int(condition["duration_frames"])}
        player.disable_gravity = true
    elif kind == "attack_up":
        party_conditions["attack_up"] = {"remaining_frames": int(condition["duration_frames"]), "amount": float(condition["amount"])}
    elif kind == "poison" and enemy_active:
        enemy_conditions["poison"] = {"remaining_frames": int(condition["duration_frames"]), "strength_raw": float(condition["strength_raw"]), "tick_frames": int(condition["tick_frames"]), "frames_until_tick": int(condition["tick_frames"]), "source_atk": int(skill_slots[slot_index]["atk"])}

func _party_attack_multiplier() -> float:
    if not party_conditions.has("attack_up"):
        return 1.0
    return 1.0 + float(party_conditions["attack_up"].get("amount", 0.0))

func _build_skill_slots() -> void:
    skill_slots.clear()
    var members_value: Variant = party_snapshot.get("members", [])
    var members: Array = members_value if members_value is Array and not members_value.is_empty() else []
    if members.is_empty():
        for character_id in quest["battle_source_defaults"]["default_party"]:
            var definition: Dictionary = quest["characters"][str(character_id)]
            var defaults: Dictionary = quest["battle_source_defaults"].get("default_ability_levels", {}).get(str(character_id), {})
            var active_abilities: Array[Dictionary] = []
            for ability in definition.get("abilities", []):
                if int(defaults.get(str(ability.get("ability_id", "")), 0)) > 0:
                    active_abilities.append(ability.duplicate(true))
            members.append({"main_character_id": str(character_id), "name": definition["name"], "atk": definition["atk"], "skill": definition["skill"], "active_abilities": active_abilities})
    for member in members:
        var skill: Dictionary = member.get("skill", {})
        skill_slots.append({"character_id": str(member.get("main_character_id", "")), "name": str(skill.get("name", "")), "atk": int(member.get("atk", 1)), "skill_point": 0, "max_skill_point": int(skill.get("max_skill_point", 1)), "runtime": skill.get("runtime", {}).duplicate(true), "active_abilities": member.get("active_abilities", []).duplicate(true)})

func _ability_direct_damage_multiplier() -> float:
    var bonus := 0.0
    for slot in skill_slots:
        for ability in slot.get("active_abilities", []):
            if str(ability.get("content_kind", "")) != "DirectDamage":
                continue
            var trigger := str(ability.get("trigger_kind", ""))
            if trigger == "None" or (trigger == "SkillMax" and int(slot["skill_point"]) >= int(slot["max_skill_point"])):
                bonus += float(ability.get("power1", 0.0))
        for ability in slot.get("active_abilities", []):
            var kind := str(ability.get("content_kind", ""))
            if kind == "ParalysisDirectDamageSlayer" and enemy_conditions.has("paralysis"):
                bonus += float(ability.get("power1", 0.0))
            elif kind in ["ParalysisSlayer", "FrozenAttackSlayer"]:
                var condition_name := "paralysis" if kind == "ParalysisSlayer" else "frozen"
                if enemy_conditions.has(condition_name):
                    bonus += float(ability.get("power1", 0.0))
            elif kind == "AdditionalDirectAtttackExtend" and str(ability.get("trigger_kind", "")) == "SkillMax" and int(slot["skill_point"]) >= int(slot["max_skill_point"]):
                bonus += float(ability.get("power1", 0.0))
    return 1.0 + bonus

func _ability_skill_damage_multiplier() -> float:
    var bonus := 0.0
    for slot in skill_slots:
        for ability in slot.get("active_abilities", []):
            var kind := str(ability.get("content_kind", ""))
            var trigger := str(ability.get("trigger_kind", ""))
            if kind == "SkillDamage" and trigger == "DamageCount" and direct_attack_count >= int(ability.get("trigger_threshold", 0.0)):
                bonus += float(ability.get("power1", 0.0))
            elif kind == "FrozenAttackSlayer" and enemy_conditions.has("frozen"):
                bonus += float(ability.get("power1", 0.0))
            elif kind == "ParalysisSlayer" and enemy_conditions.has("paralysis"):
                bonus += float(ability.get("power1", 0.0))
    return 1.0 + bonus

func _apply_skill_activation_abilities(slot_index: int) -> void:
    var slot: Dictionary = skill_slots[slot_index]
    for ability in slot.get("active_abilities", []):
        var kind := str(ability.get("content_kind", ""))
        if kind == "FixedHeal" and str(ability.get("trigger_kind", "")) in ["None", "Instant"]:
            player_hp = mini(player_max_hp, player_hp + maxi(1, floori(float(player_max_hp) * float(ability.get("power1", 0.0)))))
        elif kind == "AddFeverPoint" and str(ability.get("trigger_kind", "")) == "None":
            fever_points = mini(1000, fever_points + maxi(1, roundi(float(ability.get("power1", 0.0)) * 100.0)))

func _ability_power_flip_bonus() -> float:
    var bonus := 0.0
    for slot in skill_slots:
        for ability in slot.get("active_abilities", []):
            if str(ability.get("trigger_kind", "")) == "None" and str(ability.get("content_kind", "")) == "PowerFlipDamageUpExtend":
                bonus += float(ability.get("power1", 0.0))
    return bonus

func _record_direct_attack() -> void:
    direct_attack_count += 1
    combo_count += 1
    power_flip_level = _power_flip_level_for_combo(combo_count)
    for slot in skill_slots:
        slot["skill_point"] = mini(int(slot["max_skill_point"]), int(slot["skill_point"]) + skill_point_gain_per_direct_attack)

func _power_flip_level_for_combo(value: int) -> int:
    if value >= int(power_flip_combo_thresholds[2]): return 3
    if value >= int(power_flip_combo_thresholds[1]): return 2
    if value >= int(power_flip_combo_thresholds[0]): return 1
    return 0

func get_projectile_snapshots() -> Array[Dictionary]:
    return action_executor.get_projectile_snapshots()

func get_funnel_snapshots() -> Array[Dictionary]:
    var snapshots: Array[Dictionary] = []
    for funnel in funnel_entities:
        var snapshot: Dictionary = funnel.duplicate(true)
        snapshot.erase("body")
        snapshots.append(snapshot)
    return snapshots
func trigger_enemy_action(action_id: String) -> int:
    if status != "running" or not enemy_active:
        return 0
    return _invoke_enemy_action(action_id)

func build_result(result_id: String) -> Dictionary:
    if status != "cleared" or result_id.is_empty() or run_id.is_empty():
        return {}
    return {
        "result_id": result_id,
        "run_id": run_id,
        "quest_id": str(quest["id"]),
        "rewards": quest["rewards"].duplicate(true),
    }

func _enter_zone(zone_index: int) -> void:
    _deactivate_enemy()
    var zones: Array = quest["zones"]
    if zone_index >= zones.size():
        _clear("all_zones_cleared")
        return
    current_zone_index = zone_index
    objective_progress = 0
    frames_until_spawn = 0
    var zone: Dictionary = zones[zone_index]
    var objective: Dictionary = zone["objective"]
    objective_kind = str(objective["kind"])
    if objective_kind == "zako_kill":
        objective_target = int(objective["count"])
        var emitters: Array = zone["zako_emitters"]
        if objective_target <= 0 or emitters.is_empty():
            _fail("invalid_zako_zone")
            return
        var emitter: Dictionary = emitters[0]
        current_enemy_id = str(emitter["enemy_id"])
        current_enemy_kind = "zako"
        spawn_interval_frames = int(emitter["interval_frames"])
        _spawn_zone_enemy()
        return
    if objective_kind == "boss_clear":
        var bosses: Array = zone["bosses"]
        if bosses.is_empty():
            _fail("invalid_boss_zone")
            return
        var boss: Dictionary = bosses[0]
        objective_target = 1
        current_enemy_id = str(boss["enemy_id"])
        current_enemy_kind = str(boss["kind"])
        spawn_interval_frames = 0
        _spawn_zone_enemy()
        return
    _fail("unsupported_objective")

func _spawn_zone_enemy() -> void:
    if status != "running":
        return
    var enemy_definition := _find_enemy_definition(current_enemy_id, current_enemy_kind)
    if enemy_definition.is_empty():
        _fail("missing_enemy_definition")
        return
    var fallback_enemy: Dictionary = quest["enemy"]
    var fallback_position: Array = fallback_enemy["position"]
    enemy.position = Vector2(float(fallback_position[0]), float(fallback_position[1]))
    enemy.radius = float(fallback_enemy["radius"])
    world.add_body(enemy)
    current_enemy_definition = enemy_definition.duplicate(true)
    enemy_conditions.clear()
    enemy_hp = int(enemy_definition["max_hp"])
    _prepare_enemy_action_schedule(enemy_definition)
    enemy_spawn_serial += 1
    enemy_active = true
    frames_until_spawn = 0

func _find_enemy_definition(master_id: String, kind: String) -> Dictionary:
    var enemies: Dictionary = quest["enemies"]
    for enemy_variant in enemies.values():
        var enemy_definition: Dictionary = enemy_variant
        if str(enemy_definition["master_id"]) == master_id and str(enemy_definition["kind"]) == kind:
            return enemy_definition
    return {}

func _prepare_enemy_action_schedule(enemy_definition: Dictionary) -> void:
    enemy_action_sequence = []
    enemy_action_index = 0
    enemy_action_frames_until_fire = 0
    enemy_state_machine = {}
    enemy_state_id = ""
    enemy_state_frames_remaining = 0
    var state_machine_value: Variant = enemy_definition.get("action_state_machine", {})
    if state_machine_value is Dictionary and not state_machine_value.is_empty():
        enemy_state_machine = state_machine_value.duplicate(true)
        _enter_enemy_state(str(enemy_state_machine.get("initial_state_id", "")))
        return
    var schedule_value: Variant = enemy_definition.get("action_schedule", {})
    if not schedule_value is Dictionary:
        return
    var schedule: Dictionary = schedule_value
    var sequence_value: Variant = schedule.get("sequence", [])
    if not sequence_value is Array:
        return
    enemy_action_sequence = sequence_value.duplicate()
    enemy_action_frames_until_fire = maxi(1, int(schedule.get("initial_delay_frames", 1)))

func _step_enemy_actions() -> void:
    if not enemy_state_machine.is_empty():
        _step_enemy_state_machine()
        return
    if enemy_action_sequence.is_empty():
        return
    enemy_action_frames_until_fire -= 1
    if enemy_action_frames_until_fire > 0:
        return
    var action_id := str(enemy_action_sequence[enemy_action_index % enemy_action_sequence.size()])
    _invoke_enemy_action(action_id)
    enemy_action_index += 1
    var schedule: Dictionary = current_enemy_definition.get("action_schedule", {})
    enemy_action_frames_until_fire = maxi(1, int(schedule.get("interval_frames", 1)))

func _step_enemy_state_machine() -> void:
    if enemy_state_id.is_empty():
        return
    if enemy_move_total_frames > 0:
        enemy_move_elapsed_frames = mini(enemy_move_total_frames, enemy_move_elapsed_frames + 1)
        enemy.position = enemy_move_start.lerp(enemy_move_target, float(enemy_move_elapsed_frames) / float(enemy_move_total_frames))
    enemy_state_frames_remaining -= 1
    if enemy_state_frames_remaining > 0:
        return
    var states: Dictionary = enemy_state_machine["states"]
    var state: Dictionary = states[enemy_state_id]
    _enter_enemy_state(str(state["next_state"]))

func _enter_enemy_state(state_id: String) -> void:
    var states_value: Variant = enemy_state_machine.get("states", {})
    if not states_value is Dictionary or not states_value.has(state_id):
        _fail("missing_enemy_state")
        return
    var states: Dictionary = states_value
    var state: Dictionary = states[state_id]
    enemy_state_id = state_id
    var termination: Dictionary = state["termination"]
    enemy_move_total_frames = 0
    enemy_move_elapsed_frames = 0
    if str(termination["kind"]) == "move":
        enemy_state_frames_remaining = maxi(1, int(termination["fallback_frames"]))
        var target_name := str(termination.get("target", ""))
        var markers: Dictionary = quest["terrain_runtime"]["markers"]
        if not markers.has(target_name):
            _fail("missing_terrain_marker")
            return
        var target_value: Array = markers[target_name]
        enemy_move_start = enemy.position
        enemy_move_target = Vector2(float(target_value[0]), float(target_value[1]))
        enemy_move_total_frames = enemy_state_frames_remaining
    else:
        enemy_state_frames_remaining = maxi(1, int(termination["value"]))
    if state.has("action_id"):
        _invoke_enemy_action(str(state["action_id"]))

func _invoke_enemy_action(action_id: String) -> int:
    var action := _find_action_definition(action_id)
    if action.is_empty():
        return 0
    last_enemy_action_id = action_id
    var corrections: Dictionary = quest["battle"]["atk_corrections"]
    var correction_name := "boss" if current_enemy_kind != "zako" else "zako"
    var created: int = action_executor.start_action(
        action,
        enemy.position,
        player.position,
        int(current_enemy_definition.get("atk", 1)),
        float(corrections.get(correction_name, 1.0))
    )
    var spawn_events: Array = action_executor.consume_spawn_events()
    for spawn_event_variant in spawn_events:
        var spawn_event: Dictionary = spawn_event_variant
        _spawn_funnel_entity(spawn_event)
    funnel_spawn_count += spawn_events.size()
    return created

func _spawn_funnel_entity(spawn_event: Dictionary) -> void:
    var funnel_definition := _find_enemy_definition(str(spawn_event.get("enemy_id", "")), "funnel")
    if funnel_definition.is_empty():
        return
    var schedule: Dictionary = funnel_definition.get("action_schedule", {})
    var funnel_body: SimBody = SimBodyScript.new()
    funnel_body.tag = "funnel:%d" % next_funnel_serial
    funnel_body.dynamic = false
    funnel_body.radius = 18.0
    funnel_body.restitution = 0.9
    funnel_body.position = enemy.position
    world.add_body(funnel_body)
    funnel_entities.append({
        "serial": next_funnel_serial,
        "enemy_id": str(spawn_event.get("enemy_id", "")),
        "level": int(spawn_event.get("level", funnel_definition.get("level", 1))),
        "atk": int(funnel_definition.get("atk", 1)),
        "hp": int(funnel_definition.get("max_hp", 1)),
        "max_hp": int(funnel_definition.get("max_hp", 1)),
        "body": funnel_body,
        "radius": 18.0,
        "orbit_angle": float(next_funnel_serial - 1) * TAU / 3.0,
        "orbit_radius": 96.0,
        "position": enemy.position,
        "frames_until_action": maxi(1, int(schedule.get("initial_delay_frames", 120))),
        "action_interval_frames": maxi(1, int(schedule.get("interval_frames", 180))),
        "action_id": str(funnel_definition["action_assets"][0]),
    })
    next_funnel_serial += 1

func _step_funnel_entities() -> void:
    for funnel in funnel_entities:
        funnel["orbit_angle"] = float(funnel["orbit_angle"]) + 0.02
        funnel["position"] = enemy.position + Vector2.RIGHT.rotated(float(funnel["orbit_angle"])) * float(funnel["orbit_radius"])
        var funnel_body: SimBody = funnel["body"]
        funnel_body.position = Vector2(funnel["position"])
        funnel["frames_until_action"] = int(funnel["frames_until_action"]) - 1
        if int(funnel["frames_until_action"]) > 0:
            continue
        last_funnel_action_id = str(funnel["action_id"])
        var action := _find_action_definition(last_funnel_action_id)
        if not action.is_empty():
            var corrections: Dictionary = quest["battle"]["atk_corrections"]
            action_executor.start_action(
                action,
                Vector2(funnel["position"]),
                player.position,
                int(funnel["atk"]),
                float(corrections.get("funnel", 1.0))
            )
        funnel["frames_until_action"] = int(funnel["action_interval_frames"])

func _apply_funnel_damage(serial: int, damage: int) -> void:
    if status != "running" or damage <= 0:
        return
    for index in range(funnel_entities.size()):
        var funnel: Dictionary = funnel_entities[index]
        if int(funnel["serial"]) != serial:
            continue
        funnel["hp"] = maxi(0, int(funnel["hp"]) - damage)
        if int(funnel["hp"]) == 0:
            world.remove_body(funnel["body"])
            funnel_entities.remove_at(index)
        return

func _find_action_definition(action_id: String) -> Dictionary:
    for action_variant in quest["action_assets"]:
        var action: Dictionary = action_variant
        if str(action.get("id", "")) == action_id:
            return action
    return {}

func _default_party_hp() -> int:
    var defaults: Dictionary = quest.get("battle_source_defaults", {})
    var characters: Dictionary = quest.get("characters", {})
    var total := 0
    for character_id_variant in defaults.get("default_party", []):
        var character: Dictionary = characters.get(str(character_id_variant), {})
        total += int(character.get("hp", 0))
    return total

func _apply_enemy_damage(damage: int) -> void:
    if status != "running" or not enemy_active:
        return
    enemy_hp = maxi(0, enemy_hp - damage)
    if enemy_hp > 0:
        return
    _complete_active_enemy()

func _complete_active_enemy() -> void:
    _deactivate_enemy()
    objective_progress += 1
    if objective_progress >= objective_target:
        if objective_kind == "boss_clear":
            _clear("boss_defeated")
        else:
            _enter_zone(current_zone_index + 1)
        return
    frames_until_spawn = spawn_interval_frames

func _deactivate_enemy() -> void:
    enemy_active = false
    world.remove_body(enemy)
    action_executor.clear()
    enemy_conditions.clear()
    for funnel in funnel_entities:
        world.remove_body(funnel["body"])
    funnel_entities.clear()
    enemy_action_sequence = []
    enemy_action_frames_until_fire = 0
    enemy_state_machine = {}
    enemy_state_id = ""
    enemy_state_frames_remaining = 0
    current_enemy_definition = {}
    enemy.radius = 0.0
    enemy_hp = 0

func _clear(reason: String) -> void:
    _deactivate_enemy()
    status = "cleared"
    status_reason = reason

func _fail(reason: String) -> void:
    _deactivate_enemy()
    frames_until_spawn = 0
    status = "failed"
    status_reason = reason
