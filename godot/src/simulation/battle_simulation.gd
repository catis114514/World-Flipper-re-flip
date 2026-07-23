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
var enemy_instances: Array[Dictionary] = []
var emitter_states: Array[Dictionary] = []
var next_enemy_serial := 1
var primary_enemy_serial := 0
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
var pending_enemy_action_events: Array[Dictionary] = []
var party_conditions: Dictionary = {}
var enemy_conditions: Dictionary = {}
var direct_attack_count := 0
var fever_points := 0
var fever_active := false
var fever_remaining_frames := 0
var flippers_pressed := false
var outhole_y := 1210.0
var outhole_relaunch_count := 0
var player_damage_cooldown_frames := 0
var movement_skill_fraction := 0.0

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
    outhole_y = float(arena.get("floor_y", arena_size.y - 100.0)) + 30.0
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
    enemy.tag = "enemy:0"
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
    flippers_pressed = is_pressed
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
    player_damage_cooldown_frames = maxi(0, player_damage_cooldown_frames - 1)
    _step_emitters()
    _step_fever()
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

    var player_position_before_step := player.position
    world.step(1.0)
    _record_movement_skill_points(player_position_before_step.distance_to(player.position))
    _resolve_outhole_relaunch()
    if not enemy_instances.is_empty():
        for contact in world.contacts:
            var first: SimBody = contact[0]
            var second: SimBody = contact[1]
            var other: SimBody = second if first.tag == "player" else first if second.tag == "player" else null
            if other == null:
                continue
            var target_conditions := _conditions_for_body(other)
            var impact_damage := maxi(1, roundi(float(contact[2]) * float(party_attack) * _party_attack_multiplier() * _ability_direct_damage_multiplier(target_conditions) / float(direct_attack_reference_atk)))
            if armed_power_flip_level > 0:
                var power_flip_multipliers := [1.0, 1.5, 2.0, 3.0]
                impact_damage = maxi(1, roundi(float(impact_damage) * (float(power_flip_multipliers[armed_power_flip_level]) + _ability_power_flip_bonus())))
                armed_power_flip_level = 0
            if other.tag.begins_with("enemy:"):
                _apply_enemy_damage_to_serial(int(other.tag.trim_prefix("enemy:")), impact_damage)
                _record_direct_attack()
                break
            if other.tag.begins_with("funnel:"):
                _apply_funnel_damage(int(other.tag.trim_prefix("funnel:")), impact_damage)
                _record_direct_attack()
                break
    if status != "running":
        return
    if not enemy_instances.is_empty() and enemy_actions_enabled:
        _step_enemy_actions()
        _step_funnel_entities()
        _step_pending_enemy_action_events()
    var projectile_damage: int = action_executor.step(player.position, player.radius, player_max_hp)
    if projectile_damage > 0 and player_damage_cooldown_frames == 0:
        player_hp = maxi(0, player_hp - projectile_damage)
        player_damage_cooldown_frames = 40
        if player_hp == 0:
            _fail("party_defeated")

func _resolve_outhole_relaunch() -> void:
    if player.position.y < outhole_y or not flippers_pressed: return
    outhole_relaunch_count += 1
    player.position = Vector2(world.bounds.position.x + world.bounds.size.x * 0.5, outhole_y - 100.0)
    var horizontal := -4.0 if outhole_relaunch_count % 2 == 0 else 4.0
    player.velocity = Vector2(horizontal, -70.0)

func _scale_enemy_damage(raw_damage: int) -> int:
    var formula: Dictionary = current_enemy_definition.get("atk_formula", {})
    var reference_party_hp := maxi(1, int(formula.get("party_hp_level_1", player_max_hp)))
    return maxi(1, roundi(float(raw_damage) * float(player_max_hp) / float(reference_party_hp)))

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
        "active_enemy_count": enemy_instances.size(),
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
        "enemies": get_enemy_snapshots(),
        "emitters": _get_emitter_snapshots(),
        "pending_player_skill_event_count": pending_player_skill_events.size(),
        "pending_enemy_action_event_count": pending_enemy_action_events.size(),
        "direct_attack_count": direct_attack_count,
        "fever_points": fever_points,
        "fever_active": fever_active,
        "fever_remaining_frames": fever_remaining_frames,
        "outhole_relaunch_count": outhole_relaunch_count,
        "player_damage_cooldown_frames": player_damage_cooldown_frames,
    }

func get_enemy_snapshots() -> Array[Dictionary]:
    var snapshots: Array[Dictionary] = []
    for actor in enemy_instances:
        var body: SimBody = actor["body"]
        snapshots.append({
            "serial": int(actor["serial"]),
            "enemy_id": str(actor["enemy_id"]),
            "enemy_kind": str(actor["kind"]),
            "hp": int(actor["hp"]),
            "max_hp": int(actor["max_hp"]),
            "radius": body.radius,
            "position": [body.position.x, body.position.y],
            "state_id": str(actor.get("state_id", "")),
            "state_frames_remaining": int(actor.get("state_frames_remaining", 0)),
            "conditions": actor["conditions"].duplicate(true),
            "emitter_index": int(actor.get("emitter_index", -1)),
        })
    return snapshots

