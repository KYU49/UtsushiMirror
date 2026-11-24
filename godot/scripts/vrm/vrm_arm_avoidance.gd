class_name VrmArmAvoidance
extends RefCounted

## トラッキング中の腕・手・指先が体幹・胸・頭(+横髪)へめり込むのを 2-Bone IK で回避し、
## 二の腕の胸・体幹への弱い貫通抑制と手のひら〜指先・前腕の SpringBone 外部コライダー生成を行う。

const VrmSpringBoneScript := preload("res://scripts/vrm/vrm_springbone.gd")

var _smooth_push: Dictionary = {
	"left": Vector3.ZERO,
	"right": Vector3.ZERO,
}
var _smooth_ua_push: Dictionary = {
	"left": Vector3.ZERO,
	"right": Vector3.ZERO,
}


func reset() -> void:
	_smooth_push["left"] = Vector3.ZERO
	_smooth_push["right"] = Vector3.ZERO
	_smooth_ua_push["left"] = Vector3.ZERO
	_smooth_ua_push["right"] = Vector3.ZERO


func apply(runtime: Node3D, humanoid, spring_bone, composed_bones: Dictionary, dt: float) -> void:
	if runtime == null or humanoid == null or composed_bones.is_empty():
		return
	var skel: Skeleton3D = humanoid.skeleton
	if skel == null:
		return

	var root_inv: Transform3D = runtime.global_transform.affine_inverse()
	var hips_pos: Vector3 = _bone_local(humanoid, root_inv, "hips") if humanoid.has_bone("hips") else Vector3(0.0, 0.9, 0.0)
	var chest_pos: Vector3 = _bone_local(humanoid, root_inv, "chest") if humanoid.has_bone("chest") else (hips_pos + Vector3(0.0, 0.35, 0.0))
	var up_chest_name := "upperChest" if humanoid.has_bone("upperChest") else ("chest" if humanoid.has_bone("chest") else ("spine" if humanoid.has_bone("spine") else ""))
	var up_chest_pos: Vector3 = _bone_local(humanoid, root_inv, up_chest_name) if up_chest_name != "" else chest_pos
	var head_pos: Vector3 = _bone_local(humanoid, root_inv, "head") if humanoid.has_bone("head") else (up_chest_pos + Vector3(0.0, 0.25, 0.0))

	var sh_w: float = 0.36
	if humanoid.has_bone("leftUpperArm") and humanoid.has_bone("rightUpperArm"):
		sh_w = clampf(_bone_local(humanoid, root_inv, "leftUpperArm").distance_to(_bone_local(humanoid, root_inv, "rightUpperArm")), 0.18, 0.55)

	var q_chest := Quaternion.IDENTITY
	for tb in ["hips", "spine", "chest", "upperChest"]:
		if composed_bones.has(tb):
			q_chest = (q_chest * (composed_bones[tb] as Quaternion)).normalized()
	var torso_fwd: Vector3 = (q_chest * Vector3(0.0, 0.0, 1.0)).normalized()
	var torso_left: Vector3 = (q_chest * Vector3(1.0, 0.0, 0.0)).normalized()
	var torso_up: Vector3 = (q_chest * Vector3(0.0, 1.0, 0.0)).normalized()

	var torso_cap_p0: Vector3 = hips_pos + torso_up * (sh_w * 0.12)
	var torso_cap_p1: Vector3 = up_chest_pos + torso_up * (sh_w * 0.08)
	var torso_cap_r: float = clampf(sh_w * 0.38, 0.09, 0.19)
	var bust_base: Vector3 = chest_pos.lerp(up_chest_pos, 0.65)

	var obstacles: Array = []
	# 1) 体幹カプセル + 胸/バスト前方スフィア + 頭部(+頬・横髪)スフィア
	obstacles.append({
		"type": "capsule",
		"p0": torso_cap_p0,
		"p1": torso_cap_p1,
		"r": torso_cap_r,
		"kind": "torso",
	})
	obstacles.append({
		"type": "sphere",
		"p0": bust_base + torso_fwd * (sh_w * 0.22),
		"p1": Vector3.ZERO,
		"r": clampf(sh_w * 0.42, 0.10, 0.20),
		"kind": "torso",
	})
	obstacles.append({
		"type": "sphere",
		"p0": head_pos + torso_up * (sh_w * 0.14),
		"p1": Vector3.ZERO,
		"r": clampf(sh_w * 0.50, 0.12, 0.25),
		"kind": "head",
	})

	# 2) モデル固有の SpringBone コライダー (胸・背骨・首・頭) も統合
	if spring_bone != null and not spring_bone.colliders.is_empty():
		var body_bone_kinds: Dictionary = {}
		for hb in ["hips", "spine", "chest", "upperChest"]:
			var b_i: int = humanoid.get_bone_idx(hb)
			if b_i >= 0:
				body_bone_kinds[b_i] = "torso"
		for hb in ["neck", "head"]:
			var b_i: int = humanoid.get_bone_idx(hb)
			if b_i >= 0:
				body_bone_kinds[b_i] = "head"
		for cdef in spring_bone.colliders:
			if cdef == null or cdef.node_ref.get("skeleton") != skel:
				continue
			var b_i: int = int(cdef.node_ref.get("bone_idx", -1))
			if not body_bone_kinds.has(b_i):
				continue
			if cdef.shape != "sphere" and cdef.shape != "capsule":
				continue
			var xf_local: Transform3D = root_inv * skel.global_transform * skel.get_bone_global_pose(b_i)
			obstacles.append({
				"type": cdef.shape,
				"p0": xf_local * cdef.offset,
				"p1": xf_local * cdef.tail,
				"r": clampf(cdef.radius, 0.02, 0.35),
				"kind": body_bone_kinds[b_i],
			})

	var torso_obstacles: Array = []
	for obs in obstacles:
		if str(obs.get("kind", "")) == "torso":
			torso_obstacles.append(obs)

	var hand_pad: float = clampf(sh_w * 0.14, 0.035, 0.075)
	var ua_pad: float = clampf(sh_w * 0.06, 0.015, 0.032)
	var alpha: float = (1.0 - exp(-dt * 18.0)) if dt > 0.0 else 1.0

	for side in ["left", "right"]:
		var up_name: String = side + "UpperArm"
		var lo_name: String = side + "LowerArm"
		var hd_name: String = side + "Hand"
		var sh_name: String = side + "Shoulder"
		if not (humanoid.has_bone(up_name) and humanoid.has_bone(lo_name) and humanoid.has_bone(hd_name)):
			continue
		if not (composed_bones.has(up_name) or composed_bones.has(lo_name)):
			_smooth_push[side] = Vector3.ZERO
			_smooth_ua_push[side] = Vector3.ZERO
			continue

		var sign_v: float = 1.0 if side == "left" else -1.0
		var sh_pos: Vector3 = _bone_local(humanoid, root_inv, up_name)
		var el_pos: Vector3 = _bone_local(humanoid, root_inv, lo_name)
		var wr_pos: Vector3 = _bone_local(humanoid, root_inv, hd_name)
		var lu: float = sh_pos.distance_to(el_pos)
		var ll: float = el_pos.distance_to(wr_pos)
		if lu < 0.05 or ll < 0.05:
			continue

		# 手首に加えて指先 (掌先)・前腕中間点も判定し、指先が胸/髪を突き抜けるのを防ぐ
		var palm_tip: Vector3
		var mid_dist: String = side + "MiddleDistal"
		var mid_prox: String = side + "MiddleProximal"
		if humanoid.has_bone(mid_dist):
			palm_tip = _bone_local(humanoid, root_inv, mid_dist)
		elif humanoid.has_bone(mid_prox):
			var mp_pos: Vector3 = _bone_local(humanoid, root_inv, mid_prox)
			palm_tip = wr_pos + (mp_pos - wr_pos) * 1.9
		else:
			var fa_dir := (wr_pos - el_pos).normalized() if wr_pos.distance_to(el_pos) > 1e-4 else torso_fwd
			palm_tip = wr_pos + fa_dir * (sh_w * 0.34)

		var p_cur: Vector3 = _resolve_obstacles(wr_pos, hand_pad, obstacles, torso_fwd, torso_left, sign_v)
		var mid_fa: Vector3 = el_pos.lerp(wr_pos, 0.55)
		p_cur += _resolve_obstacles(mid_fa + p_cur * 0.55, hand_pad * 0.85, obstacles, torso_fwd, torso_left, sign_v) * 1.15
		var tip_res: Vector3 = _resolve_obstacles(palm_tip + p_cur, hand_pad * 0.75, obstacles, torso_fwd, torso_left, sign_v)
		var raw_push: Vector3 = p_cur + tip_res * 0.5

		var prev_push: Vector3 = _smooth_push.get(side, Vector3.ZERO)
		var push: Vector3 = prev_push.lerp(raw_push, alpha)
		_smooth_push[side] = push

		# 二の腕 (上腕中間〜肘) の胸・体幹への弱い貫通抑制 (手首より弱く、自然な垂れ腕では干渉しない)
		var ua_mid: Vector3 = sh_pos.lerp(el_pos, 0.65)
		var d_ua_mid: Vector3 = _resolve_upper_arm_obstacles(ua_mid, ua_pad, torso_obstacles, torso_fwd, torso_left, sign_v)
		var el_from_mid: Vector3 = d_ua_mid * 0.95
		var d_ua_el: Vector3 = _resolve_upper_arm_obstacles(el_pos + el_from_mid, ua_pad, torso_obstacles, torso_fwd, torso_left, sign_v)
		var raw_ua_push: Vector3 = el_from_mid + d_ua_el * 0.55
		var max_ua_push: float = lu * 0.45
		if raw_ua_push.length() > max_ua_push:
			raw_ua_push = raw_ua_push.normalized() * max_ua_push
		var prev_ua_push: Vector3 = _smooth_ua_push.get(side, Vector3.ZERO)
		var ua_push: Vector3 = prev_ua_push.lerp(raw_ua_push, alpha)
		_smooth_ua_push[side] = ua_push

		var cur_tip_vec: Vector3 = palm_tip - wr_pos
		var probe_wr: Vector3 = wr_pos + push
		var pre_tip_clear := Vector3.ZERO
		if cur_tip_vec.length_squared() > 1e-5:
			pre_tip_clear = _resolve_obstacles(probe_wr + cur_tip_vec, hand_pad * 0.75, obstacles, torso_fwd, torso_left, sign_v)
		if push.length_squared() < 1e-8 and ua_push.length_squared() < 1e-8 and pre_tip_clear.length_squared() < 1e-8:
			continue

		var q_parent: Quaternion = q_chest
		if composed_bones.has(sh_name):
			q_parent = (q_parent * (composed_bones[sh_name] as Quaternion)).normalized()
		var q_up_local: Quaternion = composed_bones.get(up_name, Quaternion.IDENTITY)
		var q_lo_local: Quaternion = composed_bones.get(lo_name, Quaternion.IDENTITY)
		var q_up_world: Quaternion = (q_parent * q_up_local).normalized()
		var q_lo_world: Quaternion = (q_up_world * q_lo_local).normalized()
		var has_hand_comp: bool = composed_bones.has(hd_name)
		var q_hd_world: Quaternion = (q_lo_world * (composed_bones.get(hd_name, Quaternion.IDENTITY) as Quaternion)).normalized()

		var el_shifted: Vector3 = el_pos
		var actual_el_delta := Vector3.ZERO
		if ua_push.length_squared() >= 1e-8:
			var desired_u: Vector3 = (el_pos + ua_push) - sh_pos
			if desired_u.length_squared() > 1e-8:
				el_shifted = sh_pos + desired_u.normalized() * lu
				actual_el_delta = el_shifted - el_pos

		var new_up_world: Quaternion = q_up_world
		var new_lo_world: Quaternion = q_lo_world
		var new_wr: Vector3 = wr_pos
		if push.length_squared() >= 1e-8 or actual_el_delta.length_squared() >= 1e-8:
			var max_reach: float = (lu + ll) * 0.995
			var min_reach: float = maxf(0.05, absf(lu - ll) + 0.01)
			var wr_shift: Vector3 = push
			if actual_el_delta.length_squared() >= 1e-8:
				var orig_dist: float = wr_pos.distance_to(sh_pos)
				var straight_t: float = clampf((orig_dist / (lu + ll) - 0.65) / 0.30, 0.0, 1.0)
				var carry: float = 0.25 if push.length_squared() >= 1e-6 else lerpf(0.45, 0.85, straight_t)
				wr_shift += actual_el_delta * carry
			var rel_target: Vector3 = (wr_pos + wr_shift) - sh_pos
			var dist: float = clampf(rel_target.length(), min_reach, max_reach)
			var cur_u: Vector3 = (el_pos - sh_pos).normalized()
			var cur_l: Vector3 = (wr_pos - el_pos).normalized()
			var n: Vector3 = rel_target.normalized() if rel_target.length_squared() > 1e-8 else cur_u

			# 元の肘の向き (上腕方向) を極ベクトルにして平面の不連続反転を防ぐ
			var cur_arm: Vector3 = el_shifted - sh_pos
			var b: Vector3 = cur_arm - n * cur_arm.dot(n)
			if b.length_squared() < 1e-6:
				var fb := Vector3(sign_v * 0.3, -1.0, -0.3)
				b = fb - n * fb.dot(n)
				if b.length_squared() < 1e-6:
					b = Vector3(0.0, 0.0, 1.0) - n * n.z
			b = b.normalized()

			var cos_a: float = clampf((lu * lu + dist * dist - ll * ll) / (2.0 * lu * dist), -1.0, 1.0)
			var sin_a: float = sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
			var new_el: Vector3 = sh_pos + n * (cos_a * lu) + b * (sin_a * lu)

			# 肘自体が胴体にめり込む場合はポールベクトルを外側へ少し逃がす
			var el_closest: Vector3 = _closest_pt_seg(new_el, torso_cap_p0, torso_cap_p1)
			var el_safe: float = torso_cap_r + hand_pad * 0.5
			if new_el.distance_to(el_closest) < el_safe:
				var pen_ratio := clampf((el_safe - new_el.distance_to(el_closest)) / el_safe, 0.0, 1.0)
				var out_nudge := (torso_left * sign_v - torso_fwd * 0.25).normalized()
				var b2 := (b + out_nudge * (pen_ratio * 0.9))
				b2 = b2 - n * b2.dot(n)
				if b2.length_squared() > 1e-6:
					b = b2.normalized()
					new_el = sh_pos + n * (cos_a * lu) + b * (sin_a * lu)

			new_wr = sh_pos + n * dist
			var tgt_u: Vector3 = (new_el - sh_pos).normalized()
			var tgt_l: Vector3 = (new_wr - new_el).normalized()
			var dq_u: Quaternion = _shortest_arc(cur_u, tgt_u)
			var dq_l: Quaternion = _shortest_arc(cur_l, tgt_l)

			new_up_world = (dq_u * q_up_world).normalized()
			new_lo_world = (dq_l * q_lo_world).normalized()
			var new_up_local: Quaternion = (q_parent.inverse() * new_up_world).normalized()
			var new_lo_local: Quaternion = (new_up_world.inverse() * new_lo_world).normalized()

			composed_bones[up_name] = new_up_local
			composed_bones[lo_name] = new_lo_local
			humanoid.set_normalized_bone_rotation(up_name, new_up_local)
			humanoid.set_normalized_bone_rotation(lo_name, new_lo_local)

		# 指先が依然として体幹/胸/頭に刺さる場合は、手首を外向き・前向きに沿わせて逃がす
		var final_hd_world: Quaternion = q_hd_world
		if cur_tip_vec.length_squared() > 1e-5:
			var tip_clear: Vector3 = _resolve_obstacles(new_wr + cur_tip_vec, hand_pad * 0.75, obstacles, torso_fwd, torso_left, sign_v)
			if tip_clear.length_squared() > 1e-6:
				var desired_tip_vec: Vector3 = cur_tip_vec + tip_clear
				if desired_tip_vec.length_squared() > 1e-6:
					var dq_h: Quaternion = _shortest_arc(cur_tip_vec, desired_tip_vec)
					final_hd_world = (dq_h * q_hd_world).normalized()
					has_hand_comp = true
		if has_hand_comp:
			var new_hd_local: Quaternion = (new_lo_world.inverse() * final_hd_world).normalized()
			composed_bones[hd_name] = new_hd_local
			humanoid.set_normalized_bone_rotation(hd_name, new_hd_local)


