extends RefCounted

const SimBody = preload("res://src/simulation/sim_body.gd")
const FlipperState = preload("res://src/simulation/flipper_state.gd")
const FlipperCollider = preload("res://src/simulation/flipper_collider.gd")

func run(t) -> void:
    var state = FlipperState.new(true, 0.05, 0.02, 0.0, 0.5)
    var collider = FlipperCollider.new(state, Vector2.ZERO, Vector2.RIGHT, 100.0, 8.0)
    state.on_pressed()
    state.update()
    state.integrate(1.0)

    var direction: Vector2 = collider.direction()
    var surface_normal := Vector2(-direction.y, direction.x)
    var ball = SimBody.new()
    ball.radius = 8.0
    ball.restitution = 0.8
    ball.position = collider.point_at(0.75) - surface_normal * 12.0

    t.assert_true(collider.resolve_ball(ball), "rotating flipper capsule contacts the ball")
    t.assert_true(ball.velocity.length() > 0.0, "flipper contact transfers surface velocity")
    t.assert_true(ball.velocity.y < 0.0, "left flipper launches the tested ball upward")
    t.assert_true(not collider.resolve_ball(_far_ball()), "flipper ignores a distant ball")

func _far_ball():
    var ball = SimBody.new()
    ball.radius = 8.0
    ball.position = Vector2(1000.0, 1000.0)
    return ball
