extends SceneTree
## 画面効果・Bloom・陰影・落ち影の見た目を画像に保存し、透過が保たれることを確かめる。
## 実行: VRMVIEWER_CONFIG=<一時ファイル> godot --path godot -s res://scripts/tests/test_effects.gd
## 画像: out/effects/*.png
var _m: Node
var _f := 0
var _ok := true
var _out := ""
var _jobs: Array = []
var _job_i := -1
var _wait := 0


func _check(name: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + name)
	_ok = _ok and cond


func _initialize() -> void:
	_m = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_m)
	_out = ProjectSettings.globalize_path("res://../out/effects").simplify_path()
	DirAccess.make_dir_recursive_absolute(_out)
	# [ファイル名, 画面効果, ライト]
	_jobs = [
		["00_none", {"style": "none"}, {}],
		["01_anime", {"style": "anime"}, {}],
		["02_drama", {"style": "drama"}, {}],
		["03_cinema", {"style": "cinema"}, {}],
		["04_oldfilm", {"style": "oldfilm"}, {}],
		["05_noir", {"style": "noir"}, {}],
		["06_vhs", {"style": "vhs"}, {}],
		["07_painterly", {"style": "painterly"}, {}],
		["10_bloom_off", {"style": "none"}, {"bloom_enabled": false}],
		["11_bloom_on", {"style": "none"}, {"bloom_enabled": true, "bloom_intensity": 1.0}],
		["20_shade_default", {"style": "none"}, {"bloom_enabled": false, "key_azimuth_deg": 70.0, "key_elevation_deg": 20.0, "fill_energy": 0.15}],
		["21_shade_soft", {"shade_toony": -0.8}, {}],
		["22_shade_wide_blue", {"shade_toony": 0.0, "shade_shift": -0.35, "shade_tint": "#9fb4ff"}, {}],
		["23_shade_light", {"shade_shift": 0.0, "shade_tint": "#ffffff", "shade_strength": 0.3}, {}],
		["30_cast_soft", {"shade_strength": 1.0}, {"shadow_softness": 3.0, "shadow_opacity": 0.6}],
		["24_shade_dark", {"shade_strength": 2.0}, {"shadow_softness": 0.0, "shadow_opacity": 1.0}],
		["31_cast_strong", {"shade_strength": 1.0}, {"shadow_opacity": 2.0}],
		["32_cast_normal", {"shade_strength": 1.0}, {"shadow_opacity": 1.0}],
		["34_sharp_shadow", {"shade_strength": 1.0}, LightingRig.SHARP_SHADOW],
		["35_shadow_defaults", {"shade_strength": 1.0}, LightingRig.SHADOW_DEFAULTS],
	]


func _process(_d: float) -> bool:
	_f += 1
	if _f == 5:
		_m.load_vrm(ProjectSettings.globalize_path("res://../assets/samples/Seed-san.vrm"))
		_m.bg_manager.apply_background({"mode": "solid", "color": "#3a4150"})
		_m.camera_rig.apply_preset("upper_body", 1.6)
	if _f < 40:
		return false
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			var job: Array = _jobs[_job_i]
			get_root().get_texture().get_image().save_png(_out.path_join(str(job[0]) + ".png"))
		return false
	_job_i += 1
	if _job_i < _jobs.size():
		var job: Array = _jobs[_job_i]
		if not (job[2] as Dictionary).is_empty():
			_m.lighting_rig.apply_params(job[2])
		_m.apply_effects(job[1])
		_wait = 6
		return false
	# 透過の確認: 出力ビューポートを透過にして、効果ありでも背景のアルファが 0 のまま
	if not _alpha_started:
		_alpha_started = true
		_m.lighting_rig.apply_params({"shadow_softness": 0.0, "shadow_opacity": 1.0})
		_m.apply_effects({"style": "none", "shade_strength": 1.0})
		_m.bg_manager.apply_output_viewport({"width": 640, "height": 360, "background_mode": "transparent"})
		_m.output_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_check_alpha.call_deferred()
	return _alpha_done


var _alpha_started := false
var _alpha_done := false


