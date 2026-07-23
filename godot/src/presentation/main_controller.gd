extends Node2D

const SaveRepository = preload("res://src/persistence/save_repository.gd")
const LocalProfileService = preload("res://src/domain/local_profile_service.gd")
const StaticContentRepository = preload("res://src/content/static_content_repository.gd")
const BattleSessionService = preload("res://src/domain/battle_session_service.gd")
const OfflineCatalogRepository = preload("res://src/content/offline_catalog_repository.gd")
const OfflineGameService = preload("res://src/domain/offline_game_service.gd")
const ProfileDataScript = preload("res://src/domain/profile_data.gd")
const BATTLE_FIXTURES := [
    {"id": "1001002", "path": "res://content/fixtures/quest_1001002.json"},
    {"id": "1002001", "path": "res://content/fixtures/quest_1002001.json"},
    {"id": "1002002", "path": "res://content/fixtures/quest_1002002.json"},
]

@onready var menu: Control = $UI/Menu
@onready var profile_label: Label = $UI/Menu/ProfileLabel
@onready var quest_label: Label = $UI/Menu/QuestLabel
@onready var start_button: Button = $UI/Menu/StartButton
@onready var replay_button: Button = $UI/Menu/ReplayButton
@onready var party_label: Label = $UI/Menu/PartyLabel
@onready var system_label: Label = $UI/Menu/SystemLabel
@onready var cycle_party_button: Button = $UI/Menu/Actions/CyclePartyButton
@onready var upgrade_button: Button = $UI/Menu/Actions/UpgradeButton
@onready var gacha_button: Button = $UI/Menu/GachaButton
@onready var battle_hud: Control = $UI/BattleHUD
@onready var enemy_label: Label = $UI/BattleHUD/EnemyLabel
@onready var help_label: Label = $UI/BattleHUD/HelpLabel
@onready var skill_buttons: Array[Button] = [
    $UI/BattleHUD/SkillButtons/Skill1,
    $UI/BattleHUD/SkillButtons/Skill2,
    $UI/BattleHUD/SkillButtons/Skill3,
]
@onready var result_panel: Control = $UI/ResultPanel
@onready var result_label: Label = $UI/ResultPanel/ResultContent/ResultLabel
@onready var return_button: Button = $UI/ResultPanel/ResultContent/ReturnButton

var save_repository
var content_repository
var catalog_repository
var game_service
var session_service
var profile
var quest: Dictionary = {}
var current_quest_meta: Dictionary = {}
var battle
var active_run_id := ""
var fixed_step_accumulator := 0.0
var pending_result_action := ""
var recovery_pending := false
var last_notice := ""
var active_touch_ids: Dictionary = {}

func _ready() -> void:
    var configured_save_path := OS.get_environment("STARPOINT_SAVE_PATH")
    save_repository = SaveRepository.new(configured_save_path if not configured_save_path.is_empty() else "user://saves/profile.json")
    content_repository = StaticContentRepository.new()
    catalog_repository = OfflineCatalogRepository.new()
    game_service = OfflineGameService.new()
    var catalog_error: int = catalog_repository.load_catalog("res://content/catalogs/offline_catalogs.json")
    if catalog_error != OK:
        quest_label.text = "离线目录加载失败：%s" % catalog_error
        start_button.disabled = true
        return
    for fixture in BATTLE_FIXTURES:
        var fixture_error: int = content_repository.load_fixture(str(fixture["path"]))
        if fixture_error != OK:
            quest_label.text = "关卡数据加载失败：%s（%s）" % [fixture_error, str(fixture["id"])]
            start_button.disabled = true
            return
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
    quest = _resolve_next_quest()
    start_button.pressed.connect(_start_battle)
    replay_button.pressed.connect(_begin_battle_session)
    return_button.pressed.connect(_on_result_button_pressed)
    cycle_party_button.pressed.connect(_cycle_party)
    upgrade_button.pressed.connect(_upgrade_leader)
    gacha_button.pressed.connect(_draw_ten)
    for index in range(skill_buttons.size()):
        skill_buttons[index].pressed.connect(_activate_skill.bind(index))
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
    var flippers_pressed := not active_touch_ids.is_empty() or Input.is_key_pressed(KEY_SPACE) or (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _pointer_over_skill_button())
    battle.set_flippers_pressed(flippers_pressed)
    if Input.is_key_pressed(KEY_1): battle.activate_skill(0)
    if Input.is_key_pressed(KEY_2): battle.activate_skill(1)
    if Input.is_key_pressed(KEY_3): battle.activate_skill(2)
    while fixed_step_accumulator >= 1.0 and battle.status == "running":
        battle.step()
        fixed_step_accumulator -= 1.0
    enemy_label.text = _battle_status_text()
    _refresh_skill_buttons()
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
    for enemy_variant in battle.get_enemy_snapshots():
        var enemy_snapshot: Dictionary = enemy_variant
        var enemy_position_value: Array = enemy_snapshot["position"]
        var enemy_position := Vector2(float(enemy_position_value[0]), float(enemy_position_value[1]))
        var enemy_color := Color("e85d75") if str(enemy_snapshot["enemy_id"]) == "slango" else Color("63cdda")
        draw_circle(enemy_position, float(enemy_snapshot["radius"]), enemy_color)
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

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch and battle != null and battle.status == "running":
        if event.pressed: active_touch_ids[event.index] = true
        else: active_touch_ids.erase(event.index)

