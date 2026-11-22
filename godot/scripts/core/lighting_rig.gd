class_name LightingRig
extends Node3D

## Controls Key / Fill / Rim DirectionalLight3Ds, WorldEnvironment (ambient, bloom, tonemap),
## lighting presets, and SpringBone wind vector.

signal lighting_changed

var key_light: DirectionalLight3D
var fill_light: DirectionalLight3D
var rim_light: DirectionalLight3D
var world_env: WorldEnvironment

var preset: String = "studio"
var key_azimuth_deg: float = 35.0
var key_elevation_deg: float = 30.0
var key_energy: float = 1.15
var key_color: Color = Color("#fff8f0")
var fill_energy: float = 0.42
var fill_color: Color = Color("#dce8ff")
var rim_energy: float = 0.55
var rim_color: Color = Color("#ffffff")
var ambient_energy: float = 0.45
var ambient_color: Color = Color("#e6ebf5")
var shadows_enabled: bool = true
## 落ち影 (キーライトの影) の調整
var shadow_opacity: float = 1.0      # 影の濃さ (1 を超えた分は MToon 側で落ち影をさらに暗くする。最大 2)
var shadow_softness: float = 0.0     # 影のぼけ (光源の大きさ, 度)。0 でくっきり
var shadow_blur: float = 1.0         # 影の縁のなめらかさ
var shadow_bias: float = 0.1         # 影のずれ (大きいと影が浮く、小さいと縞模様が出る)
var shadow_normal_bias: float = 2.0
var shadow_distance: float = 12.0    # 影を描く距離 (短いほど近くの影がきれい)
var shadow_quality: String = "high"  # low / medium / high / ultra

## 「くっきり影」: 鼻が頬に落とす影のような小さな影も出す組み合わせ。
##   影を面から浮かせる量 (法線方向のずれ・影のずれ) を減らし、描く範囲を狭めて細かくし、
##   ライトを少し横・上から当て、影を消す向きの補助光を弱める。
const SHARP_SHADOW := {
	"shadows_enabled": true, "shadow_normal_bias": 0.4, "shadow_bias": 0.03, "shadow_distance": 4.0,
	"shadow_quality": "ultra", "shadow_blur": 0.4, "shadow_softness": 0.0, "shadow_opacity": 1.4,
	"key_azimuth_deg": 50.0, "key_elevation_deg": 32.0, "fill_energy": 0.2,
}
## 影まわりの初期値 (「影を初期値に戻す」)
const SHADOW_DEFAULTS := {
	"shadows_enabled": true, "shadow_normal_bias": 2.0, "shadow_bias": 0.1, "shadow_distance": 12.0,
	"shadow_quality": "high", "shadow_blur": 1.0, "shadow_softness": 0.0, "shadow_opacity": 1.0,
	"key_azimuth_deg": 35.0, "key_elevation_deg": 30.0, "fill_energy": 0.42,
}
var bloom_enabled: bool = false
var bloom_intensity: float = 0.25
var exposure: float = 1.0
var tonemap: String = "filmic"
var wind: Vector3 = Vector3.ZERO
var show_gizmo: bool = false

var _gizmo_root: Node3D = null
var _gizmo_sun: MeshInstance3D = null
var _gizmo_shaft: MeshInstance3D = null
var _gizmo_head: MeshInstance3D = null
var _gizmo_mat: StandardMaterial3D = null


func setup(p_key: DirectionalLight3D, p_fill: DirectionalLight3D, p_rim: DirectionalLight3D, p_env: WorldEnvironment) -> void:
	key_light = p_key
	fill_light = p_fill
	rim_light = p_rim
	world_env = p_env
	_ensure_gizmo()
	_apply()


func set_gizmo_visible(v: bool) -> void:
	show_gizmo = v
	_apply()
	lighting_changed.emit()


