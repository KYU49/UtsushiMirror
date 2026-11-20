class_name VrmMtoon
extends RefCounted

## Applies VRMC_materials_mtoon-1.0, KHR_materials_emissive_strength,
## VRMC_materials_hdr_emissiveMultiplier, KHR_materials_unlit, and KHR_texture_transform
## onto Godot ShaderMaterials at runtime, caching shader variants by render_mode.

const BASE_SHADER_PATH := "res://shaders/mtoon10.gdshader"
const OUTLINE_SHADER_PATH := "res://shaders/mtoon10_outline.gdshader"
const BASE_SHADER_RES: Shader = preload("res://shaders/mtoon10.gdshader")
const OUTLINE_SHADER_RES: Shader = preload("res://shaders/mtoon10_outline.gdshader")

static var _shader_cache: Dictionary = {}
static var _outline_shader_cache: Dictionary = {}
static var _base_shader_code: String = ""
static var _outline_shader_code: String = ""


static func _get_mtoon_shader(double_sided: bool, is_blend: bool, z_write: bool, is_unlit: bool) -> Shader:
	var key := "%s_%s_%s_%s" % [double_sided, is_blend, z_write, is_unlit]
	if _shader_cache.has(key):
		return _shader_cache[key]

	if _base_shader_code == "":
		if BASE_SHADER_RES != null and BASE_SHADER_RES.code != "":
			_base_shader_code = BASE_SHADER_RES.code
		else:
			var f := FileAccess.open(BASE_SHADER_PATH, FileAccess.READ)
			_base_shader_code = f.get_as_text() if f != null else ""

	var modes := PackedStringArray()
	modes.append("cull_disabled" if double_sided else "cull_back")
	if is_blend:
		modes.append("depth_draw_always" if z_write else "depth_draw_never")
	else:
		modes.append("depth_draw_opaque")
	if is_unlit:
		modes.append("unshaded")
	else:
		modes.append("ambient_light_disabled")
		modes.append("specular_disabled")

	var code := _base_shader_code.replace(
		"render_mode cull_back, depth_draw_opaque, ambient_light_disabled, specular_disabled;",
		"render_mode " + ", ".join(modes) + ";"
	)
	if is_blend:
		code = code.replace("// ALPHA_OUTPUT_LINE", "ALPHA = base.a;")
	var sh := Shader.new()
	sh.code = code
	_shader_cache[key] = sh
	return sh


static func _get_outline_shader(is_blend: bool, z_write: bool) -> Shader:
	var key := "%s_%s" % [is_blend, z_write]
	if _outline_shader_cache.has(key):
		return _outline_shader_cache[key]

	if _outline_shader_code == "":
		if OUTLINE_SHADER_RES != null and OUTLINE_SHADER_RES.code != "":
			_outline_shader_code = OUTLINE_SHADER_RES.code
		else:
			var f := FileAccess.open(OUTLINE_SHADER_PATH, FileAccess.READ)
			_outline_shader_code = f.get_as_text() if f != null else ""

	var depth_mode := "depth_draw_opaque"
	if is_blend:
		depth_mode = "depth_draw_always" if z_write else "depth_draw_never"

	var code := _outline_shader_code.replace(
		"render_mode cull_front, unshaded, depth_draw_opaque;",
		"render_mode cull_front, unshaded, " + depth_mode + ";"
	)
	if is_blend:
		code = code.replace("// OUTLINE_ALPHA_LINE", "ALPHA = u_outline_color.a * base.a;")
	var sh := Shader.new()
	sh.code = code
	_outline_shader_cache[key] = sh
	return sh


static func _get_tex(gltf_json: Dictionary, textures: Array, tex_info: Variant) -> Texture2D:
	if typeof(tex_info) != TYPE_DICTIONARY:
		return null
	var idx: int = int(tex_info.get("index", -1))
	if idx < 0 or idx >= textures.size():
		return null
	var gt = textures[idx]
	if gt is Texture2D:
		return gt
	if gt != null and gt.has_method("get_src_image"):
		return null
	return null


static func _resolve_tex(state: GLTFState, tex_info: Variant) -> Texture2D:
	if typeof(tex_info) != TYPE_DICTIONARY:
		return null
	var tex_idx: int = int(tex_info.get("index", -1))
	var textures := state.get_textures()
	var images := state.get_images()
	if tex_idx < 0 or tex_idx >= textures.size():
		return null
	var gt: GLTFTexture = textures[tex_idx]
	var img_idx: int = gt.src_image
	if img_idx >= 0 and img_idx < images.size():
		var img = images[img_idx]
		if img is Texture2D:
			return img
		if img is Image:
			return ImageTexture.create_from_image(img)
	return null


