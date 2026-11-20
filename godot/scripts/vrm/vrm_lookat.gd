class_name VrmLookAt
extends RefCounted

## Official VRM 1.0 LookAt subsystem.
## Supports both "bone" (leftEye/rightEye rotations) and "expression" (lookUp/Down/Left/Right)
## with exact RangeMap curves and head-bone offset.

var offset_from_head: Vector3 = Vector3(0.0, 0.06, 0.0)
var lookat_type: String = "bone" # "bone" | "expression"
var range_h_inner := {"in_max": 90.0, "out_scale": 10.0}
var range_h_outer := {"in_max": 90.0, "out_scale": 10.0}
var range_v_down := {"in_max": 90.0, "out_scale": 10.0}
var range_v_up := {"in_max": 90.0, "out_scale": 10.0}

var mode: String = "camera" # "camera" | "manual" | "off"
var manual_target: Vector3 = Vector3(0.0, 1.4, 2.0)
var saccade_offset: Vector3 = Vector3.ZERO
var _last_yaw_deg: float = 0.0
var _last_pitch_deg: float = 0.0


func setup(gltf_json: Dictionary) -> void:
	var vrm_ext: Dictionary = gltf_json.get("extensions", {}).get("VRMC_vrm", {})
	var la: Dictionary = vrm_ext.get("lookAt", {})
	var off = la.get("offsetFromHeadBone", [0.0, 0.06, 0.0])
	if typeof(off) == TYPE_ARRAY and off.size() >= 3:
		offset_from_head = Vector3(float(off[0]), float(off[1]), float(off[2]))
	else:
		offset_from_head = Vector3(0.0, 0.06, 0.0)
	lookat_type = str(la.get("type", "bone"))
	range_h_inner = _parse_range(la.get("rangeMapHorizontalInner", {}), 90.0, 10.0 if lookat_type == "bone" else 1.0)
	range_h_outer = _parse_range(la.get("rangeMapHorizontalOuter", {}), 90.0, 10.0 if lookat_type == "bone" else 1.0)
	range_v_down = _parse_range(la.get("rangeMapVerticalDown", {}), 90.0, 10.0 if lookat_type == "bone" else 1.0)
	range_v_up = _parse_range(la.get("rangeMapVerticalUp", {}), 90.0, 10.0 if lookat_type == "bone" else 1.0)


func _parse_range(raw: Dictionary, def_in: float, def_out: float) -> Dictionary:
	return {
		"in_max": maxf(float(raw.get("inputMaxValue", def_in)), 0.001),
		"out_scale": float(raw.get("outputScale", def_out)),
	}


