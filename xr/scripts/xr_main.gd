extends Node3D

## VRMViewer XR — Android XR (OpenXR) で VRM キャラクターを空間に配置し、
## 外部プログラム (WebSocket JSON-RPC / VMC) から動かす。
##
## ・パススルー (現実の部屋) の上にキャラクターを表示
## ・コントローラー/手のグリップ (握る) でキャラクターをつかんで移動、離すとこちらを向く
## ・キャラクターはユーザーの頭を目で追う
## ・ヘッドセットが無い PC でも平面カメラで起動するので、動作確認ができる

const VrmLoaderScript := preload("res://scripts/vrm/vrm_loader.gd")
const VrmaLoaderScript := preload("res://scripts/vrm/vrma_loader.gd")
const ProceduralIdleScript := preload("res://scripts/core/procedural_idle.gd")
const ControlServerScript := preload("res://scripts/xr_control_server.gd")

const ACCENT := Color("#c8252e")

var xr_interface: XRInterface = null
var xr_active: bool = false
var origin: XROrigin3D
var camera: XRCamera3D
var controllers: Array[XRController3D] = []
var avatar_root: Node3D
var current_vrm = null
var vrma_player
var procedural_idle
var server
var info_label: Label3D
var _info_until_msec: int = 0
var _grab_ctrl: XRController3D = null
var _grab_offset: Vector3 = Vector3.ZERO
var _face_user_on_release: bool = true
var _vmc_active: bool = false
var _http: HTTPRequest
var _pending_download: Dictionary = {}
var _last_animation: String = "idle"


func _ready() -> void:
	_setup_xr()
	_build_scene()
	vrma_player = VrmaLoaderScript.VrmaPlayer.new()
	procedural_idle = ProceduralIdleScript.new()
	_preload_animations()

	server = ControlServerScript.new()
	add_child(server)
	var st: Dictionary = server.start()
	server.rpc_request.connect(_on_rpc)

	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_download_done)

	_load_initial_model()
	_show_info(25.0)
	print("[xr] ws=%s vmc=%s xr=%s" % [st.get("ws"), st.get("vmc"), xr_active])


# ---------------------------------------------------------------------------
# XR 初期化 / シーン構築
# ---------------------------------------------------------------------------
func _setup_xr() -> void:
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface != null and xr_interface.is_initialized():
		xr_active = true
		var vp := get_viewport()
		vp.use_xr = true
		vp.transparent_bg = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_set_passthrough(true)


func _set_passthrough(enabled: bool) -> bool:
	if xr_interface == null:
		return false
	var modes: Array = xr_interface.get_supported_environment_blend_modes()
	if enabled and modes.has(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND):
		xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
		get_viewport().transparent_bg = true
		return true
	xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
	get_viewport().transparent_bg = false
	return false


