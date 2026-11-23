class_name CaptureManager
extends Node

## Manages PNG Screenshots (including base64 return for MCP), real-time FFmpeg recording,
## Spout2 (OBS), Virtual Camera (Discord/Zoom), and deterministic AI Timeline Sequencer.

signal capture_state_changed

const ConfigManagerScript := preload("res://scripts/core/config_manager.gd")

var bridge: Node
var output_viewport: SubViewport
var bg_manager
var camera_rig
var lighting_rig

var spout_enabled: bool = false
var spout_sender_name: String = "UtsushiMirror"
var vcam_enabled: bool = false
var recording_active: bool = false
var recording_format: String = "mp4"
var recording_fps: int = 60
var recording_path: String = ""
var screenshots_dir: String = "screenshots"
var recordings_dir: String = "recordings"

## 録画に、録画中に流したリップシンクの音を入れる (録画を止めた後に重ねる)
var record_lipsync_audio: bool = true
## リップシンク (lip_sync.gd)。app_controller が渡す
var lip_sync = null

var _record_elapsed: float = 0.0
var _frames_pushed: int = 0
var _audio_segs: Array = []  # {path, offset, start, end} (秒。start / end は録画の中の時間)
var _seg_open := {}
var _seg_session := -1
var _rec_lipsync_audio := true
var _sequencer_busy: bool = false
var _screenshot_busy: bool = false


func setup(p_bridge: Node, p_out_vp: SubViewport, p_bg_mgr, p_cam_rig, p_light_rig) -> void:
	bridge = p_bridge
	output_viewport = p_out_vp
	bg_manager = p_bg_mgr
	camera_rig = p_cam_rig
	lighting_rig = p_light_rig
	_refresh_viewport_update_mode()


func process_frame(delta: float) -> void:
	if _sequencer_busy or output_viewport == null:
		return
	var need_record := 0
	if recording_active and bridge != null:
		# 録画の時間を実際の時間に合わせる (遅れたら同じ絵を足して追いつく。音とずれないように)
		_record_elapsed += delta
		var due := int(_record_elapsed * float(recording_fps)) + 1 - _frames_pushed
		need_record = clampi(due, 0, 4)
		_track_lipsync()
	if not spout_enabled and not vcam_enabled and need_record == 0:
		return

	var tex := output_viewport.get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)

	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()

	if spout_enabled and bridge != null:
		bridge.send_spout_frame(w, h, data)
	if vcam_enabled and bridge != null:
		bridge.send_vcam_frame(w, h, data)
	if need_record > 0 and bridge != null:
		for i in range(need_record):
			if not bridge.push_recording_frame(data, false):
				break
			_frames_pushed += 1


## 録画の中の今の時間 (秒)
func _video_time() -> float:
	return float(_frames_pushed) / maxf(float(recording_fps), 1.0)


## リップシンクの区間を覚える (始まり・切り替わり・終わり)
func _track_lipsync() -> void:
	if lip_sync == null or not _rec_lipsync_audio:
		return
	var on: bool = lip_sync.active
	if not _seg_open.is_empty() and (not on or lip_sync.session != _seg_session):
		_close_seg()
	if on and _seg_open.is_empty():
		_seg_session = lip_sync.session
		_seg_open = {"path": str(lip_sync.path), "offset": float(lip_sync._t), "start": _video_time()}


func _close_seg() -> void:
	if _seg_open.is_empty():
		return
	_seg_open["end"] = _video_time()
	_audio_segs.append(_seg_open)
	_seg_open = {}


