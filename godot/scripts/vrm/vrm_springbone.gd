class_name VrmSpringBone
extends RefCounted

## Official VRMC_springBone-1.0 + VRMC_springBone_extended_collider + VRMC_springBone_limit
## Exact Verlet integration solver with center-space support, fixed sub-stepping,
## sphere / capsule / inside-sphere / inside-capsule / plane colliders, cone/hinge limits,
## and configurable external wind.

const FIXED_SUBSTEP := 1.0 / 120.0
const MAX_ACCUM_DT := 0.1

var colliders: Array = [] # Array[ColliderDef]
var collider_groups: Array = [] # Array[Array[int]]
var springs: Array = [] # Array[SpringChain]
var external_wind: Vector3 = Vector3.ZERO
var gravity_scale: float = 1.0
var stiffness_scale: float = 1.0
var enabled: bool = true
var _accum_dt: float = 0.0


class ColliderDef:
	var node_ref: Dictionary
	var shape: String # "sphere" | "capsule" | "sphereInside" | "capsuleInside" | "plane"
	var offset: Vector3 = Vector3.ZERO
	var tail: Vector3 = Vector3.ZERO
	var radius: float = 0.05
	var normal: Vector3 = Vector3.UP


class JointState:
	var node_ref: Dictionary
	var parent_ref: Dictionary
	var has_parent: bool = false
	var rest_local_rot: Quaternion = Quaternion.IDENTITY
	var rest_local_pos: Vector3 = Vector3.ZERO
	var hit_radius: float = 0.0
	var stiffness: float = 1.0
	var gravity_power: float = 0.0
	var gravity_dir: Vector3 = Vector3.DOWN
	var drag_force: float = 0.5
	var limit_type: String = "none" # "none" | "cone" | "hinge"
	var limit_offset: Quaternion = Quaternion.IDENTITY
	var limit_angle: float = PI
	var limit_angle_min: float = -PI
	var limit_angle_max: float = PI

	# Runtime Verlet state in center space
	var bone_axis_local: Vector3 = Vector3.DOWN
	var bone_length: float = 0.1
	var current_tail: Vector3 = Vector3.ZERO
	var prev_tail: Vector3 = Vector3.ZERO
	var initialized: bool = false


class SpringChain:
	var name: String = ""
	var has_center: bool = false
	var center_ref: Dictionary
	var joints: Array = [] # Array[JointState]
	var collider_indices: Array[int] = []