func _get_emitter_snapshots() -> Array[Dictionary]:
    var snapshots: Array[Dictionary] = []
    for emitter in emitter_states:
        var snapshot: Dictionary = emitter.duplicate(true)
        snapshots.append(snapshot)
    return snapshots

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
    var target_serials := _active_enemy_serials()
    var target_funnel_serials := _active_funnel_serials()
    pending_player_skill_events.append({"kind": "damage", "frames_remaining": int(runtime.get("delay_frames", 0)), "slot": slot_index, "target_serials": target_serials.duplicate(), "target_funnel_serials": target_funnel_serials.duplicate()})
    for condition in runtime.get("conditions", []):
        pending_player_skill_events.append({"kind": "condition", "frames_remaining": int(condition.get("delay_frames", 0)), "slot": slot_index, "target_serials": target_serials.duplicate(), "condition": condition.duplicate(true)})
    _flush_ready_player_skill_events()
    return true

func _step_player_skill_runtime() -> void:
    for key in party_conditions.keys():
        var condition: Dictionary = party_conditions[key]
        condition["remaining_frames"] = int(condition["remaining_frames"]) - 1
        if int(condition["remaining_frames"]) <= 0:
            party_conditions.erase(key)
    player.disable_gravity = party_conditions.has("flying")
    for serial in _active_enemy_serials():
        var actor := _find_enemy_instance(int(serial))
        if actor.is_empty():
            continue
        var conditions: Dictionary = actor["conditions"]
        if not conditions.has("poison"):
            continue
        var poison: Dictionary = conditions["poison"]
        poison["remaining_frames"] = int(poison["remaining_frames"]) - 1
        poison["frames_until_tick"] = int(poison["frames_until_tick"]) - 1
        if int(poison["frames_until_tick"]) <= 0:
            var poison_damage := maxi(1, floori(float(poison["source_atk"]) * float(poison["strength_raw"]) / 1000.0))
            _apply_enemy_damage_to_serial(int(serial), poison_damage)
            poison["frames_until_tick"] = int(poison["tick_frames"])
        if int(poison["remaining_frames"]) <= 0:
            conditions.erase("poison")
    if status != "running":
        pending_player_skill_events.clear()
        return
    for event in pending_player_skill_events:
        event["frames_remaining"] = int(event["frames_remaining"]) - 1
    _flush_ready_player_skill_events()

func _flush_ready_player_skill_events() -> void:
    for index in range(pending_player_skill_events.size() - 1, -1, -1):
        var event: Dictionary = pending_player_skill_events[index]
        if int(event["frames_remaining"]) > 0:
            continue
        var slot_index := int(event["slot"])
        pending_player_skill_events.remove_at(index)
        if slot_index >= 0 and slot_index < skill_slots.size():
            if str(event["kind"]) == "damage":
                _execute_player_skill_damage(slot_index, event.get("target_serials", []), event.get("target_funnel_serials", []))
            elif str(event["kind"]) == "condition":
                _apply_player_skill_condition(slot_index, event["condition"], event.get("target_serials", []))
        if status != "running":
            pending_player_skill_events.clear()
            return

func _execute_player_skill_damage(slot_index: int, target_serials: Array, target_funnel_serials: Array) -> void:
    var slot: Dictionary = skill_slots[slot_index]
    var runtime: Dictionary = slot["runtime"]
    var funnel_damage := maxi(1, floori(float(slot["atk"]) * _party_attack_multiplier() * _ability_skill_damage_multiplier() * float(runtime["attack_multiplier"]) * float(runtime["max_hits"])))
    for serial_variant in target_serials:
        var actor := _find_enemy_instance(int(serial_variant))
        if actor.is_empty():
            continue
        var damage := maxi(1, floori(float(slot["atk"]) * _party_attack_multiplier() * _ability_skill_damage_multiplier(actor["conditions"]) * float(runtime["attack_multiplier"]) * float(runtime["max_hits"])))
        _apply_enemy_damage_to_serial(int(serial_variant), damage)
    for index in range(funnel_entities.size() - 1, -1, -1):
        var funnel: Dictionary = funnel_entities[index]
        if target_funnel_serials.has(int(funnel["serial"])) and Vector2(funnel["position"]).distance_to(player.position) <= float(runtime["radius"]):
            _apply_funnel_damage(int(funnel["serial"]), funnel_damage)

func _apply_player_skill_condition(slot_index: int, condition: Dictionary, target_serials: Array) -> void:
    var kind := str(condition.get("kind", ""))
    if kind == "flying":
        party_conditions["flying"] = {"remaining_frames": int(condition["duration_frames"])}
        player.disable_gravity = true
    elif kind == "attack_up":
        party_conditions["attack_up"] = {"remaining_frames": int(condition["duration_frames"]), "amount": float(condition["amount"])}
    elif kind == "poison":
        for serial_variant in target_serials:
            var actor := _find_enemy_instance(int(serial_variant))
            if actor.is_empty():
                continue
            var conditions: Dictionary = actor["conditions"]
            conditions["poison"] = {"remaining_frames": int(condition["duration_frames"]), "strength_raw": float(condition["strength_raw"]), "tick_frames": int(condition["tick_frames"]), "frames_until_tick": int(condition["tick_frames"]), "source_atk": int(skill_slots[slot_index]["atk"])}
        _sync_primary_enemy_view()

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

