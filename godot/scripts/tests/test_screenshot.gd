extends SceneTree
## スクリーンショットの保存と、保存後の通知 (設定ウィンドウのスナックバー・メイン画面のトースト) を確認する。
## 利用者の設定を壊さないよう VRMVIEWER_CONFIG で別の設定ファイルを使って実行すること。
var _m: Node
var _f := 0
var _out := ""
func _initialize() -> void:
	_m = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_m)
	_out = ProjectSettings.globalize_path("res://../out/ui_screens").simplify_path()
	DirAccess.make_dir_recursive_absolute(_out)
func _process(_d: float) -> bool:
	_f += 1
	if _f == 30:
		_m.settings_window.visible = true
		_m.settings_window._select_tab("Output")
	if _f == 50:
		_m.take_screenshot()
	if _f == 110:
		var sw = _m.settings_window
		sw._refresh_from_controller()
		sw.get_texture().get_image().save_png(_out.path_join("screenshot_notice_settings.png"))
		get_root().get_texture().get_image().save_png(_out.path_join("screenshot_notice_main.png"))
		var p: String = _m.last_screenshot_path
		print("SHOT ", p, " label=", sw._shot_dir_lbl.text)
		print("TEST_SCREENSHOT_RESULT=", "PASS" if p != "" and FileAccess.file_exists(p) and sw._snack.visible else "FAIL")
		return true
	return false
