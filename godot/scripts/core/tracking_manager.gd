extends RefCounted

## Webカメラトラッカー (tracker/vrm_tracker.py) の起動・停止と設定を管理する。
## トラッカーは別プロセスで動き、VMC Protocol で本体の OSC ポートへ送る。
## カメラ画像は本体には一切届かない (届くのはボーン回転と表情の数値、状態の数値だけ)。
##
## 設定は 2 種類:
##  - 起動時に決まるもの (モード・カメラ・解像度など) … 変えるとトラッカーを再起動する
##  - 動作中に変えられるもの (LIVE_KEYS) … 制御ポート (UDP JSON) で即時反映
## キャリブレーション結果はトラッカーが設定ファイルと同じフォルダの JSON に保存する。

## インストールが終わった (ok = 成功)
signal installation_finished(ok: bool)

const ConfigManagerScript := preload("res://scripts/core/config_manager.gd")

const DEFAULTS := {
	# 起動時に決まるもの
	"mode": "upper",          # face=顔だけ / upper=顔と手 / full=全身 / custom=部位を個別に
	"camera": "auto",
	"resolution": "1280x720",
	"fps": 30,
	"pose_model": "full",     # lite / full / heavy
	"confidence": 0.5,
	"face": true,             # custom のときの部位
	"hands": true,
	"pose": true,
	"legs": false,
	"mirror": true,
	"preview": true,
	# 動作中に変えられるもの
	"smooth": 0.85,
	"stabilize": 0.5,
	"responsiveness": 0.5,
	"head_gain": 1.0,
	"body_follow": 0.35,
	"gaze": true,
	"gaze_mode": "track",  # 視線: "track" = 目の動きに合わせる / "camera" = カメラ目線 / "fixed" = 正面で固定
	"gaze_gain": 1.0,
	"gaze_link": true,
	"gaze_limit_h": 25.0,
	"gaze_limit_up": 15.0,
	"gaze_limit_down": 12.0,
	"blink_link": false,
	"blink_sens": 0.5,
	"mouth_gain": 1.0,
	"expressions": true,
	"happy_sens": 0.2,
	"happy_gain": 0.5,
	"angry_sens": 0.5,
	"angry_gain": 0.8,
	"surprised_sens": 0.5,
	"surprised_gain": 0.8,
	"fingers": true,
	"forearm_twist": 0.7,
	"arm_from_hand": true,
	"shoulder_gain": 1.0,
	"shoulder_sens": 0.5,
	"hand_edge": 0.03,
	"arms_rest": true,
	"lost_hold": 0.5,
	"lost_return": 0.6,
	"hips_move": true,
	# キャリブレーション
	"calib_delay": 0,
}
const LIVE_KEYS := ["mirror", "smooth", "stabilize", "responsiveness", "head_gain", "body_follow", "gaze", "gaze_mode", "gaze_gain",
	"gaze_link", "gaze_limit_h", "gaze_limit_up", "gaze_limit_down", "blink_link", "blink_sens", "mouth_gain", "expressions", "happy_sens", "happy_gain", "angry_sens", "angry_gain",
	"surprised_sens", "surprised_gain", "fingers", "forearm_twist", "arm_from_hand", "shoulder_gain", "shoulder_sens", "hand_edge", "arms_rest",
	"lost_hold", "lost_return", "hips_move"]
const NO_RESTART_KEYS := ["calib_delay"]
const MODES := {
	"face": {"label": "顔だけ", "parts": [true, false, false, false]},
	"upper": {"label": "顔と手 (上半身)", "parts": [true, true, true, false]},
	"full": {"label": "全身", "parts": [true, true, true, true]},
	"custom": {"label": "カスタム", "parts": []},
}

var settings: Dictionary = DEFAULTS.duplicate(true)
var cameras: Array = []  # [{index, name}]
var last_error: String = ""
var status: Dictionary = {}       # トラッカーからの最新の状態 (fps・検出・明るさ・補正)
var control_port: int = 39540
var _pid: int = -1
var _udp := PacketPeerUDP.new()
var _udp_ready := false
var _next_poll_msec := 0
var _last_status_msec := 0

# ---- トラッキング用のシステム (uv と tracker\.venv) のインストール
## 使う容量の目安 (MB): アプリのフォルダ (.venv) と、ユーザーのフォルダ (uv の Python とダウンロードのキャッシュ)
const INSTALL_APP_MB := 400
const INSTALL_USER_MB := 500
const INSTALL_SCRIPT := "install_tracker.ps1"
var install_step := ""  # "" | "starting" | "uv" | "sync" | "done" | "error"
var install_error := ""
var install_last_line := ""
var _inst_pid := -1
var _inst_log := ""
var _inst_pos := 0
var _inst_partial := ""


