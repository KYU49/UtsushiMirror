class_name VrmExpressions
extends RefCounted

## Official VRM 1.0 Expressions subsystem.
## Supports all 18 preset expressions + custom expressions,
## morphTargetBinds, materialColorBinds, textureTransformBinds,
## isBinary, overrideBlink / overrideLookAt / overrideMouth (none / block / blend),
## and smooth transitions.

const PRESET_NAMES: Array[String] = [
	"happy", "angry", "sad", "relaxed", "surprised",
	"aa", "ih", "ou", "ee", "oh",
	"blink", "blinkLeft", "blinkRight",
	"lookUp", "lookDown", "lookLeft", "lookRight",
	"neutral",
]

const BLINK_SET := {"blink": true, "blinkLeft": true, "blinkRight": true}
const LOOKAT_SET := {"lookUp": true, "lookDown": true, "lookLeft": true, "lookRight": true}
const MOUTH_SET := {"aa": true, "ih": true, "ou": true, "ee": true, "oh": true}

var expressions: Dictionary = {} # name -> ExpressionDef
var target_weights: Dictionary = {} # name -> float
var current_weights: Dictionary = {} # name -> float
var transition_speeds: Dictionary = {} # name -> float (weight/sec, 0 = instant)

var _mesh_morph_defaults: Array = [] # [{ mi: MeshInstance3D, count: int }]
var _material_list: Array = [] # Array[Material] aligned with glTF material index
var _material_base_colors: Dictionary = {} # mat_idx -> Color
var _material_base_uv: Dictionary = {} # mat_idx -> {scale: Vector2, offset: Vector2}
var _bound_mat_indices: Array[int] = []
var _bound_morph_slots: Array = [] # [{mi: MeshInstance3D, index: int}]
var _prev_effective: Dictionary = {}
var _prev_result: Dictionary = {}
var _applied_once: bool = false
## リップシンク (音声・テキスト) が口を動かしている間は true。
## アニメ・トラッキングの口を混ぜず、ほかの表情の overrideMouth でも口を抑えない (app_controller が毎フレーム決める)
var mouth_locked: bool = false


class ExpressionDef:
	var name: String
	var is_preset: bool
	var is_binary: bool = false
	var override_blink: String = "none"
	var override_lookat: String = "none"
	var override_mouth: String = "none"
	var morph_binds: Array = [] # [{mi: MeshInstance3D, index: int, weight: float}]
	var color_binds: Array = [] # [{mat_idx: int, type: String, target: Color}]
	var tex_binds: Array = [] # [{mat_idx: int, scale: Vector2, offset: Vector2}]


