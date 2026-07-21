extends RefCounted

const ProfileFactory = preload("res://src/domain/profile_factory.gd")

func run(t) -> void:
    var profile = ProfileFactory.create_default()
    t.assert_equal(profile.schema_version, 5, "default profile schema")
    t.assert_equal(profile.profile_id, "local-1", "default profile id")
    t.assert_equal(profile.party.size(), 3, "default party has three main slots")
    t.assert_true(profile.roster.size() >= 3, "default roster can populate the party")
    t.assert_equal(profile.quest_progress, {}, "new profile starts without fabricated clears")
    t.assert_equal(profile.character_progress["141005"]["level"], 1, "default character progress owns level")
    t.assert_equal(profile.character_progress["141005"]["evolution"], 0, "default character starts unevolved")
    t.assert_equal(profile.character_progress["141005"]["limit_break"], 0, "default character starts without limit breaks")
    t.assert_equal(profile.character_progress["141005"]["learned_mana_nodes"], [], "default board progress is explicit")
    t.assert_equal(profile.character_progress["141005"]["action_skill_level"], 1, "default action skill level is explicit")
    t.assert_equal(profile.character_progress["141005"]["ability_levels"]["1410053"], 1, "default profile owns unlocked ability levels")
    t.assert_equal(profile.character_progress["141005"]["equipment"], {"weapon_id": "1010001", "soul_id": "100001"}, "default leader owns checked equipment slots")
    t.assert_equal(profile.character_progress["121002"]["equipment"], {"weapon_id": "", "soul_id": ""}, "other default members start unequipped")
