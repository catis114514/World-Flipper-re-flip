class_name StaticContentRepository
extends RefCounted

var _quests: Dictionary = {}

func load_fixture(path: String) -> Error:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return FileAccess.get_open_error()
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not parsed is Dictionary:
        return ERR_PARSE_ERROR
    var quest: Dictionary = parsed
    var validation_error := _validate_quest(quest)
    if validation_error != OK:
        return validation_error
    var normalized := _normalize_quest(quest)
    var quest_id: String = normalized["id"]
    if _quests.has(quest_id):
        return ERR_ALREADY_EXISTS
    _quests[quest_id] = normalized
    return OK

func get_quest(quest_id: String) -> Dictionary:
    if not _quests.has(quest_id):
        return {}
    return _quests[quest_id].duplicate(true)

func _validate_quest(quest: Dictionary) -> Error:
    var required := [
        "schema_version", "id", "category", "name", "entry_stamina",
        "character_exp", "rewards", "battle", "zones", "enemies",
        "action_assets", "characters", "equipments", "battle_source_defaults", "arena", "terrain_runtime", "enemy", "source"
    ]
    for field_name in required:
        if not quest.has(field_name):
            return ERR_INVALID_DATA
    if int(quest["schema_version"]) != 2 or str(quest["id"]).is_empty():
        return ERR_INVALID_DATA
    if not quest["rewards"] is Dictionary or not quest["battle"] is Dictionary:
        return ERR_INVALID_DATA
    if not quest["zones"] is Array or not quest["enemies"] is Dictionary:
        return ERR_INVALID_DATA
    if not quest["action_assets"] is Array or not quest["enemy"] is Dictionary:
        return ERR_INVALID_DATA
    if not quest["characters"] is Dictionary or not quest["equipments"] is Dictionary or not quest["battle_source_defaults"] is Dictionary:
        return ERR_INVALID_DATA
    if not quest["arena"] is Dictionary or not quest["terrain_runtime"] is Dictionary or not quest["source"] is Dictionary:
        return ERR_INVALID_DATA

    var equipments: Dictionary = quest["equipments"]
    if equipments.is_empty():
        return ERR_INVALID_DATA
    for equipment_id in equipments:
        var equipment_value: Variant = equipments[equipment_id]
        if not equipment_value is Dictionary:
            return ERR_INVALID_DATA
        var equipment: Dictionary = equipment_value
        if str(equipment.get("id", "")) != str(equipment_id) or str(equipment.get("kind", "")) not in ["weapon", "orb"]:
            return ERR_INVALID_DATA
        var equipment_curve_value: Variant = equipment.get("status_curve", {})
        if not equipment_curve_value is Dictionary or int(equipment.get("max_level", 0)) <= 0:
            return ERR_INVALID_DATA
        for equipment_status_value in equipment_curve_value.values():
            if not equipment_status_value is Dictionary or int(equipment_status_value.get("hp", -1)) < 0 or int(equipment_status_value.get("atk", -1)) < 0:
                return ERR_INVALID_DATA

    var characters: Dictionary = quest["characters"]
    var source_defaults: Dictionary = quest["battle_source_defaults"]
    var default_party_value: Variant = source_defaults.get("default_party", [])
    var behavior_value: Variant = source_defaults.get("battle_behavior_data", {})
    if characters.is_empty() or not default_party_value is Array or not behavior_value is Dictionary:
        return ERR_INVALID_DATA
    var default_party: Array = default_party_value
    var behavior: Dictionary = behavior_value
    if default_party.is_empty() or default_party.size() > 3:
        return ERR_INVALID_DATA
    if int(source_defaults.get("direct_attack_reference_atk", 0)) <= 0:
        return ERR_INVALID_DATA
    if int(source_defaults.get("skill_point_gain_per_direct_attack", 0)) <= 0:
        return ERR_INVALID_DATA
    var default_ability_levels_value: Variant = source_defaults.get("default_ability_levels", {})
    if not default_ability_levels_value is Dictionary:
        return ERR_INVALID_DATA
    var default_ability_levels: Dictionary = default_ability_levels_value
    for character_id_variant in default_party:
        var character_id := str(character_id_variant)
        if not default_ability_levels.get(character_id, {}) is Dictionary:
            return ERR_INVALID_DATA
    var power_flip_thresholds: Variant = source_defaults.get("power_flip_combo_thresholds", [])
    if not power_flip_thresholds is Array or power_flip_thresholds.size() != 3:
        return ERR_INVALID_DATA
    if int(power_flip_thresholds[0]) <= 0 or int(power_flip_thresholds[1]) <= int(power_flip_thresholds[0]) or int(power_flip_thresholds[2]) <= int(power_flip_thresholds[1]):
        return ERR_INVALID_DATA
    if int(behavior.get("skill_ability_behavior_mode", 0)) <= 0 or int(behavior.get("dash_behavior_mode", 0)) <= 0:
        return ERR_INVALID_DATA
    for character_id_variant in default_party:
        var character_id := str(character_id_variant)
        if character_id.is_empty() or not characters.has(character_id):
            return ERR_INVALID_DATA
    for character_key in characters:
        var character_value: Variant = characters[character_key]
        if not character_value is Dictionary:
            return ERR_INVALID_DATA
        var character: Dictionary = character_value
        if str(character.get("id", "")) != str(character_key) or str(character.get("name", "")).is_empty():
            return ERR_INVALID_DATA
        for stat_name in ["level", "rarity", "hp", "atk", "main_hp", "main_atk"]:
            if int(character.get(stat_name, 0)) <= 0:
                return ERR_INVALID_DATA
        var status_curve_value: Variant = character.get("status_curve", {})
        var exp_curve_value: Variant = character.get("exp_curve", {})
        var evolution_bonus_value: Variant = character.get("evolution_bonus", {})
        if not status_curve_value is Dictionary or not exp_curve_value is Dictionary or not evolution_bonus_value is Dictionary:
            return ERR_INVALID_DATA
        var status_curve: Dictionary = status_curve_value
        var max_level := int(character.get("max_level", 0))
        if max_level <= 0 or not status_curve.has("1") or not status_curve.has(str(max_level)):
            return ERR_INVALID_DATA
        for status_value in status_curve.values():
            if not status_value is Dictionary or int(status_value.get("hp", 0)) <= 0 or int(status_value.get("atk", 0)) <= 0:
                return ERR_INVALID_DATA
        var exp_curve: Dictionary = exp_curve_value
        if not exp_curve.has("1") or not exp_curve.has(str(max_level)) or int(exp_curve["1"]) != 0:
            return ERR_INVALID_DATA
        if int(character.get("unison_hp", -1)) < 0 or int(character.get("unison_atk", -1)) < 0:
            return ERR_INVALID_DATA
        var skill_value: Variant = character.get("skill", {})
        if not skill_value is Dictionary:
            return ERR_INVALID_DATA
        var skill: Dictionary = skill_value
        var skill_runtime_value: Variant = skill.get("runtime", {})
        if str(skill.get("name", "")).is_empty() or int(skill.get("max_skill_point", 0)) <= 0:
            return ERR_INVALID_DATA
        if str(skill.get("action_id", "")).is_empty() or str(skill.get("sha256", "")).length() != 64:
            return ERR_INVALID_DATA
        if not skill_runtime_value is Dictionary:
            return ERR_INVALID_DATA
        var skill_runtime: Dictionary = skill_runtime_value
        if str(skill_runtime.get("kind", "")) != "area_attack":
            return ERR_INVALID_DATA
        if float(skill_runtime.get("radius", 0.0)) <= 0.0 or int(skill_runtime.get("max_hits", 0)) <= 0:
            return ERR_INVALID_DATA
        if not character.get("ability_ids", []) is Array or not character.get("abilities", []) is Array:
            return ERR_INVALID_DATA
        if character["ability_ids"].is_empty() or character["abilities"].is_empty():
            return ERR_INVALID_DATA
        for ability_variant in character["abilities"]:
            if not ability_variant is Dictionary:
                return ERR_INVALID_DATA
            var ability: Dictionary = ability_variant
            if str(ability.get("ability_id", "")).is_empty() or str(ability.get("content_kind", "")).is_empty():
                return ERR_INVALID_DATA
            if int(ability.get("content_code", -1)) < 0 or float(ability.get("power1_raw", -1.0)) < 0.0:
                return ERR_INVALID_DATA
        if float(skill_runtime.get("attack_multiplier", 0.0)) <= 0.0:
            return ERR_INVALID_DATA
        if int(skill_runtime.get("delay_frames", -1)) < 0 or not skill_runtime.get("conditions", []) is Array:
            return ERR_INVALID_DATA
        for condition_variant in skill_runtime["conditions"]:
            if not condition_variant is Dictionary:
                return ERR_INVALID_DATA
            var condition: Dictionary = condition_variant
            if str(condition.get("kind", "")) not in ["flying", "attack_up", "poison"]:
                return ERR_INVALID_DATA
            if int(condition.get("delay_frames", -1)) < 0 or int(condition.get("duration_frames", 0)) <= 0:
                return ERR_INVALID_DATA
            if str(condition.get("kind", "")) == "attack_up" and float(condition.get("amount", 0.0)) <= 0.0:
                return ERR_INVALID_DATA
            if str(condition.get("kind", "")) == "poison" and (float(condition.get("strength_raw", 0.0)) <= 0.0 or int(condition.get("tick_frames", 0)) <= 0):
                return ERR_INVALID_DATA
    var rewards: Dictionary = quest["rewards"]
    for reward_value in rewards.values():
        if typeof(reward_value) not in [TYPE_INT, TYPE_FLOAT]:
            return ERR_INVALID_DATA
    var arena: Dictionary = quest["arena"]
    if float(arena.get("width", 0.0)) <= 0.0 or float(arena.get("height", 0.0)) <= 0.0:
        return ERR_INVALID_DATA
    if not arena.has("gravity_y") or not arena.has("floor_y"):
        return ERR_INVALID_DATA
    var terrain_runtime: Dictionary = quest["terrain_runtime"]
    if str(terrain_runtime.get("status", "")) not in ["fallback", "recovered"]: return ERR_INVALID_DATA
    var segments_value: Variant = terrain_runtime.get("segments", [])
    var markers_value: Variant = terrain_runtime.get("markers", {})
    if not segments_value is Array or not markers_value is Dictionary: return ERR_INVALID_DATA
    for segment_variant in segments_value:
        if not segment_variant is Dictionary: return ERR_INVALID_DATA
        var segment: Dictionary = segment_variant
        if str(segment.get("id", "")).is_empty(): return ERR_INVALID_DATA
        for point_name in ["start", "end"]:
            var point_value: Variant = segment.get(point_name, [])
            if not point_value is Array or point_value.size() != 2: return ERR_INVALID_DATA
        if float(segment.get("restitution", -1.0)) < 0.0: return ERR_INVALID_DATA
    var markers: Dictionary = markers_value
    for marker_name in ["p1", "p2", "p3"]:
        var marker_value: Variant = markers.get(marker_name, [])
        if not marker_value is Array or marker_value.size() != 2: return ERR_INVALID_DATA

    var enemies: Dictionary = quest["enemies"]
    var simulation_enemy: Dictionary = quest["enemy"]
    var source_enemy_key := str(simulation_enemy.get("source_enemy_key", ""))
    if source_enemy_key.is_empty() or not enemies.has(source_enemy_key):
        return ERR_INVALID_DATA
    if int(simulation_enemy.get("max_hp", 0)) <= 0 or int(simulation_enemy.get("level", 0)) <= 0:
        return ERR_INVALID_DATA
    if float(simulation_enemy.get("radius", 0.0)) <= 0.0 or not simulation_enemy.get("position", []) is Array:
        return ERR_INVALID_DATA
    var simulation_position: Array = simulation_enemy["position"]
    if simulation_position.size() != 2:
        return ERR_INVALID_DATA
    var source_enemy: Dictionary = enemies[source_enemy_key]
    if str(source_enemy.get("master_id", "")) != str(simulation_enemy.get("id", "")):
        return ERR_INVALID_DATA
    if int(source_enemy.get("max_hp", 0)) != int(simulation_enemy["max_hp"]):
        return ERR_INVALID_DATA

    var zone_ids: Dictionary = {}
    var expected_zone_id := 0
    for zone_variant in quest["zones"]:
        if not zone_variant is Dictionary:
            return ERR_INVALID_DATA
        var zone: Dictionary = zone_variant
        var zone_id := int(zone.get("id", -1))
        if zone_id != expected_zone_id or zone_ids.has(zone_id):
            return ERR_INVALID_DATA
        zone_ids[zone_id] = true
        expected_zone_id += 1
        for required_zone_field in ["objective", "zako_emitters", "bosses", "multiplayer_bosses", "actions", "field_objects", "boss_group_kind"]:
            if not zone.has(required_zone_field):
                return ERR_INVALID_DATA
        if not zone["objective"] is Dictionary:
            return ERR_INVALID_DATA
        var objective: Dictionary = zone["objective"]
        var objective_kind := str(objective.get("kind", ""))
        if objective_kind not in ["zako_kill", "boss_clear"]:
            return ERR_INVALID_DATA
        if not zone["zako_emitters"] is Array or not zone["bosses"] is Array:
            return ERR_INVALID_DATA
        if not zone["actions"] is Array or not zone["field_objects"] is Dictionary:
            return ERR_INVALID_DATA
        if objective_kind == "zako_kill" and (int(objective.get("count", 0)) <= 0 or zone["zako_emitters"].is_empty()):
            return ERR_INVALID_DATA
        if objective_kind == "boss_clear" and zone["bosses"].is_empty():
            return ERR_INVALID_DATA
        for emitter_variant in zone["zako_emitters"]:
            if not emitter_variant is Dictionary:
                return ERR_INVALID_DATA
            var emitter: Dictionary = emitter_variant
            if not _has_enemy_definition(enemies, str(emitter.get("enemy_id", "")), "zako"):
                return ERR_INVALID_DATA
            if emitter.get("interval_frames") != null and int(emitter["interval_frames"]) < 0:
                return ERR_INVALID_DATA
        for action_variant in zone["actions"]:
            if not action_variant is Dictionary:
                return ERR_INVALID_DATA
            var zone_action: Dictionary = action_variant
            if int(zone_action.get("delay_frames", -1)) < 0 or str(zone_action.get("kind", "")).is_empty():
                return ERR_INVALID_DATA
        for boss_list_name in ["bosses", "multiplayer_bosses"]:
            if not zone.get(boss_list_name, []) is Array:
                return ERR_INVALID_DATA
            for boss_variant in zone[boss_list_name]:
                if not boss_variant is Dictionary:
                    return ERR_INVALID_DATA
                var boss: Dictionary = boss_variant
                if not _has_enemy_definition(enemies, str(boss.get("enemy_id", "")), str(boss.get("kind", ""))):
                    return ERR_INVALID_DATA

    var battle: Dictionary = quest["battle"]
    for required_battle_field in ["field_data_id", "field_id", "terrain_asset", "terrain_hashed_path", "zone_master_id", "enemy_level", "quest_rank", "time_limit_frames", "field_assets"]:
        if not battle.has(required_battle_field):
            return ERR_INVALID_DATA
    if str(battle.get("field_data_id", "")).is_empty() or str(battle.get("zone_master_id", "")).is_empty():
        return ERR_INVALID_DATA
    if str(battle.get("field_id", "")).is_empty() or str(battle.get("terrain_asset", "")).is_empty():
        return ERR_INVALID_DATA
    if str(battle.get("terrain_hashed_path", "")).length() != 41:
        return ERR_INVALID_DATA
    if zone_ids.is_empty() or int(battle.get("enemy_level", 0)) <= 0:
        return ERR_INVALID_DATA
    if int(battle.get("time_limit_frames", 0)) <= 0 or not battle.get("field_assets", []) is Array:
        return ERR_INVALID_DATA
    for correction_name in ["hp_corrections", "atk_corrections", "tp_corrections"]:
        if not battle.has(correction_name) or not battle[correction_name] is Dictionary:
            return ERR_INVALID_DATA

    var action_ids: Dictionary = {}
    for action_variant in quest["action_assets"]:
        if not action_variant is Dictionary:
            return ERR_INVALID_DATA
        var action: Dictionary = action_variant
        var action_id := str(action.get("id", ""))
        if action_id.is_empty() or action_ids.has(action_id):
            return ERR_INVALID_DATA
        if str(action.get("sha256", "")).length() != 64:
            return ERR_INVALID_DATA
        var runtime_value: Variant = action.get("runtime", [])
        if not runtime_value is Array or runtime_value.is_empty():
            return ERR_INVALID_DATA
        for runtime_variant in runtime_value:
            if not runtime_variant is Dictionary:
                return ERR_INVALID_DATA
            var runtime: Dictionary = runtime_variant
            var runtime_kind := str(runtime.get("kind", ""))
            if runtime_kind == "projectile":
                if float(runtime.get("radius", 0.0)) <= 0.0 or float(runtime.get("speed_per_frame", 0.0)) <= 0.0:
                    return ERR_INVALID_DATA
                if int(runtime.get("lifetime_frames", 0)) <= 0 or float(runtime.get("attack_multiplier", 0.0)) <= 0.0:
                    return ERR_INVALID_DATA
                var distribution_value: Variant = runtime.get("distribution", {})
                if not distribution_value is Dictionary or int(distribution_value.get("count", 0)) <= 0:
                    return ERR_INVALID_DATA
                if str(distribution_value.get("kind", "")) not in ["single", "n_way", "circle"]:
                    return ERR_INVALID_DATA
            elif runtime_kind == "spawn_funnel":
                if str(runtime.get("enemy_id", "")).is_empty() or int(runtime.get("level", 0)) <= 0:
                    return ERR_INVALID_DATA
            else:
                return ERR_INVALID_DATA
        action_ids[action_id] = true
    for enemy_variant in enemies.values():
        if not enemy_variant is Dictionary:
            return ERR_INVALID_DATA
        var enemy_definition: Dictionary = enemy_variant
        if not enemy_definition.has("action_assets") or not enemy_definition["action_assets"] is Array:
            return ERR_INVALID_DATA
        if int(enemy_definition.get("max_hp", 0)) <= 0 or int(enemy_definition.get("atk", 0)) <= 0:
            return ERR_INVALID_DATA
        var schedule_value: Variant = enemy_definition.get("action_schedule", {})
        var state_machine_value: Variant = enemy_definition.get("action_state_machine", {})
        if not schedule_value is Dictionary or not state_machine_value is Dictionary:
            return ERR_INVALID_DATA
        var schedule: Dictionary = schedule_value
        var state_machine: Dictionary = state_machine_value
        if schedule.is_empty() and state_machine.is_empty():
            return ERR_INVALID_DATA
        if not schedule.is_empty():
            if int(schedule.get("initial_delay_frames", 0)) <= 0 or int(schedule.get("interval_frames", 0)) <= 0:
                return ERR_INVALID_DATA
            if not schedule.get("sequence", []) is Array or schedule["sequence"].is_empty():
                return ERR_INVALID_DATA
        if not state_machine.is_empty():
            var states_value: Variant = state_machine.get("states", {})
            var initial_state_id := str(state_machine.get("initial_state_id", ""))
            if not states_value is Dictionary or initial_state_id.is_empty():
                return ERR_INVALID_DATA
            var states: Dictionary = states_value
            if not states.has(initial_state_id):
                return ERR_INVALID_DATA
            for state_id in states:
                var state_value: Variant = states[state_id]
                if not state_value is Dictionary:
                    return ERR_INVALID_DATA
                var state: Dictionary = state_value
                if str(state.get("id", "")) != str(state_id) or not states.has(str(state.get("next_state", ""))):
                    return ERR_INVALID_DATA
                var termination_value: Variant = state.get("termination", {})
                if not termination_value is Dictionary:
                    return ERR_INVALID_DATA
                var termination: Dictionary = termination_value
                if str(termination.get("kind", "")) not in ["time", "animation_loop", "move"]:
                    return ERR_INVALID_DATA
                if str(termination.get("kind", "")) == "move":
                    if int(termination.get("fallback_frames", 0)) <= 0:
                        return ERR_INVALID_DATA
                elif int(termination.get("value", 0)) <= 0:
                    return ERR_INVALID_DATA
                if state.has("action_id") and not action_ids.has(str(state["action_id"])):
                    return ERR_INVALID_DATA
        for action_id_variant in enemy_definition["action_assets"]:
            if not action_ids.has(str(action_id_variant)):
                return ERR_INVALID_DATA
        for action_id_variant in schedule.get("sequence", []):
            if not action_ids.has(str(action_id_variant)):
                return ERR_INVALID_DATA

    var source: Dictionary = quest["source"]
    if not source.has("files") or not source["files"] is Array or source["files"].is_empty():
        return ERR_INVALID_DATA
    for source_variant in source["files"]:
        if not source_variant is Dictionary:
            return ERR_INVALID_DATA
        var source_file: Dictionary = source_variant
        if str(source_file.get("path", "")).is_empty() or str(source_file.get("sha256", "")).length() != 64:
            return ERR_INVALID_DATA
    return OK

