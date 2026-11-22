extends RefCounted

const UiWidgets := preload("res://scripts/ui/ui_widgets.gd")

var _win
var _sl_yaw: HSlider
var _sl_pitch: HSlider
var _sl_dist: HSlider
var _sl_fov: HSlider
var _chk_ortho: CheckBox
var _sl_tx: HSlider
var _sl_ty: HSlider
var _sl_tz: HSlider


func build(win, vb: VBoxContainer) -> void:
	_win = win
	var is_sync: Callable = win.is_syncing_fn()

	# ---- プリセット
	var c_pre: Dictionary = UiWidgets.card(vb, "カメラプリセット")
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	c_pre["body"].add_child(g)

	var presets := [
		["full_body", "全身"],
		["bust", "バストアップ"],
		["face", "顔アップ"],
		["back", "背面"],
		["left", "左側面"],
		["right", "右側面"],
		["top_down", "見下ろし"],
	]
	for item in presets:
		var pid: String = item[0]
		var plabel: String = item[1]
		var b := Button.new()
		b.text = plabel
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			if _win.controller != null:
				_win.controller.camera_rig.apply_preset(pid, _win.controller.get_model_height())
		)
		g.add_child(b)

	var b_auto := Button.new()
	b_auto.text = "自動フレーミング"
	b_auto.theme_type_variation = "AccentButton"
	b_auto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_auto.pressed.connect(func():
		if _win.controller == null:
			return
		if _win.controller.current_vrm != null:
			_win.controller.camera_rig.auto_frame(_win.controller.current_vrm.get_approx_bounds())
		else:
			_win.controller.camera_rig.apply_preset("full_body", 1.6)
	)
	g.add_child(b_auto)

	# ---- アングル・距離・画角
	var c_ang: Dictionary = UiWidgets.card(vb, "アングル・距離・画角")
	var push_cam := func():
		if _win.controller != null:
			_win.controller.camera_rig.apply_params({
				"yaw_deg": _sl_yaw.value,
				"pitch_deg": _sl_pitch.value,
				"distance": _sl_dist.value,
				"fov_deg": _sl_fov.value,
				"orthographic": _chk_ortho.button_pressed,
				"target": [_sl_tx.value, _sl_ty.value, _sl_tz.value],
			})
	_sl_yaw = UiWidgets.slider(c_ang["body"], "水平角 (Yaw °)", -180.0, 180.0, 1.0, 0.0, func(_v: float): push_cam.call(), is_sync)
	_sl_pitch = UiWidgets.slider(c_ang["body"], "仰俯角 (Pitch °)", -85.0, 85.0, 1.0, 6.0, func(_v: float): push_cam.call(), is_sync)
	_sl_dist = UiWidgets.slider(c_ang["body"], "距離 (m)", 0.25, 10.0, 0.02, 2.2, func(_v: float): push_cam.call(), is_sync)
	_sl_fov = UiWidgets.slider(c_ang["body"], "視野角 (FOV °)", 12.0, 90.0, 0.5, 35.0, func(_v: float): push_cam.call(), is_sync)
	_chk_ortho = UiWidgets.check(c_ang["body"], "平行投影 (パースなし)", false, func(_on: bool): push_cam.call(), is_sync)

	# ---- 注視点
	var c_tgt: Dictionary = UiWidgets.card(vb, "注視点 (Target)")
	_sl_tx = UiWidgets.slider(c_tgt["body"], "目標 X (m)", -2.0, 2.0, 0.01, 0.0, func(_v: float): push_cam.call(), is_sync)
	_sl_ty = UiWidgets.slider(c_tgt["body"], "目標 Y (高さ m)", 0.0, 2.5, 0.01, 0.95, func(_v: float): push_cam.call(), is_sync)
	_sl_tz = UiWidgets.slider(c_tgt["body"], "目標 Z (m)", -2.0, 2.0, 0.01, 0.0, func(_v: float): push_cam.call(), is_sync)
	UiWidgets.note(c_tgt["body"], "メイン画面操作: 左ドラッグ=回転 / Shift+左または中ドラッグ=平行移動 / ホイール=ズーム / Alt+左ドラッグ=枠なしウィンドウ移動")


func sync(st: Dictionary) -> void:
	var cam: Dictionary = st.get("camera", {})
	_sl_yaw.value = float(cam.get("yaw_deg", 0.0))
	_sl_pitch.value = float(cam.get("pitch_deg", 6.0))
	_sl_dist.value = float(cam.get("distance", 2.2))
	_sl_fov.value = float(cam.get("fov_deg", 35.0))
	_chk_ortho.button_pressed = bool(cam.get("orthographic", false))
	var tgt: Array = cam.get("target", [0.0, 0.95, 0.0])
	if tgt.size() >= 3:
		_sl_tx.value = float(tgt[0])
		_sl_ty.value = float(tgt[1])
		_sl_tz.value = float(tgt[2])
