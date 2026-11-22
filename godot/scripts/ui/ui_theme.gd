class_name UiTheme
extends RefCounted

## ダークスタジオ基調 + クリムゾン/プライマリブルーの共通 UI テーマ。
## 外部画像アセットに依存せず、StyleBoxFlat とプロシージャルテクスチャのみで構築する。

const ACCENT := Color("#c8252e")        # ブランド・アクティブ指標
const ACCENT_HI := Color("#e2404a")
const ACCENT_LO := Color("#9e1c24")
const PRIMARY := Color("#2f6feb")       # 安全な主要操作
const PRIMARY_HI := Color("#4785ff")
const PRIMARY_LO := Color("#2356ba")
const DANGER_BG := Color("#2b1417")     # 破壊的操作
const DANGER_BORDER := Color("#c8252e")
const DANGER_TEXT := Color("#ff9da3")
const BG_0 := Color("#0c0d10")          # 最背面 (ヘッダー/サイドバー/入力欄)
const BG_1 := Color("#13151a")          # パネル背景
const BG_2 := Color("#1b1e25")          # カード / ボタン背景
const BG_3 := Color("#242832")          # ホバー面
const LINE := Color("#2b303b")          # 枠線
const LINE_HI := Color("#424957")       # 強調枠線
const TEXT := Color("#eef0f4")          # 本文
const TEXT_DIM := Color("#a0a7b5")      # 補助ラベル
const TEXT_MUTED := Color("#878f9e")    # 注記・未選択・プレースホルダ (WCAG AA 準拠)
const VALUE_TEXT := Color("#c5d4ec")    # スライダー数値表示
const STATUS_OK := Color("#3ddc84")
const STATUS_WARN := Color("#ffb4a8")

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


static func _check_tex(on: bool, hover: bool = false, disabled: bool = false) -> ImageTexture:
	var d := 18
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var bg: Color
	var border: Color
	if disabled:
		bg = Color("#242832") if on else Color("#16181e")
		border = Color("#343944")
	else:
		bg = ACCENT if on else (BG_3 if hover else BG_2)
		border = ACCENT if on else Color("#4a505c")
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
		var check_col := Color(0.65, 0.68, 0.74, 0.65) if disabled else Color.WHITE
		var pts := [Vector2(4.5, 9.5), Vector2(7.5, 12.5), Vector2(13.5, 5.5)]
		for i in 2:
			var a_pt: Vector2 = pts[i]
			var b_pt: Vector2 = pts[i + 1]
			for s in 40:
				var p := a_pt.lerp(b_pt, s / 39.0)
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						var q := Vector2i(int(p.x) + ox, int(p.y) + oy)
						if q.x >= 0 and q.y >= 0 and q.x < d and q.y < d:
							var w := clampf(1.6 - (Vector2(q) + Vector2(0.5, 0.5) - p).length(), 0.0, 1.0)
							var old := img.get_pixel(q.x, q.y)
							img.set_pixel(q.x, q.y, old.lerp(check_col, w * check_col.a))
	return ImageTexture.create_from_image(img)


