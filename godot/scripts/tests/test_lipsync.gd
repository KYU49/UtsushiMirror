extends SceneTree
## リップシンク (音声・テキスト) と、シェーダーの読み込みで設定ファイル (.umset) を読むことを確かめる。
## 実行: godot --path godot -s res://scripts/tests/test_lipsync.gd
## 設定とプリセットのフォルダは、渡されなければ一時フォルダを使う (利用者のフォルダに書かない)。
## LIPSYNC_SAMPLE=<mp3 や mp4 のパス> を渡すと、そのファイルも解析できるか確かめる。
var _m: Node
var _f := 0
var _ok := true
var _tmp := ""
var _wav := ""
var _tone_max := 0.0
var _silence_max := 0.0
var _locked_seen := false
var _anim_name := ""


func _check(name: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + name)
	_ok = _ok and cond


func _initialize() -> void:
	_tmp = OS.get_temp_dir().path_join("utsushi_test_lipsync_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(_tmp.path_join("presets"))
	if OS.get_environment("VRMVIEWER_PRESETS_DIR") == "":
		OS.set_environment("VRMVIEWER_PRESETS_DIR", _tmp.path_join("presets"))
	if OS.get_environment("VRMVIEWER_CONFIG") == "":
		OS.set_environment("VRMVIEWER_CONFIG", _tmp.path_join("config.json"))
	_m = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_m)