func build_hand_spring_colliders(humanoid) -> Array:
	if humanoid == null or humanoid.skeleton == null:
		return []
	var sh_w: float = 0.36
	if humanoid.has_bone("leftUpperArm") and humanoid.has_bone("rightUpperArm"):
		var lw: Vector3 = humanoid.get_bone_world_transform("leftUpperArm").origin
		var rw: Vector3 = humanoid.get_bone_world_transform("rightUpperArm").origin
		sh_w = clampf(lw.distance_to(rw), 0.18, 0.55)
	var hand_r: float = clampf(sh_w * 0.18, 0.05, 0.085)
	var fore_r: float = clampf(sh_w * 0.15, 0.04, 0.07)

	var out: Array = []
	for side in ["left", "right"]:
		var hd_name: String = side + "Hand"
		var lo_name: String = side + "LowerArm"
		var mid_dist: String = side + "MiddleDistal"
		var mid_prox: String = side + "MiddleProximal"
		if humanoid.has_bone(hd_name):
			var hand_pos: Vector3 = humanoid.get_bone_world_transform(hd_name).origin
			var tip_pos := hand_pos
			if humanoid.has_bone(mid_dist):
				tip_pos = humanoid.get_bone_world_transform(mid_dist).origin
			elif humanoid.has_bone(mid_prox):
				var mp_pos: Vector3 = humanoid.get_bone_world_transform(mid_prox).origin
				tip_pos = hand_pos + (mp_pos - hand_pos) * 1.9
			var col_h = VrmSpringBoneScript.ColliderDef.new()
			if tip_pos.distance_to(hand_pos) > 0.01:
				col_h.shape = "capsule"
				col_h.w_p0 = hand_pos
				col_h.w_p1 = tip_pos
			else:
				col_h.shape = "sphere"
				col_h.w_p0 = hand_pos
			col_h.radius = hand_r
			out.append(col_h)
		if humanoid.has_bone(lo_name) and humanoid.has_bone(hd_name):
			var cap = VrmSpringBoneScript.ColliderDef.new()
			cap.shape = "capsule"
			cap.w_p0 = humanoid.get_bone_world_transform(lo_name).origin
			cap.w_p1 = humanoid.get_bone_world_transform(hd_name).origin
			cap.radius = fore_r
			out.append(cap)
	return out


