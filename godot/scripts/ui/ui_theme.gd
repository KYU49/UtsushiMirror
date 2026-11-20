class_name UiTheme
extends RefCounted

## ダーク基調 + 赤アクセントの共通 UI テーマ。
## OS の日本語フォントを使い、ボタン・スライダー・チェック・タブ・リスト等を
## すべて StyleBoxFlat と生成テクスチャで描くので、外部アセットは不要。

const ACCENT := Color("#c8252e")        # 基本アクセント (#ab1c23 より少し明るい)
const ACCENT_HI := Color("#e2404a")     # ホバー
const ACCENT_LO := Color("#ab1c23")     # 押下
const BG_0 := Color("#0e0f12")          # 最背面
const BG_1 := Color("#15171c")          # パネル
const BG_2 := Color("#1d2027")          # カード / 入力欄
const BG_3 := Color("#272b34")          # ホバー
const LINE := Color("#2f333d")          # 枠線
const TEXT := Color("#e8e9ec")
const TEXT_DIM := Color("#9aa0ab")
const TEXT_MUTED := Color("#626875")

static var _cached_theme: Theme = null


static func box(bg: Color, radius: int = 6, border: Color = Color(0, 0, 0, 0), bw: int = 0, pad_h: int = 10, pad_v: int = 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	s.anti_aliasing = true
	return s


static func _circle_tex(d: int, fill: Color, ring: Color = Color(0, 0, 0, 0), ring_w: float = 0.0) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var r := d * 0.5
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - dist, 0.0, 1.0)
			var c := fill
			if ring_w > 0.0 and dist > r - ring_w - 0.5:
				c = ring
			c.a *= a
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


static func _check_tex(on: bool, hover: bool = false) -> ImageTexture:
	# 角丸の四角 + チェックマーク
	var d := 18
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var bg := ACCENT if on else BG_2
	if hover and not on:
		bg = BG_3
	var border := ACCENT if on else Color("#4a505c")
	for y in d:
		for x in d:
			var cx := clampf(x + 0.5, 4.0, d - 4.0)
			var cy := clampf(y + 0.5, 4.0, d - 4.0)
			var dist := Vector2(x + 0.5 - cx, y + 0.5 - cy).length()
			var a := clampf(4.0 - dist, 0.0, 1.0)
			var c := border if dist > 2.6 else bg
			c.a *= a
			img.set_pixel(x, y, c)
	if on:
		var pts := [Vector2(4.5, 9.5), Vector2(7.5, 12.5), Vector2(13.5, 5.5)]
		for i in 2:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			for s in 40:
				var p := a.lerp(b, s / 39.0)
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						var q := Vector2i(int(p.x) + ox, int(p.y) + oy)
						if q.x >= 0 and q.y >= 0 and q.x < d and q.y < d:
							var w := clampf(1.6 - (Vector2(q) + Vector2(0.5, 0.5) - p).length(), 0.0, 1.0)
							var old := img.get_pixel(q.x, q.y)
							img.set_pixel(q.x, q.y, old.lerp(Color.WHITE, w))
	return ImageTexture.create_from_image(img)


static func _toggle_tex(on: bool) -> ImageTexture:
	# スイッチ型 (CheckButton 用)
	var w := 36
	var h := 20
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := ACCENT if on else Color("#3a3f4a")
	var knob_x := w - 10.0 if on else 10.0
	for y in h:
		for x in w:
			var cx := clampf(x + 0.5, 10.0, w - 10.0)
			var dist := Vector2(x + 0.5 - cx, y + 0.5 - 10.0).length()
			var c := track
			c.a *= clampf(10.0 - dist, 0.0, 1.0)
			var kd := Vector2(x + 0.5 - knob_x, y + 0.5 - 10.0).length()
			var ka := clampf(7.5 - kd, 0.0, 1.0)
			c = c.lerp(Color.WHITE, ka)
			c.a = maxf(c.a, ka)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


