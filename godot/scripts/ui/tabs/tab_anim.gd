extends RefCounted

const AnimCategoryScript := preload("res://scripts/core/anim_category.gd")
const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const UiWidgets := preload("res://scripts/ui/ui_widgets.gd")

var _win
var _search_edit: LineEdit
var _opt_cat: OptionButton
var _lbl_count: Label
var _clip_list_vb: VBoxContainer
var _clip_btns: Dictionary = {} # clip_name -> Button
var _last_list_key: String = "__init__"

var _selected_clip: String = ""
var _cur_playing_clip: String = ""
var _lbl_playing: Label
var _btn_pause: Button
var _sl_seek: HSlider
var _lbl_time: Label
var _updating_seek: bool = false

var _chk_loop: CheckBox
var _sl_speed: HSlider
var _sl_blend: HSlider

var _chk_idle_en: CheckBox
var _chk_breath: CheckBox
var _chk_blink: CheckBox
var _chk_saccade: CheckBox
var _chk_sway: CheckBox
var _sl_idle_int: HSlider

var _cached_anims: Array = []


func build(win, vb: VBoxContainer) -> void:
	_win = win
	var is_sync: Callable = win.is_syncing_fn()

	# ---- 再生コントロール (操作しやすい最上段に配置)
	var c_ply: Dictionary = UiWidgets.card(vb, "再生コントロール")
	_lbl_playing = Label.new()
	_lbl_playing.add_theme_color_override("font_color", UiTheme.VALUE_TEXT)
	_lbl_playing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_playing.text = "停止中"
	c_ply["body"].add_child(_lbl_playing)

	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	c_ply["body"].add_child(brow)

	var b_play := Button.new()
	b_play.text = "▶ 再生"
	b_play.theme_type_variation = "AccentButton"
	b_play.pressed.connect(func():
		if _win.controller == null:
			return
		var target := _selected_clip if _selected_clip != "" else _cur_playing_clip
		if target == "" and not _cached_anims.is_empty():
			target = str(_cached_anims[0])
		if target != "":
			_win.controller.play_animation_internal(target, _chk_loop.button_pressed, _sl_speed.value, _sl_blend.value)
	)
	brow.add_child(b_play)

	_btn_pause = Button.new()
	_btn_pause.text = "一時停止"
	_btn_pause.pressed.connect(func():
		if _win.controller == null or _win.controller.vrma_player == null:
			return
		var p: bool = bool(_win.controller.vrma_player.paused)
		_win.controller.set_animation_params({"paused": not p})
	)
	brow.add_child(_btn_pause)

	var b_stop := Button.new()
	b_stop.text = "■ 停止"
	b_stop.pressed.connect(func():
		if _win.controller != null:
			_win.controller.stop_animation_internal()
	)
	brow.add_child(b_stop)

	var b_open := Button.new()
	b_open.text = "VRMA / NPZ を開く..."
	b_open.pressed.connect(func():
		if _win.controller != null:
			_win.controller.open_vrma_file_dialog()
	)
	brow.add_child(b_open)

	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	c_ply["body"].add_child(srow)
	srow.add_child(UiWidgets.row_label("再生位置", 110))
	_sl_seek = HSlider.new()
	_sl_seek.min_value = 0.0
	_sl_seek.max_value = 1.0
	_sl_seek.step = 0.002
	_sl_seek.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sl_seek.value_changed.connect(func(v: float):
		if _updating_seek or _win.is_syncing or _win.controller == null:
			return
		var vp = _win.controller.vrma_player
		if vp != null and vp.current_clip != null:
			vp.seek(v * float(vp.current_clip.duration))
	)
	srow.add_child(_sl_seek)
	_lbl_time = Label.new()
	_lbl_time.theme_type_variation = "ValueLabel"
	_lbl_time.custom_minimum_size.x = 104
	_lbl_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_lbl_time.text = "0.0s / 0.0s"
	srow.add_child(_lbl_time)

	_chk_loop = UiWidgets.check(c_ply["body"], "ループ再生", true, func(on: bool):
		if _win.controller != null:
			_win.controller.set_animation_params({"looping": on}),
		is_sync
	)
	_sl_speed = UiWidgets.slider(c_ply["body"], "再生速度 (倍)", 0.1, 3.0, 0.05, 1.0, func(v: float):
		if _win.controller != null:
			_win.controller.set_animation_params({"speed": v}),
		is_sync
	)
	_sl_blend = UiWidgets.slider(c_ply["body"], "ブレンド時間 (秒)", 0.0, 1.0, 0.05, 0.25, func(_v: float): pass, is_sync)

	var fold_row := HBoxContainer.new()
	fold_row.add_theme_constant_override("separation", 8)
	c_ply["body"].add_child(fold_row)
	var b_dir := Button.new()
	b_dir.text = "プリセットフォルダを開く"
	b_dir.pressed.connect(func():
		if _win.controller != null:
			_win.controller.open_presets_folder("animations")
	)
	fold_row.add_child(b_dir)

	var b_rel := Button.new()
	b_rel.text = "フォルダを再スキャン"
	b_rel.pressed.connect(func():
		if _win.controller != null:
			var n: int = _win.controller.reload_animation_presets()
			_win.show_snackbar("モーションプリセットを再読込しました（%d 件）" % n)
	)
	fold_row.add_child(b_rel)

	# ---- アニメーション一覧 (コンパクトな専用スクロール枠)
	var c_list: Dictionary = UiWidgets.card(vb, "アニメーション一覧")
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 8)
	c_list["body"].add_child(frow)

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "クリップ名で検索..."
	_search_edit.clear_button_enabled = true
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.text_changed.connect(func(_t: String):
		_last_list_key = "__dirty__"
		_rebuild_clip_list(_cached_anims)
	)
	frow.add_child(_search_edit)

	_opt_cat = OptionButton.new()
	_opt_cat.custom_minimum_size.x = 150
	_opt_cat.add_item("すべてのカテゴリ")
	_opt_cat.set_item_metadata(0, "__all__")
	var ci := 1
	for cat in AnimCategoryScript.ORDER:
		_opt_cat.add_item(str(cat))
		_opt_cat.set_item_metadata(ci, str(cat))
		ci += 1
	_opt_cat.item_selected.connect(func(_idx: int):
		_last_list_key = "__dirty__"
		_rebuild_clip_list(_cached_anims)
	)
	frow.add_child(_opt_cat)

	var meta_row := HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 12)
	c_list["body"].add_child(meta_row)

	_lbl_count = Label.new()
	_lbl_count.theme_type_variation = "MutedLabel"
	_lbl_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta_row.add_child(_lbl_count)

	for leg in [
		["■ 女性向け", Color("#e06c9f")],
		["■ 男性向け", Color("#58a6ff")],
		["■ 共通", UiTheme.TEXT_MUTED],
	]:
		var ll := Label.new()
		ll.text = leg[0]
		ll.add_theme_color_override("font_color", leg[1])
		ll.add_theme_font_size_override("font_size", 11)
		meta_row.add_child(ll)

	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(0, 300)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	c_list["body"].add_child(list_scroll)

	_clip_list_vb = VBoxContainer.new()
	_clip_list_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clip_list_vb.add_theme_constant_override("separation", 10)
	list_scroll.add_child(_clip_list_vb)

	# ---- Procedural Idle
	var c_idle: Dictionary = UiWidgets.card(vb, "自然な待機モーション (Procedural Idle)")
	var push_idle := func():
		if _win.controller != null:
			_win.controller.procedural_idle.apply_params({
				"enabled": _chk_idle_en.button_pressed,
				"breathing": _chk_breath.button_pressed,
				"blink": _chk_blink.button_pressed,
				"saccade": _chk_saccade.button_pressed,
				"sway": _chk_sway.button_pressed,
				"intensity": _sl_idle_int.value,
			})
	_chk_idle_en = UiWidgets.check(c_idle["body"], "待機モーション有効", true, func(_on: bool): push_idle.call(), is_sync)
	_chk_breath = UiWidgets.check(c_idle["body"], "呼吸 (胸の上下)", true, func(_on: bool): push_idle.call(), is_sync)
	_chk_blink = UiWidgets.check(c_idle["body"], "自動まばたき", true, func(_on: bool): push_idle.call(), is_sync)
	_chk_saccade = UiWidgets.check(c_idle["body"], "視線の微動 (サッケード)", true, func(_on: bool): push_idle.call(), is_sync)
	_chk_sway = UiWidgets.check(c_idle["body"], "体の重心揺れ", true, func(_on: bool): push_idle.call(), is_sync)
	_sl_idle_int = UiWidgets.slider(c_idle["body"], "待機モーションの強さ", 0.0, 2.5, 0.05, 1.0, func(_v: float): push_idle.call(), is_sync)


