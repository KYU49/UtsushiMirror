extends SceneTree
## トラッキング (VMC) が目の向きを送っているとき、カメラ目線などの自動の視線に上書きされないことを確かめる。
## 実行: VRMVIEWER_CONFIG=<一時ファイル> godot --path godot -s res://scripts/tests/test_tracked_eyes.gd
var _m: Node
var _f := 0
var _ok := true
var _q := Quaternion(Vector3.UP, deg_to_rad(20.0))


func _check(name: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + name)
	_ok = _ok and cond


func _initialize() -> void:
	_m = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_m)


func _eye_local(vrm) -> Quaternion:
	var h = vrm.humanoid
	return h.skeleton.get_bone_pose_rotation(h._bones["leftEye"].bone_idx)


func _process(_d: float) -> bool:
	_f += 1
	if _f == 10:
		_m.load_vrm(ProjectSettings.globalize_path("res://../assets/samples/VRM1_Constraint_Twist_Sample.vrm"))
	if _f == 40:
		var vrm = _m.current_vrm
		_check("model loaded", vrm != null and vrm.humanoid.has_bone("leftEye"))
		vrm.lookat.mode = "camera"
		vrm.vmc_bone_overrides["leftEye"] = _q
		vrm.vmc_bone_overrides["rightEye"] = _q
	if _f == 50:
		var vrm = _m.current_vrm
		var got := _eye_local(vrm)
		vrm.humanoid.set_normalized_bone_rotation("leftEye", _q)
		var want := _eye_local(vrm)
		_check("tracked eye wins over camera lookAt (bone)", got.angle_to(want) < 0.01)
		# 表情で目を動かすモデル: 目の向きを lookLeft などへ変換する
		vrm.lookat.lookat_type = "expression"
		var ex: Dictionary = vrm.lookat.apply_tracked_eyes(_q, _q)
		_check("expression type: look left", float(ex.get("lookLeft", 0.0)) > 0.0 and float(ex.get("lookRight", 1.0)) == 0.0)
		vrm.lookat.lookat_type = "bone"
		vrm.vmc_bone_overrides.clear()
		# 「カメラ目線」: 目の向きを送られても使わず、LookAt が「切」でもカメラを見る
		vrm.lookat.mode = "off"
		_m.camera_rig.apply_params({"yaw_deg": 40.0, "pitch_deg": 0.0})
		vrm.vmc_bone_overrides["leftEye"] = _q
		vrm.force_camera_gaze = true
		vrm.vmc_bone_overrides.erase("leftEye")
	if _f == 56:
		var vrm = _m.current_vrm
		var e := _eye_local(vrm)
		_check("カメラ目線: 横のカメラの方へ目が向く", e.angle_to(Quaternion.IDENTITY) > deg_to_rad(2.0) and e.angle_to(_q) > 0.01)
		_check("カメラ目線: LookAt の設定は変えない", vrm.lookat.mode == "off")
		vrm.force_camera_gaze = false
		_m.camera_rig.apply_params({"yaw_deg": 0.0})
		# 視線の選び方 → トラッカーへの「目を動かすか」
		_m.tracking.apply_settings({"gaze_mode": "camera"})
		_check("カメラ目線ではトラッカーは目を動かさない", _m.tracking.settings.gaze == false)
		_m.tracking.apply_settings({"gaze_mode": "track"})
		_check("視線を動かすではトラッカーが目を動かす", _m.tracking.settings.gaze == true)
		_m.tracking.apply_settings({"gaze": false})
		_check("以前の設定 (動かさない) は目線固定になる", _m.tracking.settings.gaze_mode == "fixed")
		_m.tracking.apply_settings({"gaze_mode": "track"})
	if _f == 60:
		print("TEST_TRACKED_EYES_RESULT=", "PASS" if _ok else "FAIL")
		return true
	return false
