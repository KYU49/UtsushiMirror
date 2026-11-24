extends SceneTree

## VMC プロトコル双方向送受信・LAN バインド切替・自己ループ防止・カメラ/表情/ボーン変換・.umset フィルタの結合テスト。

var _m: Node
var _tx: VrmBridge
var _phase: int = 0
var _t: float = 0.0
var _ok: bool = true
var _cam_q_expected := Quaternion.IDENTITY


func _initialize() -> void:
	_m = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_m)
	_tx = VrmBridge.new()
	get_root().add_child(_tx)


func _check(name: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + name)
	_ok = _ok and cond


func _process(delta: float) -> bool:
	_t += delta
	match _phase:
		0:
			if _t > 0.25:
				_step0_config_and_reconfig()
				_phase = 1
				_t = 0.0
		1:
			# ループバック UDP 受信待機
			if _m.current_vrm != null and _m.current_vrm.vmc_bone_overrides.has("head") and _m.current_vrm.vmc_bone_overrides.has("leftThumbMetacarpal"):
				_step1_verify_received()
				_phase = 2
				_t = 0.0
			elif _t > 2.5:
				_check("ループバック UDP 受信タイムアウトせず受信", false)
				_finish()
				return true
		2:
			# VMC 送信 → _tx 側受信待機
			var rx_json := _tx.poll_vmc_frame()
			if rx_json != "":
				var parsed = JSON.parse_string(rx_json)
				if typeof(parsed) == TYPE_DICTIONARY and parsed.has("bones") and not parsed["bones"].is_empty():
					_step2_verify_sent(parsed)
					_finish()
					return true
			if _t > 2.5:
				_check("VMC 送信がループバックへ届く", false)
				_finish()
				return true
	return false


func _step0_config_and_reconfig() -> void:
	# 1) .umset ダイアログフィルタ確認
	var sw = _m.settings_window
	var imp_joined := "|".join(sw._dlg_import_cfg.filters)
	var exp_joined := "|".join(sw._dlg_export_cfg.filters)
	_check("読込ダイアログのフィルタに *.umset が含まれる", "*.umset" in imp_joined)
	_check("書出ダイアログのフィルタに *.umset が含まれる", "*.umset" in exp_joined)

	# 2) サンプル VRM 読み込み
	var lres: Dictionary = _m.load_vrm(ProjectSettings.globalize_path("res://../assets/samples/Seed-san.vrm"))
	_check("Seed-san.vrm を読み込める", bool(lres.get("ok", false)))

	# 3) LAN 切替と再バインド (再起動不要)
	var r_lan: Dictionary = _m.apply_vmc_settings({
		"recv_enabled": true,
		"recv_bind_lan": true,
		"recv_port": 39589,
		"recv_apply_root": true,
		"recv_apply_bones": true,
		"recv_apply_expressions": true,
		"recv_apply_camera": true,
	})
	var vmc_st: Dictionary = r_lan.get("vmc", {})
	var rx_st: Dictionary = vmc_st.get("receiver", {})
	_check("LAN 待受 (0.0.0.0:39589) を再起動なしで反映できる",
		bool(r_lan.get("ok", false)) and bool(rx_st.get("running", false)) and str(rx_st.get("bind", "")) == "0.0.0.0" and int(rx_st.get("port", 0)) == 39589)

	# 4) 自己ループ防止
	var r_loop: Dictionary = _m.apply_vmc_settings({
		"send_enabled": true,
		"send_host": "127.0.0.1",
		"send_port": 39589,
	})
	_check("同一ループバックポートへの自己ループ送信が防止される", not bool(r_loop.get("ok", true)) and not bool(_m.vmc_send_enabled))

	# 5) 127.0.0.1:39589 へ再バインドし、_tx から VMC フレームを UDP 送信
	_m.apply_vmc_settings({"recv_bind_lan": false, "recv_port": 39589})
	var tx_cfg_json := _tx.configure_vmc_sender(true, "127.0.0.1", 39589)
	var tx_cfg = JSON.parse_string(tx_cfg_json)
	_check("送信側 VrmBridge を 127.0.0.1:39589 へ設定できる", typeof(tx_cfg) == TYPE_DICTIONARY and bool(tx_cfg.get("ok", false)))

	var q_root := Quaternion(Vector3.UP, deg_to_rad(45.0)).normalized()
	var q_head := Quaternion.from_euler(Vector3(0.2, 0.3, 0.1)).normalized()
	var q_thumb := Quaternion(Vector3(0.0, 0.0, 1.0), deg_to_rad(-35.0)).normalized()
	var q_upchest := Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(15.0)).normalized()

	_cam_q_expected = (Quaternion(Vector3.UP, deg_to_rad(25.0)) * Quaternion(Vector3.RIGHT, deg_to_rad(-10.0))).normalized()
	var cq_u := (_cam_q_expected * Quaternion(Vector3.UP, PI)).normalized()

	var frame_payload := {
		"root": {
			"pos": [-0.25, 0.12, 0.35],
			"quat": [q_root.x, -q_root.y, -q_root.z, q_root.w],
		},
		"bones": {
			"Head": {"pos": [0.0, 0.0, 0.0], "quat": [q_head.x, -q_head.y, -q_head.z, q_head.w]},
			"LeftThumbProximal": {"pos": [0.0, 0.0, 0.0], "quat": [q_thumb.x, -q_thumb.y, -q_thumb.z, q_thumb.w]},
			"upperchest": {"pos": [0.0, 0.0, 0.0], "quat": [q_upchest.x, -q_upchest.y, -q_upchest.z, q_upchest.w]},
		},
		"blendshapes": {
			"Joy": 0.9,
			"A": 0.75,
			"Blink_L": 0.6,
		},
		"blend_apply": true,
		"camera": {
			"pos": [-0.4, 1.5, 2.5],
			"quat": [cq_u.x, -cq_u.y, -cq_u.z, cq_u.w],
			"fov_deg": 48.0,
		},
		"seq": 1,
	}
	var sent_ok := _tx.send_vmc_frame(JSON.stringify(frame_payload))
	_check("UDP VMC バンドル送信が成功する", sent_ok)


