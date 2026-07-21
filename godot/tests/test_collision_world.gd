extends RefCounted

const SimBody = preload("res://src/simulation/sim_body.gd")
const FixedStepWorld = preload("res://src/simulation/fixed_step_world.gd")

func run(t) -> void:
    var wall_body = SimBody.new()
    wall_body.position = Vector2(12.0, 50.0)
    wall_body.velocity = Vector2(-5.0, 0.0)
    wall_body.radius = 10.0
    wall_body.restitution = 1.0
    var wall_world = FixedStepWorld.new(Vector2.ZERO, Rect2(0.0, 0.0, 100.0, 100.0))
    wall_world.add_body(wall_body)
    wall_world.step(1.0)
    t.assert_near(wall_body.position.x, 10.0, 0.000001, "circle is projected inside left wall")
    t.assert_near(wall_body.velocity.x, 5.0, 0.000001, "circle reflects from left wall")

    var projectile = SimBody.new()
    projectile.position = Vector2(40.0, 50.0)
    projectile.velocity = Vector2(10.0, 0.0)
    projectile.radius = 10.0
    projectile.restitution = 1.0
    var enemy = SimBody.new()
    enemy.dynamic = false
    enemy.position = Vector2(65.0, 50.0)
    enemy.radius = 10.0
    enemy.restitution = 1.0
    var collision_world = FixedStepWorld.new(Vector2.ZERO, Rect2(0.0, 0.0, 200.0, 100.0))
    collision_world.add_body(projectile)
    collision_world.add_body(enemy)
    collision_world.step(1.0)
    t.assert_true(projectile.position.x <= 45.000001, "dynamic circle penetration is corrected")
    t.assert_near(projectile.velocity.x, -10.0, 0.000001, "dynamic circle reflects from static circle")
    t.assert_near(float(collision_world.contacts[0][2]), 10.0, 0.000001, "contact records normal impact speed")

    var separating = SimBody.new()
    separating.position = Vector2(40.0, 50.0)
    separating.velocity = Vector2(-1.0, 0.0)
    separating.radius = 10.0
    var separating_enemy = SimBody.new()
    separating_enemy.dynamic = false
    separating_enemy.position = Vector2(55.0, 50.0)
    separating_enemy.radius = 10.0
    var separating_world = FixedStepWorld.new(Vector2.ZERO, Rect2(0.0, 0.0, 200.0, 100.0))
    separating_world.add_body(separating)
    separating_world.add_body(separating_enemy)
    separating_world.step(1.0)
    t.assert_true(separating_world.contacts.is_empty(), "separating overlap is corrected without an impact contact")

    var segment_body = SimBody.new()
    segment_body.position = Vector2(50.0, 44.0)
    segment_body.velocity = Vector2(0.0, 2.0)
    segment_body.radius = 5.0
    segment_body.restitution = 1.0
    var segment_world = FixedStepWorld.new(Vector2.ZERO, Rect2(0.0, 0.0, 100.0, 100.0))
    segment_world.set_terrain_segments([{"id": "floor", "start": [20.0, 50.0], "end": [80.0, 50.0], "restitution": 1.0}])
    segment_world.add_body(segment_body)
    segment_world.step(1.0)
    t.assert_near(segment_body.position.y, 45.0, 0.000001, "circle is projected off terrain segment")
    t.assert_near(segment_body.velocity.y, -2.0, 0.000001, "approaching circle reflects from terrain segment")
    t.assert_near(float(segment_world.terrain_contacts[0][2]), 2.0, 0.000001, "terrain contact records normal impact speed")

    var separating_segment_body = SimBody.new()
    separating_segment_body.position = Vector2(50.0, 48.0)
    separating_segment_body.velocity = Vector2(0.0, -1.0)
    separating_segment_body.radius = 5.0
    var separating_segment_world = FixedStepWorld.new(Vector2.ZERO, Rect2(0.0, 0.0, 100.0, 100.0))
    separating_segment_world.set_terrain_segments([{"id": "floor", "start": [20.0, 50.0], "end": [80.0, 50.0]}])
    separating_segment_world.add_body(separating_segment_body)
    separating_segment_world.step(1.0)
    t.assert_true(separating_segment_world.terrain_contacts.is_empty(), "separating terrain overlap corrects without reflection")
    t.assert_near(separating_segment_body.velocity.y, -1.0, 0.000001, "separating terrain velocity is preserved")

    var first := _run_repeatable_world()
    var second := _run_repeatable_world()
    t.assert_equal(first, second, "fixed-step world repeats identical state")

func _run_repeatable_world() -> Array:
    var body = SimBody.new()
    body.position = Vector2(50.0, 20.0)
    body.velocity = Vector2(3.0, 0.0)
    body.radius = 5.0
    body.restitution = 0.8
    var world = FixedStepWorld.new(Vector2(0.0, 0.5), Rect2(0.0, 0.0, 100.0, 100.0))
    world.add_body(body)
    for index in range(120):
        world.step(1.0)
    return [snappedf(body.position.x, 0.000001), snappedf(body.position.y, 0.000001), snappedf(body.velocity.x, 0.000001), snappedf(body.velocity.y, 0.000001)]

func _run_terrain_corner() -> Array:
    var body = SimBody.new()
    body.position = Vector2(44.0, 44.0)
    body.velocity = Vector2(2.0, 2.0)
    body.radius = 5.0
    body.restitution = 1.0
    var world = FixedStepWorld.new(Vector2.ZERO, Rect2(0.0, 0.0, 100.0, 100.0))
    world.set_terrain_segments([
        {"id": "horizontal", "start": [20.0, 50.0], "end": [50.0, 50.0], "restitution": 1.0},
        {"id": "vertical", "start": [50.0, 20.0], "end": [50.0, 50.0], "restitution": 1.0},
    ])
    world.add_body(body)
    world.step(1.0)
    return [snappedf(body.position.x, 0.000001), snappedf(body.position.y, 0.000001), snappedf(body.velocity.x, 0.000001), snappedf(body.velocity.y, 0.000001)]