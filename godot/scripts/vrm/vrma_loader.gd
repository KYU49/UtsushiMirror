class_name VrmaLoader
extends RefCounted

## Runtime loader and retargeting player for VRMC_vrm_animation-1.0 (.vrma) GLB files.
## Supports LINEAR, STEP, and CUBICSPLINE samplers, arbitrary source skeleton rest poses,
## humanoid rotation/hips retargeting, expression channels, lookAt node, and crossfades.

const GlbReaderScript := preload("res://scripts/vrm/glb_reader.gd")


class VrmaSampler:
	var times: PackedFloat32Array
	var values: PackedFloat32Array # flat floats: 3 per key for VEC3, 4 per key for VEC4 (3x for CUBICSPLINE)
	var stride: int = 4 # 3 or 4
	var interpolation: String = "LINEAR" # "LINEAR" | "STEP" | "CUBICSPLINE"
	var _last_idx: int = 0

	func sample_vec3(t: float) -> Vector3:
		if times.is_empty():
			return Vector3.ZERO
		var n := times.size()
		if n == 1 or t <= times[0]:
			var off := 3 if interpolation == "CUBICSPLINE" else 0
			return Vector3(values[off], values[off + 1], values[off + 2])
		if t >= times[n - 1]:
			var last_idx := n - 1
			var off := (last_idx * 9 + 3) if interpolation == "CUBICSPLINE" else (last_idx * 3)
			return Vector3(values[off], values[off + 1], values[off + 2])

		var idx := _find_segment(t)
		var t0 := times[idx]
		var t1 := times[idx + 1]
		var dt := maxf(t1 - t0, 1e-6)
		var alpha := clampf((t - t0) / dt, 0.0, 1.0)

		if interpolation == "STEP":
			var o := idx * 3
			return Vector3(values[o], values[o + 1], values[o + 2])
		elif interpolation == "CUBICSPLINE":
			var o0 := idx * 9
			var o1 := (idx + 1) * 9
			var v0 := Vector3(values[o0 + 3], values[o0 + 4], values[o0 + 5])
			var b0 := Vector3(values[o0 + 6], values[o0 + 7], values[o0 + 8])
			var a1 := Vector3(values[o1], values[o1 + 1], values[o1 + 2])
			var v1 := Vector3(values[o1 + 3], values[o1 + 4], values[o1 + 5])
			var s := alpha
			var s2 := s * s
			var s3 := s2 * s
			return (2.0 * s3 - 3.0 * s2 + 1.0) * v0 + dt * (s3 - 2.0 * s2 + s) * b0 + (-2.0 * s3 + 3.0 * s2) * v1 + dt * (s3 - s2) * a1
		else:
			var o0 := idx * 3
			var o1 := (idx + 1) * 3
			var v0 := Vector3(values[o0], values[o0 + 1], values[o0 + 2])
			var v1 := Vector3(values[o1], values[o1 + 1], values[o1 + 2])
			return v0.lerp(v1, alpha)

	func sample_quat(t: float) -> Quaternion:
		if times.is_empty():
			return Quaternion.IDENTITY
		var n := times.size()
		if n == 1 or t <= times[0]:
			var off := 4 if interpolation == "CUBICSPLINE" else 0
			return Quaternion(values[off], values[off + 1], values[off + 2], values[off + 3]).normalized()
		if t >= times[n - 1]:
			var last_idx := n - 1
			var off := (last_idx * 12 + 4) if interpolation == "CUBICSPLINE" else (last_idx * 4)
			return Quaternion(values[off], values[off + 1], values[off + 2], values[off + 3]).normalized()

		var idx := _find_segment(t)
		var t0 := times[idx]
		var t1 := times[idx + 1]
		var dt := maxf(t1 - t0, 1e-6)
		var alpha := clampf((t - t0) / dt, 0.0, 1.0)

		if interpolation == "STEP":
			var o := idx * 4
			return Quaternion(values[o], values[o + 1], values[o + 2], values[o + 3]).normalized()
		elif interpolation == "CUBICSPLINE":
			var o0 := idx * 12
			var o1 := (idx + 1) * 12
			var v0 := Vector4(values[o0 + 4], values[o0 + 5], values[o0 + 6], values[o0 + 7])
			var b0 := Vector4(values[o0 + 8], values[o0 + 9], values[o0 + 10], values[o0 + 11])
			var a1 := Vector4(values[o1], values[o1 + 1], values[o1 + 2], values[o1 + 3])
			var v1 := Vector4(values[o1 + 4], values[o1 + 5], values[o1 + 6], values[o1 + 7])
			var s := alpha
			var s2 := s * s
			var s3 := s2 * s
			var qv := (2.0 * s3 - 3.0 * s2 + 1.0) * v0 + dt * (s3 - 2.0 * s2 + s) * b0 + (-2.0 * s3 + 3.0 * s2) * v1 + dt * (s3 - s2) * a1
			return Quaternion(qv.x, qv.y, qv.z, qv.w).normalized()
		else:
			var o0 := idx * 4
			var o1 := (idx + 1) * 4
			var q0 := Quaternion(values[o0], values[o0 + 1], values[o0 + 2], values[o0 + 3]).normalized()
			var q1 := Quaternion(values[o1], values[o1 + 1], values[o1 + 2], values[o1 + 3]).normalized()
			if q0.dot(q1) < 0.0:
				q1 = -q1
			return q0.slerp(q1, alpha).normalized()

	func _find_segment(t: float) -> int:
		var hi := times.size() - 2
		if hi <= 0:
			_last_idx = 0
			return 0
		var li := _last_idx
		if li >= 0 and li <= hi:
			if times[li] <= t and t < times[li + 1]:
				return li
			if li + 1 <= hi and times[li + 1] <= t and t < times[li + 2]:
				_last_idx = li + 1
				return _last_idx
		var lo := 0
		while lo <= hi:
			var mid := (lo + hi) >> 1
			if times[mid] <= t:
				if t < times[mid + 1]:
					_last_idx = mid
					return mid
				lo = mid + 1
			else:
				hi = mid - 1
		_last_idx = clampi(lo, 0, times.size() - 2)
		return _last_idx