func _ability_direct_damage_multiplier(target_conditions: Variant = null) -> float:
    var conditions: Dictionary = enemy_conditions if target_conditions == null else target_conditions
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
            if kind == "ParalysisDirectDamageSlayer" and conditions.has("paralysis"):
                bonus += float(ability.get("power1", 0.0))
            elif kind in ["ParalysisSlayer", "FrozenAttackSlayer"]:
                var condition_name := "paralysis" if kind == "ParalysisSlayer" else "frozen"
                if conditions.has(condition_name):
                    bonus += float(ability.get("power1", 0.0))
            elif kind == "AdditionalDirectAtttackExtend" and str(ability.get("trigger_kind", "")) == "SkillMax" and int(slot["skill_point"]) >= int(slot["max_skill_point"]):
                bonus += float(ability.get("power1", 0.0))
    return 1.0 + bonus

func _ability_skill_damage_multiplier(target_conditions: Variant = null) -> float:
    var conditions: Dictionary = enemy_conditions if target_conditions == null else target_conditions
    var bonus := 0.0
    for slot in skill_slots:
        for ability in slot.get("active_abilities", []):
            var kind := str(ability.get("content_kind", ""))
            var trigger := str(ability.get("trigger_kind", ""))
            if kind == "SkillDamage" and trigger == "DamageCount" and direct_attack_count >= int(ability.get("trigger_threshold", 0.0)):
                bonus += float(ability.get("power1", 0.0))
            elif kind == "FrozenAttackSlayer" and conditions.has("frozen"):
                bonus += float(ability.get("power1", 0.0))
            elif kind == "ParalysisSlayer" and conditions.has("paralysis"):
                bonus += float(ability.get("power1", 0.0))
    return 1.0 + bonus

func _apply_skill_activation_abilities(slot_index: int) -> void:
    var slot: Dictionary = skill_slots[slot_index]
    for ability in slot.get("active_abilities", []):
        var kind := str(ability.get("content_kind", ""))
        if kind == "FixedHeal" and str(ability.get("trigger_kind", "")) in ["None", "Instant"]:
            player_hp = mini(player_max_hp, player_hp + maxi(1, floori(float(player_max_hp) * float(ability.get("power1", 0.0)))))
        elif kind == "AddFeverPoint" and str(ability.get("trigger_kind", "")) == "None":
            _add_fever_points(maxi(1, roundi(float(ability.get("power1", 0.0)) * 100.0)))

func _add_fever_points(amount: int) -> void:
    if amount <= 0 or fever_active: return
    fever_points = mini(1000, fever_points + amount)
    if fever_points >= 1000:
        fever_active = true
        fever_remaining_frames = 900

func _step_fever() -> void:
    if not fever_active: return
    fever_remaining_frames = maxi(0, fever_remaining_frames - 1)
    if fever_remaining_frames == 0:
        fever_active = false
        fever_points = 0

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

func _record_movement_skill_points(distance: float) -> void:
    if distance <= 0.0: return
    movement_skill_fraction += distance * 0.05
    var gained := floori(movement_skill_fraction)
    if gained <= 0: return
    movement_skill_fraction -= float(gained)
    for slot in skill_slots:
        slot["skill_point"] = mini(int(slot["max_skill_point"]), int(slot["skill_point"]) + gained)

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
    var actor := _primary_enemy_instance()
    if actor.is_empty():
        return 0
    return _invoke_enemy_action(actor, action_id)

func build_result(result_id: String) -> Dictionary:
    if status != "cleared" or result_id.is_empty() or run_id.is_empty():
        return {}
    var result_rewards: Dictionary = quest["rewards"].duplicate(true)
    result_rewards["exp_pool"] = int(quest.get("pool_exp", 0))
    result_rewards["_character_exp"] = int(quest.get("character_exp", 0))
    return {
        "result_id": result_id,
        "run_id": run_id,
        "quest_id": str(quest["id"]),
        "rewards": result_rewards,
    }