static func _vec4_from_arr(arr: Variant, def: Color) -> Color:
	if typeof(arr) == TYPE_ARRAY and arr.size() >= 4:
		return Color(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
	if typeof(arr) == TYPE_ARRAY and arr.size() >= 3:
		return Color(float(arr[0]), float(arr[1]), float(arr[2]), def.a)
	return def


static func _vec3_from_arr(arr: Variant, def: Vector3) -> Vector3:
	if typeof(arr) == TYPE_ARRAY and arr.size() >= 3:
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return def


static func build_materials(gltf_json: Dictionary, state: GLTFState) -> Array:
	var jmats: Array = gltf_json.get("materials", [])
	var state_mats := state.get_materials()
	var out := []
	out.resize(jmats.size())

	for i in range(jmats.size()):
		var jm: Dictionary = jmats[i]
		var exts: Dictionary = jm.get("extensions", {})
		var orig_mat: Material = state_mats[i] if i < state_mats.size() else null

		if not exts.has("VRMC_materials_mtoon"):
			out[i] = orig_mat
			continue

		var mtoon: Dictionary = exts["VRMC_materials_mtoon"]
		var is_unlit := false
		var alpha_mode: String = str(jm.get("alphaMode", "OPAQUE"))
		var is_blend := (alpha_mode == "BLEND")
		var is_mask := (alpha_mode == "MASK")
		var double_sided := bool(jm.get("doubleSided", false))
		var z_write := bool(mtoon.get("transparentWithZWrite", false))
		var render_offset := int(mtoon.get("renderQueueOffsetNumber", 0))

		var mat := ShaderMaterial.new()
		mat.shader = _get_mtoon_shader(double_sided, is_blend, z_write, is_unlit)
		mat.resource_name = str(jm.get("name", "mtoon_%d" % i))
		mat.render_priority = clampi(render_offset, -128, 127)

		var pbr: Dictionary = jm.get("pbrMetallicRoughness", {})
		var base_col := _vec4_from_arr(pbr.get("baseColorFactor", null), Color(1, 1, 1, 1))
		mat.set_shader_parameter("u_base_color", base_col)
		mat.set_shader_parameter("u_is_unlit", is_unlit)
		mat.set_shader_parameter("u_is_alpha_mask", is_mask)
		mat.set_shader_parameter("u_alpha_cutoff", float(jm.get("alphaCutoff", 0.5)))

		var base_tex_info = pbr.get("baseColorTexture", null)
		var base_tex := _resolve_tex(state, base_tex_info)
		if base_tex != null:
			mat.set_shader_parameter("u_has_base_tex", true)
			mat.set_shader_parameter("u_base_tex", base_tex)

		var uv_scale := Vector2(1.0, 1.0)
		var uv_offset := Vector2(0.0, 0.0)
		if typeof(base_tex_info) == TYPE_DICTIONARY:
			var tex_exts: Dictionary = base_tex_info.get("extensions", {})
			if tex_exts.has("KHR_texture_transform"):
				var tt: Dictionary = tex_exts["KHR_texture_transform"]
				var sc = tt.get("scale", [1.0, 1.0])
				var off = tt.get("offset", [0.0, 0.0])
				if typeof(sc) == TYPE_ARRAY and sc.size() >= 2:
					uv_scale = Vector2(float(sc[0]), float(sc[1]))
				if typeof(off) == TYPE_ARRAY and off.size() >= 2:
					uv_offset = Vector2(float(off[0]), float(off[1]))
		mat.set_shader_parameter("u_uv_scale", uv_scale)
		mat.set_shader_parameter("u_uv_offset", uv_offset)

		# Shade
		var shade_col := _vec3_from_arr(mtoon.get("shadeColorFactor", null), Vector3(0.97, 0.81, 0.86))
		mat.set_shader_parameter("u_shade_color", shade_col)
		var shade_tex := _resolve_tex(state, mtoon.get("shadeMultiplyTexture", null))
		if shade_tex != null:
			mat.set_shader_parameter("u_has_shade_tex", true)
			mat.set_shader_parameter("u_shade_tex", shade_tex)

		# Shading curve
		mat.set_shader_parameter("u_shading_shift", float(mtoon.get("shadingShiftFactor", 0.0)))
		var shift_tex_info = mtoon.get("shadingShiftTexture", null)
		var shift_tex := _resolve_tex(state, shift_tex_info)
		if shift_tex != null:
			mat.set_shader_parameter("u_has_shading_shift_tex", true)
			mat.set_shader_parameter("u_shading_shift_tex", shift_tex)
			mat.set_shader_parameter("u_shading_shift_tex_scale", float(shift_tex_info.get("scale", 1.0)))
		mat.set_shader_parameter("u_shading_toony", float(mtoon.get("shadingToonyFactor", 0.9)))
		mat.set_shader_parameter("u_gi_equalization", float(mtoon.get("giEqualizationFactor", 0.9)))

		# Normal
		var norm_info = jm.get("normalTexture", null)
		var norm_tex := _resolve_tex(state, norm_info)
		if norm_tex != null:
			mat.set_shader_parameter("u_has_normal_tex", true)
			mat.set_shader_parameter("u_normal_tex", norm_tex)
			mat.set_shader_parameter("u_normal_scale", float(norm_info.get("scale", 1.0)))

		# Emissive (KHR_materials_emissive_strength + legacy VRMC_materials_hdr_emissiveMultiplier)
		var emissive_mult := 1.0
		if exts.has("KHR_materials_emissive_strength"):
			emissive_mult *= float(exts["KHR_materials_emissive_strength"].get("emissiveStrength", 1.0))
		if exts.has("VRMC_materials_hdr_emissiveMultiplier"):
			emissive_mult *= float(exts["VRMC_materials_hdr_emissiveMultiplier"].get("emissiveMultiplier", 1.0))
		var emissive := _vec3_from_arr(jm.get("emissiveFactor", null), Vector3.ZERO) * emissive_mult
		mat.set_shader_parameter("u_emissive_color", emissive)
		var emissive_tex := _resolve_tex(state, jm.get("emissiveTexture", null))
		if emissive_tex != null:
			mat.set_shader_parameter("u_has_emissive_tex", true)
			mat.set_shader_parameter("u_emissive_tex", emissive_tex)

		# MatCap
		mat.set_shader_parameter("u_matcap_color", _vec3_from_arr(mtoon.get("matcapFactor", null), Vector3.ONE))
		var matcap_tex := _resolve_tex(state, mtoon.get("matcapTexture", null))
		if matcap_tex != null:
			mat.set_shader_parameter("u_has_matcap_tex", true)
			mat.set_shader_parameter("u_matcap_tex", matcap_tex)

		# Rim
		mat.set_shader_parameter("u_rim_color", _vec3_from_arr(mtoon.get("parametricRimColorFactor", null), Vector3.ZERO))
		mat.set_shader_parameter("u_rim_fresnel_power", float(mtoon.get("parametricRimFresnelPowerFactor", 5.0)))
		mat.set_shader_parameter("u_rim_lift", float(mtoon.get("parametricRimLiftFactor", 0.0)))
		mat.set_shader_parameter("u_rim_lighting_mix", float(mtoon.get("rimLightingMixFactor", 1.0)))
		var rim_tex := _resolve_tex(state, mtoon.get("rimMultiplyTexture", null))
		if rim_tex != null:
			mat.set_shader_parameter("u_has_rim_tex", true)
			mat.set_shader_parameter("u_rim_tex", rim_tex)

		# UV Animation
		var anim_mask_tex := _resolve_tex(state, mtoon.get("uvAnimationMaskTexture", null))
		if anim_mask_tex != null:
			mat.set_shader_parameter("u_has_uv_anim_mask", true)
			mat.set_shader_parameter("u_uv_anim_mask_tex", anim_mask_tex)
		mat.set_shader_parameter("u_uv_anim_scroll_x", float(mtoon.get("uvAnimationScrollXSpeedFactor", 0.0)))
		mat.set_shader_parameter("u_uv_anim_scroll_y", float(mtoon.get("uvAnimationScrollYSpeedFactor", 0.0)))
		mat.set_shader_parameter("u_uv_anim_rotation", float(mtoon.get("uvAnimationRotationSpeedFactor", 0.0)))

		# Outline next_pass
		var outline_mode_str: String = str(mtoon.get("outlineWidthMode", "none"))
		var outline_width := float(mtoon.get("outlineWidthFactor", 0.0))
		if outline_mode_str != "none" and outline_width > 0.0:
			var outline_mat := ShaderMaterial.new()
			outline_mat.shader = _get_outline_shader(is_blend, z_write)
			outline_mat.render_priority = clampi(render_offset, -128, 127)
			outline_mat.set_shader_parameter("u_outline_mode", 2 if outline_mode_str == "screenCoordinates" else 1)
			outline_mat.set_shader_parameter("u_outline_width", outline_width)
			var out_tex := _resolve_tex(state, mtoon.get("outlineWidthMultiplyTexture", null))
			if out_tex != null:
				outline_mat.set_shader_parameter("u_has_outline_tex", true)
				outline_mat.set_shader_parameter("u_outline_tex", out_tex)
			var out_col_arr = mtoon.get("outlineColorFactor", [0.0, 0.0, 0.0])
			outline_mat.set_shader_parameter("u_outline_color", _vec4_from_arr(out_col_arr, Color(0, 0, 0, 1)))
			outline_mat.set_shader_parameter("u_outline_lighting_mix", float(mtoon.get("outlineLightingMixFactor", 1.0)))
			outline_mat.set_shader_parameter("u_base_color", base_col)
			if base_tex != null:
				outline_mat.set_shader_parameter("u_has_base_tex", true)
				outline_mat.set_shader_parameter("u_base_tex", base_tex)
			outline_mat.set_shader_parameter("u_uv_scale", uv_scale)
			outline_mat.set_shader_parameter("u_uv_offset", uv_offset)
			outline_mat.set_shader_parameter("u_is_alpha_mask", is_mask)
			outline_mat.set_shader_parameter("u_alpha_cutoff", float(jm.get("alphaCutoff", 0.5)))
			mat.next_pass = outline_mat

		out[i] = mat

	return out