static func get_theme() -> Theme:
	if _cached_theme != null:
		return _cached_theme

	var th := Theme.new()
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray([
		"Yu Gothic UI", "Meiryo UI", "Meiryo", "BIZ UDGothic", "MS Gothic",
		"Noto Sans CJK JP", "Noto Sans JP", "Hiragino Sans", "sans-serif",
	])
	sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	sf.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	th.default_font = sf
	th.default_font_size = 14

	# --- 背景系 ---
	th.set_stylebox("panel", "PanelContainer", box(BG_1, 0, Color(), 0, 0, 0))
	th.set_stylebox("panel", "Panel", box(BG_1, 0))
	th.set_stylebox("embedded_border", "Window", box(BG_1, 0))
	th.set_stylebox("panel", "PopupPanel", box(BG_2, 8, LINE, 1, 6, 6))
	th.set_stylebox("panel", "TooltipPanel", box(Color("#22252d"), 6, LINE, 1, 8, 5))
	th.set_color("font_color", "TooltipLabel", TEXT)

	# --- 文字 ---
	for t in ["Label", "CheckBox", "CheckButton", "Button", "OptionButton", "MenuButton", "LinkButton"]:
		th.set_color("font_color", t, TEXT)
	th.set_color("default_color", "RichTextLabel", TEXT)
	th.set_stylebox("normal", "RichTextLabel", box(BG_2, 6, LINE, 1, 10, 8))

	# --- ボタン ---
	var btn_n := box(BG_2, 6, LINE, 1, 12, 6)
	var btn_h := box(BG_3, 6, Color("#454b57"), 1, 12, 6)
	var btn_p := box(ACCENT_LO, 6, ACCENT, 1, 12, 6)
	var btn_d := box(Color("#17191e"), 6, Color("#23262d"), 1, 12, 6)
	var btn_f := box(Color(0, 0, 0, 0), 6, ACCENT_HI, 1, 12, 6)
	for t in ["Button", "OptionButton", "MenuButton", "ColorPickerButton"]:
		th.set_stylebox("normal", t, btn_n)
		th.set_stylebox("hover", t, btn_h)
		th.set_stylebox("pressed", t, btn_p)
		th.set_stylebox("hover_pressed", t, btn_p)
		th.set_stylebox("disabled", t, btn_d)
		th.set_stylebox("focus", t, btn_f)
		th.set_color("font_hover_color", t, Color.WHITE)
		th.set_color("font_pressed_color", t, Color.WHITE)
		th.set_color("font_hover_pressed_color", t, Color.WHITE)
		th.set_color("font_disabled_color", t, TEXT_MUTED)
		th.set_color("font_focus_color", t, TEXT)

	# 強調ボタン (type variation "AccentButton")
	th.add_type("AccentButton")
	th.set_type_variation("AccentButton", "Button")
	th.set_stylebox("normal", "AccentButton", box(ACCENT, 6, ACCENT_HI, 1, 14, 7))
	th.set_stylebox("hover", "AccentButton", box(ACCENT_HI, 6, Color("#ff6b73"), 1, 14, 7))
	th.set_stylebox("pressed", "AccentButton", box(ACCENT_LO, 6, ACCENT, 1, 14, 7))
	th.set_color("font_color", "AccentButton", Color.WHITE)

	# サイドバー項目 (type variation "NavButton")
	th.add_type("NavButton")
	th.set_type_variation("NavButton", "Button")
	var nav_n := box(Color(0, 0, 0, 0), 6, Color(), 0, 14, 9)
	var nav_h := box(Color("#1f2229"), 6, Color(), 0, 14, 9)
	var nav_p := box(Color("#2a1416"), 6, Color(), 0, 14, 9)
	nav_p.border_color = ACCENT
	nav_p.border_width_left = 3
	th.set_stylebox("normal", "NavButton", nav_n)
	th.set_stylebox("hover", "NavButton", nav_h)
	th.set_stylebox("pressed", "NavButton", nav_p)
	th.set_stylebox("hover_pressed", "NavButton", nav_p)
	th.set_stylebox("focus", "NavButton", StyleBoxEmpty.new())
	th.set_color("font_color", "NavButton", TEXT_DIM)
	th.set_color("font_hover_color", "NavButton", TEXT)
	th.set_color("font_pressed_color", "NavButton", Color.WHITE)
	th.set_color("font_hover_pressed_color", "NavButton", Color.WHITE)
	th.set_constant("h_separation", "NavButton", 10)

	# --- 入力欄 ---
	var le_n := box(BG_0, 6, LINE, 1, 8, 5)
	var le_f := box(BG_0, 6, ACCENT, 1, 8, 5)
	for t in ["LineEdit", "TextEdit", "SpinBox"]:
		th.set_stylebox("normal", t, le_n)
		th.set_stylebox("focus", t, le_f)
		th.set_stylebox("read_only", t, box(BG_1, 6, LINE, 1, 8, 5))
		th.set_color("font_color", t, TEXT)
		th.set_color("caret_color", t, ACCENT_HI)
		th.set_color("selection_color", t, Color(ACCENT, 0.45))
		th.set_color("font_placeholder_color", t, TEXT_MUTED)

	# --- スライダー ---
	var track := box(Color("#2b2f38"), 3, Color(), 0, 0, 0)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	var fill := box(ACCENT, 3, Color(), 0, 0, 0)
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	var fill_h := box(ACCENT_HI, 3, Color(), 0, 0, 0)
	fill_h.content_margin_top = 2
	fill_h.content_margin_bottom = 2
	for t in ["HSlider", "VSlider"]:
		th.set_stylebox("slider", t, track)
		th.set_stylebox("grabber_area", t, fill)
		th.set_stylebox("grabber_area_highlight", t, fill_h)
		th.set_icon("grabber", t, _circle_tex(16, Color.WHITE, ACCENT, 3.0))
		th.set_icon("grabber_highlight", t, _circle_tex(16, Color.WHITE, ACCENT_HI, 3.0))
		th.set_icon("grabber_disabled", t, _circle_tex(16, Color("#555a66")))

	# --- チェック / スイッチ ---
	th.set_icon("checked", "CheckBox", _check_tex(true))
	th.set_icon("unchecked", "CheckBox", _check_tex(false))
	th.set_icon("checked_disabled", "CheckBox", _check_tex(true))
	th.set_icon("unchecked_disabled", "CheckBox", _check_tex(false))
	th.set_icon("radio_checked", "CheckBox", _circle_tex(18, Color.WHITE, ACCENT, 5.0))
	th.set_icon("radio_unchecked", "CheckBox", _circle_tex(18, BG_2, Color("#4a505c"), 1.5))
	th.set_icon("checked", "CheckButton", _toggle_tex(true))
	th.set_icon("unchecked", "CheckButton", _toggle_tex(false))
	for t in ["CheckBox", "CheckButton"]:
		var e := StyleBoxEmpty.new()
		e.content_margin_top = 3
		e.content_margin_bottom = 3
		th.set_stylebox("normal", t, e)
		th.set_stylebox("pressed", t, e)
		th.set_stylebox("hover", t, box(Color(1, 1, 1, 0.03), 5, Color(), 0, 0, 3))
		th.set_stylebox("hover_pressed", t, box(Color(1, 1, 1, 0.03), 5, Color(), 0, 0, 3))
		th.set_stylebox("focus", t, StyleBoxEmpty.new())
		th.set_color("font_hover_color", t, Color.WHITE)
		th.set_color("font_pressed_color", t, TEXT)
		th.set_color("font_hover_pressed_color", t, Color.WHITE)
		th.set_constant("h_separation", t, 8)

	# --- タブ ---
	th.set_stylebox("panel", "TabContainer", box(BG_1, 0, Color(), 0, 0, 0))
	th.set_stylebox("tab_selected", "TabContainer", box(BG_2, 6, ACCENT, 0, 12, 6))
	th.set_stylebox("tab_unselected", "TabContainer", box(Color(0, 0, 0, 0), 6, Color(), 0, 12, 6))
	th.set_stylebox("tab_hovered", "TabContainer", box(BG_3, 6, Color(), 0, 12, 6))
	th.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())

	# --- リスト / ポップアップ ---
	th.set_stylebox("panel", "ItemList", box(BG_0, 6, LINE, 1, 4, 4))
	th.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	th.set_stylebox("selected", "ItemList", box(Color("#3a1518"), 4, Color(), 0, 4, 2))
	th.set_stylebox("selected_focus", "ItemList", box(Color("#4a171b"), 4, ACCENT, 0, 4, 2))
	th.set_stylebox("hovered", "ItemList", box(BG_3, 4, Color(), 0, 4, 2))
	th.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	th.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	th.set_color("font_color", "ItemList", TEXT_DIM)
	th.set_color("font_selected_color", "ItemList", Color.WHITE)
	th.set_color("font_hovered_color", "ItemList", TEXT)
	th.set_constant("v_separation", "ItemList", 4)
	th.set_stylebox("panel", "PopupMenu", box(BG_2, 8, LINE, 1, 4, 6))
	th.set_stylebox("hover", "PopupMenu", box(Color("#3a1518"), 4, Color(), 0, 8, 4))
	th.set_color("font_color", "PopupMenu", TEXT)
	th.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	th.set_constant("v_separation", "PopupMenu", 8)

	# --- スクロールバー ---
	for t in ["VScrollBar", "HScrollBar"]:
		th.set_stylebox("scroll", t, box(Color(0, 0, 0, 0), 4, Color(), 0, 3, 3))
		th.set_stylebox("grabber", t, box(Color("#353a45"), 4, Color(), 0, 3, 3))
		th.set_stylebox("grabber_highlight", t, box(Color("#4a505c"), 4, Color(), 0, 3, 3))
		th.set_stylebox("grabber_pressed", t, box(ACCENT, 4, Color(), 0, 3, 3))

	# --- 区切り線 ---
	var sep := StyleBoxLine.new()
	sep.color = LINE
	sep.thickness = 1
	th.set_stylebox("separator", "HSeparator", sep)
	var vsep := StyleBoxLine.new()
	vsep.color = LINE
	vsep.vertical = true
	th.set_stylebox("separator", "VSeparator", vsep)

	# --- 見出し用ラベル (type variation) ---
	th.add_type("SectionLabel")
	th.set_type_variation("SectionLabel", "Label")
	th.set_color("font_color", "SectionLabel", Color.WHITE)
	th.set_font_size("font_size", "SectionLabel", 13)
	th.add_type("DimLabel")
	th.set_type_variation("DimLabel", "Label")
	th.set_color("font_color", "DimLabel", TEXT_DIM)
	th.set_font_size("font_size", "DimLabel", 13)
	th.add_type("ValueLabel")
	th.set_type_variation("ValueLabel", "Label")
	th.set_color("font_color", "ValueLabel", Color("#ff8a90"))
	th.set_font_size("font_size", "ValueLabel", 12)
	th.add_type("TitleLabel")
	th.set_type_variation("TitleLabel", "Label")
	th.set_color("font_color", "TitleLabel", Color.WHITE)
	th.set_font_size("font_size", "TitleLabel", 20)

	# カード (type variation "Card")
	th.add_type("Card")
	th.set_type_variation("Card", "PanelContainer")
	th.set_stylebox("panel", "Card", box(BG_2, 8, LINE, 1, 14, 12))
	th.add_type("Sidebar")
	th.set_type_variation("Sidebar", "PanelContainer")
	var sb := box(BG_0, 0, Color(), 0, 8, 10)
	sb.border_color = LINE
	sb.border_width_right = 1
	th.set_stylebox("panel", "Sidebar", sb)
	th.add_type("Header")
	th.set_type_variation("Header", "PanelContainer")
	var hd := box(BG_0, 0, Color(), 0, 18, 12)
	hd.border_color = LINE
	hd.border_width_bottom = 1
	th.set_stylebox("panel", "Header", hd)
	th.add_type("Footer")
	th.set_type_variation("Footer", "PanelContainer")
	var ft := box(BG_0, 0, Color(), 0, 14, 8)
	ft.border_color = LINE
	ft.border_width_top = 1
	th.set_stylebox("panel", "Footer", ft)

	_cached_theme = th
	return _cached_theme
