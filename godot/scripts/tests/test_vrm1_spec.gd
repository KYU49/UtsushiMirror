extends SceneTree

const VrmLoaderScript := preload("res://scripts/vrm/vrm_loader.gd")

var _ran := false

func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run_tests()
	return true

func _run_tests() -> void:
	var all_ok := true
	var root_node := Node3D.new()
	get_root().add_child(root_node)

	for rel in ["res://../assets/samples/Seed-san.vrm", "res://../assets/samples/VRM1_Constraint_Twist_Sample.vrm"]:
		var path := ProjectSettings.globalize_path(rel)
		print("=== Testing ", rel.get_file(), " ===")
		var res: Dictionary = VrmLoaderScript.load_vrm(path)
		if not res.get("ok", false):
			push_error("Load failed: " + str(res.get("error", "")))
			all_ok = false
			continue

		var vrm = res["runtime"]
		root_node.add_child(vrm)
		vrm.manual_step_only = true

		var info: Dictionary = vrm.get_model_info()
		print("  meta.name=", info["meta"].get("name", "?"), " human_bones=", info["human_bones"].size(), " constraints=", info["constraints"].size(), " springs=", info["spring_bone"].get("springs", 0))
		if info["human_bones"].size() < 50:
			push_error("Too few human bones mapped")
			all_ok = false

		# 1. Test Expressions & OverrideBlink
		vrm.expressions.set_weight("aa", 0.8, 0.0)
		vrm.expressions.set_weight("blink", 1.0, 0.0)
		vrm.step(0.016)
		var eff_res: Dictionary = vrm.expressions.update(0.016, {}, 0.0)
		var eff: Dictionary = eff_res["effective"]
		print("  aa effective=", eff.get("aa", 0.0), " blink effective=", eff.get("blink", 0.0))
		if eff.get("aa", 0.0) < 0.79:
			push_error("aa expression failed")
			all_ok = false

		if rel.contains("Seed-san"):
			# relaxed has overrideBlink=block, isBinary=true, textureTransformBinds
			vrm.expressions.set_weight("relaxed", 1.0, 0.0)
			vrm.step(0.016)
			var eff2: Dictionary = vrm.expressions.update(0.016, {}, 0.0)["effective"]
			print("  with relaxed(overrideBlink=block): blink effective=", eff2.get("blink", 0.0))
			if eff2.get("blink", 1.0) > 0.01:
				push_error("overrideBlink=block did not block blink!")
				all_ok = false

		vrm.expressions.reset_all(0.0)

		# 2. Test Humanoid Normalized Pose + NodeConstraints
		vrm.direct_bone_overrides["leftUpperArm"] = Quaternion.from_euler(Vector3(0.0, 0.4, -0.8))
		vrm.direct_bone_overrides["leftLowerArm"] = Quaternion.from_euler(Vector3(0.0, 0.7, 0.0))
		vrm.step(0.016)
		if info["constraints"].size() > 0:
			var c0: Dictionary = info["constraints"][0]
			print("  first constraint evaluated: ", c0)

		# 3. Test SpringBone physics with wind
		vrm.spring_bone.external_wind = Vector3(2.5, 0.0, 1.0)
		for _f in range(25):
			vrm.step(1.0 / 60.0)
		if vrm.spring_bone.springs.size() > 0:
			var j0 = vrm.spring_bone.springs[0].joints[0]
			print("  spring0 joint0 current_tail=", j0.current_tail)

		# 4. Test LookAt
		vrm.lookat.mode = "manual"
		vrm.lookat.manual_target = Vector3(1.5, 1.4, 2.0)
		vrm.step(0.016)
		print("  lookat type=", vrm.lookat.lookat_type, " yaw=", snappedf(vrm.lookat._last_yaw_deg, 0.1))

		# 5. Test FirstPerson toggle
		vrm.first_person.set_first_person_mode(true)
		var hidden_in_fp := 0
		for a in vrm.first_person.annotations:
			if not a["mesh_instance"].visible:
				hidden_in_fp += 1
		vrm.first_person.set_first_person_mode(false)
		print("  firstPerson hidden meshes in FP mode=", hidden_in_fp)

		vrm.free()

	root_node.free()
	# 感情の表情が overrideBlink="none" (VRoid の書き出し) でも、その強さの分だけまばたきを弱める (まぶたが下がりすぎない)
	var ex := VrmExpressions.new()
	ex.setup({"extensions": {"VRMC_vrm": {"expressions": {"preset": {
		"happy": {"overrideBlink": "none"}, "relaxed": {"overrideBlink": "block"}, "blink": {}, "aa": {}}}}}}, {}, [])
	ex.set_weights({"happy": 0.5, "blink": 1.0}, 0.0, true)
	var eff_h: float = float(ex.update(0.016)["effective"].get("blink", -1.0))
	print("  happy=0.5(overrideBlink=none) + blink=1: blink effective=", eff_h)
	if absf(eff_h - 0.5) > 0.001:
		push_error("happy (overrideBlink=none) did not attenuate blink")
		all_ok = false
	ex.set_weights({"happy": 0.3}, 0.0, true)
	var eff_a: float = float(ex.update(0.016, {}, 1.0)["effective"].get("blink", -1.0))
	if absf(eff_a - 0.7) > 0.001:
		push_error("auto blink was not attenuated by happy: %f" % eff_a)
		all_ok = false
	ex.set_weights({"relaxed": 0.4, "blink": 1.0}, 0.0, true)
	if float(ex.update(0.016)["effective"].get("blink", -1.0)) != 0.0:
		push_error("explicit overrideBlink=block was changed")
		all_ok = false
	ex.set_weights({"aa": 1.0, "blink": 1.0}, 0.0, true)
	if float(ex.update(0.016)["effective"].get("blink", -1.0)) != 1.0:
		push_error("non-emotion expression attenuated blink")
		all_ok = false

	print("TEST_VRM1_SPEC_RESULT=", "PASS" if all_ok else "FAIL")
	quit(0 if all_ok else 1)