func _enter_zone(zone_index: int) -> void:
    _deactivate_all_enemies()
    emitter_states.clear()
    var zones: Array = quest["zones"]
    if zone_index >= zones.size():
        _clear("all_zones_cleared")
        return
    current_zone_index = zone_index
    objective_progress = 0
    frames_until_spawn = 0
    spawn_interval_frames = 0
    var zone: Dictionary = zones[zone_index]
    var objective: Dictionary = zone["objective"]
    objective_kind = str(objective["kind"])
    if objective_kind == "zako_kill":
        objective_target = int(objective["count"])
        var emitters: Array = zone["zako_emitters"]
        if objective_target <= 0 or emitters.is_empty():
            _fail("invalid_zako_zone")
            return
        for emitter_index in range(emitters.size()):
            var emitter: Dictionary = emitters[emitter_index]
            emitter_states.append({
                "index": emitter_index,
                "enemy_id": str(emitter["enemy_id"]),
                "interval_frames": maxi(0, int(emitter.get("interval_frames", 0))),
                "frames_until_spawn": 0,
                "active_serial": 0,
                "spawn_count": 0,
            })
        spawn_interval_frames = int(emitter_states[0]["interval_frames"])
        for emitter_index in range(emitter_states.size()):
            if objective_progress + enemy_instances.size() >= objective_target:
                break
            _spawn_emitter_enemy(emitter_index)
        _sync_primary_enemy_view()
        return
    if objective_kind == "boss_clear":
        var bosses: Array = zone["bosses"]
        if bosses.is_empty():
            _fail("invalid_boss_zone")
            return
        objective_target = bosses.size()
        for boss_index in range(bosses.size()):
            var boss: Dictionary = bosses[boss_index]
            _spawn_zone_enemy(
                str(boss["enemy_id"]),
                str(boss["kind"]),
                -1,
                boss_index,
                bosses.size()
            )
        _sync_primary_enemy_view()
        return
    _fail("unsupported_objective")

func _step_emitters() -> void:
    if objective_kind != "zako_kill":
        return
    for emitter_index in range(emitter_states.size()):
        var emitter: Dictionary = emitter_states[emitter_index]
        if int(emitter["active_serial"]) != 0:
            continue
        if objective_progress + enemy_instances.size() >= objective_target:
            continue
        if int(emitter["frames_until_spawn"]) > 0:
            emitter["frames_until_spawn"] = int(emitter["frames_until_spawn"]) - 1
        if int(emitter["frames_until_spawn"]) == 0:
            _spawn_emitter_enemy(emitter_index)
    frames_until_spawn = _minimum_emitter_cooldown()

func _spawn_emitter_enemy(emitter_index: int) -> void:
    if emitter_index < 0 or emitter_index >= emitter_states.size():
        return
    var emitter: Dictionary = emitter_states[emitter_index]
    if int(emitter["active_serial"]) != 0:
        return
    var serial := _spawn_zone_enemy(
        str(emitter["enemy_id"]),
        "zako",
        emitter_index,
        emitter_index,
        emitter_states.size()
    )
    if serial <= 0:
        return
    emitter["active_serial"] = serial
    emitter["frames_until_spawn"] = 0
    emitter["spawn_count"] = int(emitter["spawn_count"]) + 1

func _spawn_zone_enemy(
    enemy_id: String,
    enemy_kind: String,
    emitter_index: int = -1,
    spawn_ordinal: int = 0,
    spawn_count: int = 1
) -> int:
    if status != "running":
        return 0
    var enemy_definition := _find_enemy_definition(enemy_id, enemy_kind)
    if enemy_definition.is_empty():
        _fail("missing_enemy_definition")
        return 0
    var fallback_enemy: Dictionary = quest["enemy"]
    var fallback_position: Array = fallback_enemy["position"]
    var enemy_body: SimBody = SimBodyScript.new()
    var serial := next_enemy_serial
    next_enemy_serial += 1
    enemy_body.tag = "enemy:%d" % serial
    enemy_body.dynamic = false
    enemy_body.radius = float(fallback_enemy["radius"])
    enemy_body.restitution = 0.9
    var base_position := Vector2(float(fallback_position[0]), float(fallback_position[1]))
    var centered_index := float(spawn_ordinal) - float(maxi(1, spawn_count) - 1) * 0.5
    enemy_body.position = base_position + Vector2(centered_index * 96.0, 0.0)
    var actor: Dictionary = {
        "serial": serial,
        "emitter_index": emitter_index,
        "enemy_id": enemy_id,
        "kind": enemy_kind,
        "definition": enemy_definition.duplicate(true),
        "body": enemy_body,
        "hp": int(enemy_definition["max_hp"]),
        "max_hp": int(enemy_definition["max_hp"]),
        "conditions": {},
        "action_sequence": [],
        "action_index": 0,
        "action_frames_until_fire": 0,
        "state_machine": {},
        "state_id": "",
        "state_frames_remaining": 0,
        "move_start": Vector2.ZERO,
        "move_target": Vector2.ZERO,
        "move_total_frames": 0,
        "move_elapsed_frames": 0,
    }
    enemy_instances.append(actor)
    world.add_body(enemy_body)
    _prepare_enemy_action_schedule(actor)
    enemy_spawn_serial += 1
    if primary_enemy_serial == 0:
        primary_enemy_serial = serial
    _sync_primary_enemy_view()
    return serial

func _find_enemy_definition(master_id: String, kind: String) -> Dictionary:
    var enemies: Dictionary = quest["enemies"]
    for enemy_variant in enemies.values():
        var enemy_definition: Dictionary = enemy_variant
        if str(enemy_definition["master_id"]) == master_id and str(enemy_definition["kind"]) == kind:
            return enemy_definition
    return {}