func capture_screenshot(params: Dictionary) -> Dictionary:
	if output_viewport == null:
		return {"ok": false, "error": "Output viewport unavailable"}
	if _sequencer_busy or _screenshot_busy:
		return {"ok": false, "error": "Capture already in progress"}
	_screenshot_busy = true

	var saved_out: Dictionary = bg_manager.output_to_dict() if bg_manager != null else {}
	var override_needed := params.has("transparent") or params.has("width") or params.has("height")
	if override_needed and bg_manager != null:
		var temp_cfg := {}
		if params.get("transparent", null) != null:
			temp_cfg["background_mode"] = "transparent" if bool(params["transparent"]) else "match_main"
		if params.get("width", null) != null:
			temp_cfg["width"] = int(params["width"])
		if params.get("height", null) != null:
			temp_cfg["height"] = int(params["height"])
		bg_manager.apply_output_viewport(temp_cfg)

	output_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw

	var img := output_viewport.get_texture().get_image()
	if img == null or img.is_empty():
		if override_needed and bg_manager != null:
			bg_manager.apply_output_viewport(saved_out)
		_refresh_viewport_update_mode()
		_screenshot_busy = false
		return {"ok": false, "error": "Failed to read viewport image"}

	var out_path := str(params.get("output_path", ""))
	if out_path == "":
		var ts := Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "").replace(" ", "_")
		out_path = screenshots_dir.path_join("vrm_" + ts + ".png")

	var abs_out := _resolve_output_path(out_path)
	DirAccess.make_dir_recursive_absolute(abs_out.get_base_dir())
	var err := img.save_png(abs_out)

	var result := {
		"ok": (err == OK),
		"path": abs_out,
		"width": img.get_width(),
		"height": img.get_height(),
	}
	if err != OK:
		result["error"] = "save_png failed: " + str(err)
	elif bool(params.get("return_base64", false)) and bridge != null:
		var png_bytes := img.save_png_to_buffer()
		result["base64_png"] = bridge.encode_png_base64(png_bytes)

	if override_needed and bg_manager != null:
		bg_manager.apply_output_viewport(saved_out)
	_refresh_viewport_update_mode()
	_screenshot_busy = false
	return result


func start_recording(params: Dictionary) -> Dictionary:
	if bridge == null:
		return {"ok": false, "error": "VrmBridge unavailable"}
	if output_viewport == null:
		return {"ok": false, "error": "Output viewport unavailable"}
	if recording_active:
		return {"ok": false, "error": "Already recording"}

	if bg_manager != null and (params.get("width", null) != null or params.get("height", null) != null):
		var vp_ovr := {}
		if params.get("width", null) != null:
			vp_ovr["width"] = int(params["width"])
		if params.get("height", null) != null:
			vp_ovr["height"] = int(params["height"])
		bg_manager.apply_output_viewport(vp_ovr)

	recording_format = str(params.get("format", "mp4"))
	recording_fps = clampi(int(params.get("fps", 60)), 1, 120)
	var ext := "webm" if recording_format == "webm_alpha" else "mp4"
	var out_path := str(params.get("output_path", ""))
	if out_path == "":
		var ts := Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "").replace(" ", "_")
		out_path = recordings_dir.path_join("vrm_" + ts + "." + ext)

	var abs_out := _resolve_output_path(out_path)
	DirAccess.make_dir_recursive_absolute(abs_out.get_base_dir())
	var w := output_viewport.size.x
	var h := output_viewport.size.y
	var res: Dictionary = bridge.start_recording(abs_out, w, h, recording_fps, recording_format, "", false)
	if res.get("ok", false):
		recording_active = true
		recording_path = abs_out
		_record_elapsed = 0.0
		_frames_pushed = 0
		_audio_segs.clear()
		_seg_open = {}
		_rec_lipsync_audio = bool(params.get("lipsync_audio", record_lipsync_audio))
		_refresh_viewport_update_mode()
		capture_state_changed.emit()
	return res


func stop_recording() -> Dictionary:
	if bridge == null or not recording_active:
		return {"ok": false, "error": "Not currently recording"}
	_close_seg()
	recording_active = false
	var res: Dictionary = bridge.stop_recording()
	if res.get("ok", false):
		res["path"] = str(res.get("output_path", recording_path))
		if not _audio_segs.is_empty():
			var mx := _mux_lipsync_audio(str(res["path"]))
			res["lipsync_audio"] = mx.get("ok", false)
			if not mx.get("ok", false):
				res["audio_error"] = str(mx.get("error", ""))
	_audio_segs.clear()
	_refresh_viewport_update_mode()
	capture_state_changed.emit()
	return res