func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0) if xr_active else Color("#15171c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.92, 0.93, 0.98)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.1
	add_child(sun)

	origin = XROrigin3D.new()
	add_child(origin)
	camera = XRCamera3D.new()
	camera.current = true
	camera.near = 0.05
	origin.add_child(camera)
	if not xr_active:
		camera.position = Vector3(0, 1.45, 0.4)
		camera.rotation_degrees = Vector3(-8, 0, 0)

	for tracker_name in ["left_hand", "right_hand"]:
		var c := XRController3D.new()
		c.tracker = tracker_name
		c.pose = "grip"
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.018
		sm.height = 0.036
		var mat := StandardMaterial3D.new()
		mat.albedo_color = ACCENT
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.material = mat
		mi.mesh = sm
		c.add_child(mi)
		origin.add_child(c)
		controllers.append(c)

	avatar_root = Node3D.new()
	avatar_root.name = "Avatar"
	avatar_root.position = Vector3(0, 0, -1.4)
	add_child(avatar_root)

	# 足元の円 (つかめる目印)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.36
	tm.outer_radius = 0.38
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(ACCENT, 0.7)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.material = rmat
	ring.mesh = tm
	ring.position.y = 0.005
	avatar_root.add_child(ring)

	info_label = Label3D.new()
	info_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	info_label.font_size = 28
	info_label.pixel_size = 0.0012
	info_label.outline_size = 8
	info_label.outline_modulate = Color(0, 0, 0, 0.85)
	info_label.modulate = Color.WHITE
	info_label.position = Vector3(0, 2.0, 0)
	avatar_root.add_child(info_label)


func _preload_animations() -> void:
	var dirs: Array[String] = ["res://assets/animations", "user://animations"]
	for sub in DirAccess.get_directories_at("res://assets/animations"):
		dirs.append("res://assets/animations".path_join(sub))
	for dir_path in dirs:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for fn in dir.get_files():
			if fn.ends_with(".vrma"):
				var loaded: Dictionary = VrmaLoaderScript.load_vrma(dir_path.path_join(fn), null)
				if loaded.get("ok", false):
					vrma_player.add_clip(loaded["clip"].name, loaded["clip"])


func _load_initial_model() -> void:
	var candidates: Array[String] = []
	var last := _read_last_model()
	if last != "":
		candidates.append(last)
	var d := DirAccess.open("res://assets/samples")
	if d != null:
		for fn in d.get_files():
			if fn.ends_with(".vrm"):
				candidates.append("res://assets/samples".path_join(fn))
	for p in candidates:
		if load_vrm(p).get("ok", false):
			return


# ---------------------------------------------------------------------------
# モデル / アニメーション
# ---------------------------------------------------------------------------
func load_vrm(path: String) -> Dictionary:
	var res: Dictionary = VrmLoaderScript.load_vrm(path, null)
	if not res.get("ok", false):
		return res
	if current_vrm != null:
		current_vrm.queue_free()
	current_vrm = res["runtime"]
	avatar_root.add_child(current_vrm)
	current_vrm.animation_player = vrma_player
	current_vrm.procedural_idle = procedural_idle
	current_vrm.lookat.mode = "camera"
	if vrma_player.has_clip(_last_animation):
		vrma_player.play(_last_animation, true, 1.0, 0.0)
	if not path.begins_with("res://"):
		_write_last_model(path)
	return {"ok": true, "model_info": current_vrm.get_model_info()}


func _read_last_model() -> String:
	var f := FileAccess.open("user://last_model.txt", FileAccess.READ)
	if f == null:
		return ""
	var p := f.get_as_text().strip_edges()
	return p if FileAccess.file_exists(p) else ""


func _write_last_model(p: String) -> void:
	var f := FileAccess.open("user://last_model.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(p)


func _download(url: String, kind: String, peer_id: int, id, extra: Dictionary) -> void:
	if not _pending_download.is_empty():
		server.send_error(peer_id, id, -32020, "別のダウンロードが進行中です")
		return
	var sub := "models" if kind == "vrm" else "animations"
	DirAccess.make_dir_recursive_absolute("user://" + sub)
	var fname := url.get_file().split("?")[0]
	if fname == "" or not (fname.ends_with(".vrm") or fname.ends_with(".vrma")):
		fname = "download." + kind
	var dest := "user://%s/%s" % [sub, fname]
	_http.download_file = dest
	_pending_download = {"peer": peer_id, "id": id, "kind": kind, "path": dest, "extra": extra}
	if _http.request(url) != OK:
		_pending_download = {}
		server.send_error(peer_id, id, -32021, "ダウンロードを開始できません")


func _on_download_done(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	var pd := _pending_download
	_pending_download = {}
	if pd.is_empty():
		return
	if result != HTTPRequest.RESULT_SUCCESS or code >= 400:
		server.send_error(pd.peer, pd.id, -32022, "ダウンロード失敗 (HTTP %d)" % code)
		return
	if pd.kind == "vrm":
		var r := load_vrm(pd.path)
		if r.get("ok", false):
			server.send_result(pd.peer, pd.id, r)
		else:
			server.send_error(pd.peer, pd.id, -32001, str(r.get("error", "load failed")))
	else:
		_rpc_load_vrma(pd.peer, pd.id, {"path": pd.path, "name": pd.extra.get("name", ""), "auto_play": pd.extra.get("auto_play", false)})


# ---------------------------------------------------------------------------
# 毎フレーム
# ---------------------------------------------------------------------------
func _process(_delta: float) -> void:
	if current_vrm != null:
		current_vrm.lookat_world_target = camera.global_position
		_apply_vmc()
	_update_grab()
	if info_label.visible and _info_until_msec > 0 and Time.get_ticks_msec() > _info_until_msec:
		info_label.visible = false
	elif info_label.visible:
		info_label.text = _info_text()


func _apply_vmc() -> void:
	var fresh: bool = server.vmc_last_msec > 0 and Time.get_ticks_msec() - server.vmc_last_msec < 1500
	if fresh:
		_vmc_active = true
		for b in server.vmc_bones.keys():
			current_vrm.vmc_bone_overrides[b] = server.vmc_bones[b]
		if server.vmc_root_pos != null:
			current_vrm.vmc_hips_offset = server.vmc_root_pos
			current_vrm.has_vmc_hips_offset = true
		if server.vmc_blend_dirty:
			server.vmc_blend_dirty = false
			current_vrm.expressions.set_weights(server.vmc_blends.duplicate(), 0.0, false)
	elif _vmc_active:
		_vmc_active = false
		server.vmc_bones.clear()
		server.vmc_root_pos = null
		current_vrm.vmc_bone_overrides.clear()
		current_vrm.has_vmc_hips_offset = false


func _update_grab() -> void:
	if _grab_ctrl == null:
		for c in controllers:
			if c.get_is_active() and (c.get_float("grip") > 0.75 or c.is_button_pressed("grip_click")):
				var flat := Vector2(c.global_position.x - avatar_root.global_position.x, c.global_position.z - avatar_root.global_position.z)
				if flat.length() < 0.8:
					_grab_ctrl = c
					_grab_offset = avatar_root.global_position - c.global_position
					break
	else:
		if not (_grab_ctrl.get_float("grip") > 0.5 or _grab_ctrl.is_button_pressed("grip_click")):
			_grab_ctrl = null
			if _face_user_on_release:
				face_user()
			return
		var p := _grab_ctrl.global_position + _grab_offset
		avatar_root.global_position = Vector3(p.x, avatar_root.global_position.y, p.z)


func face_user() -> void:
	var to_user := camera.global_position - avatar_root.global_position
	to_user.y = 0.0
	if to_user.length() > 0.01:
		# モデルは +Z を向いている
		avatar_root.rotation.y = atan2(to_user.x, to_user.z)


func place_in_front(distance: float) -> void:
	var fwd := -camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3(0, 0, -1)
	var p := camera.global_position + fwd * distance
	avatar_root.global_position = Vector3(p.x, origin.global_position.y, p.z)
	face_user()


# ---------------------------------------------------------------------------
# 情報表示
# ---------------------------------------------------------------------------
func _local_ips() -> String:
	var ips: Array[String] = []
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254"):
			ips.append(ip)
	return ", ".join(ips) if not ips.is_empty() else "(ネットワーク未接続)"


func _info_text() -> String:
	return "VRMViewer XR\n%s\nWS :%d  /  VMC :%d\n接続中 %d   %s" % [
		_local_ips(), server.ws_port, server.vmc_port, server.client_count(),
		"VMC受信中" if _vmc_active else "",
	]


func _show_info(seconds: float) -> void:
	info_label.visible = true
	info_label.text = _info_text()
	_info_until_msec = Time.get_ticks_msec() + int(seconds * 1000.0) if seconds > 0 else 0


# ---------------------------------------------------------------------------
# JSON-RPC
# ---------------------------------------------------------------------------
func _on_rpc(peer_id: int, id, method: String, params: Dictionary) -> void:
	match method:
		"ping":
			server.send_result(peer_id, id, {"pong": true, "app": "VRMViewer XR", "xr": xr_active})
		"get_state":
			server.send_result(peer_id, id, get_state())
		"load_vrm":
			if params.has("url"):
				_download(str(params["url"]), "vrm", peer_id, id, {})
				return
			var r := load_vrm(str(params.get("path", "")))
			if r.get("ok", false):
				server.send_result(peer_id, id, r)
			else:
				server.send_error(peer_id, id, -32001, str(r.get("error", "load failed")))
		"load_vrma":
			if params.has("url"):
				_download(str(params["url"]), "vrma", peer_id, id, params)
				return
			_rpc_load_vrma(peer_id, id, params)
		"play_animation":
			var nm := str(params.get("name", ""))
			if not vrma_player.has_clip(nm):
				server.send_error(peer_id, id, -32602, "Unknown animation: " + nm)
				return
			_last_animation = nm
			vrma_player.play(nm, bool(params.get("looping", true)), float(params.get("speed", 1.0)), float(params.get("blend_sec", 0.25)))
			server.send_result(peer_id, id, {"ok": true})
		"stop_animation":
			vrma_player.stop()
			server.send_result(peer_id, id, {"ok": true})
		"set_expression":
			if current_vrm != null:
				current_vrm.expressions.set_weights({str(params.get("name", "")): float(params.get("weight", 0.0))}, float(params.get("transition_sec", 0.0)), false)
			server.send_result(peer_id, id, {"ok": true})
		"set_expressions":
			if current_vrm != null:
				current_vrm.expressions.set_weights(params.get("weights", {}), float(params.get("transition_sec", 0.0)), bool(params.get("reset_others", false)))
			server.send_result(peer_id, id, {"ok": true})
		"reset_expressions":
			if current_vrm != null:
				current_vrm.expressions.reset_all(float(params.get("transition_sec", 0.0)))
			server.send_result(peer_id, id, {"ok": true})
		"set_lookat":
			if current_vrm != null:
				if params.has("mode"):
					current_vrm.lookat.mode = str(params["mode"])
				var t = params.get("target", null)
				if typeof(t) == TYPE_ARRAY and t.size() >= 3:
					current_vrm.lookat.manual_target = Vector3(float(t[0]), float(t[1]), float(t[2]))
			server.send_result(peer_id, id, {"ok": true})
		"set_bones":
			_rpc_set_bones(params)
			server.send_result(peer_id, id, {"ok": true})
		"reset_bones":
			if current_vrm != null:
				current_vrm.direct_bone_overrides.clear()
				current_vrm.has_direct_hips_offset = false
			server.send_result(peer_id, id, {"ok": true})
		"set_avatar_transform":
			_rpc_set_transform(params)
			server.send_result(peer_id, id, get_state()["avatar"])
		"place_in_front":
			place_in_front(float(params.get("distance", 1.4)))
			server.send_result(peer_id, id, get_state()["avatar"])
		"face_user":
			face_user()
			server.send_result(peer_id, id, {"ok": true})
		"set_passthrough":
			server.send_result(peer_id, id, {"ok": true, "passthrough": _set_passthrough(bool(params.get("enabled", true)))})
		"show_info":
			if bool(params.get("visible", true)):
				_show_info(float(params.get("seconds", 0.0)))
			else:
				info_label.visible = false
			server.send_result(peer_id, id, {"ok": true})
		_:
			server.send_error(peer_id, id, -32601, "Method not found: " + method)


func _rpc_load_vrma(peer_id: int, id, params: Dictionary) -> void:
	var res: Dictionary = VrmaLoaderScript.load_vrma(str(params.get("path", "")), null, str(params.get("name", "")))
	if not res.get("ok", false):
		server.send_error(peer_id, id, -32003, str(res.get("error", "load failed")))
		return
	var clip = res["clip"]
	vrma_player.add_clip(clip.name, clip)
	if bool(params.get("auto_play", false)):
		_last_animation = clip.name
		vrma_player.play(clip.name, true, 1.0, 0.25)
	server.send_result(peer_id, id, {"ok": true, "name": clip.name})


func _rpc_set_bones(params: Dictionary) -> void:
	if current_vrm == null:
		return
	if bool(params.get("clear_others", false)):
		current_vrm.direct_bone_overrides.clear()
	var bones: Dictionary = params.get("bones", {})
	for bname in bones.keys():
		var spec: Dictionary = bones[bname]
		if typeof(spec.get("quat_xyzw", null)) == TYPE_ARRAY and spec["quat_xyzw"].size() >= 4:
			var q: Array = spec["quat_xyzw"]
			current_vrm.direct_bone_overrides[str(bname)] = Quaternion(float(q[0]), float(q[1]), float(q[2]), float(q[3])).normalized()
		elif typeof(spec.get("euler_deg", null)) == TYPE_ARRAY and spec["euler_deg"].size() >= 3:
			var e: Array = spec["euler_deg"]
			current_vrm.direct_bone_overrides[str(bname)] = Quaternion.from_euler(Vector3(deg_to_rad(float(e[0])), deg_to_rad(float(e[1])), deg_to_rad(float(e[2]))))
	var hp = params.get("hips_position", null)
	if typeof(hp) == TYPE_ARRAY and hp.size() >= 3:
		current_vrm.direct_hips_offset = Vector3(float(hp[0]), float(hp[1]), float(hp[2]))
		current_vrm.has_direct_hips_offset = true


func _rpc_set_transform(params: Dictionary) -> void:
	var p = params.get("position", null)
	if typeof(p) == TYPE_ARRAY and p.size() >= 3:
		avatar_root.global_position = origin.global_position + Vector3(float(p[0]), float(p[1]), float(p[2]))
	if params.has("rotation_y_deg"):
		avatar_root.rotation.y = deg_to_rad(float(params["rotation_y_deg"]))
	if params.has("scale"):
		var s := clampf(float(params["scale"]), 0.05, 20.0)
		avatar_root.scale = Vector3(s, s, s)
	if params.has("face_user_on_release"):
		_face_user_on_release = bool(params["face_user_on_release"])


func get_state() -> Dictionary:
	var ap := avatar_root.global_position - origin.global_position
	return {
		"app": "VRMViewer XR",
		"xr_active": xr_active,
		"model_loaded": current_vrm != null,
		"model_info": current_vrm.get_model_info() if current_vrm != null else {},
		"available_animations": vrma_player.get_clip_names(),
		"animation": _last_animation,
		"vmc_active": _vmc_active,
		"avatar": {"position": [ap.x, ap.y, ap.z], "rotation_y_deg": rad_to_deg(avatar_root.rotation.y), "scale": avatar_root.scale.x},
		"user_head": [camera.global_position.x, camera.global_position.y, camera.global_position.z],
		"ws_port": server.ws_port,
		"vmc_port": server.vmc_port,
		"ips": _local_ips(),
	}
