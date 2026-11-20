class_name LightDirectionPad
extends Control

## Interactive polar light-direction pad showing viewer-relative Key/Fill/Rim
## positions on a hemisphere plus a live shaded preview sphere in the center.

signal direction_changed(azimuth_deg: float, elevation_deg: float)

var azimuth_deg: float = 35.0
var elevation_deg: float = 30.0
var key_color: Color = Color("#fff8f0")
var fill_color: Color = Color("#dce8ff")
var ambient_energy: float = 0.45
var _dragging: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(204, 204)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "ドラッグして Key ライトの方向（前後・左右・高さ）を設定"


func set_values(az_deg: float, el_deg: float, p_key_col: Color, p_fill_col: Color, p_amb_en: float) -> void:
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
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_update_from_pos(mm.position)


func _update_from_pos(pos: Vector2) -> void:
	var c := size * 0.5
	var max_r := maxf(minf(size.x, size.y) * 0.5 - 24.0, 20.0)
	var d := pos - c
	var dist := d.length()
	var az: float = azimuth_deg
	if dist > 2.0:
		az = wrapf(rad_to_deg(atan2(d.x, d.y)), -180.0, 180.0)
	var ratio: float = clampf(dist / max_r, 0.0, 1.0)
	var el: float = snappedf((1.0 - ratio) * 85.0, 1.0)
	az = snappedf(az, 1.0)
	azimuth_deg = az
	elevation_deg = el
	queue_redraw()
	direction_changed.emit(az, el)


func _draw() -> void:
	var c := size * 0.5
	var max_r := maxf(minf(size.x, size.y) * 0.5 - 24.0, 20.0)
	var font: Font = get_theme_default_font()
	var fsz: int = 12

	# Outer dark disk
	draw_circle(c, max_r + 3.0, Color("#0e0f12"))
	draw_arc(c, max_r, 0.0, TAU, 64, Color("#4a505c"), 1.5)
	draw_arc(c, max_r * (45.0 / 85.0), 0.0, TAU, 48, Color("#2f333d"), 1.0)

	# Crosshairs
	draw_line(c + Vector2(-max_r, 0), c + Vector2(max_r, 0), Color("#2f333d"), 1.0)
	draw_line(c + Vector2(0, -max_r), c + Vector2(0, max_r), Color("#2f333d"), 1.0)

	# Cardinal labels (viewer-relative)
	if font != null:
		draw_string(font, c + Vector2(-12, -max_r - 7), "後ろ", HORIZONTAL_ALIGNMENT_CENTER, -1, fsz, Color("#9aa0ab"))
		draw_string(font, c + Vector2(-18, max_r + 15), "正面・前", HORIZONTAL_ALIGNMENT_CENTER, -1, fsz, Color("#e2404a"))
		draw_string(font, c + Vector2(-max_r - 20, 4), "左", HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color("#9aa0ab"))
		draw_string(font, c + Vector2(max_r + 7, 4), "右", HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color("#9aa0ab"))

	# Center mini shaded sphere preview (2D ray-traced circle for immediate lighting intuition)
	var sph_r: float = 20.0
	var az_r: float = deg_to_rad(azimuth_deg)
	var el_r: float = deg_to_rad(elevation_deg)
	var light_dir := Vector3(
		cos(el_r) * sin(az_r),
		sin(el_r),
		cos(el_r) * cos(az_r)
	).normalized()
	for py in range(-int(sph_r), int(sph_r) + 1, 2):
		for px in range(-int(sph_r), int(sph_r) + 1, 2):
			var nx: float = float(px) / sph_r
			var ny: float = float(-py) / sph_r
			var rr: float = nx * nx + ny * ny
			if rr <= 1.0:
				var nz: float = sqrt(maxf(0.0, 1.0 - rr))
				var nrm := Vector3(nx, ny, nz)
				var ndotl: float = clampf(nrm.dot(light_dir), 0.0, 1.0)
				var toon_t: float = smoothstep(-0.08, 0.16, nrm.dot(light_dir))
				var lit_c: Color = Color(0.95, 0.96, 1.0) * key_color * clampf(0.35 + 0.65 * ndotl, 0.0, 1.0)
				var shd_c: Color = fill_color * clampf(0.22 + 0.35 * ambient_energy, 0.15, 0.75)
				var col: Color = shd_c.lerp(lit_c, toon_t)
				col.a = 1.0
				draw_rect(Rect2(c + Vector2(px, py), Vector2(2.2, 2.2)), col)
	draw_arc(c, sph_r, 0.0, TAU, 32, Color("#626875"), 1.2)

	# Secondary Fill & Rim markers (reference)
	var fill_az := deg_to_rad(azimuth_deg - 110.0)
	var fill_pos := c + Vector2(sin(fill_az), cos(fill_az)) * (max_r * 0.82)
	draw_circle(fill_pos, 4.5, Color(fill_color.r, fill_color.g, fill_color.b, 0.75))

	var rim_az := deg_to_rad(azimuth_deg + 165.0)
	var rim_pos := c + Vector2(sin(rim_az), cos(rim_az)) * (max_r * 0.86)
	draw_circle(rim_pos, 4.0, Color(0.95, 0.95, 1.0, 0.6))

	# Primary Key Light sun marker + ray line
	var clamped_el: float = clampf(elevation_deg, 0.0, 85.0)
	var key_dist: float = max_r * (1.0 - clamped_el / 85.0)
	var key_pos: Vector2 = c + Vector2(sin(az_r), cos(az_r)) * key_dist
	draw_line(key_pos, c, Color(key_color.r, key_color.g, key_color.b, 0.65), 2.0)

	var is_below: bool = elevation_deg < 0.0
	var ring_col: Color = Color("#9aa0ab") if is_below else Color("#e2404a")
	draw_circle(key_pos, 9.0, ring_col)
	draw_circle(key_pos, 5.5, Color(key_color.r, key_color.g, key_color.b, 1.0))
	draw_arc(key_pos, 9.0, 0.0, TAU, 20, Color(0.05, 0.08, 0.12), 1.5)
