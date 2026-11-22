extends RefCounted

const VrmExpressionsScript := preload("res://scripts/vrm/vrm_expressions.gd")
const UiWidgets := preload("res://scripts/ui/ui_widgets.gd")

const HOTKEY_KEYS := ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12", "Ctrl+Shift+S"]

var _win
var _opt_lookat: OptionButton
var _sl_lx: HSlider
var _sl_ly: HSlider
var _sl_lz: HSlider

var _expr_box: VBoxContainer
var _expr_sliders: Dictionary = {} # ename -> HSlider
var _last_expr_list_key: String = ""

var _chk_global_hk: CheckBox
var _hk_edits: Dictionary = {} # key -> LineEdit


func build(win, vb: VBoxContainer) -> void:
	_win = win
	var is_sync: Callable = win.is_syncing_fn()

	# ---- 視線 (LookAt)
	var c_la: Dictionary = UiWidgets.card(vb, "視線 (LookAt)")
	_opt_lookat = UiWidgets.option_row(c_la["body"], "視線モード", [
		["camera", "カメラを見る"],
		["manual", "指定した座標を見る"],
		["off", "オフ (正面固定)"],
	], func(m: String):
		if _win.controller != null:
			_win.controller.set_lookat_params({"mode": m}),
		is_sync
	)
	var push_lt := func(_v: float):
		if _win.controller != null:
			_win.controller.set_lookat_params({"target": [_sl_lx.value, _sl_ly.value, _sl_lz.value]})
	_sl_lx = UiWidgets.slider(c_la["body"], "注視 X (m)", -5.0, 5.0, 0.05, 0.0, push_lt, is_sync)
	_sl_ly = UiWidgets.slider(c_la["body"], "注視 Y (m)", -1.0, 4.0, 0.05, 1.4, push_lt, is_sync)
	_sl_lz = UiWidgets.slider(c_la["body"], "注視 Z (m)", -5.0, 5.0, 0.05, 2.0, push_lt, is_sync)

	# ---- クイック表情
	var c_q: Dictionary = UiWidgets.card(vb, "クイック表情プリセット")
	var qg := GridContainer.new()
	qg.columns = 4
	qg.add_theme_constant_override("h_separation", 8)
	qg.add_theme_constant_override("v_separation", 8)
	c_q["body"].add_child(qg)

	var quick_exprs := [
		["neutral", "通常"],
		["happy", "笑顔"],
		["angry", "怒り"],
		["sad", "悲しみ"],
		["relaxed", "リラックス"],
		["surprised", "驚き"],
		["aa", "口: あ"],
		["ih", "口: い"],
		["ou", "口: う"],
		["ee", "口: え"],
		["oh", "口: お"],
	]
	for item in quick_exprs:
		var ename: String = item[0]
		var elabel: String = item[1]
		var b := Button.new()
		b.text = elabel
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			if _win.controller != null:
				_win.controller.set_expressions_weights({ename: 1.0}, 0.15, true)
		)
		qg.add_child(b)

	var b_rst := Button.new()
	b_rst.text = "すべてリセット"
	b_rst.theme_type_variation = "DangerButton"
	b_rst.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_rst.pressed.connect(func():
		if _win.controller != null:
			_win.controller.reset_expressions(0.15)
	)
	qg.add_child(b_rst)

	# ---- 個別スライダー
	var c_sl: Dictionary = UiWidgets.card(vb, "表情ウェイト個別調整")
	_expr_box = VBoxContainer.new()
	_expr_box.add_theme_constant_override("separation", 6)
	c_sl["body"].add_child(_expr_box)
	_rebuild_expr_sliders(VrmExpressionsScript.PRESET_NAMES)

	# ---- ショートカットキー
	var c_hk: Dictionary = UiWidgets.card(vb, "ホットキー設定 (F1〜F12)")
	_chk_global_hk = UiWidgets.check(c_hk["body"], "グローバルホットキー有効 (他アプリ使用中も反応)", false, func(on: bool):
		if _win.controller != null:
			_win.controller.hotkey_manager.apply_params({"global_enabled": on}),
		is_sync
	)
	for hk in HOTKEY_KEYS:
		var k: String = hk
		var r := UiWidgets.labeled_row(c_hk["body"], k, 110)
		var le := LineEdit.new()
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.text_submitted.connect(func(txt: String): _commit_hotkey(k, txt))
		le.focus_exited.connect(func(): _commit_hotkey(k, le.text))
		r.add_child(le)
		_hk_edits[k] = le
	UiWidgets.note(c_hk["body"], "書式例: expr:happy / action:screenshot / action:toggle_record / action:toggle_settings")


func _commit_hotkey(k: String, txt: String) -> void:
	if _win.is_syncing or _win.controller == null:
		return
	_win.controller.hotkey_manager.apply_params({"bindings": {k: txt.strip_edges()}})


func _rebuild_expr_sliders(names: Array) -> void:
	var key := JSON.stringify(names)
	if key == _last_expr_list_key:
		return
	_last_expr_list_key = key
	for c in _expr_box.get_children():
		c.queue_free()
	_expr_sliders.clear()

	var is_sync: Callable = _win.is_syncing_fn()
	for n_raw in names:
		var ename := str(n_raw)
		var sl := UiWidgets.slider(_expr_box, ename, 0.0, 1.0, 0.02, 0.0, func(v: float):
			if _win.controller != null:
				_win.controller.set_expression_weight(ename, v, 0.05),
			is_sync
		)
		_expr_sliders[ename] = sl


func on_model_loaded(info: Dictionary) -> void:
	var raw_names: Variant = info.get("expressions", [])
	if typeof(raw_names) == TYPE_ARRAY and not (raw_names as Array).is_empty():
		_rebuild_expr_sliders(raw_names)
	else:
		_rebuild_expr_sliders(VrmExpressionsScript.PRESET_NAMES)


func sync(st: Dictionary) -> void:
	UiWidgets.select_option_by_meta(_opt_lookat, str(st.get("lookat_mode", "camera")))
	var lt: Array = st.get("lookat_target", [0.0, 1.4, 2.0])
	if lt.size() >= 3:
		_sl_lx.value = float(lt[0])
		_sl_ly.value = float(lt[1])
		_sl_lz.value = float(lt[2])

	var ex: Dictionary = st.get("expressions", {})
	if not ex.is_empty():
		var keys := ex.keys()
		keys.sort()
		var missing := false
		for k in keys:
			if not _expr_sliders.has(str(k)):
				missing = true
				break
		if missing:
			_rebuild_expr_sliders(keys)
	for k in _expr_sliders.keys():
		(_expr_sliders[k] as HSlider).value = float(ex.get(k, 0.0))

	var hk: Dictionary = st.get("hotkeys", {})
	_chk_global_hk.button_pressed = bool(hk.get("global_enabled", false))
	var binds: Dictionary = hk.get("bindings", {})
	for k in _hk_edits.keys():
		var le: LineEdit = _hk_edits[k]
		if not le.has_focus():
			le.text = str(binds.get(k, ""))
