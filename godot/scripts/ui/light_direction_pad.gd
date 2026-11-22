class_name LightDirectionPad
extends Control

## Interactive polar light-direction pad showing viewer-relative Key/Fill/Rim
## positions on a hemisphere (plus outer ring down to -45°) and a cached shaded preview sphere.

signal direction_changed(azimuth_deg: float, elevation_deg: float)

const UiThemeScript := preload("res://scripts/ui/ui_theme.gd")
const HelpMarkScript := preload("res://scripts/ui/help_mark.gd")

const HORIZON_RATIO := 0.78
const MIN_EL := -45.0
const MAX_EL := 85.0
const SPHERE_TEX_SIZE := 48

var azimuth_deg: float = 35.0
var elevation_deg: float = 30.0
var key_color: Color = Color("#fff8f0")
var fill_color: Color = Color("#dce8ff")
var ambient_energy: float = 0.45
var _dragging: bool = false
var _hover_part: String = ""

var _sphere_tex: ImageTexture = null
var _sphere_img: Image = null
var _sphere_key: String = ""


func _ready() -> void:
	custom_minimum_size = Vector2(204, 204)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "ドラッグして Key ライトの方向（前後・左右・高さ。外周は下から）を設定"
	mouse_exited.connect(func():
		if _hover_part != "":
			_hover_part = ""
			queue_redraw()
	)


func set_values(az_deg: float, el_deg: float, p_key_col: Color, p_fill_col: Color, p_amb_en: float) -> void:
	if is_equal_approx(azimuth_deg, az_deg) and is_equal_approx(elevation_deg, el_deg) \
			and key_color.is_equal_approx(p_key_col) and fill_color.is_equal_approx(p_fill_col) \
			and is_equal_approx(ambient_energy, p_amb_en):
		return
	azimuth_deg = az_deg
	elevation_deg = el_deg
	key_color = p_key_col
	fill_color = p_fill_col
	ambient_energy = p_amb_en
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_update_from_pos(mb.position)
			else:
				_dragging = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			_update_from_pos(mm.position)
		else:
			var hp := _hit_part(mm.position)
			if hp != _hover_part:
				_hover_part = hp
				queue_redraw()


func _calc_geom() -> Dictionary:
	var c := size * 0.5
	var max_r := maxf(minf(size.x, size.y) * 0.5 - 24.0, 20.0)
	var horizon_r := max_r * HORIZON_RATIO
	var fill_az := deg_to_rad(azimuth_deg - 110.0)
	var fill_pos := c + Vector2(sin(fill_az), cos(fill_az)) * (horizon_r * 0.85)
	var rim_az := deg_to_rad(azimuth_deg + 165.0)
	var rim_pos := c + Vector2(sin(rim_az), cos(rim_az)) * (horizon_r * 0.92)
	var az_r := deg_to_rad(azimuth_deg)
	var key_dist: float
	if elevation_deg >= 0.0:
		key_dist = horizon_r * (1.0 - clampf(elevation_deg, 0.0, MAX_EL) / MAX_EL)
	else:
		var neg_frac := clampf(-elevation_deg / absf(MIN_EL), 0.0, 1.0)
		key_dist = horizon_r + (max_r - horizon_r) * neg_frac
	var key_pos: Vector2 = c + Vector2(sin(az_r), cos(az_r)) * key_dist
	return {
		"c": c,
		"max_r": max_r,
		"horizon_r": horizon_r,
		"key_pos": key_pos,
		"fill_pos": fill_pos,
		"rim_pos": rim_pos,
	}


func _hit_part(pos: Vector2) -> String:
	var g := _calc_geom()
	if pos.distance_to(g["key_pos"]) <= 14.0:
		return "key"
	if pos.distance_to(g["fill_pos"]) <= 14.0:
		return "fill"
	if pos.distance_to(g["rim_pos"]) <= 14.0:
		return "rim"
	if pos.distance_to(g["c"]) <= 22.0:
		return "sphere"
	return ""


