extends RefCounted

const ConfigManagerScript := preload("res://scripts/core/config_manager.gd")
const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const UiWidgets := preload("res://scripts/ui/ui_widgets.gd")

var _win
var _lbl_path: Label
var _lbl_meta: Label
var _chk_first_person: CheckBox
var _recent_box: VBoxContainer
var _last_recent_key: String = "__init__"

var _sl_pos_x: HSlider
var _sl_pos_y: HSlider
var _sl_pos_z: HSlider
var _sl_rot_y: HSlider
var _sl_scale: HSlider

var _chk_sb_en: CheckBox
var _sl_sb_grav: HSlider
var _sl_sb_stiff: HSlider
var _sl_wind_x: HSlider
var _sl_wind_y: HSlider
var _sl_wind_z: HSlider


func build(win, vb: VBoxContainer) -> void:
	_win = win
	var is_sync: Callable = win.is_syncing_fn()

	# ---- VRM モデル
	var c_mod: Dictionary = UiWidgets.card(vb, "VRM モデル")
	var row_act := HBoxContainer.new()
	row_act.add_theme_constant_override("separation", 8)
	c_mod["body"].add_child(row_act)

	var b_open := Button.new()
	b_open.text = "VRM を開く..."
	b_open.theme_type_variation = "AccentButton"
	b_open.pressed.connect(func():
		if _win.controller != null:
			_win.controller.open_vrm_file_dialog()
	)
	row_act.add_child(b_open)

	var b_sample := Button.new()
	b_sample.text = "サンプル読込 (Seed-san)"
	b_sample.pressed.connect(func():
		if _win.controller != null:
			_win.controller.load_vrm(ConfigManagerScript.get_app_root_dir().path_join("assets/samples/Seed-san.vrm"))
	)
	row_act.add_child(b_sample)

	var b_unload := Button.new()
	b_unload.text = "モデルを外す"
	b_unload.theme_type_variation = "DangerButton"
	b_unload.pressed.connect(func():
		if _win.controller == null or _win.controller.current_vrm == null:
			return
		_win.confirm(
			"モデルを外す",
			"現在表示中の VRM モデルを外しますか？\n（いつでも右クリックやこの画面から読み直せます）",
			"モデルを外す",
			func():
				if _win.controller != null:
					_win.controller.unload_vrm()
		)
	)
	row_act.add_child(b_unload)

	_lbl_path = Label.new()
	_lbl_path.theme_type_variation = "DimLabel"
	_lbl_path.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_path.text = "未読み込み — メインウィンドウに .vrm ファイルをドラッグ＆ドロップできます"
	c_mod["body"].add_child(_lbl_path)

	_lbl_meta = Label.new()
	_lbl_meta.theme_type_variation = "MutedLabel"
	_lbl_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c_mod["body"].add_child(_lbl_meta)

	_chk_first_person = UiWidgets.check(c_mod["body"], "一人称メッシュ表示 (頭パーツ非表示)", false, func(on: bool):
		if _win.controller != null:
			_win.controller.set_first_person_mode(on),
		is_sync
	)

	# ---- 最近使った VRM
	var c_rec: Dictionary = UiWidgets.card(vb, "最近使った VRM")
	_recent_box = VBoxContainer.new()
	_recent_box.add_theme_constant_override("separation", 4)
	c_rec["body"].add_child(_recent_box)

	# ---- 配置・スケール
	var c_xf: Dictionary = UiWidgets.card(vb, "配置・スケール (モデルルート)")
	var apply_xf := func(_v: float):
		if _win.controller != null:
			_win.controller.set_model_transform({
				"position": [_sl_pos_x.value, _sl_pos_y.value, _sl_pos_z.value],
				"rotation_y_deg": _sl_rot_y.value,
				"scale": _sl_scale.value,
			})
	_sl_pos_x = UiWidgets.slider(c_xf["body"], "X 位置 (m)", -3.0, 3.0, 0.01, 0.0, apply_xf, is_sync)
	_sl_pos_y = UiWidgets.slider(c_xf["body"], "Y 位置 (m)", -2.0, 2.0, 0.01, 0.0, apply_xf, is_sync)
	_sl_pos_z = UiWidgets.slider(c_xf["body"], "Z 位置 (m)", -3.0, 3.0, 0.01, 0.0, apply_xf, is_sync)
	_sl_rot_y = UiWidgets.slider(c_xf["body"], "Y 回転 (°)", -180.0, 180.0, 1.0, 0.0, apply_xf, is_sync)
	_sl_scale = UiWidgets.slider(c_xf["body"], "スケール", 0.1, 3.0, 0.01, 1.0, apply_xf, is_sync)

	var b_reset_xf := Button.new()
	b_reset_xf.text = "配置をリセット"
	b_reset_xf.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b_reset_xf.pressed.connect(func():
		if _win.controller != null:
			_win.controller.reset_model_transform()
	)
	c_xf["body"].add_child(b_reset_xf)

	# ---- 揺れもの・風
	var c_sb: Dictionary = UiWidgets.card(vb, "揺れもの (SpringBone) と風")
	var apply_sb := func():
		if _win.controller != null:
			_win.controller.set_spring_bone_params({
				"enabled": _chk_sb_en.button_pressed,
				"gravity_scale": _sl_sb_grav.value,
				"stiffness_scale": _sl_sb_stiff.value,
				"wind": [_sl_wind_x.value, _sl_wind_y.value, _sl_wind_z.value],
			})
	_chk_sb_en = UiWidgets.check(c_sb["body"], "SpringBone 有効", true, func(_on: bool): apply_sb.call(), is_sync)
	_sl_sb_grav = UiWidgets.slider(c_sb["body"], "重力の倍率", 0.0, 3.0, 0.05, 1.0, func(_v: float): apply_sb.call(), is_sync)
	_sl_sb_stiff = UiWidgets.slider(c_sb["body"], "硬さ・張り具合", 0.0, 3.0, 0.05, 1.0, func(_v: float): apply_sb.call(), is_sync)
	_sl_wind_x = UiWidgets.slider(c_sb["body"], "風 X (横 m/s)", -5.0, 5.0, 0.1, 0.0, func(_v: float): apply_sb.call(), is_sync)
	_sl_wind_y = UiWidgets.slider(c_sb["body"], "風 Y (上下 m/s)", -5.0, 5.0, 0.1, 0.0, func(_v: float): apply_sb.call(), is_sync)
	_sl_wind_z = UiWidgets.slider(c_sb["body"], "風 Z (前後 m/s)", -5.0, 5.0, 0.1, 0.0, func(_v: float): apply_sb.call(), is_sync)

	var b_calm := Button.new()
	b_calm.text = "風を止める"
	b_calm.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b_calm.pressed.connect(func():
		if _win.controller != null:
			_win.controller.set_spring_bone_params({"wind": [0.0, 0.0, 0.0]})
	)
	c_sb["body"].add_child(b_calm)


