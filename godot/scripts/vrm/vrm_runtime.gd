class_name VrmRuntime
extends Node3D

## Runtime controller attached to a loaded VRM model root.
## Executes all VRM 1.0 subsystems in official specification order:
## 1. Reset pose -> Animation (.vrma) -> Procedural Idle -> Direct Bone / VMC overrides
## 2. NodeConstraints
## 3. LookAt
## 4. Expressions (+ overrides for Blink/LookAt/Mouth)
## 5. SpringBone 1.0 (+ deterministic MToon UV time)

const VrmHumanoidScript := preload("res://scripts/vrm/vrm_humanoid.gd")
const VrmFirstPersonScript := preload("res://scripts/vrm/vrm_firstperson.gd")
const VrmExpressionsScript := preload("res://scripts/vrm/vrm_expressions.gd")
const VrmLookAtScript := preload("res://scripts/vrm/vrm_lookat.gd")
const VrmConstraintsScript := preload("res://scripts/vrm/vrm_constraints.gd")
const VrmSpringBoneScript := preload("res://scripts/vrm/vrm_springbone.gd")

var model_path: String = ""
var vrm_version: String = "1.0"
var humanoid
var first_person
var expressions
var lookat
var constraints
var spring_bone
var materials: Array = []

# External / Layered pose & animation hooks
var animation_player = null # VrmaPlayer set in Milestone 3
var procedural_idle = null # ProceduralIdle set in Milestone 3
var direct_bone_overrides: Dictionary = {} # human_bone -> Quaternion
var direct_hips_offset: Vector3 = Vector3.ZERO
var has_direct_hips_offset: bool = false
var vmc_bone_overrides: Dictionary = {} # human_bone -> Quaternion
var vmc_hips_offset: Vector3 = Vector3.ZERO
var has_vmc_hips_offset: bool = false

var lookat_world_target: Vector3 = Vector3(0.0, 1.4, 2.0)
## トラッキング中に「カメラ目線」を選んだとき: 目の向きはトラッキングを使わず、LookAt の設定に関係なくカメラを見る
var force_camera_gaze: bool = false
var has_lookat_target: bool = true
var deterministic_time: float = 0.0
var manual_step_only: bool = false


func initialize_subsystems(
	p_path: String,
	p_version: String,
	p_humanoid,
	p_fp,
	p_expr,
	p_lookat,
	p_constraints,
	p_spring,
	p_materials: Array
) -> void:
	model_path = p_path
	vrm_version = p_version
	humanoid = p_humanoid
	first_person = p_fp
	expressions = p_expr
	lookat = p_lookat
	constraints = p_constraints
	spring_bone = p_spring
	materials = p_materials


func _process(delta: float) -> void:
	if manual_step_only:
		return
	step(delta)


