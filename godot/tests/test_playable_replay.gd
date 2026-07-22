extends RefCounted

const StaticContentRepository = preload("res://src/content/static_content_repository.gd")
const BattleSimulation = preload("res://src/simulation/battle_simulation.gd")
const ProfileFactory = preload("res://src/domain/profile_factory.gd")
const BattlePartySnapshot = preload("res://src/domain/battle_party_snapshot.gd")

func run(t) -> void:
    var repository = StaticContentRepository.new()
    t.assert_equal(repository.load_fixture("res://content/fixtures/quest_1001002.json"), OK, "playable replay fixture loads")
    var quest := repository.get_quest("1001002")
    var snapshot := BattlePartySnapshot.build(ProfileFactory.create_default(), quest, "playable-replay")
    var battle = BattleSimulation.new(quest, "playable-replay", snapshot)
    for frame in range(36000):
        battle.set_flippers_pressed((frame % 15) < 8)
        for skill_index in range(3): battle.activate_skill(skill_index)
        battle.step()
        if battle.status != "running": break
    t.assert_equal(battle.status, "cleared", "normal flipper and skill input clears the canonical quest without teleporting the ball")
    t.assert_equal(battle.status_reason, "boss_defeated", "playable replay clears by defeating the boss")
    t.assert_true(battle.outhole_relaunch_count > 0, "fallback outhole relaunch participates in the playable loop")
