extends RefCounted

const ConfigManagerScript := preload("res://scripts/core/config_manager.gd")
const UiWidgets := preload("res://scripts/ui/ui_widgets.gd")

var _loaded: bool = false
var _text_edit: TextEdit


func build(_win, vb: VBoxContainer) -> void:
	var c: Dictionary = UiWidgets.card(vb, "ライセンス・オープンソースクレジット")
	UiWidgets.note(c["body"], "本ソフトウェアが利用しているエンジン・同梱アセット・OSS ライブラリのライセンス表記です。")
	_text_edit = TextEdit.new()
	_text_edit.editable = false
	_text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text_edit.custom_minimum_size = Vector2(0, 560)
	_text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_edit.text = "（タブを開くとライセンス情報を読み込みます）"
	c["body"].add_child(_text_edit)


func ensure_loaded() -> void:
	if _loaded or _text_edit == null:
		return
	_loaded = true
	_text_edit.text = _build_license_text()


func sync(_st: Dictionary) -> void:
	ensure_loaded()


static func _build_license_text() -> String:
	var parts := PackedStringArray()
	var candidates := [
		ConfigManagerScript.get_app_root_dir().path_join("assets/licenses/THIRD_PARTY_NOTICES.txt"),
		ProjectSettings.globalize_path("res://../assets/licenses/THIRD_PARTY_NOTICES.txt"),
	]
	for p in candidates:
		if FileAccess.file_exists(p):
			parts.append(FileAccess.get_file_as_string(p).strip_edges())
			break

	parts.append("\n================================================================\n[Godot Engine License]\n")
	parts.append(Engine.get_license_text().strip_edges())

	var comps := Engine.get_copyright_info()
	if not comps.is_empty():
		parts.append("\n================================================================\n[Godot Engine Built-in Components]\n")
		for comp in comps:
			if typeof(comp) != TYPE_DICTIONARY:
				continue
			var cname := str(comp.get("name", ""))
			var p_arr: Array = comp.get("parts", [])
			var lics := PackedStringArray()
			for p in p_arr:
				if typeof(p) == TYPE_DICTIONARY and p.has("license"):
					lics.append(str(p["license"]))
			parts.append("- %s (%s)" % [cname, ", ".join(lics)])
	return "\n\n".join(parts)