static func _toggle_tex(on: bool, disabled: bool = false) -> ImageTexture:
	var w := 36
	var h := 20
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := (Color("#30343e") if disabled else ACCENT) if on else (Color("#1d2027") if disabled else Color("#3a3f4a"))
	var knob_col := Color("#78808f") if disabled else Color.WHITE
	var knob_x := w - 10.0 if on else 10.0
	for y in h:
		for x in w:
			var cx := clampf(x + 0.5, 10.0, w - 10.0)
			var dist := Vector2(x + 0.5 - cx, y + 0.5 - 10.0).length()
			var c := track
			c.a *= clampf(10.0 - dist, 0.0, 1.0)
			var kd := Vector2(x + 0.5 - knob_x, y + 0.5 - 10.0).length()
			var ka := clampf(7.5 - kd, 0.0, 1.0)
			c = c.lerp(knob_col, ka)
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

	var sf_semi := SystemFont.new()
	sf_semi.font_names = sf.font_names
	sf_semi.font_weight = 600
	sf_semi.antialiasing = sf.antialiasing
	sf_semi.subpixel_positioning = sf.subpixel_positioning

	var sf_bold := SystemFont.new()
	sf_bold.font_names = sf.font_names
	sf_bold.font_weight = 700
	sf_bold.antialiasing = sf.antialiasing
	sf_bold.subpixel_positioning = sf.subpixel_positioning

	var sf_mono := SystemFont.new()
	sf_mono.font_names = PackedStringArray([
		"Cascadia Mono", "Consolas", "BIZ UDGothic", "Meiryo UI", "monospace",
	])
	sf_mono.antialiasing = sf.antialiasing

	th.default_font = sf
	th.default_font_size = 13

	# --- 背景系 ---
	th.set_stylebox("panel", "PanelContainer", box(BG_1, 0, Color(), 0, 0, 0))
	th.set_stylebox("panel", "Panel", box(BG_1, 0))
	th.set_stylebox("embedded_border", "Window", box(BG_1, 0))
	th.set_stylebox("panel", "PopupPanel", box(BG_2, 8, LINE_HI, 1, 6, 6))
	th.set_stylebox("panel", "TooltipPanel", box(Color("#22252d"), 6, LINE_HI, 1, 10, 6))
	th.set_color("font_color", "TooltipLabel", TEXT)

	# --- 文字 ---
	for t in ["Label", "CheckBox", "CheckButton", "Button", "OptionButton", "MenuButton", "LinkButton"]:
		th.set_color("font_color", t, TEXT)
	th.set_color("default_color", "RichTextLabel", TEXT)
	th.set_stylebox("normal", "RichTextLabel", box(BG_0, 6, LINE, 1, 10, 8))

	# --- ボタン ---
	var btn_n := box(BG_2, 6, LINE, 1, 12, 6)
	var btn_h := box(BG_3, 6, LINE_HI, 1, 12, 6)
	var btn_p := box(Color("#253047"), 6, PRIMARY, 1, 12, 6)
	var btn_d := box(Color("#16181e"), 6, Color("#22262e"), 1, 12, 6)
	var btn_f := box(Color(0, 0, 0, 0), 6, PRIMARY_HI, 1, 12, 6)
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

	# 主要操作ボタン ("AccentButton") — 安全なプライマリ操作には落ち着いたブルー
	th.add_type("AccentButton")
	th.set_type_variation("AccentButton", "Button")
	th.set_stylebox("normal", "AccentButton", box(PRIMARY, 6, PRIMARY_HI, 1, 14, 7))
	th.set_stylebox("hover", "AccentButton", box(PRIMARY_HI, 6, Color("#7aadff"), 1, 14, 7))
	th.set_stylebox("pressed", "AccentButton", box(PRIMARY_LO, 6, PRIMARY, 1, 14, 7))
	th.set_color("font_color", "AccentButton", Color.WHITE)
	th.set_font("font", "AccentButton", sf_semi)

	# 危険操作ボタン ("DangerButton")
	th.add_type("DangerButton")
	th.set_type_variation("DangerButton", "Button")
	th.set_stylebox("normal", "DangerButton", box(DANGER_BG, 6, DANGER_BORDER, 1, 12, 6))
	th.set_stylebox("hover", "DangerButton", box(ACCENT, 6, ACCENT_HI, 1, 12, 6))
	th.set_stylebox("pressed", "DangerButton", box(ACCENT_LO, 6, ACCENT, 1, 12, 6))
	th.set_color("font_color", "DangerButton", DANGER_TEXT)
	th.set_color("font_hover_color", "DangerButton", Color.WHITE)
	th.set_color("font_pressed_color", "DangerButton", Color.WHITE)

	# モーション一覧ボタン ("AnimClipButton" + 男女別カラー)
	th.add_type("AnimClipButton")
	th.set_type_variation("AnimClipButton", "Button")
	th.set_stylebox("normal", "AnimClipButton", box(Color(0, 0, 0, 0), 5, Color(), 0, 10, 5))
	th.set_stylebox("hover", "AnimClipButton", box(BG_3, 5, LINE, 1, 10, 5))
	th.set_stylebox("pressed", "AnimClipButton", box(Color("#3a161b"), 5, ACCENT, 1, 10, 5))
	th.set_stylebox("hover_pressed", "AnimClipButton", box(Color("#471b21"), 5, ACCENT_HI, 1, 10, 5))
	th.set_color("font_color", "AnimClipButton", TEXT)
	th.set_color("font_hover_color", "AnimClipButton", Color.WHITE)
	th.set_color("font_pressed_color", "AnimClipButton", Color.WHITE)
	th.set_color("font_hover_pressed_color", "AnimClipButton", Color.WHITE)

	for pair in [
		["AnimClipButtonFemale", Color("#17131a"), Color("#281a24"), Color("#e06c9f")],
		["AnimClipButtonMale", Color("#12161f"), Color("#1a2434"), Color("#58a6ff")],
	]:
		var vname: String = pair[0]
		var vbg: Color = pair[1]
		var vhbg: Color = pair[2]
		var vbar: Color = pair[3]
		th.add_type(vname)
		th.set_type_variation(vname, "AnimClipButton")
		var sn := box(vbg, 5, Color(), 0, 10, 5)
		sn.border_color = vbar
		sn.border_width_left = 3
		var sh := box(vhbg, 5, Color(), 0, 10, 5)
		sh.border_color = vbar
		sh.border_width_left = 3
		th.set_stylebox("normal", vname, sn)
		th.set_stylebox("hover", vname, sh)
		th.set_color("font_color", vname, TEXT)
		th.set_color("font_hover_color", vname, Color.WHITE)

	# 折りたたみヘッダーボタン ("CollapsibleHeader")
	th.add_type("CollapsibleHeader")
	th.set_type_variation("CollapsibleHeader", "Button")
	th.set_stylebox("normal", "CollapsibleHeader", box(Color(0, 0, 0, 0), 5, Color(), 0, 4, 2))
	th.set_stylebox("hover", "CollapsibleHeader", box(Color(1, 1, 1, 0.04), 5, Color(), 0, 4, 2))
	th.set_stylebox("pressed", "CollapsibleHeader", box(Color(1, 1, 1, 0.06), 5, Color(), 0, 4, 2))
	th.set_stylebox("hover_pressed", "CollapsibleHeader", box(Color(1, 1, 1, 0.06), 5, Color(), 0, 4, 2))

	# サイドバー項目 ("NavButton")
	th.add_type("NavButton")
	th.set_type_variation("NavButton", "Button")
	var nav_n := box(Color(0, 0, 0, 0), 6, Color(), 0, 12, 6)
	var nav_h := box(Color("#1d2028"), 6, Color(), 0, 12, 6)
	var nav_p := box(Color("#2a1417"), 6, Color(), 0, 12, 6)
	nav_p.border_color = ACCENT
	nav_p.border_width_left = 3
	var nav_f := box(Color(0, 0, 0, 0), 6, Color(PRIMARY_HI, 0.75), 1, 12, 6)
	th.set_stylebox("normal", "NavButton", nav_n)
	th.set_stylebox("hover", "NavButton", nav_h)
	th.set_stylebox("pressed", "NavButton", nav_p)
	th.set_stylebox("hover_pressed", "NavButton", nav_p)
	th.set_stylebox("focus", "NavButton", nav_f)
	th.set_color("font_color", "NavButton", TEXT_DIM)
	th.set_color("font_hover_color", "NavButton", TEXT)
	th.set_color("font_pressed_color", "NavButton", Color.WHITE)
	th.set_color("font_hover_pressed_color", "NavButton", Color.WHITE)
	th.set_constant("h_separation", "NavButton", 10)

	# --- 入力欄 ---
	var le_n := box(BG_0, 6, LINE, 1, 8, 5)
	var le_f := box(BG_0, 6, PRIMARY_HI, 1, 8, 5)
	for t in ["LineEdit", "TextEdit", "SpinBox"]:
		th.set_stylebox("normal", t, le_n)
		th.set_stylebox("focus", t, le_f)
		th.set_stylebox("read_only", t, box(BG_1, 6, LINE, 1, 8, 5))
		th.set_color("font_color", t, TEXT)
		th.set_color("caret_color", t, PRIMARY_HI)
		th.set_color("selection_color", t, Color(PRIMARY, 0.45))
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
	th.set_icon("checked_disabled", "CheckBox", _check_tex(true, false, true))
	th.set_icon("unchecked_disabled", "CheckBox", _check_tex(false, false, true))
	th.set_icon("radio_checked", "CheckBox", _circle_tex(18, Color.WHITE, ACCENT, 5.0))
	th.set_icon("radio_unchecked", "CheckBox", _circle_tex(18, BG_2, Color("#4a505c"), 1.5))
	th.set_icon("checked", "CheckButton", _toggle_tex(true))
	th.set_icon("unchecked", "CheckButton", _toggle_tex(false))
	th.set_icon("checked_disabled", "CheckButton", _toggle_tex(true, true))
	th.set_icon("unchecked_disabled", "CheckButton", _toggle_tex(false, true))
	var chk_focus := box(Color(0, 0, 0, 0), 5, Color(PRIMARY_HI, 0.75), 1, 2, 3)
	for t in ["CheckBox", "CheckButton"]:
		var e := StyleBoxEmpty.new()
		e.content_margin_top = 3
		e.content_margin_bottom = 3
		th.set_stylebox("normal", t, e)
		th.set_stylebox("pressed", t, e)
		th.set_stylebox("hover", t, box(Color(1, 1, 1, 0.03), 5, Color(), 0, 2, 3))
		th.set_stylebox("hover_pressed", t, box(Color(1, 1, 1, 0.03), 5, Color(), 0, 2, 3))
		th.set_stylebox("focus", t, chk_focus)
		th.set_color("font_hover_color", t, Color.WHITE)
		th.set_color("font_pressed_color", t, TEXT)
		th.set_color("font_hover_pressed_color", t, Color.WHITE)
		th.set_color("font_disabled_color", t, TEXT_MUTED)
		th.set_constant("h_separation", t, 8)

	# --- タブ ---
	th.set_stylebox("panel", "TabContainer", box(BG_1, 0, Color(), 0, 0, 0))
	th.set_stylebox("tab_selected", "TabContainer", box(BG_2, 6, ACCENT, 0, 12, 6))
	th.set_stylebox("tab_unselected", "TabContainer", box(Color(0, 0, 0, 0), 6, Color(), 0, 12, 6))
	th.set_stylebox("tab_hovered", "TabContainer", box(BG_3, 6, Color(), 0, 12, 6))
	th.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())

	# --- リスト / ポップアップ ---
	th.set_stylebox("panel", "ItemList", box(BG_0, 6, LINE, 1, 4, 4))
	th.set_stylebox("focus", "ItemList", box(Color(0, 0, 0, 0), 6, Color(PRIMARY_HI, 0.75), 1, 4, 4))
	th.set_stylebox("selected", "ItemList", box(Color("#3a1518"), 4, Color(), 0, 4, 2))
	th.set_stylebox("selected_focus", "ItemList", box(Color("#4a171b"), 4, ACCENT, 0, 4, 2))
	th.set_stylebox("hovered", "ItemList", box(BG_3, 4, Color(), 0, 4, 2))
	th.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	th.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	th.set_color("font_color", "ItemList", TEXT_DIM)
	th.set_color("font_selected_color", "ItemList", Color.WHITE)
	th.set_color("font_hovered_color", "ItemList", TEXT)
	th.set_constant("v_separation", "ItemList", 4)
	th.set_stylebox("panel", "PopupMenu", box(BG_2, 8, LINE_HI, 1, 6, 6))
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

	# --- 見出し・情報ラベル ---
	th.add_type("SectionLabel")
	th.set_type_variation("SectionLabel", "Label")
	th.set_color("font_color", "SectionLabel", Color.WHITE)
	th.set_font("font", "SectionLabel", sf_semi)
	th.set_font_size("font_size", "SectionLabel", 15)

	th.add_type("DimLabel")
	th.set_type_variation("DimLabel", "Label")
	th.set_color("font_color", "DimLabel", TEXT_DIM)
	th.set_font_size("font_size", "DimLabel", 13)

	th.add_type("MutedLabel")
	th.set_type_variation("MutedLabel", "Label")
	th.set_color("font_color", "MutedLabel", TEXT_MUTED)
	th.set_font_size("font_size", "MutedLabel", 12)

	th.add_type("ValueLabel")
	th.set_type_variation("ValueLabel", "Label")
	th.set_color("font_color", "ValueLabel", VALUE_TEXT)
	th.set_font("font", "ValueLabel", sf_mono)
	th.set_font_size("font_size", "ValueLabel", 12)

	th.add_type("TitleLabel")
	th.set_type_variation("TitleLabel", "Label")
	th.set_color("font_color", "TitleLabel", Color.WHITE)
	th.set_font("font", "TitleLabel", sf_bold)
	th.set_font_size("font_size", "TitleLabel", 20)

	th.add_type("NavTitleLabel")
	th.set_type_variation("NavTitleLabel", "Label")
	th.set_color("font_color", "NavTitleLabel", TEXT)
	th.set_font("font", "NavTitleLabel", sf_semi)
	th.set_font_size("font_size", "NavTitleLabel", 13)

	th.add_type("SubNavLabel")
	th.set_type_variation("SubNavLabel", "Label")
	th.set_color("font_color", "SubNavLabel", TEXT_MUTED)
	th.set_font_size("font_size", "SubNavLabel", 11)

	th.add_type("SidebarGroupLabel")
	th.set_type_variation("SidebarGroupLabel", "Label")
	th.set_color("font_color", "SidebarGroupLabel", TEXT_MUTED)
	th.set_font("font", "SidebarGroupLabel", sf_bold)
	th.set_font_size("font_size", "SidebarGroupLabel", 11)

	th.add_type("HelpMark")
	th.set_type_variation("HelpMark", "Label")
	th.set_color("font_color", "HelpMark", Color("#cfd5e2"))
	th.set_font_size("font_size", "HelpMark", 11)
	th.set_stylebox("normal", "HelpMark", box(Color("#262b35"), 9, Color("#565e6d"), 1, 0, 0))

	# --- コンテナ ---
	th.add_type("Card")
	th.set_type_variation("Card", "PanelContainer")
	th.set_stylebox("panel", "Card", box(BG_2, 8, LINE, 1, 16, 13))

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
