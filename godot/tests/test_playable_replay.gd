extends RefCounted

const StaticContentRepository = preload("res://src/content/static_content_repository.gd")
const BattleSimulation = preload("res://src/simulation/battle_simulation.gd")
const ProfileFactory = preload("res://src/domain/profile_factory.gd")
const BattlePartySnapshot = preload("res://src/domain/battle_party_snapshot.gd")

func run(t) -> void:
    var repository = StaticContentRepository.new()
    t.assert_equal(repository.load_fixture("res://content/fixtures/quest_1001002.json"), OK, "playable replay fixture loads")
    var quest := repository.get_quest("1001002")
    var battle = _drive_replay(quest, "playable-replay")
    t.assert_equal(battle.status, "cleared", "normal flipper and skill input clears the canonical quest without teleporting the ball")
    t.assert_equal(battle.status_reason, "boss_defeated", "playable replay clears by defeating the boss")
    t.assert_true(battle.outhole_relaunch_count > 0, "fallback outhole relaunch participates in the playable loop")

    t.assert_equal(repository.load_fixture("res://content/fixtures/quest_1002001.json"), OK, "second playable replay fixture loads")
    var second_quest := repository.get_quest("1002001")
    var second_battle = _drive_replay(second_quest, "playable-replay-second")
    t.assert_equal(second_battle.status, "cleared", "normal input clears the multi-emitter Spirit quest")
    t.assert_equal(second_battle.status_reason, "boss_defeated", "second playable replay clears by defeating Spirit")
    t.assert_true(second_battle.enemy_spawn_serial > 20, "second replay exercises both emitters and respawns")

    t.assert_equal(repository.load_fixture("res://content/fixtures/quest_1002002.json"), OK, "third playable replay fixture loads")
    var third_quest := repository.get_quest("1002002")
    var third_battle = _drive_replay(third_quest, "playable-replay-third")
    t.assert_equal(third_battle.status, "cleared", "normal input clears the twenty-two-enemy Slango quest")
    t.assert_equal(third_battle.status_reason, "boss_defeated", "third playable replay clears by defeating Slango")
    t.assert_true(third_battle.enemy_spawn_serial > 22, "third replay exercises both emitters, respawns, and the boss")

    t.assert_equal(repository.load_fixture("res://content/fixtures/quest_1003002.json"), OK, "fourth playable replay fixture loads")
    var fourth_quest := repository.get_quest("1003002")
    var fourth_battle = _drive_replay(fourth_quest, "playable-replay-fourth")
    t.assert_equal(fourth_battle.status, "cleared", "normal input clears the three-emitter Fox quest")
    t.assert_equal(fourth_battle.status_reason, "boss_defeated", "fourth playable replay clears by defeating Fox")
    t.assert_true(fourth_battle.enemy_spawn_serial > 20, "fourth replay exercises three emitters, respawns, and the boss")

func _drive_replay(quest: Dictionary, run_id: String):
    var snapshot := BattlePartySnapshot.build(ProfileFactory.create_default(), quest, run_id)
    var battle = BattleSimulation.new(quest, run_id, snapshot)
    for frame in range(36000):
        battle.set_flippers_pressed((frame % 15) < 8)
        for skill_index in range(3):
            battle.activate_skill(skill_index)
        battle.step()
        if battle.status != "running":
            break
    return battle