## 録画中に流したリップシンクの音を、録画したファイルに重ねる
func _mux_lipsync_audio(video: String) -> Dictionary:
	var paths := PackedStringArray()
	var times := PackedFloat64Array()
	var total := _video_time()
	for s in _audio_segs:
		var st := float(s["start"])
		var en := minf(float(s["end"]), total)
		if en - st < 0.02:
			continue
		paths.append(str(s["path"]))
		times.append_array([float(s["offset"]), st, en])
	if paths.is_empty():
		return {"ok": true}
	return bridge.mux_recording_audio(video, paths, times, recording_format)


func set_spout(params: Dictionary) -> Dictionary:
	if bridge == null:
		return {"ok": false, "error": "VrmBridge unavailable"}
	var en := bool(params.get("enabled", false))
	var sname := str(params.get("sender_name", spout_sender_name))
	if sname == "":
		sname = "UtsushiMirror"
	var res: Dictionary = bridge.set_spout_enabled(en, sname)
	spout_enabled = bool(res.get("enabled", false))
	spout_sender_name = sname
	_refresh_viewport_update_mode()
	capture_state_changed.emit()
	return res


func set_vcam(params: Dictionary) -> Dictionary:
	if bridge == null:
		return {"ok": false, "available": false, "error": "VrmBridge unavailable"}
	var en := bool(params.get("enabled", false))
	var w := output_viewport.size.x if output_viewport != null else 1280
	var h := output_viewport.size.y if output_viewport != null else 720
	var res: Dictionary = bridge.set_vcam_enabled(en, w, h)
	vcam_enabled = bool(res.get("active", false))
	_refresh_viewport_update_mode()
	capture_state_changed.emit()
	return res


