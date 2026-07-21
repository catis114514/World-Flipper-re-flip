extends Node2D

const SaveRepository = preload("res://src/persistence/save_repository.gd")
const LocalProfileService = preload("res://src/domain/local_profile_service.gd")
const StaticContentRepository = preload("res://src/content/static_content_repository.gd")
const BattleSessionService = preload("res://src/domain/battle_session_service.gd")

@onready var menu: Control = $UI/Menu
@onready var profile_label: Label = $UI/Menu/ProfileLabel
@onready var quest_label: Label = $UI/Menu/QuestLabel
@onready var start_button: Button = $UI/Menu/StartButton
@onready var battle_hud: Control = $UI/BattleHUD
@onready var enemy_label: Label = $UI/BattleHUD/EnemyLabel
@onready var help_label: Label = $UI/BattleHUD/HelpLabel
@onready var result_panel: Control = $UI/ResultPanel
@onready var result_label: Label = $UI/ResultPanel/ResultContent/ResultLabel
@onready var return_button: Button = $UI/ResultPanel/ResultContent/ReturnButton

var save_repository
var content_repository
var session_service
var profile
var quest: Dictionary = {}
var battle
var active_run_id := ""
var fixed_step_accumulator := 0.0
var pending_result_action := ""
var recovery_pending := false

func _ready() -> void:
    save_repository = SaveRepository.new()
    content_repository = StaticContentRepository.new()
    var fixture_error: int = content_repository.load_fixture("res://content/fixtures/quest_1001002.json")
    if fixture_error != OK:
        quest_label.text = "关卡数据加载失败：%s" % fixture_error
        start_button.disabled = true
        return
    quest = content_repository.get_quest("1001002")
    session_service = BattleSessionService.new(
        save_repository,
        LocalProfileService.new(),
        content_repository
    )
    profile = session_service.load_or_create_profile()
    if profile == null:
        quest_label.text = "本地存档创建失败"
        start_button.disabled = true
        return
    start_button.pressed.connect(_start_battle)
    return_button.pressed.connect(_on_result_button_pressed)
    if not profile.active_run.is_empty() and not session_service.abort_battle(profile):
        recovery_pending = true
        quest_label.text = "中断战斗恢复失败，修复存储后重试"
        start_button.text = "重试恢复"
        return
    _refresh_menu()

func _process(delta: float) -> void:
    if battle == null or battle.status != "running":
        return
    fixed_step_accumulator += delta * 60.0
    var flippers_pressed := Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
    battle.set_flippers_pressed(flippers_pressed)
    if Input.is_key_pressed(KEY_1): battle.activate_skill(0)
    if Input.is_key_pressed(KEY_2): battle.activate_skill(1)
    if Input.is_key_pressed(KEY_3): battle.activate_skill(2)
    while fixed_step_accumulator >= 1.0 and battle.status == "running":
        battle.step()
        fixed_step_accumulator -= 1.0
    enemy_label.text = _battle_status_text()
    queue_redraw()
    if battle.status == "cleared":
        _finish_battle()
    elif battle.status == "failed":
        _show_failed_battle()

func _draw() -> void:
    if battle == null or not battle_hud.visible:
        return
    draw_rect(Rect2(0.0, 0.0, 720.0, 1280.0), Color("101827"), true)
    for segment in battle.world.terrain_segments:
        draw_line(Vector2(segment["start"]), Vector2(segment["end"]), Color("5b718f"), 6.0, true)
    if battle.enemy_active:
        draw_circle(battle.enemy.position, battle.enemy.radius, Color("e85d75"))
    for funnel_variant in battle.get_funnel_snapshots():
        var funnel: Dictionary = funnel_variant
        draw_circle(Vector2(funnel["position"]), float(funnel["radius"]), Color("9b5de5"))
    for projectile_variant in battle.get_projectile_snapshots():
        var projectile: Dictionary = projectile_variant
        draw_circle(Vector2(projectile["position"]), float(projectile["radius"]), Color("ff9f43"))
    draw_circle(battle.player.position, battle.player.radius, Color("f5d76e"))
    draw_line(
        battle.left_collider.pivot,
        battle.left_collider.point_at(1.0),
        Color("7bdff2"),
        battle.left_collider.collision_radius * 2.0,
        true
    )
    draw_line(
        battle.right_collider.pivot,
        battle.right_collider.point_at(1.0),
        Color("7bdff2"),
        battle.right_collider.collision_radius * 2.0,
        true
    )

