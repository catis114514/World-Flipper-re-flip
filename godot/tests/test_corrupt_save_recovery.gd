extends RefCounted

const SaveRepository = preload("res://src/persistence/save_repository.gd")
const LocalProfileService = preload("res://src/domain/local_profile_service.gd")
const StaticContentRepository = preload("res://src/content/static_content_repository.gd")
const BattleSessionService = preload("res://src/domain/battle_session_service.gd")

func run(t) -> void:
    var save_path := "user://tests/corrupt-profile.json"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
    var corrupt_text := "{ definitely-not-valid-json"
    var file := FileAccess.open(save_path, FileAccess.WRITE)
    file.store_string(corrupt_text)
    file.close()

    var repository = SaveRepository.new(save_path)
    var content = StaticContentRepository.new()
    content.load_fixture("res://content/fixtures/quest_1001002.json")
    var session = BattleSessionService.new(repository, LocalProfileService.new(), content)
    t.assert_true(session.load_or_create_profile() == null, "corrupt primary save is not silently replaced")
    var preserved := FileAccess.open(save_path, FileAccess.READ)
    t.assert_equal(preserved.get_as_text(), corrupt_text, "corrupt primary save remains available for recovery")
    preserved.close()
