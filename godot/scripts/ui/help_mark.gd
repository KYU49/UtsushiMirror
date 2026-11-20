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
	add_theme_font_size_override("font_size", 11)
	add_theme_color_override("font_color", Color("#c9ccd4"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#2b2f38")
	sb.border_color = Color("#5a606c")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(9)
	add_theme_stylebox_override("normal", sb)


func _make_custom_tooltip(for_text: String) -> Object:
	var l := Label.new()
	l.text = for_text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(340, 0)
	l.add_theme_color_override("font_color", UiThemeScript.TEXT)
	l.add_theme_font_size_override("font_size", 13)
	return l
