extends Node3D

## Master coordinator connecting VrmBridge (WS/OSC/Platform), VRM 1.0 runtime,
## CameraRig, LightingRig, BackgroundManager, HotkeyManager, CaptureManager,
## ConfigManager, and the separate SettingsWindow.

signal state_changed
signal model_loaded(info: Dictionary)

const VrmLoaderScript := preload("res://scripts/vrm/vrm_loader.gd")
const VrmaLoaderScript := preload("res://scripts/vrm/vrma_loader.gd")
const AnimCategoryScript := preload("res://scripts/core/anim_category.gd")
const NpzMotionLoaderScript := preload("res://scripts/vrm/npz_motion_loader.gd")
const MotionDirectorScript := preload("res://scripts/core/motion_director.gd")
const LipSyncScript := preload("res://scripts/core/lip_sync.gd")
const VrmExpressionsScript := preload("res://scripts/vrm/vrm_expressions.gd")
const ProceduralIdleScript := preload("res://scripts/core/procedural_idle.gd")
const TrackingManagerScript := preload("res://scripts/core/tracking_manager.gd")
const PostEffectsScript := preload("res://scripts/core/post_effects.gd")
const ConfigManagerScript := preload("res://scripts/core/config_manager.gd")
const UiThemeScript := preload("res://scripts/ui/ui_theme.gd")

@onready var bridge: VrmBridge = $VrmBridge
@onready var main_bg_layer: CanvasLayer = $MainBgLayer
@onready var main_bg_rect: ColorRect = $MainBgLayer/MainBgRect
@onready var main_bg_image: TextureRect = $MainBgLayer/MainBgImage
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var key_light: DirectionalLight3D = $KeyLight
@onready var fill_light: DirectionalLight3D = $FillLight
@onready var rim_light: DirectionalLight3D = $RimLight
@onready var main_camera: Camera3D = $MainCamera
@onready var model_root: Node3D = $ModelRoot

@onready var camera_rig = $CameraRig
@onready var lighting_rig = $LightingRig
@onready var bg_manager = $BackgroundManager
@onready var hotkey_manager = $HotkeyManager
@onready var capture_manager = $CaptureManager

@onready var output_viewport: SubViewport = $OutputViewport
@onready var output_bg_rect: ColorRect = $OutputViewport/OutputBgLayer/OutputBgRect
@onready var output_bg_image: TextureRect = $OutputViewport/OutputBgLayer/OutputBgImage
@onready var output_camera: Camera3D = $OutputViewport/OutputCamera
@onready var settings_window: Window = $SettingsWindow

var current_vrm = null
var vrma_player
## 外部からの「しゃべる」「歩く」
var motion
var lip_sync
## 口の動きをどこから作るか: "off" (なし) / "audio" (音声から) / "text" (テキストから)
var lipsync_mode: String = "audio"
const LIPSYNC_MODES := ["off", "audio", "text"]
const LIPSYNC_MODE_NAMES := {"off": "なし", "audio": "音声から", "text": "テキストから"}
var procedural_idle
var recent_vrm_paths: Array[String] = []
## 書き出した・読み込んだ設定ファイル (.umset) の場所。新しい順。
var recent_settings_paths: Array[String] = []
const RECENT_SETTINGS_MAX := 10
var ws_port: int = 19100
var osc_port: int = 39539
var _last_animation: String = "for-test_a-pose"
var _last_lookat_mode: String = "camera"
var _last_lookat_manual_target: Vector3 = Vector3(0.0, 1.4, 2.0)
var _last_first_person: bool = false
var _shutting_down: bool = false
var tracking = TrackingManagerScript.new()
var _manual_expr_overrides: Dictionary = {} # ename -> true (UI/hotkey で固定中の表情)

const VMC_AUTO_EMOTION_KEYS := {"happy": true, "angry": true, "surprised": true, "sad": true, "relaxed": true}
var post_effects = PostEffectsScript.new()
var _last_vmc_msec: int = 0
var _spring_enabled: bool = true
var _spring_gravity_scale: float = 1.0
var _spring_stiffness_scale: float = 1.0
var _direct_bone_euler_deg: Dictionary = {}
var _cfg_settings_visible: bool = true

var _overlay_layer: CanvasLayer = null
var _toast_layer: CanvasLayer = null
var _overlay_error_lbl: Label = null
var _context_menu: PopupMenu = null
var _ctx_cam_menu: PopupMenu = null
var _ctx_anim_menu: PopupMenu = null
var _ctx_anim_names: Array[String] = []  # 右クリックの動きの小メニューの id → 名前
var _ctx_bg_menu: PopupMenu = null
var _main_dialog_vrm: FileDialog = null
var _main_dialog_vrma: FileDialog = null
var _main_dialog_bg_img: FileDialog = null

const VMC_EXPR_ALIASES := {
	"Joy": "happy",
	"Sorrow": "sad",
	"Fun": "relaxed",
	"Angry": "angry",
	"Surprised": "surprised",
	"Neutral": "neutral",
	"A": "aa",
	"I": "ih",
	"U": "ou",
	"E": "ee",
	"O": "oh",
	"Blink": "blink",
	"Blink_L": "blinkLeft",
	"Blink_R": "blinkRight",
}


func _ready() -> void:
	if output_viewport != null and get_viewport() != null:
		output_viewport.world_3d = get_viewport().world_3d

	vrma_player = VrmaLoaderScript.VrmaPlayer.new()
	motion = MotionDirectorScript.new(self)
	lip_sync = LipSyncScript.new(self)
	procedural_idle = ProceduralIdleScript.new()
	_preload_bundled_animations()
	reload_animation_presets()

	camera_rig.setup(main_camera, output_camera)
	lighting_rig.setup(key_light, fill_light, rim_light, world_env)
	post_effects.attach(self, output_viewport)
	bg_manager.setup(
		bridge,
		main_bg_layer,
		main_bg_rect,
		main_bg_image,
		world_env,
		output_viewport,
		output_bg_rect,
		output_bg_image,
		output_camera
	)
	hotkey_manager.setup(bridge)
	capture_manager.setup(bridge, output_viewport, bg_manager, camera_rig, lighting_rig)

	hotkey_manager.hotkey_triggered.connect(_on_hotkey_action)
	camera_rig.camera_changed.connect(_emit_state_changed)
	camera_rig.right_clicked.connect(_on_main_right_clicked)
	lighting_rig.lighting_changed.connect(_on_lighting_changed)
	bg_manager.background_changed.connect(_emit_state_changed)
	bg_manager.window_changed.connect(_emit_state_changed)
	bg_manager.background_changed.connect(post_effects.refresh_transparency)
	bg_manager.window_changed.connect(post_effects.refresh_transparency)
	capture_manager.capture_state_changed.connect(_emit_state_changed)

	_build_main_file_dialogs()
	_build_main_overlay()
	_build_context_menu()

	# Load saved config before starting servers so ports/settings apply cleanly
	var cfg_res: Dictionary = ConfigManagerScript.load_config()
	if cfg_res.get("ok", false):
		_apply_config_dict(cfg_res["config"])

	var env_ws := OS.get_environment("VRMVIEWER_WS_PORT")
	if env_ws != "" and env_ws.is_valid_int():
		ws_port = int(env_ws)
	var env_osc := OS.get_environment("VRMVIEWER_OSC_PORT")
	if env_osc != "" and env_osc.is_valid_int():
		osc_port = int(env_osc)

	if bridge != null:
		var ok := bridge.start_servers(ws_port, osc_port)
		print("AppController ready, bridge servers=", ok)

	if settings_window != null and settings_window.has_method("bind_controller"):
		settings_window.bind_controller(self)
		settings_window.files_dropped.connect(_on_files_dropped)
		if OS.get_environment("VRMVIEWER_NO_SETTINGS") == "1" or DisplayServer.get_name() == "headless":
			settings_window.visible = false
		else:
			call_deferred("_startup_show_settings")

	if get_window() != null:
		get_window().files_dropped.connect(_on_files_dropped)

	_update_overlay_visibility()
	_emit_state_changed()
	_load_initial_cmdline_model()
	_build_tray_icon()
	call_deferred("_ensure_operable_window")


func _load_initial_cmdline_model() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	var skip_next: bool = false
	for raw_arg in args:
		var arg: String = str(raw_arg)
		if skip_next:
			skip_next = false
			continue
		if arg in ["--path", "--script", "-s"]:
			skip_next = true
			continue
		if arg.begins_with("-"):
			continue
		if arg.to_lower().ends_with(".vrm"):
			var resolved: String = _resolve_input_path(arg)
			if FileAccess.file_exists(resolved):
				call_deferred("load_vrm", resolved)
				break


func _on_files_dropped(files: PackedStringArray) -> void:
	for f in files:
		var path: String = str(f)
		var lower: String = path.to_lower()
		if lower.ends_with(".vrm"):
			load_vrm(path)
		elif lower.ends_with(".vrma") or lower.ends_with(".npz"):
			load_vrma_file(path, "", true)
		elif LipSyncScript.is_media_file(path):
			var r: Dictionary = start_lipsync({"path": path})
			if settings_window != null:
				if r.get("ok", false):
					settings_window.show_snackbar("音声に口を合わせています: %s (%.1f 秒)" % [path.get_file(), float(r.get("duration_sec", 0.0))])
				else:
					settings_window.show_snackbar("リップシンクできません: " + str(r.get("error", "")))


# ---------------------------------------------------------------- リップシンク
## 口の動きの元を選ぶ。選び直したら、動いている方を止めて口を閉じる
func set_lipsync_mode(mode: String) -> Dictionary:
	if not mode in LIPSYNC_MODES:
		return {"ok": false, "error": "mode は off / audio / text のどれかです"}
	if mode != lipsync_mode:
		lip_sync.stop()
		motion.stop_talk()
		lipsync_mode = mode
		state_changed.emit()
	return {"ok": true, "mode": lipsync_mode}


func _lipsync_mode_error(want: String) -> Dictionary:
	return {"ok": false, "error": "口の動きが「%s」になっています。「%s」に切り替えると使えます (設定のトラッキング → リップシンク、または vrm_set_lipsync_mode で mode=%s)" % [
		LIPSYNC_MODE_NAMES[lipsync_mode], LIPSYNC_MODE_NAMES[want], want]}


## 音声・動画ファイルに口を合わせる (口の動きが「音声から」のときだけ)
func start_lipsync(params: Dictionary) -> Dictionary:
	if lipsync_mode != "audio":
		return _lipsync_mode_error("audio")
	return lip_sync.start(params)


## 文から口を動かす (口の動きが「テキストから」のときだけ)
func start_text_talk(params: Dictionary) -> Dictionary:
	if lipsync_mode != "text":
		return _lipsync_mode_error("text")
	return motion.start_talk(params)


func lipsync_state() -> Dictionary:
	var d: Dictionary = lip_sync.state() if lip_sync != null else {}
	d["mode"] = lipsync_mode
	d["talking"] = motion.talking if motion != null else false
	d["remaining_sec"] = snappedf(lip_sync.remaining_sec() if lip_sync != null and lip_sync.active else (motion.state().get("talk_remaining_sec", 0.0) if motion != null else 0.0), 0.01)
	return d


func _exit_tree() -> void:
	tracking.stop(true)
	tracking.stop_install()
	if capture_manager != null and capture_manager.recording_active:
		capture_manager.stop_recording()
	if not _shutting_down:
		save_config()


func _process(delta: float) -> void:
	if bridge != null:
		_poll_rpc()
		_poll_vmc()
		hotkey_manager.poll_global()
	tracking.poll()

	if current_vrm != null:
		current_vrm.lookat_world_target = camera_rig.get_camera_world_position()
	motion.process(delta)
	lip_sync.process(delta)
	if current_vrm != null and current_vrm.expressions != null:
		current_vrm.expressions.mouth_locked = lip_sync.active or motion.talking

	capture_manager.process_frame(delta)