func _prepare_enemy_action_schedule(actor: Dictionary) -> void:
    actor["action_sequence"] = []
    actor["action_index"] = 0
    actor["action_frames_until_fire"] = 0
    actor["state_machine"] = {}
    actor["state_id"] = ""
    actor["state_frames_remaining"] = 0
    var enemy_definition: Dictionary = actor["definition"]
    var state_machine_value: Variant = enemy_definition.get("action_state_machine", {})
    if state_machine_value is Dictionary and not state_machine_value.is_empty():
        actor["state_machine"] = state_machine_value.duplicate(true)
        var state_machine: Dictionary = actor["state_machine"]
        _enter_enemy_state(actor, str(state_machine.get("initial_state_id", "")))
        return
    var schedule_value: Variant = enemy_definition.get("action_schedule", {})
    if not schedule_value is Dictionary:
        return
    var schedule: Dictionary = schedule_value
    var sequence_value: Variant = schedule.get("sequence", [])
    if not sequence_value is Array:
        return
    actor["action_sequence"] = sequence_value.duplicate()
    actor["action_frames_until_fire"] = maxi(1, int(schedule.get("initial_delay_frames", 1)))

func _step_enemy_actions() -> void:
    var primary := _primary_enemy_instance()
    if not primary.is_empty():
        primary["action_frames_until_fire"] = enemy_action_frames_until_fire
    for serial_variant in _active_enemy_serials():
        var actor := _find_enemy_instance(int(serial_variant))
        if actor.is_empty():
            continue
        _step_enemy_actor_actions(actor)
    _sync_primary_enemy_view()

func _step_enemy_actor_actions(actor: Dictionary) -> void:
    var state_machine: Dictionary = actor["state_machine"]
    if not state_machine.is_empty():
        _step_enemy_state_machine(actor)
        return
    var action_sequence: Array = actor["action_sequence"]
    if action_sequence.is_empty():
        return
    actor["action_frames_until_fire"] = int(actor["action_frames_until_fire"]) - 1
    if int(actor["action_frames_until_fire"]) > 0:
        return
    var action_index := int(actor["action_index"])
    var action_id := str(action_sequence[action_index % action_sequence.size()])
    _invoke_enemy_action(actor, action_id)
    actor["action_index"] = action_index + 1
    var definition: Dictionary = actor["definition"]
    var schedule: Dictionary = definition.get("action_schedule", {})
    actor["action_frames_until_fire"] = maxi(1, int(schedule.get("interval_frames", 1)))

func _step_enemy_state_machine(actor: Dictionary = {}) -> void:
    if actor.is_empty():
        actor = _primary_enemy_instance()
    if actor.is_empty():
        return
    if str(actor["state_id"]).is_empty():
        return
    var enemy_body: SimBody = actor["body"]
    var move_total_frames := int(actor["move_total_frames"])
    if move_total_frames > 0:
        actor["move_elapsed_frames"] = mini(move_total_frames, int(actor["move_elapsed_frames"]) + 1)
        enemy_body.position = Vector2(actor["move_start"]).lerp(Vector2(actor["move_target"]), float(actor["move_elapsed_frames"]) / float(move_total_frames))
    actor["state_frames_remaining"] = int(actor["state_frames_remaining"]) - 1
    if int(actor["state_frames_remaining"]) > 0:
        return
    var state_machine: Dictionary = actor["state_machine"]
    var states: Dictionary = state_machine["states"]
    var state: Dictionary = states[str(actor["state_id"])]
    _enter_enemy_state(actor, str(state["next_state"]))

func _enter_enemy_state(actor_or_state: Variant, requested_state_id: String = "") -> void:
    var actor: Dictionary
    var state_id: String
    if actor_or_state is Dictionary:
        actor = actor_or_state
        state_id = requested_state_id
    else:
        actor = _primary_enemy_instance()
        state_id = str(actor_or_state)
    if actor.is_empty():
        return
    var state_machine: Dictionary = actor["state_machine"]
    var states_value: Variant = state_machine.get("states", {})
    if not states_value is Dictionary or not states_value.has(state_id):
        _fail("missing_enemy_state")
        return
    var states: Dictionary = states_value
    var state: Dictionary = states[state_id]
    actor["state_id"] = state_id
    var termination: Dictionary = state["termination"]
    actor["move_total_frames"] = 0
    actor["move_elapsed_frames"] = 0
    if str(termination["kind"]) == "move":
        actor["state_frames_remaining"] = maxi(1, int(termination["fallback_frames"]))
        var target_name := str(termination.get("target", ""))
        var markers: Dictionary = quest["terrain_runtime"]["markers"]
        if not markers.has(target_name):
            _fail("missing_terrain_marker")
            return
        var target_value: Array = markers[target_name]
        var enemy_body: SimBody = actor["body"]
        actor["move_start"] = enemy_body.position
        actor["move_target"] = Vector2(float(target_value[0]), float(target_value[1]))
        actor["move_total_frames"] = int(actor["state_frames_remaining"])
    else:
        actor["state_frames_remaining"] = maxi(1, int(termination["value"]))
    if state.has("action_id"):
        _invoke_enemy_action(actor, str(state["action_id"]))

