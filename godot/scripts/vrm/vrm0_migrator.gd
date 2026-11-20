class_name Vrm0Migrator
extends RefCounted

## Runtime VRM 0.x -> VRM 1.0 JSON migration adapter.
## Converts extensions.VRM (meta, humanoid, blendShapeMaster, firstPerson,
## secondaryAnimation, materialProperties) into VRMC_vrm, VRMC_springBone,
## and VRMC_materials_mtoon so VRM 0.x models load through the VRM 1.0 pipeline.

const PRESET_MAP := {
	"neutral": "neutral",
	"joy": "happy",
	"angry": "angry",
	"sorrow": "sad",
	"fun": "relaxed",
	"a": "aa",
	"i": "ih",
	"u": "ou",
	"e": "ee",
	"o": "oh",
	"blink": "blink",
	"blink_l": "blinkLeft",
	"blink_r": "blinkRight",
	"lookup": "lookUp",
	"lookdown": "lookDown",
	"lookleft": "lookLeft",
	"lookright": "lookRight",
}

const FP_FLAG_MAP := {
	"Auto": "auto",
	"Both": "both",
	"ThirdPersonOnly": "thirdPersonOnly",
	"FirstPersonOnly": "firstPersonOnly",
}


static func migrate_vrm0_to_vrm1(gltf_json: Dictionary) -> Dictionary:
	var out: Dictionary = gltf_json.duplicate(true)
	var exts: Dictionary = out.get("extensions", {})
	if not exts.has("VRM"):
		return out
	var vrm0: Dictionary = exts["VRM"]

	# Build mesh_idx -> first gltf_node_idx lookup
	var mesh_to_node: Dictionary = {}
	var jnodes: Array = out.get("nodes", [])
	for ni in range(jnodes.size()):
		var jn: Dictionary = jnodes[ni]
		if jn.has("mesh"):
			var mi := int(jn["mesh"])
			if not mesh_to_node.has(mi):
				mesh_to_node[mi] = ni

	# Build material_name -> mat_idx lookup
	var mat_name_to_idx: Dictionary = {}
	var jmats: Array = out.get("materials", [])
	for mi in range(jmats.size()):
		var mname := str(jmats[mi].get("name", ""))
		if mname != "" and not mat_name_to_idx.has(mname):
			mat_name_to_idx[mname] = mi

	# 1. Meta
	var m0: Dictionary = vrm0.get("meta", {})
	var authors: Array = []
	if str(m0.get("author", "")) != "":
		authors.append(str(m0.get("author", "")))
	var meta1 := {
		"name": str(m0.get("title", "VRM0 Model")),
		"version": str(m0.get("version", "")),
		"authors": authors,
		"copyrightInformation": str(m0.get("contactInformation", "")),
		"licenseUrl": str(m0.get("otherLicenseUrl", "")),
		"avatarPermission": "everyone" if str(m0.get("allowedUserName", "")) == "Everyone" else "onlyAuthor",
		"commercialUsage": "personalProfit" if str(m0.get("commercialUssageName", "")) == "Allow" else "personalNonProfit",
	}

	# 2. Humanoid
	var hb1: Dictionary = {}
	for entry in vrm0.get("humanoid", {}).get("humanBones", []):
		var bname := str(entry.get("bone", ""))
		var gnode := int(entry.get("node", -1))
		if bname != "" and gnode >= 0:
			hb1[bname] = {"node": gnode}

	# 3. Expressions (blendShapeMaster -> expressions)
	var preset_exprs: Dictionary = {}
	var custom_exprs: Dictionary = {}
	for bg in vrm0.get("blendShapeMaster", {}).get("blendShapeGroups", []):
		var raw_preset := str(bg.get("presetName", "unknown")).to_lower()
		var raw_name := str(bg.get("name", raw_preset))
		var is_binary := bool(bg.get("isBinary", false))
		var morph_binds: Array = []
		for b in bg.get("binds", []):
			var midx := int(b.get("mesh", -1))
			if mesh_to_node.has(midx):
				morph_binds.append({
					"node": mesh_to_node[midx],
					"index": int(b.get("index", 0)),
					"weight": clampf(float(b.get("weight", 100.0)) / 100.0, 0.0, 1.0),
				})
		var color_binds: Array = []
		var tex_binds: Array = []
		for mv in bg.get("materialValues", []):
			var mname := str(mv.get("materialName", ""))
			if not mat_name_to_idx.has(mname):
				continue
			var mat_i: int = mat_name_to_idx[mname]
			var prop := str(mv.get("propertyName", ""))
			var tv: Array = mv.get("targetValue", [1.0, 1.0, 1.0, 1.0])
			if prop == "_MainTex_ST" and tv.size() >= 4:
				tex_binds.append({
					"material": mat_i,
					"scale": [float(tv[0]), float(tv[1])],
					"offset": [float(tv[2]), float(tv[3])],
				})
			elif tv.size() >= 4:
				var ctype := "color"
				if prop == "_ShadeColor":
					ctype = "shadeColor"
				elif prop == "_EmissionColor":
					ctype = "emissiveColor"
				elif prop == "_OutlineColor":
					ctype = "outlineColor"
				elif prop == "_RimColor":
					ctype = "rimColor"
				color_binds.append({
					"material": mat_i,
					"type": ctype,
					"targetValue": [float(tv[0]), float(tv[1]), float(tv[2]), float(tv[3])],
				})

		var expr_obj := {
			"isBinary": is_binary,
			"morphTargetBinds": morph_binds,
			"materialColorBinds": color_binds,
			"textureTransformBinds": tex_binds,
		}
		if PRESET_MAP.has(raw_preset):
			preset_exprs[PRESET_MAP[raw_preset]] = expr_obj
		else:
			custom_exprs[raw_name] = expr_obj

	# 4. FirstPerson & LookAt
	var fp0: Dictionary = vrm0.get("firstPerson", {})
	var annots1: Array = []
	for ma in fp0.get("meshAnnotations", []):
		var midx := int(ma.get("mesh", -1))
		if mesh_to_node.has(midx):
			annots1.append({
				"node": mesh_to_node[midx],
				"type": FP_FLAG_MAP.get(str(ma.get("firstPersonFlag", "Auto")), "auto"),
			})

	var la_type := "expression" if str(fp0.get("lookAtTypeName", "Bone")) == "BlendShape" else "bone"
	var off: Variant = fp0.get("firstPersonBoneOffset", {"x": 0.0, "y": 0.06, "z": 0.0})
	var off_arr: Array = [float(off.get("x", 0.0)), float(off.get("y", 0.06)), float(off.get("z", 0.0))] if typeof(off) == TYPE_DICTIONARY else [0.0, 0.06, 0.0]

	var lookat1 := {
		"offsetFromHeadBone": off_arr,
		"type": la_type,
		"rangeMapHorizontalInner": _map_vrm0_curve(fp0.get("lookAtHorizontalInner", {})),
		"rangeMapHorizontalOuter": _map_vrm0_curve(fp0.get("lookAtHorizontalOuter", {})),
		"rangeMapVerticalDown": _map_vrm0_curve(fp0.get("lookAtVerticalDown", {})),
		"rangeMapVerticalUp": _map_vrm0_curve(fp0.get("lookAtVerticalUp", {})),
	}

	exts["VRMC_vrm"] = {
		"specVersion": "1.0",
		"meta": meta1,
		"humanoid": {"humanBones": hb1},
		"firstPerson": {"meshAnnotations": annots1},
		"lookAt": lookat1,
		"expressions": {
			"preset": preset_exprs,
			"custom": custom_exprs,
		},
	}

	# 5. SecondaryAnimation -> VRMC_springBone
	var sa0: Dictionary = vrm0.get("secondaryAnimation", {})
	var cols1: Array = []
	var cgroups1: Array = []
	var cg_node_to_idx: Dictionary = {}
	for cg in sa0.get("colliderGroups", []):
		var cnode := int(cg.get("node", -1))
		var group_indices: Array = []
		for c in cg.get("colliders", []):
			var o: Dictionary = c.get("offset", {})
			var c_idx := cols1.size()
			cols1.append({
				"node": cnode,
				"shape": {
					"sphere": {
						"offset": [float(o.get("x", 0.0)), float(o.get("y", 0.0)), float(o.get("z", 0.0))],
						"radius": float(c.get("radius", 0.05)),
					}
				},
			})
			group_indices.append(c_idx)
		var g_idx := cgroups1.size()
		cgroups1.append({"colliders": group_indices})
		cg_node_to_idx[cnode] = g_idx

	var springs1: Array = []
	for bg in sa0.get("boneGroups", []):
		var stiff := float(bg.get("stiffiness", 1.0))
		var gpow := float(bg.get("gravityPower", 0.0))
		var gdir: Dictionary = bg.get("gravityDir", {"x": 0.0, "y": -1.0, "z": 0.0})
		var gdir_arr := [float(gdir.get("x", 0.0)), float(gdir.get("y", -1.0)), float(gdir.get("z", 0.0))]
		var drag := float(bg.get("dragForce", 0.4))
		var hit_r := float(bg.get("hitRadius", 0.02))
		var center_node := int(bg.get("center", -1))
		var cg_refs: Array = []
		for cg_n in bg.get("colliderGroups", []):
			var g_idx: int = int(cg_node_to_idx.get(int(cg_n), -1))
			if g_idx >= 0:
				cg_refs.append(g_idx)

		for root_bone in bg.get("bones", []):
			var chain_nodes: Array = []
			_collect_chain(int(root_bone), jnodes, chain_nodes)
			if chain_nodes.size() < 2:
				continue
			var joints: Array = []
			for bn in chain_nodes:
				joints.append({
					"node": bn,
					"hitRadius": hit_r,
					"stiffness": stiff,
					"gravityPower": gpow,
					"gravityDir": gdir_arr,
					"dragForce": drag,
				})
			var sp := {
				"name": str(bg.get("comment", "spring")),
				"joints": joints,
				"colliderGroups": cg_refs,
			}
			if center_node >= 0:
				sp["center"] = center_node
			springs1.append(sp)

	if not springs1.is_empty():
		exts["VRMC_springBone"] = {
			"specVersion": "1.0",
			"colliders": cols1,
			"colliderGroups": cgroups1,
			"springs": springs1,
		}

	# 6. materialProperties (VRM/MToon -> VRMC_materials_mtoon)
	var mprops: Array = vrm0.get("materialProperties", [])
	for i in range(mini(mprops.size(), jmats.size())):
		var mp: Dictionary = mprops[i]
		if str(mp.get("shader", "")) != "VRM/MToon":
			continue
		var fp_map: Dictionary = mp.get("floatProperties", {})
		var vp_map: Dictionary = mp.get("vectorProperties", {})
		var tp_map: Dictionary = mp.get("textureProperties", {})
		var jm: Dictionary = jmats[i]
		var m_exts: Dictionary = jm.get("extensions", {})
		var mtoon1 := {
			"specVersion": "1.0",
			"transparentWithZWrite": float(fp_map.get("_ZWrite", 1.0)) > 0.5,
			"renderQueueOffsetNumber": int(mp.get("renderQueue", 2000)) - 2000,
			"shadeColorFactor": _arr3_from_vec4(vp_map.get("_ShadeColor", [0.97, 0.81, 0.86, 1.0])),
			"shadingShiftFactor": clampf(float(fp_map.get("_ShadeShift", 0.0)), -1.0, 1.0),
			"shadingToonyFactor": clampf(float(fp_map.get("_ShadeToony", 0.9)), 0.0, 1.0),
			"giEqualizationFactor": clampf(1.0 - float(fp_map.get("_IndirectLightIntensity", 0.1)), 0.0, 1.0),
			"parametricRimColorFactor": _arr3_from_vec4(vp_map.get("_RimColor", [0.0, 0.0, 0.0, 1.0])),
			"parametricRimFresnelPowerFactor": float(fp_map.get("_RimFresnelPower", 5.0)),
			"parametricRimLiftFactor": float(fp_map.get("_RimLift", 0.0)),
			"rimLightingMixFactor": float(fp_map.get("_RimLightingMix", 1.0)),
			"outlineWidthMode": "worldCoordinates" if int(fp_map.get("_OutlineWidthMode", 0)) == 1 else ("screenCoordinates" if int(fp_map.get("_OutlineWidthMode", 0)) == 2 else "none"),
			"outlineWidthFactor": float(fp_map.get("_OutlineWidth", 0.0)) * 0.01,
			"outlineColorFactor": _arr3_from_vec4(vp_map.get("_OutlineColor", [0.0, 0.0, 0.0, 1.0])),
			"outlineLightingMixFactor": float(fp_map.get("_OutlineLightingMix", 1.0)),
			"uvAnimationScrollXSpeedFactor": float(fp_map.get("_UvAnimScrollX", 0.0)),
			"uvAnimationScrollYSpeedFactor": float(fp_map.get("_UvAnimScrollY", 0.0)),
			"uvAnimationRotationSpeedFactor": float(fp_map.get("_UvAnimRotation", 0.0)),
		}
		if tp_map.has("_ShadeTexture"):
			mtoon1["shadeMultiplyTexture"] = {"index": int(tp_map["_ShadeTexture"])}
		if tp_map.has("_SphereAdd"):
			mtoon1["matcapTexture"] = {"index": int(tp_map["_SphereAdd"])}
		m_exts["VRMC_materials_mtoon"] = mtoon1
		jm["extensions"] = m_exts
		jmats[i] = jm

	out["materials"] = jmats
	out["extensions"] = exts
	return out


static func _collect_chain(node_idx: int, jnodes: Array, out_chain: Array) -> void:
	if node_idx < 0 or node_idx >= jnodes.size():
		return
	out_chain.append(node_idx)
	var ch: Array = jnodes[node_idx].get("children", [])
	if not ch.is_empty():
		_collect_chain(int(ch[0]), jnodes, out_chain)


static func _map_vrm0_curve(raw: Dictionary) -> Dictionary:
	return {
		"inputMaxValue": float(raw.get("xRange", 90.0)),
		"outputScale": float(raw.get("yRange", 10.0)),
	}


static func _arr3_from_vec4(v: Variant) -> Array:
	if typeof(v) == TYPE_ARRAY and v.size() >= 3:
		return [float(v[0]), float(v[1]), float(v[2])]
	return [1.0, 1.0, 1.0]
