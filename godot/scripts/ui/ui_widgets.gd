class_name UiWidgets
extends RefCounted

## 設定ウィンドウ共通のカード・フォーム部品ファクトリ。
## ラベル幅 (150px)、HelpMark 配置、マウスホイール無効化、折りたたみカード、トースト枠を統一する。

const UiThemeScript := preload("res://scripts/ui/ui_theme.gd")
const HelpMarkScript := preload("res://scripts/ui/help_mark.gd")
const UiHelpScript := preload("res://scripts/ui/ui_help.gd")

const LABEL_WIDTH := 150


## Card を直接構築する。header.get_parent().get_parent() が PanelContainer (card) になる構造を保つ。
static func card(parent: VBoxContainer, title_text: String, collapsible: bool = false, start_open: bool = true) -> Dictionary:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "Card"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)

	var card_vb := VBoxContainer.new()
	card_vb.add_theme_constant_override("separation", 7)
	panel.add_child(card_vb)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	card_vb.add_child(header)

	var bar := ColorRect.new()
	bar.color = UiThemeScript.ACCENT
	bar.custom_minimum_size = Vector2(3, 17)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(bar)

	var toggle_btn: Button = null

	if collapsible:
		toggle_btn = Button.new()
		toggle_btn.theme_type_variation = "CollapsibleHeader"
		toggle_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		toggle_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		toggle_btn.add_theme_font_size_override("font_size", 15)
		header.add_child(toggle_btn)
	else:
		var lbl := Label.new()
		lbl.theme_type_variation = "SectionLabel"
		lbl.text = title_text
		lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		header.add_child(lbl)

	if UiHelpScript.HELP.has(title_text):
		header.add_child(HelpMarkScript.new(UiHelpScript.HELP[title_text]))

	if not collapsible:
		var hdr_spacer := Control.new()
		hdr_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hdr_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_child(hdr_spacer)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	card_vb.add_child(sep)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 7)
	card_vb.add_child(body)

	var set_open := func(open: bool) -> void:
		sep.visible = open
		body.visible = open
		if toggle_btn != null:
			toggle_btn.text = ("%s  %s" % ["▾" if open else "▸", title_text])

	if collapsible:
		set_open.call(start_open)
		toggle_btn.pressed.connect(func(): set_open.call(not body.visible))

	return {"card": panel, "header": header, "body": body, "set_open": set_open}


static func row_label(label_text: String, width: int = LABEL_WIDTH) -> Control:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.theme_type_variation = "DimLabel"
	lbl.clip_text = true
	lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbl.tooltip_text = label_text
	if not UiHelpScript.HELP.has(label_text):
		lbl.custom_minimum_size = Vector2(width, 0)
		return lbl
	var box := HBoxContainer.new()
	box.custom_minimum_size = Vector2(width, 0)
	box.add_theme_constant_override("separation", 4)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(lbl)
	box.add_child(HelpMarkScript.new(UiHelpScript.HELP[label_text]))
	return box


static func labeled_row(parent: VBoxContainer, label_text: String, width: int = LABEL_WIDTH) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.add_child(row_label(label_text, width))
	parent.add_child(hb)
	return hb


static func slider(
	parent: VBoxContainer,
	label_text: String,
	min_v: float,
	max_v: float,
	step_v: float,
	def_v: float,
	cb: Callable,
	is_syncing: Callable
) -> HSlider:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var lbl_ctrl := row_label(label_text)
	var lbl: Label = lbl_ctrl if lbl_ctrl is Label else (lbl_ctrl.get_child(0) as Label)
	lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	hb.add_child(lbl_ctrl)

	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step_v
	sl.value = def_v
	sl.scrollable = false
	sl.mouse_filter = Control.MOUSE_FILTER_PASS
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var val_lbl := Label.new()
	val_lbl.theme_type_variation = "ValueLabel"
	val_lbl.custom_minimum_size = Vector2(58, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.text = str(snappedf(def_v, 0.01))

	sl.value_changed.connect(func(v: float):
		val_lbl.text = str(snappedf(v, 0.01))
		if not bool(is_syncing.call()):
			cb.call(v)
	)
	var default_v := def_v
	lbl.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.double_click and ev.button_index == MOUSE_BUTTON_LEFT:
			sl.value = default_v
	)
	lbl.tooltip_text = "%s\n(ラベルをダブルクリックで初期値 %s に戻す)" % [label_text, str(snappedf(def_v, 0.01))]

	hb.add_child(sl)
	hb.add_child(val_lbl)
	parent.add_child(hb)
	return sl