static func describe_direction(az_deg: float, el_deg: float) -> String:
	var a: float = wrapf(az_deg, -180.0, 180.0)
	var h_txt := "正面"
	if absf(a) >= 157.5:
		h_txt = "真後ろ"
	elif absf(a) <= 22.5:
		h_txt = "正面"
	elif a > 22.5 and a <= 67.5:
		h_txt = "前・画面右斜め"
	elif a > 67.5 and a <= 112.5:
		h_txt = "画面右真横"
	elif a > 112.5:
		h_txt = "後ろ・画面右斜め"
	elif a < -22.5 and a >= -67.5:
		h_txt = "前・画面左斜め"
	elif a < -67.5 and a >= -112.5:
		h_txt = "画面左真横"
	else:
		h_txt = "後ろ・画面左斜め"

	var v_txt := ""
	if el_deg >= 72.0:
		v_txt = "・ほぼ真上"
	elif el_deg >= 20.0:
		v_txt = "・上から"
	elif el_deg > -10.0:
		v_txt = "・目の高さ"
	else:
		v_txt = "・下から"

	return "%s%s (方位 %.0f°, 仰角 %.0f°)" % [h_txt, v_txt, a, el_deg]


func apply_params(params: Dictionary) -> void:
	if params.has("preset") and params["preset"] != null:
		apply_preset(str(params["preset"]))
	if params.has("key_azimuth_deg") and params["key_azimuth_deg"] != null:
		key_azimuth_deg = float(params["key_azimuth_deg"])
	if params.has("key_elevation_deg") and params["key_elevation_deg"] != null:
		key_elevation_deg = clampf(float(params["key_elevation_deg"]), -85.0, 85.0)
	if params.has("key_energy") and params["key_energy"] != null:
		key_energy = maxf(float(params["key_energy"]), 0.0)
	if params.has("key_color") and params["key_color"] != null:
		key_color = Color(str(params["key_color"]))
	if params.has("fill_energy") and params["fill_energy"] != null:
		fill_energy = maxf(float(params["fill_energy"]), 0.0)
	if params.has("fill_color") and params["fill_color"] != null:
		fill_color = Color(str(params["fill_color"]))
	if params.has("rim_energy") and params["rim_energy"] != null:
		rim_energy = maxf(float(params["rim_energy"]), 0.0)
	if params.has("rim_color") and params["rim_color"] != null:
		rim_color = Color(str(params["rim_color"]))
	if params.has("ambient_energy") and params["ambient_energy"] != null:
		ambient_energy = maxf(float(params["ambient_energy"]), 0.0)
	if params.has("ambient_color") and params["ambient_color"] != null:
		ambient_color = Color(str(params["ambient_color"]))
	if params.has("shadows_enabled") and params["shadows_enabled"] != null:
		shadows_enabled = bool(params["shadows_enabled"])
	for k in ["shadow_opacity", "shadow_softness", "shadow_blur", "shadow_bias", "shadow_normal_bias", "shadow_distance"]:
		if params.has(k) and params[k] != null:
			set(k, maxf(float(params[k]), 0.0))
	if params.has("shadow_quality") and params["shadow_quality"] != null:
		shadow_quality = str(params["shadow_quality"])
	if params.has("bloom_enabled") and params["bloom_enabled"] != null:
		bloom_enabled = bool(params["bloom_enabled"])
	if params.has("bloom_intensity") and params["bloom_intensity"] != null:
		bloom_intensity = clampf(float(params["bloom_intensity"]), 0.0, 4.0)
	if params.has("exposure") and params["exposure"] != null:
		exposure = clampf(float(params["exposure"]), 0.1, 4.0)
	if params.has("tonemap") and params["tonemap"] != null:
		tonemap = str(params["tonemap"])
	if params.has("wind") and typeof(params["wind"]) == TYPE_ARRAY and params["wind"].size() >= 3:
		var w: Array = params["wind"]
		wind = Vector3(float(w[0]), float(w[1]), float(w[2]))
	if params.has("show_gizmo") and params["show_gizmo"] != null:
		show_gizmo = bool(params["show_gizmo"])
	_apply()
	lighting_changed.emit()


