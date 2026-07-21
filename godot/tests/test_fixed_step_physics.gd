extends RefCounted

const SimBody = preload("res://src/simulation/sim_body.gd")
const FixedStepWorld = preload("res://src/simulation/fixed_step_world.gd")
const FlipperState = preload("res://src/simulation/flipper_state.gd")

func run(t) -> void:
    var body = SimBody.new()
    body.velocity = Vector2(10.0, -5.0)
    body.integrate(0.5)
    t.assert_near(body.position.x, 5.0, 0.000001, "body integrates x like AS3 Body.integrate")
    t.assert_near(body.position.y, -2.5, 0.000001, "body integrates y like AS3 Body.integrate")

    var damped = SimBody.new()
    damped.velocity = Vector2(12.0, 0.0)
    damped.linear_damping = 2.0
    damped.integrate(0.5)
    var damping_factor := 1.0 / (1.0 + 1.0 * (1.0 + 1.0 * (0.5 + 1.0 / 6.0)))
    t.assert_near(damped.velocity.x, 12.0 * damping_factor, 0.000001, "body uses original damping approximation")

    var falling = SimBody.new()
    var world = FixedStepWorld.new(Vector2(0.0, 1.0))
    world.add_body(falling)
    world.step(1.0)
    t.assert_equal(falling.velocity, Vector2(0.0, 1.0), "world applies gravity before integration")
    t.assert_equal(falling.position, Vector2(0.0, 1.0), "world integrates after gravity")

    var left = FlipperState.new(true, 0.25, 0.10, 0.10, 0.50)
    left.on_pressed()
    left.update()
    left.integrate(1.0)
    t.assert_near(left.angle, -0.5, 0.000001, "left flipper clamps to negative target")
    t.assert_true(left.is_flipping(), "left flipper reports active upward rotation")

    var right = FlipperState.new(false, 0.25, 0.10, 0.10, 0.50)
    right.on_pressed()
    right.update()
    right.integrate(1.0)
    t.assert_near(right.angle, 0.5, 0.000001, "right flipper clamps to positive target")
