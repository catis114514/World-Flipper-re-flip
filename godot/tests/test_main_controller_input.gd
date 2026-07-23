extends RefCounted

const MainController = preload("res://src/presentation/main_controller.gd")

class SpyBattle:
    extends RefCounted

    var status := "running"
    var activated_slots: Array[int] = []

    func activate_skill(slot_index: int) -> bool:
        activated_slots.append(slot_index)
        return true

func run(t) -> void:
    var controller = MainController.new()
    t.assert_true(controller.has_method("_handle_battle_key_event"), "main controller exposes a testable keyboard input boundary")
    if not controller.has_method("_handle_battle_key_event"):
        controller.free()
        return

    var battle = SpyBattle.new()
    controller.battle = battle

    t.assert_true(controller._handle_battle_key_event(_key_event(KEY_SPACE, true)), "Space press is consumed as a flipper input")
    t.assert_true(controller.active_flipper_keys.has(KEY_SPACE), "Space press holds both flippers")
    t.assert_true(controller._handle_battle_key_event(_key_event(KEY_DOWN, true)), "Down press is consumed as a flipper input")
    t.assert_equal(controller.active_flipper_keys.size(), 2, "Space and Down are tracked independently")
    controller._handle_battle_key_event(_key_event(KEY_SPACE, false))
    t.assert_true(controller.active_flipper_keys.has(KEY_DOWN), "releasing Space keeps Down-held flippers active")
    controller._handle_battle_key_event(_key_event(KEY_DOWN, false))
    t.assert_true(controller.active_flipper_keys.is_empty(), "releasing both flipper keys releases the flippers")

    controller._handle_battle_key_event(_key_event(KEY_SPACE, true, true))
    t.assert_true(controller.active_flipper_keys.is_empty(), "keyboard echo does not create a new flipper press")

    for keycode in [KEY_LEFT, KEY_UP, KEY_RIGHT, KEY_1, KEY_2, KEY_3]:
        controller._handle_battle_key_event(_key_event(keycode, true))
        controller._handle_battle_key_event(_key_event(keycode, false))
    t.assert_equal(battle.activated_slots, [0, 1, 2, 0, 1, 2], "arrow keys and numeric compatibility keys map to skill slots one through three")

    controller._handle_battle_key_event(_key_event(KEY_LEFT, true, true))
    controller._handle_battle_key_event(_key_event(KEY_LEFT, false))
    t.assert_equal(battle.activated_slots.size(), 6, "skill release and echo events do not repeat activation")
    t.assert_true(not controller._handle_battle_key_event(_key_event(KEY_A, true)), "unrelated keys remain unhandled")

    controller._handle_battle_key_event(_key_event(KEY_SPACE, true))
    controller._clear_active_inputs()
    t.assert_true(controller.active_flipper_keys.is_empty(), "input cleanup clears held keyboard flippers")

    battle.status = "cleared"
    t.assert_true(not controller._handle_battle_key_event(_key_event(KEY_DOWN, true)), "terminal battles ignore keyboard input")
    controller.battle = null
    t.assert_true(not controller._handle_battle_key_event(_key_event(KEY_LEFT, true)), "missing battles ignore keyboard input")
    controller.free()

func _key_event(keycode: Key, pressed: bool, echo: bool = false) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.pressed = pressed
    event.echo = echo
    return event
