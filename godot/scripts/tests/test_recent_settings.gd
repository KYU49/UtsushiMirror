extends SceneTree
## 下の段の「最近の設定」ドロップダウンを確かめる。
## 実行: VRMVIEWER_CONFIG=<一時ファイル> TEST_OUT_DIR=<一時フォルダ> godot --path godot -s res://scripts/tests/test_recent_settings.gd
var _m: Node
var _f := 0
var _ok := true


func _check(name: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + name)
	_ok = _ok and cond


func _initialize() -> void:
	_m = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_m)


func _process(_d: float) -> bool:
	_f += 1
	if _f == 20:
		var dir := OS.get_environment("TEST_OUT_DIR")
		var sw = _m.settings_window
		var a := dir.path_join("a.umset")
		var b := dir.path_join("b.umset")
		_m.apply_effects({"style": "anime"})
		_check("a を書き出せる", _m.export_settings(a).get("ok", false))
		_m.apply_effects({"style": "none"})
		_check("b を書き出せる", _m.export_settings(b).get("ok", false))
		var rec: Array = _m.get_recent_settings_paths()
		print("recent ", rec)
		_check("新しい順に履歴に入る", rec.size() == 2 and rec[0].get_file() == "b.umset" and rec[1].get_file() == "a.umset")
		_m.import_settings(b.replace("/", "\\"))
		_check("区切りが違っても同じファイルは 1 件", _m.get_recent_settings_paths().size() == 2)
		_m.export_settings(b)
		var txt := FileAccess.get_file_as_string(a)
		_check("書き出したファイルに履歴は入らない", not txt.contains("recent_settings_paths"))
		var cfg_txt := FileAccess.get_file_as_string(OS.get_environment("VRMVIEWER_CONFIG"))
		_check("履歴はいつもの設定ファイルに残る", cfg_txt.contains("a.umset") and cfg_txt.contains("b.umset"))
		# ドロップダウン
		sw._refresh_recent_settings()
		var ob: OptionButton = sw._recent_cfg_btn
		_check("ドロップダウンがある", ob != null and ob.is_inside_tree())
		_check("見出し + 2 件 + 区切り + 消す", ob.item_count == 5 and ob.get_item_text(1).begins_with("b") and ob.get_item_text(4) == "履歴を消す")
		# 2 番目 (a) を選ぶ
		ob.select(2)
		sw._on_recent_settings_selected(2)
		_check("選んだ設定が読み込まれる", _m.post_effects.style == "anime")
		rec = _m.get_recent_settings_paths()
		_check("読み込んだものが先頭に来る", rec[0].get_file() == "a.umset")
		_check("選んだ後は見出しに戻る", ob.selected == 0)
		# 消えたファイルは出さない
		DirAccess.remove_absolute(b)
		_check("消えたファイルは出さない", _m.get_recent_settings_paths().size() == 1)
		sw._refresh_recent_settings()
		sw._on_recent_settings_selected(ob.item_count - 1)
		_check("履歴を消せる", _m.get_recent_settings_paths().is_empty())
		_check("空のときは「まだありません」", ob.item_count == 2 and ob.is_item_disabled(1))
	if _f == 30:
		print("TEST_RECENT_RESULT=", "PASS" if _ok else "FAIL")
		return true
	return false