func _tracker_dir() -> String:
	var env_dir := OS.get_environment("VRMVIEWER_TRACKER_DIR")  # テスト用
	if env_dir != "":
		return env_dir.replace("\\", "/")
	return ConfigManagerScript.get_app_root_dir().path_join("tracker")


func _data_dir() -> String:
	# 既定の設定は user:// なので、Python へ渡せる実際のパスに直す
	return ProjectSettings.globalize_path(ConfigManagerScript.resolve_path()).get_base_dir()


func settings_file() -> String:
	return _data_dir().path_join("tracker_settings.json")


func calib_file() -> String:
	return _data_dir().path_join("tracker_calibration.json")


func find_python() -> String:
	var env_py := OS.get_environment("VRMVIEWER_PYTHON")
	if env_py != "":
		return env_py
	var d := _tracker_dir()
	for rel in [".venv/Scripts/python.exe", ".venv/bin/python3", ".venv/bin/python"]:
		var p := d.path_join(rel)
		if FileAccess.file_exists(p):
			return p
	return "python" if OS.get_name() == "Windows" else "python3"


func script_path() -> String:
	return _tracker_dir().path_join("vrm_tracker.py")


## トラッキング用のシステム (Python の環境) が入っているか
func is_installed() -> bool:
	if OS.get_environment("VRMVIEWER_PYTHON") != "":
		return true
	var d := _tracker_dir()
	for rel in [".venv/Scripts/python.exe", ".venv/bin/python3", ".venv/bin/python"]:
		if FileAccess.file_exists(d.path_join(rel)):
			return true
	return false


## uv の場所 (見つからなければ "")
func find_uv() -> String:
	var out: Array = []
	if OS.get_name() == "Windows" and OS.execute("where.exe", PackedStringArray(["uv"]), out, true) == 0 and not out.is_empty():
		var first := str(out[0]).strip_edges().split("\n")[0].strip_edges()
		if first != "" and FileAccess.file_exists(first):
			return first
	var home := OS.get_environment("USERPROFILE")
	var local := OS.get_environment("LOCALAPPDATA")
	for p in [home.path_join(".local/bin/uv.exe"), local.path_join("Microsoft/WinGet/Links/uv.exe"), home.path_join(".cargo/bin/uv.exe")]:
		if home != "" and FileAccess.file_exists(p):
			return p
	return ""


static func _free_mb(path: String) -> int:
	var da := DirAccess.open(path)
	if da == null:
		return -1
	return int(da.get_space_left() / (1024 * 1024))


## インストール前の案内に出す情報
func install_info() -> Dictionary:
	var tdir := _tracker_dir()
	var home := OS.get_environment("USERPROFILE")
	var app_drive := tdir.substr(0, 2).to_upper()
	var user_drive := home.substr(0, 2).to_upper() if home != "" else app_drive
	var uv := find_uv()
	return {
		"tracker_dir": tdir.replace("/", "\\"),
		"script_found": FileAccess.file_exists(tdir.path_join(INSTALL_SCRIPT)),
		"uv_found": uv != "",
		"uv_path": uv,
		"app_drive": app_drive,
		"user_drive": user_drive,
		"same_drive": app_drive == user_drive,
		"app_free_mb": _free_mb(tdir),
		"user_free_mb": _free_mb(home) if home != "" else -1,
		"app_need_mb": INSTALL_APP_MB,
		"user_need_mb": INSTALL_USER_MB,
	}


func is_installing() -> bool:
	return _inst_pid > 0 and OS.is_process_running(_inst_pid)


func install_log_path() -> String:
	return _inst_log


## uv が無ければ uv を入れ、tracker フォルダで uv sync する (別のプロセスで動かし、poll() で進み具合を読む)
func start_install() -> Dictionary:
	if is_installing():
		return {"ok": true}
	if OS.get_name() != "Windows":
		return {"ok": false, "error": "自動のインストールは Windows だけです。README の手順で uv sync してください。"}
	var script := _tracker_dir().path_join(INSTALL_SCRIPT)
	if not FileAccess.file_exists(script):
		install_step = "error"
		install_error = "インストール用のファイルがありません: " + script
		return {"ok": false, "error": install_error}
	DirAccess.make_dir_recursive_absolute(_data_dir())
	_inst_log = _data_dir().path_join("tracker_install.log")
	var f := FileAccess.open(_inst_log, FileAccess.WRITE)
	if f != null:
		f.close()
	_inst_pos = 0
	_inst_partial = ""
	install_error = ""
	install_last_line = ""
	_inst_pid = OS.create_process("powershell.exe", PackedStringArray(["-NoProfile", "-ExecutionPolicy", "Bypass",
		"-File", script.replace("/", "\\"), "-Log", _inst_log.replace("/", "\\")]), false)
	if _inst_pid <= 0:
		install_step = "error"
		install_error = "PowerShell を起動できませんでした"
		return {"ok": false, "error": install_error}
	install_step = "starting"
	return {"ok": true}


