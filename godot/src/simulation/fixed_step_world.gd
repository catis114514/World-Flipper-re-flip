class_name FixedStepWorld
extends RefCounted

var gravity_per_step: Vector2
var bounds: Rect2
var bodies: Array = []
var contacts: Array = []
var terrain_segments: Array[Dictionary] = []
var terrain_contacts: Array = []

func _init(gravity: Vector2 = Vector2.ZERO, world_bounds: Rect2 = Rect2()) -> void:
    gravity_per_step = gravity
    bounds = world_bounds

func add_body(body: SimBody) -> void:
    if not bodies.has(body): bodies.append(body)

func remove_body(body: SimBody) -> void:
    bodies.erase(body)

func set_terrain_segments(segments: Array) -> void:
    terrain_segments.clear()
    for value in segments:
        if not value is Dictionary: continue
        var start_value: Variant = value.get("start", [])
        var end_value: Variant = value.get("end", [])
        if not start_value is Array or not end_value is Array or start_value.size() != 2 or end_value.size() != 2: continue
        terrain_segments.append({"id": str(value.get("id", "segment-%d" % terrain_segments.size())), "start": Vector2(float(start_value[0]), float(start_value[1])), "end": Vector2(float(end_value[0]), float(end_value[1])), "restitution": float(value.get("restitution", 1.0))})

func step(step_ratio: float = 1.0) -> void:
    contacts.clear(); terrain_contacts.clear()
    for body: SimBody in bodies:
        if body.dynamic and not body.disable_gravity: body.velocity += gravity_per_step
    for body: SimBody in bodies: body.limit_velocity()
    for body: SimBody in bodies: body.integrate(step_ratio)
    _resolve_circle_pairs()
    for body: SimBody in bodies: _resolve_terrain(body)
    if bounds.size.x > 0.0 and bounds.size.y > 0.0:
        for body: SimBody in bodies: _resolve_bounds(body)
    for body: SimBody in bodies: body.limit_velocity()

func _resolve_terrain(body: SimBody) -> void:
    if not body.dynamic or body.radius <= 0.0: return
    for segment in terrain_segments: _resolve_circle_segment(body, segment)

func _resolve_circle_segment(body: SimBody, segment: Dictionary) -> void:
    var start: Vector2 = segment["start"]
    var end: Vector2 = segment["end"]
    var edge := end - start
    var edge_length_squared := edge.length_squared()
    if edge_length_squared <= 0.0000001: return
    var projection := clampf((body.position - start).dot(edge) / edge_length_squared, 0.0, 1.0)
    var closest := start + edge * projection
    var offset := body.position - closest
    var distance_squared := offset.length_squared()
    if distance_squared >= body.radius * body.radius: return
    var distance := sqrt(distance_squared)
    var normal := Vector2(-edge.y, edge.x).normalized() if distance <= 0.0000001 else offset / distance
    if distance <= 0.0000001 and body.velocity.dot(normal) > 0.0: normal = -normal
    body.position += normal * (body.radius - distance)
    var velocity_along_normal := body.velocity.dot(normal)
    if velocity_along_normal >= 0.0: return
    terrain_contacts.append([body, str(segment["id"]), -velocity_along_normal])
    body.velocity -= normal * (1.0 + minf(body.restitution, float(segment["restitution"]))) * velocity_along_normal

func _resolve_bounds(body: SimBody) -> void:
    if not body.dynamic or body.radius <= 0.0: return
    var minimum := bounds.position + Vector2(body.radius, body.radius)
    var maximum := bounds.end - Vector2(body.radius, body.radius)
    if body.position.x < minimum.x:
        body.position.x = minimum.x
        if body.velocity.x < 0.0: body.velocity.x = -body.velocity.x * body.restitution
    elif body.position.x > maximum.x:
        body.position.x = maximum.x
        if body.velocity.x > 0.0: body.velocity.x = -body.velocity.x * body.restitution
    if body.position.y < minimum.y:
        body.position.y = minimum.y
        if body.velocity.y < 0.0: body.velocity.y = -body.velocity.y * body.restitution
    elif body.position.y > maximum.y:
        body.position.y = maximum.y
        if body.velocity.y > 0.0: body.velocity.y = -body.velocity.y * body.restitution

func _resolve_circle_pairs() -> void:
    for first_index in range(bodies.size()):
        var first: SimBody = bodies[first_index]
        if first.radius <= 0.0: continue
        for second_index in range(first_index + 1, bodies.size()):
            var second: SimBody = bodies[second_index]
            if second.radius > 0.0: _resolve_circle_pair(first, second)

func _resolve_circle_pair(first: SimBody, second: SimBody) -> void:
    var delta := second.position - first.position
    var minimum_distance := first.radius + second.radius
    var distance_squared := delta.length_squared()
    if distance_squared >= minimum_distance * minimum_distance: return
    var distance := sqrt(distance_squared)
    var normal := Vector2.RIGHT if distance <= 0.0000001 else delta / distance
    var first_inverse_mass := first.inverse_mass(); var second_inverse_mass := second.inverse_mass()
    var total_inverse_mass := first_inverse_mass + second_inverse_mass
    if total_inverse_mass <= 0.0: return
    var penetration := minimum_distance - distance
    first.position -= normal * penetration * (first_inverse_mass / total_inverse_mass)
    second.position += normal * penetration * (second_inverse_mass / total_inverse_mass)
    var velocity_along_normal := (second.velocity - first.velocity).dot(normal)
    if velocity_along_normal >= 0.0: return
    contacts.append([first, second, -velocity_along_normal])
    var impulse := normal * (-(1.0 + minf(first.restitution, second.restitution)) * velocity_along_normal / total_inverse_mass)
    first.velocity -= impulse * first_inverse_mass; second.velocity += impulse * second_inverse_mass
