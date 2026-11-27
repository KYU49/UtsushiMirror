extends RefCounted
## FFmpeg (録画・リップシンクの音の重ね書き・音声の読み込みに使う) の有無と、アプリのフォルダへのインストール。
## 探す順番は Rust 側 (ffmpeg.rs) が決める: 環境変数 VRMVIEWER_FFMPEG → アプリの tools\ffmpeg → PATH。
## 利用者の PATH やレジストリは変えない。

signal installation_finished(ok: bool)

const ConfigManagerScript := preload("res://scripts/core/config_manager.gd")
const INSTALL_SCRIPT := "scripts/install_ffmpeg.ps1"
## 入れる版 (scripts/install_ffmpeg.ps1 の $Version と合わせる)
const VERSION := "9.1"
## ダウンロードの大きさ (MB) と、入れたあとの大きさ (MB) の目安
const DOWNLOAD_MB := 114
const INSTALLED_MB := 100

var bridge = null
var install_step := ""  # "" | "starting" | "download" | "verify" | "extract" | "done" | "error"
var install_progress := 0
var install_error := ""
var _status: Dictionary = {}
var _pid := -1
var _log := ""
var _pos := 0
var _partial := ""


func setup(b) -> void:
	bridge = b
	if bridge != null:
		bridge.set_ffmpeg_app_dir(app_dir().replace("/", "\\") if OS.get_name() == "Windows" else app_dir())
	refresh()


func app_dir() -> String:
	return ConfigManagerScript.get_app_root_dir()


## 有無を調べ直す (PATH を通したあと・インストールのあとなど)
func refresh() -> Dictionary:
	_status = bridge.ffmpeg_status() if bridge != null else {}
	return _status


func status() -> Dictionary:
	return _status


func is_available() -> bool:
	return bool(_status.get("available", false))


func is_installing() -> bool:
	return _pid > 0 and OS.is_process_running(_pid)


func start_install() -> Dictionary:
	if is_installing():
		return {"ok": true}
	if OS.get_name() != "Windows":
		return {"ok": false, "error": "自動のインストールは Windows だけです。FFmpeg を入れて PATH を通してください。"}
	var script := app_dir().path_join(INSTALL_SCRIPT)
	if not FileAccess.file_exists(script):
		install_step = "error"
		install_error = "インストール用のファイルがありません: " + script
		return {"ok": false, "error": install_error}
	var data_dir := ProjectSettings.globalize_path(ConfigManagerScript.resolve_path()).get_base_dir()
	DirAccess.make_dir_recursive_absolute(data_dir)
	_log = data_dir.path_join("ffmpeg_install.log")
	var f := FileAccess.open(_log, FileAccess.WRITE)
	if f != null:
		f.close()
	_pos = 0
	_partial = ""
	install_error = ""
	install_progress = 0
	_pid = OS.create_process("powershell.exe", PackedStringArray(["-NoProfile", "-ExecutionPolicy", "Bypass",
		"-File", script.replace("/", "\\"), "-Log", _log.replace("/", "\\"), "-AppDir", app_dir().replace("/", "\\")]), false)
	if _pid <= 0:
		install_step = "error"
		install_error = "PowerShell を起動できませんでした"
		return {"ok": false, "error": install_error}
	install_step = "starting"
	return {"ok": true}


## 毎フレーム呼ぶ。インストールが終わったら installation_finished を出す
func poll() -> void:
	if _pid <= 0:
		return
	_read_log()
	var finished := install_step in ["done", "error"]
	if not finished and not is_installing():
		_read_log()
		if _partial.strip_edges() != "":
			_on_line(_partial.strip_edges())
			_partial = ""
		if not install_step in ["done", "error"]:
			install_step = "error"
			install_error = "インストールが途中で終わりました"
		finished = true
	if finished:
		_pid = -1
		refresh()
		if install_step == "done" and not is_available():
			install_step = "error"
			install_error = "ffmpeg.exe が見つかりません"
		installation_finished.emit(install_step == "done")


func _read_log() -> void:
	var f := FileAccess.open(_log, FileAccess.READ)
	if f == null:
		return
	var n := f.get_length()
	if n > _pos:
		f.seek(_pos)
		var text := _partial + f.get_buffer(n - _pos).get_string_from_utf8()
		_pos = n
		var lines := text.split("\n")
		_partial = lines[lines.size() - 1]
		for i in lines.size() - 1:
			_on_line(lines[i].strip_edges())
	f.close()


func _on_line(line: String) -> void:
	if line.begins_with("@@STEP "):
		install_step = line.substr(7).strip_edges()
	elif line.begins_with("@@PROGRESS "):
		install_progress = int(line.substr(11))
	elif line == "@@DONE":
		install_step = "done"
	elif line.begins_with("@@ERROR "):
		install_step = "error"
		install_error = line.substr(8)


## 進み具合の文 (画面に出す)
func progress_text() -> String:
	match install_step:
		"starting":
			return "準備しています..."
		"download":
			return "ダウンロードしています... %d%%" % install_progress
		"verify":
			return "ファイルを確かめています..."
		"extract":
			return "展開しています..."
		"error":
			return "エラー: " + install_error
	return ""