func _unhandled_input(event: InputEvent) -> void:
	if hotkey_manager.handle_key_event(event):
		get_viewport().set_input_as_handled()
		return
	if camera_rig.handle_input(event):
		get_viewport().set_input_as_handled()


func _make_clip_loader(path: String, clip_name: String) -> Callable:
	return func():
		var loaded: Dictionary = _load_motion_clip(path, clip_name)
		if loaded.get("ok", false):
			return loaded["clip"]
		push_warning("アニメーションを読めません: %s (%s)" % [path, loaded.get("error", "")])
		return null


func _preload_bundled_animations() -> void:
	var anim_dir: String = ConfigManagerScript.get_app_root_dir().path_join("assets/animations")
	if not DirAccess.dir_exists_absolute(anim_dir):
		push_warning("Bundled animations directory not found: " + anim_dir)
		return
	# 直下と、1 階層下のフォルダ (例: quaternius/) を登録だけしておく (再生時に遅延読み込み)
	var dirs: Array[String] = [anim_dir]
	for sub in DirAccess.get_directories_at(anim_dir):
		dirs.append(anim_dir.path_join(sub))
	for d in dirs:
		for fn in DirAccess.get_files_at(d):
			if fn.ends_with(".vrma"):
				var clip_name: String = fn.get_basename()
				vrma_player.register_lazy_clip(clip_name, _make_clip_loader(d.path_join(fn), clip_name))
	print("Registered %d bundled animations from %s" % [vrma_player.get_clip_names().size(), anim_dir])


# ---------------------------------------------------------------------------
# プリセットのフォルダ (ここに入れた .vrma / .npz / .umshader が一覧に出る)
# ---------------------------------------------------------------------------

## kind: "animations" | "shaders"。無ければ作る。
## 既定は %APPDATA%/UtsushiMirror/presets/<kind> (アプリを更新しても消えない)。VRMVIEWER_PRESETS_DIR で変えられる。
func presets_dir(kind: String) -> String:
	var base := OS.get_environment("VRMVIEWER_PRESETS_DIR")
	if base == "":
		base = ProjectSettings.globalize_path("user://presets")
	var d := base.path_join(kind)
	if not DirAccess.dir_exists_absolute(d):
		DirAccess.make_dir_recursive_absolute(d)
	return d


func open_presets_folder(kind: String) -> void:
	OS.shell_open(presets_dir(kind))


var _preset_clip_names: Array[String] = []


## プリセットのフォルダのアニメーション (.vrma / .npz) を読み直す。登録した数を返す。
func reload_animation_presets() -> int:
	for nm in _preset_clip_names:
		if vrma_player.current_name != nm:
			vrma_player.erase_clip(nm)
	_preset_clip_names.clear()
	var d := presets_dir("animations")
	var files := Array(DirAccess.get_files_at(d))
	files.sort()
	for fn in files:
		var low := str(fn).to_lower()
		if not (low.ends_with(".vrma") or low.ends_with(".npz")):
			continue
		var clip_name: String = str(fn).get_basename()
		vrma_player.register_lazy_clip(clip_name, _make_clip_loader(d.path_join(fn), clip_name))
		_preset_clip_names.append(clip_name)
	_emit_state_changed()
	return _preset_clip_names.size()


## プリセットのフォルダにあるシェーダー設定の一覧 [{name, path}]
func list_shader_presets() -> Array:
	var out := []
	var d := presets_dir("shaders")
	var files := Array(DirAccess.get_files_at(d))
	files.sort()
	for fn in files:
		var low := str(fn).to_lower()
		if low.ends_with(".umshader") or low.ends_with(".json"):
			out.append({"name": str(fn).get_basename(), "path": d.path_join(fn)})
	return out


## 今のシェーダー設定を、プリセットのフォルダに「名前.umshader」で保存する
func save_shader_preset(preset_name: String) -> Dictionary:
	var nm := preset_name.strip_edges().validate_filename()
	if nm == "":
		return {"ok": false, "error": "名前を入れてください"}
	return export_effects(presets_dir("shaders").path_join(nm + ".umshader"))


func apply_shader_preset(preset_name: String) -> Dictionary:
	for p in list_shader_presets():
		if p.name == preset_name:
			return import_effects(p.path)
	return {"ok": false, "error": "プリセットがありません: " + preset_name}


func _poll_rpc() -> void:
	var reqs: PackedStringArray = bridge.poll_rpc_requests()
	for line in reqs:
		var parsed = JSON.parse_string(line)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var client_id: int = int(parsed.get("client_id", 0))
		var id_json: String = JSON.stringify(parsed.get("id", null))
		var method: String = str(parsed.get("method", ""))
		var params: Dictionary = parsed.get("params", {}) if typeof(parsed.get("params", {})) == TYPE_DICTIONARY else {}
		_dispatch_rpc(client_id, id_json, method, params)


func _dispatch_rpc(client_id: int, id_json: String, method: String, params: Dictionary) -> void:
	match method:
		"ping":
			_reply_ok(client_id, id_json, {"pong": true, "ws_port": ws_port, "osc_port": osc_port})
		"talk":
			var tres: Dictionary = start_text_talk(params)
			if tres.get("ok", false):
				_reply_ok(client_id, id_json, tres)
			else:
				_reply_err(client_id, id_json, -32602, str(tres.get("error", "talk failed")))
		"stop_talk":
			motion.stop_talk()
			_reply_ok(client_id, id_json, motion.state())
		"walk":
			var wres: Dictionary = motion.start_walk(params)
			if wres.get("ok", false):
				_reply_ok(client_id, id_json, wres)
			else:
				_reply_err(client_id, id_json, -32602, str(wres.get("error", "walk failed")))
		"stop_walk":
			motion.stop_walk()
			_reply_ok(client_id, id_json, motion.state())
		"turn":
			var tres2: Dictionary = motion.start_turn(params)
			if tres2.get("ok", false):
				_reply_ok(client_id, id_json, tres2)
			else:
				_reply_err(client_id, id_json, -32602, str(tres2.get("error", "turn failed")))
		"set_model_transform":
			set_model_transform(params)
			_reply_ok(client_id, id_json, get_model_transform_dict())
		"get_motion_state":
			_reply_ok(client_id, id_json, motion.state())
		"lipsync":
			var lres: Dictionary = start_lipsync(params)
			if lres.get("ok", false):
				_reply_ok(client_id, id_json, lres)
			else:
				_reply_err(client_id, id_json, -32602, str(lres.get("error", "lipsync failed")))
		"stop_lipsync":
			lip_sync.stop()
			_reply_ok(client_id, id_json, lip_sync.state())
		"set_lipsync_mode":
			var mres: Dictionary = set_lipsync_mode(str(params.get("mode", "")))
			if mres.get("ok", false):
				_reply_ok(client_id, id_json, mres)
			else:
				_reply_err(client_id, id_json, -32602, str(mres.get("error", "")))
		"reload_presets":
			_reply_ok(client_id, id_json, {"animations": reload_animation_presets(), "shaders": list_shader_presets()})
		"apply_shader_preset":
			var spr: Dictionary = apply_shader_preset(str(params.get("name", "")))
			if spr.get("ok", false):
				_reply_ok(client_id, id_json, spr)
			else:
				_reply_err(client_id, id_json, -32602, str(spr.get("error", "")))
		"get_state":
			_reply_ok(client_id, id_json, get_full_state())
		"tracking.start":
			tracking.apply_settings(params)
			var tr: Dictionary = start_tracking()
			if tr.get("ok", false):
				_reply_ok(client_id, id_json, tracking.to_dict())
			else:
				_reply_err(client_id, id_json, -32010, str(tr.get("error", "tracking start failed")))
		"tracking.stop":
			stop_tracking()
			_reply_ok(client_id, id_json, tracking.to_dict())
		"tracking.status":
			_reply_ok(client_id, id_json, tracking.to_dict())
		"tracking.set":
			apply_tracking_settings(params)
			_reply_ok(client_id, id_json, tracking.to_dict())
		"tracking.calibrate":
			var cr: Dictionary = tracking.calibrate()
			if cr.get("ok", false):
				_reply_ok(client_id, id_json, cr)
			else:
				_reply_err(client_id, id_json, -32011, str(cr.get("error", "")))
		"tracking.reset_calibration":
			tracking.reset_calibration()
			_reply_ok(client_id, id_json, tracking.to_dict())
		"get_model_info":
			if current_vrm == null:
				_reply_err(client_id, id_json, -32001, "No VRM model loaded")
			else:
				_reply_ok(client_id, id_json, current_vrm.get_model_info())
		"load_vrm":
			var res := load_vrm(str(params.get("path", "")))
			if res.get("ok", false):
				_reply_ok(client_id, id_json, res)
			else:
				_reply_err(client_id, id_json, -32002, str(res.get("error", "load_vrm failed")))
		"unload_vrm":
			unload_vrm()
			_reply_ok(client_id, id_json, {"ok": true})
		"set_camera":
			camera_rig.apply_params(params)
			_reply_ok(client_id, id_json, camera_rig.to_dict())
		"apply_camera_preset":
			var h := _get_model_height()
			camera_rig.apply_preset(str(params.get("preset", "full_body")), h)
			_reply_ok(client_id, id_json, camera_rig.to_dict())
		"effects.set":
			apply_effects(params)
			_reply_ok(client_id, id_json, post_effects.to_dict())
		"effects.get":
			_reply_ok(client_id, id_json, post_effects.to_dict())
		"effects.presets":
			var plist: Array = []
			for k in PostEffectsScript.PRESETS.keys():
				plist.append({"id": k, "name": PostEffectsScript.PRESETS[k][0], "description": PostEffectsScript.PRESETS[k][1]})
			_reply_ok(client_id, id_json, {"presets": plist})
		"set_lighting", "apply_lighting_preset":
			lighting_rig.apply_params(params)
			_reply_ok(client_id, id_json, lighting_rig.to_dict())
		"load_vrma":
			var lres := load_vrma_file(str(params.get("path", "")), str(params.get("name", "")), bool(params.get("auto_play", false)))
			if lres.get("ok", false):
				_reply_ok(client_id, id_json, lres)
			else:
				_reply_err(client_id, id_json, -32003, str(lres.get("error", "load_vrma failed")))
		"play_animation":
			var ok_play := play_animation_internal(
				str(params.get("name", "")),
				bool(params.get("looping", true)),
				float(params.get("speed", 1.0)),
				float(params.get("blend_sec", 0.25))
			)
			if ok_play:
				_reply_ok(client_id, id_json, {"playing": true, "name": vrma_player.current_name})
			else:
				_reply_err(client_id, id_json, -32602, "Unknown animation: " + str(params.get("name", "")))
		"stop_animation":
			stop_animation_internal()
			_reply_ok(client_id, id_json, {"playing": false})
		"set_animation_params":
			set_animation_params(params)
			_reply_ok(client_id, id_json, _anim_state_dict())
		"set_idle_params":
			procedural_idle.apply_params(params)
			_emit_state_changed()
			_reply_ok(client_id, id_json, procedural_idle.get_params())
		"set_expression":
			set_expression_weight(str(params.get("name", "")), float(params.get("weight", 0.0)), float(params.get("transition_sec", 0.0)))
			_reply_ok(client_id, id_json, _expr_weights_dict())
		"set_expressions":
			set_expressions_weights(
				params.get("weights", {}),
				float(params.get("transition_sec", 0.0)),
				bool(params.get("reset_others", false))
			)
			_reply_ok(client_id, id_json, _expr_weights_dict())
		"reset_expressions":
			reset_expressions(float(params.get("transition_sec", 0.0)))
			_reply_ok(client_id, id_json, _expr_weights_dict())
		"set_lookat":
			set_lookat_params(params)
			_reply_ok(client_id, id_json, {"mode": _last_lookat_mode})
		"set_first_person":
			set_first_person_mode(bool(params.get("enabled", false)))
			_reply_ok(client_id, id_json, {"first_person": _last_first_person})
		"set_bones":
			set_bones_pose(params)
			_reply_ok(client_id, id_json, {"ok": true})
		"reset_bones":
			reset_bones_pose_smooth(float(params.get("transition_sec", 0.0)))
			_reply_ok(client_id, id_json, {"ok": true})
		"apply_pose_preset":
			var p_name: String = str(params.get("preset", "reset"))
			apply_pose_preset(p_name, float(params.get("transition_sec", 0.0)), bool(params.get("keep_animation", false)))
			_reply_ok(client_id, id_json, {"ok": true, "preset": p_name})
		"restore_normal_window":
			bg_manager.restore_normal_window()
			var rn_res: Dictionary = bg_manager.window_to_dict()
			rn_res["settings_visible"] = settings_window.visible if settings_window != null else false
			_reply_ok(client_id, id_json, rn_res)
		"set_background":
			bg_manager.apply_background(params)
			_reply_ok(client_id, id_json, bg_manager.bg_to_dict())
		"set_window":
			if params.has("settings_visible") and params["settings_visible"] != null:
				if bool(params["settings_visible"]):
					open_settings_window()
				else:
					close_settings_window()
			bg_manager.apply_window(params)
			var w_res: Dictionary = bg_manager.window_to_dict()
			w_res["settings_visible"] = settings_window.visible if settings_window != null else false
			_reply_ok(client_id, id_json, w_res)
		"set_output_viewport":
			bg_manager.apply_output_viewport(params)
			_reply_ok(client_id, id_json, bg_manager.output_to_dict())
		"capture_screenshot":
			_handle_capture_screenshot(client_id, id_json, params)
		"start_recording":
			var sres: Dictionary = capture_manager.start_recording(params)
			if sres.get("ok", false):
				_reply_ok(client_id, id_json, sres)
			else:
				_reply_err(client_id, id_json, -32004, str(sres.get("error", "start_recording failed")))
		"stop_recording":
			var stop_r: Dictionary = capture_manager.stop_recording()
			if stop_r.get("ok", false):
				_reply_ok(client_id, id_json, stop_r)
			else:
				_reply_err(client_id, id_json, -32004, str(stop_r.get("error", "stop_recording failed")))
		"render_sequence":
			_handle_render_sequence(client_id, id_json, params)
		"set_spout":
			var sp: Dictionary = capture_manager.set_spout(params)
			if sp.get("ok", false):
				_reply_ok(client_id, id_json, sp)
			else:
				_reply_err(client_id, id_json, -32005, str(sp.get("error", "set_spout failed")))
		"set_vcam":
			var vc: Dictionary = capture_manager.set_vcam(params)
			_reply_ok(client_id, id_json, vc)
		"get_vcam_status":
			_reply_ok(client_id, id_json, capture_manager.get_vcam_status())
		"set_hotkeys":
			hotkey_manager.apply_params(params)
			_emit_state_changed()
			_reply_ok(client_id, id_json, hotkey_manager.to_dict())
		"save_config":
			var sc := save_config(str(params.get("path", "")))
			_reply_ok(client_id, id_json, sc)
		"load_config":
			var lc := reload_config(str(params.get("path", "")))
			_reply_ok(client_id, id_json, lc)
		"shutdown":
			_reply_ok(client_id, id_json, {"shutting_down": true})
			_shutting_down = true
			save_config()
			get_tree().call_deferred("quit", 0)
		_:
			_reply_err(client_id, id_json, -32601, "Method not found: " + method)


