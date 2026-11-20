class_name VrmLoader
extends RefCounted

## Runtime VRM 1.0 (and VRM 0.x via Vrm0Migrator) loader.
## Parses raw GLB chunks + Godot GLTFDocument/GLTFState scene generation,
## maps glTF node/mesh/material indices to runtime Godot objects,
## and returns an initialized VrmRuntime node ready to add to the scene.

const GlbReaderScript := preload("res://scripts/vrm/glb_reader.gd")
const VrmMtoonScript := preload("res://scripts/vrm/vrm_mtoon.gd")
const VrmHumanoidScript := preload("res://scripts/vrm/vrm_humanoid.gd")
const VrmFirstPersonScript := preload("res://scripts/vrm/vrm_firstperson.gd")
const VrmExpressionsScript := preload("res://scripts/vrm/vrm_expressions.gd")
const VrmLookAtScript := preload("res://scripts/vrm/vrm_lookat.gd")
const VrmConstraintsScript := preload("res://scripts/vrm/vrm_constraints.gd")
const VrmSpringBoneScript := preload("res://scripts/vrm/vrm_springbone.gd")
const VrmRuntimeScript := preload("res://scripts/vrm/vrm_runtime.gd")
const Vrm0MigratorScript := preload("res://scripts/vrm/vrm0_migrator.gd")


static func load_vrm(path: String, bridge: Node = null) -> Dictionary:
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	if not FileAccess.file_exists(abs_path):
		return {"ok": false, "error": "File not found: " + abs_path}

	var glb: Dictionary = GlbReaderScript.read_glb(abs_path, bridge)
	if not glb.get("ok", false):
		return glb

	var gltf_json: Dictionary = glb["json"]
	var vrm_ver := GlbReaderScript.detect_vrm_version(gltf_json)
	if vrm_ver == "0.x":
		# Migrator hook (implemented fully in Milestone 8)
		gltf_json = Vrm0MigratorScript.migrate_vrm0_to_vrm1(gltf_json)
	elif vrm_ver != "1.0":
		return {"ok": false, "error": "File is not a valid VRM model (missing VRMC_vrm/VRM extension)"}

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(abs_path, state)
	if err != OK:
		return {"ok": false, "error": "GLTFDocument.append_from_file failed: " + str(err)}

	var generated_root := doc.generate_scene(state)
	if generated_root == null:
		return {"ok": false, "error": "GLTFDocument.generate_scene returned null"}

	# Wrap in VrmRuntime Node3D
	var runtime = VrmRuntimeScript.new()
	runtime.name = generated_root.name if generated_root.name != "" else "VrmModel"
	runtime.add_child(generated_root)

	# Build glTF node -> Godot Bone / Node3D mapping
	var node_map := _build_node_map(state, gltf_json, generated_root)

	# Build glTF node -> MeshInstance3D mapping
	var mesh_instances := _collect_mesh_instances(generated_root)
	var node_to_mis := _build_node_mesh_map(state, gltf_json, mesh_instances)

	# Build MToon 1.0 ShaderMaterials and replace surfaces on MeshInstance3Ds
	var built_materials: Array = VrmMtoonScript.build_materials(gltf_json, state)
	_apply_materials_to_meshes(state, gltf_json, mesh_instances, built_materials)

	# Initialize all VRM 1.0 subsystems
	var humanoid = VrmHumanoidScript.new()
	humanoid.setup(generated_root, gltf_json, node_map)

	var first_person = VrmFirstPersonScript.new()
	first_person.setup(gltf_json, node_to_mis, humanoid)

	var expressions = VrmExpressionsScript.new()
	expressions.setup(gltf_json, node_to_mis, built_materials)

	var lookat = VrmLookAtScript.new()
	lookat.setup(gltf_json)

	var constraints = VrmConstraintsScript.new()
	constraints.setup(gltf_json, node_map)

	var spring_bone = VrmSpringBoneScript.new()
	spring_bone.setup(gltf_json, node_map)

	runtime.initialize_subsystems(
		abs_path,
		vrm_ver,
		humanoid,
		first_person,
		expressions,
		lookat,
		constraints,
		spring_bone,
		built_materials
	)

	# Handle VRM 0.x -Z facing normalization if migrated
	if vrm_ver == "0.x":
		generated_root.rotation_degrees.y = 180.0

	return {"ok": true, "runtime": runtime}