func get_vcam_status() -> Dictionary:
	if bridge == null or not bridge.has_method("get_vcam_status_json"):
		return {
			"available": false,
			"active": false,
			"backend": "none",
			"requires_admin_registration": true,
			"is_admin": false,
			"message": "VrmBridge unavailable",
		}
	var parsed = JSON.parse_string(str(bridge.get_vcam_status_json()))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func render_sequence(seq: Dictionary, app_ctrl) -> Dictionary:
	if bridge == null or output_viewport == null:
		return {"ok": false, "error": "Bridge or OutputViewport unavailable"}
	if _sequencer_busy or recording_active:
		return {"ok": false, "error": "Recorder/sequencer already running"}

	_sequencer_busy = true
	var fps: int = clampi(int(seq.get("fps", 60)), 1, 120)
	var width: int = clampi(int(seq.get("width", 1280)), 64, 3840)
	var height: int = clampi(int(seq.get("height", 720)), 64, 2160)
	var transparent: bool = bool(seq.get("transparent", false))
	var fmt: String = str(seq.get("format", "mp4"))
	var out_path := _resolve_output_path(str(seq.get("output_path", "recordings/sequence.mp4")))
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var audio_path := str(seq.get("audio_path", ""))
	if audio_path != "":
		audio_path = _resolve_output_path(audio_path)
	var duration_sec: float = maxf(float(seq.get("duration_sec", 1.0)), 0.05)
	var reset_before: bool = bool(seq.get("reset_before_start", false))
	var tracks: Dictionary = seq.get("tracks", {})

	var saved_out: Dictionary = bg_manager.output_to_dict() if bg_manager != null else {}
	if bg_manager != null:
		bg_manager.apply_output_viewport({
			"width": width,
			"height": height,
			"background_mode": "transparent" if transparent else "match_main",
		})

	var start_res: Dictionary = bridge.start_recording(out_path, width, height, fps, fmt, audio_path, true)
	if not start_res.get("ok", false):
		if bg_manager != null:
			bg_manager.apply_output_viewport(saved_out)
		_sequencer_busy = false
		_refresh_viewport_update_mode()
		return start_res

	var vrm = app_ctrl.current_vrm
	var prev_manual := false
	if vrm != null:
		prev_manual = vrm.manual_step_only
		vrm.manual_step_only = true
		if reset_before:
			vrm.direct_bone_overrides.clear()
			vrm.has_direct_hips_offset = false
			vrm.expressions.reset_all(0.0)
			if vrm.animation_player != null:
				vrm.animation_player.stop()

	var dt := 1.0 / float(fps)
	var total_frames := maxi(int(round(duration_sec * float(fps))), 1)
	var anim_cues: Array = tracks.get("animations", []).duplicate()
	anim_cues.sort_custom(func(a, b): return float(a.get("time_sec", 0.0)) < float(b.get("time_sec", 0.0)))
	var next_cue := 0

	var cam_keys: Array = tracks.get("camera", []).duplicate()
	cam_keys.sort_custom(func(a, b): return float(a.get("time_sec", 0.0)) < float(b.get("time_sec", 0.0)))

	var expr_keys: Array = tracks.get("expressions", []).duplicate()
	expr_keys.sort_custom(func(a, b): return float(a.get("time_sec", 0.0)) < float(b.get("time_sec", 0.0)))

	var bone_keys: Array = tracks.get("bones", []).duplicate()
	bone_keys.sort_custom(func(a, b): return float(a.get("time_sec", 0.0)) < float(b.get("time_sec", 0.0)))

	var lookat_keys: Array = tracks.get("lookat", []).duplicate()
	lookat_keys.sort_custom(func(a, b): return float(a.get("time_sec", 0.0)) < float(b.get("time_sec", 0.0)))

	var light_keys: Array = tracks.get("lighting", []).duplicate()
	light_keys.sort_custom(func(a, b): return float(a.get("time_sec", 0.0)) < float(b.get("time_sec", 0.0)))

	var ok_all := true
	for frame in range(total_frames):
		var t := float(frame) * dt

		while next_cue < anim_cues.size() and float(anim_cues[next_cue].get("time_sec", 0.0)) <= t + 1e-5:
			var cue: Dictionary = anim_cues[next_cue]
			app_ctrl.play_animation_internal(
				str(cue.get("name", "")),
				bool(cue.get("looping", true)),
				float(cue.get("speed", 1.0)),
				float(cue.get("blend_sec", 0.2))
			)
			next_cue += 1

		if not cam_keys.is_empty() and camera_rig != null:
			camera_rig.apply_params(_eval_dict_track(cam_keys, t, ["yaw_deg", "pitch_deg", "distance", "fov_deg"], ["target"]))

		if not light_keys.is_empty() and lighting_rig != null:
			lighting_rig.apply_params(_eval_dict_track(light_keys, t, ["key_azimuth_deg", "key_elevation_deg", "key_energy", "ambient_energy"], []))

		if vrm != null:
			if not expr_keys.is_empty():
				var ew := _eval_map_track(expr_keys, "weights", t)
				vrm.expressions.set_weights(ew, 0.0, false)
			if not bone_keys.is_empty():
				var bm := _eval_bone_track(bone_keys, t)
				for bname in bm["bones"].keys():
					vrm.direct_bone_overrides[bname] = bm["bones"][bname]
				if bm["has_hips"]:
					vrm.direct_hips_offset = bm["hips"]
					vrm.has_direct_hips_offset = true
			if not lookat_keys.is_empty():
				var la := _eval_lookat_track(lookat_keys, t)
				vrm.lookat.mode = la["mode"]
				if la["has_target"]:
					vrm.lookat.manual_target = la["target"]
			if camera_rig != null:
				vrm.lookat_world_target = camera_rig.get_camera_world_position()
			vrm.step(dt)

		output_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw

		var img := output_viewport.get_texture().get_image()
		if img == null or img.is_empty():
			ok_all = false
			break
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		if not bridge.push_recording_frame(img.get_data(), true):
			ok_all = false
			break

	var stop_res: Dictionary = bridge.stop_recording()
	if vrm != null:
		vrm.manual_step_only = prev_manual
	if bg_manager != null:
		bg_manager.apply_output_viewport(saved_out)
	_sequencer_busy = false
	_refresh_viewport_update_mode()

	if not ok_all:
		return {"ok": false, "error": "Failed during sequence frame capture"}
	return stop_res