static func _clip_variation(nm: String) -> String:
	var g: String = AnimCategoryScript.gender_of(nm)
	if g == "female":
		return "AnimClipButtonFemale"
	if g == "male":
		return "AnimClipButtonMale"
	return "AnimClipButton"


func _rebuild_clip_list(anims: Array) -> void:
	var cat_meta: String = str(_opt_cat.get_item_metadata(_opt_cat.selected)) if _opt_cat.selected >= 0 else "__all__"
	var q: String = _search_edit.text.strip_edges().to_lower()
	var list_key := JSON.stringify(anims) + "|" + cat_meta + "|" + q
	if list_key == _last_list_key:
		return
	_last_list_key = list_key

	for c in _clip_list_vb.get_children():
		c.queue_free()
	_clip_btns.clear()

	var only_cat := "" if cat_meta == "__all__" else cat_meta
	var groups: Array = AnimCategoryScript.group(anims)
	var shown := 0
	for g in groups:
		var gname := str(g[0])
		if only_cat != "" and gname != only_cat:
			continue
		var matched: Array[String] = []
		for nm_raw in g[1]:
			var nm := str(nm_raw)
			var disp: String = AnimCategoryScript.display_name(nm)
			if q != "" and not nm.to_lower().contains(q) and not disp.to_lower().contains(q):
				continue
			matched.append(nm)
		if matched.is_empty():
			continue

		var cat_hdr := HBoxContainer.new()
		cat_hdr.add_theme_constant_override("separation", 8)
		_clip_list_vb.add_child(cat_hdr)

		var cat_lbl := Label.new()
		cat_lbl.text = "%s (%d)" % [gname, matched.size()]
		cat_lbl.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		cat_lbl.add_theme_font_size_override("font_size", 12)
		cat_hdr.add_child(cat_lbl)

		var cat_sep := HSeparator.new()
		cat_sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cat_sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cat_hdr.add_child(cat_sep)

		var cat_grid := GridContainer.new()
		cat_grid.columns = 2
		cat_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cat_grid.add_theme_constant_override("h_separation", 8)
		cat_grid.add_theme_constant_override("v_separation", 6)
		_clip_list_vb.add_child(cat_grid)

		for nm in matched:
			shown += 1
			var disp: String = AnimCategoryScript.display_name(nm)
			var b := Button.new()
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			b.tooltip_text = "%s [%s]" % [nm, gname]
			b.theme_type_variation = "AccentButton" if nm == _cur_playing_clip else _clip_variation(nm)
			b.text = ("▶ " + disp) if nm == _cur_playing_clip else disp
			b.pressed.connect(func():
				_selected_clip = nm
				if _win.controller != null:
					_win.controller.play_animation_internal(nm, _chk_loop.button_pressed, _sl_speed.value, _sl_blend.value)
			)
			cat_grid.add_child(b)
			_clip_btns[nm] = b

	_lbl_count.text = "%d 件表示 / 全 %d 件" % [shown, anims.size()]