func _start_battle() -> void:
    if recovery_pending:
        if session_service.abort_battle(profile):
            recovery_pending = false
            start_button.text = "进入 1001002「开始的草原」"
            _refresh_menu()
        else:
            quest_label.text = "中断战斗恢复仍失败"
        return
    if battle != null or not profile.active_run.is_empty():
        return
    var candidate_run_id := _new_persistent_id("run")
    var started_battle = session_service.start_battle(profile, "1001002", candidate_run_id)
    if started_battle == null:
        quest_label.text = "无法开始关卡，请检查本地档"
        return
    active_run_id = candidate_run_id
    battle = started_battle
    fixed_step_accumulator = 0.0
    pending_result_action = ""
    return_button.text = "返回"
    menu.visible = false
    result_panel.visible = false
    battle_hud.visible = true
    help_label.text = "空格 / 鼠标左键：弹板  |  1/2/3：角色技能"
    enemy_label.text = _battle_status_text()
    queue_redraw()

func _finish_battle() -> void:
    var applied: bool = session_service.finish_battle(
        profile,
        battle,
        "result-%s" % active_run_id
    )
    battle_hud.visible = false
    result_panel.visible = true
    if applied:
        pending_result_action = ""
        result_label.text = "通关！Mana +%d" % int(quest["rewards"]["free_mana"])
        return_button.text = "返回"
    else:
        pending_result_action = "finish"
        result_label.text = "结算保存失败，存档未改动"
        return_button.text = "重试结算"
    queue_redraw()

func _show_failed_battle() -> void:
    var aborted: bool = session_service.abort_battle(profile)
    battle_hud.visible = false
    result_panel.visible = true
    if aborted:
        pending_result_action = ""
        result_label.text = _failure_result_text()
        return_button.text = "返回"
    else:
        pending_result_action = "abort"
        result_label.text = "失败状态保存失败，存档未改动"
        return_button.text = "重试保存"
    queue_redraw()

func _failure_result_text() -> String:
    if battle.status_reason == "timeout":
        return "挑战失败：时间耗尽"
    if battle.status_reason == "party_defeated":
        return "挑战失败：队伍全灭"
    return "挑战失败：战斗数据异常（%s）" % battle.status_reason

func _on_result_button_pressed() -> void:
    if pending_result_action == "finish":
        _finish_battle()
        return
    if pending_result_action == "abort":
        _show_failed_battle()
        return
    _return_to_menu()

func _return_to_menu() -> void:
    battle = null
    active_run_id = ""
    pending_result_action = ""
    return_button.text = "返回"
    result_panel.visible = false
    menu.visible = true
    _refresh_menu()
    queue_redraw()

func _battle_status_text() -> String:
    var progress: Dictionary = battle.get_progress_snapshot()
    var zone_text := "区域 %d/%d" % [int(progress["zone_index"]) + 1, int(progress["zone_count"])]
    var skill_parts: Array[String] = []
    for skill in progress["skill_slots"]:
        skill_parts.append("%s %d/%d" % [str(skill["name"]), int(skill["skill_point"]), int(skill["max_skill_point"])])
    var party_text := "队伍 HP %d/%d  |  连击 %d/PF%d  |  弹幕 %d  |  浮游炮 %d  |  %s" % [
        int(progress["player_hp"]), int(progress["player_max_hp"]), int(progress["combo_count"]),
        int(progress["power_flip_level"]), int(progress["projectile_count"]), int(progress["active_funnel_count"]),
        " / ".join(skill_parts),
    ]
    var remaining_seconds := ceili(float(maxi(0, battle.time_limit_frames - battle.elapsed_frames)) / 60.0)
    if not bool(progress["enemy_active"]):
        return "%s  |  %s  |  下一波 %d  |  剩余 %d秒" % [zone_text, party_text, int(progress["frames_until_spawn"]), remaining_seconds]
    if str(progress["objective_kind"]) == "zako_kill":
        return "%s  |  %s  |  击破 %d/%d  |  HP %d  |  剩余 %d秒" % [
            zone_text,
            party_text,
            int(progress["objective_progress"]),
            int(progress["objective_target"]),
            int(progress["enemy_hp"]),
            remaining_seconds,
        ]
    return "%s  |  %s  |  Boss HP %d  |  剩余 %d秒" % [zone_text, party_text, int(progress["enemy_hp"]), remaining_seconds]

func _refresh_menu() -> void:
    profile_label.text = "%s  |  Mana %d  |  星导石 %d" % [
        profile.display_name,
        int(profile.currencies.get("free_mana", 0)),
        int(profile.currencies.get("free_vmoney", 0)),
    ]
    var clear_count := 0
    if profile.quest_progress.has("1001002"):
        clear_count = int(profile.quest_progress["1001002"].get("clear_count", 0))
    quest_label.text = "%s  |  体力 %d  |  已通关 %d 次" % [
        quest["name"],
        int(quest["entry_stamina"]),
        clear_count,
    ]

func _new_persistent_id(prefix: String) -> String:
    var random_bytes := Crypto.new().generate_random_bytes(16)
    return "%s-%s" % [prefix, random_bytes.hex_encode()]