func _pointer_over_skill_button() -> bool:
    var pointer := get_viewport().get_mouse_position()
    for button in skill_buttons:
        if button.visible and button.get_global_rect().has_point(pointer): return true
    return false

func _activate_skill(index: int) -> void:
    if battle != null and battle.status == "running":
        battle.activate_skill(index)
        _refresh_skill_buttons()

func _refresh_skill_buttons() -> void:
    if battle == null: return
    var progress: Dictionary = battle.get_progress_snapshot()
    var slots: Array = progress.get("skill_slots", [])
    for index in range(skill_buttons.size()):
        if index >= slots.size():
            skill_buttons[index].disabled = true
            continue
        var slot: Dictionary = slots[index]
        skill_buttons[index].text = "%s\n%d/%d" % [str(slot["name"]), int(slot["skill_point"]), int(slot["max_skill_point"])]
        skill_buttons[index].disabled = int(slot["skill_point"]) < int(slot["max_skill_point"])
func _start_battle() -> void:
    if recovery_pending:
        if session_service.abort_battle(profile):
            recovery_pending = false
            start_button.text = "开始当前主线"
            _refresh_menu()
        else:
            quest_label.text = "中断战斗恢复仍失败"
        return
    current_quest_meta = _next_catalog_quest()
    if str(current_quest_meta.get("kind", "")) == "story":
        _complete_story(current_quest_meta)
        return
    if not current_quest_meta.is_empty():
        var next_quest_id := str(current_quest_meta.get("id", ""))
        var next_quest: Dictionary = content_repository.get_quest(next_quest_id)
        if next_quest.is_empty():
            last_notice = "下一战斗 %s「%s」尚未生成完整战斗图" % [next_quest_id, str(current_quest_meta.get("name", ""))]
            _refresh_menu()
            return
        quest = next_quest
    _begin_battle_session()

func _begin_battle_session() -> void:
    if battle != null or not profile.active_run.is_empty():
        return
    var candidate_run_id := _new_persistent_id("run")
    if quest.is_empty():
        quest = _latest_replay_quest()
    if quest.is_empty():
        quest_label.text = "没有可玩的离线关卡"
        return
    var started_battle = session_service.start_battle(
        profile,
        str(quest["id"]),
        candidate_run_id,
        int(quest.get("entry_stamina", 0)),
        int(Time.get_unix_time_from_system())
    )
    if started_battle == null:
        quest_label.text = "无法开始关卡，请检查本地档"
        return
    active_run_id = candidate_run_id
    active_touch_ids.clear()
    battle = started_battle
    fixed_step_accumulator = 0.0
    pending_result_action = ""
    return_button.text = "返回"
    menu.visible = false
    result_panel.visible = false
    battle_hud.visible = true
    help_label.text = "空格 / 鼠标左键：弹板  |  1/2/3：角色技能"
    _refresh_skill_buttons()
    enemy_label.text = _battle_status_text()
    queue_redraw()

func _finish_battle() -> void:
    active_touch_ids.clear()
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
    active_touch_ids.clear()
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
    active_touch_ids.clear()
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
    var active_enemies: Array = progress.get("enemies", [])
    var active_enemy_hp := 0
    for enemy_snapshot in active_enemies:
        active_enemy_hp += int(enemy_snapshot.get("hp", 0))
    if str(progress["objective_kind"]) == "zako_kill":
        return "%s  |  %s  |  击破 %d/%d  |  敌人 %d / 总HP %d  |  剩余 %d秒" % [
            zone_text,
            party_text,
            int(progress["objective_progress"]),
            int(progress["objective_target"]),
            active_enemies.size(),
            active_enemy_hp,
            remaining_seconds,
        ]
    return "%s  |  %s  |  Boss %d / 总HP %d  |  剩余 %d秒" % [zone_text, party_text, active_enemies.size(), active_enemy_hp, remaining_seconds]