## Deterministic single frame update following official VRM 1.0 execution order.
func step(dt: float) -> void:
	if humanoid == null:
		return
	deterministic_time += dt

	# Update MToon UV animation uniform deterministically
	for mat in materials:
		if mat is ShaderMaterial:
			mat.set_shader_parameter("u_time", deterministic_time)

	# 1. Reset pose and compose Animation -> Procedural Idle -> Direct Bone / VMC overrides
	humanoid.reset_to_rest_pose()

	var composed_bones: Dictionary = {} # human_bone -> Quaternion
	var hips_delta: Vector3 = Vector3.ZERO
	var anim_exprs: Dictionary = {}
	var anim_has_lookat := false
	var anim_lookat_target := Vector3.ZERO

	if animation_player != null and animation_player.has_method("sample_pose"):
		var anim_res: Dictionary = animation_player.sample_pose(dt, humanoid)
		var abones: Dictionary = anim_res.get("bones", {})
		for bname in abones.keys():
			composed_bones[bname] = abones[bname]
		hips_delta += anim_res.get("hips_delta", Vector3.ZERO)
		anim_exprs = anim_res.get("expressions", {})
		if anim_res.get("has_lookat", false):
			anim_has_lookat = true
			anim_lookat_target = anim_res.get("lookat_target", Vector3.ZERO)

	var idle_blink_weight := 0.0
	var idle_saccade := Vector3.ZERO
	if procedural_idle != null and procedural_idle.has_method("sample_idle"):
		var idle_res: Dictionary = procedural_idle.sample_idle(dt)
		var ibones: Dictionary = idle_res.get("bones", {})
		for bname in ibones.keys():
			var base_q: Quaternion = composed_bones.get(bname, Quaternion.IDENTITY)
			composed_bones[bname] = (base_q * ibones[bname]).normalized()
		hips_delta += idle_res.get("hips_delta", Vector3.ZERO)
		idle_blink_weight = float(idle_res.get("blink_weight", 0.0))
		idle_saccade = idle_res.get("saccade_offset", Vector3.ZERO)

	for bname in vmc_bone_overrides.keys():
		composed_bones[bname] = vmc_bone_overrides[bname]
	if has_vmc_hips_offset:
		hips_delta = vmc_hips_offset

	for bname in direct_bone_overrides.keys():
		composed_bones[bname] = direct_bone_overrides[bname]
	if has_direct_hips_offset:
		hips_delta = direct_hips_offset

	for bname in composed_bones.keys():
		humanoid.set_normalized_bone_rotation(str(bname), composed_bones[bname])
	if hips_delta.length_squared() > 1e-10:
		humanoid.set_hips_translation_delta(hips_delta)

	# 2. NodeConstraints
	if constraints != null:
		constraints.update()

	# 3. LookAt
	var lookat_exprs: Dictionary = {}
	var tracked_eyes := vmc_bone_overrides.has("leftEye") or vmc_bone_overrides.has("rightEye")
	if lookat != null and tracked_eyes:
		# Webカメラ等のトラッキングが目の向きを送っているときは、それを優先する
		lookat_exprs = lookat.apply_tracked_eyes(
			vmc_bone_overrides.get("leftEye", vmc_bone_overrides.get("rightEye", Quaternion.IDENTITY)),
			vmc_bone_overrides.get("rightEye", vmc_bone_overrides.get("leftEye", Quaternion.IDENTITY)))
	elif lookat != null and force_camera_gaze:
		lookat.saccade_offset = idle_saccade
		var saved_mode: String = lookat.mode
		lookat.mode = "camera"
		lookat_exprs = lookat.compute_and_apply(humanoid, lookat_world_target, true, 1.0)
		lookat.mode = saved_mode
	elif lookat != null:
		lookat.saccade_offset = idle_saccade
		var tgt := lookat_world_target
		var active := has_lookat_target
		if lookat.mode == "manual":
			tgt = lookat.manual_target
			active = true
		elif anim_has_lookat and lookat.mode != "off":
			tgt = anim_lookat_target
			active = true
		lookat_exprs = lookat.compute_and_apply(humanoid, tgt, active, 1.0)

	# Merge any VRMA expression channels without clobbering manual expressions
	for ename in anim_exprs.keys():
		if not lookat_exprs.has(ename):
			lookat_exprs[ename] = anim_exprs[ename]

	# 4. Expressions (morphs, materialColorBinds, textureTransformBinds, overrides)
	if expressions != null:
		var expr_res: Dictionary = expressions.update(dt, lookat_exprs, idle_blink_weight)
		# Re-apply bone LookAt attenuated if overrideLookAt blocked/blended eye bones
		var lookat_mul: float = float(expr_res.get("lookat_mul", 1.0))
		if lookat != null and lookat.lookat_type == "bone" and lookat_mul < 0.999 and not tracked_eyes:
			var tgt2: Vector3 = lookat.manual_target if lookat.mode == "manual" else lookat_world_target
			lookat.compute_and_apply(humanoid, tgt2, has_lookat_target or lookat.mode == "manual", lookat_mul)

	# 5. SpringBone
	if spring_bone != null:
		spring_bone.update(dt)


func get_model_info() -> Dictionary:
	return {
		"path": model_path,
		"vrm_version": vrm_version,
		"meta": first_person.meta if first_person else {},
		"human_bones": humanoid.get_bone_names() if humanoid else [],
		"expressions": expressions.get_expression_names() if expressions else [],
		"lookat": {
			"type": lookat.lookat_type if lookat else "bone",
			"mode": lookat.mode if lookat else "off",
		},
		"first_person": first_person.first_person_enabled if first_person else false,
		"constraints": constraints.get_summary() if constraints else [],
		"spring_bone": spring_bone.get_stats() if spring_bone else {},
	}


func get_approx_bounds() -> AABB:
	var aabb := AABB(Vector3(-0.35, 0.0, -0.35), Vector3(0.7, 1.65, 0.7))
	var first := true
	for mi in _collect_mesh_instances(self):
		if mi.mesh == null or not mi.visible:
			continue
		var m_aabb := mi.global_transform * mi.get_aabb()
		if first:
			aabb = m_aabb
			first = false
		else:
			aabb = aabb.merge(m_aabb)
	return aabb


static func _collect_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_collect_mesh_instances(c))
	return out
