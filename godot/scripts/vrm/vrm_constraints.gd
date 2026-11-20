class_name VrmConstraints
extends RefCounted

## Official VRMC_node_constraint-1.0 subsystem.
## Supports rotation, roll (X/Y/Z), and aim (Positive/Negative X/Y/Z) constraints
## across both Skeleton3D bones and Scene Node3Ds, evaluated in topological order.

var _constraints: Array = [] # Sorted list of ConstraintEntry


class ConstraintEntry:
	var kind: String # "rotation" | "roll" | "aim"
	var dst_node_idx: int
	var src_node_idx: int
	var dst_ref: Dictionary
	var src_ref: Dictionary
	var weight: float = 1.0
	var axis_vec: Vector3 = Vector3.RIGHT # For roll or aim


func setup(gltf_json: Dictionary, node_map: Dictionary) -> void:
	_constraints.clear()
	var jnodes: Array = gltf_json.get("nodes", [])
	var raw_entries: Array = []
	var dst_to_entry: Dictionary = {}

	for i in range(jnodes.size()):
		var jn: Dictionary = jnodes[i]
		var exts: Dictionary = jn.get("extensions", {})
		if not exts.has("VRMC_node_constraint"):
			continue
		var nc: Dictionary = exts["VRMC_node_constraint"]
		var c: Dictionary = nc.get("constraint", {})
		if not node_map.has(i):
			continue

		var entry := ConstraintEntry.new()
		entry.dst_node_idx = i
		entry.dst_ref = node_map[i]

		if c.has("rotation"):
			var r: Dictionary = c["rotation"]
			entry.kind = "rotation"
			entry.src_node_idx = int(r.get("source", -1))
			entry.weight = clampf(float(r.get("weight", 1.0)), 0.0, 1.0)
		elif c.has("roll"):
			var rl: Dictionary = c["roll"]
			entry.kind = "roll"
			entry.src_node_idx = int(rl.get("source", -1))
			entry.weight = clampf(float(rl.get("weight", 1.0)), 0.0, 1.0)
			entry.axis_vec = _parse_roll_axis(str(rl.get("rollAxis", "X")))
		elif c.has("aim"):
			var am: Dictionary = c["aim"]
			entry.kind = "aim"
			entry.src_node_idx = int(am.get("source", -1))
			entry.weight = clampf(float(am.get("weight", 1.0)), 0.0, 1.0)
			entry.axis_vec = _parse_aim_axis(str(am.get("aimAxis", "PositiveX")))
		else:
			continue

		if not node_map.has(entry.src_node_idx):
			continue
		entry.src_ref = node_map[entry.src_node_idx]
		raw_entries.append(entry)
		dst_to_entry[entry.dst_node_idx] = entry

	# Topological sort so dependencies (including source constraints) evaluate first
	var visited: Dictionary = {}
	for entry in raw_entries:
		_topo_visit(entry, dst_to_entry, visited, {})


func _topo_visit(entry: ConstraintEntry, dst_map: Dictionary, visited: Dictionary, visiting: Dictionary) -> void:
	if visited.has(entry.dst_node_idx) or visiting.has(entry.dst_node_idx):
		return
	visiting[entry.dst_node_idx] = true
	if dst_map.has(entry.src_node_idx):
		_topo_visit(dst_map[entry.src_node_idx], dst_map, visited, visiting)
	visiting.erase(entry.dst_node_idx)
	visited[entry.dst_node_idx] = true
	_constraints.append(entry)


func get_constraint_count() -> int:
	return _constraints.size()


func get_summary() -> Array:
	var out := []
	for e: ConstraintEntry in _constraints:
		out.append({
			"kind": e.kind,
			"dst_node": e.dst_node_idx,
			"src_node": e.src_node_idx,
			"weight": e.weight,
		})
	return out


func update() -> void:
	for e: ConstraintEntry in _constraints:
		if e.weight <= 0.0001:
			continue
		match e.kind:
			"rotation":
				_eval_rotation(e)
			"roll":
				_eval_roll(e)
			"aim":
				_eval_aim(e)