func _refresh_menu() -> void:
    var stamina: int = int(game_service.settle_stamina(profile, int(Time.get_unix_time_from_system())))
    profile_label.text = "%s  |  RankPt %d  |  Mana %d  |  星导石 %d  |  体力 %d" % [
        profile.display_name,
        profile.rank_points,
        int(profile.currencies.get("free_mana", 0)),
        int(profile.currencies.get("free_vmoney", 0)),
        stamina,
    ]
    current_quest_meta = _next_catalog_quest()
    var next_quest_id := str(current_quest_meta.get("id", ""))
    var next_fixture: Dictionary = content_repository.get_quest(next_quest_id) if not next_quest_id.is_empty() else {}
    var replay_quest: Dictionary = _latest_replay_quest()
    if str(current_quest_meta.get("kind", "")) == "battle" and not next_fixture.is_empty():
        quest = next_fixture
    elif not replay_quest.is_empty():
        quest = replay_quest
    var selected_quest_id := str(quest.get("id", ""))
    var clear_count := int(profile.quest_progress.get(selected_quest_id, {}).get("clear_count", 0))
    var location := _quest_location_text(current_quest_meta)
    if current_quest_meta.is_empty():
        if quest.is_empty():
            quest_label.text = "主线目录为空，且没有已通关的离线关卡"
            start_button.text = "没有可玩的离线关卡"
            start_button.disabled = true
        else:
            quest_label.text = "主线目录已完成  |  %s 已通关 %d 次" % [selected_quest_id, clear_count]
            start_button.text = "重玩 %s「%s」" % [selected_quest_id, str(quest.get("name", ""))]
            start_button.disabled = false
        replay_button.visible = false
    elif str(current_quest_meta.get("kind", "")) == "story":
        quest_label.text = "%s  |  下一主线：%s「%s」（剧情）" % [location, str(current_quest_meta["id"]), str(current_quest_meta["name"])]
        start_button.text = "阅读剧情「%s」" % str(current_quest_meta["name"])
        start_button.disabled = false
        replay_button.visible = not replay_quest.is_empty()
        replay_button.text = "重玩 %s「%s」" % [selected_quest_id, str(quest.get("name", ""))]
    elif not next_fixture.is_empty():
        quest_label.text = "%s  |  %s「%s」  |  消耗 %d  |  已通关 %d 次" % [location, selected_quest_id, quest["name"], int(quest["entry_stamina"]), clear_count]
        start_button.text = "进入 %s「%s」" % [selected_quest_id, str(quest["name"])]
        start_button.disabled = false
        replay_button.visible = false
    else:
        quest_label.text = "%s  |  下一主线：%s「%s」  |  战斗图待转换" % [location, str(current_quest_meta["id"]), str(current_quest_meta["name"])]
        start_button.text = "该战斗尚未转换"
        start_button.disabled = true
        replay_button.visible = not replay_quest.is_empty()
        replay_button.text = "重玩 %s「%s」" % [selected_quest_id, str(quest.get("name", ""))]
    party_label.text = "当前队伍：%s  |  已持有角色 %d/%d" % [
        " / ".join(profile.party.map(func(value): return str(value))),
        profile.roster.size(), catalog_repository.characters.size(),
    ]
    system_label.text = "离线目录：章节 %d / 节点 %d / 主线 %d / 角色 %d / 装备 %d / 卡池 %d（%d 个有奖池）%s" % [
        catalog_repository.chapters.size(), int(catalog_repository.counts.get("stage_nodes", 0)),
        catalog_repository.quests.size(), catalog_repository.characters.size(),
        catalog_repository.equipments.size(), catalog_repository.gacha_banners.size(), catalog_repository.gachas.size(),
        "  |  %s" % last_notice if not last_notice.is_empty() else "",
    ]
    save_repository.save(profile)

func _next_catalog_quest() -> Dictionary:
    return game_service.get_next_main_quest(
        catalog_repository.chapters,
        catalog_repository.stage_nodes,
        catalog_repository.quests,
        profile.quest_progress,
        profile.roster,
        int(Time.get_unix_time_from_system())
    )

