class_name VrmFirstPerson
extends RefCounted

## Official VRM 1.0 Meta & FirstPerson meshAnnotations subsystem.
## Controls mesh visibility layers for thirdPersonOnly / firstPersonOnly / both / auto.

var meta: Dictionary = {}
var annotations: Array = [] # [{ "mesh_instance": MeshInstance3D, "type": String, "gltf_node": int }]
var first_person_enabled: bool = false
var _head_descendant_bone_indices: Dictionary = {} # bone_idx -> true


func setup(gltf_json: Dictionary, node_to_mesh_instances: Dictionary, humanoid = null) -> void:
	var vrm_ext: Dictionary = gltf_json.get("extensions", {}).get("VRMC_vrm", {})
	meta = vrm_ext.get("meta", {}).duplicate(true)
	annotations.clear()
	_head_descendant_bone_indices.clear()

	# Collect head and its descendant bones for "auto" firstPerson mesh filtering
	if humanoid != null and humanoid.skeleton != null:
		var head_idx: int = humanoid.get_bone_idx("head")
		if head_idx >= 0:
			_collect_bone_descendants(humanoid.skeleton, head_idx, _head_descendant_bone_indices)

	var fp: Dictionary = vrm_ext.get("firstPerson", {})
	var raw_annots: Array = fp.get("meshAnnotations", [])
	var seen_meshes: Dictionary = {}

	for item in raw_annots:
		var gltf_node: int = int(item.get("node", -1))
		var fp_type: String = str(item.get("type", "auto"))
		var mis: Array = node_to_mesh_instances.get(gltf_node, [])
		for mi in mis:
			if mi is MeshInstance3D:
				annotations.append({
					"mesh_instance": mi,
					"type": fp_type,
					"gltf_node": gltf_node,
				})
				seen_meshes[mi.get_instance_id()] = true

	# Any mesh not explicitly annotated defaults to "auto" per VRM 1.0 spec
	for gltf_node in node_to_mesh_instances.keys():
		for mi in node_to_mesh_instances[gltf_node]:
			if mi is MeshInstance3D and not seen_meshes.has(mi.get_instance_id()):
				annotations.append({
					"mesh_instance": mi,
					"type": "auto",
					"gltf_node": gltf_node,
				})
				seen_meshes[mi.get_instance_id()] = true

	set_first_person_mode(false)


func set_first_person_mode(enabled: bool) -> void:
	first_person_enabled = enabled
	for entry in annotations:
		var mi: MeshInstance3D = entry["mesh_instance"]
		if not is_instance_valid(mi):
			continue
		var fp_type: String = entry["type"]
		if not enabled:
			# Third person camera
			mi.visible = (fp_type != "firstPersonOnly")
		else:
			# First person camera
			if fp_type == "firstPersonOnly" or fp_type == "both":
				mi.visible = true
			elif fp_type == "thirdPersonOnly":
				mi.visible = false
			else:
				# "auto": hide if skinned heavily to head descendants, else visible
				mi.visible = not _is_head_mesh(mi)


func _is_head_mesh(mi: MeshInstance3D) -> bool:
	if _head_descendant_bone_indices.is_empty():
		return false
	var lname := mi.name.to_lower()
	if lname.contains("head") or lname.contains("face") or lname.contains("hair"):
		return true
	return false


static func _collect_bone_descendants(skel: Skeleton3D, bone_idx: int, out: Dictionary) -> void:
	out[bone_idx] = true
	for child_idx in skel.get_bone_children(bone_idx):
		_collect_bone_descendants(skel, child_idx, out)