func _handle_capture_screenshot(client_id: int, id_json: String, params: Dictionary) -> void:
	var res: Dictionary = await capture_manager.capture_screenshot(params)
	if res.get("ok", false):
		_reply_ok(client_id, id_json, res)
	else:
		_reply_err(client_id, id_json, -32004, str(res.get("error", "capture_screenshot failed")))


func _handle_render_sequence(client_id: int, id_json: String, params: Dictionary) -> void:
	var res: Dictionary = await capture_manager.render_sequence(params, self)
	if res.get("ok", false):
		_reply_ok(client_id, id_json, res)
	else:
		_reply_err(client_id, id_json, -32006, str(res.get("error", "render_sequence failed")))


func _reply_ok(client_id: int, id_json: String, result_dict: Dictionary) -> void:
	if bridge != null:
		bridge.send_rpc_response(client_id, bridge.build_rpc_ok(id_json, JSON.stringify(result_dict)))


func _reply_err(client_id: int, id_json: String, code: int, msg: String) -> void:
	if bridge != null:
		bridge.send_rpc_response(client_id, bridge.build_rpc_err(id_json, code, msg))


func _poll_vmc() -> void:
	if current_vrm == null:
		return
	var json_str := bridge.poll_vmc_frame()
	if json_str == "":
		# VMC が 1.5 秒途切れたら (トラッカー停止など) 上書きを解除して通常の動きに戻す
		if _last_vmc_msec > 0 and Time.get_ticks_msec() - _last_vmc_msec > 1500:
			_last_vmc_msec = 0
			current_vrm.vmc_bone_overrides.clear()
			current_vrm.force_camera_gaze = false
			current_vrm.has_vmc_hips_offset = false
		return
	_last_vmc_msec = Time.get_ticks_msec()
	var frame = JSON.parse_string(json_str)
	if typeof(frame) != TYPE_DICTIONARY:
		return

	var root_pose = frame.get("root", null)
	if typeof(root_pose) == TYPE_DICTIONARY:
		var pos: Array = root_pose.get("pos", [0.0, 0.0, 0.0])
		if pos.size() >= 3:
			# VMC は Unity 座標 (左手系) → VRM/Godot 座標へ
			current_vrm.vmc_hips_offset = Vector3(-float(pos[0]), float(pos[1]), float(pos[2]))
			current_vrm.has_vmc_hips_offset = true

	var bones: Dictionary = frame.get("bones", {})
	# 「カメラ目線」のときは、送られてきた目の向きを使わない (LookAt でカメラを見る)
	var camera_gaze: bool = str(tracking.settings.get("gaze_mode", "track")) == "camera"
	current_vrm.force_camera_gaze = camera_gaze
	if camera_gaze:
		current_vrm.vmc_bone_overrides.erase("leftEye")
		current_vrm.vmc_bone_overrides.erase("rightEye")
	for raw_name in bones.keys():
		var bname := _vmc_bone_to_vrm(str(raw_name))
		if camera_gaze and (bname == "leftEye" or bname == "rightEye"):
			continue
		var bdata: Dictionary = bones[raw_name]
		var q: Array = bdata.get("quat", [0.0, 0.0, 0.0, 1.0])
		if q.size() >= 4:
			# VMC は Unity 座標 (左手系) → VRM/Godot 座標へ (x, -y, -z, w)
			current_vrm.vmc_bone_overrides[bname] = Quaternion(float(q[0]), -float(q[1]), -float(q[2]), float(q[3])).normalized()

	var blends: Dictionary = frame.get("blendshapes", {})
	if bool(frame.get("blend_apply", false)) and not blends.is_empty():
		var auto_expr: bool = bool(tracking.settings.get("expressions", true))
		var mapped := {}
		for k in blends.keys():
			var ek := str(VMC_EXPR_ALIASES.get(str(k), str(k)))
			if not auto_expr and VMC_AUTO_EMOTION_KEYS.has(ek):
				continue
			if _manual_expr_overrides.has(ek):
				continue
			if current_vrm.expressions.mouth_locked and VrmExpressionsScript.MOUTH_SET.has(ek):
				continue  # リップシンクの間は、トラッキングの口を使わない
			mapped[ek] = float(blends[k])
		if not mapped.is_empty():
			current_vrm.expressions.set_weights(mapped, 0.0, false)


static func _vmc_bone_to_vrm(raw: String) -> String:
	if raw.is_empty():
		return raw
	var n := raw.substr(0, 1).to_lower() + raw.substr(1)
	# Unity HumanBodyBones の親指名 → VRM 1.0 の親指名
	if n.ends_with("ThumbProximal"):
		return n.trim_suffix("ThumbProximal") + "ThumbMetacarpal"
	if n.ends_with("ThumbIntermediate"):
		return n.trim_suffix("ThumbIntermediate") + "ThumbProximal"
	return n


static func _resolve_input_path(path: String) -> String:
	if path == "" or path.begins_with("res://") or path.begins_with("user://") or path.is_absolute_path():
		return path
	if FileAccess.file_exists(path):
		return path
	var rel: String = ConfigManagerScript.get_app_root_dir().path_join(path)
	if FileAccess.file_exists(rel):
		return rel
	return path


## keep_camera: 保存した設定からの読み込みでは、カメラを自動で合わせ直さない (保存したカメラ位置を使う)
func load_vrm(path: String, keep_camera: bool = false) -> Dictionary:
	path = _resolve_input_path(path)
	var res: Dictionary = VrmLoaderScript.load_vrm(path, bridge)
	if not res.get("ok", false):
		if _overlay_error_lbl != null:
			_overlay_error_lbl.text = "読み込みエラー: " + str(res.get("error", "unknown error"))
			_overlay_error_lbl.visible = true
		return res
	if _overlay_error_lbl != null:
		_overlay_error_lbl.visible = false
	unload_vrm(false)  # 差し替え中は窓の状態を戻さない
	current_vrm = res["runtime"]
	model_root.add_child(current_vrm)
	post_effects.apply_shade_to(current_vrm)
	current_vrm.animation_player = vrma_player
	current_vrm.procedural_idle = procedural_idle
	current_vrm.lookat.mode = _last_lookat_mode
	current_vrm.lookat.manual_target = _last_lookat_manual_target
	current_vrm.first_person.set_first_person_mode(_last_first_person)
	current_vrm.spring_bone.enabled = _spring_enabled
	current_vrm.spring_bone.gravity_scale = _spring_gravity_scale
	current_vrm.spring_bone.stiffness_scale = _spring_stiffness_scale
	current_vrm.spring_bone.external_wind = lighting_rig.wind

	var abs_path: String = current_vrm.model_path
	if not recent_vrm_paths.has(abs_path):
		recent_vrm_paths.push_front(abs_path)
		if recent_vrm_paths.size() > 10:
			recent_vrm_paths.resize(10)

	if _last_animation != "" and not vrma_player.has_clip(_last_animation):
		_last_animation = "for-test_a-pose"  # 前に使っていた動きが無くなったとき (同梱の idle などを消した)
	if _last_animation != "" and vrma_player.has_clip(_last_animation):
		vrma_player.play(_last_animation, true, 1.0, 0.0)
	if not keep_camera:
		camera_rig.auto_frame(current_vrm.get_approx_bounds())

	_update_overlay_visibility()
	var info: Dictionary = current_vrm.get_model_info()
	model_loaded.emit(info)
	_emit_state_changed()
	return {"ok": true, "model_info": info}


func unload_vrm(restore_window_if_empty: bool = true) -> void:
	_direct_bone_euler_deg.clear()
	if current_vrm != null:
		current_vrm.queue_free()
		current_vrm = null
	if restore_window_if_empty:
		_ensure_operable_window()
	_update_overlay_visibility()
	_emit_state_changed()


## .vrma と .npz (SMPL 系のモーション) のどちらも、同じアニメーションのクリップとして読む
func _load_motion_clip(path: String, clip_name: String) -> Dictionary:
	if path.to_lower().ends_with(".npz"):
		return NpzMotionLoaderScript.load_npz(path, clip_name)
	return VrmaLoaderScript.load_vrma(path, bridge, clip_name)


func load_vrma_file(path: String, clip_name: String = "", auto_play: bool = false) -> Dictionary:
	path = _resolve_input_path(path)
	var res: Dictionary = _load_motion_clip(path, clip_name)
	if not res.get("ok", false):
		return res
	var clip = res["clip"]
	vrma_player.add_clip(clip.name, clip)
	if auto_play:
		vrma_player.play(clip.name, true, 1.0, 0.25)
		_last_animation = clip.name
	_emit_state_changed()
	return {"ok": true, "name": clip.name, "duration": clip.duration}


