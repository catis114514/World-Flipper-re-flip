class_name SimBody
extends RefCounted

var tag := ""
var dynamic := true
var disable_gravity := false
var position := Vector2.ZERO
var velocity := Vector2.ZERO
var pseudo_velocity := Vector2.ZERO
var angle := 0.0
var angular_velocity := 0.0
var pseudo_angular_velocity := 0.0
var linear_damping := 0.0
var angular_damping := 0.0
var limit_max_linear_velocity := false
var max_linear_velocity := 1000000.0
var limit_max_angular_velocity := false
var max_angular_velocity := 1000000.0
var radius := 0.0
var restitution := 0.0

func inverse_mass() -> float:
    return 1.0 if dynamic else 0.0

func limit_velocity() -> void:
    var speed_squared := velocity.length_squared()
    if limit_max_linear_velocity and speed_squared > max_linear_velocity * max_linear_velocity:
        velocity *= max_linear_velocity / sqrt(speed_squared)
    if limit_max_angular_velocity:
        angular_velocity = clampf(angular_velocity, -max_angular_velocity, max_angular_velocity)

func integrate(step_ratio: float) -> void:
    if not dynamic:
        velocity = Vector2.ZERO
        angular_velocity = 0.0
    else:
        if linear_damping > 0.0:
            var linear_term := linear_damping * step_ratio
            var linear_factor := 1.0 / (
                1.0 + linear_term * (1.0 + linear_term * (0.5 + linear_term / 6.0))
            )
            velocity *= linear_factor
        if angular_damping > 0.0:
            var angular_term := angular_damping * step_ratio
            var angular_factor := 1.0 / (
                1.0 + angular_term * (1.0 + angular_term * (0.5 + angular_term / 6.0))
            )
            angular_velocity *= angular_factor
        position += velocity * step_ratio + pseudo_velocity
        angle += angular_velocity * step_ratio + pseudo_angular_velocity
    pseudo_velocity = Vector2.ZERO
    pseudo_angular_velocity = 0.0
