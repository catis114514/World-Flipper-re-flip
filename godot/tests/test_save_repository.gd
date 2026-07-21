extends RefCounted

const ProfileFactory = preload("res://src/domain/profile_factory.gd")
const SaveRepository = preload("res://src/persistence/save_repository.gd")

func run(t) -> void:
    var save_path := "user://tests/profile-roundtrip.json"
    var absolute_dir := ProjectSettings.globalize_path("user://tests")
    DirAccess.make_dir_recursive_absolute(absolute_dir)
    var absolute_save := ProjectSettings.globalize_path(save_path)
    if FileAccess.file_exists(save_path):
        DirAccess.remove_absolute(absolute_save)
    if FileAccess.file_exists(save_path + ".tmp"):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + ".tmp"))

    var repository = SaveRepository.new(save_path)
    var original = ProfileFactory.create_default()
    original.currencies["free_mana"] = 12345
    t.assert_equal(repository.save(original), OK, "profile save succeeds")
    var restored = repository.load_profile()
    t.assert_true(restored != null, "saved profile reloads")
    t.assert_equal(restored.profile_id, original.profile_id, "saved profile id reloads")
    t.assert_equal(restored.currencies, original.currencies, "saved currencies reload")
    t.assert_true(not FileAccess.file_exists(save_path + ".tmp"), "atomic temp file is not left behind")
