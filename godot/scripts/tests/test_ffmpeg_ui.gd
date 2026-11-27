extends SceneTree
## 出力ページの「FFmpeg を入れる」の案内が、FFmpeg の有無で出たり消えたりするかを確かめる。
## 実行 (利用者の設定を変えないよう、設定は一時ファイルに):
##   VRMVIEWER_CONFIG=<一時ファイル> TEST_EXPECT_FFMPEG=1|0 godot --path godot -s res://scripts/tests/test_ffmpeg_ui.gd
##   TEST_EXPECT_FFMPEG=0 のときは PATH から ffmpeg を外し、VRMVIEWER_FFMPEG も消しておくこと
var _m: Node
var _f := 0
var _ok := true


func _check(name: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + name)
	_ok = _ok and cond


func _initialize() -> void:
	_m = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_m)


func _process(_d: float) -> bool:
	_f += 1
	if _f == 20:
		var expect := OS.get_environment("TEST_EXPECT_FFMPEG") == "1"
		var fm = _m.ffmpeg
		var st: Dictionary = fm.status()
		print("status: ", st)
		_check("有無を正しく調べる", fm.is_available() == expect)
		var sw = _m.settings_window
		sw.visible = true
		sw._select_tab("Output")
		var tab = sw._tab_handlers["Output"]
		tab.refresh_ffmpeg()
		if expect:
			_check("見つかれば案内を出さない", not tab._ff_box.visible)
			_check("見つかれば録画ボタンを押せる", not tab._btn_rec.disabled)
		else:
			_check("見つからなければ案内を出す", tab._ff_box.visible)
			_check("見つからなければ録画ボタンを止める", tab._btn_rec.disabled)
			_check("入れる場所はアプリのフォルダ", str(st.get("app_path", "")).replace("\\", "/").contains("tools/ffmpeg/bin/ffmpeg"))
			var out := OS.get_environment("TEST_OUT_DIR")
			if out != "":
				var r: Dictionary = _m.capture_manager.start_recording({"output_path": out.path_join("no_ffmpeg.mp4")})
				print("record: ", r)
				_check("録画を始めると入れ方を案内する", not r.get("ok", true) and str(r.get("error", "")).contains("FFmpeg を入れる"))
				if r.get("ok", false):
					_m.capture_manager.stop_recording()
	if _f == 30:
		print("RESULT ", "OK" if _ok else "NG")
		quit(0 if _ok else 1)
	return false