func _get_tooltip(at_position: Vector2) -> String:
	match _hit_part(at_position):
		"key":
			return "キーライト (主光源・赤丸)\nドラッグして照らす方向（前後・左右・高さ）を動かせます。"
		"fill":
			return "フィルライト (補助光・青白い点)\n影になった側を和らげる光。キーライトの約 -110° 側へ自動で連動します。"
		"rim":
			return "リムライト (輪郭光・白い点)\n髪や肩のフチを後ろから照らす光。キーライトの反対側 (+165°) へ自動で連動します。"
		"sphere":
			return "陰影プレビュー球\n現在の Key 色・Fill 色・環境光による陰影の簡易イメージです。"
		_:
			return "ドラッグして Key ライトの方向を設定（内側の円=水平、外周=下から、中心=真上）。\n点にカーソルを合わせると Key / Fill / Rim の説明が出ます。"


func _make_custom_tooltip(for_text: String) -> Object:
	return HelpMarkScript.make_tooltip_label(for_text, self)


func _update_from_pos(pos: Vector2) -> void:
	var c := size * 0.5
	var max_r := maxf(minf(size.x, size.y) * 0.5 - 24.0, 20.0)
	var d := pos - c
	var dist := d.length()
	var az: float = azimuth_deg
	if dist > 2.0:
		az = wrapf(rad_to_deg(atan2(d.x, d.y)), -180.0, 180.0)
	var ratio: float = clampf(dist / max_r, 0.0, 1.0)
	var el: float
	if ratio <= HORIZON_RATIO:
		el = (1.0 - ratio / HORIZON_RATIO) * MAX_EL
	else:
		el = -((ratio - HORIZON_RATIO) / (1.0 - HORIZON_RATIO)) * absf(MIN_EL)
	el = snappedf(clampf(el, MIN_EL, MAX_EL), 1.0)
	az = snappedf(az, 1.0)
	azimuth_deg = az
	elevation_deg = el
	queue_redraw()
	direction_changed.emit(az, el)


func _ensure_sphere_tex() -> ImageTexture:
	var k := "%.1f|%.1f|%s|%s|%.2f" % [azimuth_deg, elevation_deg, key_color.to_html(false), fill_color.to_html(false), ambient_energy]
	if _sphere_tex != null and k == _sphere_key:
		return _sphere_tex
	_sphere_key = k
	if _sphere_img == null:
		_sphere_img = Image.create(SPHERE_TEX_SIZE, SPHERE_TEX_SIZE, false, Image.FORMAT_RGBA8)
	var az_r: float = deg_to_rad(azimuth_deg)
	var el_r: float = deg_to_rad(elevation_deg)
	var light_dir := Vector3(
		cos(el_r) * sin(az_r),
		sin(el_r),
		cos(el_r) * cos(az_r)
	).normalized()
	var half := SPHERE_TEX_SIZE * 0.5
	var r := half - 1.5
	for py in SPHERE_TEX_SIZE:
		for px in SPHERE_TEX_SIZE:
			var nx: float = (px + 0.5 - half) / r
			var ny: float = -(py + 0.5 - half) / r
			var rr: float = nx * nx + ny * ny
			if rr <= 1.0:
				var nz: float = sqrt(maxf(0.0, 1.0 - rr))
				var nrm := Vector3(nx, ny, nz)
				var raw_dot: float = nrm.dot(light_dir)
				var ndotl: float = clampf(raw_dot, 0.0, 1.0)
				var toon_t: float = smoothstep(-0.08, 0.16, raw_dot)
				var lit_c: Color = Color(0.95, 0.96, 1.0) * key_color * clampf(0.35 + 0.65 * ndotl, 0.0, 1.0)
				var shd_c: Color = fill_color * clampf(0.22 + 0.35 * ambient_energy, 0.15, 0.75)
				var col: Color = shd_c.lerp(lit_c, toon_t)
				col.a = clampf((1.0 - sqrt(rr)) * r, 0.0, 1.0)
				_sphere_img.set_pixel(px, py, col)
			else:
				_sphere_img.set_pixel(px, py, Color(0, 0, 0, 0))
	if _sphere_tex == null:
		_sphere_tex = ImageTexture.create_from_image(_sphere_img)
	else:
		_sphere_tex.update(_sphere_img)
	return _sphere_tex