func setup(
	gltf_json: Dictionary,
	node_to_mesh_instances: Dictionary,
	materials: Array
) -> void:
	expressions.clear()
	target_weights.clear()
	current_weights.clear()
	transition_speeds.clear()
	_mesh_morph_defaults.clear()
	_material_list = materials
	_material_base_colors.clear()
	_material_base_uv.clear()

	var seen_mi: Dictionary = {}
	for gltf_node in node_to_mesh_instances.keys():
		for mi in node_to_mesh_instances[gltf_node]:
			if mi is MeshInstance3D and not seen_mi.has(mi.get_instance_id()):
				seen_mi[mi.get_instance_id()] = true
				var bs_count: int = mi.get_blend_shape_count()
				if bs_count > 0:
					_mesh_morph_defaults.append({"mi": mi, "count": bs_count})

	for i in range(materials.size()):
		var mat = materials[i]
		if mat is ShaderMaterial:
			var sc: Variant = mat.get_shader_parameter("u_uv_scale")
			var off: Variant = mat.get_shader_parameter("u_uv_offset")
			_material_base_uv[i] = {
				"scale": sc if sc is Vector2 else Vector2.ONE,
				"offset": off if off is Vector2 else Vector2.ZERO,
			}
		elif mat is StandardMaterial3D:
			_material_base_colors[i] = mat.albedo_color
			_material_base_uv[i] = {
				"scale": Vector2(mat.uv1_scale.x, mat.uv1_scale.y),
				"offset": Vector2(mat.uv1_offset.x, mat.uv1_offset.y),
			}

	var vrm_ext: Dictionary = gltf_json.get("extensions", {}).get("VRMC_vrm", {})
	var expr_root: Dictionary = vrm_ext.get("expressions", {})

	var presets: Dictionary = expr_root.get("preset", {})
	for pname in presets.keys():
		_register_expr(str(pname), true, presets[pname], node_to_mesh_instances)

	var customs: Dictionary = expr_root.get("custom", {})
	for cname in customs.keys():
		_register_expr(str(cname), false, customs[cname], node_to_mesh_instances)

	_bound_mat_indices.clear()
	_bound_morph_slots.clear()
	_prev_effective.clear()
	_prev_result.clear()
	_applied_once = false
	var mat_seen: Dictionary = {}
	var morph_seen: Dictionary = {}
	for def: ExpressionDef in expressions.values():
		for mb in def.morph_binds:
			var mi: MeshInstance3D = mb["mi"]
			var idx: int = int(mb["index"])
			var mkey := "%d:%d" % [mi.get_instance_id(), idx]
			if not morph_seen.has(mkey):
				morph_seen[mkey] = true
				_bound_morph_slots.append({"mi": mi, "index": idx})
		for cb in def.color_binds:
			var midx: int = int(cb["mat_idx"])
			if not mat_seen.has(midx):
				mat_seen[midx] = true
				_bound_mat_indices.append(midx)
		for tb in def.tex_binds:
			var midx: int = int(tb["mat_idx"])
			if not mat_seen.has(midx):
				mat_seen[midx] = true
				_bound_mat_indices.append(midx)

	# Ensure all 18 official presets exist as queryable keys even if omitted
	for pname in PRESET_NAMES:
		if not expressions.has(pname):
			var empty_def := ExpressionDef.new()
			empty_def.name = pname
			empty_def.is_preset = true
			expressions[pname] = empty_def
			target_weights[pname] = 0.0
			current_weights[pname] = 0.0
			transition_speeds[pname] = 0.0


func _register_expr(ename: String, is_preset: bool, raw: Dictionary, node_to_mis: Dictionary) -> void:
	var def := ExpressionDef.new()
	def.name = ename
	def.is_preset = is_preset
	def.is_binary = bool(raw.get("isBinary", false))
	def.override_blink = str(raw.get("overrideBlink", "none"))
	def.override_lookat = str(raw.get("overrideLookAt", "none"))
	def.override_mouth = str(raw.get("overrideMouth", "none"))

	for b in raw.get("morphTargetBinds", []):
		var gnode: int = int(b.get("node", -1))
		var idx: int = int(b.get("index", -1))
		var w: float = float(b.get("weight", 1.0))
		var mis: Array = node_to_mis.get(gnode, [])
		for mi in mis:
			if mi is MeshInstance3D and idx >= 0 and idx < mi.get_blend_shape_count():
				def.morph_binds.append({"mi": mi, "index": idx, "weight": w})

	for cb in raw.get("materialColorBinds", []):
		var mat_idx: int = int(cb.get("material", -1))
		var ctype: String = str(cb.get("type", "color"))
		var tv: Array = cb.get("targetValue", [1.0, 1.0, 1.0, 1.0])
		if mat_idx >= 0 and mat_idx < _material_list.size() and tv.size() >= 4:
			def.color_binds.append({
				"mat_idx": mat_idx,
				"type": ctype,
				"target": Color(float(tv[0]), float(tv[1]), float(tv[2]), float(tv[3])),
			})

	for tb in raw.get("textureTransformBinds", []):
		var mat_idx: int = int(tb.get("material", -1))
		var sc: Array = tb.get("scale", [1.0, 1.0])
		var off: Array = tb.get("offset", [0.0, 0.0])
		if mat_idx >= 0 and mat_idx < _material_list.size():
			def.tex_binds.append({
				"mat_idx": mat_idx,
				"scale": Vector2(float(sc[0]), float(sc[1])) if sc.size() >= 2 else Vector2.ONE,
				"offset": Vector2(float(off[0]), float(off[1])) if off.size() >= 2 else Vector2.ZERO,
			})

	expressions[ename] = def
	target_weights[ename] = 0.0
	current_weights[ename] = 0.0
	transition_speeds[ename] = 0.0


func get_expression_names() -> Array[String]:
	var out: Array[String] = []
	for k in expressions.keys():
		out.append(str(k))
	out.sort()
	return out