func _eval_rotation(e: ConstraintEntry) -> void:
	var src_rest := _get_rest_local_rot(e.src_ref)
	var src_cur := _get_cur_local_rot(e.src_ref)
	var dst_rest := _get_rest_local_rot(e.dst_ref)

	var delta_src := src_rest.inverse() * src_cur
	var target_dst := (dst_rest * delta_src).normalized()
	var out_rot := dst_rest.slerp(target_dst, e.weight).normalized()
	_set_cur_local_rot(e.dst_ref, out_rot)


func _eval_roll(e: ConstraintEntry) -> void:
	var src_rest_local := _get_rest_local_rot(e.src_ref)
	var src_cur_local := _get_cur_local_rot(e.src_ref)
	var src_parent_rest_world := _get_parent_rest_world_rot(e.src_ref)
	var dst_rest_local := _get_rest_local_rot(e.dst_ref)
	var dst_rest_world := _get_rest_world_rot(e.dst_ref)

	var delta_src_world := src_parent_rest_world * (src_cur_local * src_rest_local.inverse()) * src_parent_rest_world.inverse()
	var delta_in_dst := (dst_rest_world.inverse() * delta_src_world * dst_rest_world).normalized()
	if delta_in_dst.w < 0.0:
		delta_in_dst = -delta_in_dst

	var proj := Vector3(delta_in_dst.x, delta_in_dst.y, delta_in_dst.z).dot(e.axis_vec) * e.axis_vec
	var twist := Quaternion(proj.x, proj.y, proj.z, delta_in_dst.w)
	if twist.length_squared() < 1e-8:
		twist = Quaternion.IDENTITY
	else:
		twist = twist.normalized()

	var target_dst := (dst_rest_local * twist).normalized()
	var out_rot := dst_rest_local.slerp(target_dst, e.weight).normalized()
	_set_cur_local_rot(e.dst_ref, out_rot)


func _eval_aim(e: ConstraintEntry) -> void:
	var dst_pos := _get_world_pos(e.dst_ref)
	var src_pos := _get_world_pos(e.src_ref)
	var to_vec := src_pos - dst_pos
	if to_vec.length_squared() < 1e-8:
		return
	to_vec = to_vec.normalized()

	var dst_parent_world_rot := _get_parent_cur_world_rot(e.dst_ref)
	var dst_rest_local := _get_rest_local_rot(e.dst_ref)
	var aim_world_dir := ((dst_parent_world_rot * dst_rest_local) * e.axis_vec).normalized()

	var world_delta := _shortest_arc(aim_world_dir, to_vec)
	var target_world_rot := (world_delta * dst_parent_world_rot * dst_rest_local).normalized()
	var target_local_rot := (dst_parent_world_rot.inverse() * target_world_rot).normalized()
	var out_rot := dst_rest_local.slerp(target_local_rot, e.weight).normalized()
	_set_cur_local_rot(e.dst_ref, out_rot)


static func _shortest_arc(from_v: Vector3, to_v: Vector3) -> Quaternion:
	var d := clampf(from_v.dot(to_v), -1.0, 1.0)
	if d > 0.999999:
		return Quaternion.IDENTITY
	if d < -0.999999:
		var ortho := from_v.cross(Vector3.UP)
		if ortho.length_squared() < 1e-6:
			ortho = from_v.cross(Vector3.RIGHT)
		return Quaternion(ortho.normalized(), PI)
	var axis := from_v.cross(to_v).normalized()
	return Quaternion(axis, acos(d))


static func _get_rest_local_rot(ref: Dictionary) -> Quaternion:
	if ref["type"] == "bone":
		var skel: Skeleton3D = ref["skeleton"]
		return skel.get_bone_rest(ref["bone_idx"]).basis.orthonormalized().get_rotation_quaternion()
	var xf: Transform3D = ref["rest_local"]
	return xf.basis.orthonormalized().get_rotation_quaternion()


static func _get_cur_local_rot(ref: Dictionary) -> Quaternion:
	if ref["type"] == "bone":
		var skel: Skeleton3D = ref["skeleton"]
		return skel.get_bone_pose_rotation(ref["bone_idx"]).normalized()
	var n: Node3D = ref["node"]
	return n.transform.basis.orthonormalized().get_rotation_quaternion()