## インストールの進み具合をログから読む。終わった (成功・失敗) ときに true
func _poll_install() -> bool:
	var f := FileAccess.open(_inst_log, FileAccess.READ)
	if f != null:
		var n := f.get_length()
		if n > _inst_pos:
			f.seek(_inst_pos)
			var text := _inst_partial + f.get_buffer(n - _inst_pos).get_string_from_utf8()
			_inst_pos = n
			var lines := text.split("\n")
			_inst_partial = lines[lines.size() - 1]
			for i in lines.size() - 1:
				_on_install_line(lines[i].strip_edges())
		f.close()
	if install_step in ["done", "error"]:
		_inst_pid = -1
		return true
	if not is_installing():
		_inst_pid = -1
		if _inst_partial.strip_edges() != "":
			_on_install_line(_inst_partial.strip_edges())
			_inst_partial = ""
		if install_step != "done" and install_step != "error":
			install_step = "error"
			install_error = "インストールが途中で終わりました"
		return true
	return false


func _on_install_line(line: String) -> void:
	if line == "":
		return
	if line.begins_with("@@STEP "):
		install_step = line.substr(7).strip_edges()
	elif line == "@@DONE":
		install_step = "done" if is_installed() else "error"
		if install_step == "error":
			install_error = "Python の環境ができていません"
	elif line.begins_with("@@ERROR "):
		install_step = "error"
		install_error = line.substr(8)
	elif line.begins_with("@@UV "):
		pass
	else:
		install_last_line = line


func is_running() -> bool:
	return _pid > 0 and OS.is_process_running(_pid)


## 今のモードで使う部位 [顔, 手, 体, 脚]
func parts() -> Array:
	var m: String = str(settings.mode)
	if MODES.has(m) and m != "custom":
		return MODES[m].parts
	return [bool(settings.face), bool(settings.hands), bool(settings.pose) or bool(settings.hands) or bool(settings.legs), bool(settings.legs)]


func _live_dict() -> Dictionary:
	var d := {}
	for k in LIVE_KEYS:
		d[k] = settings[k]
	return d


func _write_settings_file() -> void:
	DirAccess.make_dir_recursive_absolute(_data_dir())
	var f := FileAccess.open(settings_file(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_live_dict(), "\t"))
		f.close()


func start(osc_port: int) -> Dictionary:
	if is_running():
		return {"ok": true, "pid": _pid}
	if not is_installed():
		last_error = "トラッキング用のシステムが入っていません。設定画面の「トラッキング」ページからインストールしてください。"
		return {"ok": false, "error": last_error, "not_installed": true}
	if not FileAccess.file_exists(script_path()):
		last_error = "トラッカーが見つかりません: " + script_path()
		return {"ok": false, "error": last_error}
	_write_settings_file()
	var res: PackedStringArray = str(settings.resolution).split("x")
	var w := int(res[0]) if res.size() == 2 else 1280
	var h := int(res[1]) if res.size() == 2 else 720
	var args := PackedStringArray([script_path(), "--port", str(osc_port), "--camera", str(settings.camera),
		"--control-port", str(control_port), "--mode", str(settings.mode),
		"--width", str(w), "--height", str(h), "--fps", str(int(settings.fps)),
		"--pose-model", str(settings.pose_model), "--detect-confidence", str(float(settings.confidence)),
		"--settings-file", settings_file(), "--calib-file", calib_file()])
	if str(settings.mode) == "custom":
		if not settings.face:
			args.append("--no-face")
		if not settings.hands:
			args.append("--no-hands")
		if not settings.pose:
			args.append("--no-pose")
		if settings.legs:
			args.append("--legs")
	if not settings.mirror:
		args.append("--no-mirror")
	if not settings.preview:
		args.append("--no-preview")
	_pid = OS.create_process(find_python(), args, false)
	if _pid <= 0:
		last_error = "Python を起動できません (%s)" % find_python()
		return {"ok": false, "error": last_error}
	last_error = ""
	status = {}
	_last_status_msec = 0
	return {"ok": true, "pid": _pid}


func stop() -> void:
	if is_running():
		_send({"cmd": "stop"})
		OS.kill(_pid)
	_pid = -1
	status = {}


func refresh_cameras() -> Array:
	var out: Array = []
	var code := OS.execute(find_python(), PackedStringArray([script_path(), "--list-cameras"]), out, true)
	cameras.clear()
	if code == 0 and out.size() > 0:
		for line in str(out[0]).split("\n"):
			var parsed = JSON.parse_string(line.strip_edges())
			if typeof(parsed) == TYPE_DICTIONARY and parsed.has("cameras"):
				for c in parsed["cameras"]:
					if typeof(c) == TYPE_DICTIONARY:
						cameras.append(c)
					else:
						cameras.append({"index": int(c), "name": "Camera %d" % int(c)})
	else:
		last_error = "カメラ一覧を取得できません (Python 環境を確認してください)"
	return cameras


