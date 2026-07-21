class_name EnemyActionExecutor
extends RefCounted

var arena: Rect2
var projectiles: Array[Dictionary] = []
var spawn_events: Array[Dictionary] = []

func _init(bounds: Rect2) -> void:
    arena = bounds

func clear() -> void:
    projectiles.clear()
    spawn_events.clear()

func start_action(
    action: Dictionary,
    origin: Vector2,
    target: Vector2,
    enemy_atk: int,
    quest_correction: float
) -> int:
    var created := 0
    for runtime_variant in action.get("runtime", []):
        if not runtime_variant is Dictionary:
            continue
        var runtime: Dictionary = runtime_variant
        var kind := str(runtime.get("kind", ""))
        if kind == "projectile":
            created += _spawn_projectile_pattern(runtime, origin, target, enemy_atk, quest_correction)
        elif kind == "spawn_funnel":
            spawn_events.append(runtime.duplicate(true))
    return created

func step(player_position: Vector2, player_radius: float) -> int:
    var damage := 0
    for index in range(projectiles.size() - 1, -1, -1):
        var projectile: Dictionary = projectiles[index]
        projectile["position"] = Vector2(projectile["position"]) + Vector2(projectile["velocity"])
        projectile["remaining_frames"] = int(projectile["remaining_frames"]) - 1
        var radius := float(projectile["radius"])
        if Vector2(projectile["position"]).distance_squared_to(player_position) <= pow(radius + player_radius, 2.0):
            damage += int(projectile["damage"])
            projectiles.remove_at(index)
            continue
        if int(projectile["remaining_frames"]) <= 0 or not arena.grow(radius).has_point(Vector2(projectile["position"])):
            projectiles.remove_at(index)
    return damage

func consume_spawn_events() -> Array[Dictionary]:
    var events := spawn_events.duplicate(true)
    spawn_events.clear()
    return events

func get_projectile_snapshots() -> Array[Dictionary]:
    return projectiles.duplicate(true)

func _spawn_projectile_pattern(
    runtime: Dictionary,
    origin: Vector2,
    target: Vector2,
    enemy_atk: int,
    quest_correction: float
) -> int:
    var distribution_value: Variant = runtime.get("distribution", {})
    if not distribution_value is Dictionary:
        return 0
    var distribution: Dictionary = distribution_value
    var count := maxi(1, int(distribution.get("count", 1)))
    var base_angle := (target - origin).angle()
    var kind := str(distribution.get("kind", "single"))
    var angles: Array[float] = []
    if kind == "circle":
        for index in range(count):
            angles.append(float(runtime.get("angle_offset_radians", 0.0)) + TAU * float(index) / float(count))
    elif kind == "n_way":
        var spread := float(distribution.get("spread_radians", 0.0))
        for index in range(count):
            angles.append(base_angle + (float(index) - float(count - 1) * 0.5) * spread)
    else:
        angles.append(base_angle)

    var attack_multiplier := float(runtime.get("attack_multiplier", 0.0))
    var damage := maxi(1, floori(float(enemy_atk) * attack_multiplier * quest_correction))
    for angle in angles:
        projectiles.append({
            "position": origin,
            "velocity": Vector2.RIGHT.rotated(angle) * float(runtime.get("speed_per_frame", 0.0)),
            "radius": float(runtime.get("radius", 1.0)),
            "remaining_frames": int(runtime.get("lifetime_frames", 1)),
            "damage": damage,
            "hit_area_name": str(runtime.get("hit_area_name", "")),
        })
    return angles.size()
