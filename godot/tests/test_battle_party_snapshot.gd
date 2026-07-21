extends RefCounted

const ProfileFactory = preload("res://src/domain/profile_factory.gd")
const BattlePartySnapshot = preload("res://src/domain/battle_party_snapshot.gd")
const StaticContentRepository = preload("res://src/content/static_content_repository.gd")

func run(t) -> void:
    var repository = StaticContentRepository.new()
    t.assert_equal(repository.load_fixture("res://content/fixtures/quest_1001002.json"), OK, "party snapshot fixture loads")
    var quest: Dictionary = repository.get_quest("1001002")
    var profile = ProfileFactory.create_default()
    var snapshot := BattlePartySnapshot.build(profile, quest, "run-party-snapshot")

    t.assert_equal(snapshot["id"], "run-party-snapshot", "battle source id is the run id")
    t.assert_equal(snapshot["leader_character_id"], "141005", "first selected slot is the leader")
    t.assert_equal(snapshot["members"].size(), 3, "all selected main slots are snapshotted")
    t.assert_equal(snapshot["members"][0]["name"], "西微", "CN character data is included")
    t.assert_equal(snapshot["members"][0]["hp"], 99, "level-one leader HP includes checked weapon")
    t.assert_equal(snapshot["members"][0]["atk"], 29, "level-one leader attack includes checked weapon")
    t.assert_equal(snapshot["members"][0]["skill"]["action_id"], "battle/action/skill/action/rare5/bigwing_shaman$bigwing_shaman_1", "party snapshot owns the leader skill contract")
    t.assert_true(snapshot["members"][0]["active_abilities"].size() >= 3, "party snapshot owns profile-unlocked ability rows")
    t.assert_equal(snapshot["members"][0]["equipment"]["weapon"]["name"], "老旧短剑", "party snapshot resolves checked weapon")
    t.assert_true(snapshot["members"][0]["active_abilities"].any(func(value): return str(value.get("origin", "")) == "soul"), "party snapshot activates equipped soul ability")
    t.assert_equal(snapshot["total_hp"], 209, "party HP totals include weapon stats")
    t.assert_equal(snapshot["total_atk"], 48, "party attack totals include weapon stats")
    t.assert_equal(snapshot["direct_attack_reference_atk"], 30, "fixture damage reference matches default party")
    t.assert_equal(snapshot["battle_behavior_data"], {"skill_ability_behavior_mode": 1, "dash_behavior_mode": 1}, "single battle behavior defaults match original")

    var leveled_profile = ProfileFactory.create_default()
    leveled_profile.character_progress["141005"]["level"] = 10
    leveled_profile.character_progress["141005"]["evolution"] = 1
    var leveled_snapshot := BattlePartySnapshot.build(leveled_profile, quest, "run-leveled-snapshot")
    t.assert_equal(leveled_snapshot["members"][0]["hp"], 865, "level-10 evolved leader includes weapon HP")
    t.assert_equal(leveled_snapshot["members"][0]["atk"], 185, "level-10 evolved leader includes weapon ATK")
    t.assert_equal(leveled_snapshot["total_hp"], 975, "party total consumes calculated member and weapon HP")
    t.assert_equal(leveled_snapshot["total_atk"], 204, "party total consumes calculated member and weapon ATK")

    var equipped_profile = ProfileFactory.create_default()
    equipped_profile.equipment_inventory["1010001"]["level"] = 3
    var equipped_snapshot := BattlePartySnapshot.build(equipped_profile, quest, "run-equipment-level")
    t.assert_equal(equipped_snapshot["members"][0]["equipment"]["weapon"]["hp"], 59, "weapon HP uses original ceil interpolation")
    t.assert_equal(equipped_snapshot["members"][0]["equipment"]["weapon"]["atk"], 22, "weapon ATK uses original ceil interpolation")
    t.assert_equal(equipped_snapshot["total_hp"], 221, "party total includes interpolated weapon HP")
    t.assert_equal(equipped_snapshot["total_atk"], 52, "party total includes interpolated weapon ATK")

    profile.character_progress["141005"]["ability_levels"]["1410053"] = 0
    t.assert_equal(snapshot["members"][0]["active_abilities"][0]["ability_id"], "1410051", "running snapshot is immutable after ability progression edits")
    profile.party[0] = 999999
    t.assert_equal(snapshot["leader_character_id"], "141005", "snapshot is immutable after party edits")
    t.assert_equal(BattlePartySnapshot.build(profile, quest, "run-missing-character"), {}, "unknown selected character rejects snapshot")