func setup(gltf_json: Dictionary, node_map: Dictionary) -> void:
	colliders.clear()
	collider_groups.clear()
	springs.clear()
	_accum_dt = 0.0

	var exts: Dictionary = gltf_json.get("extensions", {})
	if not exts.has("VRMC_springBone"):
		return
	var sb: Dictionary = exts["VRMC_springBone"]

	for raw_col in sb.get("colliders", []):
		var gnode: int = int(raw_col.get("node", -1))
		if not node_map.has(gnode):
			colliders.append(null)
			continue
		var cdef := ColliderDef.new()
		cdef.node_ref = node_map[gnode]
		var shape: Dictionary = raw_col.get("shape", {})
		var c_exts: Dictionary = raw_col.get("extensions", {})
		if c_exts.has("VRMC_springBone_extended_collider"):
			shape = c_exts["VRMC_springBone_extended_collider"].get("shape", shape)

		if shape.has("sphere"):
			var s: Dictionary = shape["sphere"]
			cdef.shape = "sphereInside" if bool(s.get("inside", false)) else "sphere"
			cdef.offset = _arr3(s.get("offset", [0, 0, 0]))
			cdef.radius = float(s.get("radius", 0.05))
		elif shape.has("capsule"):
			var cp: Dictionary = shape["capsule"]
			cdef.shape = "capsuleInside" if bool(cp.get("inside", false)) else "capsule"
			cdef.offset = _arr3(cp.get("offset", [0, 0, 0]))
			cdef.tail = _arr3(cp.get("tail", [0, 0, 0]))
			cdef.radius = float(cp.get("radius", 0.05))
		elif shape.has("sphereInside"):
			var si: Dictionary = shape["sphereInside"]
			cdef.shape = "sphereInside"
			cdef.offset = _arr3(si.get("offset", [0, 0, 0]))
			cdef.radius = float(si.get("radius", 0.05))
		elif shape.has("capsuleInside"):
			var ci: Dictionary = shape["capsuleInside"]
			cdef.shape = "capsuleInside"
			cdef.offset = _arr3(ci.get("offset", [0, 0, 0]))
			cdef.tail = _arr3(ci.get("tail", [0, 0, 0]))
			cdef.radius = float(ci.get("radius", 0.05))
		elif shape.has("plane"):
			var pl: Dictionary = shape["plane"]
			cdef.shape = "plane"
			cdef.offset = _arr3(pl.get("offset", [0, 0, 0]))
			cdef.normal = _arr3(pl.get("normal", [0, 1, 0])).normalized()
		else:
			cdef.shape = "sphere"
			cdef.radius = 0.0
		colliders.append(cdef)

	for grp in sb.get("colliderGroups", []):
		var list: Array[int] = []
		for ci in grp.get("colliders", []):
			list.append(int(ci))
		collider_groups.append(list)

	var jnodes: Array = gltf_json.get("nodes", [])
	for raw_sp in sb.get("springs", []):
		var raw_joints: Array = raw_sp.get("joints", [])
		if raw_joints.size() < 2:
			continue

		var chain := SpringChain.new()
		chain.name = str(raw_sp.get("name", "spring"))
		var center_node: int = int(raw_sp.get("center", -1))
		if center_node >= 0 and node_map.has(center_node):
			chain.has_center = true
			chain.center_ref = node_map[center_node]

		for cg_idx in raw_sp.get("colliderGroups", []):
			var g: int = int(cg_idx)
			if g >= 0 and g < collider_groups.size():
				for col_idx in collider_groups[g]:
					if col_idx >= 0 and col_idx < colliders.size() and colliders[col_idx] != null:
						if not chain.collider_indices.has(col_idx):
							chain.collider_indices.append(col_idx)

		for j_i in range(raw_joints.size() - 1):
			var rj: Dictionary = raw_joints[j_i]
			var next_rj: Dictionary = raw_joints[j_i + 1]
			var gnode: int = int(rj.get("node", -1))
			var next_gnode: int = int(next_rj.get("node", -1))
			if not node_map.has(gnode) or not node_map.has(next_gnode):
				continue

			var js := JointState.new()
			js.node_ref = node_map[gnode]
			var parent_ref := _get_parent_ref(js.node_ref, jnodes, gnode, node_map)
			js.has_parent = not parent_ref.is_empty()
			js.parent_ref = parent_ref
			js.rest_local_rot = _get_rest_local_rot(js.node_ref)
			js.rest_local_pos = _get_rest_local_pos(js.node_ref)
			js.hit_radius = float(rj.get("hitRadius", 0.0))
			js.stiffness = float(rj.get("stiffness", 1.0))
			js.gravity_power = float(rj.get("gravityPower", 0.0))
			js.gravity_dir = _arr3(rj.get("gravityDir", [0.0, -1.0, 0.0]))
			if js.gravity_dir.length_squared() < 1e-6:
				js.gravity_dir = Vector3.DOWN
			else:
				js.gravity_dir = js.gravity_dir.normalized()
			js.drag_force = clampf(float(rj.get("dragForce", 0.5)), 0.0, 1.0)

			# Optional VRMC_springBone_limit extension
			var j_exts: Dictionary = rj.get("extensions", {})
			if j_exts.has("VRMC_springBone_limit"):
				var lim: Dictionary = j_exts["VRMC_springBone_limit"]
				if lim.has("cone"):
					var cone: Dictionary = lim["cone"]
					js.limit_type = "cone"
					js.limit_angle = float(cone.get("angle", PI))
					js.limit_offset = _arr_quat(cone.get("rotation", [0, 0, 0, 1]))
				elif lim.has("hinge"):
					var h: Dictionary = lim["hinge"]
					js.limit_type = "hinge"
					js.limit_angle_min = float(h.get("minAngle", -PI))
					js.limit_angle_max = float(h.get("maxAngle", PI))
					js.limit_offset = _arr_quat(h.get("rotation", [0, 0, 0, 1]))

			var next_rest_pos: Vector3 = _get_rest_local_pos(node_map[next_gnode])
			js.bone_length = maxf(next_rest_pos.length(), 0.001)
			js.bone_axis_local = (next_rest_pos / js.bone_length) if next_rest_pos.length_squared() > 1e-8 else Vector3.DOWN
			chain.joints.append(js)

		if not chain.joints.is_empty():
			springs.append(chain)

	reset_state()