## Computes yaw/pitch from head bone toward world target and returns expression weights
## (if type == "expression") and applies bone eye rotations (if type == "bone").
func compute_and_apply(humanoid, world_target: Vector3, has_target: bool, lookat_override_mul: float = 1.0) -> Dictionary:
	var expr_out: Dictionary = {}
	if mode == "off" or not has_target or humanoid == null or not humanoid.has_bone("head"):
		_last_yaw_deg = 0.0
		_last_pitch_deg = 0.0
		return expr_out

	var head_world: Transform3D = humanoid.get_bone_world_transform("head")
	var look_origin_world: Vector3 = head_world * offset_from_head
	var target_with_saccade: Vector3 = world_target + saccade_offset
	var dir_world: Vector3 = target_with_saccade - look_origin_world
	if dir_world.length_squared() < 1e-6:
		return expr_out

	# Convert direction into head canonical local space (+Z forward, +Y up, +X left)
	var head_pose_model: Transform3D = humanoid.get_bone_pose_global("head")
	var model_to_head_rot: Quaternion = (humanoid.model_root.global_transform.basis.orthonormalized().get_rotation_quaternion()
		* head_pose_model.basis.orthonormalized().get_rotation_quaternion()
		* humanoid.get_bone_rest_model_rot("head").inverse())
	var dir_head: Vector3 = (model_to_head_rot.inverse() * dir_world).normalized()

	var yaw_deg: float = rad_to_deg(atan2(dir_head.x, dir_head.z))
	var horiz_len: float = sqrt(dir_head.x * dir_head.x + dir_head.z * dir_head.z)
	var pitch_deg: float = rad_to_deg(atan2(dir_head.y, maxf(horiz_len, 1e-5)))

	# If target is behind head (>95 deg), gently attenuate toward forward
	if absf(yaw_deg) > 95.0:
		var fade := clampf(1.0 - (absf(yaw_deg) - 95.0) / 45.0, 0.0, 1.0)
		yaw_deg *= fade
		pitch_deg *= fade

	_last_yaw_deg = yaw_deg
	_last_pitch_deg = pitch_deg

	if lookat_type == "bone":
		var yaw_l := _map_range(yaw_deg, range_h_inner, range_h_outer) * lookat_override_mul
		var yaw_r := -_map_range(-yaw_deg, range_h_inner, range_h_outer) * lookat_override_mul
		var pitch_val := _map_range(pitch_deg, range_v_up, range_v_down) * lookat_override_mul
		# Apply eye bone rotations around canonical X (pitch) & Y (yaw)
		var q_left := Quaternion.from_euler(Vector3(deg_to_rad(-pitch_val), deg_to_rad(yaw_l), 0.0))
		var q_right := Quaternion.from_euler(Vector3(deg_to_rad(-pitch_val), deg_to_rad(yaw_r), 0.0))
		humanoid.set_normalized_bone_rotation("leftEye", q_left)
		humanoid.set_normalized_bone_rotation("rightEye", q_right)
	else:
		# Expression type
		if yaw_deg >= 0.0:
			expr_out["lookLeft"] = _map_range(yaw_deg, range_h_inner, range_h_outer)
			expr_out["lookRight"] = 0.0
		else:
			expr_out["lookLeft"] = 0.0
			expr_out["lookRight"] = _map_range(-yaw_deg, range_h_outer, range_h_inner)
		if pitch_deg >= 0.0:
			expr_out["lookUp"] = _map_range(pitch_deg, range_v_up, range_v_up)
			expr_out["lookDown"] = 0.0
		else:
			expr_out["lookUp"] = 0.0
			expr_out["lookDown"] = _map_range(-pitch_deg, range_v_down, range_v_down)

	return expr_out


## トラッカー (VMC) が目の向きを送っているときに使う。カメラ目線などの自動の視線より優先する。
## 目のボーンのモデルは受け取った回転がそのまま適用済みなので何もしない。
## 表情で目を動かすモデルは、目の向きを lookLeft / lookRight / lookUp / lookDown に変換する。
func apply_tracked_eyes(q_left: Quaternion, q_right: Quaternion) -> Dictionary:
	var out: Dictionary = {}
	var d: Vector3 = (q_left * Vector3.BACK) + (q_right * Vector3.BACK)
	if d.length_squared() < 1e-8:
		return out
	d = d.normalized()
	var yaw := rad_to_deg(atan2(d.x, d.z))
	var pitch := rad_to_deg(asin(clampf(d.y, -1.0, 1.0)))
	_last_yaw_deg = yaw
	_last_pitch_deg = pitch
	if lookat_type == "bone":
		return out
	var h := float(range_h_outer["in_max"])
	out["lookLeft"] = clampf(yaw / h, 0.0, 1.0) * float(range_h_outer["out_scale"])
	out["lookRight"] = clampf(-yaw / h, 0.0, 1.0) * float(range_h_outer["out_scale"])
	out["lookUp"] = clampf(pitch / float(range_v_up["in_max"]), 0.0, 1.0) * float(range_v_up["out_scale"])
	out["lookDown"] = clampf(-pitch / float(range_v_down["in_max"]), 0.0, 1.0) * float(range_v_down["out_scale"])
	return out


static func _map_range(angle_deg: float, pos_map: Dictionary, neg_map: Dictionary) -> float:
	if angle_deg >= 0.0:
		var t := clampf(angle_deg / float(pos_map["in_max"]), 0.0, 1.0)
		return t * float(pos_map["out_scale"])
	else:
		var t := clampf((-angle_deg) / float(neg_map["in_max"]), 0.0, 1.0)
		return -t * float(neg_map["out_scale"])