func to_dict() -> Dictionary:
	return {
		"spout_enabled": spout_enabled,
		"spout_sender_name": spout_sender_name,
		"vcam_enabled": vcam_enabled,
		"recording_active": recording_active,
		"recording_path": recording_path,
		"screenshots_dir": screenshots_dir,
		"recordings_dir": recordings_dir,
		"record_lipsync_audio": record_lipsync_audio,
	}


func _refresh_viewport_update_mode() -> void:
	if output_viewport == null:
		return
	if spout_enabled or vcam_enabled or recording_active:
		output_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	else:
		output_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


static func _resolve_output_path(p: String) -> String:
	if p.begins_with("res://") or p.begins_with("user://"):
		return ProjectSettings.globalize_path(p)
	if p.is_absolute_path():
		return p
	return ConfigManagerScript.get_app_root_dir().path_join(p)


static func _ease(t: float, easing: String) -> float:
	var x := clampf(t, 0.0, 1.0)
	match easing:
		"step":
			return 0.0 if x < 1.0 else 1.0
		"ease_in":
			return x * x
		"ease_out":
			return 1.0 - (1.0 - x) * (1.0 - x)
		"ease_in_out":
			return x * x * (3.0 - 2.0 * x)
		_:
			return x


static func _eval_dict_track(keys: Array, t: float, scalar_fields: Array, vec3_fields: Array) -> Dictionary:
	var n := keys.size()
	if n == 0:
		return {}
	if t <= float(keys[0].get("time_sec", 0.0)):
		return keys[0]
	if t >= float(keys[n - 1].get("time_sec", 0.0)):
		return keys[n - 1]
	var i := 0
	while i + 1 < n and float(keys[i + 1].get("time_sec", 0.0)) < t:
		i += 1
	var k0: Dictionary = keys[i]
	var k1: Dictionary = keys[i + 1]
	var t0 := float(k0.get("time_sec", 0.0))
	var t1 := float(k1.get("time_sec", 0.0))
	var alpha := _ease((t - t0) / maxf(t1 - t0, 1e-6), str(k1.get("easing", "linear")))
	var out := {}
	for f in scalar_fields:
		if k0.get(f, null) != null and k1.get(f, null) != null:
			out[f] = lerpf(float(k0[f]), float(k1[f]), alpha)
		elif k1.get(f, null) != null:
			out[f] = float(k1[f])
		elif k0.get(f, null) != null:
			out[f] = float(k0[f])
	for vf in vec3_fields:
		if typeof(k0.get(vf, null)) == TYPE_ARRAY and typeof(k1.get(vf, null)) == TYPE_ARRAY:
			var a: Array = k0[vf]
			var b: Array = k1[vf]
			out[vf] = [
				lerpf(float(a[0]), float(b[0]), alpha),
				lerpf(float(a[1]), float(b[1]), alpha),
				lerpf(float(a[2]), float(b[2]), alpha),
			]
	return out


