extends RefCounted

const StaticContentRepository = preload("res://src/content/static_content_repository.gd")

func run(t) -> void:
    var repository = StaticContentRepository.new()
    t.assert_equal(repository.load_fixture("res://content/fixtures/quest_1001002.json"), OK, "CN fixture loads")
    t.assert_equal(repository.load_fixture("res://content/fixtures/quest_1002001.json"), OK, "second CN fixture loads")
    t.assert_equal(repository.load_fixture("res://content/fixtures/quest_1002002.json"), OK, "third CN fixture loads")
    var quest: Dictionary = repository.get_quest("1001002")
    var second_quest: Dictionary = repository.get_quest("1002001")
    var third_quest: Dictionary = repository.get_quest("1002002")
    t.assert_equal(third_quest["name"], "追蘑菇2", "third fixture keeps the canonical CN quest name")
    t.assert_equal(third_quest["zones"][0]["objective"], {"kind": "zako_kill", "count": 22}, "third fixture keeps the twenty-two-zako objective")
    t.assert_equal(third_quest["zones"][0]["zako_emitters"], second_quest["zones"][0]["zako_emitters"], "third fixture reuses the checked dual-emitter graph")
    t.assert_equal(third_quest["zones"][1]["bosses"], [{"enemy_id": "slango", "kind": "general_boss"}], "third fixture returns to the Slango boss")
    t.assert_equal(third_quest["enemies"]["slango_boss"]["max_hp"], 12196, "third fixture applies its canonical boss HP correction")
    t.assert_equal(third_quest["enemies"]["slango_boss"]["action_state_machine"]["states"]["skill1_charge1"]["termination"]["value"], 210, "third fixture keeps the Slango skill charge")
    t.assert_equal(second_quest["name"], "追蘑菇1", "second fixture keeps the canonical CN quest name")
    t.assert_equal(second_quest["zones"][0]["objective"], {"kind": "zako_kill", "count": 20}, "second fixture keeps the twenty-zako objective")
    t.assert_equal(second_quest["zones"][0]["zako_emitters"].size(), 2, "second fixture retains both original emitters")
    t.assert_equal(second_quest["zones"][0]["zako_emitters"][1], {"enemy_id": "spirit", "interval_frames": 120}, "second emitter keeps Spirit and its canonical interval")
    t.assert_equal(second_quest["enemies"]["spirit_boss"]["action_state_machine"]["states"].size(), 31, "Spirit boss keeps its complete state cycle")
    t.assert_equal(second_quest["enemies"]["spirit_boss"]["action_state_machine"]["states"]["skill1_charge1"]["termination"]["value"], 240, "Spirit time variable resolves from the canonical level threshold")
    t.assert_equal(quest["schema_version"], 2, "fixture schema records canonical battle graph")
    t.assert_equal(quest["name"], "开始的草原", "CN quest name is canonical")
    t.assert_equal(quest["entry_stamina"], 6, "CN quest stamina is canonical")
    t.assert_equal(quest["rewards"]["free_mana"], 20, "CN mana reward is canonical")
    t.assert_equal(quest["character_exp"], 13, "CN character exp is canonical")
    t.assert_equal(quest["battle"]["field_data_id"], "tutorial_main_1_1_2", "quest field data id is canonical")
    t.assert_equal(quest["battle"]["field_id"], "tree_grass01_1_2", "quest field id is canonical")
    t.assert_equal(quest["battle"]["terrain_hashed_path"], "a8/4b9b6f30c442623dcaf76685fab0cb79e2a58f", "terrain hash follows original client mapping")
    t.assert_true(not quest["battle"]["terrain_present_in_apk_bundle"], "fixture records missing downloaded terrain explicitly")
    t.assert_equal(quest["zones"].size(), 2, "original quest contains two zones")
    t.assert_equal(quest["zones"][0]["objective"], {"kind": "zako_kill", "count": 18}, "first zone objective is canonical")
    t.assert_equal(quest["zones"][0]["zako_emitters"][0]["enemy_id"], "slango", "first zone enemy is canonical")
    t.assert_equal(quest["zones"][1]["bosses"][0], {"enemy_id": "slango", "kind": "general_boss"}, "second zone boss is canonical")
    t.assert_equal(quest["enemies"]["slango_zako"]["max_hp"], 148, "zako HP is calculated from original curves")
    t.assert_equal(quest["enemies"]["slango_boss"]["max_hp"], 13009, "boss HP is calculated from original curves")
    t.assert_equal(quest["enemies"]["slango_zako"]["atk"], 19, "zako ATK is calculated from original curves")
    t.assert_equal(quest["enemies"]["slango_boss"]["atk"], 30, "boss ATK is calculated from original curves")
    t.assert_equal(quest["enemies"]["slango_funnel"]["max_hp"], 132, "level-15 funnel HP is calculated from original curves")
    t.assert_equal(quest["enemies"]["slango_funnel"]["atk"], 23, "level-15 funnel ATK is calculated from original curves")
    t.assert_equal(quest["terrain_runtime"]["status"], "fallback", "terrain adapter is explicitly marked as fallback")
    t.assert_equal(quest["terrain_runtime"]["markers"].keys().size(), 3, "terrain adapter exposes three boss movement markers")
    t.assert_equal(quest["equipments"]["1010001"]["name"], "老旧短剑", "fixture contains checked starter weapon")
    t.assert_equal(quest["equipments"]["1010001"]["status_curve"]["5"]["atk"], 26, "weapon status curve preserves max-level ATK")
    t.assert_equal(quest["equipments"]["100001"]["kind"], "orb", "fixture distinguishes ability soul orb from weapon")
    t.assert_equal(quest["equipments"]["100001"]["ability_soul"][0]["content_kind"], "FixedHeal", "orb ability content is decoded")
    t.assert_equal(quest["equipments"]["1010001"]["ability_soul"][0]["content_kind"], "ResistanceWhite", "weapon ability content is decoded")
    t.assert_equal(quest["enemy"]["id"], "slango", "simulation slice uses a canonical enemy")
    t.assert_equal(quest["enemy"]["max_hp"], 148, "simulation enemy HP uses canonical calculation")
    t.assert_equal(quest["action_assets"].size(), 4, "fixture records the exact action DSL subset")
    t.assert_equal(quest["characters"]["141005"]["name"], "西微", "fixture records the predefined CN leader")
    t.assert_equal(quest["characters"]["141005"]["atk"], 11, "fixture records canonical level-one attack")
    t.assert_equal(quest["characters"]["141005"]["status_curve"]["80"], {"hp": 3108.0, "atk": 642.0}, "fixture records canonical level-80 status key")
    t.assert_equal(quest["characters"]["141005"]["evolution_bonus"]["hp_1"], 300, "fixture records rarity-five evolution HP bonus")
    t.assert_equal(quest["characters"]["141005"]["exp_curve"]["80"], 125223, "fixture records canonical cumulative level EXP")
    t.assert_equal(quest["characters"]["141005"]["mana_boards"]["1"].size(), 23, "fixture records complete first mana board")
    t.assert_equal(quest["characters"]["141005"]["mana_boards"]["1"][0]["required_mana"], 60, "root mana node preserves canonical mana cost")
    t.assert_equal(quest["characters"]["141005"]["mana_boards"]["1"][0]["required_items"], {"13": 3.0}, "root mana node preserves material cost")
    t.assert_equal(quest["characters"]["141005"]["skill"]["name"], "精灵风暴", "fixture records canonical leader skill")
    t.assert_equal(quest["characters"]["141005"]["skill"]["max_skill_point"], 530, "leader skill gauge comes from CN master")
    t.assert_equal(quest["characters"]["131004"]["skill"]["runtime"]["max_hits"], 5, "skill runtime preserves canonical max hits")
    t.assert_equal(quest["characters"]["121002"]["skill"]["runtime"]["delay_frames"], 3, "onmyoji skill preserves canonical wait delay")
    t.assert_equal(quest["characters"]["131004"]["skill"]["runtime"]["delay_frames"], 80, "archer skill preserves nested 60+20 wait delay")
    t.assert_equal(quest["characters"]["141005"]["skill"]["runtime"]["conditions"][0]["kind"], "flying", "leader skill preserves flying condition")
    t.assert_equal(quest["characters"]["121002"]["skill"]["runtime"]["conditions"].size(), 2, "onmyoji skill preserves poison and attack-up conditions")
    t.assert_equal(quest["characters"]["131004"]["abilities"][0]["content_kind"], "DirectDamage", "thunder archer ability content is decoded")
    t.assert_equal(quest["characters"]["131004"]["abilities"][0]["power1"], 0.1, "ability decimal scaling is preserved")
    t.assert_equal(quest["characters"]["141005"]["abilities"][2]["trigger_kind"], "DamageCount", "ability trigger code is decoded")
    t.assert_equal(int(quest["battle_source_defaults"]["power_flip_combo_thresholds"][0]), 9, "power flip level-one threshold is explicit")
    t.assert_equal(int(quest["battle_source_defaults"]["power_flip_combo_thresholds"][2]), 39, "power flip level-three threshold is explicit")
    t.assert_equal(quest["battle_source_defaults"]["default_party"], ["141005", "121002", "131004"], "fixture binds the predefined party")
    t.assert_true(quest["source"]["files"].size() >= 18, "fixture records source evidence")

    var missing_marker := quest.duplicate(true)
    missing_marker["terrain_runtime"]["markers"].erase("p2")
    _assert_invalid_fixture(t, "missing-marker", missing_marker, "missing required terrain marker is rejected")

    var malformed_segment := quest.duplicate(true)
    malformed_segment["terrain_runtime"]["segments"][0]["end"] = [1.0]
    _assert_invalid_fixture(t, "malformed-segment", malformed_segment, "malformed terrain segment is rejected")

    var malformed_status_curve := quest.duplicate(true)
    malformed_status_curve["characters"]["141005"]["status_curve"]["80"]["hp"] = 0
    _assert_invalid_fixture(t, "malformed-status-curve", malformed_status_curve, "non-positive status curve value is rejected")

    var malformed_skill := quest.duplicate(true)
    malformed_skill["characters"]["141005"]["skill"]["runtime"]["max_hits"] = 0
    _assert_invalid_fixture(t, "malformed-skill", malformed_skill, "malformed player skill runtime is rejected")

    var missing_character := quest.duplicate(true)
    missing_character["characters"].erase("141005")
    _assert_invalid_fixture(t, "missing-character", missing_character, "missing default party character is rejected")

    var malformed_character := quest.duplicate(true)
    malformed_character["characters"]["141005"]["atk"] = 0
    _assert_invalid_fixture(t, "malformed-character", malformed_character, "non-positive character attack is rejected")

    var missing_enemy := quest.duplicate(true)
    missing_enemy["zones"][0]["zako_emitters"][0]["enemy_id"] = "missing_enemy"
    _assert_invalid_fixture(t, "missing-enemy", missing_enemy, "missing enemy reference is rejected")

    var missing_zone_field := quest.duplicate(true)
    missing_zone_field["zones"][0].erase("actions")
    _assert_invalid_fixture(t, "missing-zone-actions", missing_zone_field, "missing zone field is rejected without a runtime error")

    var broken_state_reference := quest.duplicate(true)
    broken_state_reference["enemies"]["slango_boss"]["action_state_machine"]["states"]["neutral1"]["next_state"] = "missing_state"
    _assert_invalid_fixture(t, "broken-state-reference", broken_state_reference, "missing enemy state reference is rejected")

    var malformed_action_runtime := quest.duplicate(true)
    malformed_action_runtime["action_assets"][0]["runtime"] = []
    _assert_invalid_fixture(t, "malformed-action-runtime", malformed_action_runtime, "empty normalized action runtime is rejected")

    var missing_action := quest.duplicate(true)
    missing_action["enemies"]["slango_zako"]["action_assets"][0] = "missing_action"
    _assert_invalid_fixture(t, "missing-action", missing_action, "missing action reference is rejected")

    var missing_funnel_target := quest.duplicate(true)
    for action in missing_funnel_target["action_assets"]:
        for runtime in action["runtime"]:
            if str(runtime.get("kind", "")) == "spawn_funnel":
                runtime["enemy_id"] = "missing_funnel"
    _assert_invalid_fixture(t, "missing-funnel-target", missing_funnel_target, "spawn-funnel runtime must resolve to a funnel definition")

    var unsupported_objective := quest.duplicate(true)
    unsupported_objective["zones"][0]["objective"] = {"kind": "unknown"}
    _assert_invalid_fixture(t, "unsupported-objective", unsupported_objective, "unsupported objective is rejected before simulation")

    var out_of_order_zone := quest.duplicate(true)
    out_of_order_zone["zones"][0]["id"] = 1
    _assert_invalid_fixture(t, "zone-order", out_of_order_zone, "zone array order must match canonical ids")

func _assert_invalid_fixture(t, suffix: String, fixture: Dictionary, message: String) -> void:
    var invalid_path := "user://tests/invalid-fixture-%s.json" % suffix
    var invalid_absolute := ProjectSettings.globalize_path(invalid_path)
    DirAccess.make_dir_recursive_absolute(invalid_absolute.get_base_dir())
    if FileAccess.file_exists(invalid_path):
        DirAccess.remove_absolute(invalid_absolute)
    var invalid_file := FileAccess.open(invalid_path, FileAccess.WRITE)
    t.assert_true(invalid_file != null, "%s test file opens" % suffix)
    if invalid_file == null:
        return
    invalid_file.store_string(JSON.stringify(fixture))
    invalid_file.close()
    var invalid_repository = StaticContentRepository.new()
    t.assert_equal(invalid_repository.load_fixture(invalid_path), ERR_INVALID_DATA, message)
