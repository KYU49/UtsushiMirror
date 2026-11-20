class_name VrmHumanoid
extends RefCounted

## Official VRM 1.0 Humanoid subsystem (all 55 official humanBones)
## Handles normalized pose math, rest-pose caching, and bone accessors.

const ALL_HUMAN_BONES: Array[String] = [
	# Torso
	"hips", "spine", "chest", "upperChest", "neck", "head",
	# Face
	"leftEye", "rightEye", "jaw",
	# Left Arm
	"leftShoulder", "leftUpperArm", "leftLowerArm", "leftHand",
	# Right Arm
	"rightShoulder", "rightUpperArm", "rightLowerArm", "rightHand",
	# Left Leg
	"leftUpperLeg", "leftLowerLeg", "leftFoot", "leftToes",
	# Right Leg
	"rightUpperLeg", "rightLowerLeg", "rightFoot", "rightToes",
	# Left Fingers
	"leftThumbMetacarpal", "leftThumbProximal", "leftThumbDistal",
	"leftIndexProximal", "leftIndexIntermediate", "leftIndexDistal",
	"leftMiddleProximal", "leftMiddleIntermediate", "leftMiddleDistal",
	"leftRingProximal", "leftRingIntermediate", "leftRingDistal",
	"leftLittleProximal", "leftLittleIntermediate", "leftLittleDistal",
	# Right Fingers
	"rightThumbMetacarpal", "rightThumbProximal", "rightThumbDistal",
	"rightIndexProximal", "rightIndexIntermediate", "rightIndexDistal",
	"rightMiddleProximal", "rightMiddleIntermediate", "rightMiddleDistal",
	"rightRingProximal", "rightRingIntermediate", "rightRingDistal",
	"rightLittleProximal", "rightLittleIntermediate", "rightLittleDistal",
]

var model_root: Node3D
var skeleton: Skeleton3D
var _bones: Dictionary = {} # human_bone_name -> BoneEntry
var hips_rest_height: float = 0.9


class BoneEntry:
	var human_name: String
	var gltf_node_idx: int
	var bone_idx: int
	var rest_local_pos: Vector3
	var rest_local_rot: Quaternion
	var rest_local_scale: Vector3
	var parent_rest_model_rot: Quaternion
	var rest_model_rot: Quaternion


func setup(root: Node3D, gltf_json: Dictionary, node_map: Dictionary) -> void:
	model_root = root
	_bones.clear()
	skeleton = _find_primary_skeleton(root)
	if skeleton == null:
		return

	var vrm_ext: Dictionary = gltf_json.get("extensions", {}).get("VRMC_vrm", {})
	var human_bones: Dictionary = vrm_ext.get("humanoid", {}).get("humanBones", {})
	var skel_to_model: Transform3D = _transform_relative_to_root(skeleton, model_root)
	var skel_basis_rot: Quaternion = skel_to_model.basis.orthonormalized().get_rotation_quaternion()

	for human_name in human_bones.keys():
		var info: Dictionary = human_bones[human_name]
		var gltf_idx: int = int(info.get("node", -1))
		if not node_map.has(gltf_idx):
			continue
		var target: Dictionary = node_map[gltf_idx]
		if target.get("type", "") != "bone":
			continue
		var skel: Skeleton3D = target["skeleton"]
		if skel != skeleton:
			continue
		var b_idx: int = int(target["bone_idx"])
		var rest_xform: Transform3D = skeleton.get_bone_rest(b_idx)
		var global_rest: Transform3D = skeleton.get_bone_global_rest(b_idx)
		var p_idx: int = skeleton.get_bone_parent(b_idx)
		var parent_model_rot := skel_basis_rot
		if p_idx >= 0:
			var p_global_rest: Transform3D = skeleton.get_bone_global_rest(p_idx)
			parent_model_rot = skel_basis_rot * p_global_rest.basis.orthonormalized().get_rotation_quaternion()

		var entry := BoneEntry.new()
		entry.human_name = str(human_name)
		entry.gltf_node_idx = gltf_idx
		entry.bone_idx = b_idx
		entry.rest_local_pos = rest_xform.origin
		entry.rest_local_rot = rest_xform.basis.orthonormalized().get_rotation_quaternion()
		entry.rest_local_scale = rest_xform.basis.get_scale()
		entry.parent_rest_model_rot = parent_model_rot.normalized()
		entry.rest_model_rot = (skel_basis_rot * global_rest.basis.orthonormalized().get_rotation_quaternion()).normalized()
		_bones[entry.human_name] = entry

		if entry.human_name == "hips":
			var hips_pos_model := skel_to_model * global_rest.origin
			if absf(hips_pos_model.y) > 0.01:
				hips_rest_height = absf(hips_pos_model.y)


func has_bone(human_name: String) -> bool:
	return _bones.has(human_name)


func get_bone_names() -> Array[String]:
	var out: Array[String] = []
	for k in _bones.keys():
		out.append(str(k))
	out.sort()
	return out


func get_bone_idx(human_name: String) -> int:
	if _bones.has(human_name):
		return _bones[human_name].bone_idx
	return -1


func get_bone_rest_model_rot(human_name: String) -> Quaternion:
	if _bones.has(human_name):
		return _bones[human_name].rest_model_rot
	return Quaternion.IDENTITY


func get_bone_world_transform(human_name: String) -> Transform3D:
	if skeleton == null or not _bones.has(human_name):
		return Transform3D.IDENTITY
	var b_idx: int = _bones[human_name].bone_idx
	return skeleton.global_transform * skeleton.get_bone_global_pose(b_idx)


func get_bone_pose_global(human_name: String) -> Transform3D:
	if skeleton == null or not _bones.has(human_name):
		return Transform3D.IDENTITY
	return skeleton.get_bone_global_pose(_bones[human_name].bone_idx)


func reset_to_rest_pose() -> void:
	if skeleton == null:
		return
	skeleton.reset_bone_poses()


## Applies a normalized rotation in VRM canonical character space (+X left, +Y up, +Z forward).
## Formula: Q_dst = Q_dst_rest_world(parent)^-1 * R_norm * Q_dst_rest_world(parent) * Q_dst_rest_local
func set_normalized_bone_rotation(human_name: String, norm_rot: Quaternion) -> void:
	if skeleton == null or not _bones.has(human_name):
		return
	var entry: BoneEntry = _bones[human_name]
	var q_inv := entry.parent_rest_model_rot.inverse()
	var q_local := (q_inv * norm_rot.normalized() * entry.parent_rest_model_rot * entry.rest_local_rot).normalized()
	skeleton.set_bone_pose_rotation(entry.bone_idx, q_local)


## Multiplies an additional normalized delta rotation on top of an already-posed normalized rotation,
## or from rest pose if base_norm is omitted.
func apply_additive_normalized_rotation(human_name: String, base_norm: Quaternion, delta_norm: Quaternion) -> void:
	set_normalized_bone_rotation(human_name, (base_norm * delta_norm).normalized())


## Applies a normalized delta translation (meters in model space) to hips.
func set_hips_translation_delta(delta_model_pos: Vector3) -> void:
	if skeleton == null or not _bones.has("hips"):
		return
	var entry: BoneEntry = _bones["hips"]
	var local_delta := entry.parent_rest_model_rot.inverse() * delta_model_pos
	skeleton.set_bone_pose_position(entry.bone_idx, entry.rest_local_pos + local_delta)


static func _find_primary_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_primary_skeleton(child)
		if found != null:
			return found
	return null


static func _transform_relative_to_root(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
