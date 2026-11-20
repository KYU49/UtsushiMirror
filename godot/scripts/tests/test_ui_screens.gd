extends SceneTree

## 設定ウィンドウの各ページを PNG に保存する (目視確認用)。
## 実行: godot --path godot -s res://scripts/tests/test_ui_screens.gd
## 出力: <repo>/out/ui_screens/*.png

var _frame := 0
var _main: Node
var _pages := ["Model", "Camera", "Light", "Effects", "Pose", "Anim", "Expr", "Tracking", "Window", "Output", "API/Config", "License"]
var _page_i := 0
var _out_dir := ""


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	_out_dir = ProjectSettings.globalize_path("res://../out/ui_screens").simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)


func _process(_delta: float) -> bool:
	_frame += 1
	var sw: Window = _main.get("settings_window")
	if sw == null:
		return _frame > 300
	if _frame == 30:
		sw.visible = true
	if _frame >= 60 and _frame % 15 == 0:
		if _page_i > 0:
			var img := sw.get_texture().get_image()
			var nm := str(_pages[_page_i - 1]).replace("/", "_")
			img.save_png(_out_dir.path_join("%02d_%s.png" % [_page_i, nm]))
		if _page_i >= _pages.size():
			print("UI screens saved: ", _out_dir)
			return true
		sw._select_tab(_pages[_page_i])
		_page_i += 1
	return false
