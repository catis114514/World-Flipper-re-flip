class_name FlipperState
extends RefCounted

var left: bool
var rpf_up: float
var rpf_down: float
var min_rad: float
var max_rad: float
var target_angle: float
var angle := 0.0
var angular_velocity := 0.0
var rotation_state := 0
var next_rotation_state := 0
var pressed := false
var auto_return := false

func _init(
    is_left: bool,
    up_revolutions_per_frame: float,
    down_revolutions_per_frame: float,
    minimum_radians: float,
    maximum_radians: float
) -> void:
    left = is_left
    rpf_up = up_revolutions_per_frame
    rpf_down = down_revolutions_per_frame
    min_rad = minimum_radians
    max_rad = maximum_radians
    target_angle = min_rad

func update_flipper_rotation(up: float, down: float, target: float) -> void:
    rotation_state = next_rotation_state
    var up_delta := TAU * up
    var down_delta := TAU * down
    if left:
        if angle + down_delta > -target and angle - up_delta < -target:
            angular_velocity = -target - angle
        else:
            angular_velocity = down_delta if angle < -target else -up_delta
        next_rotation_state = 1 if angular_velocity < -0.00001 else (-1 if angular_velocity > 0.00001 else 0)
    else:
        if angle + up_delta > target and angle - down_delta < target:
            angular_velocity = target - angle
        else:
            angular_velocity = up_delta if angle < target else -down_delta
        next_rotation_state = 1 if angular_velocity > 0.00001 else (-1 if angular_velocity < -0.00001 else 0)

func update() -> void:
    update_flipper_rotation(rpf_up, rpf_down, target_angle)
    if rotation_state == 0 and auto_return:
        auto_return = false
        target_angle = min_rad

func integrate(step_ratio: float) -> void:
    angle += angular_velocity * step_ratio

func on_pressed() -> void:
    pressed = true
    auto_return = false
    target_angle = max_rad

func on_released() -> void:
    pressed = false
    target_angle = min_rad

func is_flipping() -> bool:
    if rotation_state != 1:
        return next_rotation_state == 1
    return true