func _invoke_enemy_action(actor_or_action: Variant, requested_action_id: String = "") -> int:
    var actor: Dictionary
    var action_id: String
    if actor_or_action is Dictionary:
        actor = actor_or_action
        action_id = requested_action_id
    else:
        actor = _primary_enemy_instance()
        action_id = str(actor_or_action)
    if actor.is_empty():
        return 0
    var action := _find_action_definition(action_id)
    if action.is_empty():
        return 0
    last_enemy_action_id = action_id
    var corrections: Dictionary = quest["battle"]["atk_corrections"]
    var enemy_kind := str(actor["kind"])
    var correction_name := "boss" if enemy_kind != "zako" else "zako"
    var definition: Dictionary = actor["definition"]
    var formula: Dictionary = definition.get("atk_formula", {})
    var reference_party_hp := maxi(1, int(formula.get("party_hp_level_1", player_max_hp)))
    return _schedule_enemy_action_runtime(
        action,
        int(actor["serial"]),
        int(definition.get("atk", 1)),
        float(corrections.get(correction_name, 1.0)),
        reference_party_hp
    )

func _schedule_enemy_action_runtime(
    action: Dictionary,
    source_serial: int,
    enemy_atk: int,
    quest_correction: float,
    reference_party_hp: int
) -> int:
    var created := 0
    for runtime_variant in action.get("runtime", []):
        if not runtime_variant is Dictionary:
            continue
        var runtime: Dictionary = runtime_variant
        var delay_frames := int(runtime.get("delay_frames", 0))
        if delay_frames > 0:
            pending_enemy_action_events.append({
                "due_frame": elapsed_frames + delay_frames,
                "source_serial": source_serial,
                "enemy_atk": enemy_atk,
                "quest_correction": quest_correction,
                "reference_party_hp": reference_party_hp,
                "runtime": runtime.duplicate(true),
            })
            continue
        created += _start_enemy_action_runtime(
            runtime,
            source_serial,
            enemy_atk,
            quest_correction,
            reference_party_hp
        )
    return created

func _step_pending_enemy_action_events() -> void:
    var waiting: Array[Dictionary] = []
    for event in pending_enemy_action_events:
        if elapsed_frames < int(event["due_frame"]):
            waiting.append(event)
            continue
        _start_enemy_action_runtime(
            event["runtime"],
            int(event["source_serial"]),
            int(event["enemy_atk"]),
            float(event["quest_correction"]),
            int(event["reference_party_hp"])
        )
    pending_enemy_action_events = waiting

func _start_enemy_action_runtime(
    runtime: Dictionary,
    source_serial: int,
    enemy_atk: int,
    quest_correction: float,
    reference_party_hp: int
) -> int:
    var origin := Vector2.ZERO
    var owner_actor: Dictionary = {}
    if source_serial > 0:
        owner_actor = _find_enemy_instance(source_serial)
        if owner_actor.is_empty():
            return 0
        var owner_body: SimBody = owner_actor["body"]
        origin = owner_body.position
    else:
        var funnel := _find_funnel_entity(-source_serial)
        if funnel.is_empty():
            return 0
        origin = Vector2(funnel["position"])
        owner_actor = _find_enemy_instance(int(funnel.get("owner_serial", 0)))
        if owner_actor.is_empty():
            return 0
    var created: int = action_executor.start_runtime(
        runtime,
        origin,
        player.position,
        enemy_atk,
        quest_correction,
        source_serial,
        reference_party_hp
    )
    var spawn_events: Array = action_executor.consume_spawn_events()
    for spawn_event_variant in spawn_events:
        var spawn_event: Dictionary = spawn_event_variant
        _spawn_funnel_entity(spawn_event, owner_actor)
    funnel_spawn_count += spawn_events.size()
    return created

func _spawn_funnel_entity(spawn_event: Dictionary, owner_actor: Dictionary = {}) -> void:
    if owner_actor.is_empty():
        owner_actor = _find_enemy_instance(int(spawn_event.get("source_serial", primary_enemy_serial)))
    if owner_actor.is_empty():
        return
    var funnel_definition := _find_enemy_definition(str(spawn_event.get("enemy_id", "")), "funnel")
    if funnel_definition.is_empty():
        return
    var schedule: Dictionary = funnel_definition.get("action_schedule", {})
    var funnel_body: SimBody = SimBodyScript.new()
    funnel_body.tag = "funnel:%d" % next_funnel_serial
    funnel_body.dynamic = false
    funnel_body.radius = 18.0
    funnel_body.restitution = 0.9
    var owner_body: SimBody = owner_actor["body"]
    funnel_body.position = owner_body.position
    world.add_body(funnel_body)
    funnel_entities.append({
        "serial": next_funnel_serial,
        "owner_serial": int(owner_actor["serial"]),
        "enemy_id": str(spawn_event.get("enemy_id", "")),
        "level": int(spawn_event.get("level", funnel_definition.get("level", 1))),
        "atk": int(funnel_definition.get("atk", 1)),
        "reference_party_hp": maxi(1, int(funnel_definition.get("atk_formula", {}).get("party_hp_level_1", player_max_hp))),
        "hp": int(funnel_definition.get("max_hp", 1)),
        "max_hp": int(funnel_definition.get("max_hp", 1)),
        "body": funnel_body,
        "radius": 18.0,
        "orbit_angle": float(next_funnel_serial - 1) * TAU / 3.0,
        "orbit_radius": 96.0,
        "position": owner_body.position,
        "frames_until_action": maxi(1, int(schedule.get("initial_delay_frames", 120))),
        "action_interval_frames": maxi(1, int(schedule.get("interval_frames", 180))),
        "action_id": str(funnel_definition["action_assets"][0]),
    })
    next_funnel_serial += 1

