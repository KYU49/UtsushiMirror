extends SceneTree
## 透過チェック時のスナックバー確認: 背景を白→透過にチェック→案内を撮影→ボタン押下→撮影。
## 利用者の設定を壊さないよう VRMVIEWER_CONFIG で別の設定ファイルを使って実行すること。
var _main: Node
var _f := 0
var _out := ""
func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	_out = ProjectSettings.globalize_path("res://../out/ui_screens").simplify_path()
	DirAccess.make_dir_recursive_absolute(_out)
func _process(_d: float) -> bool:
	_f += 1
	var sw = _main.settings_window
	if _f == 30:
		sw.visible = true
		_main.bg_manager.apply_background({"mode": "solid", "color": "#1e222b"})
		sw._select_tab("Window")
	if _f == 50:
		sw._win_trans_chk.button_pressed = true
	if _f == 90:
		sw.get_texture().get_image().save_png(_out.path_join("snackbar_1.png"))
		print("bg before=", _main.bg_manager.bg_color.to_html(false))
		sw._snack_btn.pressed.emit()
	if _f == 120:
		sw.get_texture().get_image().save_png(_out.path_join("snackbar_2.png"))
		print("bg after=", _main.bg_manager.bg_color.to_html(false), " transparent=", _main.bg_manager.win_transparent)
		return true
	return false