static func _build_node_map(state: GLTFState, gltf_json: Dictionary, _root: Node3D) -> Dictionary:
	var out: Dictionary = {}
	var gnodes := state.get_nodes()
	var jnodes: Array = gltf_json.get("nodes", [])
	var skels := state.get_skeletons()

	# 1. Map all skinned joints inside Skeleton3Ds
	for gs: GLTFSkeleton in skels:
		var skel: Skeleton3D = gs.get_godot_skeleton()
		if skel == null:
			continue
		for gn_idx in gs.get_joints():
			if gn_idx < 0 or gn_idx >= gnodes.size():
				continue
			var gn: GLTFNode = gnodes[gn_idx]
			var b_idx := skel.find_bone(gn.resource_name)
			if b_idx < 0 and gn_idx < jnodes.size():
				var jname := str(jnodes[gn_idx].get("name", ""))
				if jname != "":
					b_idx = skel.find_bone(jname)
			if b_idx >= 0:
				out[gn_idx] = {
					"type": "bone",
					"skeleton": skel,
					"bone_idx": b_idx,
				}

	# 2. Map non-joint scene nodes (skip Skeleton3D placeholders if already mapped as bone)
	for i in range(gnodes.size()):
		if out.has(i):
			continue
		var sn: Node = state.get_scene_node(i)
		if is_instance_valid(sn) and sn is Node3D and not (sn is Skeleton3D):
			out[i] = {
				"type": "node",
				"node": sn,
				"rest_local": (sn as Node3D).transform,
			}

	return out


static func _build_node_mesh_map(state: GLTFState, gltf_json: Dictionary, mesh_instances: Array[MeshInstance3D]) -> Dictionary:
	var out: Dictionary = {}
	var gnodes := state.get_nodes()
	var jnodes: Array = gltf_json.get("nodes", [])
	var gmeshes := state.get_meshes()
	var used_mi_ids: Dictionary = {}

	for i in range(jnodes.size()):
		var jn: Dictionary = jnodes[i]
		if not jn.has("mesh"):
			continue
		var mesh_idx: int = int(jn["mesh"])
		var matched: Array[MeshInstance3D] = []

		var sn: Node = state.get_scene_node(i)
		if is_instance_valid(sn) and sn is MeshInstance3D:
			matched.append(sn as MeshInstance3D)
			used_mi_ids[sn.get_instance_id()] = true
		else:
			var target_name := str(jn.get("name", ""))
			var gn_name := str(gnodes[i].resource_name) if i < gnodes.size() else ""
			var mesh_name := str(gmeshes[mesh_idx].resource_name) if mesh_idx >= 0 and mesh_idx < gmeshes.size() else ""
			for mi in mesh_instances:
				if used_mi_ids.has(mi.get_instance_id()):
					continue
				if mi.name == target_name or (gn_name != "" and mi.name == gn_name) or (mesh_name != "" and mi.name == mesh_name):
					matched.append(mi)
					used_mi_ids[mi.get_instance_id()] = true
					break
			# Secondary match by mesh resource name or surface count if still unmatched
			if matched.is_empty():
				var expected_prims: int = gltf_json.get("meshes", [])[mesh_idx].get("primitives", []).size()
				for mi in mesh_instances:
					if used_mi_ids.has(mi.get_instance_id()):
						continue
					if mi.mesh != null and mi.mesh.get_surface_count() == expected_prims:
						matched.append(mi)
						used_mi_ids[mi.get_instance_id()] = true
						break

		if not matched.is_empty():
			out[i] = matched

	return out


static func _apply_materials_to_meshes(
	state: GLTFState,
	_gltf_json: Dictionary,
	mesh_instances: Array[MeshInstance3D],
	built_materials: Array
) -> void:
	var state_mats := state.get_materials()
	for mi in mesh_instances:
		if mi.mesh == null:
			continue
		var surf_cnt := mi.mesh.get_surface_count()
		for s in range(surf_cnt):
			var orig: Material = mi.mesh.surface_get_material(s)
			var mat_idx := state_mats.find(orig)
			if mat_idx >= 0 and mat_idx < built_materials.size():
				var replacement: Material = built_materials[mat_idx]
				if replacement != null and replacement != orig:
					mi.set_surface_override_material(s, replacement)


static func _collect_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_collect_mesh_instances(c))
	return out