static func _bone_local(humanoid, root_inv: Transform3D, human_name: String) -> Vector3:
	return root_inv * humanoid.get_bone_world_transform(human_name).origin


static func _resolve_obstacles(pt: Vector3, pad: float, obstacles: Array, torso_fwd: Vector3, torso_left: Vector3, sign_v: float) -> Vector3:
	var p := pt
	for _pass in 2:
		for obs in obstacles:
			var c: Vector3 = obs["p0"] if obs["type"] == "sphere" else _closest_pt_seg(p, obs["p0"], obs["p1"])
			var r_safe: float = float(obs["r"]) + pad
			var d_vec := p - c
			var dist_sq := d_vec.length_squared()
			if dist_sq < r_safe * r_safe:
				var dist := sqrt(dist_sq)
				var push_dir := (d_vec / dist) if dist > 1e-5 else torso_fwd
				var fwd_dot := push_dir.dot(torso_fwd)
				if obs["kind"] == "torso":
					if fwd_dot < 0.35:
						push_dir += torso_fwd * (0.45 - fwd_dot)
					push_dir += torso_left * (sign_v * 0.25)
				else:
					if fwd_dot < 0.20:
						push_dir += torso_fwd * (0.30 - fwd_dot)
					push_dir += torso_left * (sign_v * 0.30)
				if push_dir.length_squared() > 1e-8:
					var u := push_dir.normalized()
					# バイアス方向へ安全球表面まで厳密に押し出す (めり込み残りを防ぐ)
					var b_q := d_vec.dot(u)
					var c_q := dist_sq - r_safe * r_safe
					var step_t := -b_q + sqrt(maxf(0.0, b_q * b_q - c_q))
					p += u * step_t
	return p - pt