func _quest_location_text(quest_meta: Dictionary) -> String:
    var chapter: Variant = quest_meta.get("resolved_chapter", null)
    var stage_node: Variant = quest_meta.get("resolved_stage_node", null)
    if not chapter is Dictionary or not stage_node is Dictionary:
        return "主线"
    return "%s · %s" % [str(chapter.get("name", "主线")), str(stage_node.get("name", ""))]

func _complete_story(story_quest: Dictionary) -> void:
    var staged = ProfileDataScript.from_dict(profile.to_dict())
    var result: Dictionary = game_service.complete_story(staged, story_quest, _new_persistent_id("story"))
    if result.is_empty() or save_repository.save(staged) != OK:
        last_notice = "剧情进度保存失败"
        _refresh_menu()
        return
    profile.replace_from(staged)
    menu.visible = false
    battle_hud.visible = false
    result_panel.visible = true
    result_label.text = "%s\n\n%s" % [str(result["name"]), str(result["summary"])]
    return_button.text = "继续"

func _resolve_next_quest() -> Dictionary:
    var next_meta: Dictionary = _next_catalog_quest()
    if next_meta.is_empty():
        return _latest_replay_quest()
    if str(next_meta.get("kind", "")) == "battle":
        var converted: Dictionary = content_repository.get_quest(str(next_meta.get("id", "")))
        if not converted.is_empty():
            return converted
    var replay_quest: Dictionary = _latest_replay_quest()
    if not replay_quest.is_empty():
        return replay_quest
    return content_repository.get_quest(str(BATTLE_FIXTURES[0]["id"]))

func _latest_replay_quest() -> Dictionary:
    for index in range(BATTLE_FIXTURES.size() - 1, -1, -1):
        var quest_id := str(BATTLE_FIXTURES[index]["id"])
        if not bool(profile.quest_progress.get(quest_id, {}).get("cleared", false)):
            continue
        var converted: Dictionary = content_repository.get_quest(quest_id)
        if not converted.is_empty():
            return converted
    return {}

func _cycle_party() -> void:
    var staged = ProfileDataScript.from_dict(profile.to_dict())
    var compatible: Array = []
    for character_id in staged.roster:
        if quest.get("characters", {}).has(str(character_id)): compatible.append(character_id)
    if compatible.size() < 2: return
    var start_index := compatible.find(staged.party[0]) + 1 if not staged.party.is_empty() else 0
    var selected: Array = []
    for offset in range(mini(3, compatible.size())):
        selected.append(compatible[(start_index + offset) % compatible.size()])
    if game_service.save_party(staged, selected) and save_repository.save(staged) == OK:
        profile.replace_from(staged)
        _refresh_menu()

func _upgrade_leader() -> void:
    if profile.party.is_empty(): return
    var key := str(profile.party[0])
    var staged = ProfileDataScript.from_dict(profile.to_dict())
    var progress: Dictionary = staged.character_progress.get(key, {})
    var level := int(progress.get("level", 1))
    var cost := level * 100
    if level >= 100 or int(staged.currencies.get("free_mana", 0)) < cost:
        last_notice = "队长升级失败：Mana 不足或已满级"
        _refresh_menu()
        return
    staged.currencies["free_mana"] = int(staged.currencies["free_mana"]) - cost
    progress["level"] = level + 1
    staged.character_progress[key] = progress
    if save_repository.save(staged) == OK:
        profile.replace_from(staged)
        last_notice = "队长 %s 已升至 Lv.%d" % [key, level + 1]
        _refresh_menu()
    else:
        last_notice = "队长升级保存失败，未扣除 Mana"
        _refresh_menu()

func _draw_ten() -> void:
    var staged = ProfileDataScript.from_dict(profile.to_dict())
    var result: Dictionary = game_service.draw_gacha(staged, catalog_repository.get_gacha("1"), 10, _new_persistent_id("gacha"))
    if result.is_empty():
        last_notice = "十连失败：星导石不足"
        _refresh_menu()
        return
    if save_repository.save(staged) != OK:
        last_notice = "十连保存失败"
        _refresh_menu()
        return
    profile.replace_from(staged)
    var names: Array[String] = []
    for draw in result["results"]:
        var character: Dictionary = catalog_repository.get_character(str(draw["id"]))
        names.append("%s★ %s" % [int(draw["rank"]), str(character.get("name", draw["id"]))])
    last_notice = "十连：%s" % "、".join(names)
    _refresh_menu()

func _new_persistent_id(prefix: String) -> String:
    var random_bytes := Crypto.new().generate_random_bytes(16)
    return "%s-%s" % [prefix, random_bytes.hex_encode()]