## 設定を反映する。戻り値: トラッカーの再起動が必要なら true
func apply_settings(d: Dictionary) -> bool:
	d = d.duplicate()
	# 視線の選び方 (gaze_mode) から、トラッカーが目を動かすか (gaze) を決める。
	# 以前の設定 (gaze だけ) で「動かさない」になっていたら「目線固定」とみなす。
	if d.has("gaze_mode"):
		var gm := str(d["gaze_mode"])
		if not (gm in ["track", "camera", "fixed"]):
			gm = "track"
		d["gaze_mode"] = gm
		d["gaze"] = gm == "track"
	elif d.has("gaze"):
		if not bool(d["gaze"]):
			d["gaze_mode"] = "fixed"
		elif str(settings.get("gaze_mode", "track")) != "track":
			d["gaze_mode"] = "track"
	var restart := false
	var live := {}
	for k in d.keys():
		if not settings.has(k):
			continue
		var v = d[k]
		if typeof(DEFAULTS[k]) == TYPE_BOOL:
			v = bool(v)
		elif typeof(DEFAULTS[k]) == TYPE_FLOAT:
			v = float(v)
		elif typeof(DEFAULTS[k]) == TYPE_INT:
			v = int(v)
		else:
			v = str(v)
		if settings[k] == v:
			continue
		settings[k] = v
		if k in LIVE_KEYS:
			live[k] = v
		elif not (k in NO_RESTART_KEYS):
			restart = true
	if k_mirror_needs_restart(live):
		restart = true
	if not live.is_empty() and is_running():
		_write_settings_file()
		_send({"cmd": "set", "params": live})
	return restart and is_running()


## ミラーはワイヤー表示とキャリブレーションの向きに関わるので、切り替えたら再起動する
func k_mirror_needs_restart(live: Dictionary) -> bool:
	return live.has("mirror")


func reset_settings() -> bool:
	var keep := {"camera": settings.camera}
	var d: Dictionary = DEFAULTS.duplicate(true)
	d.merge(keep, true)
	return apply_settings(d)


func calibrate() -> Dictionary:
	if not is_running():
		return {"ok": false, "error": "トラッキングを開始してから実行してください"}
	_send({"cmd": "calibrate", "delay": int(settings.calib_delay)})
	return {"ok": true, "delay": int(settings.calib_delay)}


func reset_calibration() -> void:
	if is_running():
		_send({"cmd": "reset_calibration"})
	elif FileAccess.file_exists(calib_file()):
		DirAccess.remove_absolute(calib_file())


## 保存済みキャリブレーションの日時 (なければ "")
func calibration_time() -> String:
	if status.has("calibrated_at") and is_running():
		return str(status.calibrated_at)
	if not FileAccess.file_exists(calib_file()):
		return ""
	var d = JSON.parse_string(FileAccess.get_file_as_string(calib_file()))
	return str(d.get("time", "")) if typeof(d) == TYPE_DICTIONARY else ""


func _send(obj: Dictionary) -> void:
	if not _udp_ready:
		_udp.connect_to_host("127.0.0.1", control_port)
		_udp_ready = true
	_udp.put_packet(JSON.stringify(obj).to_utf8_buffer())


## 毎フレーム呼ぶ。動作中は 0.25 秒ごとに状態を問い合わせる。
func poll() -> void:
	if _inst_pid > 0 and _poll_install():
		if install_step == "done" and last_error.contains("インストール"):
			last_error = ""
		installation_finished.emit(install_step == "done")
	if not is_running():
		if _pid > 0:
			_pid = -1
			status = {}
		return
	while _udp_ready and _udp.get_available_packet_count() > 0:
		var parsed = JSON.parse_string(_udp.get_packet().get_string_from_utf8())
		if typeof(parsed) == TYPE_DICTIONARY:
			status = parsed
			_last_status_msec = Time.get_ticks_msec()
	var now := Time.get_ticks_msec()
	if now >= _next_poll_msec:
		_next_poll_msec = now + 250
		_send({"cmd": "status"})
	if _last_status_msec > 0 and now - _last_status_msec > 3000:
		status = {}


func to_dict() -> Dictionary:
	return {
		"running": is_running(),
		"settings": settings.duplicate(),
		"cameras": cameras.duplicate(),
		"python": find_python(),
		"error": last_error,
		"status": status.duplicate(),
		"calibrated_at": calibration_time(),
		"installed": is_installed(),
		"install": {"step": install_step, "running": is_installing(), "error": install_error, "last_line": install_last_line},
	}
