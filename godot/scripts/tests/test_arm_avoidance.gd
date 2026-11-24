extends SceneTree

## 体・頭への腕めり込み回避 2-Bone IK と SpringBone 手コライダー連携のテスト。

const VrmLoaderScript := preload("res://scripts/vrm/vrm_loader.gd")
const VrmSpringBoneScript := preload("res://scripts/vrm/vrm_springbone.gd")

var _ran := false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var ok := _run_tests()
	print("TEST_ARM_AVOIDANCE=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
	return true


func _check(name: String, cond: bool) -> bool:
	print(("PASS " if cond else "FAIL ") + name)
	return cond


func _run_tests() -> bool:
	var ok := true
	var root_node := Node3D.new()
	get_root().add_child(root_node)

	var path := ProjectSettings.globalize_path("res://../assets/samples/Seed-san.vrm")
	var res: Dictionary = VrmLoaderScript.load_vrm(path)
	if not _check("Sample VRM loaded", bool(res.get("ok", false))):
		return false

	var vrm = res["runtime"]
	root_node.add_child(vrm)
	vrm.manual_step_only = true

	# 左手を胸の真ん中へ深くめり込ませる合成トラッキング姿勢 (+X左, +Y上, +Z前)
	var q_up_in := Quaternion(Vector3(1.0, 0.0, 0.0), Vector3(0.40, -0.80, 0.45).normalized()).normalized()
	var q_lo_world_chest := Quaternion(Vector3(1.0, 0.0, 0.0), Vector3(-0.90, 0.25, -0.35).normalized()).normalized()
	var q_lo_in := (q_up_in.inverse() * q_lo_world_chest).normalized()
	var q_hd := Quaternion(Vector3(0.1, 0.2, 0.0).normalized(), deg_to_rad(25.0)).normalized()

	vrm.vmc_bone_overrides = {
		"leftUpperArm": q_up_in,
		"leftLowerArm": q_lo_in,
		"leftHand": q_hd,
	}

	# 1) 回避オフ: 胸の近くにめり込む位置を記録
	vrm.avoid_body_enabled = false
	vrm.step(0.016)
	var chest_pos_off: Vector3 = vrm.humanoid.get_bone_world_transform("chest").origin
	var hand_pos_off: Vector3 = vrm.humanoid.get_bone_world_transform("leftHand").origin
	var dist_off: float = hand_pos_off.distance_to(chest_pos_off)
	var tip_bone := "leftMiddleDistal" if vrm.humanoid.has_bone("leftMiddleDistal") else "leftHand"
	var tip_dist_off: float = vrm.humanoid.get_bone_world_transform(tip_bone).origin.distance_to(chest_pos_off)

	# 2) 回避オン: 胸・体幹から前方/外側へ押し出される
	vrm.arm_avoidance.reset()
	vrm.avoid_body_enabled = true
	for _i in 20:
		vrm.step(0.016)
	var chest_pos_on: Vector3 = vrm.humanoid.get_bone_world_transform("chest").origin
	var hand_pos_on: Vector3 = vrm.humanoid.get_bone_world_transform("leftHand").origin
	var dist_on: float = hand_pos_on.distance_to(chest_pos_on)
	var tip_dist_on: float = vrm.humanoid.get_bone_world_transform(tip_bone).origin.distance_to(chest_pos_on)
	ok = _check("腕の胸めり込み回避で手首が胸から押し出される (off=%.3f -> on=%.3f)" % [dist_off, dist_on], dist_on > dist_off + 0.04) and ok
	ok = _check("指先 (%s) も胸から押し出される (off=%.3f -> on=%.3f)" % [tip_bone, tip_dist_off, tip_dist_on], tip_dist_on > tip_dist_off + 0.04) and ok
	ok = _check("回避後も前方 (+Z) 側に保たれる", hand_pos_on.z >= chest_pos_on.z + 0.05) and ok

	# 3) 頭部・横髪への腕差し込みでも発散・NaNにならず押し出される
	var q_up_head := Quaternion(Vector3(1.0, 0.0, 0.0), Vector3(0.70, 0.50, 0.45).normalized()).normalized()
	var q_lo_world_head := Quaternion(Vector3(1.0, 0.0, 0.0), Vector3(-0.92, 0.15, -0.35).normalized()).normalized()
	var q_lo_head := (q_up_head.inverse() * q_lo_world_head).normalized()
	vrm.avoid_body_enabled = false
	vrm.vmc_bone_overrides["leftUpperArm"] = q_up_head
	vrm.vmc_bone_overrides["leftLowerArm"] = q_lo_head
	vrm.step(0.016)
	var head_off: Vector3 = vrm.humanoid.get_bone_world_transform("head").origin
	var h_dist_off: float = vrm.humanoid.get_bone_world_transform("leftHand").origin.distance_to(head_off)

	vrm.arm_avoidance.reset()
	vrm.avoid_body_enabled = true
	for _i in 20:
		vrm.step(0.016)
	var head_on: Vector3 = vrm.humanoid.get_bone_world_transform("head").origin
	var h_hand_on: Vector3 = vrm.humanoid.get_bone_world_transform("leftHand").origin
	var h_dist_on: float = h_hand_on.distance_to(head_on)
	ok = _check("頭部付近へのめり込み回避で手首が押し出される (off=%.3f -> on=%.3f)" % [h_dist_off, h_dist_on], h_dist_on > h_dist_off + 0.03 and h_hand_on.is_finite()) and ok

	# 3b) 手首は前方に出ていて問題ないが二の腕(上腕)が胸へめり込む姿勢での弱い貫通抑制
	var q_up_ua_in := Quaternion(Vector3(1.0, 0.0, 0.0), Vector3(-0.60, -0.65, 0.46).normalized()).normalized()
	var q_lo_world_fwd := Quaternion(Vector3(1.0, 0.0, 0.0), Vector3(0.25, 0.10, 0.96).normalized()).normalized()
	var q_lo_ua_in := (q_up_ua_in.inverse() * q_lo_world_fwd).normalized()
	vrm.avoid_body_enabled = false
	vrm.vmc_bone_overrides = {
		"leftUpperArm": q_up_ua_in,
		"leftLowerArm": q_lo_ua_in,
		"leftHand": q_hd,
	}
	vrm.step(0.016)
	var sh_ua_off: Vector3 = vrm.humanoid.get_bone_world_transform("leftUpperArm").origin
	var el_ua_off: Vector3 = vrm.humanoid.get_bone_world_transform("leftLowerArm").origin
	var ua_mid_off: Vector3 = sh_ua_off.lerp(el_ua_off, 0.65)
	var bust_ref_off: Vector3 = vrm.humanoid.get_bone_world_transform("chest").origin + Vector3(0.0, 0.05, 0.06)
	var ua_dist_off: float = ua_mid_off.distance_to(bust_ref_off)

	vrm.arm_avoidance.reset()
	vrm.avoid_body_enabled = true
	for _i in 20:
		vrm.step(0.016)
	var sh_ua_on: Vector3 = vrm.humanoid.get_bone_world_transform("leftUpperArm").origin
	var el_ua_on: Vector3 = vrm.humanoid.get_bone_world_transform("leftLowerArm").origin
	var hand_ua_on: Vector3 = vrm.humanoid.get_bone_world_transform("leftHand").origin
	var ua_mid_on: Vector3 = sh_ua_on.lerp(el_ua_on, 0.65)
	var bust_ref_on: Vector3 = vrm.humanoid.get_bone_world_transform("chest").origin + Vector3(0.0, 0.05, 0.06)
	var ua_dist_on: float = ua_mid_on.distance_to(bust_ref_on)
	var ua_gain: float = ua_dist_on - ua_dist_off
	var wr_gain: float = dist_on - dist_off
	ok = _check("二の腕の胸めり込みが手首より弱く抑えられる (off=%.3f -> on=%.3f, ua_gain=%.3f < wr_gain=%.3f)" % [ua_dist_off, ua_dist_on, ua_gain, wr_gain], ua_gain > 0.015 and ua_gain < wr_gain and ua_mid_on.is_finite() and el_ua_on.is_finite() and hand_ua_on.is_finite()) and ok

	# 3c) 自然に腕を下ろした垂れ腕では不自然に外へ開かない
	var q_up_left_hang := Quaternion(Vector3(1.0, 0.0, 0.0), Vector3(0.25, -0.97, 0.0).normalized()).normalized()
	var q_up_right_hang := Quaternion(Vector3(-1.0, 0.0, 0.0), Vector3(-0.25, -0.97, 0.0).normalized()).normalized()
	vrm.avoid_body_enabled = false
	vrm.vmc_bone_overrides = {
		"leftUpperArm": q_up_left_hang,
		"leftLowerArm": Quaternion.IDENTITY,
		"rightUpperArm": q_up_right_hang,
		"rightLowerArm": Quaternion.IDENTITY,
	}
	vrm.step(0.016)
	var l_sh_hang: Vector3 = vrm.humanoid.get_bone_world_transform("leftUpperArm").origin
	var l_el_hang_off: Vector3 = vrm.humanoid.get_bone_world_transform("leftLowerArm").origin
	var r_sh_hang: Vector3 = vrm.humanoid.get_bone_world_transform("rightUpperArm").origin
	var r_el_hang_off: Vector3 = vrm.humanoid.get_bone_world_transform("rightLowerArm").origin

	vrm.arm_avoidance.reset()
	vrm.avoid_body_enabled = true
	for _i in 20:
		vrm.step(0.016)
	var l_el_hang_on: Vector3 = vrm.humanoid.get_bone_world_transform("leftLowerArm").origin
	var r_el_hang_on: Vector3 = vrm.humanoid.get_bone_world_transform("rightLowerArm").origin
	var l_el_delta: float = l_el_hang_on.distance_to(l_el_hang_off)
	var r_el_delta: float = r_el_hang_on.distance_to(r_el_hang_off)
	ok = _check("自然な垂れ腕では二の腕が外へ開かない (L=%.4f, R=%.4f)" % [l_el_delta, r_el_delta], l_el_hang_off.y < l_sh_hang.y and r_el_hang_off.y < r_sh_hang.y and l_el_delta < 0.015 and r_el_delta < 0.015) and ok

	# 以降のセクション用に状態を戻す
	vrm.arm_avoidance.reset()
	vrm.vmc_bone_overrides = {
		"leftUpperArm": q_up_in,
		"leftLowerArm": q_lo_in,
		"leftHand": q_hd,
	}

	# 4) SpringBone 手コライダーの生成と揺れものへの押し出し作用
	vrm.hand_spring_collide_enabled = true
	vrm.step(0.016)
	var cols: Array = vrm.arm_avoidance.build_hand_spring_colliders(vrm.humanoid)
	var cols_ok: bool = cols.size() >= 4
	for c in cols:
		if c == null or c.radius <= 0.03:
			cols_ok = false
	ok = _check("SpringBone 用の手・前腕コライダー 4 つが生成される", cols_ok and vrm.spring_bone.extra_colliders.size() >= 4) and ok

	if not vrm.spring_bone.springs.is_empty() and not vrm.spring_bone.springs[0].joints.is_empty():
		var target_chain = vrm.spring_bone.springs[0]
		for sc in vrm.spring_bone.springs:
			if str(sc.name).to_lower().contains("hair"):
				target_chain = sc
				break
		var js = target_chain.joints[0]
		var tail_test := Vector3(1.0, 1.0, 1.0)
		var sphere_col = VrmSpringBoneScript.ColliderDef.new()
		sphere_col.shape = "sphere"
		sphere_col.w_p0 = tail_test - Vector3(0.0, 0.0, 0.02)
		sphere_col.radius = 0.08
		var pushed: Vector3 = vrm.spring_bone._resolve_collider(sphere_col, tail_test, maxf(0.01, js.hit_radius))
		ok = _check("手コライダー球が SpringBone ジョイントを押せる", pushed.distance_to(sphere_col.w_p0) >= 0.08) and ok

		# 実モデルの髪 SpringBone チェーンに外部コライダーを当てて実際に揺れ動くかを検証
		vrm.step(0.016)
		var center_xf: Transform3D = vrm.spring_bone._get_center_transform(target_chain)
		var tail_world_before: Vector3 = center_xf * js.current_tail
		var tail_before_local: Vector3 = js.current_tail
		var fake_hand = VrmSpringBoneScript.ColliderDef.new()
		fake_hand.shape = "sphere"
		fake_hand.w_p0 = tail_world_before + Vector3(0.0, 0.0, 0.03)
		fake_hand.radius = 0.09
		vrm.hand_spring_collide_enabled = false
		vrm.spring_bone.extra_colliders = [fake_hand]
		vrm.spring_bone.update(0.016)
		var deflect: float = (js.current_tail - tail_before_local).length()
		vrm.spring_bone.extra_colliders.clear()
		vrm.hand_spring_collide_enabled = true
		ok = _check("実モデルの髪 SpringBone (%s) が手コライダーで実際に押し出される (変位=%.4f)" % [target_chain.name, deflect], deflect > 0.005) and ok

	# 5) VMC トラッキングが空のときは干渉せず extra_colliders も空になる
	vrm.vmc_bone_overrides.clear()
	vrm.direct_bone_overrides = {
		"leftUpperArm": q_up_in,
		"leftLowerArm": q_lo_in,
	}
	vrm.step(0.016)
	var hand_direct: Vector3 = vrm.humanoid.get_bone_world_transform("leftHand").origin
	ok = _check("非トラッキング時は腕回避や手コライダーが介入しない", hand_direct.distance_to(hand_pos_off) < 1e-4 and vrm.spring_bone.extra_colliders.is_empty()) and ok

	return ok