func _step_funnel_entities() -> void:
    for index in range(funnel_entities.size() - 1, -1, -1):
        var funnel: Dictionary = funnel_entities[index]
        var owner_actor := _find_enemy_instance(int(funnel.get("owner_serial", 0)))
        if owner_actor.is_empty():
            world.remove_body(funnel["body"])
            action_executor.remove_source(-int(funnel["serial"]))
            _remove_pending_enemy_action_events(-int(funnel["serial"]))
            funnel_entities.remove_at(index)
            continue
        var owner_body: SimBody = owner_actor["body"]
        funnel["orbit_angle"] = float(funnel["orbit_angle"]) + 0.02
        funnel["position"] = owner_body.position + Vector2.RIGHT.rotated(float(funnel["orbit_angle"])) * float(funnel["orbit_radius"])
        var funnel_body: SimBody = funnel["body"]
        funnel_body.position = Vector2(funnel["position"])
        funnel["frames_until_action"] = int(funnel["frames_until_action"]) - 1
        if int(funnel["frames_until_action"]) > 0:
            continue
        last_funnel_action_id = str(funnel["action_id"])
        var action := _find_action_definition(last_funnel_action_id)
        if not action.is_empty():
            var corrections: Dictionary = quest["battle"]["atk_corrections"]
            _schedule_enemy_action_runtime(
                action,
                -int(funnel["serial"]),
                int(funnel["atk"]),
                float(corrections.get("funnel", 1.0)),
                int(funnel["reference_party_hp"])
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
            action_executor.remove_source(-serial)
            _remove_pending_enemy_action_events(-serial)
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

func _active_enemy_serials() -> Array[int]:
    var serials: Array[int] = []
    for actor in enemy_instances:
        serials.append(int(actor["serial"]))
    return serials

func _active_funnel_serials() -> Array[int]:
    var serials: Array[int] = []
    for funnel in funnel_entities:
        serials.append(int(funnel["serial"]))
    return serials

func _find_enemy_instance(serial: int) -> Dictionary:
    for actor in enemy_instances:
        if int(actor["serial"]) == serial:
            return actor
    return {}

func _find_funnel_entity(serial: int) -> Dictionary:
    for funnel in funnel_entities:
        if int(funnel["serial"]) == serial:
            return funnel
    return {}

func _remove_pending_enemy_action_events(source_serial: int) -> void:
    for index in range(pending_enemy_action_events.size() - 1, -1, -1):
        if int(pending_enemy_action_events[index].get("source_serial", 0)) == source_serial:
            pending_enemy_action_events.remove_at(index)

func _primary_enemy_instance() -> Dictionary:
    if primary_enemy_serial != 0:
        var current := _find_enemy_instance(primary_enemy_serial)
        if not current.is_empty():
            return current
    if enemy_instances.is_empty():
        return {}
    var primary: Dictionary = enemy_instances[0]
    primary_enemy_serial = int(primary["serial"])
    return primary

func _conditions_for_body(body: SimBody) -> Dictionary:
    if body == null or not body.tag.begins_with("enemy:"):
        return {}
    var actor := _find_enemy_instance(int(body.tag.trim_prefix("enemy:")))
    if actor.is_empty():
        return {}
    return actor["conditions"]

func _sync_primary_enemy_view() -> void:
    var primary := _primary_enemy_instance()
    if primary.is_empty():
        primary_enemy_serial = 0
        enemy_active = false
        enemy_hp = 0
        enemy_conditions.clear()
        current_enemy_definition = {}
        enemy_action_sequence = []
        enemy_action_frames_until_fire = 0
        enemy_state_machine = {}
        enemy_state_id = ""
        enemy_state_frames_remaining = 0
        frames_until_spawn = _minimum_emitter_cooldown()
        return
    var body: SimBody = primary["body"]
    enemy = body
    enemy_active = true
    current_enemy_id = str(primary["enemy_id"])
    current_enemy_kind = str(primary["kind"])
    enemy_hp = int(primary["hp"])
    enemy_conditions = primary["conditions"]
    current_enemy_definition = primary["definition"]
    enemy_action_sequence = primary["action_sequence"]
    enemy_action_frames_until_fire = int(primary["action_frames_until_fire"])
    enemy_action_index = int(primary["action_index"])
    enemy_state_machine = primary["state_machine"]
    enemy_state_id = str(primary["state_id"])
    enemy_state_frames_remaining = int(primary["state_frames_remaining"])
    enemy_move_start = Vector2(primary["move_start"])
    enemy_move_target = Vector2(primary["move_target"])
    enemy_move_total_frames = int(primary["move_total_frames"])
    enemy_move_elapsed_frames = int(primary["move_elapsed_frames"])
    if int(primary.get("emitter_index", -1)) >= 0:
        var emitter_index := int(primary["emitter_index"])
        if emitter_index < emitter_states.size():
            frames_until_spawn = int(emitter_states[emitter_index]["frames_until_spawn"])
            spawn_interval_frames = int(emitter_states[emitter_index]["interval_frames"])
    else:
        frames_until_spawn = _minimum_emitter_cooldown()

func _minimum_emitter_cooldown() -> int:
    var minimum := 0
    for emitter in emitter_states:
        if int(emitter.get("active_serial", 0)) != 0:
            continue
        var remaining := int(emitter.get("frames_until_spawn", 0))
        if remaining <= 0:
            continue
        if minimum == 0 or remaining < minimum:
            minimum = remaining
    return minimum

func _apply_enemy_damage(damage: int) -> void:
    var primary := _primary_enemy_instance()
    if primary.is_empty():
        return
    _apply_enemy_damage_to_serial(int(primary["serial"]), damage)

func _apply_enemy_damage_to_serial(serial: int, damage: int) -> void:
    if status != "running" or damage <= 0:
        return
    var actor := _find_enemy_instance(serial)
    if actor.is_empty():
        return
    actor["hp"] = maxi(0, int(actor["hp"]) - damage)
    if int(actor["hp"]) > 0:
        _sync_primary_enemy_view()
        return
    _complete_enemy_instance(serial)

func _complete_enemy_instance(serial: int) -> void:
    var actor := _find_enemy_instance(serial)
    if actor.is_empty():
        return
    var emitter_index := int(actor.get("emitter_index", -1))
    _deactivate_enemy_instance(serial)
    objective_progress += 1
    if objective_progress >= objective_target:
        if objective_kind == "boss_clear":
            _clear("boss_defeated")
        else:
            _enter_zone(current_zone_index + 1)
        return
    if emitter_index >= 0 and emitter_index < emitter_states.size():
        var emitter: Dictionary = emitter_states[emitter_index]
        emitter["frames_until_spawn"] = int(emitter["interval_frames"])
    _sync_primary_enemy_view()

func _deactivate_enemy_instance(serial: int) -> void:
    var actor_index := -1
    for index in range(enemy_instances.size()):
        if int(enemy_instances[index]["serial"]) == serial:
            actor_index = index
            break
    if actor_index < 0:
        return
    var actor: Dictionary = enemy_instances[actor_index]
    world.remove_body(actor["body"])
    action_executor.remove_source(serial)
    _remove_pending_enemy_action_events(serial)
    for index in range(funnel_entities.size() - 1, -1, -1):
        var funnel: Dictionary = funnel_entities[index]
        if int(funnel.get("owner_serial", 0)) != serial:
            continue
        world.remove_body(funnel["body"])
        action_executor.remove_source(-int(funnel["serial"]))
        _remove_pending_enemy_action_events(-int(funnel["serial"]))
        funnel_entities.remove_at(index)
    var emitter_index := int(actor.get("emitter_index", -1))
    if emitter_index >= 0 and emitter_index < emitter_states.size():
        emitter_states[emitter_index]["active_serial"] = 0
    enemy_instances.remove_at(actor_index)
    if primary_enemy_serial == serial:
        primary_enemy_serial = 0
    _sync_primary_enemy_view()

func _deactivate_all_enemies() -> void:
    for actor in enemy_instances:
        world.remove_body(actor["body"])
        action_executor.remove_source(int(actor["serial"]))
    for funnel in funnel_entities:
        world.remove_body(funnel["body"])
        action_executor.remove_source(-int(funnel["serial"]))
    enemy_instances.clear()
    funnel_entities.clear()
    pending_enemy_action_events.clear()
    action_executor.clear()
    primary_enemy_serial = 0
    enemy_active = false
    enemy_hp = 0
    enemy_conditions.clear()
    enemy_action_sequence = []
    enemy_action_frames_until_fire = 0
    enemy_state_machine = {}
    enemy_state_id = ""
    enemy_state_frames_remaining = 0
    current_enemy_definition = {}
    if enemy != null:
        enemy.radius = 0.0
    _sync_primary_enemy_view()

func _deactivate_enemy() -> void:
    _deactivate_all_enemies()

func _reset_terminal_enemy_facade() -> void:
    current_enemy_id = ""
    current_enemy_kind = ""
    enemy_action_index = 0
    enemy_move_start = Vector2.ZERO
    enemy_move_target = Vector2.ZERO
    enemy_move_total_frames = 0
    enemy_move_elapsed_frames = 0
    frames_until_spawn = 0
    spawn_interval_frames = 0
    emitter_states.clear()
    if enemy != null:
        enemy.tag = "enemy:0"
        enemy.position = Vector2.ZERO
        enemy.radius = 0.0

func _clear(reason: String) -> void:
    _deactivate_all_enemies()
    pending_player_skill_events.clear()
    _reset_terminal_enemy_facade()
    status = "cleared"
    status_reason = reason

func _fail(reason: String) -> void:
    _deactivate_all_enemies()
    pending_player_skill_events.clear()
    _reset_terminal_enemy_facade()
    frames_until_spawn = 0
    status = "failed"
    status_reason = reason