static func _set_cur_local_rot(ref: Dictionary, q: Quaternion) -> void:
	if ref["type"] == "bone":
		var skel: Skeleton3D = ref["skeleton"]
		skel.set_bone_pose_rotation(ref["bone_idx"], q.normalized())
	else:
		var n: Node3D = ref["node"]
		var sc := n.transform.basis.get_scale()
		n.transform = Transform3D(Basis(q.normalized()).scaled(sc), n.transform.origin)


static func _safe_global_rot(n: Node3D) -> Quaternion:
	if not is_instance_valid(n):
		return Quaternion.IDENTITY
	if n.is_inside_tree():
		return n.global_transform.basis.orthonormalized().get_rotation_quaternion()
	var b := Basis.IDENTITY
	var cur: Node = n
	while cur is Node3D:
		b = (cur as Node3D).transform.basis.orthonormalized() * b
		cur = cur.get_parent()
	return b.get_rotation_quaternion()


static func _get_parent_rest_world_rot(ref: Dictionary) -> Quaternion:
	if ref["type"] == "bone":
		var skel: Skeleton3D = ref["skeleton"]
		var b_idx: int = ref["bone_idx"]
		var p_idx: int = skel.get_bone_parent(b_idx)
		var skel_rot := _safe_global_rot(skel)
		if p_idx >= 0:
			return (skel_rot * skel.get_bone_global_rest(p_idx).basis.orthonormalized().get_rotation_quaternion()).normalized()
		return skel_rot
	var n: Node3D = ref["node"]
	var p := n.get_parent()
	if p is Node3D:
		return _safe_global_rot(p as Node3D)
	return Quaternion.IDENTITY


static func _get_rest_world_rot(ref: Dictionary) -> Quaternion:
	if ref["type"] == "bone":
		var skel: Skeleton3D = ref["skeleton"]
		var skel_rot := _safe_global_rot(skel)
		return (skel_rot * skel.get_bone_global_rest(ref["bone_idx"]).basis.orthonormalized().get_rotation_quaternion()).normalized()
	return (_get_parent_rest_world_rot(ref) * _get_rest_local_rot(ref)).normalized()


static func _get_parent_cur_world_rot(ref: Dictionary) -> Quaternion:
	if ref["type"] == "bone":
		var skel: Skeleton3D = ref["skeleton"]
		var p_idx: int = skel.get_bone_parent(ref["bone_idx"])
		var skel_rot := _safe_global_rot(skel)
		if p_idx >= 0:
			return (skel_rot * skel.get_bone_global_pose(p_idx).basis.orthonormalized().get_rotation_quaternion()).normalized()
		return skel_rot
	var n: Node3D = ref["node"]
	var p := n.get_parent()
	if p is Node3D:
		return _safe_global_rot(p as Node3D)
	return Quaternion.IDENTITY


static func _get_world_pos(ref: Dictionary) -> Vector3:
	if ref["type"] == "bone":
		var skel: Skeleton3D = ref["skeleton"]
		var xf := skel.global_transform if skel.is_inside_tree() else Transform3D.IDENTITY
		return (xf * skel.get_bone_global_pose(ref["bone_idx"])).origin
	var n: Node3D = ref["node"]
	return n.global_position if n.is_inside_tree() else n.position


static func _parse_roll_axis(s: String) -> Vector3:
	match s:
		"Y":
			return Vector3.UP
		"Z":
			return Vector3.BACK
		_:
			return Vector3.RIGHT


static func _parse_aim_axis(s: String) -> Vector3:
	match s:
		"PositiveX":
			return Vector3.RIGHT
		"NegativeX":
			return Vector3.LEFT
		"PositiveY":
			return Vector3.UP
		"NegativeY":
			return Vector3.DOWN
		"PositiveZ":
			return Vector3.BACK
		"NegativeZ":
			return Vector3.FORWARD
		_:
			return Vector3.RIGHT
