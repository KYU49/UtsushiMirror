extends SceneTree
## 指定アニメーションを再生してメイン画面を PNG 保存する。
## 実行: VRMVIEWER_CONFIG=<一時ファイル> godot --path godot -s res://scripts/tests/test_anim_snapshot.gd -- <clip> <秒> <png>
var _m: Node
var _t := 0.0
var _clip := "idle"
var _sec := 2.0
var _out := ""
var _started := false
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	_clip = a[0]
	_sec = float(a[1])
	_out = a[2]
	_m = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_m)
func _process(d: float) -> bool:
	_t += d
	if not _started and _t > 2.0:
		_started = true
		_m.settings_window.visible = false
		if _m.current_vrm == null:
			_m.load_vrm(ProjectSettings.globalize_path("res://../assets/samples/Seed-san.vrm"))
		print("play ", _clip, " -> ", _m.play_animation_internal(_clip, true, 1.0, 0.0))
	if _started and _t > 2.0 + _sec:
		get_root().get_texture().get_image().save_png(_out)
		return true
	return false
