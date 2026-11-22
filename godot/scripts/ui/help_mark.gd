extends Label

## 項目の右に出す「?」マーク。マウスを乗せると説明 (折り返し付き) を出す。

const UiThemeScript := preload("res://scripts/ui/ui_theme.gd")


func _init(help_text: String = "") -> void:
	text = "?"
	tooltip_text = help_text
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_HELP
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	custom_minimum_size = Vector2(18, 18)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	theme_type_variation = "HelpMark"


static func make_tooltip_label(for_text: String, ref_ctrl: Control = null) -> Label:
	var l := Label.new()
	l.text = for_text
	l.add_theme_color_override("font_color", UiThemeScript.TEXT)
	l.add_theme_font_size_override("font_size", 13)
	var font: Font = ref_ctrl.get_theme_default_font() if ref_ctrl != null else UiThemeScript.get_theme().default_font
	var max_w := 0.0
	if font != null:
		for line in for_text.split("\n"):
			max_w = maxf(max_w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x)
	else:
		max_w = float(for_text.length()) * 13.0
	if max_w > 340.0:
		l.custom_minimum_size = Vector2(340, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		l.custom_minimum_size = Vector2(ceilf(max_w) + 6.0, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return l


func _make_custom_tooltip(for_text: String) -> Object:
	return make_tooltip_label(for_text, self)
