class_name ConfigManager
extends RefCounted

## Persistent JSON config manager (defaults to user://vrmviewer_config.json or VRMVIEWER_CONFIG env).

const DEFAULT_PATH := "user://vrmviewer_config.json"


static func get_app_root_dir() -> String:
	if OS.has_feature("template") or not OS.has_feature("editor"):
		return OS.get_executable_path().get_base_dir()
	return ProjectSettings.globalize_path("res://../").simplify_path()


static func resolve_path(custom_path: String = "") -> String:
	if custom_path != "":
		return custom_path
	var env_path := OS.get_environment("VRMVIEWER_CONFIG")
	if env_path != "":
		return env_path
	return DEFAULT_PATH


static func save_config(data: Dictionary, custom_path: String = "") -> Dictionary:
	var path := resolve_path(custom_path)
	var dir_path := path.get_base_dir()
	if dir_path != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "Failed to open config for writing: " + path}
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return {"ok": true, "path": ProjectSettings.globalize_path(path)}


static func load_config(custom_path: String = "") -> Dictionary:
	var path := resolve_path(custom_path)
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Config not found", "path": path}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "Failed to read config: " + path}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Invalid JSON in config"}
	return {"ok": true, "config": parsed, "path": ProjectSettings.globalize_path(path)}
