extends RefCounted

const ProfileFactory = preload("res://src/domain/profile_factory.gd")
const ProfileDataScript = preload("res://src/domain/profile_data.gd")

func run(t) -> void:
    var original = ProfileFactory.create_default()
    original.quest_progress = {"1001001": {"clear_count": 1}}
    original.applied_result_ids.append("result-1")
    var encoded: Dictionary = original.to_dict()
    var restored = ProfileDataScript.from_dict(encoded)
    t.assert_equal(restored.schema_version, original.schema_version, "schema survives round-trip")
    t.assert_equal(restored.profile_id, original.profile_id, "profile id survives round-trip")
    t.assert_equal(restored.roster, original.roster, "roster survives round-trip")
    t.assert_equal(restored.party, original.party, "party survives round-trip")
    t.assert_equal(restored.currencies, original.currencies, "currencies survive round-trip")
    t.assert_equal(restored.character_progress, original.character_progress, "character progression and equipment survive round-trip")
    t.assert_equal(restored.equipment_inventory, original.equipment_inventory, "equipment inventory survives round-trip")
    t.assert_equal(restored.quest_progress, original.quest_progress, "progress survives round-trip")
    t.assert_equal(restored.applied_result_ids, original.applied_result_ids, "result ids survive round-trip")
    t.assert_equal(restored.stamina_state, original.stamina_state, "stamina anchor survives round-trip")
    t.assert_equal(restored.gacha_state, original.gacha_state, "gacha RNG state survives round-trip")
    t.assert_equal(restored.operation_ledger, original.operation_ledger, "operation ledger survives round-trip")