func play_animation_internal(anim_name: String, looping: bool = true, speed: float = 1.0, blend_sec: float = 0.25) -> bool:
	if anim_name == "" or anim_name == "none":
		stop_animation_internal()
		return true
	var ok: bool = vrma_player.play(anim_name, looping, speed, blend_sec)
	if ok:
		_last_animation = anim_name
		_emit_state_changed()
	return ok


func stop_animation_internal() -> void:
	vrma_player.stop()
	_last_animation = ""
	_emit_state_changed()


func set_animation_params(params: Dictionary) -> void:
	if params.get("speed", null) != null:
		vrma_player.speed = clampf(float(params["speed"]), 0.0, 5.0)
	if params.get("looping", null) != null:
		vrma_player.looping = bool(params["looping"])
	if params.get("paused", null) != null:
		vrma_player.paused = bool(params["paused"])
	if params.get("seek_sec", null) != null:
		vrma_player.seek(float(params["seek_sec"]))
	_emit_state_changed()


func set_expression_weight(ename: String, weight: float, transition_sec: float = 0.0) -> void:
	if weight > 0.001:
		_manual_expr_overrides[ename] = true
	else:
		_manual_expr_overrides.erase(ename)
	if current_vrm == null:
		return
	current_vrm.expressions.set_weight(ename, weight, transition_sec)
	_emit_state_changed()


func set_expressions_weights(weights: Dictionary, transition_sec: float = 0.0, reset_others: bool = false) -> void:
	if reset_others:
		_manual_expr_overrides.clear()
	for k in weights.keys():
		var ek := str(k)
		if float(weights[k]) > 0.001:
			_manual_expr_overrides[ek] = true
		else:
			_manual_expr_overrides.erase(ek)
	if current_vrm == null:
		return
	current_vrm.expressions.set_weights(weights, transition_sec, reset_others)
	_emit_state_changed()


func reset_expressions(transition_sec: float = 0.0) -> void:
	_manual_expr_overrides.clear()
	if current_vrm == null:
		return
	current_vrm.expressions.reset_all(transition_sec)
	_emit_state_changed()


func set_lookat_params(params: Dictionary) -> void:
	if params.get("mode", null) != null:
		_last_lookat_mode = str(params["mode"])
	if typeof(params.get("target", null)) == TYPE_ARRAY and params["target"].size() >= 3:
		var t: Array = params["target"]
		_last_lookat_manual_target = Vector3(float(t[0]), float(t[1]), float(t[2]))
	if current_vrm != null:
		current_vrm.lookat.mode = _last_lookat_mode
		current_vrm.lookat.manual_target = _last_lookat_manual_target
	_emit_state_changed()


func set_first_person_mode(enabled: bool) -> void:
	_last_first_person = enabled
	if current_vrm != null:
		current_vrm.first_person.set_first_person_mode(enabled)
	_emit_state_changed()


func set_bones_pose(params: Dictionary) -> void:
	if current_vrm == null:
		return
	var trans := float(params.get("transition_sec", 0.0))
	if trans > 0.0:
		_set_bones_pose_smooth(params, trans)
		return
	motion.cancel_blend()
	if bool(params.get("clear_others", false)):
		current_vrm.direct_bone_overrides.clear()
		_direct_bone_euler_deg.clear()
		current_vrm.has_direct_hips_offset = false
		current_vrm.direct_hips_offset = Vector3.ZERO
	var bones: Dictionary = params.get("bones", {})
	for bname in bones.keys():
		var sbname: String = str(bname)
		var spec: Dictionary = bones[bname]
		if typeof(spec.get("quat_xyzw", null)) == TYPE_ARRAY and spec["quat_xyzw"].size() >= 4:
			var q: Array = spec["quat_xyzw"]
			var quat := Quaternion(float(q[0]), float(q[1]), float(q[2]), float(q[3])).normalized()
			current_vrm.direct_bone_overrides[sbname] = quat
			var er := quat.get_euler()
			_direct_bone_euler_deg[sbname] = Vector3(rad_to_deg(er.x), rad_to_deg(er.y), rad_to_deg(er.z))
		elif typeof(spec.get("euler_deg", null)) == TYPE_ARRAY and spec["euler_deg"].size() >= 3:
			var e: Array = spec["euler_deg"]
			var ev := Vector3(float(e[0]), float(e[1]), float(e[2]))
			_direct_bone_euler_deg[sbname] = ev
			current_vrm.direct_bone_overrides[sbname] = Quaternion.from_euler(
				Vector3(deg_to_rad(ev.x), deg_to_rad(ev.y), deg_to_rad(ev.z))
			)
	if typeof(params.get("hips_position", null)) == TYPE_ARRAY and params["hips_position"].size() >= 3:
		var hp: Array = params["hips_position"]
		current_vrm.direct_hips_offset = Vector3(float(hp[0]), float(hp[1]), float(hp[2]))
		current_vrm.has_direct_hips_offset = true


## ボーンの指定を transition_sec 秒かけてなめらかに付ける
func _set_bones_pose_smooth(params: Dictionary, trans: float) -> void:
	var target := {}
	var bones: Dictionary = params.get("bones", {})
	for bname in bones.keys():
		var sb := str(bname)
		var spec: Dictionary = bones[bname]
		if typeof(spec.get("quat_xyzw", null)) == TYPE_ARRAY and spec["quat_xyzw"].size() >= 4:
			var q: Array = spec["quat_xyzw"]
			target[sb] = Quaternion(float(q[0]), float(q[1]), float(q[2]), float(q[3])).normalized()
		elif typeof(spec.get("euler_deg", null)) == TYPE_ARRAY and spec["euler_deg"].size() >= 3:
			var e: Array = spec["euler_deg"]
			target[sb] = Quaternion.from_euler(Vector3(deg_to_rad(float(e[0])), deg_to_rad(float(e[1])), deg_to_rad(float(e[2]))))
		if target.has(sb):
			var er: Vector3 = (target[sb] as Quaternion).get_euler()
			_direct_bone_euler_deg[sb] = Vector3(rad_to_deg(er.x), rad_to_deg(er.y), rad_to_deg(er.z))
	if typeof(params.get("hips_position", null)) == TYPE_ARRAY and params["hips_position"].size() >= 3:
		var hp: Array = params["hips_position"]
		current_vrm.direct_hips_offset = Vector3(float(hp[0]), float(hp[1]), float(hp[2]))
		current_vrm.has_direct_hips_offset = true
	motion.blend_bones(target, trans, bool(params.get("clear_others", false)))
	_emit_state_changed()


## ボーンの直接指定を transition_sec 秒かけて外し、アニメーションの姿勢へ戻す
func reset_bones_pose_smooth(trans: float) -> void:
	if current_vrm == null:
		return
	if trans <= 0.0:
		reset_bones_pose()
		return
	current_vrm.has_direct_hips_offset = false
	current_vrm.direct_hips_offset = Vector3.ZERO
	motion.blend_bones({}, trans, true)
	_emit_state_changed()


func reset_bones_pose() -> void:
	_direct_bone_euler_deg.clear()
	if motion != null:
		motion.cancel_blend()
	if current_vrm == null:
		return
	current_vrm.direct_bone_overrides.clear()
	current_vrm.has_direct_hips_offset = false
	current_vrm.direct_hips_offset = Vector3.ZERO
	current_vrm.vmc_bone_overrides.clear()
	current_vrm.force_camera_gaze = false
	current_vrm.has_vmc_hips_offset = false
	if current_vrm.spring_bone != null:
		current_vrm.spring_bone.reset_state()
	_emit_state_changed()


func save_config(custom_path: String = "") -> Dictionary:
	return ConfigManagerScript.save_config(build_config_dict(), custom_path)


## 今の設定をすべて 1 つのファイルに書き出す (別の PC への移行・バックアップ用)。
const SETTINGS_FILE_KIND := "utsushimirror-settings"


func export_settings(path: String) -> Dictionary:
	if path.get_extension() == "":
		path += ".umset"
	var d := build_config_dict()
	d["kind"] = SETTINGS_FILE_KIND
	d.erase("recent_settings_paths")  # 履歴はこの PC だけのもの
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": error_string(FileAccess.get_open_error())}
	f.store_string(JSON.stringify(d, "	"))
	f.close()
	_remember_settings_path(path)
	return {"ok": true, "path": path}


## 最近書き出した・読み込んだ設定ファイルのうち、今もあるもの (新しい順)。
func get_recent_settings_paths() -> Array[String]:
	var out: Array[String] = []
	for p in recent_settings_paths:
		if FileAccess.file_exists(p):
			out.append(p)
	return out


func clear_recent_settings_paths() -> void:
	recent_settings_paths.clear()
	_persist_recent_settings()


func _norm_settings_path(path: String) -> String:
	return path.replace("\\", "/").simplify_path()


func _remember_settings_path(path: String) -> void:
	var p := _norm_settings_path(path)
	recent_settings_paths.erase(p)
	recent_settings_paths.push_front(p)
	if recent_settings_paths.size() > RECENT_SETTINGS_MAX:
		recent_settings_paths.resize(RECENT_SETTINGS_MAX)
	_persist_recent_settings()


## 履歴だけをいつもの設定ファイルに書き足す (ほかの設定は保存しない)。
func _persist_recent_settings() -> void:
	var res: Dictionary = ConfigManagerScript.load_config()
	var cfg: Dictionary = res.get("config", {}) if res.get("ok", false) else {}
	cfg["recent_settings_paths"] = recent_settings_paths.duplicate()
	ConfigManagerScript.save_config(cfg)


## 書き出した設定ファイル (または保存先の設定ファイルそのもの) を読み込んで反映する。
## 反映したあとは、ふだんの保存先にも保存する (次に起動したときもこの設定になる)。
func import_settings(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "ファイルがありません"}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(d) != TYPE_DICTIONARY:
		return {"ok": false, "error": "設定ファイルとして読めません"}
	var kind := str(d.get("kind", ""))
	if kind != SETTINGS_FILE_KIND and not (kind == "" and d.has("version") and d.has("camera")):
		return {"ok": false, "error": "うつしみらーの設定ファイルではありません"}
	# 同じモデルを読み込み直さない
	if current_vrm != null and str(d.get("last_vrm_path", "")) == current_vrm.model_path:
		d.erase("last_vrm_path")
	d.erase("recent_settings_paths")
	_apply_config_dict(d)
	_emit_state_changed()
	recent_settings_paths.erase(_norm_settings_path(path))
	recent_settings_paths.push_front(_norm_settings_path(path))
	if recent_settings_paths.size() > RECENT_SETTINGS_MAX:
		recent_settings_paths.resize(RECENT_SETTINGS_MAX)
	save_config()
	return {"ok": true}


func reload_config(custom_path: String = "") -> Dictionary:
	var res: Dictionary = ConfigManagerScript.load_config(custom_path)
	if res.get("ok", false):
		_apply_config_dict(res["config"])
		_emit_state_changed()
	return res