class VrmaClip:
	var name: String
	var path: String
	var duration: float = 1.0
	var src_hips_rest_y: float = 0.9
	var src_hips_rest_pos: Vector3 = Vector3(0.0, 0.9, 0.0)
	var hips_trans_sampler: VrmaSampler = null
	# human_bone_name -> { rest_local, rest_local_inv, parent_rest_world, parent_rest_world_inv, sampler }
	var bone_tracks: Dictionary = {}
	# expr_name -> VrmaSampler (translation.x)
	var expr_tracks: Dictionary = {}
	var lookat_sampler: VrmaSampler = null

	func evaluate(time_sec: float, dst_hips_rest_y: float) -> Dictionary:
		var bones: Dictionary = {}
		for bname in bone_tracks.keys():
			var tr: Dictionary = bone_tracks[bname]
			var samp: VrmaSampler = tr["sampler"]
			var q_pose_local: Quaternion = samp.sample_quat(time_sec)
			var q_rest_inv: Quaternion = tr["rest_local_inv"] if tr.has("rest_local_inv") else (tr["rest_local"] as Quaternion).inverse()
			var q_parent_world: Quaternion = tr["parent_rest_world"]
			var q_parent_inv: Quaternion = tr["parent_rest_world_inv"] if tr.has("parent_rest_world_inv") else q_parent_world.inverse()
			var norm_rot: Quaternion = (q_parent_world * (q_pose_local * q_rest_inv) * q_parent_inv).normalized()
			bones[bname] = norm_rot

		var hips_delta := Vector3.ZERO
		if hips_trans_sampler != null:
			var p_pose := hips_trans_sampler.sample_vec3(time_sec)
			var scale := (dst_hips_rest_y / maxf(src_hips_rest_y, 0.05))
			hips_delta = (p_pose - src_hips_rest_pos) * scale

		var exprs: Dictionary = {}
		for ename in expr_tracks.keys():
			var esamp: VrmaSampler = expr_tracks[ename]
			exprs[ename] = clampf(esamp.sample_vec3(time_sec).x, 0.0, 1.0)

		var has_lookat := false
		var lookat_target := Vector3.ZERO
		if lookat_sampler != null:
			has_lookat = true
			lookat_target = lookat_sampler.sample_vec3(time_sec)

		return {
			"bones": bones,
			"hips_delta": hips_delta,
			"expressions": exprs,
			"has_lookat": has_lookat,
			"lookat_target": lookat_target,
		}


