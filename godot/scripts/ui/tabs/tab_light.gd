extends RefCounted

const LightDirectionPadScript := preload("res://scripts/ui/light_direction_pad.gd")
const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const UiWidgets := preload("res://scripts/ui/ui_widgets.gd")

var _win
var _pad: Control
var _dir_lbl: Label
var _chk_gizmo: CheckBox

var _sl_az: HSlider
var _sl_el: HSlider
var _sl_key_e: HSlider
var _cp_key: ColorPickerButton
var _sl_fill_e: HSlider
var _cp_fill: ColorPickerButton
var _sl_rim_e: HSlider
var _cp_rim: ColorPickerButton
var _sl_amb_e: HSlider
var _cp_amb: ColorPickerButton

var _chk_shadows: CheckBox
var _chk_bloom: CheckBox
var _sl_bloom: HSlider
var _sl_exp: HSlider
var _opt_tonemap: OptionButton


func build(win, vb: VBoxContainer) -> void:
	_win = win
	var is_sync: Callable = win.is_syncing_fn()

	# ---- プリセット
	var c_pre: Dictionary = UiWidgets.card(vb, "ライティングプリセット")
	var pg := GridContainer.new()
	pg.columns = 3
	pg.add_theme_constant_override("h_separation", 8)
	pg.add_theme_constant_override("v_separation", 8)
	c_pre["body"].add_child(pg)

	var presets := [
		["studio", "スタジオ"],
		["daylight", "昼光"],
		["sunset", "夕焼け"],
		["dramatic", "ドラマチック"],
		["flat_toon", "フラットトゥーン"],
	]
	for item in presets:
		var pid: String = item[0]
		var plabel: String = item[1]
		var b := Button.new()
		b.text = plabel
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			if _win.controller != null:
				_win.controller.lighting_rig.apply_preset(pid)
		)
		pg.add_child(b)

	# ---- ライト方向パッド
	var c_pad: Dictionary = UiWidgets.card(vb, "ライト方向・プレビュー (ドラッグで直感操作)")
	var pad_center := HBoxContainer.new()
	pad_center.alignment = BoxContainer.ALIGNMENT_CENTER
	c_pad["body"].add_child(pad_center)

	_pad = LightDirectionPadScript.new()
	_pad.custom_minimum_size = Vector2(210, 210)
	_pad.direction_changed.connect(func(az: float, el: float):
		if not _win.is_syncing and _win.controller != null:
			_win.controller.lighting_rig.apply_params({"key_azimuth_deg": az, "key_elevation_deg": el})
	)
	pad_center.add_child(_pad)

	_dir_lbl = Label.new()
	_dir_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dir_lbl.add_theme_color_override("font_color", UiTheme.VALUE_TEXT)
	_dir_lbl.add_theme_font_size_override("font_size", 13)
	c_pad["body"].add_child(_dir_lbl)

	var qg := GridContainer.new()
	qg.columns = 4
	qg.add_theme_constant_override("h_separation", 6)
	qg.add_theme_constant_override("v_separation", 6)
	c_pad["body"].add_child(qg)

	var quick_dirs := [
		["正面", 0.0, 20.0],
		["右前 45°", 45.0, 28.0],
		["左前 45°", -45.0, 28.0],
		["真上", 0.0, 80.0],
		["右真横", 90.0, 15.0],
		["左真横", -90.0, 15.0],
		["後ろ (逆光)", 180.0, 22.0],
		["下から", 0.0, -30.0],
	]
	for item in quick_dirs:
		var qlabel: String = item[0]
		var az: float = item[1]
		var el: float = item[2]
		var qb := Button.new()
		qb.text = qlabel
		qb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		qb.pressed.connect(func():
			if _win.controller != null:
				_win.controller.lighting_rig.apply_params({"key_azimuth_deg": az, "key_elevation_deg": el})
		)
		qg.add_child(qb)

	_chk_gizmo = UiWidgets.check(c_pad["body"], "3D ライト方向矢印を表示 (撮影・OBSには写りません)", false, func(on: bool):
		if _win.controller != null:
			_win.controller.lighting_rig.apply_params({"show_gizmo": on}),
		is_sync
	)

	# ---- ライト詳細
	var c_det: Dictionary = UiWidgets.card(vb, "ライト詳細 (Key / Fill / Rim / 環境光)")
	_sl_az = UiWidgets.slider(c_det["body"], "Key 方位角", -180.0, 180.0, 1.0, 35.0, func(v: float):
		if _win.controller != null: _win.controller.lighting_rig.apply_params({"key_azimuth_deg": v}), is_sync)
	_sl_el = UiWidgets.slider(c_det["body"], "Key 仰角", -60.0, 85.0, 1.0, 30.0, func(v: float):
		if _win.controller != null: _win.controller.lighting_rig.apply_params({"key_elevation_deg": v}), is_sync)
	_sl_key_e = UiWidgets.slider(c_det["body"], "Key 強さ", 0.0, 4.0, 0.05, 1.15, func(v: float):
		if _win.controller != null: _win.controller.lighting_rig.apply_params({"key_energy": v}), is_sync)
	_cp_key = UiWidgets.color_row(c_det["body"], "Key 色", Color("#fff8f0"), func(col: Color):
		if _win.controller != null: _win.controller.lighting_rig.apply_params({"key_color": "#" + col.to_html(false)}), is_sync)

	_sl_fill_e = UiWidgets.slider(c_det["body"], "Fill 強さ", 0.0, 3.0, 0.05, 0.42, func(v: float):
		if _win.controller != null: _win.controller.lighting_rig.apply_params({"fill_energy": v}), is_sync)
	_cp_fill = UiWidgets.color_row(c_det["body"], "Fill 色", Color("#dce8ff"), func(col: Color):
		if _win.controller != null: _win.controller.lighting_rig.apply_params({"fill_color": "#" + col.to_html(false)}), is_sync)

	_sl_rim_e = UiWidgets.slider(c_det["body"], "Rim 強さ", 0.0, 3.0, 0.05, 0.55, func(v: float):
		if _win.controller != null: _win.controller.lighting_rig.apply_params({"rim_energy": v}), is_sync)
	_cp_rim = UiWidgets.color_row(c_det["body"], "Rim 色", Color("#ffffff"), func(col: Color):
		if _win.controller != null: _win.controller.lighting_rig.apply_params({"rim_color": "#" + col.to_html(false)}), is_sync)

	_sl_amb_e = UiWidgets.slider(c_det["body"], "環境光強さ", 0.0, 2.0, 0.02, 0.45, func(v: float):
		if _win.controller != null: _win.controller.lighting_rig.apply_params({"ambient_energy": v}), is_sync)
	_cp_amb = UiWidgets.color_row(c_det["body"], "環境光色", Color("#e6ebf5"), func(col: Color):
		if _win.controller != null: _win.controller.lighting_rig.apply_params({"ambient_color": "#" + col.to_html(false)}), is_sync)

	# ---- シャドウ・ブルーム・露出
	var c_env: Dictionary = UiWidgets.card(vb, "シャドウ・ブルーム・露出")
	_chk_shadows = UiWidgets.check(c_env["body"], "シャドウ有効", true, func(on: bool):
		if _win.controller != null: _win.controller.lighting_rig.apply_params({"shadows_enabled": on}), is_sync)
	_chk_bloom = UiWidgets.check(c_env["body"], "Bloom 有効", false, func(on: bool):
		if _win.controller != null: _win.controller.lighting_rig.apply_params({"bloom_enabled": on}), is_sync)
	_sl_bloom = UiWidgets.slider(c_env["body"], "Bloom 強度", 0.0, 2.0, 0.02, 0.25, func(v: float):
		if _win.controller != null: _win.controller.lighting_rig.apply_params({"bloom_intensity": v}), is_sync)
	_sl_exp = UiWidgets.slider(c_env["body"], "露出 Exposure", 0.2, 2.5, 0.02, 1.0, func(v: float):
		if _win.controller != null: _win.controller.lighting_rig.apply_params({"exposure": v}), is_sync)
	_opt_tonemap = UiWidgets.option_row(c_env["body"], "トーンマップ", [
		["filmic", "Filmic (標準・自然なハイライト)"],
		["aces", "ACES (映画的・高コントラスト)"],
		["reinhard", "Reinhard (穏やか)"],
		["linear", "Linear (加工なし・原色)"],
	], func(tm: String):
		if _win.controller != null:
			_win.controller.lighting_rig.apply_params({"tonemap": tm}),
		is_sync
	)