func reset_state() -> void:
	for chain: SpringChain in springs:
		var center_inv := _get_center_transform(chain).affine_inverse()
		for js: JointState in chain.joints:
			var world_xf := _get_world_transform(js.node_ref)
			var tail_world := world_xf * (js.bone_axis_local * js.bone_length)
			var tail_center := center_inv * tail_world
			js.current_tail = tail_center
			js.prev_tail = tail_center
			js.initialized = true


func update(dt: float) -> void:
	if not enabled or springs.is_empty():
		return
	var clamped_dt := clampf(dt, 0.0, MAX_ACCUM_DT)
	if clamped_dt <= 0.0:
		return
	_accum_dt += clamped_dt
	var steps := 0
	while _accum_dt >= FIXED_SUBSTEP and steps < 6:
		_step_once(FIXED_SUBSTEP)
		_accum_dt -= FIXED_SUBSTEP
		steps += 1
	if steps == 0 and _accum_dt > 0.0001:
		# Still apply current pose rotation smoothly even at >120fps
		_step_once(_accum_dt)
		_accum_dt = 0.0


func _step_once(dt: float) -> void:
	for chain: SpringChain in springs:
		var center_xf := _get_center_transform(chain)
		var center_inv := center_xf.affine_inverse()

		for js: JointState in chain.joints:
			var parent_world_xf := _get_parent_world_transform(js)
			var head_world := parent_world_xf * js.rest_local_pos
			var head_center := center_inv * head_world

			if not js.initialized:
				var init_tail_world := _get_world_transform(js.node_ref) * (js.bone_axis_local * js.bone_length)
				js.current_tail = center_inv * init_tail_world
				js.prev_tail = js.current_tail
				js.initialized = true

			var parent_rot_world := parent_world_xf.basis.orthonormalized().get_rotation_quaternion()
			var rest_rot_world := (parent_rot_world * js.rest_local_rot).normalized()
			var world_bone_axis := rest_rot_world * js.bone_axis_local
			var center_bone_axis := (center_inv.basis.orthonormalized() * world_bone_axis).normalized()

			# Inertia + Drag
			var inertia := (js.current_tail - js.prev_tail) * (1.0 - js.drag_force)
			# Stiffness pull back toward rest bone axis
			var stiffness_force := center_bone_axis * (js.stiffness * stiffness_scale * dt)
			# Gravity + external wind
			var ext_world := (js.gravity_dir * js.gravity_power * gravity_scale + external_wind) * dt
			var ext_center := center_inv.basis.orthonormalized() * ext_world

			var next_tail := js.current_tail + inertia + stiffness_force + ext_center

			# Length constraint
			var dir := next_tail - head_center
			if dir.length_squared() < 1e-10:
				dir = center_bone_axis
			else:
				dir = dir.normalized()
			next_tail = head_center + dir * js.bone_length

			# Colliders in world space -> project back to bone_length sphere after each collider per VRM 1.0 spec
			if not chain.collider_indices.is_empty():
				var tail_world := center_xf * next_tail
				for col_idx in chain.collider_indices:
					var cdef: ColliderDef = colliders[col_idx]
					if cdef == null:
						continue
					var pushed := _resolve_collider(cdef, tail_world, js.hit_radius)
					if pushed != tail_world:
						var d_w := pushed - head_world
						if d_w.length_squared() > 1e-10:
							tail_world = head_world + d_w.normalized() * js.bone_length
				next_tail = center_inv * tail_world

			# Optional joint angle limit (cone / hinge)
			if js.limit_type != "none":
				next_tail = _apply_joint_limit(js, head_center, next_tail, center_inv, rest_rot_world)

			js.prev_tail = js.current_tail
			js.current_tail = next_tail

			# Apply bone local rotation so bone_axis_local points from head -> next_tail
			var final_tail_world := center_xf * next_tail
			var target_dir_world := (final_tail_world - head_world).normalized()
			var delta_world := _shortest_arc(world_bone_axis, target_dir_world)
			var target_world_rot := (delta_world * rest_rot_world).normalized()
			var local_rot := (parent_rot_world.inverse() * target_world_rot).normalized()
			_set_local_rot(js.node_ref, local_rot)