static func check(
	parent: VBoxContainer,
	label_text: String,
	def_v: bool,
	cb: Callable,
	is_syncing: Callable
) -> CheckBox:
	var chk := CheckBox.new()
	chk.text = label_text
	chk.button_pressed = def_v
	chk.toggled.connect(func(v: bool):
		if not bool(is_syncing.call()):
			cb.call(v)
	)
	if UiHelpScript.HELP.has(label_text):
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		hb.add_child(chk)
		hb.add_child(HelpMarkScript.new(UiHelpScript.HELP[label_text]))
		parent.add_child(hb)
	else:
		parent.add_child(chk)
	return chk


static func option_row(
	parent: VBoxContainer,
	label_text: String,
	items: Array,
	cb: Callable,
	is_syncing: Callable,
	width: int = LABEL_WIDTH
) -> OptionButton:
	var hb := labeled_row(parent, label_text, width)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in items.size():
		opt.add_item(str(items[i][1]))
		opt.set_item_metadata(i, items[i][0])
	opt.item_selected.connect(func(i: int):
		if not bool(is_syncing.call()):
			cb.call(opt.get_item_metadata(i))
	)
	hb.add_child(opt)
	return opt


static func color_row(
	parent: VBoxContainer,
	label_text: String,
	def_col: Color,
	cb: Callable,
	is_syncing: Callable
) -> ColorPickerButton:
	var hb := labeled_row(parent, label_text)
	var btn := ColorPickerButton.new()
	btn.color = def_col
	btn.edit_alpha = false
	btn.custom_minimum_size = Vector2(96, 28)
	btn.color_changed.connect(func(c: Color):
		if not bool(is_syncing.call()):
			cb.call(c)
	)
	hb.add_child(btn)
	return btn


static func note(parent: VBoxContainer, text_str: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = "MutedLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = text_str
	parent.add_child(l)
	return l


static func select_option_by_meta(opt: OptionButton, meta_val: String) -> void:
	for i in range(opt.item_count):
		if str(opt.get_item_metadata(i)) == meta_val:
			opt.selected = i
			return


static func select_option_by_text(opt: OptionButton, text_val: String) -> void:
	for i in range(opt.item_count):
		if opt.get_item_text(i) == text_val:
			opt.selected = i
			return


static func file_dialog(
	owner: Node,
	mode: FileDialog.FileMode,
	filters: PackedStringArray,
	on_selected: Callable,
	default_file: String = ""
) -> FileDialog:
	var dlg := FileDialog.new()
	dlg.use_native_dialog = true
	dlg.theme = UiThemeScript.get_theme()
	dlg.file_mode = mode
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = filters
	if default_file != "":
		dlg.current_file = default_file
	dlg.file_selected.connect(on_selected)
	owner.add_child(dlg)
	return dlg


## 左端だけにアクセント帯が付く統一トーストパネルを作る。
static func make_toast_panel() -> Dictionary:
	var panel := PanelContainer.new()
	var st := UiThemeScript.box(Color("#1f232c"), 8, UiThemeScript.LINE_HI, 1, 0, 0)
	st.shadow_color = Color(0, 0, 0, 0.48)
	st.shadow_size = 10
	panel.add_theme_stylebox_override("panel", st)

	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	panel.add_child(outer)

	var bar := ColorRect.new()
	bar.color = UiThemeScript.ACCENT
	bar.custom_minimum_size = Vector2(4, 0)
	outer.add_child(bar)

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 9)
	pad.add_theme_constant_override("margin_bottom", 9)
	outer.add_child(pad)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	pad.add_child(hb)

	return {"panel": panel, "hbox": hb}