## 「あ」らしい音 0.6 秒 → 無音 0.6 秒 → 「あ」0.6 秒 の wav を作る
func _make_wav(path: String) -> void:
	var sr := 22050
	var data := PackedByteArray()
	for part in [1, 0, 1]:
		for i in range(int(0.6 * sr)):
			var v := 0.0
			if part == 1:
				for h in range(1, 20):
					var f := 150.0 * h
					var g := exp(-pow((f - 750.0) / 90.0, 2)) + 0.6 * exp(-pow((f - 1250.0) / 110.0, 2)) + 0.02
					v += g * sin(TAU * f * i / sr)
				v *= 0.25
			var s := int(clampf(v, -1.0, 1.0) * 32767.0)
			data.append(s & 0xff)
			data.append((s >> 8) & 0xff)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = sr
	w.stereo = false
	w.data = data
	w.save_to_wav(path)


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
		_wav = _tmp.path_join("tone.wav")
		_make_wav(_wav)
		var a: Dictionary = _m.bridge.analyze_lipsync(_wav)
		_check("wav を解析できる", a.get("ok", false) and absf(float(a.get("duration", 0.0)) - 1.8) < 0.05)
		_check("無いファイルは断る", not _m.bridge.analyze_lipsync(_tmp.path_join("none.mp3")).get("ok", true))
		var sample := OS.get_environment("LIPSYNC_SAMPLE")
		if sample != "":
			var s: Dictionary = _m.bridge.analyze_lipsync(sample)
			print("sample ", sample.get_file(), " ok=", s.get("ok"), " dur=", s.get("duration"), " err=", s.get("error", ""))
			_check("渡されたファイル (%s) を解析できる" % sample.get_extension(), s.get("ok", false))
		# 選択: 既定は「音声から」。テキストの命令は断る
		_check("口の動きの既定は「音声から」", _m.lipsync_mode == "audio")
		_check("音声からのときは、テキストの命令を断る", not _m.start_text_talk({"text": "こんにちは"}).get("ok", true))
		_m.play_animation_internal("Idle_Loop", true, 1.0, 0.0)
		_anim_name = _m.vrma_player.current_name
		var r: Dictionary = _m.start_lipsync({"path": _wav})
		print("lipsync ", r)
		_check("音声ファイルで始められる", r.get("ok", false))
		# 口以外の表情は、リップシンクの間も効く
		_m.current_vrm.expressions.set_weights({"blink": 1.0}, 0.0, false)
	if _f > 30 and _m.lip_sync.active:
		var t: float = _m.lip_sync._t
		if _m.current_vrm.expressions.mouth_locked:
			_locked_seen = true
		if t > 0.15 and t < 0.45:
			_tone_max = maxf(_tone_max, _mouth_sum())
		if t > 0.85 and t < 1.05:
			_silence_max = maxf(_silence_max, _mouth_sum())
	if _f == 60:
		var w: Dictionary = _m.current_vrm.expressions.get_weights_snapshot()
		_check("口以外の表情 (まばたき) は効いたまま", float(w.get("blink", 0.0)) > 0.9)
		_m.current_vrm.expressions.set_weights({"blink": 0.0}, 0.0, false)
	if _f == 260:
		print("tone %.2f / silence %.2f" % [_tone_max, _silence_max])
		_check("音の間は口が開く", _tone_max > 0.4)
		_check("無音では口が閉じる", _silence_max < 0.05)
		_check("リップシンクの間は口を固定する (トラッキング・アニメの口を使わない)", _locked_seen)
		_check("終わると止まる", not _m.lip_sync.active)
	if _f == 270:
		_check("終わると口が閉じる", _mouth_sum() < 0.05)
		_check("終わると口の固定を戻す", not _m.current_vrm.expressions.mouth_locked)
		_check("アニメーションは止まらない", _m.vrma_player.playing and _m.vrma_player.current_name == _anim_name)
		# テキストから
		_check("選択を「テキストから」にできる", _m.set_lipsync_mode("text").get("ok", false))
		_check("テキストからのときは、音声の命令を断る", not _m.start_lipsync({"path": _wav}).get("ok", true))
		_check("テキストからのときは、しゃべる命令を受け付ける", _m.start_text_talk({"text": "あいうえお"}).get("ok", false))
	if _f == 290:
		_check("しゃべっている間も口を固定する", _m.current_vrm.expressions.mouth_locked)
		_m.set_lipsync_mode("off")
		_check("「なし」に切り替えると、しゃべるのを止める", not _m.motion.talking)
		_check("「なし」のときは、どちらの命令も断る", not _m.start_lipsync({"path": _wav}).get("ok", true) and not _m.start_text_talk({"text": "あ"}).get("ok", true))
		_check("選択は設定に保存される", str(_m.build_config_dict().get("lipsync", {}).get("mode", "")) == "off")
		_m.set_lipsync_mode("audio")
		_check("知らない選択は断る", not _m.set_lipsync_mode("xyz").get("ok", true))
		# シェーダーの読み込みで設定ファイル (.umset) を読むと、シェーダーの部分だけを当てる
		_m.apply_effects({"style": "anime"})
		var umset := _tmp.path_join("all.umset")
		_check("設定ファイルを書き出せる", _m.export_settings(umset).get("ok", false))
		_m.apply_effects({"style": "none"})
		var yaw_before: float = float(_m.camera_rig.to_dict().get("yaw_deg", 0.0))
		_m.camera_rig.apply_params({"yaw_deg": yaw_before + 33.0})
		_check("シェーダーの読み込みで .umset を読める", _m.import_effects(umset).get("ok", false))
		_check("設定ファイルのシェーダーの部分が当たる", _m.post_effects.style == "anime")
		_check("設定ファイルのシェーダー以外 (カメラ) は当てない", absf(float(_m.camera_rig.to_dict().get("yaw_deg", 0.0)) - (yaw_before + 33.0)) < 0.01)
		var bad := _tmp.path_join("bad.umset")
		var fbad := FileAccess.open(bad, FileAccess.WRITE)
		fbad.store_string("{\"kind\": \"other\"}")
		fbad.close()
		_check("うつしみらーのファイルでなければ断る", not _m.import_effects(bad).get("ok", true))
	if _f == 300:
		print("TEST_LIPSYNC_RESULT=", "PASS" if _ok else "FAIL")
		return true
	return false