static func _resolve_upper_arm_obstacles(pt: Vector3, pad: float, torso_obstacles: Array, torso_fwd: Vector3, torso_left: Vector3, sign_v: float) -> Vector3:
	var p: Vector3 = pt
	var out_lat: Vector3 = torso_left * sign_v
	for _pass in 2:
		for obs in torso_obstacles:
			var c: Vector3 = obs["p0"] if obs["type"] == "sphere" else _closest_pt_seg(p, obs["p0"], obs["p1"])
			var r_safe: float = float(obs["r"]) + pad
			var d_vec: Vector3 = p - c
			var dist_sq: float = d_vec.length_squared()
			if dist_sq < r_safe * r_safe:
				var dist: float = sqrt(dist_sq)
				var push_dir: Vector3 = (d_vec / dist) if dist > 1e-5 else out_lat
				var lat_dot: float = push_dir.dot(out_lat)
				if lat_dot < 0.30:
					push_dir += out_lat * (0.40 - lat_dot)
				if d_vec.dot(torso_fwd) > -0.02:
					var fwd_dot: float = push_dir.dot(torso_fwd)
					if fwd_dot < 0.25:
						push_dir += torso_fwd * (0.30 - fwd_dot)
				if push_dir.length_squared() > 1e-8:
					var u: Vector3 = push_dir.normalized()
					var b_q: float = d_vec.dot(u)
					var c_q: float = dist_sq - r_safe * r_safe
					var step_t: float = -b_q + sqrt(maxf(0.0, b_q * b_q - c_q))
					p += u * step_t
	return p - pt


static func _closest_pt_seg(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 1e-10:
		return a
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return a + ab * t


static func _shortest_arc(u: Vector3, v: Vector3) -> Quaternion:
	var nu := u.normalized()
	var nv := v.normalized()
	var d := nu.dot(nv)
	if d > 0.999999:
		return Quaternion.IDENTITY
	if d < -0.999999:
		var ortho := Vector3.RIGHT.cross(nu)
		if ortho.length_squared() < 1e-6:
			ortho = Vector3.UP.cross(nu)
		return Quaternion(ortho.normalized(), PI)
	var c := nu.cross(nv)
	return Quaternion(c.x, c.y, c.z, 1.0 + d).normalized()
