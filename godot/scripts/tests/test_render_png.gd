extends SceneTree

const VrmLoaderScript := preload("res://scripts/vrm/vrm_loader.gd")

var _frame := 0
var _vp: SubViewport
var _vrm

func _initialize() -> void:
	var win := get_root()
	var sv := SubViewport.new()
	sv.size = Vector2i(512, 512)
	sv.transparent_bg = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.own_world_3d = true
	win.add_child(sv)
	_vp = sv

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.92, 0.98)
	env.ambient_light_energy = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	sv.add_child(we)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 35, 0)
	light.light_energy = 1.4
	sv.add_child(light)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.05, 2.2)
	cam.look_at_from_position(cam.position, Vector3(0.0, 0.9, 0.0), Vector3.UP)
	sv.add_child(cam)
	cam.current = true

	var path := ProjectSettings.globalize_path("res://../assets/samples/Seed-san.vrm")
	var res := VrmLoaderScript.load_vrm(path)
	if res.get("ok", false):
		_vrm = res["runtime"]
		sv.add_child(_vrm)
		_vrm.expressions.set_weight("happy", 1.0, 0.0)
		_vrm.direct_bone_overrides["leftUpperArm"] = Quaternion.from_euler(Vector3(0.0, 0.0, -0.9))
		_vrm.direct_bone_overrides["rightUpperArm"] = Quaternion.from_euler(Vector3(0.0, 0.0, 0.9))

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 4:
		var img: Image = _vp.get_texture().get_image()
		var out_path := ProjectSettings.globalize_path("res://../target/test_m2_seed.png")
		img.save_png(out_path)
		print("SAVED_PNG=", out_path, " size=", img.get_width(), "x", img.get_height())
		_vp.free()
		quit(0)
	return false