func set_weight(ename: String, weight: float, transition_sec: float = 0.0) -> void:
	if not expressions.has(ename):
		return
	var clamped := clampf(weight, 0.0, 1.0)
	target_weights[ename] = clamped
	if transition_sec <= 0.0001:
		current_weights[ename] = clamped
		transition_speeds[ename] = 0.0
	else:
		transition_speeds[ename] = maxf(absf(clamped - float(current_weights.get(ename, 0.0))) / transition_sec, 0.01)


func set_weights(weights_dict: Dictionary, transition_sec: float = 0.0, reset_others: bool = false) -> void:
	if reset_others:
		for k in target_weights.keys():
			if not weights_dict.has(k):
				set_weight(str(k), 0.0, transition_sec)
	for k in weights_dict.keys():
		set_weight(str(k), float(weights_dict[k]), transition_sec)


func reset_all(transition_sec: float = 0.0) -> void:
	for k in target_weights.keys():
		set_weight(str(k), 0.0, transition_sec)


func get_weights_snapshot() -> Dictionary:
	return current_weights.duplicate()


## Computes effective expression weights (including binary snap, override attenuation,
## and automatic blink/lookAt injection) and writes morph targets + shader uniforms.
func update(dt: float, lookat_expr_weights: Dictionary = {}, auto_blink_weight: float = 0.0) -> Dictionary:
	# 1. Advance smooth transitions
	for ename in expressions.keys():
		var cur: float = float(current_weights.get(ename, 0.0))
		var tgt: float = float(target_weights.get(ename, 0.0))
		var spd: float = float(transition_speeds.get(ename, 0.0))
		if spd > 0.0 and not is_equal_approx(cur, tgt):
			current_weights[ename] = move_toward(cur, tgt, spd * dt)
		else:
			current_weights[ename] = tgt

	# 2. Combine manual/API weights with auto-blink & lookAt expressions
	var raw_weights: Dictionary = {}
	for ename in expressions.keys():
		var w: float = float(current_weights.get(ename, 0.0))
		if ename == "blink":
			w = maxf(w, auto_blink_weight)
		if lookat_expr_weights.has(ename):
			w = maxf(w, float(lookat_expr_weights[ename]))
		var def: ExpressionDef = expressions[ename]
		if def.is_binary:
			w = 1.0 if w > 0.5 else 0.0
		raw_weights[ename] = w

	# 3. Compute override multipliers per VRM 1.0 spec
	var blink_mul := 1.0
	var lookat_mul := 1.0
	var mouth_mul := 1.0
	for ename in expressions.keys():
		var w: float = raw_weights[ename]
		if w <= 0.0:
			continue
		var def: ExpressionDef = expressions[ename]
		blink_mul = _apply_override(blink_mul, def.override_blink, w)
		lookat_mul = _apply_override(lookat_mul, def.override_lookat, w)
		if not mouth_locked:
			mouth_mul = _apply_override(mouth_mul, def.override_mouth, w)

	var effective: Dictionary = {}
	for ename in expressions.keys():
		var w: float = raw_weights[ename]
		if BLINK_SET.has(ename):
			w *= blink_mul
		elif LOOKAT_SET.has(ename):
			w *= lookat_mul
		elif MOUTH_SET.has(ename):
			w *= mouth_mul
		effective[ename] = clampf(w, 0.0, 1.0)

	# 4. Skip GPU/blend-shape writes when effective weights have not changed since last frame
	var changed := not _applied_once or _prev_effective.size() != effective.size()
	if not changed:
		for ename in effective.keys():
			if not is_equal_approx(float(effective[ename]), float(_prev_effective.get(ename, -1.0))):
				changed = true
				break
	if not changed:
		return _prev_result

	# Reset only bound morph slots (instead of every morph on every mesh)
	for entry in _bound_morph_slots:
		var mi: MeshInstance3D = entry["mi"]
		if is_instance_valid(mi):
			mi.set_blend_shape_value(int(entry["index"]), 0.0)

	var mat_color_acc: Dictionary = {} # mat_idx -> {type -> Color}
	var mat_uv_acc: Dictionary = {} # mat_idx -> {scale: Vector2, offset: Vector2}

	# 5. Accumulate active expression bindings
	for ename in expressions.keys():
		var w: float = effective[ename]
		if w <= 0.0001:
			continue
		var def: ExpressionDef = expressions[ename]

		for mb in def.morph_binds:
			var mi: MeshInstance3D = mb["mi"]
			if is_instance_valid(mi):
				var idx: int = mb["index"]
				var prev: float = mi.get_blend_shape_value(idx)
				mi.set_blend_shape_value(idx, clampf(prev + w * float(mb["weight"]), 0.0, 1.0))

		for cb in def.color_binds:
			var midx: int = cb["mat_idx"]
			var ctype: String = cb["type"]
			var tgt_col: Color = cb["target"]
			if not mat_color_acc.has(midx):
				mat_color_acc[midx] = {}
			var base_mul := Color(1.0, 1.0, 1.0, 1.0)
			if mat_color_acc[midx].has(ctype):
				base_mul = mat_color_acc[midx][ctype]
			mat_color_acc[midx][ctype] = base_mul.lerp(tgt_col, w)

		for tb in def.tex_binds:
			var midx: int = tb["mat_idx"]
			if not mat_uv_acc.has(midx):
				mat_uv_acc[midx] = {"scale": Vector2.ONE, "offset": Vector2.ZERO}
			var cur_s: Vector2 = mat_uv_acc[midx]["scale"]
			var cur_o: Vector2 = mat_uv_acc[midx]["offset"]
			mat_uv_acc[midx]["scale"] = cur_s.lerp(tb["scale"], w)
			mat_uv_acc[midx]["offset"] = cur_o.lerp(tb["offset"], w)

	# 6. Write material parameters back cleanly (only expression-bound materials)
	for midx in _bound_mat_indices:
		var mat = _material_list[midx]
		if mat == null:
			continue
		var cols: Dictionary = mat_color_acc.get(midx, {})
		var uvs: Dictionary = mat_uv_acc.get(midx, {"scale": Vector2.ONE, "offset": Vector2.ZERO})
		if mat is ShaderMaterial:
			mat.set_shader_parameter("u_expr_color_mul", cols.get("color", Color.WHITE))
			mat.set_shader_parameter("u_expr_shade_mul", cols.get("shadeColor", Color.WHITE))
			mat.set_shader_parameter("u_expr_emissive_mul", cols.get("emissiveColor", Color.WHITE))
			mat.set_shader_parameter("u_expr_matcap_mul", cols.get("matcapColor", Color.WHITE))
			mat.set_shader_parameter("u_expr_rim_mul", cols.get("rimColor", Color.WHITE))
			mat.set_shader_parameter("u_expr_uv_scale", uvs["scale"])
			mat.set_shader_parameter("u_expr_uv_offset", uvs["offset"])
			if mat.next_pass is ShaderMaterial:
				var np: ShaderMaterial = mat.next_pass
				np.set_shader_parameter("u_expr_outline_mul", cols.get("outlineColor", Color.WHITE))
				np.set_shader_parameter("u_expr_uv_scale", uvs["scale"])
				np.set_shader_parameter("u_expr_uv_offset", uvs["offset"])
		elif mat is StandardMaterial3D:
			var base_c: Color = _material_base_colors.get(midx, Color.WHITE)
			var c_mul: Color = cols.get("color", Color.WHITE)
			mat.albedo_color = base_c * c_mul
			var base_uv: Dictionary = _material_base_uv.get(midx, {"scale": Vector2.ONE, "offset": Vector2.ZERO})
			var s_mul: Vector2 = uvs["scale"]
			var o_add: Vector2 = uvs["offset"]
			mat.uv1_scale = Vector3(base_uv["scale"].x * s_mul.x, base_uv["scale"].y * s_mul.y, 1.0)
			mat.uv1_offset = Vector3(base_uv["offset"].x + o_add.x, base_uv["offset"].y + o_add.y, 0.0)

	_prev_effective = effective.duplicate()
	_prev_result = {"lookat_mul": lookat_mul, "blink_mul": blink_mul, "mouth_mul": mouth_mul, "effective": effective}
	_applied_once = true
	return _prev_result


static func _apply_override(cur: float, mode: String, weight: float) -> float:
	if mode == "block":
		return 0.0 if weight > 0.0 else cur
	if mode == "blend":
		return cur * clampf(1.0 - weight, 0.0, 1.0)
	return cur
