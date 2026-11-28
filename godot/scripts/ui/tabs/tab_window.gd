extends RefCounted

const UiWidgets := preload("res://scripts/ui/ui_widgets.gd")

var _win
var _opt_bg: OptionButton
var _cp_bg: ColorPickerButton
var _cp_grad: ColorPickerButton
var _lbl_img: Label
var _img_path := ""

var _chk_trans: CheckBox
var _chk_borderless: CheckBox
var _chk_top: CheckBox
var _chk_click_through: CheckBox

var _sp_w: SpinBox
var _sp_h: SpinBox


func build(win, vb: VBoxContainer) -> void:
	_win = win
	var is_sync: Callable = win.is_syncing_fn()

	# ---- 背景モード
	var c_bg: Dictionary = UiWidgets.card(vb, "背景モード")
	_opt_bg = UiWidgets.option_row(c_bg["body"], "背景タイプ", [
		["solid", "単色"],
		["chroma_green", "クロマキー (緑 #00ff00)"],
		["chroma_blue", "クロマキー (青 #0000ff)"],
		["gradient", "グラデーション"],
		["image", "背景画像"],
		["transparent_window", "透過ウィンドウ"],
	], func(m: String):
		if _win.controller != null:
			_win.controller.bg_manager.apply_background({"mode": m}),
		is_sync
	)

	var qcol := HBoxContainer.new()
	qcol.add_theme_constant_override("separation", 8)
	c_bg["body"].add_child(qcol)
	for pair in [["黒 (#000000)", "#000000"], ["標準グレー", "#1e222b"], ["白 (#ffffff)", "#ffffff"]]:
		var qlbl: String = pair[0]
		var qhex: String = pair[1]
		var b := Button.new()
		b.text = qlbl
		b.pressed.connect(func():
			if _win.controller != null:
				_win.controller.bg_manager.apply_background({"mode": "solid", "color": qhex})
		)
		qcol.add_child(b)

	_cp_bg = UiWidgets.color_row(c_bg["body"], "メイン背景色", Color("#1e222b"), func(c: Color):
		if _win.controller != null:
			_win.controller.bg_manager.apply_background({"color": "#" + c.to_html(false)}),
		is_sync
	)
	_cp_grad = UiWidgets.color_row(c_bg["body"], "グラデーション下部色", Color("#0f1218"), func(c: Color):
		if _win.controller != null:
			_win.controller.bg_manager.apply_background({"gradient_bottom": "#" + c.to_html(false)}),
		is_sync
	)

	var img_row := UiWidgets.labeled_row(c_bg["body"], "背景画像ファイル")
	_lbl_img = Label.new()
	_lbl_img.theme_type_variation = "MutedLabel"
	_lbl_img.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_img.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_lbl_img.text = "(未設定)"
	img_row.add_child(_lbl_img)
	UiWidgets.path_link(_lbl_img, func(): return _img_path)

	var b_img := Button.new()
	b_img.text = "画像を選択..."
	b_img.pressed.connect(func():
		if _win.controller != null:
			_win.controller.open_bg_image_dialog()
	)
	img_row.add_child(b_img)

	var b_iclr := Button.new()
	b_iclr.text = "クリア"
	b_iclr.pressed.connect(func():
		if _win.controller != null:
			_win.controller.bg_manager.apply_background({"image_path": "", "mode": "solid"})
	)
	img_row.add_child(b_iclr)

	# ---- ウィンドウ状態
	var c_win: Dictionary = UiWidgets.card(vb, "ウィンドウ状態 (デスクトップマスコット)")
	_chk_trans = UiWidgets.check(c_win["body"], "背景透過ウィンドウ", false, func(on: bool):
		if _win.controller != null: _win.controller.bg_manager.apply_window({"transparent": on}), is_sync)
	_chk_borderless = UiWidgets.check(c_win["body"], "枠なしウィンドウ (タイトルバー非表示)", false, func(on: bool):
		if _win.controller != null: _win.controller.bg_manager.apply_window({"borderless": on}), is_sync)
	_chk_top = UiWidgets.check(c_win["body"], "常に最前面", false, func(on: bool):
		if _win.controller != null: _win.controller.bg_manager.apply_window({"always_on_top": on}), is_sync)
	_chk_click_through = UiWidgets.check(c_win["body"], "クリックスルー (背景/キャラ透過で操作)", false, func(on: bool):
		if _win.controller != null: _win.controller.bg_manager.apply_window({"click_through": on}), is_sync)

	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	c_win["body"].add_child(mrow)

	var b_mascot := Button.new()
	b_mascot.text = "デスクトップマスコットモードにする"
	b_mascot.theme_type_variation = "AccentButton"
	b_mascot.pressed.connect(func():
		if _win.controller != null:
			_win.controller.bg_manager.apply_background({"mode": "transparent_window"})
			_win.controller.bg_manager.apply_window({"transparent": true, "borderless": true, "always_on_top": true})
	)
	mrow.add_child(b_mascot)

	var b_norm := Button.new()
	b_norm.text = "通常ウィンドウに戻す"
	b_norm.pressed.connect(func():
		if _win.controller != null:
			_win.controller.bg_manager.restore_normal_window()
	)
	mrow.add_child(b_norm)
	UiWidgets.note(c_win["body"], "マスコット中はメイン画面で Alt + 左ドラッグで位置移動できます。クリックスルーはタスクトレイから解除可能です。")

	# ---- ウィンドウサイズ
	var c_sz: Dictionary = UiWidgets.card(vb, "メインウィンドウサイズ")
	var srow := UiWidgets.labeled_row(c_sz["body"], "幅 × 高さ (px)")
	_sp_w = SpinBox.new()
	_sp_w.min_value = 320
	_sp_w.max_value = 3840
	_sp_w.step = 10
	_sp_w.custom_minimum_size.x = 96
	srow.add_child(_sp_w)

	var x_lbl := Label.new()
	x_lbl.text = "×"
	srow.add_child(x_lbl)

	_sp_h = SpinBox.new()
	_sp_h.min_value = 240
	_sp_h.max_value = 2160
	_sp_h.step = 10
	_sp_h.custom_minimum_size.x = 96
	srow.add_child(_sp_h)

	var b_sz := Button.new()
	b_sz.text = "適用"
	b_sz.pressed.connect(func():
		if _win.controller != null:
			_win.controller.bg_manager.apply_window({"size": [int(_sp_w.value), int(_sp_h.value)]})
	)
	srow.add_child(b_sz)

	var pgrid := HBoxContainer.new()
	pgrid.add_theme_constant_override("separation", 6)
	c_sz["body"].add_child(pgrid)
	for szp in [["960×720", 960, 720], ["1280×720", 1280, 720], ["1920×1080", 1920, 1080], ["540×960 (縦)", 540, 960]]:
		var plbl: String = szp[0]
		var pw: int = szp[1]
		var ph: int = szp[2]
		var bp := Button.new()
		bp.text = plbl
		bp.pressed.connect(func():
			if _win.controller != null:
				_win.controller.bg_manager.apply_window({"size": [pw, ph]})
		)
		pgrid.add_child(bp)


func sync(st: Dictionary) -> void:
	var bg: Dictionary = st.get("background", {})
	UiWidgets.select_option_by_meta(_opt_bg, str(bg.get("mode", "solid")))
	_cp_bg.color = Color(str(bg.get("color", "#1e222b")))
	_cp_grad.color = Color(str(bg.get("gradient_bottom", "#0f1218")))
	var ip := str(bg.get("image_path", ""))
	_lbl_img.text = ip.get_file() if ip != "" else "(未設定)"
	_img_path = ip
	UiWidgets.refresh_path_link(_lbl_img)

	var w: Dictionary = st.get("window", {})
	_chk_trans.button_pressed = bool(w.get("transparent", false))
	_chk_borderless.button_pressed = bool(w.get("borderless", false))
	_chk_top.button_pressed = bool(w.get("always_on_top", false))
	_chk_click_through.button_pressed = bool(w.get("click_through", false))

	var ww := int(w.get("width", 1280))
	var wh := int(w.get("height", 720))
	if ww > 0:
		_sp_w.value = ww
	if wh > 0:
		_sp_h.value = wh