func _check_alpha() -> void:
	for i in 6:
		await process_frame
	var img0: Image = _m.output_viewport.get_texture().get_image()
	print("no-effect corner ", img0.get_pixel(3, 3))
	_m.apply_effects({"style": "anime"})
	for i in 6:
		await process_frame
	var img: Image = _m.output_viewport.get_texture().get_image()
	var corner := img.get_pixel(3, 3)
	var center := img.get_pixel(int(img.get_width() * 0.36), int(img.get_height() * 0.45))
	print("corner ", corner, " center ", center)
	_check("transparent corner stays transparent with effect", corner.a < 0.01)
	_check("model stays opaque with effect", center.a > 0.9)
	img.save_png(_out.path_join("40_output_alpha_anime.png"))
	_check("effect layer active", _m.post_effects.is_active())
	# アニメ風は、モデルの陰影も一緒に変え、別の画風に替えると陰影を元に戻す
	_check("アニメ風で陰影も変わる", is_equal_approx(float(_m.post_effects.shade.shade_strength), 1.56)
		and is_equal_approx(float(_m.post_effects.shade.shade_shift), -0.4))
	_m.apply_effects({"style": "drama"})
	_check("別の画風で陰影が戻る", is_equal_approx(float(_m.post_effects.shade.shade_strength), 1.0)
		and is_equal_approx(float(_m.post_effects.shade.shade_shift), 0.0))
	_m.apply_effects({"style": "none", "shade_strength": 1.6})
	_m.apply_effects({"style": "drama"})
	_check("自分で変えた陰影は、画風を替えても残る", is_equal_approx(float(_m.post_effects.shade.shade_strength), 1.6))
	_m.apply_effects({"style": "none", "shade_strength": 1.0})
	_m.apply_effects({"style": "anime"})
	var reg_path := OS.get_environment("APPDATA").path_join("UtsushiMirror/presets/shaders/アニメ風.umshader")
	if FileAccess.file_exists(reg_path):
		var reg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(reg_path)).effects
		var cur: Dictionary = _m.post_effects.to_dict()
		var same := true
		for k in reg.keys():
			if k in ["style"] or not cur.has(k):
				continue
			if typeof(reg[k]) == TYPE_STRING:
				same = same and str(reg[k]).to_lower() == str(cur[k]).to_lower()
			elif k != "grain_fps":
				same = same and absf(float(reg[k]) - float(cur[k])) < 0.0001
		_check("アニメ風が登録した値と同じ", same)
	# シェーダー設定の書き出し・読み込み
	var path := OS.get_temp_dir().path_join("vv_shader_io_test.json")
	_m.apply_effects({"style": "anime", "kuwahara": 1.5, "shade_strength": 1.6})
	_m.lighting_rig.apply_params({"shadow_opacity": 1.4})
	_check("書き出せる", bool(_m.export_effects(path).get("ok", false)))
	_m.apply_effects({"style": "none", "shade_strength": 1.0})
	_m.lighting_rig.apply_params({"shadow_opacity": 0.5})
	_check("読み込める", bool(_m.import_effects(path).get("ok", false)))
	_check("画面効果が戻る", _m.post_effects.style == "custom" or _m.post_effects.style == "anime")
	_check("筆の大きさ 1.5 が戻る", is_equal_approx(float(_m.post_effects.params.kuwahara), 1.5))
	_check("影の濃さが戻る", is_equal_approx(float(_m.post_effects.shade.shade_strength), 1.6))
	_check("落ち影の濃さが戻る", is_equal_approx(float(_m.lighting_rig.shadow_opacity), 1.4))
	_check("ほかのファイルは読まない", not bool(_m.import_effects(ProjectSettings.globalize_path("res://project.godot")).get("ok", true)))
	_m.lighting_rig.apply_params({"shadow_opacity": 1.0})
	# 背景を真っ黒・真っ白 (透過なし) にすると、メイン画面は不透明のその色になる
	for col in ["#000000", "#ffffff"]:
		_m.apply_effects({"style": "none"})
		_m.bg_manager.apply_background({"mode": "solid", "color": col})
		for i in 4:
			await process_frame
		var px := get_root().get_texture().get_image().get_pixel(3, 3)
		print("solid ", col, " corner ", px)
		_check("背景 %s は不透明" % col, px.a > 0.99 and not get_root().transparent_bg)
		_check("背景 %s の色" % col, absf(px.r - Color(col).r) < 0.02 and absf(px.b - Color(col).b) < 0.02)
	# くっきり影の組み合わせが読める
	_m.lighting_rig.apply_params(LightingRig.SHARP_SHADOW)
	_check("くっきり影で法線方向のずれが下がる", _m.lighting_rig.shadow_normal_bias < 1.0 and _m.lighting_rig.shadow_quality == "ultra")
	for i in 6:
		await process_frame
	get_root().get_texture().get_image().save_png(_out.path_join("33_sharp_shadow_main.png"))
	_m.lighting_rig.apply_params(LightingRig.SHADOW_DEFAULTS)
	_check("影を初期値に戻せる", is_equal_approx(_m.lighting_rig.shadow_normal_bias, 2.0))
	# 設定全体の書き出し・読み込み
	var spath := OS.get_temp_dir().path_join("vv_settings_io_test")
	_m.tracking.apply_settings({"smooth": 0.42})
	_m.lighting_rig.apply_params({"shadow_opacity": 1.3})
	_m.camera_rig.apply_params({"yaw_deg": 33.0, "distance": 3.3, "target": [0.2, 1.1, 0.0]})
	_m.set_model_transform({"position": [0.4, 0.0, -0.2], "rotation_y_deg": 20.0, "scale": 1.1})
	DisplayServer.window_set_size(Vector2i(900, 700))
	var sr: Dictionary = _m.export_settings(spath)
	_check("設定を書き出せる (.umset が付く)", bool(sr.get("ok", false)) and str(sr.get("path", "")).ends_with(".umset"))
	_m.tracking.apply_settings({"smooth": 0.85})
	_m.lighting_rig.apply_params({"shadow_opacity": 1.0})
	_m.camera_rig.apply_params({"yaw_deg": 0.0, "distance": 2.2, "target": [0.0, 0.95, 0.0]})
	_m.reset_model_transform()
	DisplayServer.window_set_size(Vector2i(800, 600))
	_check("設定を読み込める", bool(_m.import_settings(spath + ".umset").get("ok", false)))
	_check("トラッキングの設定が戻る", is_equal_approx(float(_m.tracking.settings.smooth), 0.42))
	_check("落ち影の濃さも戻る", is_equal_approx(float(_m.lighting_rig.shadow_opacity), 1.3))
	_check("カメラの位置が戻る", is_equal_approx(_m.camera_rig.yaw_deg, 33.0) and is_equal_approx(_m.camera_rig.distance, 3.3) and is_equal_approx(_m.camera_rig.target.x, 0.2))
	_check("キャラクターの位置・向き・大きさが戻る", is_equal_approx(_m.model_root.position.x, 0.4) and is_equal_approx(_m.model_root.rotation_degrees.y, 20.0) and is_equal_approx(_m.model_root.scale.x, 1.1))
	_check("ウィンドウの大きさが戻る", DisplayServer.window_get_size() == Vector2i(900, 700))
	# モデルを読み込み直しても (起動時と同じ流れ)、保存したカメラ位置が自動調整で上書きされない
	if _m.current_vrm != null:
		var d2 = JSON.parse_string(FileAccess.get_file_as_string(spath + ".umset"))
		_m._apply_config_dict(d2)
		_check("モデルを読み直してもカメラの位置が残る", is_equal_approx(_m.camera_rig.yaw_deg, 33.0) and is_equal_approx(_m.camera_rig.distance, 3.3))
	else:
		print("SKIP モデルが無いので読み直しの確認は省略")
	_m.camera_rig.apply_params({"yaw_deg": 0.0, "distance": 2.2, "target": [0.0, 0.95, 0.0]})
	_m.reset_model_transform()
	_check("シェーダーだけのファイルは設定として読まない", not bool(_m.import_settings(path).get("ok", true)))
	_m.tracking.apply_settings({"smooth": 0.85})
	_m.lighting_rig.apply_params({"shadow_opacity": 1.0})
	print("TEST_EFFECTS_RESULT=", "PASS" if _ok else "FAIL")
	_alpha_done = true