func _resolve_collider(cdef: ColliderDef, tail_world: Vector3, hit_radius: float) -> Vector3:
	var c_xf := _get_world_transform(cdef.node_ref)
	match cdef.shape:
		"sphere":
			var center := c_xf * cdef.offset
			var r := cdef.radius + hit_radius
			var d := tail_world - center
			var dist := d.length()
			if dist < r and dist > 1e-6:
				return center + (d / dist) * r
			elif dist <= 1e-6 and r > 0.0:
				return center + Vector3.UP * r
		"sphereInside":
			var center := c_xf * cdef.offset
			var r := maxf(cdef.radius - hit_radius, 0.0)
			var d := tail_world - center
			var dist := d.length()
			if dist > r and dist > 1e-6:
				return center + (d / dist) * r
		"capsule":
			var p0 := c_xf * cdef.offset
			var p1 := c_xf * cdef.tail
			var closest := _closest_point_segment(tail_world, p0, p1)
			var r := cdef.radius + hit_radius
			var d := tail_world - closest
			var dist := d.length()
			if dist < r and dist > 1e-6:
				return closest + (d / dist) * r
		"capsuleInside":
			var p0 := c_xf * cdef.offset
			var p1 := c_xf * cdef.tail
			var closest := _closest_point_segment(tail_world, p0, p1)
			var r := maxf(cdef.radius - hit_radius, 0.0)
			var d := tail_world - closest
			var dist := d.length()
			if dist > r and dist > 1e-6:
				return closest + (d / dist) * r
		"plane":
			var p := c_xf * cdef.offset
			var n := (c_xf.basis.orthonormalized() * cdef.normal).normalized()
			var signed_dist := (tail_world - p).dot(n)
			if signed_dist < hit_radius:
				return tail_world + n * (hit_radius - signed_dist)
	return tail_world


func _apply_joint_limit(
	js: JointState,
	head_center: Vector3,
	tail_center: Vector3,
	center_inv: Transform3D,
	rest_rot_world: Quaternion
) -> Vector3:
	var dir_center := (tail_center - head_center).normalized()
	var limit_frame_world := (rest_rot_world * js.limit_offset).normalized()
	var limit_frame_center := (center_inv.basis.orthonormalized().get_rotation_quaternion() * limit_frame_world).normalized()
	var ref_dir := (limit_frame_center * js.bone_axis_local).normalized()

	if js.limit_type == "cone":
		var dot_v := clampf(ref_dir.dot(dir_center), -1.0, 1.0)
		var ang := acos(dot_v)
		if ang > js.limit_angle and ang > 1e-5:
			var axis := ref_dir.cross(dir_center)
			if axis.length_squared() < 1e-8:
				axis = Vector3.UP
			else:
				axis = axis.normalized()
			var clamped_dir := Quaternion(axis, js.limit_angle) * ref_dir
			return head_center + clamped_dir.normalized() * js.bone_length
	elif js.limit_type == "hinge":
		var dir_local := (limit_frame_center.inverse() * dir_center).normalized()
		# Hinge rotates in X-Y plane around Z axis of limit frame
		var base_ang := atan2(js.bone_axis_local.y, js.bone_axis_local.x)
		var cur_ang := atan2(dir_local.y, dir_local.x)
		var rel_ang := wrapf(cur_ang - base_ang, -PI, PI)
		var clamped := clampf(rel_ang, js.limit_angle_min, js.limit_angle_max)
		var target_local := Vector3(cos(base_ang + clamped), sin(base_ang + clamped), 0.0).normalized()
		var target_center := (limit_frame_center * target_local).normalized()
		return head_center + target_center * js.bone_length
	return tail_center