func build_config_dict() -> Dictionary:
	var win_dict: Dictionary = bg_manager.window_to_dict()
	var sv: bool = settings_window.visible if settings_window != null else true
	if OS.get_environment("VRMVIEWER_NO_SETTINGS") == "1":
		sv = true
	win_dict["settings_visible"] = sv
	var out_dict: Dictionary = bg_manager.output_to_dict()
	out_dict["spout_enabled"] = capture_manager.spout_enabled
	out_dict["spout_sender_name"] = capture_manager.spout_sender_name
	out_dict["vcam_enabled"] = capture_manager.vcam_enabled
	out_dict["screenshots_dir"] = capture_manager.screenshots_dir
	out_dict["recordings_dir"] = capture_manager.recordings_dir
	return {
		"version": 1,
		"last_vrm_path": current_vrm.model_path if current_vrm != null else "",
		"recent_vrm_paths": recent_vrm_paths.duplicate(),
		"recent_settings_paths": recent_settings_paths.duplicate(),
		"last_animation": _last_animation,
		"first_person": _last_first_person,
		"lookat_mode": _last_lookat_mode,
		"lookat_target": [_last_lookat_manual_target.x, _last_lookat_manual_target.y, _last_lookat_manual_target.z],
		"model_transform": get_model_transform_dict(),
		"spring_bone": get_spring_bone_params_dict(),
		"camera": camera_rig.to_dict(),
		"lighting": lighting_rig.to_dict(),
		"effects": post_effects.to_dict(),
		"background": bg_manager.bg_to_dict(),
		"window": win_dict,
		"output": out_dict,
		"idle": procedural_idle.get_params(),
		"hotkeys": hotkey_manager.to_dict(),
		"api": {"ws_port": ws_port, "osc_port": osc_port},
		"tracking": tracking.settings.duplicate(),
		"lipsync": {"mode": lipsync_mode, "intensity": lip_sync.intensity, "emotion": lip_sync.emotion},
	}


func get_full_state() -> Dictionary:
	var win_dict: Dictionary = bg_manager.window_to_dict()
	win_dict["settings_visible"] = settings_window.visible if settings_window != null else false
	return {
		"model_loaded": current_vrm != null,
		"model_path": current_vrm.model_path if current_vrm != null else "",
		"model_name": current_vrm.first_person.meta.get("name", "") if current_vrm != null else "",
		"recent_vrm_paths": recent_vrm_paths.duplicate(),
		"model_transform": get_model_transform_dict(),
		"spring_bone": get_spring_bone_params_dict(),
		"available_animations": vrma_player.get_clip_names(),
		"animation_categories": _animation_categories(),
		"shader_presets": list_shader_presets().map(func(x): return x.name),
		"motion": motion.state() if motion != null else {},
		"lipsync": lipsync_state(),
		"animation": _anim_state_dict(),
		"idle": procedural_idle.get_params(),
		"expressions": _expr_weights_dict(),
		"lookat_mode": _last_lookat_mode,
		"lookat_target": [_last_lookat_manual_target.x, _last_lookat_manual_target.y, _last_lookat_manual_target.z],
		"first_person": _last_first_person,
		"camera": camera_rig.to_dict(),
		"lighting": lighting_rig.to_dict(),
		"effects": post_effects.to_dict(),
		"background": bg_manager.bg_to_dict(),
		"window": win_dict,
		"output_viewport": bg_manager.output_to_dict(),
		"capture": capture_manager.to_dict(),
		"vcam_status": capture_manager.get_vcam_status(),
		"hotkeys": hotkey_manager.to_dict(),
		"api": {"ws_port": ws_port, "osc_port": osc_port, "running": bridge.is_servers_running() if bridge != null else false},
		"tracking": tracking.to_dict(),
	}


func _apply_config_dict(cfg: Dictionary) -> void:
	if cfg.has("recent_vrm_paths") and typeof(cfg["recent_vrm_paths"]) == TYPE_ARRAY:
		recent_vrm_paths.clear()
		for p in cfg["recent_vrm_paths"]:
			recent_vrm_paths.append(str(p))
	if cfg.has("recent_settings_paths") and typeof(cfg["recent_settings_paths"]) == TYPE_ARRAY:
		recent_settings_paths.clear()
		for p in cfg["recent_settings_paths"]:
			recent_settings_paths.append(str(p))
	if cfg.has("last_animation"):
		_last_animation = str(cfg["last_animation"])
	if cfg.has("first_person"):
		_last_first_person = bool(cfg["first_person"])
	if cfg.has("lookat_mode"):
		_last_lookat_mode = str(cfg["lookat_mode"])
	if typeof(cfg.get("lookat_target", null)) == TYPE_ARRAY and cfg["lookat_target"].size() >= 3:
		var lt: Array = cfg["lookat_target"]
		_last_lookat_manual_target = Vector3(float(lt[0]), float(lt[1]), float(lt[2]))
	if cfg.has("model_transform") and typeof(cfg["model_transform"]) == TYPE_DICTIONARY:
		set_model_transform(cfg["model_transform"])
	if cfg.has("spring_bone") and typeof(cfg["spring_bone"]) == TYPE_DICTIONARY:
		set_spring_bone_params(cfg["spring_bone"])
	if cfg.has("camera") and typeof(cfg["camera"]) == TYPE_DICTIONARY:
		camera_rig.apply_params(cfg["camera"])
	if cfg.has("lighting") and typeof(cfg["lighting"]) == TYPE_DICTIONARY:
		lighting_rig.apply_params(cfg["lighting"])
	if cfg.has("effects") and typeof(cfg["effects"]) == TYPE_DICTIONARY:
		post_effects.load_dict(cfg["effects"])
		post_effects.apply_shade_to(current_vrm)
	if cfg.has("background") and typeof(cfg["background"]) == TYPE_DICTIONARY:
		bg_manager.apply_background(cfg["background"])
	if cfg.has("window") and typeof(cfg["window"]) == TYPE_DICTIONARY:
		bg_manager.apply_window(cfg["window"])
		if cfg["window"].has("settings_visible"):
			_cfg_settings_visible = bool(cfg["window"]["settings_visible"])
			if settings_window != null:
				settings_window.visible = _cfg_settings_visible
	if cfg.has("output") and typeof(cfg["output"]) == TYPE_DICTIONARY:
		var out_d: Dictionary = cfg["output"]
		bg_manager.apply_output_viewport(out_d)
		if out_d.has("screenshots_dir"):
			capture_manager.screenshots_dir = str(out_d["screenshots_dir"])
		if out_d.has("recordings_dir"):
			capture_manager.recordings_dir = str(out_d["recordings_dir"])
	if cfg.has("idle") and typeof(cfg["idle"]) == TYPE_DICTIONARY:
		procedural_idle.apply_params(cfg["idle"])
	if cfg.has("hotkeys") and typeof(cfg["hotkeys"]) == TYPE_DICTIONARY:
		hotkey_manager.apply_params(cfg["hotkeys"])
	if cfg.has("api") and typeof(cfg["api"]) == TYPE_DICTIONARY:
		ws_port = int(cfg["api"].get("ws_port", ws_port))
		osc_port = int(cfg["api"].get("osc_port", osc_port))
	if cfg.has("lipsync") and typeof(cfg["lipsync"]) == TYPE_DICTIONARY:
		var ls: Dictionary = cfg["lipsync"]
		if str(ls.get("mode", "")) in LIPSYNC_MODES:
			set_lipsync_mode(str(ls["mode"]))
		lip_sync.intensity = clampf(float(ls.get("intensity", lip_sync.intensity)), 0.0, 1.5)
		lip_sync.emotion = bool(ls.get("emotion", lip_sync.emotion))
	if cfg.has("tracking") and typeof(cfg["tracking"]) == TYPE_DICTIONARY:
		tracking.apply_settings(cfg["tracking"])
	var last_vrm := str(cfg.get("last_vrm_path", ""))
	if last_vrm != "" and FileAccess.file_exists(last_vrm):
		load_vrm(last_vrm, cfg.has("camera") and typeof(cfg["camera"]) == TYPE_DICTIONARY)


func _on_hotkey_action(action: String) -> void:
	if action.begins_with("expr:"):
		var ename := action.substr(5)
		if current_vrm != null:
			var cur: float = float(current_vrm.expressions.target_weights.get(ename, 0.0))
			var next_w := 0.0 if cur > 0.5 else 1.0
			if ename == "neutral":
				reset_expressions(0.15)
			else:
				set_expressions_weights({ename: next_w}, 0.12, true)
	elif action == "action:screenshot":
		take_screenshot()
	elif action == "action:toggle_record":
		if capture_manager.recording_active:
			capture_manager.stop_recording()
		else:
			capture_manager.start_recording({})
	elif action == "action:toggle_click_through":
		bg_manager.apply_window({"click_through": not bg_manager.win_click_through})
	elif action == "action:toggle_settings":
		toggle_settings_window()


func _on_lighting_changed() -> void:
	if bg_manager != null:
		bg_manager.sync_output_environment()
	if current_vrm != null and current_vrm.spring_bone != null:
		current_vrm.spring_bone.external_wind = lighting_rig.wind
	_emit_state_changed()


func _get_model_height() -> float:
	if current_vrm == null:
		return 1.6
	return maxf(current_vrm.get_approx_bounds().size.y, 0.6)


func get_model_height() -> float:
	return _get_model_height()


func _anim_state_dict() -> Dictionary:
	return {
		"playing": vrma_player.playing,
		"name": vrma_player.current_name,
		"looping": vrma_player.looping,
		"speed": vrma_player.speed,
		"paused": vrma_player.paused,
		"time_sec": vrma_player.time_sec,
		"duration": vrma_player.current_clip.duration if vrma_player.current_clip != null else 0.0,
	}


func _expr_weights_dict() -> Dictionary:
	if current_vrm == null:
		return {}
	return current_vrm.expressions.get_weights_snapshot()


func _emit_state_changed() -> void:
	state_changed.emit()


# ---------------------------------------------------------------------------
# Main Window Guidance Overlay, Context Menu, File Dialogs & Settings Window
# ---------------------------------------------------------------------------

func _build_main_file_dialogs() -> void:
	var th := UiThemeScript.get_theme()

	_main_dialog_vrm = FileDialog.new()
	_main_dialog_vrm.use_native_dialog = true  # Windows 標準のファイル選択画面
	_main_dialog_vrm.theme = th
	_main_dialog_vrm.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_main_dialog_vrm.access = FileDialog.ACCESS_FILESYSTEM
	_main_dialog_vrm.filters = PackedStringArray(["*.vrm ; VRM Model"])
	_main_dialog_vrm.file_selected.connect(func(p: String): load_vrm(p))
	add_child(_main_dialog_vrm)

	_main_dialog_vrma = FileDialog.new()
	_main_dialog_vrma.use_native_dialog = true  # Windows 標準のファイル選択画面
	_main_dialog_vrma.theme = th
	_main_dialog_vrma.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_main_dialog_vrma.access = FileDialog.ACCESS_FILESYSTEM
	_main_dialog_vrma.filters = PackedStringArray(["*.vrma,*.npz ; アニメーション (VRMA / SMPL の npz)", "*.vrma ; VRM Animation", "*.npz ; SMPL 系のモーション (AMASS など)"])
	_main_dialog_vrma.file_selected.connect(func(p: String): load_vrma_file(p, "", true))
	add_child(_main_dialog_vrma)

	_main_dialog_bg_img = FileDialog.new()
	_main_dialog_bg_img.use_native_dialog = true  # Windows 標準のファイル選択画面
	_main_dialog_bg_img.theme = th
	_main_dialog_bg_img.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_main_dialog_bg_img.access = FileDialog.ACCESS_FILESYSTEM
	_main_dialog_bg_img.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Image"])
	_main_dialog_bg_img.file_selected.connect(func(p: String): bg_manager.apply_background({"mode": "image", "image_path": p}))
	add_child(_main_dialog_bg_img)


func open_vrm_file_dialog() -> void:
	if _main_dialog_vrm != null:
		# 前に開いた VRM と同じフォルダから始める
		var last := str(current_vrm.model_path) if current_vrm != null else (str(recent_vrm_paths[0]) if not recent_vrm_paths.is_empty() else "")
		if last != "" and DirAccess.dir_exists_absolute(last.get_base_dir()):
			_main_dialog_vrm.current_dir = last.get_base_dir()
		_main_dialog_vrm.popup_centered(Vector2i(760, 520))


func open_vrma_file_dialog() -> void:
	if _main_dialog_vrma != null:
		_main_dialog_vrma.popup_centered(Vector2i(760, 520))


func open_bg_image_dialog() -> void:
	if _main_dialog_bg_img != null:
		_main_dialog_bg_img.popup_centered(Vector2i(760, 520))