func _draw_centered_label(font: Font, center_pos: Vector2, text: String, fsz: int, col: Color) -> void:
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz)
	var asc := font.get_ascent(fsz)
	draw_string(font, Vector2(center_pos.x - sz.x * 0.5, center_pos.y + asc * 0.45), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, col)


func _draw() -> void:
	var g := _calc_geom()
	var c: Vector2 = g["c"]
	var max_r: float = g["max_r"]
	var horizon_r: float = g["horizon_r"]
	var fill_pos: Vector2 = g["fill_pos"]
	var rim_pos: Vector2 = g["rim_pos"]
	var key_pos: Vector2 = g["key_pos"]
	var font: Font = get_theme_default_font()
	var fsz: int = 12

	# Outer disk & elevation guides (horizon = HORIZON_RATIO, 45° ring, below-horizon ring)
	draw_circle(c, max_r + 3.0, UiThemeScript.BG_0)
	draw_arc(c, max_r, 0.0, TAU, 64, UiThemeScript.LINE, 1.2)
	draw_arc(c, horizon_r, 0.0, TAU, 64, UiThemeScript.LINE_HI, 1.5)
	draw_arc(c, horizon_r * (45.0 / MAX_EL), 0.0, TAU, 48, UiThemeScript.LINE, 1.0)

	# Crosshairs
	draw_line(c + Vector2(-max_r, 0), c + Vector2(max_r, 0), UiThemeScript.LINE, 1.0)
	draw_line(c + Vector2(0, -max_r), c + Vector2(0, max_r), UiThemeScript.LINE, 1.0)

	# Cardinal labels centered accurately
	if font != null:
		_draw_centered_label(font, c + Vector2(0, -max_r - 12), "後ろ", fsz, UiThemeScript.TEXT_DIM)
		_draw_centered_label(font, c + Vector2(0, max_r + 13), "正面・前", fsz, UiThemeScript.ACCENT_HI)
		_draw_centered_label(font, c + Vector2(-max_r - 12, 0), "左", fsz, UiThemeScript.TEXT_DIM)
		_draw_centered_label(font, c + Vector2(max_r + 12, 0), "右", fsz, UiThemeScript.TEXT_DIM)

	# Center mini shaded sphere preview (cached ImageTexture)
	var sph_r: float = 20.0
	var tex := _ensure_sphere_tex()
	draw_texture_rect(tex, Rect2(c - Vector2(sph_r, sph_r), Vector2(sph_r * 2.0, sph_r * 2.0)), false)
	draw_arc(c, sph_r, 0.0, TAU, 32, UiThemeScript.ACCENT_HI if _hover_part == "sphere" else UiThemeScript.LINE_HI, 1.4 if _hover_part == "sphere" else 1.2)

	# Secondary Fill & Rim markers (reference)
	if _hover_part == "fill":
		draw_arc(fill_pos, 8.0, 0.0, TAU, 20, fill_color, 1.6)
	draw_circle(fill_pos, 4.5, Color(fill_color.r, fill_color.g, fill_color.b, 0.85))

	if _hover_part == "rim":
		draw_arc(rim_pos, 7.5, 0.0, TAU, 20, Color.WHITE, 1.6)
	draw_circle(rim_pos, 4.0, Color(0.95, 0.95, 1.0, 0.7))

	# Primary Key Light sun marker + ray line
	draw_line(key_pos, c, Color(key_color.r, key_color.g, key_color.b, 0.65), 2.0)

	var is_below: bool = elevation_deg < 0.0
	var ring_col: Color = UiThemeScript.TEXT_DIM if is_below else UiThemeScript.ACCENT_HI
	draw_circle(key_pos, 9.5 if _hover_part == "key" else 9.0, ring_col)
	draw_circle(key_pos, 5.5, Color(key_color.r, key_color.g, key_color.b, 1.0))
	draw_arc(key_pos, 9.5 if _hover_part == "key" else 9.0, 0.0, TAU, 20, UiThemeScript.BG_0, 1.5)