static func _eval_map_track(keys: Array, field: String, t: float) -> Dictionary:
	var n := keys.size()
	if n == 0:
		return {}
	if t <= float(keys[0].get("time_sec", 0.0)):
		return keys[0].get(field, {})
	if t >= float(keys[n - 1].get("time_sec", 0.0)):
		return keys[n - 1].get(field, {})
	var i := 0
	while i + 1 < n and float(keys[i + 1].get("time_sec", 0.0)) < t:
		i += 1
	var k0: Dictionary = keys[i]
	var k1: Dictionary = keys[i + 1]
	var t0 := float(k0.get("time_sec", 0.0))
	var t1 := float(k1.get("time_sec", 0.0))
	var alpha := _ease((t - t0) / maxf(t1 - t0, 1e-6), str(k1.get("easing", "linear")))
	var m0: Dictionary = k0.get(field, {})
	var m1: Dictionary = k1.get(field, {})
	var out := {}
	for k in m0.keys():
		out[k] = lerpf(float(m0[k]), float(m1.get(k, 0.0)), alpha)
	for k in m1.keys():
		if not out.has(k):
			out[k] = lerpf(0.0, float(m1[k]), alpha)
	return out


static func _eval_bone_track(keys: Array, t: float) -> Dictionary:
	var n := keys.size()
	if n == 0:
		return {"bones": {}, "has_hips": false, "hips": Vector3.ZERO}
	var i := 0
	if t <= float(keys[0].get("time_sec", 0.0)):
		i = 0
	elif t >= float(keys[n - 1].get("time_sec", 0.0)):
		i = n - 1
	else:
		while i + 1 < n and float(keys[i + 1].get("time_sec", 0.0)) < t:
			i += 1
	var k0: Dictionary = keys[i]
	var k1: Dictionary = keys[mini(i + 1, n - 1)]
	var t0 := float(k0.get("time_sec", 0.0))
	var t1 := float(k1.get("time_sec", 0.0))
	var alpha := 0.0 if i == n - 1 or t <= t0 else _ease((t - t0) / maxf(t1 - t0, 1e-6), str(k1.get("easing", "linear")))
	var b0: Dictionary = k0.get("bones_euler_deg", {})
	var b1: Dictionary = k1.get("bones_euler_deg", {})
	var seen := {}
	for k in b0.keys():
		seen[k] = true
	for k in b1.keys():
		seen[k] = true
	var out_bones := {}
	for bname in seen.keys():
		var e0: Array = b0.get(bname, [0.0, 0.0, 0.0])
		var e1: Array = b1.get(bname, [0.0, 0.0, 0.0])
		var q0 := Quaternion.from_euler(Vector3(deg_to_rad(float(e0[0])), deg_to_rad(float(e0[1])), deg_to_rad(float(e0[2]))))
		var q1 := Quaternion.from_euler(Vector3(deg_to_rad(float(e1[0])), deg_to_rad(float(e1[1])), deg_to_rad(float(e1[2]))))
		if q0.dot(q1) < 0.0:
			q1 = -q1
		out_bones[str(bname)] = q0.slerp(q1, alpha).normalized()
	var has_hips := (k0.get("hips_position", null) != null or k1.get("hips_position", null) != null)
	var hips := Vector3.ZERO
	if has_hips:
		var h0: Array = k0.get("hips_position", [0.0, 0.0, 0.0]) if k0.get("hips_position", null) != null else [0.0, 0.0, 0.0]
		var h1: Array = k1.get("hips_position", h0) if k1.get("hips_position", null) != null else h0
		hips = Vector3(lerpf(float(h0[0]), float(h1[0]), alpha), lerpf(float(h0[1]), float(h1[1]), alpha), lerpf(float(h0[2]), float(h1[2]), alpha))
	return {"bones": out_bones, "has_hips": has_hips, "hips": hips}


static func _eval_lookat_track(keys: Array, t: float) -> Dictionary:
	var d := _eval_dict_track(keys, t, [], ["target"])
	var mode_str := str(keys[0].get("mode", "camera"))
	for k in keys:
		if float(k.get("time_sec", 0.0)) <= t:
			mode_str = str(k.get("mode", mode_str))
	var has_t := typeof(d.get("target", null)) == TYPE_ARRAY
	var tgt := Vector3.ZERO
	if has_t:
		var a: Array = d["target"]
		tgt = Vector3(float(a[0]), float(a[1]), float(a[2]))
	return {"mode": mode_str, "has_target": has_t, "target": tgt}