func _refresh_active_clip_style(new_playing: String) -> void:
	if new_playing == _cur_playing_clip:
		return
	if _clip_btns.has(_cur_playing_clip):
		var prev_b: Button = _clip_btns[_cur_playing_clip]
		if is_instance_valid(prev_b):
			prev_b.theme_type_variation = _clip_variation(_cur_playing_clip)
			prev_b.text = AnimCategoryScript.display_name(_cur_playing_clip)
	_cur_playing_clip = new_playing
	if _clip_btns.has(_cur_playing_clip):
		var cur_b: Button = _clip_btns[_cur_playing_clip]
		if is_instance_valid(cur_b):
			cur_b.theme_type_variation = "AccentButton"
			cur_b.text = "▶ " + AnimCategoryScript.display_name(_cur_playing_clip)


func update_scrubber() -> void:
	if _win.controller == null or _win.controller.vrma_player == null:
		return
	var vp = _win.controller.vrma_player
	if not vp.playing or vp.current_clip == null:
		return
	var dur := maxf(float(vp.current_clip.duration), 0.001)
	var t := clampf(float(vp.time_sec), 0.0, dur)
	_updating_seek = true
	_sl_seek.value = clampf(t / dur, 0.0, 1.0)
	_updating_seek = false
	_lbl_time.text = "%.1fs / %.1fs" % [t, dur]


func sync(st: Dictionary) -> void:
	_cached_anims = st.get("available_animations", [])
	var anim: Dictionary = st.get("animation", {})
	var playing := bool(anim.get("playing", false))
	var paused := bool(anim.get("paused", false))
	var cur_name := str(anim.get("name", "")) if playing else ""

	_rebuild_clip_list(_cached_anims)
	_refresh_active_clip_style(cur_name)

	if playing:
		_selected_clip = cur_name
		_lbl_playing.text = ("⏸ 一時停止: " if paused else "▶ 再生中: ") + AnimCategoryScript.display_name(cur_name) + " (" + cur_name + ")"
		_btn_pause.text = "再開" if paused else "一時停止"
		_btn_pause.disabled = false
	else:
		_lbl_playing.text = "停止中"
		_btn_pause.text = "一時停止"
		_btn_pause.disabled = true

	var dur := float(anim.get("duration", 0.0))
	var t := float(anim.get("time_sec", 0.0))
	_updating_seek = true
	_sl_seek.value = clampf(t / maxf(dur, 0.001), 0.0, 1.0) if playing else 0.0
	_updating_seek = false
	_lbl_time.text = "%.1fs / %.1fs" % [t, dur]

	_chk_loop.button_pressed = bool(anim.get("looping", true))
	_sl_speed.value = float(anim.get("speed", 1.0))

	var idl: Dictionary = st.get("idle", {})
	_chk_idle_en.button_pressed = bool(idl.get("enabled", true))
	_chk_breath.button_pressed = bool(idl.get("breathing", true))
	_chk_blink.button_pressed = bool(idl.get("blink", true))
	_chk_saccade.button_pressed = bool(idl.get("saccade", true))
	_chk_sway.button_pressed = bool(idl.get("sway", true))
	_sl_idle_int.value = float(idl.get("intensity", 1.0))
