extends SceneTree

const CameraRigScript := preload("res://scripts/core/camera_rig.gd")
const LightingRigScript := preload("res://scripts/core/lighting_rig.gd")
const BackgroundManagerScript := preload("res://scripts/core/background_manager.gd")
const HotkeyManagerScript := preload("res://scripts/core/hotkey_manager.gd")
const ConfigManagerScript := preload("res://scripts/core/config_manager.gd")

var _ran := false

func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run_tests()
	return true

func _run_tests() -> void:
	var root := Node3D.new()
	get_root().add_child(root)

	var cam := Camera3D.new()
	var out_cam := Camera3D.new()
	var key_l := DirectionalLight3D.new()
	var fill_l := DirectionalLight3D.new()
	var rim_l := DirectionalLight3D.new()
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	root.add_child(cam)
	root.add_child(out_cam)
	root.add_child(key_l)
	root.add_child(fill_l)
	root.add_child(rim_l)
	root.add_child(we)

	var cam_rig = CameraRigScript.new()
	root.add_child(cam_rig)
	cam_rig.setup(cam, out_cam)
	cam_rig.apply_preset("face", 1.6)
	var cam_dict: Dictionary = cam_rig.to_dict()
	print("cam face preset: ", cam_dict)

	var light_rig = LightingRigScript.new()
	root.add_child(light_rig)
	light_rig.setup(key_l, fill_l, rim_l, we)
	light_rig.apply_preset("sunset")
	var light_dict: Dictionary = light_rig.to_dict()
	print("light sunset preset: ", light_dict["preset"], " key_energy=", light_dict["key_energy"])

	var bg_mgr = BackgroundManagerScript.new()
	root.add_child(bg_mgr)
	bg_mgr.setup(null, null, null, null, we, null, null, null, out_cam)
	bg_mgr.apply_background({"mode": "chroma_green"})
	var bg_dict: Dictionary = bg_mgr.bg_to_dict()
	print("bg mode: ", bg_dict["mode"])

	var hk_mgr = HotkeyManagerScript.new()
	root.add_child(hk_mgr)
	hk_mgr.setup(null)
	var hk_dict: Dictionary = hk_mgr.to_dict()

	var cfg := {
		"version": 1,
		"camera": cam_dict,
		"lighting": light_dict,
		"background": bg_dict,
		"hotkeys": hk_dict,
	}
	var cfg_path := ProjectSettings.globalize_path("res://../target/test_m4_config.json")
	var save_res: Dictionary = ConfigManagerScript.save_config(cfg, cfg_path)
	var load_res: Dictionary = ConfigManagerScript.load_config(cfg_path)
	var ok: bool = bool(save_res.get("ok", false)) and bool(load_res.get("ok", false))
	if ok:
		var loaded: Dictionary = load_res["config"]
		ok = (loaded["lighting"]["preset"] == "sunset" and loaded["background"]["mode"] == "chroma_green")

	root.free()
	print("TEST_M4_CORE_RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