func _build_main_overlay() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 10
	add_child(_overlay_layer)

	_toast_layer = CanvasLayer.new()
	_toast_layer.layer = 20
	add_child(_toast_layer)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.theme = UiThemeScript.get_theme()
	_overlay_layer.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(540, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.06, 0.07, 0.92)
	style.border_color = Color("#c8252e")
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(28)
	card.add_theme_stylebox_override("panel", style)
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed:
				_on_main_right_clicked(mb.position)
				card.accept_event()
	)
	center.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	card.add_child(vb)

	var title_lbl := Label.new()
	title_lbl.text = "うつしみらー"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 26)
	vb.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "ここに .vrm ファイルをドラッグ＆ドロップして読み込み"
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", 18)
	sub_lbl.add_theme_color_override("font_color", Color("#ff8a90"))
	vb.add_child(sub_lbl)

	var guide_lbl := Label.new()
	guide_lbl.text = (
		"• .vrm / .vrma ファイルをウィンドウへそのままドロップできます\n"
		+ "• カメラ操作: 左ドラッグ回転 / Shift+左または中ドラッグ平行移動 / ホイール拡大縮小\n"
		+ "• 右クリック: メニューを開く（設定ウィンドウの再表示・ポーズ・背景切替など）\n"
		+ "• F1〜F10: 表情切替 / F11: スクショ / F12: 録画 / Ctrl+Shift+S: 設定表示切替"
	)
	guide_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide_lbl.add_theme_color_override("font_color", Color(0.84, 0.88, 0.94, 1.0))
	vb.add_child(guide_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 10)
	vb.add_child(btn_row)

	var b_open := Button.new()
	b_open.text = "VRM を開く..."
	b_open.pressed.connect(open_vrm_file_dialog)
	btn_row.add_child(b_open)

	var b_sample := Button.new()
	b_sample.text = "サンプル読込 (Seed-san)"
	b_sample.pressed.connect(func():
		load_vrm(ConfigManagerScript.get_app_root_dir().path_join("assets/samples/Seed-san.vrm"))
	)
	btn_row.add_child(b_sample)

	var b_settings := Button.new()
	b_settings.text = "設定ウィンドウを開く"
	b_settings.pressed.connect(open_settings_window)
	btn_row.add_child(b_settings)

	_overlay_error_lbl = Label.new()
	_overlay_error_lbl.visible = false
	_overlay_error_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_error_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_error_lbl.add_theme_color_override("font_color", Color("#ff7b7b"))
	vb.add_child(_overlay_error_lbl)


func _update_overlay_visibility() -> void:
	if _overlay_layer != null:
		_overlay_layer.visible = (current_vrm == null)


func _build_context_menu() -> void:
	var th := UiThemeScript.get_theme()

	_context_menu = PopupMenu.new()
	_context_menu.theme = th
	_context_menu.id_pressed.connect(_on_context_menu_id)
	add_child(_context_menu)

	_ctx_cam_menu = PopupMenu.new()
	_ctx_cam_menu.theme = th
	var cam_labels := ["全身 (full_body)", "バストアップ (bust)", "顔アップ (face)", "背面 (back)", "左側面 (left)", "右側面 (right)", "俯瞰 (top_down)"]
	for i in range(cam_labels.size()):
		_ctx_cam_menu.add_item(cam_labels[i], i)
	_ctx_cam_menu.add_separator()
	_ctx_cam_menu.add_item("オートフレーム", 99)
	_ctx_cam_menu.id_pressed.connect(_on_ctx_cam_id)
	_context_menu.add_child(_ctx_cam_menu)

	_ctx_anim_menu = PopupMenu.new()
	_ctx_anim_menu.theme = th
	_ctx_anim_menu.id_pressed.connect(_on_ctx_anim_id)
	_context_menu.add_child(_ctx_anim_menu)

	_ctx_bg_menu = PopupMenu.new()
	_ctx_bg_menu.theme = th
	_ctx_bg_menu.add_item("単色 (Solid)", 0)
	_ctx_bg_menu.add_item("クロマキー緑", 1)
	_ctx_bg_menu.add_item("クロマキー青", 2)
	_ctx_bg_menu.add_item("グラデーション", 3)
	_ctx_bg_menu.add_item("デスクトップ透過 (マスコット)", 4)
	_ctx_bg_menu.add_item("通常ウィンドウに戻す", 5)
	_ctx_bg_menu.id_pressed.connect(_on_ctx_bg_id)
	_context_menu.add_child(_ctx_bg_menu)


func _refresh_context_menu() -> void:
	if _context_menu == null:
		return
	_context_menu.clear()

	var sw_vis: bool = settings_window != null and settings_window.visible
	_context_menu.add_item("設定ウィンドウを閉じる" if sw_vis else "設定ウィンドウを開く", 1)
	_context_menu.add_separator()
	_context_menu.add_item("VRM を開く...", 2)
	_context_menu.add_item("VRMA モーションを開く...", 3)
	_context_menu.add_item("サンプル読込 (Seed-san)", 4)
	_context_menu.add_item("モデルをアンロード", 5)
	_context_menu.set_item_disabled(_context_menu.get_item_index(5), current_vrm == null)
	_context_menu.add_separator()

	_context_menu.add_submenu_node_item("カメラ", _ctx_cam_menu, 10)

	_ctx_anim_menu.clear()
	for c in _ctx_anim_menu.get_children():
		if c is PopupMenu:
			_ctx_anim_menu.remove_child(c)
			c.queue_free()
	# カテゴリーごとの小メニューに分ける
	_ctx_anim_names.clear()
	for g in AnimCategoryScript.group(vrma_player.get_clip_names()):
		var sub := PopupMenu.new()
		sub.theme = _ctx_anim_menu.theme
		sub.id_pressed.connect(_on_ctx_anim_id)
		_ctx_anim_menu.add_child(sub)
		var any_playing := false
		# 女性・男性・共通に分ける (性別の無いものしか無いカテゴリーは見出しを付けない)
		var parts := {"female": [], "male": [], "": []}
		for nm in g[1]:
			parts[AnimCategoryScript.gender_of(str(nm))].append(str(nm))
		var has_gender: bool = not parts["female"].is_empty() or not parts["male"].is_empty()
		for key in ["female", "male", ""]:
			if parts[key].is_empty():
				continue
			if has_gender:
				sub.add_separator({"female": "女性", "male": "男性", "": "共通"}[key])
			for nm in parts[key]:
				var id := _ctx_anim_names.size()
				_ctx_anim_names.append(nm)
				sub.add_check_item(AnimCategoryScript.display_name(nm), id)
				var on: bool = vrma_player.playing and vrma_player.current_name == nm
				sub.set_item_checked(sub.get_item_index(id), on)
				any_playing = any_playing or on
		_ctx_anim_menu.add_submenu_node_item(("● " if any_playing else "") + str(g[0]), sub)
	_ctx_anim_menu.add_separator()
	_ctx_anim_menu.add_item("停止 / リセット (Rest Pose)", 999)
	_context_menu.add_submenu_node_item("ポーズ / アニメーション", _ctx_anim_menu, 11)

	_context_menu.add_submenu_node_item("背景モード", _ctx_bg_menu, 12)
	_context_menu.add_separator()

	_context_menu.add_item("スクリーンショット撮影 (F11)", 6)
	_context_menu.add_check_item("常に最前面", 7)
	_context_menu.set_item_checked(_context_menu.get_item_index(7), bg_manager.win_always_on_top)
	_context_menu.add_check_item("クリックスルー (解除はタスクトレイから)", 8)
	_context_menu.set_item_checked(_context_menu.get_item_index(8), bg_manager.win_click_through)
	_context_menu.add_separator()
	_context_menu.add_item("終了", 9)


func _on_main_right_clicked(_local_pos: Vector2) -> void:
	if _context_menu == null:
		return
	_refresh_context_menu()
	var screen_pos: Vector2i = DisplayServer.mouse_get_position()
	_context_menu.reset_size()
	_context_menu.popup(Rect2i(screen_pos, Vector2i.ZERO))


func _on_context_menu_id(id: int) -> void:
	match id:
		1:
			toggle_settings_window()
		2:
			open_vrm_file_dialog()
		3:
			open_vrma_file_dialog()
		4:
			load_vrm(ConfigManagerScript.get_app_root_dir().path_join("assets/samples/Seed-san.vrm"))
		5:
			unload_vrm()
		6:
			take_screenshot()
		7:
			bg_manager.apply_window({"always_on_top": not bg_manager.win_always_on_top})
		8:
			bg_manager.apply_window({"click_through": not bg_manager.win_click_through})
		9:
			_shutting_down = true
			save_config()
			get_tree().call_deferred("quit", 0)


func _on_ctx_cam_id(id: int) -> void:
	var presets := ["full_body", "bust", "face", "back", "left", "right", "top_down"]
	if id >= 0 and id < presets.size():
		camera_rig.apply_preset(presets[id], _get_model_height())
	elif id == 99 and current_vrm != null:
		camera_rig.auto_frame(current_vrm.get_approx_bounds())


## カテゴリー → 名前の並び (一覧と同じ順)
func _animation_categories() -> Dictionary:
	var out := {}
	for g in AnimCategoryScript.group(vrma_player.get_clip_names()):
		out[g[0]] = g[1]
	return out


func _on_ctx_anim_id(id: int) -> void:
	if id == 999:
		stop_animation_internal()
		reset_bones_pose()
		return
	if id >= 0 and id < _ctx_anim_names.size():
		play_animation_internal(_ctx_anim_names[id], true, 1.0, 0.25)


func _on_ctx_bg_id(id: int) -> void:
	match id:
		0:
			bg_manager.apply_background({"mode": "solid"})
		1:
			bg_manager.apply_background({"mode": "chroma_green"})
		2:
			bg_manager.apply_background({"mode": "chroma_blue"})
		3:
			bg_manager.apply_background({"mode": "gradient"})
		4:
			bg_manager.apply_background({"mode": "transparent_window"})
			bg_manager.apply_window({"transparent": true, "borderless": true, "always_on_top": true})
		5:
			bg_manager.restore_normal_window()


func _startup_show_settings() -> void:
	if settings_window == null or DisplayServer.get_name() == "headless":
		return
	_position_settings_window_beside_main()
	if _cfg_settings_visible or current_vrm == null:
		open_settings_window()
	else:
		settings_window.visible = false
		_emit_state_changed()


func open_settings_window() -> void:
	if settings_window == null:
		return
	_ensure_settings_window_on_screen()
	settings_window.visible = true
	settings_window.grab_focus()
	_emit_state_changed()


func close_settings_window() -> void:
	if settings_window == null:
		return
	settings_window.visible = false
	_emit_state_changed()


func toggle_settings_window() -> void:
	if settings_window == null:
		return
	if settings_window.visible:
		close_settings_window()
	else:
		open_settings_window()


func _position_settings_window_beside_main() -> void:
	if settings_window == null or DisplayServer.get_name() == "headless":
		return
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	if usable.size.x <= 0 or usable.size.y <= 0:
		return
	var max_sz := Vector2i(maxi(420, usable.size.x - 40), maxi(500, usable.size.y - 40))
	settings_window.size = Vector2i(mini(settings_window.size.x, max_sz.x), mini(settings_window.size.y, max_sz.y))
	var main_pos: Vector2i = DisplayServer.window_get_position()
	var main_sz: Vector2i = DisplayServer.window_get_size()
	var sw_sz: Vector2i = settings_window.size
	var x: int = main_pos.x + main_sz.x + 12
	if x + sw_sz.x > usable.position.x + usable.size.x:
		var left_x: int = main_pos.x - sw_sz.x - 12
		if left_x >= usable.position.x:
			x = left_x
		else:
			x = usable.position.x + usable.size.x - sw_sz.x
	var y: int = clampi(main_pos.y, usable.position.y + 30, usable.position.y + usable.size.y - sw_sz.y)
	settings_window.position = Vector2i(x, y)