func sync(st: Dictionary) -> void:
	var lt: Dictionary = st.get("lighting", {})
	var az := float(lt.get("key_azimuth_deg", 35.0))
	var el := float(lt.get("key_elevation_deg", 30.0))
	var key_col := Color(str(lt.get("key_color", "#fff8f0")))
	var fill_col := Color(str(lt.get("fill_color", "#dce8ff")))
	var amb_e := float(lt.get("ambient_energy", 0.45))
	_pad.set_values(az, el, key_col, fill_col, amb_e)
	if _win.controller != null and _win.controller.lighting_rig != null:
		_dir_lbl.text = "現在の光向き: " + str(_win.controller.lighting_rig.describe_direction(az, el))
	else:
		_dir_lbl.text = "方位角 %.0f° / 仰角 %.0f°" % [az, el]

	_chk_gizmo.button_pressed = bool(lt.get("show_gizmo", false))
	_sl_az.value = az
	_sl_el.value = el
	_sl_key_e.value = float(lt.get("key_energy", 1.15))
	_cp_key.color = key_col
	_sl_fill_e.value = float(lt.get("fill_energy", 0.42))
	_cp_fill.color = Color(str(lt.get("fill_color", "#dce8ff")))
	_sl_rim_e.value = float(lt.get("rim_energy", 0.55))
	_cp_rim.color = Color(str(lt.get("rim_color", "#ffffff")))
	_sl_amb_e.value = float(lt.get("ambient_energy", 0.45))
	_cp_amb.color = Color(str(lt.get("ambient_color", "#e6ebf5")))

	_chk_shadows.button_pressed = bool(lt.get("shadows_enabled", true))
	_chk_bloom.button_pressed = bool(lt.get("bloom_enabled", false))
	_sl_bloom.value = float(lt.get("bloom_intensity", 0.25))
	_sl_exp.value = float(lt.get("exposure", 1.0))
	UiWidgets.select_option_by_meta(_opt_tonemap, str(lt.get("tonemap", "filmic")))
