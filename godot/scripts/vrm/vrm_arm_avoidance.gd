class_name VrmArmAvoidance
extends RefCounted

## トラッキング中の腕・手が体幹・胸・頭(+横髪)へめり込むのを 2-Bone IK で回避し、
## 手のひら・前腕の SpringBone 外部コライダーを生成する。

const VrmSpringBoneScript := preload("res://scripts/vrm/vrm_springbone.gd")

var _smooth_push: Dictionary = {
	"left": Vector3.ZERO,
	"right": Vector3.ZERO,
}


func reset() -> void:
	_smooth_push["left"] = Vector3.ZERO
	_smooth_push["right"] = Vector3.ZERO


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

	var obstacles: Array = []
	# 1) 体幹カプセル + 胸前方スフィア + 頭部/横髪スフィア (肩幅スケール基準)
	obstacles.append({
		"type": "capsule",
		"p0": hips_pos + torso_up * (sh_w * 0.15),
		"p1": up_chest_pos,
		"r": clampf(sh_w * 0.36, 0.08, 0.18),
		"kind": "torso",
	})
	obstacles.append({
		"type": "sphere",
		"p0": chest_pos + torso_fwd * (sh_w * 0.16) - torso_up * (sh_w * 0.05),
		"p1": Vector3.ZERO,
		"r": clampf(sh_w * 0.34, 0.08, 0.17),
		"kind": "torso",
	})
	obstacles.append({
		"type": "sphere",
		"p0": head_pos + Vector3(0.0, sh_w * 0.20, 0.0),
		"p1": Vector3.ZERO,
		"r": clampf(sh_w * 0.45, 0.11, 0.22),
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

	var hand_pad: float = clampf(sh_w * 0.14, 0.035, 0.075)
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
			continue

		var sign_v: float = 1.0 if side == "left" else -1.0
		var sh_pos: Vector3 = _bone_local(humanoid, root_inv, up_name)
		var el_pos: Vector3 = _bone_local(humanoid, root_inv, lo_name)
		var wr_pos: Vector3 = _bone_local(humanoid, root_inv, hd_name)
		var lu: float = sh_pos.distance_to(el_pos)
		var ll: float = el_pos.distance_to(wr_pos)
		if lu < 0.05 or ll < 0.05:
			continue

		var push_wr: Vector3 = _resolve_obstacles(wr_pos, hand_pad, obstacles, torso_fwd, torso_left, sign_v)
		var mid_fa: Vector3 = el_pos.lerp(wr_pos, 0.55)
		var push_fa: Vector3 = _resolve_obstacles(mid_fa, hand_pad * 0.85, obstacles, torso_fwd, torso_left, sign_v)
		var raw_push: Vector3 = push_wr if push_wr.length_squared() >= push_fa.length_squared() else (push_fa * 1.15)

		var prev_push: Vector3 = _smooth_push.get(side, Vector3.ZERO)
		var push: Vector3 = prev_push.lerp(raw_push, alpha)
		_smooth_push[side] = push
		if push.length_squared() < 1e-8:
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

		var max_reach: float = (lu + ll) * 0.995
		var min_reach: float = maxf(0.05, absf(lu - ll) + 0.01)
		var rel_target: Vector3 = (wr_pos + push) - sh_pos
		var dist: float = clampf(rel_target.length(), min_reach, max_reach)
		var cur_u: Vector3 = (el_pos - sh_pos).normalized()
		var cur_l: Vector3 = (wr_pos - el_pos).normalized()
		var n: Vector3 = rel_target.normalized() if rel_target.length_squared() > 1e-8 else cur_u

		# 元の肘の向き (上腕方向) を極ベクトルにして平面の不連続反転を防ぐ
		var cur_arm: Vector3 = el_pos - sh_pos
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
		var new_wr: Vector3 = sh_pos + n * dist

		var tgt_u: Vector3 = (new_el - sh_pos).normalized()
		var tgt_l: Vector3 = (new_wr - new_el).normalized()
		var dq_u: Quaternion = _shortest_arc(cur_u, tgt_u)
		var dq_l: Quaternion = _shortest_arc(cur_l, tgt_l)

		var new_up_world: Quaternion = (dq_u * q_up_world).normalized()
		var new_lo_world: Quaternion = (dq_l * q_lo_world).normalized()
		var new_up_local: Quaternion = (q_parent.inverse() * new_up_world).normalized()
		var new_lo_local: Quaternion = (new_up_world.inverse() * new_lo_world).normalized()

		composed_bones[up_name] = new_up_local
		composed_bones[lo_name] = new_lo_local
		humanoid.set_normalized_bone_rotation(up_name, new_up_local)
		humanoid.set_normalized_bone_rotation(lo_name, new_lo_local)
		if has_hand_comp:
			var new_hd_local: Quaternion = (new_lo_world.inverse() * q_hd_world).normalized()
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
	var palm_r: float = clampf(sh_w * 0.16, 0.04, 0.08)
	var fore_r: float = clampf(sh_w * 0.14, 0.035, 0.065)

	var out: Array = []
	for side in ["left", "right"]:
		var hd_name: String = side + "Hand"
		var lo_name: String = side + "LowerArm"
		var mid_name: String = side + "MiddleProximal"
		if humanoid.has_bone(hd_name):
			var palm_pos: Vector3 = humanoid.get_bone_world_transform(hd_name).origin
			if humanoid.has_bone(mid_name):
				palm_pos = palm_pos.lerp(humanoid.get_bone_world_transform(mid_name).origin, 0.55)
			var sph = VrmSpringBoneScript.ColliderDef.new()
			sph.shape = "sphere"
			sph.w_p0 = palm_pos
			sph.radius = palm_r
			out.append(sph)
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
			var dist := d_vec.length()
			if dist < r_safe:
				var pen := r_safe - dist
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
					p += push_dir.normalized() * pen
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
