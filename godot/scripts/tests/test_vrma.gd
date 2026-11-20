extends SceneTree

const VrmLoaderScript := preload("res://scripts/vrm/vrm_loader.gd")
const VrmaLoaderScript := preload("res://scripts/vrm/vrma_loader.gd")
const ProceduralIdleScript := preload("res://scripts/core/procedural_idle.gd")

var _ran := false

func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run_tests()
	return true

func _run_tests() -> void:
	var root_node := Node3D.new()
	get_root().add_child(root_node)

	var vrm_path := ProjectSettings.globalize_path("res://../assets/samples/Seed-san.vrm")
	var res: Dictionary = VrmLoaderScript.load_vrm(vrm_path)
	if not res.get("ok", false):
		push_error("Failed to load Seed-san.vrm")
		quit(1)
		return

	var vrm = res["runtime"]
	root_node.add_child(vrm)
	vrm.manual_step_only = true

	var player = VrmaLoaderScript.VrmaPlayer.new()
	var idle = ProceduralIdleScript.new()
	vrm.animation_player = player
	vrm.procedural_idle = idle

	var anim_dir := ProjectSettings.globalize_path("res://../assets/animations")
	var dir := DirAccess.open(anim_dir)
	var files := PackedStringArray()
	if dir != null:
		dir.list_dir_begin()
		var fn := dir.get_next()
		while fn != "":
			if fn.ends_with(".vrma"):
				files.append(fn)
			fn = dir.get_next()
		files.sort()

	print("Found .vrma files: ", files.size())
	var ok := (files.size() == 12)
	for fn in files:
		var loaded: Dictionary = VrmaLoaderScript.load_vrma(anim_dir.path_join(fn))
		if not loaded.get("ok", false):
			push_error("Failed to load " + fn + ": " + str(loaded.get("error", "")))
			ok = false
			continue
		var clip = loaded["clip"]
		player.add_clip(clip.name, clip)
		player.play(clip.name, true, 1.0, 0.15)
		for _i in range(10):
			vrm.step(1.0 / 30.0)
			var head_xf: Transform3D = vrm.humanoid.get_bone_world_transform("head")
			if not head_xf.origin.is_finite():
				push_error("Non-finite transform in " + fn)
				ok = false
				break
		print("  verified ", fn, " dur=", snappedf(clip.duration, 0.01), " tracks=", clip.bone_tracks.size())

	# Test seek & pause determinism
	player.play("walk", true, 1.0, 0.0)
	player.paused = true
	player.seek(0.25)
	vrm.step(1.0 / 60.0)
	var leg_rot_a: Quaternion = vrm.humanoid.skeleton.get_bone_pose_rotation(vrm.humanoid.get_bone_idx("leftUpperLeg"))
	player.seek(0.25)
	vrm.step(1.0 / 60.0)
	var leg_rot_b: Quaternion = vrm.humanoid.skeleton.get_bone_pose_rotation(vrm.humanoid.get_bone_idx("leftUpperLeg"))
	if not leg_rot_a.is_equal_approx(leg_rot_b):
		push_error("Seek determinism check failed")
		ok = false

	vrm.free()
	root_node.free()
	print("TEST_VRMA_RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