func get_stats() -> Dictionary:
	return {
		"colliders": colliders.size(),
		"springs": springs.size(),
		"enabled": enabled,
		"wind": [external_wind.x, external_wind.y, external_wind.z],
	}


static func _closest_point_segment(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := b - a
	var denom := ab.length_squared()
	if denom < 1e-10:
		return a
	var t := clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return a + ab * t


static func _shortest_arc(from_v: Vector3, to_v: Vector3) -> Quaternion:
	var d := clampf(from_v.dot(to_v), -1.0, 1.0)
	if d > 0.999999:
		return Quaternion.IDENTITY
	if d < -0.999999:
		var ortho := from_v.cross(Vector3.UP)
		if ortho.length_squared() < 1e-6:
			ortho = from_v.cross(Vector3.RIGHT)
		return Quaternion(ortho.normalized(), PI)
	return Quaternion(from_v.cross(to_v).normalized(), acos(d))


func _get_center_transform(chain: SpringChain) -> Transform3D:
	if chain.has_center:
		return _get_world_transform(chain.center_ref)
	return Transform3D.IDENTITY


func _get_parent_world_transform(js: JointState) -> Transform3D:
	if js.has_parent:
		return _get_world_transform(js.parent_ref)
	if js.node_ref["type"] == "bone":
		var skel: Skeleton3D = js.node_ref["skeleton"]
		return _safe_global_transform(skel)
	var n: Node3D = js.node_ref["node"]
	var p := n.get_parent()
	if p is Node3D:
		return _safe_global_transform(p as Node3D)
	return Transform3D.IDENTITY


static func _get_parent_ref(ref: Dictionary, _jnodes: Array, _gnode: int, _node_map: Dictionary) -> Dictionary:
	if ref["type"] == "bone":
		var skel: Skeleton3D = ref["skeleton"]
		var p_idx: int = skel.get_bone_parent(ref["bone_idx"])
		if p_idx >= 0:
			return {"type": "bone", "skeleton": skel, "bone_idx": p_idx}
		return {}
	return {}


static func _safe_global_transform(n: Node3D) -> Transform3D:
	if not is_instance_valid(n):
		return Transform3D.IDENTITY
	if n.is_inside_tree():
		return n.global_transform
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur is Node3D:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


static func _get_world_transform(ref: Dictionary) -> Transform3D:
	if ref.is_empty():
		return Transform3D.IDENTITY
	if ref["type"] == "bone":
		var skel: Skeleton3D = ref["skeleton"]
		return _safe_global_transform(skel) * skel.get_bone_global_pose(ref["bone_idx"])
	var n: Node3D = ref["node"]
	return _safe_global_transform(n)


static func _get_rest_local_rot(ref: Dictionary) -> Quaternion:
	if ref["type"] == "bone":
		var skel: Skeleton3D = ref["skeleton"]
		return skel.get_bone_rest(ref["bone_idx"]).basis.orthonormalized().get_rotation_quaternion()
	var xf: Transform3D = ref["rest_local"]
	return xf.basis.orthonormalized().get_rotation_quaternion()


static func _get_rest_local_pos(ref: Dictionary) -> Vector3:
	if ref["type"] == "bone":
		var skel: Skeleton3D = ref["skeleton"]
		return skel.get_bone_rest(ref["bone_idx"]).origin
	var xf: Transform3D = ref["rest_local"]
	return xf.origin


static func _set_local_rot(ref: Dictionary, q: Quaternion) -> void:
	if ref["type"] == "bone":
		var skel: Skeleton3D = ref["skeleton"]
		skel.set_bone_pose_rotation(ref["bone_idx"], q.normalized())
	else:
		var n: Node3D = ref["node"]
		var sc := n.transform.basis.get_scale()
		n.transform = Transform3D(Basis(q.normalized()).scaled(sc), n.transform.origin)


static func _arr3(a: Variant) -> Vector3:
	if typeof(a) == TYPE_ARRAY and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


static func _arr_quat(a: Variant) -> Quaternion:
	if typeof(a) == TYPE_ARRAY and a.size() >= 4:
		return Quaternion(float(a[0]), float(a[1]), float(a[2]), float(a[3])).normalized()
	return Quaternion.IDENTITY
