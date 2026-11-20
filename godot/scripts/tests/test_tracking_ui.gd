extends SceneTree
## トラッキング設定ページの確認 (実カメラを使う)。
## 開始 → 状態表示 → キャリブレーション → 顔だけモードへ切替 (再起動) → 停止 を順に行い、画面を撮る。
## 実行: VRMVIEWER_CONFIG=<一時ファイル> godot --path godot -s res://scripts/tests/test_tracking_ui.gd -- [カメラ番号]
var _m: Node
var _t := 0.0
var _step := 0
var _out := ""
var _ok := true
var _cam := "auto"


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		_cam = a[0]
	_m = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_m)
	_out = ProjectSettings.globalize_path("res://../out/ui_screens").simplify_path()
	DirAccess.make_dir_recursive_absolute(_out)


func _check(name: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + name)
	_ok = _ok and cond


func _shot(name: String, scroll_to: Control = null) -> void:
	var sw = _m.settings_window
	if scroll_to != null:
		var p: Node = scroll_to
		while p != null and not (p is ScrollContainer):
			p = p.get_parent()
		if p is ScrollContainer:
			p.scroll_vertical = int(scroll_to.get_global_rect().position.y - p.get_global_rect().position.y + p.scroll_vertical - 8)
	await process_frame
	await process_frame
	sw.get_texture().get_image().save_png(_out.path_join(name + ".png"))


func _process(d: float) -> bool:
	_t += d
	var sw = _m.settings_window
	var tm = _m.tracking
	match _step:
		0:
			if _t > 0.5:
				sw.visible = true
				sw._select_tab("Tracking")
				_m.apply_tracking_settings({"camera": _cam, "mode": "upper", "calib_delay": 0})
				tm.reset_calibration()
				sw._trk_start_btn.pressed.emit()
				_check("started", tm.is_running())
				_step = 1
				_t = 0.0
		1:
			if float(tm.status.get("fps", 0)) > 0.0 and _t > 4.0:
				print("status ", tm.status)
				_check("status received", tm.status.has("fps"))
				_step = 2
				_t = 0.0
				_shot("tracking_1_running")
			elif _t > 40.0:
				_check("status received", false)
				_step = 9
		2:
			if _t > 1.0:
				_m.apply_tracking_settings({"smooth": 0.7, "blink_link": true})
				_check("live change keeps process", tm.is_running())
				sw._trk_calib_btn.pressed.emit()
				_step = 3
				_t = 0.0
		3:
			if _t > 3.0:
				print("after calib ", tm.status)
				_check("calibration finished", float(tm.status.get("calib_countdown", 0)) < 0.0 and not bool(tm.status.get("calib_capturing", true)))
				_shot("tracking_2_calib", sw._trk_calib_btn)
				_step = 4
				_t = 0.0
		4:
			if _t > 1.0:
				_shot("tracking_3_eyes", sw._trk_sec["eyes"])
				_step = 5
				_t = 0.0
		5:
			if _t > 1.0:
				_shot("tracking_4_hands", sw._trk_sec["hands"])
				_m.apply_tracking_settings({"mode": "face"})
				_check("restart on mode change", tm.is_running() and str(tm.settings.mode) == "face")
				_check("hands section hidden in face mode", not sw._trk_sec["hands"].get_parent().get_parent().visible)
				_step = 6
				_t = 0.0
		6:
			if not tm.status.is_empty() and str(tm.status.get("mode", "")) == "face" and _t > 2.0:
				_check("face mode running", true)
				_shot("tracking_5_facemode", sw._trk_mode_btns["face"])
				_step = 9
			elif _t > 40.0:
				_check("face mode running", false)
				_step = 9
		9:
			_m.stop_tracking()
			_check("stopped", not tm.is_running())
			print("TEST_TRACKING_UI_RESULT=", "PASS" if _ok else "FAIL")
			return true
	return false
