extends RefCounted

static func impact_once(battle, speed: float = 30.0) -> void:
    var start_distance: float = battle.player.radius + battle.enemy.radius + 8.0
    battle.set_player_state(
        battle.enemy.position - Vector2(start_distance, 0.0),
        Vector2(speed, 0.0)
    )
    battle.step()

static func defeat_active_enemy(battle, max_impacts: int = 1000) -> void:
    var impacts := 0
    var spawn_serial: int = battle.enemy_spawn_serial
    while battle.status == "running" and battle.enemy_active and battle.enemy_spawn_serial == spawn_serial and impacts < max_impacts:
        impact_once(battle)
        impacts += 1
static func wait_for_enemy(battle, max_frames: int = 1000) -> void:
    var frames := 0
    while battle.status == "running" and not battle.enemy_active and frames < max_frames:
        battle.step()
        frames += 1

static func clear_quest(battle, max_frames: int = 10000) -> void:
    var frames := 0
    while battle.status == "running" and frames < max_frames:
        if battle.enemy_active:
            impact_once(battle)
        else:
            battle.step()
        frames += 1