func sync(st: Dictionary) -> void:
	var loaded := bool(st.get("model_loaded", false))
	var mpath := str(st.get("model_path", ""))
	var mname := str(st.get("model_name", ""))
	if loaded:
		_lbl_path.text = (mname + "  —  " if mname != "" else "") + mpath
		var meta_parts := PackedStringArray()
		if _win.controller != null and _win.controller.current_vrm != null:
			var vrm = _win.controller.current_vrm
			meta_parts.append("VRM " + str(vrm.vrm_version))
			if vrm.first_person != null:
				var meta: Dictionary = vrm.first_person.meta
				var auth = meta.get("authors", [])
				if typeof(auth) == TYPE_ARRAY and not auth.is_empty():
					meta_parts.append("作者: " + ", ".join(auth.map(func(x): return str(x))))
				elif typeof(auth) == TYPE_STRING and str(auth) != "":
					meta_parts.append("作者: " + str(auth))
				if str(meta.get("version", "")) != "":
					meta_parts.append("Ver: " + str(meta["version"]))
		_lbl_meta.text = " / ".join(meta_parts)
	else:
		_lbl_path.text = "未読み込み — メインウィンドウに .vrm ファイルをドラッグ＆ドロップできます"
		_lbl_meta.text = "サンプル読込や「VRM を開く...」からも読み込めます。"

	_chk_first_person.button_pressed = bool(st.get("first_person", false))

	var rec: Array = st.get("recent_vrm_paths", [])
	var rkey := JSON.stringify(rec)
	if rkey != _last_recent_key:
		_last_recent_key = rkey
		for c in _recent_box.get_children():
			c.queue_free()
		if rec.is_empty():
			UiWidgets.note(_recent_box, "履歴はまだありません。")
		else:
			for p_raw in rec:
				var rp := str(p_raw)
				var b := Button.new()
				b.text = rp.get_file()
				b.tooltip_text = rp
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				b.pressed.connect(func():
					if _win.controller != null:
						_win.controller.load_vrm(rp)
				)
				_recent_box.add_child(b)

	var xf: Dictionary = st.get("model_transform", {})
	var pos: Array = xf.get("position", [0.0, 0.0, 0.0])
	if pos.size() >= 3:
		_sl_pos_x.value = float(pos[0])
		_sl_pos_y.value = float(pos[1])
		_sl_pos_z.value = float(pos[2])
	_sl_rot_y.value = float(xf.get("rotation_y_deg", 0.0))
	_sl_scale.value = float(xf.get("scale", 1.0))

	var sb: Dictionary = st.get("spring_bone", {})
	_chk_sb_en.button_pressed = bool(sb.get("enabled", true))
	_sl_sb_grav.value = float(sb.get("gravity_scale", 1.0))
	_sl_sb_stiff.value = float(sb.get("stiffness_scale", 1.0))
	var w: Array = sb.get("wind", [0.0, 0.0, 0.0])
	if w.size() >= 3:
		_sl_wind_x.value = float(w[0])
		_sl_wind_y.value = float(w[1])
		_sl_wind_z.value = float(w[2])
