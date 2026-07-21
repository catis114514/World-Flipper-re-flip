class_name SaveRepository
extends RefCounted

const ProfileDataScript = preload("res://src/domain/profile_data.gd")
const ProfileMigratorScript = preload("res://src/persistence/profile_migrator.gd")

var save_path: String

func _init(path: String = "user://saves/profile.json") -> void:
    save_path = path

func save(profile: ProfileData) -> Error:
    var directory_error := DirAccess.make_dir_recursive_absolute(
        ProjectSettings.globalize_path(save_path.get_base_dir())
    )
    if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
        return directory_error

    var temp_path := save_path + ".tmp"
    var temp_file := FileAccess.open(temp_path, FileAccess.WRITE)
    if temp_file == null:
        return FileAccess.get_open_error()
    temp_file.store_string(JSON.stringify(profile.to_dict()))
    temp_file.flush()
    temp_file.close()

    var absolute_save := ProjectSettings.globalize_path(save_path)
    var absolute_temp := ProjectSettings.globalize_path(temp_path)
    var backup_path := save_path + ".bak"
    var absolute_backup := ProjectSettings.globalize_path(backup_path)

    if FileAccess.file_exists(backup_path):
        DirAccess.remove_absolute(absolute_backup)
    if FileAccess.file_exists(save_path):
        var backup_error := DirAccess.rename_absolute(absolute_save, absolute_backup)
        if backup_error != OK:
            return backup_error

    var replace_error := DirAccess.rename_absolute(absolute_temp, absolute_save)
    if replace_error != OK:
        if FileAccess.file_exists(backup_path):
            DirAccess.rename_absolute(absolute_backup, absolute_save)
        return replace_error

    if FileAccess.file_exists(backup_path):
        DirAccess.remove_absolute(absolute_backup)
    return OK

func has_primary_save() -> bool:
    return FileAccess.file_exists(save_path)

func load_profile() -> ProfileData:
    var profile := _load_from_path(save_path)
    if profile != null:
        return profile
    return _load_from_path(save_path + ".bak")

func _load_from_path(path: String) -> ProfileData:
    if not FileAccess.file_exists(path):
        return null
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return null
    var parser := JSON.new()
    var parse_error := parser.parse(file.get_as_text())
    file.close()
    if parse_error != OK or not parser.data is Dictionary:
        return null
    var data: Dictionary = parser.data
    var migrated: Dictionary = ProfileMigratorScript.migrate(data)
    if migrated.is_empty():
        return null
    return ProfileDataScript.from_dict(migrated)
