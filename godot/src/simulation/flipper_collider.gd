class_name FlipperCollider
extends RefCounted

var state: FlipperState
var pivot: Vector2
var base_direction: Vector2
var length: float
var collision_radius: float

func _init(
    flipper_state: FlipperState,
    pivot_position: Vector2,
    initial_direction: Vector2,
    flipper_length: float,
    radius: float
) -> void:
    state = flipper_state
    pivot = pivot_position
    base_direction = initial_direction.normalized()
    length = flipper_length
    collision_radius = radius

func direction() -> Vector2:
    return base_direction.rotated(state.angle)

func point_at(ratio: float) -> Vector2:
    return pivot + direction() * length * clampf(ratio, 0.0, 1.0)

func resolve_ball(ball: SimBody) -> bool:
    var segment := direction() * length
    var segment_length_squared := segment.length_squared()
    if segment_length_squared <= 0.0000001:
        return false
    var ratio := clampf((ball.position - pivot).dot(segment) / segment_length_squared, 0.0, 1.0)
    var closest := pivot + segment * ratio
    var delta := ball.position - closest
    var minimum_distance := ball.radius + collision_radius
    var distance_squared := delta.length_squared()
    if distance_squared >= minimum_distance * minimum_distance:
        return false

    var distance := sqrt(distance_squared)
    var normal := Vector2(-direction().y, direction().x) if distance <= 0.0000001 else delta / distance
    ball.position += normal * (minimum_distance - distance)

    var lever := closest - pivot
    var surface_velocity := Vector2(-lever.y, lever.x) * state.angular_velocity
    var relative_velocity := ball.velocity - surface_velocity
    var velocity_along_normal := relative_velocity.dot(normal)
    if velocity_along_normal < 0.0:
        ball.velocity -= normal * (1.0 + ball.restitution) * velocity_along_normal
    return true
