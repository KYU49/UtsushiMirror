extends SceneTree
## トラッキング用のシステムが入っていないときの案内とインストールを確かめる。
## 実行 (利用者の環境を変えないよう、すべて一時の場所で):
##   VRMVIEWER_CONFIG=<一時ファイル> VRMVIEWER_TRACKER_DIR=<.venv の無い tracker の写し> TEST_OUT_DIR=<一時フォルダ>
##   [TEST_DO_INSTALL=1 で実際にインストールまで行う。USERPROFILE・LOCALAPPDATA・APPDATA・PATH も一時のものにし、
##    UV_NO_MODIFY_PATH=1 と UV_INSTALL_DIR を渡すこと]
##   godot --path godot -s res://scripts/tests/test_tracker_install.gd
var _m: Node
var _f := 0
var _ok := true
var _out := ""
var _installing := false
var _t0 := 0


func _check(name: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + name)
	_ok = _ok and cond


func _initialize() -> void:
	_out = OS.get_environment("TEST_OUT_DIR")
	_m = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_m)


func _process(_d: float) -> bool:
	_f += 1
	var sw = _m.settings_window if _m != null else null
	if _f == 20:
		var tm = _m.tracking
		_check("入っていないと分かる", not tm.is_installed())
		var r: Dictionary = _m.start_tracking()
		_check("入っていないと開始せずに案内する", not r.get("ok", true) and str(r.get("error", "")).contains("インストール"))
		sw.visible = true
		sw._select_tab("Tracking")
	if _f == 40:
		sw._refresh_tracking_install()
		_check("インストールの欄が出る", sw._trk_install_box.visible and sw._trk_install_btn.visible)
		_check("開始ボタンは隠れる", not sw._trk_start_row.visible)
		sw.get_texture().get_image().save_png(_out.path_join("install_box.png"))
		var info: Dictionary = _m.tracking.install_info()
		print("info ", info)
		_check("インストール用のファイルが見つかる", info.get("script_found", false))
		_check("空き容量が分かる", int(info.get("app_free_mb", -1)) > 0 and int(info.get("user_free_mb", -1)) > 0)
		var msg: Dictionary = sw.tracking_install_message(info)
		var text := str(msg.text)
		_check("案内に要求スペックがある", text.contains("要求スペック") and text.contains("メモリ"))
		_check("案内に空き容量がある", text.contains("必要な空き容量") and text.contains("今の空き"))
		_check("uv の案内は、uv が無いときだけ", text.contains("公式のインストーラー") == not bool(info.get("uv_found", false)))
		# 空きが足りないときはインストールできない
		var small := info.duplicate()
		small["app_free_mb"] = 10
		small["user_free_mb"] = 10
		_check("空きが足りないと止める", not bool(sw.tracking_install_message(small).enough))
		sw._show_tracking_install_dialog()
	if _f == 60:
		var dlg: ConfirmationDialog = sw._trk_install_dlg
		_check("案内のダイアログが出る", dlg.visible and not dlg.get_ok_button().disabled)
		dlg.get_texture().get_image().save_png(_out.path_join("install_dialog.png"))
		print("---- dialog ----\n", dlg.dialog_text, "\n----")
		if OS.get_environment("TEST_DO_INSTALL") != "1":
			dlg.hide()
			print("TEST_TRACKER_INSTALL_RESULT=", "PASS" if _ok else "FAIL")
			return true
		dlg.get_ok_button().pressed.emit()
		_installing = true
		_t0 = Time.get_ticks_msec()
	if _installing and _f % 120 == 0:
		var tm = _m.tracking
		print("[%ds] step=%s running=%s last=%s" % [(Time.get_ticks_msec() - _t0) / 1000, tm.install_step, tm.is_installing(), tm.install_last_line.left(100)])
		if _f == 240:
			sw._refresh_tracking_install()
			sw.get_texture().get_image().save_png(_out.path_join("install_progress.png"))
		if tm.install_step in ["done", "error"] and not tm.is_installing():
			_check("インストールが終わる", tm.install_step == "done")
			if tm.install_step == "error":
				print("error: ", tm.install_error, " log: ", tm.install_log_path())
			_check("入ったと分かる", tm.is_installed())
			_installing = false
			_f = 100000
	if _f == 100030:
		sw._refresh_tracking_install()
		_check("インストール後は開始ボタンに戻る", sw._trk_start_row.visible and not sw._trk_install_box.visible)
		_check("「入っていません」の知らせが消える", not str(sw._trk_status_lbl.text).contains("インストール"))
		sw.get_texture().get_image().save_png(_out.path_join("install_after.png"))
		print("TEST_TRACKER_INSTALL_RESULT=", "PASS" if _ok else "FAIL")
		return true
	if _installing and Time.get_ticks_msec() - _t0 > 20 * 60 * 1000:
		_check("20 分以内に終わる", false)
		print("TEST_TRACKER_INSTALL_RESULT=FAIL")
		return true
	return false
