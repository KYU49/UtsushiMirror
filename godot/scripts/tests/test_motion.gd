extends SceneTree
## 「しゃべる」「歩く」、プリセットのフォルダ、npz のモーションを確かめる。
## 実行: VRMVIEWER_CONFIG=<一時ファイル> VRMVIEWER_PRESETS_DIR=<一時フォルダ> godot --path godot -s res://scripts/tests/test_motion.gd
## NPZ_SAMPLE=<.npz のパス> を渡すと、プリセットのフォルダに入れて読み込めるかも確かめる。
var _m: Node
var _f := 0
var _ok := true
var _max_mouth := 0.0
var _walk_start := Vector3.ZERO
var _walk_seen_anim := ""


func _check(name: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + name)
	_ok = _ok and cond


func _initialize() -> void:
	_m = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_m)


func _mouth_sum() -> float:
	var w: Dictionary = _m.current_vrm.expressions.get_weights_snapshot()
	var s := 0.0
	for v in ["aa", "ih", "ou", "ee", "oh"]:
		s += float(w.get(v, 0.0))
	return s


func _process(_d: float) -> bool:
	_f += 1
	if _f == 5:
		_m.load_vrm(ProjectSettings.globalize_path("res://../assets/samples/Seed-san.vrm"))
	if _f == 30:
		_check("モデルを読み込めた", _m.current_vrm != null)
		_m.set_model_transform({"position": [0.0, 0.0, 0.0], "rotation_y_deg": 0.0, "scale": 1.0})
		_m.camera_rig.apply_params({"yaw_deg": 0.0})
		var r: Dictionary = _m.motion.start_talk({"text": "こんにちは、うつしみらーです。Hello!"})
		_check("しゃべる命令を受け付ける", r.get("ok", false) and float(r.get("duration_sec", 0.0)) > 1.0)
		print("talk ", r)
		_check("文も長さも無いときは断る", not _m.motion.start_talk({}).get("ok", true))
	if _f > 30 and _f < 400 and _m.motion.talking:
		_max_mouth = maxf(_max_mouth, _mouth_sum())
	if _f == 400:
		_check("しゃべっている間に口が開く", _max_mouth > 0.3)
		_check("しゃべり終わると止まる", not _m.motion.talking)
	if _f == 410:
		_check("しゃべり終わると口が閉じる", _mouth_sum() < 0.05)
		_walk_start = _m.model_root.position
		var r: Dictionary = _m.motion.start_walk({"direction": "right", "distance": 1.0, "speed": 1.0})
		print("walk ", r)
		_check("歩く命令を受け付ける", r.get("ok", false))
	if _f > 410 and _m.motion.walking and _walk_seen_anim == "":
		_walk_seen_anim = _m.vrma_player.current_name
	if _f == 700:
		var p: Vector3 = _m.model_root.position
		print("walked to ", p, " yaw=", rad_to_deg(_m.model_root.rotation.y), " anim=", _walk_seen_anim)
		_check("歩き終わっている", not _m.motion.walking)
		# キャラクターは +z を向いているので、キャラクターの右は -x
		_check("キャラクターの右へ 1m 進む", absf(p.x - (_walk_start.x - 1.0)) < 0.05 and absf(p.z - _walk_start.z) < 0.05)
		_check("歩くアニメーションを使う", _walk_seen_anim in ["Walk_Loop", "walk"])
		var cam: Vector3 = _m.camera_rig.get_camera_world_position()
		var want_yaw := atan2(cam.x - p.x, cam.z - p.z)
		_check("着いたらカメラの方を向く", absf(angle_difference(_m.model_root.rotation.y, want_yaw)) < deg_to_rad(3.0))
		_check("歩き終わると、アニメの水平移動の無視を戻す", not _m.vrma_player.strip_root_xz)
		# 画面から見た左へ (カメラは正面 +z から原点を見ているので、画面の左は -x)
		_walk_start = _m.model_root.position
		_m.motion.start_walk({"direction": "left", "relative_to": "screen", "distance": 0.5})
	if _f == 900:
		var p2: Vector3 = _m.model_root.position
		print("screen-left walk to ", p2)
		_check("画面の左へ 0.5m 進む", absf(p2.x - (_walk_start.x - 0.5)) < 0.05 or absf(p2.x - (_walk_start.x + 0.5)) < 0.05)
		var cam_right: Vector3 = _m.camera_rig.main_camera.global_transform.basis.x
		_check("画面の左 = カメラの右の反対", signf(p2.x - _walk_start.x) == -signf(cam_right.x))
		_m.reset_model_transform()
		# プリセットのフォルダ
		var adir: String = _m.presets_dir("animations")
		var sdir: String = _m.presets_dir("shaders")
		_check("プリセットのフォルダができる", DirAccess.dir_exists_absolute(adir) and DirAccess.dir_exists_absolute(sdir))
		var src := OS.get_environment("NPZ_SAMPLE")
		if src != "":
			DirAccess.copy_absolute(src, adir.path_join("npz_sample.npz"))
		DirAccess.copy_absolute(ProjectSettings.globalize_path("res://../assets/animations/sit.vrma"), adir.path_join("my_sit.vrma"))
		var n: int = _m.reload_animation_presets()
		_check("フォルダの .vrma が一覧に出る", _m.vrma_player.has_clip("my_sit"))
		if src != "":
			_check("フォルダの .npz が一覧に出る", _m.vrma_player.has_clip("npz_sample") and n == 2)
			_check("npz を再生できる", _m.play_animation_internal("npz_sample"))
		_m.apply_effects({"style": "anime"})
		_check("シェーダーをプリセットに保存できる", _m.save_shader_preset("テスト用").get("ok", false))
		var names: Array = _m.list_shader_presets().map(func(x): return x.name)
		_check("保存したプリセットが一覧に出る", "テスト用" in names)
		_m.apply_effects({"style": "none"})
		_check("プリセットを読み込める", _m.apply_shader_preset("テスト用").get("ok", false) and _m.post_effects.style == "anime")
		_check("名前が空なら保存しない", not _m.save_shader_preset("  ").get("ok", true))
	if _f == 920:
		# その場で 1 回転
		_m.play_animation_internal("idle", true, 1.0, 0.0)
		_m.set_model_transform({"position": [0.0, 0.0, 0.0], "rotation_y_deg": 30.0})
		var r: Dictionary = _m.motion.start_turn({"angle_deg": 360})
		_check("回る命令を受け付ける", r.get("ok", false) and float(r.get("duration_sec", 0.0)) > 0.5)
	if _f == 960:
		_check("回っている途中は向きが変わる", _m.motion.turning and absf(angle_difference(_m.model_root.rotation.y, deg_to_rad(30.0))) > deg_to_rad(20.0))
	if _f == 1000:
		_check("1 回転すると元の向きに戻る", not _m.motion.turning and absf(angle_difference(_m.model_root.rotation.y, deg_to_rad(30.0))) < deg_to_rad(0.5))
		_m.motion.start_turn({"to": "camera"})
	if _f == 1040:
		var cam: Vector3 = _m.camera_rig.get_camera_world_position()
		var p: Vector3 = _m.model_root.position
		_check("カメラの方へ回れる", absf(angle_difference(_m.model_root.rotation.y, atan2(cam.x - p.x, cam.z - p.z))) < deg_to_rad(1.0))
		# アニメーションを止めずにピースをなめらかに重ねる
		_m.apply_pose_preset("peace", 0.5, true)
	if _f == 1050:
		var w: float = float(_m.current_vrm.direct_bone_weights.get("rightUpperArm", 1.0))
		_check("ポーズが途中まで効いている", w > 0.0 and w < 1.0)
	if _f == 1090:
		_check("ピースになっている", _m.current_vrm.direct_bone_overrides.has("rightIndexProximal") and _m.current_vrm.direct_bone_weights.is_empty())
		_check("アニメーションは止まらない", _m.vrma_player.playing and _m.vrma_player.current_name == "idle")
		_m.set_bones_pose({"bones": {"head": {"euler_deg": [0, 0, 12]}}, "transition_sec": 0.3})
	if _f == 1096:
		var hq: Quaternion = _m.current_vrm.direct_bone_overrides["head"]
		var want := Quaternion.from_euler(Vector3(0, 0, deg_to_rad(12)))
		_check("首の傾きが途中で、なめらかに移っている", not hq.is_equal_approx(want))
	if _f == 1130:
		_check("首の傾きが行き先に着く", (_m.current_vrm.direct_bone_overrides["head"] as Quaternion).is_equal_approx(Quaternion.from_euler(Vector3(0, 0, deg_to_rad(12)))))
		_check("ほかの指定 (ピース) は残る", _m.current_vrm.direct_bone_overrides.has("rightIndexProximal"))
		_m.reset_bones_pose_smooth(0.4)
	if _f == 1180:
		_check("なめらかに外すと、指定が消える", _m.current_vrm.direct_bone_overrides.is_empty() and _m.current_vrm.direct_bone_weights.is_empty())
	if _f == 1190:
		print("TEST_MOTION_RESULT=", "PASS" if _ok else "FAIL")
		return true
	return false