func _ensure_settings_window_on_screen() -> void:
	if settings_window == null or DisplayServer.get_name() == "headless":
		return
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	if usable.size.x <= 0 or usable.size.y <= 0:
		return
	var pos: Vector2i = settings_window.position
	var sz: Vector2i = settings_window.size
	var clamped_x: int = clampi(pos.x, usable.position.x, usable.position.x + maxi(0, usable.size.x - sz.x))
	var clamped_y: int = clampi(pos.y, usable.position.y + 24, usable.position.y + maxi(24, usable.size.y - sz.y))
	if clamped_x != pos.x or clamped_y != pos.y:
		settings_window.position = Vector2i(clamped_x, clamped_y)


# ---------------------------------------------------------------------------
# Extended Runtime Controls (Model Transform, SpringBone, Bone Pose, Reset)
# ---------------------------------------------------------------------------

func set_model_transform(params: Dictionary) -> void:
	if model_root == null:
		return
	if typeof(params.get("position", null)) == TYPE_ARRAY and params["position"].size() >= 3:
		var p: Array = params["position"]
		model_root.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	if params.get("rotation_y_deg", null) != null:
		model_root.rotation_degrees.y = float(params["rotation_y_deg"])
	if params.get("scale", null) != null:
		var sc: float = clampf(float(params["scale"]), 0.1, 5.0)
		model_root.scale = Vector3(sc, sc, sc)
	_emit_state_changed()


func reset_model_transform() -> void:
	set_model_transform({"position": [0.0, 0.0, 0.0], "rotation_y_deg": 0.0, "scale": 1.0})


func get_model_transform_dict() -> Dictionary:
	if model_root == null:
		return {"position": [0.0, 0.0, 0.0], "rotation_y_deg": 0.0, "scale": 1.0}
	return {
		"position": [model_root.position.x, model_root.position.y, model_root.position.z],
		"rotation_y_deg": model_root.rotation_degrees.y,
		"scale": model_root.scale.x,
	}


func set_spring_bone_params(params: Dictionary) -> void:
	if params.has("enabled") and params["enabled"] != null:
		_spring_enabled = bool(params["enabled"])
	if params.has("gravity_scale") and params["gravity_scale"] != null:
		_spring_gravity_scale = clampf(float(params["gravity_scale"]), 0.0, 3.0)
	if params.has("stiffness_scale") and params["stiffness_scale"] != null:
		_spring_stiffness_scale = clampf(float(params["stiffness_scale"]), 0.0, 3.0)
	if params.has("wind") and typeof(params["wind"]) == TYPE_ARRAY and params["wind"].size() >= 3:
		lighting_rig.apply_params({"wind": params["wind"]})
	if current_vrm != null and current_vrm.spring_bone != null:
		current_vrm.spring_bone.enabled = _spring_enabled
		current_vrm.spring_bone.gravity_scale = _spring_gravity_scale
		current_vrm.spring_bone.stiffness_scale = _spring_stiffness_scale
		current_vrm.spring_bone.external_wind = lighting_rig.wind
	_emit_state_changed()


func get_spring_bone_params_dict() -> Dictionary:
	return {
		"enabled": _spring_enabled,
		"gravity_scale": _spring_gravity_scale,
		"stiffness_scale": _spring_stiffness_scale,
		"wind": [lighting_rig.wind.x, lighting_rig.wind.y, lighting_rig.wind.z],
	}


func set_single_bone_euler(bname: String, euler_deg: Vector3) -> void:
	_direct_bone_euler_deg[bname] = euler_deg
	if current_vrm != null:
		current_vrm.direct_bone_overrides[bname] = Quaternion.from_euler(
			Vector3(deg_to_rad(euler_deg.x), deg_to_rad(euler_deg.y), deg_to_rad(euler_deg.z))
		)
	_emit_state_changed()


func clear_single_bone_pose(bname: String) -> void:
	_direct_bone_euler_deg.erase(bname)
	if current_vrm != null:
		current_vrm.direct_bone_overrides.erase(bname)
	_emit_state_changed()


func get_direct_bones_euler_deg() -> Dictionary:
	return _direct_bone_euler_deg.duplicate()


func get_direct_hips_offset() -> Vector3:
	if current_vrm != null and current_vrm.has_direct_hips_offset:
		return current_vrm.direct_hips_offset
	return Vector3.ZERO


func set_direct_hips_offset(offset: Vector3, enabled: bool = true) -> void:
	if current_vrm == null:
		return
	current_vrm.direct_hips_offset = offset if enabled else Vector3.ZERO
	current_vrm.has_direct_hips_offset = enabled


func mirror_bones_pose(left_to_right: bool) -> void:
	var src_prefix: String = "left" if left_to_right else "right"
	var dst_prefix: String = "right" if left_to_right else "left"
	var keys := _direct_bone_euler_deg.keys().duplicate()
	for k in keys:
		var sk: String = str(k)
		if sk.begins_with(src_prefix):
			var dst_name: String = dst_prefix + sk.substr(src_prefix.length())
			var ev: Vector3 = _direct_bone_euler_deg[sk]
			var mirrored := Vector3(ev.x, -ev.y, -ev.z)
			_direct_bone_euler_deg[dst_name] = mirrored
			if current_vrm != null:
				current_vrm.direct_bone_overrides[dst_name] = Quaternion.from_euler(
					Vector3(deg_to_rad(mirrored.x), deg_to_rad(mirrored.y), deg_to_rad(mirrored.z))
				)
	_emit_state_changed()


static func _ax(axis: Vector3, deg: float) -> Quaternion:
	return Quaternion(axis, deg_to_rad(deg))


static func _quat_to_euler_deg(q: Quaternion) -> Array:
	var e: Vector3 = q.normalized().get_euler()
	return [rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)]


## transition_sec > 0 なら、今の姿勢からなめらかに移す。
## keep_animation = true なら、再生中のアニメーションを止めずに、その上へポーズを重ねる。
func apply_pose_preset(preset_name: String, transition_sec: float = 0.0, keep_animation: bool = false) -> void:
	if not keep_animation:
		stop_animation_internal()
	if transition_sec <= 0.0:
		reset_bones_pose()
	if current_vrm == null or preset_name == "t_pose" or preset_name == "reset":
		if transition_sec > 0.0:
			reset_bones_pose_smooth(transition_sec)
		_emit_state_changed()
		return

	var bones := {}
	var hips_pos := Vector3.ZERO
	match preset_name:
		"a_pose":
			bones = {
				"leftUpperArm": [0, 0, -45],
				"rightUpperArm": [0, 0, 45],
				"leftThumbProximal": [0, 15, 0],
				"rightThumbProximal": [0, -15, 0],
			}
		"attention":
			bones = {
				"leftUpperArm": [0, 0, -72],
				"rightUpperArm": [0, 0, 72],
				"leftLowerArm": [0, -8, -4],
				"rightLowerArm": [0, 8, 4],
			}
		"wave":
			# Friendly side wave beside right cheek/shoulder (clear of face), palm facing camera
			var r_ua: Quaternion = _ax(Vector3.UP, 14.0) * _ax(Vector3.BACK, 34.0) * _ax(Vector3.RIGHT, -82.0)
			var r_la: Quaternion = _ax(Vector3.BACK, 6.0) * _ax(Vector3.UP, 102.0)
			bones = {
				"spine": [0, -3, -3],
				"chest": [0, -3, -2],
				"head": [-2, 6, 6],
				"leftUpperArm": [0, 0, -56],
				"leftLowerArm": [0, -14, -6],
				"rightShoulder": [0, 0, 4],
				"rightUpperArm": _quat_to_euler_deg(r_ua),
				"rightLowerArm": _quat_to_euler_deg(r_la),
				"rightHand": [0, 0, -10],
			}
		"peace":
			# Clean V-sign beside right cheek using Z-axis finger curl & natural thumb tuck
			var r_ua_p: Quaternion = _ax(Vector3.UP, 24.0) * _ax(Vector3.BACK, 42.0) * _ax(Vector3.RIGHT, -76.0)
			var r_la_p: Quaternion = _ax(Vector3.BACK, 6.0) * _ax(Vector3.UP, 112.0)
			bones = {
				"spine": [0, 4, 2],
				"head": [-2, -8, -6],
				"leftUpperArm": [0, 0, -56],
				"leftLowerArm": [0, -16, -6],
				"rightUpperArm": _quat_to_euler_deg(r_ua_p),
				"rightLowerArm": _quat_to_euler_deg(r_la_p),
				"rightHand": [0, 12, -4],
				"rightIndexProximal": [0, 10, 0],
				"rightMiddleProximal": [0, -10, 0],
				"rightThumbMetacarpal": [-8, -46, 18],
				"rightThumbProximal": [-6, -34, 26],
				"rightThumbDistal": [0, -16, 34],
				"rightRingProximal": [0, 0, 80],
				"rightRingIntermediate": [0, 0, 95],
				"rightRingDistal": [0, 0, 75],
				"rightLittleProximal": [0, 0, 80],
				"rightLittleIntermediate": [0, 0, 95],
				"rightLittleDistal": [0, 0, 75],
			}
		"sit":
			hips_pos = Vector3(0.0, -0.38, -0.08)
			bones = {
				"hips": [-5, 0, 0],
				"spine": [4, 0, 0],
				"chest": [3, 0, 0],
				"leftUpperLeg": [-85, 6, 4],
				"rightUpperLeg": [-85, -6, -4],
				"leftLowerLeg": [88, 0, 0],
				"rightLowerLeg": [88, 0, 0],
				"leftFoot": [-5, 0, 0],
				"rightFoot": [-5, 0, 0],
				"leftUpperArm": [18, -20, -52],
				"rightUpperArm": [18, 20, 52],
				"leftLowerArm": [0, -48, -15],
				"rightLowerArm": [0, 48, 15],
			}
		"hands_on_hips":
			# Lower upper arms around +Z (-46/+46) and roll +X (+58) so bent elbows rest hands on waist sides
			var l_ua_h: Quaternion = _ax(Vector3.UP, -4.0) * _ax(Vector3.BACK, -46.0) * _ax(Vector3.RIGHT, 58.0)
			var r_ua_h: Quaternion = _ax(Vector3.UP, 4.0) * _ax(Vector3.BACK, 46.0) * _ax(Vector3.RIGHT, 58.0)
			bones = {
				"spine": [-2, 0, 0],
				"head": [2, 0, 0],
				"leftUpperArm": _quat_to_euler_deg(l_ua_h),
				"rightUpperArm": _quat_to_euler_deg(r_ua_h),
				"leftLowerArm": [0, -114, 0],
				"rightLowerArm": [0, 114, 0],
				"leftHand": [0, 12, -26],
				"rightHand": [0, -12, 26],
			}

	var spec_bones := {}
	for k in bones.keys():
		spec_bones[k] = {"euler_deg": bones[k]}
	var pose_params: Dictionary = {"bones": spec_bones}
	if transition_sec > 0.0:
		pose_params["transition_sec"] = transition_sec
		pose_params["clear_others"] = true
	if hips_pos.length_squared() > 1e-8:
		pose_params["hips_position"] = [hips_pos.x, hips_pos.y, hips_pos.z]
	set_bones_pose(pose_params)
	_emit_state_changed()