func apply_preset(p_name: String) -> void:
	preset = p_name
	match p_name:
		"studio":
			key_azimuth_deg = 35.0
			key_elevation_deg = 30.0
			key_energy = 1.15
			key_color = Color("#fff8f0")
			fill_energy = 0.42
			fill_color = Color("#dce8ff")
			rim_energy = 0.55
			rim_color = Color("#ffffff")
			ambient_energy = 0.45
			shadows_enabled = true
			bloom_enabled = false
			tonemap = "filmic"
		"daylight":
			key_azimuth_deg = 45.0
			key_elevation_deg = 52.0
			key_energy = 1.35
			key_color = Color("#fffdf5")
			fill_energy = 0.55
			fill_color = Color("#b8dcff")
			rim_energy = 0.35
			rim_color = Color("#fff7e8")
			ambient_energy = 0.6
			shadows_enabled = true
			bloom_enabled = false
			tonemap = "aces"
		"sunset":
			key_azimuth_deg = -65.0
			key_elevation_deg = 12.0
			key_energy = 1.25
			key_color = Color("#ff9d5c")
			fill_energy = 0.35
			fill_color = Color("#7088c8")
			rim_energy = 0.85
			rim_color = Color("#ffc480")
			ambient_energy = 0.35
			shadows_enabled = true
			bloom_enabled = true
			bloom_intensity = 0.3
			tonemap = "aces"
		"dramatic":
			key_azimuth_deg = 65.0
			key_elevation_deg = 22.0
			key_energy = 1.45
			key_color = Color("#f5f0ff")
			fill_energy = 0.12
			fill_color = Color("#4a6499")
			rim_energy = 1.1
			rim_color = Color("#7fd6ff")
			ambient_energy = 0.18
			shadows_enabled = true
			bloom_enabled = true
			bloom_intensity = 0.25
			tonemap = "filmic"
		"flat_toon":
			key_azimuth_deg = 10.0
			key_elevation_deg = 25.0
			key_energy = 1.0
			key_color = Color("#ffffff")
			fill_energy = 0.5
			fill_color = Color("#ffffff")
			rim_energy = 0.15
			rim_color = Color("#ffffff")
			ambient_energy = 0.65
			shadows_enabled = false
			bloom_enabled = false
			tonemap = "linear"
	_apply()
	lighting_changed.emit()


func to_dict() -> Dictionary:
	return {
		"preset": preset,
		"key_azimuth_deg": key_azimuth_deg,
		"key_elevation_deg": key_elevation_deg,
		"key_energy": key_energy,
		"key_color": "#" + key_color.to_html(false),
		"fill_energy": fill_energy,
		"fill_color": "#" + fill_color.to_html(false),
		"rim_energy": rim_energy,
		"rim_color": "#" + rim_color.to_html(false),
		"ambient_energy": ambient_energy,
		"ambient_color": "#" + ambient_color.to_html(false),
		"shadows_enabled": shadows_enabled,
		"shadow_opacity": shadow_opacity,
		"shadow_softness": shadow_softness,
		"shadow_blur": shadow_blur,
		"shadow_bias": shadow_bias,
		"shadow_normal_bias": shadow_normal_bias,
		"shadow_distance": shadow_distance,
		"shadow_quality": shadow_quality,
		"bloom_enabled": bloom_enabled,
		"bloom_intensity": bloom_intensity,
		"exposure": exposure,
		"tonemap": tonemap,
		"wind": [wind.x, wind.y, wind.z],
		"show_gizmo": show_gizmo,
	}


func _ensure_gizmo() -> void:
	if _gizmo_root != null:
		return
	_gizmo_mat = StandardMaterial3D.new()
	_gizmo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_gizmo_mat.albedo_color = Color("#ffd24d")
	_gizmo_mat.no_depth_test = false

	_gizmo_root = Node3D.new()
	_gizmo_root.name = "KeyLightGizmo"
	_gizmo_root.visible = false
	add_child(_gizmo_root)

	_gizmo_sun = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.085
	sm.height = 0.17
	_gizmo_sun.mesh = sm
	_gizmo_sun.layers = 2
	_gizmo_sun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gizmo_sun.material_override = _gizmo_mat
	_gizmo_root.add_child(_gizmo_sun)

	_gizmo_shaft = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.018
	cm.bottom_radius = 0.018
	cm.height = 0.55
	_gizmo_shaft.mesh = cm
	_gizmo_shaft.layers = 2
	_gizmo_shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gizmo_shaft.material_override = _gizmo_mat
	_gizmo_root.add_child(_gizmo_shaft)

	_gizmo_head = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.055
	cone.height = 0.16
	_gizmo_head.mesh = cone
	_gizmo_head.layers = 2
	_gizmo_head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gizmo_head.material_override = _gizmo_mat
	_gizmo_root.add_child(_gizmo_head)