func _has_enemy_definition(enemies: Dictionary, master_id: String, kind: String) -> bool:
    if master_id.is_empty() or kind.is_empty():
        return false
    for enemy_variant in enemies.values():
        if not enemy_variant is Dictionary:
            continue
        var enemy_definition: Dictionary = enemy_variant
        if str(enemy_definition.get("master_id", "")) == master_id and str(enemy_definition.get("kind", "")) == kind:
            return int(enemy_definition.get("max_hp", 0)) > 0
    return false

func _normalize_quest(quest: Dictionary) -> Dictionary:
    var normalized := quest.duplicate(true)
    normalized["schema_version"] = int(quest["schema_version"])
    normalized["id"] = str(quest["id"])
    normalized["category"] = int(quest["category"])
    normalized["entry_stamina"] = int(quest["entry_stamina"])
    normalized["character_exp"] = int(quest["character_exp"])
    normalized["pool_exp"] = int(quest.get("pool_exp", 0))
    var rewards: Dictionary = normalized["rewards"]
    for reward_name in rewards:
        rewards[reward_name] = int(rewards[reward_name])
    var battle: Dictionary = normalized["battle"]
    battle["enemy_level"] = int(battle["enemy_level"])
    battle["quest_rank"] = int(battle["quest_rank"])
    battle["time_limit_frames"] = int(battle["time_limit_frames"])
    var zones: Array = normalized["zones"]
    for zone_variant in zones:
        var zone: Dictionary = zone_variant
        zone["id"] = int(zone["id"])
        zone["boss_group_kind"] = int(zone["boss_group_kind"])
        var objective: Dictionary = zone["objective"]
        if objective.has("count"):
            objective["count"] = int(objective["count"])
        for emitter_variant in zone["zako_emitters"]:
            var emitter: Dictionary = emitter_variant
            if emitter["interval_frames"] != null:
                emitter["interval_frames"] = int(emitter["interval_frames"])
        for action_variant in zone["actions"]:
            var action: Dictionary = action_variant
            action["delay_frames"] = int(action["delay_frames"])
    var characters: Dictionary = normalized["characters"]
    for character_key in characters:
        var character: Dictionary = characters[character_key]
        for stat_name in ["level", "rarity", "element", "hp", "atk", "main_hp", "unison_hp", "main_atk", "unison_atk"]:
            character[stat_name] = int(character[stat_name])
    var source_defaults: Dictionary = normalized["battle_source_defaults"]
    source_defaults["player_role_kind"] = int(source_defaults["player_role_kind"])
    source_defaults["player_rank"] = int(source_defaults["player_rank"])
    source_defaults["degree_id"] = int(source_defaults["degree_id"])
    source_defaults["direct_attack_reference_atk"] = int(source_defaults["direct_attack_reference_atk"])
    var behavior: Dictionary = source_defaults["battle_behavior_data"]
    behavior["skill_ability_behavior_mode"] = int(behavior["skill_ability_behavior_mode"])
    behavior["dash_behavior_mode"] = int(behavior["dash_behavior_mode"])
    var simulation_enemy: Dictionary = normalized["enemy"]
    simulation_enemy["level"] = int(simulation_enemy["level"])
    simulation_enemy["max_hp"] = int(simulation_enemy["max_hp"])
    var enemies: Dictionary = normalized["enemies"]
    for enemy_key in enemies:
        var enemy_definition: Dictionary = enemies[enemy_key]
        enemy_definition["level"] = int(enemy_definition["level"])
        enemy_definition["max_hp"] = int(enemy_definition["max_hp"])
        enemy_definition["atk"] = int(enemy_definition["atk"])
        var schedule: Dictionary = enemy_definition.get("action_schedule", {})
        if not schedule.is_empty():
            schedule["initial_delay_frames"] = int(schedule["initial_delay_frames"])
            schedule["interval_frames"] = int(schedule["interval_frames"])
        var state_machine: Dictionary = enemy_definition.get("action_state_machine", {})
        if not state_machine.is_empty():
            for state_id in state_machine["states"]:
                var state: Dictionary = state_machine["states"][state_id]
                var termination: Dictionary = state["termination"]
                if str(termination["kind"]) == "move":
                    termination["fallback_frames"] = int(termination["fallback_frames"])
                else:
                    termination["value"] = int(termination["value"])
    return normalized