func reset_all_settings() -> void:
	reset_model_transform()
	lighting_rig.apply_preset("studio")
	post_effects.apply_preset("none")
	post_effects.reset_shade()
	post_effects.apply_shade_to(current_vrm)
	lighting_rig.apply_params({"exposure": 1.0, "bloom_intensity": 0.25, "wind": [0.0, 0.0, 0.0]})
	set_spring_bone_params({"enabled": true, "gravity_scale": 1.0, "stiffness_scale": 1.0, "wind": [0.0, 0.0, 0.0]})
	if current_vrm != null:
		camera_rig.auto_frame(current_vrm.get_approx_bounds())
	else:
		camera_rig.apply_preset("full_body", 1.6)
	camera_rig.apply_params({"fov_deg": 35.0, "orthographic": false})
	bg_manager.restore_normal_window()
	bg_manager.apply_background({"color": "#1e222b", "gradient_bottom": "#0f1218"})
	bg_manager.apply_output_viewport({"width": 1280, "height": 720, "background_mode": "transparent", "color": "#00ff00"})
	procedural_idle.apply_params({"enabled": true, "breathing": true, "blink": true, "saccade": true, "sway": true, "intensity": 1.0})
	set_first_person_mode(false)
	set_lookat_params({"mode": "camera", "target": [0.0, 1.4, 2.0]})
	reset_expressions(0.1)
	reset_bones_pose()
	_emit_state_changed()


# ---------------------------------------------------------------------------
# Webカメラトラッキング (別プロセス → VMC)
# ---------------------------------------------------------------------------

func start_tracking() -> Dictionary:
	if not tracking.is_installed():
		return tracking.start(osc_port)
	if bridge == null or not bridge.is_servers_running():
		return {"ok": false, "error": "OSC/VMC 受信サーバーが動いていません"}
	_clear_vmc_pose()
	var r: Dictionary = tracking.start(osc_port)
	state_changed.emit()
	return r


## トラッキング設定を変える。モード・カメラ等を変えたときは動作中なら再起動する。
func apply_tracking_settings(d: Dictionary) -> void:
	if tracking.apply_settings(d):
		stop_tracking()
		start_tracking()
	else:
		state_changed.emit()


func _clear_vmc_pose() -> void:
	if current_vrm != null:
		current_vrm.vmc_bone_overrides.clear()
		current_vrm.force_camera_gaze = false
		current_vrm.has_vmc_hips_offset = false


func stop_tracking() -> void:
	tracking.stop()
	if current_vrm != null:
		current_vrm.vmc_bone_overrides.clear()
		current_vrm.force_camera_gaze = false
		current_vrm.has_vmc_hips_offset = false
	state_changed.emit()


# ---------------------------------------------------------------------------
# 操作不能の防止 (モデル未表示時の窓状態の解除・タスクトレイ)
# ---------------------------------------------------------------------------

## モデルが表示されていないのに透過・枠なし・クリックスルー・最前面だと、
## 画面に何も見えず操作もできなくなるので、通常のウィンドウへ戻す。
func _ensure_operable_window() -> void:
	if current_vrm != null:
		return
	var bm = bg_manager
	if bm.win_transparent or bm.win_borderless or bm.win_click_through or bm.win_always_on_top or bm.bg_mode == "transparent_window":
		bm.restore_normal_window()
		print("No VRM shown: window restored to normal (transparent/borderless/click-through off)")
		if settings_window != null and settings_window.has_method("show_snackbar"):
			settings_window.show_snackbar("モデルが表示されていないため、透過・枠なし・クリックスルー・最前面を解除しました。", "", Callable(), 8.0)


var _tray: StatusIndicator = null
var _tray_menu: PopupMenu = null


## タスクトレイ (通知領域) のアイコン。クリックスルー中でもここから設定を開ける。
func _build_tray_icon() -> void:
	if DisplayServer.get_name() == "headless" or not DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR):
		return
	_tray_menu = PopupMenu.new()
	_tray_menu.theme = UiThemeScript.get_theme()
	_tray_menu.add_item("設定ウィンドウを開く  (Ctrl+Shift+S)", 0)
	_tray_menu.add_item("クリックスルーを解除", 1)
	_tray_menu.add_item("通常のウィンドウに戻す", 2)
	_tray_menu.add_separator()
	_tray_menu.add_item("終了", 9)
	_tray_menu.id_pressed.connect(_on_tray_menu)
	add_child(_tray_menu)

	_tray = StatusIndicator.new()
	_tray.tooltip = "うつしみらー — クリックで設定ウィンドウ / 右クリックでメニュー"
	_tray.icon = _make_tray_texture()
	_tray.pressed.connect(func(button: int, _pos: Vector2i):
		if button == MOUSE_BUTTON_LEFT:
			open_settings_window()
	)
	add_child(_tray)
	_tray.menu = _tray.get_path_to(_tray_menu)  # ツリーに入れてから設定する


func _on_tray_menu(id: int) -> void:
	match id:
		0:
			open_settings_window()
		1:
			bg_manager.apply_window({"click_through": false})
		2:
			bg_manager.restore_normal_window()
			open_settings_window()
		9:
			get_tree().quit()


static func _make_tray_texture() -> ImageTexture:
	# アプリのアイコン (res://icon.png) を縮めて使う。読めないときは下の手描きの図にする
	var tex := load("res://icon.png") as Texture2D
	if tex != null:
		var icon_img := tex.get_image()
		if icon_img != null:
			icon_img = icon_img.duplicate()
			if icon_img.is_compressed():
				icon_img.decompress()
			icon_img.resize(32, 32, Image.INTERPOLATE_LANCZOS)
			return ImageTexture.create_from_image(icon_img)
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var red := Color("#c8252e")
	for y in n:
		for x in n:
			var c := Color(0, 0, 0, 0)
			var cx := clampf(x + 0.5, 6.0, n - 6.0)
			var cy := clampf(y + 0.5, 6.0, n - 6.0)
			if Vector2(x + 0.5 - cx, y + 0.5 - cy).length() <= 6.0:
				c = Color("#15171c")
				# 中央に赤い人型 (頭と体)
				if Vector2(x + 0.5 - 16, y + 0.5 - 10).length() <= 4.2:
					c = red
				elif y >= 15 and y <= 26 and absf(x + 0.5 - 16) <= 3.0 + (y - 15) * 0.45:
					c = red
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------------
# 通知 (メイン画面のトースト + 設定ウィンドウのスナックバー)
# ---------------------------------------------------------------------------

var _toast: PanelContainer = null
var _toast_lbl: Label = null
var _toast_btn: Button = null
var _toast_action: Callable
var _toast_timer: Timer = null


## 利用者に知らせる。設定ウィンドウが開いていればそちらのスナックバーにも出す。
## メイン画面のトーストは画面 (ウィンドウ) にだけ出て、撮影・録画・OBS 出力には写らない。
func notify(message: String, action_text: String = "", action: Callable = Callable(), seconds: float = 6.0) -> void:
	print("[notify] ", message)
	if settings_window != null and settings_window.visible and settings_window.has_method("show_snackbar"):
		settings_window.show_snackbar(message, action_text, action, seconds)
	_show_main_toast(message, action_text, action, seconds)


func _show_main_toast(message: String, action_text: String, action: Callable, seconds: float) -> void:
	if _toast_layer == null or DisplayServer.get_name() == "headless":
		return
	if _toast == null:
		var holder := MarginContainer.new()
		holder.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		holder.offset_top = -96
		holder.add_theme_constant_override("margin_left", 24)
		holder.add_theme_constant_override("margin_right", 24)
		holder.add_theme_constant_override("margin_bottom", 20)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.theme = UiThemeScript.get_theme()
		_toast_layer.add_child(holder)
		var toast_res: Dictionary = preload("res://scripts/ui/ui_widgets.gd").make_toast_panel()
		_toast = toast_res["panel"]
		_toast.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_toast.size_flags_vertical = Control.SIZE_SHRINK_END
		holder.add_child(_toast)
		var hb: HBoxContainer = toast_res["hbox"]
		hb.add_theme_constant_override("separation", 12)
		_toast_lbl = Label.new()
		_toast_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hb.add_child(_toast_lbl)
		_toast_btn = Button.new()
		_toast_btn.theme_type_variation = "AccentButton"
		_toast_btn.pressed.connect(func():
			_toast.visible = false
			if _toast_action.is_valid():
				_toast_action.call()
		)
		hb.add_child(_toast_btn)
		_toast_timer = Timer.new()
		_toast_timer.one_shot = true
		_toast_timer.timeout.connect(func(): _toast.visible = false)
		add_child(_toast_timer)
	_toast_lbl.text = message
	_toast_btn.text = action_text
	_toast_btn.visible = action_text != ""
	_toast_action = action
	_toast.visible = true
	_toast_timer.start(maxf(seconds, 1.0))


## スクリーンショットを撮り、保存先を知らせる (F11・右クリックメニュー・設定画面から共通)。
func take_screenshot() -> Dictionary:
	var r: Dictionary = await capture_manager.capture_screenshot({})
	if r.get("ok", false):
		var path := str(r.get("path", ""))
		last_screenshot_path = path
		notify("📷 スクリーンショットを保存しました: %s" % path.get_file(), "フォルダを開く",
			func(): OS.shell_show_in_file_manager(path), 6.0)
	else:
		notify("スクリーンショットに失敗しました: %s" % str(r.get("error", "")), "", Callable(), 8.0)
	_emit_state_changed()
	return r


var last_screenshot_path: String = ""


func get_screenshots_dir() -> String:
	return capture_manager._resolve_output_path(capture_manager.screenshots_dir)


func get_capture_dir(sub: String) -> String:
	if capture_manager == null:
		return ""
	var raw: String = capture_manager.recordings_dir if sub == "recordings" else capture_manager.screenshots_dir
	return str(capture_manager._resolve_output_path(raw))


# ---------------------------------------------------------------------------
# 画面効果 (ポストエフェクト) とモデルの陰影
# ---------------------------------------------------------------------------

## {"style": "cinema", "strength": 0.8, "vignette": 0.3, "shade_shift": 0.1, ...}
func apply_effects(d: Dictionary) -> void:
	post_effects.apply_params(d)
	post_effects.apply_shade_to(current_vrm)
	state_changed.emit()


## シェーダーページの設定 (画面効果・モデルの陰影・落ち影) だけをファイルへ書き出す。
const EFFECTS_FILE_KIND := "utsushimirror-shader"
const EFFECTS_SHADOW_KEYS := ["shadows_enabled", "shadow_opacity", "shadow_softness", "shadow_blur", "shadow_quality",
	"shadow_bias", "shadow_normal_bias", "shadow_distance"]


func effects_file_dict() -> Dictionary:
	var lt: Dictionary = lighting_rig.to_dict()
	var shadow := {}
	for k in EFFECTS_SHADOW_KEYS:
		if lt.has(k):
			shadow[k] = lt[k]
	return {"kind": EFFECTS_FILE_KIND, "version": 1, "effects": post_effects.to_dict(), "shadow": shadow}


func export_effects(path: String) -> Dictionary:
	if path.get_extension() == "":
		path += ".umshader"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": error_string(FileAccess.get_open_error())}
	f.store_string(JSON.stringify(effects_file_dict(), "	"))
	f.close()
	return {"ok": true, "path": path}


## シェーダー設定のファイル (.umshader) か、設定ファイル (.umset) のシェーダーの部分だけを読み込む。
func import_effects(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "ファイルがありません"}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return {"ok": false, "error": "シェーダー設定のファイルではありません"}
	var kind := str(data.get("kind", ""))
	if kind == SETTINGS_FILE_KIND or (kind == "" and data.has("version") and data.has("camera")):
		# 設定ファイル (.umset) からは、シェーダーの部分 (画面効果と落ち影) だけを取り出す
		var lt = data.get("lighting", {})
		data = {"effects": data.get("effects"), "shadow": lt if typeof(lt) == TYPE_DICTIONARY else {}}
	elif kind != EFFECTS_FILE_KIND:
		return {"ok": false, "error": "シェーダー設定のファイルではありません"}
	if typeof(data.get("effects")) == TYPE_DICTIONARY:
		post_effects.load_dict(data["effects"])
		post_effects.apply_shade_to(current_vrm)
	if typeof(data.get("shadow")) == TYPE_DICTIONARY:
		var sh := {}
		for k in EFFECTS_SHADOW_KEYS:
			if data["shadow"].has(k):
				sh[k] = data["shadow"][k]
		lighting_rig.apply_params(sh)
	state_changed.emit()
	return {"ok": true}