func _update_gizmo() -> void:
	if _gizmo_root == null:
		return
	_gizmo_root.visible = show_gizmo
	if not show_gizmo or key_light == null:
		return
	_gizmo_mat.albedo_color = Color(
		maxf(key_color.r, 0.35),
		maxf(key_color.g, 0.35),
		maxf(key_color.b, 0.25),
		1.0
	)
	var target_pt := Vector3(0.0, 1.25, 0.0)
	var from_dir := key_light.transform.basis.z.normalized()
	var sun_pos := target_pt + from_dir * 1.45
	_gizmo_sun.position = sun_pos

	# Orient shaft & arrowhead along rays pointing toward character (-from_dir)
	var ray_dir := -from_dir
	var up_ref := Vector3.UP if absf(ray_dir.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	var x_axis := up_ref.cross(ray_dir).normalized()
	var z_axis := x_axis.cross(ray_dir).normalized()
	var rot_basis := Basis(x_axis, ray_dir, z_axis).orthonormalized()

	_gizmo_shaft.transform = Transform3D(rot_basis, sun_pos + ray_dir * 0.32)
	_gizmo_head.transform = Transform3D(rot_basis, sun_pos + ray_dir * 0.64)


func _apply() -> void:
	if key_light != null:
		key_light.rotation_degrees = Vector3(-key_elevation_deg, key_azimuth_deg, 0.0)
		key_light.light_energy = key_energy
		key_light.light_color = key_color
		key_light.shadow_enabled = shadows_enabled
		key_light.shadow_opacity = clampf(shadow_opacity, 0.0, 1.0)
		RenderingServer.global_shader_parameter_set("vv_cast_dark", clampf(shadow_opacity - 1.0, 0.0, 1.0) if shadows_enabled else 0.0)
		key_light.light_angular_distance = clampf(shadow_softness, 0.0, 10.0)
		key_light.shadow_blur = clampf(shadow_blur, 0.0, 4.0)
		key_light.shadow_bias = shadow_bias
		key_light.shadow_normal_bias = shadow_normal_bias
		key_light.directional_shadow_max_distance = clampf(shadow_distance, 1.0, 200.0)
		_apply_shadow_quality()
	if fill_light != null:
		fill_light.rotation_degrees = Vector3(-15.0, key_azimuth_deg - 110.0, 0.0)
		fill_light.light_energy = fill_energy
		fill_light.light_color = fill_color
		fill_light.shadow_enabled = false
	if rim_light != null:
		rim_light.rotation_degrees = Vector3(18.0, key_azimuth_deg + 165.0, 0.0)
		rim_light.light_energy = rim_energy
		rim_light.light_color = rim_color
		rim_light.shadow_enabled = false
	RenderingServer.global_shader_parameter_set("vv_ambient_color", Vector3(ambient_color.r, ambient_color.g, ambient_color.b))
	RenderingServer.global_shader_parameter_set("vv_ambient_energy", ambient_energy)
	if world_env != null and world_env.environment != null:
		var env := world_env.environment
		env.ambient_light_color = ambient_color
		env.ambient_light_energy = ambient_energy
		env.glow_enabled = bloom_enabled
		env.glow_intensity = bloom_intensity
		# 既定 (しきい値 1.0・ソフトライト合成) だと白い服やハイライトでもほとんど光らないので、
		# 少し暗めの所からにじませ、スクリーン合成ではっきり見えるようにする
		env.glow_hdr_threshold = 0.75
		env.glow_hdr_scale = 2.0
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
		env.glow_bloom = 0.0
		env.tonemap_exposure = exposure
		match tonemap:
			"linear":
				env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
			"reinhard":
				env.tonemap_mode = Environment.TONE_MAPPER_REINHARDT
			"aces":
				env.tonemap_mode = Environment.TONE_MAPPER_ACES
			_:
				env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_update_gizmo()


## 影の解像度とぼかしの品質 (画面全体の設定)。
var _applied_quality := ""


func _apply_shadow_quality() -> void:
	if _applied_quality == shadow_quality:
		return
	_applied_quality = shadow_quality
	var size := 4096
	var q := RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
	match shadow_quality:
		"low":
			size = 2048
			q = RenderingServer.SHADOW_QUALITY_SOFT_LOW
		"medium":
			size = 4096
			q = RenderingServer.SHADOW_QUALITY_SOFT_LOW
		"ultra":
			size = 8192
			q = RenderingServer.SHADOW_QUALITY_SOFT_ULTRA
		_:
			size = 4096
			q = RenderingServer.SHADOW_QUALITY_SOFT_HIGH
	RenderingServer.directional_shadow_atlas_set_size(size, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(q)