func _step1_verify_received() -> void:
	var vrm = _m.current_vrm
	vrm.step(0.016)
	var vmc_st: Dictionary = _m.get_vmc_state()
	var rx_st: Dictionary = vmc_st.get("receiver", {})
	_check("受信ステータスがアクティブになる", bool(rx_st.get("active", false)) and int(rx_st.get("packets_total", 0)) >= 1)

	_check("ルート移動・回転 (/VMC/Ext/Root/Pos) が反映される",
		vrm.has_vmc_root_rot and vrm.has_vmc_hips_offset and vrm.vmc_hips_offset.distance_to(Vector3(0.25, 0.12, 0.35)) < 0.01)

	var q_root_exp := Quaternion(Vector3.UP, deg_to_rad(45.0)).normalized()
	_check("ルート回転角度が一致する", absf(vrm.vmc_root_rot.dot(q_root_exp)) > 0.999)

	var q_head_exp := Quaternion.from_euler(Vector3(0.2, 0.3, 0.1)).normalized()
	_check("Head ボーン回転が一致する", absf((vrm.vmc_bone_overrides["head"] as Quaternion).dot(q_head_exp)) > 0.999)
	_check("大文字小文字ゆれ (upperchest -> upperChest) がマップされる", vrm.vmc_bone_overrides.has("upperChest"))

	_check("VRM 0.x 表情エイリアス (Joy/A/Blink_L -> happy/aa/blinkLeft) が反映される",
		absf(float(vrm.expressions.target_weights.get("happy", 0.0)) - 0.9) < 0.02
		and absf(float(vrm.expressions.target_weights.get("aa", 0.0)) - 0.75) < 0.02
		and absf(float(vrm.expressions.target_weights.get("blinkLeft", 0.0)) - 0.6) < 0.02)

	var cam_xf: Transform3D = _m.main_camera.global_transform
	var fwd_actual: Vector3 = (cam_xf.basis.orthonormalized() * Vector3(0.0, 0.0, -1.0)).normalized()
	var fwd_exp := (_cam_q_expected * Vector3(0.0, 0.0, -1.0)).normalized()
	_check("カメラ同期 (/VMC/Ext/Cam) の位置・向き・FOV が一致する",
		cam_xf.origin.distance_to(Vector3(0.4, 1.5, 2.5)) < 0.01
		and absf(_m.main_camera.fov - 48.0) < 0.1
		and fwd_actual.dot(fwd_exp) > 0.999)

	# 次のフェーズ: 別ポート (39590) へうつしみらー側から送信して折り返し受信を確認
	_tx.configure_vmc_sender(false, "127.0.0.1", 39589)
	var rx_setup = JSON.parse_string(_tx.reconfigure_osc_receiver(true, false, 39590))
	_check("折り返し受信用 _tx ポート 39590 が開く", typeof(rx_setup) == TYPE_DICTIONARY and bool(rx_setup.get("ok", false)))
	var tx_setup: Dictionary = _m.apply_vmc_settings({
		"send_enabled": true,
		"send_host": "127.0.0.1",
		"send_port": 39590,
		"send_fps": 60,
		"send_bones": true,
		"send_expressions": true,
		"send_camera": true,
		"send_vrm0_names": true,
	})
	_check("うつしみらー送信設定を有効化できる", bool(tx_setup.get("ok", false)))


func _step2_verify_sent(pkt: Dictionary) -> void:
	var bones: Dictionary = pkt.get("bones", {})
	var blends: Dictionary = pkt.get("blendshapes", {})
	_check("送信パケットに VMC ボーン (Head 等) が含まれる", bones.has("Head") and bones.has("LeftThumbProximal"))
	_check("送信パケットに VRM 0.x 変換済み表情名 (Joy/A) が含まれる",
		absf(float(blends.get("Joy", 0.0)) - 1.0) < 0.05 and absf(float(blends.get("A", 0.0)) - 0.75) < 0.05)
	_check("送信パケットにカメラ変換 (/VMC/Ext/Cam) が含まれる",
		typeof(pkt.get("camera", null)) == TYPE_DICTIONARY and absf(float(pkt["camera"].get("fov_deg", 0.0)) - 48.0) < 0.2)


func _finish() -> void:
	_m.apply_vmc_settings({"send_enabled": false, "recv_enabled": false})
	_tx.stop_servers()
	print("TEST_VMC_PROTOCOL=", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)
