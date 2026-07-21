class_name BattleSessionService
extends RefCounted

const ProfileFactoryScript = preload("res://src/domain/profile_factory.gd")
const ProfileDataScript = preload("res://src/domain/profile_data.gd")
const BattleSimulationScript = preload("res://src/simulation/battle_simulation.gd")
const BattlePartySnapshotScript = preload("res://src/domain/battle_party_snapshot.gd")

var save_repository
var profile_service
var content_repository

func _init(save_store, local_profiles, static_content) -> void:
    save_repository = save_store
    profile_service = local_profiles
    content_repository = static_content

func load_or_create_profile() -> ProfileData:
    var profile = save_repository.load_profile()
    if profile != null:
        return profile
    if save_repository.has_primary_save():
        return null
    profile = ProfileFactoryScript.create_default()
    if save_repository.save(profile) != OK:
        return null
    return profile

func start_battle(profile: ProfileData, quest_id: String, run_id: String):
    if run_id.is_empty() or not profile.active_run.is_empty():
        return null
    if profile.applied_result_ids.has(_result_id_for_run(run_id)):
        return null
    var quest: Dictionary = content_repository.get_quest(quest_id)
    if quest.is_empty() or not _party_is_valid(profile):
        return null
    var party_snapshot := BattlePartySnapshotScript.build(profile, quest, run_id)
    if party_snapshot.is_empty():
        return null
    var battle = BattleSimulationScript.new(quest, run_id, party_snapshot)
    if battle.status != "running":
        return null

    var staged := ProfileDataScript.from_dict(profile.to_dict())
    staged.active_run = {
        "run_id": run_id,
        "quest_id": quest_id,
        "party": staged.party.duplicate(),
        "party_snapshot": party_snapshot.duplicate(true),
    }
    if save_repository.save(staged) != OK:
        return null
    profile.replace_from(staged)
    return battle

func finish_battle(profile: ProfileData, battle, result_id: String) -> bool:
    if profile.active_run.is_empty():
        return false
    var active_run_id := str(profile.active_run.get("run_id", ""))
    if result_id != _result_id_for_run(active_run_id):
        return false
    var result: Dictionary = battle.build_result(result_id)
    if result.is_empty():
        return false
    if str(profile.active_run.get("quest_id", "")) != str(result["quest_id"]):
        return false
    if str(profile.active_run.get("run_id", "")) != str(result["run_id"]):
        return false

    var staged := ProfileDataScript.from_dict(profile.to_dict())
    if not profile_service.apply_clear_result(
        staged,
        str(result["result_id"]),
        str(result["quest_id"]),
        result["rewards"]
    ):
        return false
    if save_repository.save(staged) != OK:
        return false
    profile.replace_from(staged)
    return true

func abort_battle(profile: ProfileData) -> bool:
    if profile.active_run.is_empty():
        return false
    var staged := ProfileDataScript.from_dict(profile.to_dict())
    staged.active_run = {}
    if save_repository.save(staged) != OK:
        return false
    profile.replace_from(staged)
    return true

func _party_is_valid(profile: ProfileData) -> bool:
    if profile.party.is_empty() or profile.party.size() > 3:
        return false
    for character_id in profile.party:
        if not profile.roster.has(character_id):
            return false
    return true

func _result_id_for_run(run_id: String) -> String:
    return "result-%s" % run_id
