class_name CameraRig
extends Node3D

## Orbit / Pan / Zoom camera rig supporting perspective & orthographic modes,
## framing presets, mouse interaction, Alt+drag mascot window moving,
## and synchronization with an optional Output SubViewport Camera3D.

signal camera_changed
signal right_clicked(local_pos: Vector2)

var yaw_deg: float = 0.0
var pitch_deg: float = 6.0
var distance: float = 2.2
var target: Vector3 = Vector3(0.0, 0.95, 0.0)
var fov_deg: float = 35.0
var orthographic: bool = false

var main_camera: Camera3D
var output_camera: Camera3D

var _dragging_orbit: bool = false
var _dragging_pan: bool = false
var _dragging_window: bool = false
var _last_mouse: Vector2 = Vector2.ZERO
var _drag_win_offset: Vector2i = Vector2i.ZERO
var _rmb_down: bool = false
var _rmb_press_pos: Vector2 = Vector2.ZERO
var _rmb_dragged: bool = false
var input_enabled: bool = true


func setup(p_main_cam: Camera3D, p_output_cam: Camera3D = null) -> void:
	main_camera = p_main_cam
	output_camera = p_output_cam
	_apply_transform()


func apply_params(params: Dictionary) -> void:
	if params.has("preset") and params["preset"] != null:
		apply_preset(str(params["preset"]))
	if params.has("yaw_deg") and params["yaw_deg"] != null:
		yaw_deg = float(params["yaw_deg"])
	if params.has("pitch_deg") and params["pitch_deg"] != null:
		pitch_deg = clampf(float(params["pitch_deg"]), -85.0, 85.0)
	if params.has("distance") and params["distance"] != null:
		distance = clampf(float(params["distance"]), 0.25, 20.0)
	if params.has("target") and typeof(params["target"]) == TYPE_ARRAY and params["target"].size() >= 3:
		var t: Array = params["target"]
		target = Vector3(float(t[0]), float(t[1]), float(t[2]))
	if params.has("fov_deg") and params["fov_deg"] != null:
		fov_deg = clampf(float(params["fov_deg"]), 10.0, 110.0)
	if params.has("orthographic") and params["orthographic"] != null:
		orthographic = bool(params["orthographic"])
	_apply_transform()
	camera_changed.emit()


func apply_preset(preset: String, model_height: float = 1.6) -> void:
	var h := clampf(model_height, 0.5, 3.0)
	match preset:
		"full_body":
			yaw_deg = 0.0
			pitch_deg = 5.0
			distance = h * 1.45
			target = Vector3(0.0, h * 0.52, 0.0)
		"bust":
			yaw_deg = 0.0
			pitch_deg = 5.0
			distance = h * 0.65
			target = Vector3(0.0, h * 0.78, 0.0)
		"face":
			yaw_deg = 0.0
			pitch_deg = 3.0
			distance = h * 0.35
			target = Vector3(0.0, h * 0.88, 0.0)
		"back":
			yaw_deg = 180.0
			pitch_deg = 6.0
			distance = h * 1.45
			target = Vector3(0.0, h * 0.52, 0.0)
		"left":
			yaw_deg = 90.0
			pitch_deg = 5.0
			distance = h * 1.45
			target = Vector3(0.0, h * 0.52, 0.0)
		"right":
			yaw_deg = -90.0
			pitch_deg = 5.0
			distance = h * 1.45
			target = Vector3(0.0, h * 0.52, 0.0)
		"top_down":
			yaw_deg = 0.0
			pitch_deg = 70.0
			distance = h * 1.5
			target = Vector3(0.0, h * 0.52, 0.0)
	_apply_transform()
	camera_changed.emit()


func auto_frame(bounds: AABB) -> void:
	var height := maxf(bounds.size.y, 0.6)
	var center := bounds.position + bounds.size * 0.52
	target = Vector3(center.x, center.y, center.z)
	distance = clampf(height * 1.45, 0.8, 10.0)
	yaw_deg = 0.0
	pitch_deg = 6.0
	_apply_transform()
	camera_changed.emit()


func to_dict() -> Dictionary:
	return {
		"yaw_deg": yaw_deg,
		"pitch_deg": pitch_deg,
		"distance": distance,
		"target": [target.x, target.y, target.z],
		"fov_deg": fov_deg,
		"orthographic": orthographic,
	}


func get_camera_world_position() -> Vector3:
	return main_camera.global_position if main_camera != null else Vector3(0.0, 1.4, 2.2)


func handle_input(event: InputEvent) -> bool:
	if not input_enabled:
		return false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and mb.alt_pressed:
				_dragging_window = true
				_drag_win_offset = Vector2i(DisplayServer.mouse_get_position()) - DisplayServer.window_get_position()
				return true
			elif mb.pressed and mb.shift_pressed:
				_dragging_pan = true
				_last_mouse = mb.position
				return true
			elif mb.pressed:
				_dragging_orbit = true
				_last_mouse = mb.position
				return true
			else:
				_dragging_orbit = false
				_dragging_pan = false
				_dragging_window = false
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_dragging_pan = true
				_last_mouse = mb.position
				return true
			else:
				_dragging_pan = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_rmb_down = true
				_rmb_press_pos = mb.position
				_rmb_dragged = false
				_last_mouse = mb.position
				return true
			else:
				var emit_ctx: bool = _rmb_down and not _rmb_dragged
				_rmb_down = false
				_rmb_dragged = false
				_dragging_orbit = false
				if emit_ctx:
					right_clicked.emit(mb.position)
				return true
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			distance = clampf(distance * 0.9, 0.25, 20.0)
			_apply_transform()
			camera_changed.emit()
			return true
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			distance = clampf(distance * 1.11, 0.25, 20.0)
			_apply_transform()
			camera_changed.emit()
			return true

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _rmb_down and not _rmb_dragged and mm.position.distance_to(_rmb_press_pos) >= 6.0:
			_rmb_dragged = true
			_dragging_orbit = true
			_last_mouse = mm.position
		if _dragging_window:
			var cur := Vector2i(DisplayServer.mouse_get_position())
			DisplayServer.window_set_position(cur - _drag_win_offset)
			return true
		if _dragging_orbit:
			var d := mm.position - _last_mouse
			_last_mouse = mm.position
			yaw_deg = wrapf(yaw_deg - d.x * 0.35, -180.0, 180.0)
			pitch_deg = clampf(pitch_deg + d.y * 0.35, -85.0, 85.0)
			_apply_transform()
			camera_changed.emit()
			return true
		if _dragging_pan and main_camera != null:
			var d := mm.position - _last_mouse
			_last_mouse = mm.position
			var pan_scale := distance * 0.0014
			var basis := main_camera.global_transform.basis
			target -= basis.x * (d.x * pan_scale)
			target += basis.y * (d.y * pan_scale)
			_apply_transform()
			camera_changed.emit()
			return true
	return false


func _apply_transform() -> void:
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	var cos_p := cos(pitch)
	var offset := Vector3(
		sin(yaw) * cos_p * distance,
		sin(pitch) * distance,
		cos(yaw) * cos_p * distance
	)
	var cam_pos := target + offset
	for cam in [main_camera, output_camera]:
		if cam == null:
			continue
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL if orthographic else Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = fov_deg
		cam.size = distance * 0.72
		cam.near = 0.02
		cam.far = 100.0
		if cam.is_inside_tree():
			cam.look_at_from_position(cam_pos, target, Vector3.UP)
		else:
			var xf := Transform3D(Basis(), cam_pos).looking_at(target, Vector3.UP)
			cam.transform = xf
