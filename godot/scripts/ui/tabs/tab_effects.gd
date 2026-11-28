extends RefCounted

const PostEffectsScript := preload("res://scripts/core/post_effects.gd")
const UiWidgets := preload("res://scripts/ui/ui_widgets.gd")

const STYLE_ORDER := ["none", "anime", "cinema", "drama", "painterly", "noir", "oldfilm", "vhs"]

var _win
var _style_btns: Dictionary = {} # style_id -> Button
var _cur_style: String = "__init__"
var _lbl_style_desc: Label
var _sl_strength: HSlider

var _ef_sliders: Dictionary = {} # key -> HSlider
var _ef_colors: Dictionary = {}  # key -> ColorPickerButton
var _opt_letterbox: OptionButton

var _chk_sh_en: CheckBox
var _sl_sh_opac: HSlider
var _sl_sh_soft: HSlider
var _sl_sh_blur: HSlider
var _opt_sh_qual: OptionButton
var _sl_sh_dist: HSlider
var _sl_sh_bias: HSlider
var _sl_sh_nbias: HSlider

var _preset_name_edit: LineEdit
var _saved_box: GridContainer
var _last_saved_key: String = "__init__"
var _dlg_export: FileDialog
var _dlg_import: FileDialog


func build(win, vb: VBoxContainer) -> void:
	_win = win
	var is_sync: Callable = win.is_syncing_fn()

	# ---- スタイルプリセット
	var c_sty: Dictionary = UiWidgets.card(vb, "画面効果のスタイル")
	var sg := GridContainer.new()
	sg.columns = 4
	sg.add_theme_constant_override("h_separation", 8)
	sg.add_theme_constant_override("v_separation", 8)
	c_sty["body"].add_child(sg)

	for pid in STYLE_ORDER:
		var info: Array = PostEffectsScript.PRESETS.get(pid, [pid, "", {}])
		var b := Button.new()
		b.text = str(info[0])
		b.tooltip_text = str(info[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			if _win.controller != null:
				_win.controller.apply_effects({"style": pid})
		)
		sg.add_child(b)
		_style_btns[pid] = b

	_lbl_style_desc = Label.new()
	_lbl_style_desc.theme_type_variation = "DimLabel"
	_lbl_style_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c_sty["body"].add_child(_lbl_style_desc)

	_sl_strength = UiWidgets.slider(c_sty["body"], "効果の強さ", 0.0, 1.0, 0.02, 1.0, func(v: float):
		if _win.controller != null:
			_win.controller.apply_effects({"strength": v}),
		is_sync
	)

	var apply_ef := func(key: String, val: Variant):
		if _win.controller != null:
			_win.controller.apply_effects({key: val})

	# ---- 色 (折りたたみ)
	var c_col: Dictionary = UiWidgets.card(vb, "色", true, false)
	_add_sl(c_col["body"], "明るさ (段)", "exposure", -2.0, 2.0, 0.05, 0.0, apply_ef, is_sync)
	_add_sl(c_col["body"], "コントラスト", "contrast", 0.4, 1.8, 0.02, 1.0, apply_ef, is_sync)
	_add_sl(c_col["body"], "彩度", "saturation", 0.0, 2.0, 0.02, 1.0, apply_ef, is_sync)
	_add_sl(c_col["body"], "自然な彩度", "vibrance", -1.0, 1.0, 0.02, 0.0, apply_ef, is_sync)
	_add_sl(c_col["body"], "色温度", "temperature", -1.0, 1.0, 0.02, 0.0, apply_ef, is_sync)
	_add_sl(c_col["body"], "色かぶり", "tint", -1.0, 1.0, 0.02, 0.0, apply_ef, is_sync)
	_add_sl(c_col["body"], "黒の浮き", "black_lift", 0.0, 0.3, 0.005, 0.0, apply_ef, is_sync)
	_add_sl(c_col["body"], "白の柔らかさ", "highlight_roll", 0.0, 1.0, 0.02, 0.0, apply_ef, is_sync)
	_add_cp(c_col["body"], "暗部の色", "shadow_color", Color("#808080"), apply_ef, is_sync)
	_add_sl(c_col["body"], "暗部の色の量", "shadow_amount", 0.0, 1.0, 0.02, 0.0, apply_ef, is_sync)
	_add_cp(c_col["body"], "明部の色", "highlight_color", Color("#808080"), apply_ef, is_sync)
	_add_sl(c_col["body"], "明部の色の量", "highlight_amount", 0.0, 1.0, 0.02, 0.0, apply_ef, is_sync)
	_add_sl(c_col["body"], "セピア", "sepia", 0.0, 1.0, 0.02, 0.0, apply_ef, is_sync)
	_add_sl(c_col["body"], "モノクロ", "mono", 0.0, 1.0, 0.02, 0.0, apply_ef, is_sync)

	# ---- 絵づくり (折りたたみ)
	var c_art: Dictionary = UiWidgets.card(vb, "絵づくり (アニメ・絵画)", true, false)
	_add_sl(c_art["body"], "明るさの段数 (セル画風)", "posterize", 0.0, 16.0, 1.0, 0.0, apply_ef, is_sync)
	_add_sl(c_art["body"], "輪郭線", "edge", 0.0, 1.0, 0.02, 0.0, apply_ef, is_sync)
	_add_sl(c_art["body"], "輪郭線の感度", "edge_threshold", 0.01, 0.5, 0.005, 0.08, apply_ef, is_sync)
	_add_cp(c_art["body"], "輪郭線の色", "edge_color", Color("#1f1724"), apply_ef, is_sync)
	_add_sl(c_art["body"], "絵画風の筆の大きさ", "kuwahara", 0.0, 8.0, 0.5, 0.0, apply_ef, is_sync)

	# ---- 光のにじみ・質感 (折りたたみ)
	var c_glow: Dictionary = UiWidgets.card(vb, "光のにじみ・質感", true, false)
	_add_sl(c_glow["body"], "拡散 (Pro-Mist)", "diffusion", 0.0, 1.5, 0.02, 0.0, apply_ef, is_sync)
	_add_sl(c_glow["body"], "にじむ明るさ", "diffusion_threshold", 0.1, 1.2, 0.02, 0.6, apply_ef, is_sync)
	_add_sl(c_glow["body"], "ハレーション", "halation", 0.0, 1.0, 0.02, 0.0, apply_ef, is_sync)
	_add_sl(c_glow["body"], "ふんわり", "glow", 0.0, 1.0, 0.02, 0.0, apply_ef, is_sync)

	# ---- レンズ・フィルム・ビデオ (折りたたみ)
	var c_film: Dictionary = UiWidgets.card(vb, "レンズ・フィルム・ビデオ", true, false)
	_add_sl(c_film["body"], "ぼかし", "softness", 0.0, 1.5, 0.02, 0.0, apply_ef, is_sync)
	_add_sl(c_film["body"], "シャープ", "sharpen", 0.0, 1.5, 0.02, 0.0, apply_ef, is_sync)
	_add_sl(c_film["body"], "周辺減光", "vignette", 0.0, 1.0, 0.02, 0.0, apply_ef, is_sync)
	_add_sl(c_film["body"], "色収差", "chroma", 0.0, 3.0, 0.05, 0.0, apply_ef, is_sync)
	_add_sl(c_film["body"], "粒子", "grain", 0.0, 1.0, 0.01, 0.0, apply_ef, is_sync)
	_add_sl(c_film["body"], "粒子のコマ数", "grain_fps", 4.0, 60.0, 1.0, 24.0, apply_ef, is_sync)
	_add_sl(c_film["body"], "傷", "scratches", 0.0, 1.5, 0.02, 0.0, apply_ef, is_sync)
	_add_sl(c_film["body"], "ほこり", "dust", 0.0, 1.5, 0.02, 0.0, apply_ef, is_sync)
	_add_sl(c_film["body"], "ちらつき", "flicker", 0.0, 1.0, 0.02, 0.0, apply_ef, is_sync)
	_add_sl(c_film["body"], "揺れ", "jitter", 0.0, 1.5, 0.02, 0.0, apply_ef, is_sync)
	_add_sl(c_film["body"], "走査線", "scanlines", 0.0, 1.0, 0.02, 0.0, apply_ef, is_sync)
	_add_sl(c_film["body"], "ビデオの乱れ", "vhs", 0.0, 1.5, 0.02, 0.0, apply_ef, is_sync)
	_opt_letterbox = UiWidgets.option_row(c_film["body"], "黒帯 (縦横比)", [
		["0", "なし (全画面)"],
		["1.78", "16:9"],
		["1.85", "1.85:1 (ビスタ)"],
		["2.39", "2.39:1 (シネスコ)"],
	], func(val: String):
		apply_ef.call("letterbox", float(val)),
		is_sync
	)

	# ---- モデルの陰影 (開く)
	var c_shade: Dictionary = UiWidgets.card(vb, "モデルの陰影 (トゥーン)")
	_add_sl(c_shade["body"], "影の範囲", "shade_shift", -1.0, 1.0, 0.02, 0.0, apply_ef, is_sync)
	_add_sl(c_shade["body"], "影の境界のくっきりさ", "shade_toony", -1.0, 1.0, 0.02, 0.0, apply_ef, is_sync)
	_add_sl(c_shade["body"], "影の濃さ", "shade_strength", 0.0, 2.0, 0.02, 1.0, apply_ef, is_sync)
	_add_cp(c_shade["body"], "影の色味", "shade_tint", Color("#ffffff"), apply_ef, is_sync)

	var b_rst_shade := Button.new()
	b_rst_shade.text = "陰影を初期値に戻す"
	b_rst_shade.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b_rst_shade.pressed.connect(func():
		if _win.controller != null:
			_win.controller.apply_effects(PostEffectsScript.SHADE_DEFAULTS.duplicate())
	)
	c_shade["body"].add_child(b_rst_shade)

	# ---- 落ち影 (開く)
	var c_sh: Dictionary = UiWidgets.card(vb, "落ち影 (キーライトの影)")
	_chk_sh_en = UiWidgets.check(c_sh["body"], "影を出す", true, func(on: bool):
		if _win.controller != null: _win.controller.lighting_rig.apply_params({"shadows_enabled": on}), is_sync)
	_sl_sh_opac = UiWidgets.slider(c_sh["body"], "落ち影の濃さ", 0.0, 2.0, 0.02, 1.0, func(v: float):
		if _win.controller != null: _win.controller.lighting_rig.apply_params({"shadow_opacity": v}), is_sync)
	_sl_sh_soft = UiWidgets.slider(c_sh["body"], "影のぼけ (光源の大きさ)", 0.0, 12.0, 0.1, 0.0, func(v: float):
		if _win.controller != null: _win.controller.lighting_rig.apply_params({"shadow_softness": v}), is_sync)
	_sl_sh_blur = UiWidgets.slider(c_sh["body"], "影の縁のなめらかさ", 0.0, 4.0, 0.05, 1.0, func(v: float):
		if _win.controller != null: _win.controller.lighting_rig.apply_params({"shadow_blur": v}), is_sync)
	_opt_sh_qual = UiWidgets.option_row(c_sh["body"], "影の品質", [
		["low", "低 (軽い)"],
		["medium", "中"],
		["high", "高 (標準)"],
		["ultra", "最高 (くっきり)"],
	], func(q: String):
		if _win.controller != null: _win.controller.lighting_rig.apply_params({"shadow_quality": q}), is_sync)
	_sl_sh_dist = UiWidgets.slider(c_sh["body"], "影を描く距離 (m)", 2.0, 40.0, 0.5, 12.0, func(v: float):
		if _win.controller != null: _win.controller.lighting_rig.apply_params({"shadow_distance": v}), is_sync)
	_sl_sh_bias = UiWidgets.slider(c_sh["body"], "影のずれ", 0.0, 0.5, 0.005, 0.1, func(v: float):
		if _win.controller != null: _win.controller.lighting_rig.apply_params({"shadow_bias": v}), is_sync)
	_sl_sh_nbias = UiWidgets.slider(c_sh["body"], "法線方向のずれ", 0.0, 5.0, 0.05, 2.0, func(v: float):
		if _win.controller != null: _win.controller.lighting_rig.apply_params({"shadow_normal_bias": v}), is_sync)

	var sh_btns := HBoxContainer.new()
	sh_btns.add_theme_constant_override("separation", 8)
	c_sh["body"].add_child(sh_btns)
	var b_sharp := Button.new()
	b_sharp.text = "くっきり影にする"
	b_sharp.pressed.connect(func():
		if _win.controller != null:
			_win.controller.lighting_rig.apply_params(_win.controller.lighting_rig.SHARP_SHADOW)
	)
	sh_btns.add_child(b_sharp)
	var b_sh_rst := Button.new()
	b_sh_rst.text = "落ち影を初期値に戻す"
	b_sh_rst.pressed.connect(func():
		if _win.controller != null:
			_win.controller.lighting_rig.apply_params(_win.controller.lighting_rig.SHADOW_DEFAULTS)
	)
	sh_btns.add_child(b_sh_rst)

	# ---- 保存したプリセット
	var c_sav: Dictionary = UiWidgets.card(vb, "保存したプリセット")
	var sav_row := HBoxContainer.new()
	sav_row.add_theme_constant_override("separation", 8)
	c_sav["body"].add_child(sav_row)

	_preset_name_edit = LineEdit.new()
	_preset_name_edit.placeholder_text = "プリセット名を入力..."
	_preset_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sav_row.add_child(_preset_name_edit)

	var b_save := Button.new()
	b_save.text = "保存"
	b_save.theme_type_variation = "AccentButton"
	b_save.pressed.connect(func():
		if _win.controller == null:
			return
		var nm := _preset_name_edit.text.strip_edges()
		if nm == "":
			_win.show_snackbar("プリセット名を入力してください。")
			return
		var res: Dictionary = _win.controller.save_shader_preset(nm)
		if res.get("ok", false):
			_preset_name_edit.text = ""
			_win.show_snackbar("シェーダープリセット「" + nm + "」を保存しました。")
			_win.controller.state_changed.emit()
		else:
			_win.show_snackbar("保存失敗: " + str(res.get("error", "")))
	)
	sav_row.add_child(b_save)

	var b_dir := Button.new()
	b_dir.text = "フォルダを開く"
	b_dir.pressed.connect(func():
		if _win.controller != null:
			_win.controller.open_presets_folder("shaders")
	)
	sav_row.add_child(b_dir)

	var b_reload := Button.new()
	b_reload.text = "再読込"
	b_reload.pressed.connect(func():
		if _win.controller != null:
			_win.controller.state_changed.emit()
	)
	sav_row.add_child(b_reload)

	_saved_box = GridContainer.new()
	_saved_box.columns = 3
	_saved_box.add_theme_constant_override("h_separation", 8)
	_saved_box.add_theme_constant_override("v_separation", 6)
	c_sav["body"].add_child(_saved_box)

	# ---- 書き出し・読み込み
	var c_io: Dictionary = UiWidgets.card(vb, "シェーダー設定の書き出し・読み込み")
	var io_row := HBoxContainer.new()
	io_row.add_theme_constant_override("separation", 8)
	c_io["body"].add_child(io_row)

	_dlg_export = UiWidgets.file_dialog(_win, FileDialog.FILE_MODE_SAVE_FILE, PackedStringArray(["*.umshader ; UtsushiMirror Shader"]), func(p: String):
		if _win.controller == null:
			return
		var res: Dictionary = _win.controller.export_effects(p)
		if res.get("ok", false):
			var ep := str(res.get("path", p))
			_win.show_snackbar("シェーダー設定を書き出しました: " + ep.get_file(), "フォルダを開く", func(): UiWidgets.open_in_folder(ep))
		else:
			_win.show_snackbar("書き出し失敗: " + str(res.get("error", "")))
	, "effects.umshader")

	# 設定ファイル (.umset) も選べる。そのときはシェーダーの部分だけを読み込む
	_dlg_import = UiWidgets.file_dialog(_win, FileDialog.FILE_MODE_OPEN_FILE, PackedStringArray(["*.umshader, *.umset ; UtsushiMirror Shader / Settings", "*.umshader ; UtsushiMirror Shader", "*.umset ; UtsushiMirror Settings"]), func(p: String):
		if _win.controller == null:
			return
		var res: Dictionary = _win.controller.import_effects(p)
		if res.get("ok", false):
			var part := " (シェーダーの部分だけ)" if p.to_lower().ends_with(".umset") else ""
			_win.show_snackbar("シェーダー設定を読み込みました%s: %s" % [part, p.get_file()], "フォルダを開く", func(): UiWidgets.open_in_folder(p))
		else:
			_win.show_snackbar("読み込み失敗: " + str(res.get("error", "")))
	)

	var b_exp := Button.new()
	b_exp.text = "ファイルに書き出す (.umshader)..."
	b_exp.pressed.connect(func(): _win.popup_at_vrm_dir(_dlg_export))
	io_row.add_child(b_exp)

	var b_imp := Button.new()
	b_imp.text = "ファイルから読み込む..."
	b_imp.pressed.connect(func(): _win.popup_at_vrm_dir(_dlg_import))
	io_row.add_child(b_imp)


func _add_sl(parent: VBoxContainer, label: String, key: String, mn: float, mx: float, st: float, def_v: float, apply_ef: Callable, is_sync: Callable) -> void:
	_ef_sliders[key] = UiWidgets.slider(parent, label, mn, mx, st, def_v, func(v: float): apply_ef.call(key, v), is_sync)


func _add_cp(parent: VBoxContainer, label: String, key: String, def_c: Color, apply_ef: Callable, is_sync: Callable) -> void:
	_ef_colors[key] = UiWidgets.color_row(parent, label, def_c, func(col: Color): apply_ef.call(key, "#" + col.to_html(false)), is_sync)


func sync(st: Dictionary) -> void:
	var ef: Dictionary = st.get("effects", {})
	var style := str(ef.get("style", "none"))
	if style != _cur_style:
		_cur_style = style
		for pid in _style_btns.keys():
			var b: Button = _style_btns[pid]
			b.theme_type_variation = "AccentButton" if str(pid) == style else ""
		if PostEffectsScript.PRESETS.has(style):
			_lbl_style_desc.text = str(PostEffectsScript.PRESETS[style][1])
		else:
			_lbl_style_desc.text = "プリセットから個別に微調整されたカスタム状態です。"

	_sl_strength.value = float(ef.get("strength", 1.0))
	for k in _ef_sliders.keys():
		if ef.has(k):
			(_ef_sliders[k] as HSlider).value = float(ef[k])
	for k in _ef_colors.keys():
		if ef.has(k):
			(_ef_colors[k] as ColorPickerButton).color = Color(str(ef[k]))

	var lb := float(ef.get("letterbox", 0.0))
	var lb_meta := "0"
	if lb >= 2.1:
		lb_meta = "2.39"
	elif lb >= 1.81:
		lb_meta = "1.85"
	elif lb >= 1.0:
		lb_meta = "1.78"
	UiWidgets.select_option_by_meta(_opt_letterbox, lb_meta)

	var lt: Dictionary = st.get("lighting", {})
	_chk_sh_en.button_pressed = bool(lt.get("shadows_enabled", true))
	_sl_sh_opac.value = float(lt.get("shadow_opacity", 1.0))
	_sl_sh_soft.value = float(lt.get("shadow_softness", 0.0))
	_sl_sh_blur.value = float(lt.get("shadow_blur", 1.0))
	UiWidgets.select_option_by_meta(_opt_sh_qual, str(lt.get("shadow_quality", "high")))
	_sl_sh_dist.value = float(lt.get("shadow_distance", 12.0))
	_sl_sh_bias.value = float(lt.get("shadow_bias", 0.1))
	_sl_sh_nbias.value = float(lt.get("shadow_normal_bias", 2.0))

	var saved: Array = st.get("shader_presets", [])
	var skey := JSON.stringify(saved)
	if skey != _last_saved_key:
		_last_saved_key = skey
		for c in _saved_box.get_children():
			c.queue_free()
		if saved.is_empty():
			var l := Label.new()
			l.theme_type_variation = "MutedLabel"
			l.text = "保存したプリセットはありません"
			_saved_box.add_child(l)
		else:
			for s_raw in saved:
				var sname := str(s_raw)
				var sb := Button.new()
				sb.text = sname
				sb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				sb.pressed.connect(func():
					if _win.controller != null:
						_win.controller.apply_shader_preset(sname)
				)
				_saved_box.add_child(sb)