class VrmaPlayer:
	var clips: Dictionary = {} # name -> VrmaClip
	var clip_loaders: Dictionary = {} # name -> Callable -> VrmaClip?
	var current_clip: VrmaClip = null
	var current_name: String = ""
	var time_sec: float = 0.0
	var looping: bool = true
	var speed: float = 1.0
	var paused: bool = false
	var playing: bool = false
	## true のあいだは、クリップの腰の前後左右の移動を使わない (歩く命令で体ごと動かすとき、二重に進まないように)
	var strip_root_xz: bool = false

	# Crossfade state
	var _prev_pose: Dictionary = {}
	var _blend_elapsed: float = 0.0
	var _blend_duration: float = 0.0
	var _last_pose: Dictionary = {}
	var _last_dst_y: float = 0.9
	## 姿勢の違いを測る骨 (指や目は見ない)
	const BLEND_MEASURE_BONES := [
		"hips", "spine", "chest", "upperChest", "neck", "head",
		"leftUpperArm", "rightUpperArm", "leftLowerArm", "rightLowerArm",
		"leftUpperLeg", "rightUpperLeg", "leftLowerLeg", "rightLowerLeg",
	]
	const BLEND_SMALL_DEG := 30.0
	const BLEND_LARGE_DEG := 120.0
	const BLEND_MAX_SEC := 1.0

	func add_clip(clip_name: String, clip: VrmaClip) -> void:
		clip_loaders.erase(clip_name)
		clips[clip_name] = clip

	func register_lazy_clip(clip_name: String, loader: Callable) -> void:
		clips.erase(clip_name)
		clip_loaders[clip_name] = loader

	func erase_clip(clip_name: String) -> void:
		clips.erase(clip_name)
		clip_loaders.erase(clip_name)

	func has_clip(clip_name: String) -> bool:
		return clips.has(clip_name) or clip_loaders.has(clip_name)

	func get_clip(clip_name: String) -> VrmaClip:
		if clips.has(clip_name):
			return clips[clip_name]
		if clip_loaders.has(clip_name):
			var loader: Callable = clip_loaders[clip_name]
			clip_loaders.erase(clip_name)
			var clip = loader.call() if loader.is_valid() else null
			if clip is VrmaClip:
				clips[clip_name] = clip
				return clip
		return null

	func get_clip_names() -> Array[String]:
		var seen: Dictionary = {}
		for k in clips.keys():
			seen[str(k)] = true
		for k in clip_loaders.keys():
			seen[str(k)] = true
		var out: Array[String] = []
		for k in seen.keys():
			out.append(k)
		out.sort()
		return out

	func play(clip_name: String, p_looping: bool = true, p_speed: float = 1.0, blend_sec: float = 0.25) -> bool:
		var target_clip := get_clip(clip_name)
		if target_clip == null:
			return false
		if playing and not _last_pose.is_empty() and blend_sec > 0.001:
			_prev_pose = _last_pose.duplicate(true)
			# 次の動きの最初の姿勢が今の姿勢から大きく違うほど、ゆっくりつなぐ
			var first: Dictionary = target_clip.evaluate(0.0, _last_dst_y)
			_blend_duration = auto_blend_sec(blend_sec, pose_distance_deg(_last_pose, first))
			_blend_elapsed = 0.0
		else:
			_prev_pose = {}
			_blend_duration = 0.0
			_blend_elapsed = 0.0

		current_clip = target_clip
		current_name = clip_name
		time_sec = 0.0
		looping = p_looping
		speed = p_speed
		paused = false
		playing = true
		return true

	func stop() -> void:
		playing = false
		paused = false
		current_clip = null
		current_name = ""
		time_sec = 0.0
		_prev_pose = {}
		_last_pose = {}

	func seek(p_time_sec: float) -> void:
		if current_clip == null:
			return
		var dur := maxf(current_clip.duration, 0.001)
		if looping:
			time_sec = fposmod(p_time_sec, dur)
		else:
			time_sec = clampf(p_time_sec, 0.0, dur)

	func sample_pose(dt: float, humanoid) -> Dictionary:
		if not playing or current_clip == null:
			return {}

		if not paused:
			var dur := maxf(current_clip.duration, 0.001)
			time_sec += dt * speed
			if looping:
				time_sec = fposmod(time_sec, dur)
			else:
				if time_sec >= dur:
					time_sec = dur
					paused = true

		var dst_y: float = humanoid.hips_rest_height if humanoid != null else 0.9
		_last_dst_y = dst_y
		var pose := current_clip.evaluate(time_sec, dst_y)
		if strip_root_xz:
			var hd: Vector3 = pose.get("hips_delta", Vector3.ZERO)
			pose["hips_delta"] = Vector3(0.0, hd.y, 0.0)

		if not _prev_pose.is_empty() and _blend_duration > 0.001:
			_blend_elapsed += dt
			var w := clampf(_blend_elapsed / _blend_duration, 0.0, 1.0)
			if w >= 1.0:
				_prev_pose = {}
				_blend_duration = 0.0
			else:
				pose = _blend_poses(_prev_pose, pose, ease_out(w))

		_last_pose = pose
		return pose

	## 始めは速く、終わりにゆっくり止まる (3 次の ease out)
	static func ease_out(x: float) -> float:
		var r := 1.0 - clampf(x, 0.0, 1.0)
		return 1.0 - r * r * r

	## 2 つの姿勢の違い (度)。体の大きな骨の回転の違いの最大と、腰の移動 (0.1 m を 30 度と見る) の大きい方
	static func pose_distance_deg(a: Dictionary, b: Dictionary) -> float:
		var abones: Dictionary = a.get("bones", {})
		var bbones: Dictionary = b.get("bones", {})
		var worst := 0.0
		for k in BLEND_MEASURE_BONES:
			if not abones.has(k) and not bbones.has(k):
				continue
			var qa: Quaternion = abones.get(k, Quaternion.IDENTITY)
			var qb: Quaternion = bbones.get(k, Quaternion.IDENTITY)
			var d := clampf(absf(qa.normalized().dot(qb.normalized())), 0.0, 1.0)
			worst = maxf(worst, rad_to_deg(2.0 * acos(d)))
		var ah: Vector3 = a.get("hips_delta", Vector3.ZERO)
		var bh: Vector3 = b.get("hips_delta", Vector3.ZERO)
		return maxf(worst, ah.distance_to(bh) * 300.0)

	## つなぐ秒数。違いが BLEND_SMALL_DEG までは指定のまま、BLEND_LARGE_DEG で BLEND_MAX_SEC まで伸ばす
	static func auto_blend_sec(base_sec: float, diff_deg: float) -> float:
		if base_sec <= 0.001:
			return base_sec
		var k := clampf((diff_deg - BLEND_SMALL_DEG) / (BLEND_LARGE_DEG - BLEND_SMALL_DEG), 0.0, 1.0)
		return maxf(base_sec, lerpf(base_sec, BLEND_MAX_SEC, k))

	static func _blend_poses(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
		var out_bones: Dictionary = {}
		var abones: Dictionary = a.get("bones", {})
		var bbones: Dictionary = b.get("bones", {})
		var seen: Dictionary = {}
		for k in abones.keys():
			seen[k] = true
		for k in bbones.keys():
			seen[k] = true
		for k in seen.keys():
			var qa: Quaternion = abones.get(k, Quaternion.IDENTITY)
			var qb: Quaternion = bbones.get(k, Quaternion.IDENTITY)
			if qa.dot(qb) < 0.0:
				qb = -qb
			out_bones[k] = qa.slerp(qb, w).normalized()

		var ah: Vector3 = a.get("hips_delta", Vector3.ZERO)
		var bh: Vector3 = b.get("hips_delta", Vector3.ZERO)
		return {
			"bones": out_bones,
			"hips_delta": ah.lerp(bh, w),
			"expressions": b.get("expressions", {}),
			"has_lookat": b.get("has_lookat", false),
			"lookat_target": b.get("lookat_target", Vector3.ZERO),
		}


static func load_vrma(path: String, bridge: Node = null, clip_name: String = "") -> Dictionary:
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	if not FileAccess.file_exists(abs_path):
		return {"ok": false, "error": "VRMA file not found: " + abs_path}

	var glb: Dictionary = GlbReaderScript.read_glb(abs_path, bridge)
	if not glb.get("ok", false):
		return glb

	var gltf_json: Dictionary = glb["json"]
	var bin: PackedByteArray = glb.get("bin", PackedByteArray())
	var exts: Dictionary = gltf_json.get("extensions", {})
	if not exts.has("VRMC_vrm_animation"):
		return {"ok": false, "error": "Missing VRMC_vrm_animation extension"}
	var vrma_ext: Dictionary = exts["VRMC_vrm_animation"]

	var jnodes: Array = gltf_json.get("nodes", [])
	var anims: Array = gltf_json.get("animations", [])
	if anims.is_empty():
		return {"ok": false, "error": "VRMA contains no animations"}

	# Build rest transforms (local & global) for all nodes in the VRMA file
	var rest_local_rot: Array = []
	var rest_local_pos: Array = []
	var rest_world_rot: Array = []
	var rest_world_pos: Array = []
	var parent_of: Array = []
	rest_local_rot.resize(jnodes.size())
	rest_local_pos.resize(jnodes.size())
	rest_world_rot.resize(jnodes.size())
	rest_world_pos.resize(jnodes.size())
	parent_of.resize(jnodes.size())
	for i in range(jnodes.size()):
		parent_of[i] = -1
		var jn: Dictionary = jnodes[i]
		rest_local_rot[i] = _parse_node_rot(jn)
		rest_local_pos[i] = _parse_node_pos(jn)
		rest_world_rot[i] = Quaternion.IDENTITY
		rest_world_pos[i] = Vector3.ZERO
	for i in range(jnodes.size()):
		for ch in jnodes[i].get("children", []):
			var ci := int(ch)
			if ci >= 0 and ci < jnodes.size():
				parent_of[ci] = i
	for i in range(jnodes.size()):
		if parent_of[i] < 0:
			_compute_world_rest(i, Quaternion.IDENTITY, Vector3.ZERO, jnodes, rest_local_rot, rest_local_pos, rest_world_rot, rest_world_pos)

	var anim: Dictionary = anims[0]
	var raw_samplers: Array = anim.get("samplers", [])
	var raw_channels: Array = anim.get("channels", [])
	var parsed_samplers: Dictionary = {} # "samp_idx:stride" -> VrmaSampler

	var max_dur := 0.0
	var node_rot_samplers: Dictionary = {} # node_idx -> VrmaSampler
	var node_trans_samplers: Dictionary = {} # node_idx -> VrmaSampler

	for ch in raw_channels:
		var target: Dictionary = ch.get("target", {})
		if not target.has("node"):
			continue
		var node_idx: int = int(target["node"])
		var path_str: String = str(target.get("path", ""))
		var samp_idx: int = int(ch.get("sampler", -1))
		if samp_idx < 0 or samp_idx >= raw_samplers.size():
			continue

		if path_str == "rotation":
			var s := _get_or_parse_sampler(parsed_samplers, samp_idx, 4, raw_samplers, gltf_json, bin)
			if s != null:
				node_rot_samplers[node_idx] = s
				if not s.times.is_empty():
					max_dur = maxf(max_dur, s.times[s.times.size() - 1])
		elif path_str == "translation":
			var s := _get_or_parse_sampler(parsed_samplers, samp_idx, 3, raw_samplers, gltf_json, bin)
			if s != null:
				node_trans_samplers[node_idx] = s
				if not s.times.is_empty():
					max_dur = maxf(max_dur, s.times[s.times.size() - 1])

	var clip := VrmaClip.new()
	clip.name = clip_name if clip_name != "" else abs_path.get_file().get_basename()
	clip.path = abs_path
	clip.duration = maxf(max_dur, 0.01)

	# Map humanoid bone tracks
	var hb: Dictionary = vrma_ext.get("humanoid", {}).get("humanBones", {})
	for bname in hb.keys():
		var gnode: int = int(hb[bname].get("node", -1))
		if gnode < 0 or gnode >= jnodes.size():
			continue
		var p_idx: int = parent_of[gnode]
		var p_world_rot: Quaternion = rest_world_rot[p_idx] if p_idx >= 0 else Quaternion.IDENTITY
		if str(bname) == "hips":
			var hips_wpos: Vector3 = rest_world_pos[gnode]
			if absf(hips_wpos.y) > 0.01:
				clip.src_hips_rest_y = absf(hips_wpos.y)
			clip.src_hips_rest_pos = rest_local_pos[gnode]
			if node_trans_samplers.has(gnode):
				clip.hips_trans_sampler = node_trans_samplers[gnode]
		if node_rot_samplers.has(gnode):
			var q_rest_local: Quaternion = rest_local_rot[gnode]
			clip.bone_tracks[str(bname)] = {
				"rest_local": q_rest_local,
				"rest_local_inv": q_rest_local.inverse(),
				"parent_rest_world": p_world_rot,
				"parent_rest_world_inv": p_world_rot.inverse(),
				"sampler": node_rot_samplers[gnode],
			}

	# Map VRMA expression tracks (translation.x of referenced node)
	var vrma_exprs: Dictionary = vrma_ext.get("expressions", {})
	for group_key in ["preset", "custom"]:
		var grp: Dictionary = vrma_exprs.get(group_key, {})
		for ename in grp.keys():
			var enode: int = int(grp[ename].get("node", -1))
			if node_trans_samplers.has(enode):
				clip.expr_tracks[str(ename)] = node_trans_samplers[enode]

	# Map VRMA lookAt node
	if vrma_ext.has("lookAt"):
		var lnode: int = int(vrma_ext["lookAt"].get("node", -1))
		if node_trans_samplers.has(lnode):
			clip.lookat_sampler = node_trans_samplers[lnode]

	return {"ok": true, "clip": clip}


static func _compute_world_rest(
	idx: int,
	parent_rot: Quaternion,
	parent_pos: Vector3,
	jnodes: Array,
	lrot: Array,
	lpos: Array,
	wrot: Array,
	wpos: Array
) -> void:
	var cur_rot: Quaternion = (parent_rot * lrot[idx]).normalized()
	var cur_pos: Vector3 = parent_pos + parent_rot * lpos[idx]
	wrot[idx] = cur_rot
	wpos[idx] = cur_pos
	for ch in jnodes[idx].get("children", []):
		var ci := int(ch)
		if ci >= 0 and ci < jnodes.size():
			_compute_world_rest(ci, cur_rot, cur_pos, jnodes, lrot, lpos, wrot, wpos)


static func _get_or_parse_sampler(
	cache: Dictionary,
	samp_idx: int,
	stride: int,
	raw_samplers: Array,
	gltf_json: Dictionary,
	bin: PackedByteArray
) -> VrmaSampler:
	var key := "%d:%d" % [samp_idx, stride]
	if cache.has(key):
		return cache[key]
	var rs: Dictionary = raw_samplers[samp_idx]
	var in_acc := int(rs.get("input", -1))
	var out_acc := int(rs.get("output", -1))
	var interp := str(rs.get("interpolation", "LINEAR"))

	var times := _read_accessor_floats(gltf_json, bin, in_acc, 1)
	var vals := _read_accessor_floats(gltf_json, bin, out_acc, stride)
	if times.is_empty() or vals.is_empty():
		return null

	var samp := VrmaSampler.new()
	samp.times = times
	samp.values = vals
	samp.stride = stride
	samp.interpolation = interp
	cache[key] = samp
	return samp


static func _read_accessor_floats(gltf_json: Dictionary, bin: PackedByteArray, acc_idx: int, comps: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var accessors: Array = gltf_json.get("accessors", [])
	var bvs: Array = gltf_json.get("bufferViews", [])
	if acc_idx < 0 or acc_idx >= accessors.size():
		return out
	var acc: Dictionary = accessors[acc_idx]
	var bv_idx := int(acc.get("bufferView", -1))
	if bv_idx < 0 or bv_idx >= bvs.size():
		return out
	var bv: Dictionary = bvs[bv_idx]
	var count := int(acc.get("count", 0))
	var comp_type := int(acc.get("componentType", 5126))
	var byte_offset := int(bv.get("byteOffset", 0)) + int(acc.get("byteOffset", 0))
	var default_stride := comps * (4 if comp_type == 5126 else (2 if comp_type == 5123 or comp_type == 5122 else 1))
	var byte_stride := int(bv.get("byteStride", default_stride))
	if byte_stride <= 0:
		byte_stride = default_stride

	var normalized := bool(acc.get("normalized", false))
	if comp_type == 5126 and byte_stride == default_stride and count > 0:
		var end_off := byte_offset + count * comps * 4
		if byte_offset >= 0 and end_off <= bin.size():
			return bin.slice(byte_offset, end_off).to_float32_array()
	out.resize(count * comps)
	for i in range(count):
		var base := byte_offset + i * byte_stride
		for c in range(comps):
			var elem_off := base + c * (4 if comp_type == 5126 else (2 if comp_type == 5123 or comp_type == 5122 else 1))
			var v := 0.0
			if comp_type == 5126 and elem_off + 4 <= bin.size():
				v = bin.decode_float(elem_off)
			elif comp_type == 5122 and elem_off + 2 <= bin.size():
				var iv := bin.decode_s16(elem_off)
				v = maxf(float(iv) / 32767.0, -1.0) if normalized else float(iv)
			elif comp_type == 5123 and elem_off + 2 <= bin.size():
				var uv := bin.decode_u16(elem_off)
				v = (float(uv) / 65535.0) if normalized else float(uv)
			elif comp_type == 5120 and elem_off + 1 <= bin.size():
				var bv_s := bin.decode_s8(elem_off)
				v = maxf(float(bv_s) / 127.0, -1.0) if normalized else float(bv_s)
			elif comp_type == 5121 and elem_off + 1 <= bin.size():
				var bv_u := bin.decode_u8(elem_off)
				v = (float(bv_u) / 255.0) if normalized else float(bv_u)
			out[i * comps + c] = v
	return out


static func _parse_node_rot(jn: Dictionary) -> Quaternion:
	var r = jn.get("rotation", null)
	if typeof(r) == TYPE_ARRAY and r.size() >= 4:
		return Quaternion(float(r[0]), float(r[1]), float(r[2]), float(r[3])).normalized()
	return Quaternion.IDENTITY


static func _parse_node_pos(jn: Dictionary) -> Vector3:
	var t = jn.get("translation", null)
	if typeof(t) == TYPE_ARRAY and t.size() >= 3:
		return Vector3(float(t[0]), float(t[1]), float(t[2]))
	return Vector3.ZERO
