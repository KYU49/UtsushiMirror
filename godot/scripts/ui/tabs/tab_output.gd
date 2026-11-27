extends RefCounted

const UiWidgets := preload("res://scripts/ui/ui_widgets.gd")

var _win
var _opt_res: OptionButton
var _sp_ow: SpinBox
var _sp_oh: SpinBox
var _opt_out_bg: OptionButton
var _cp_out: ColorPickerButton
var _lbl_out_img: Label
var _dlg_out_img: FileDialog

var _lbl_dirs: Label
var _opt_fmt: OptionButton
var _opt_fps: OptionButton
var _chk_rec_audio: CheckBox
var _btn_rec: Button
var _ff_box: VBoxContainer
var _ff_btn: Button
var _ff_lbl: Label
var _ff_dlg: ConfirmationDialog

var _chk_spout: CheckBox
var _edit_spout: LineEdit
var _chk_vcam: CheckBox
var _lbl_vcam: Label


func build(win, vb: VBoxContainer) -> void:
	_win = win
	var is_sync: Callable = win.is_syncing_fn()

	# ---- 出力解像度・背景
	var c_vp: Dictionary = UiWidgets.card(vb, "出力解像度・背景 (OBS / 録画 / スクショ共通)")
	_opt_res = UiWidgets.option_row(c_vp["body"], "解像度プリセット", [
		["1280x720", "1280×720 (HD 16:9)"],
		["1920x1080", "1920×1080 (Full HD 16:9)"],
		["2560x1440", "2560×1440 (WQHD)"],
		["1080x1920", "1080×1920 (縦型ショート)"],
		["custom", "カスタム"],
	], func(r: String):
		if _win.controller == null or r == "custom":
			return
		var parts := r.split("x")
		if parts.size() == 2:
			_win.controller.bg_manager.apply_output_viewport({"width": int(parts[0]), "height": int(parts[1])}),
		is_sync
	)

	var wh_row := UiWidgets.labeled_row(c_vp["body"], "幅 × 高さ (px)")
	_sp_ow = SpinBox.new()
	_sp_ow.min_value = 64
	_sp_ow.max_value = 7680
	_sp_ow.step = 16
	_sp_ow.custom_minimum_size.x = 96
	wh_row.add_child(_sp_ow)
	var x_lbl := Label.new()
	x_lbl.text = "×"
	wh_row.add_child(x_lbl)
	_sp_oh = SpinBox.new()
	_sp_oh.min_value = 64
	_sp_oh.max_value = 4320
	_sp_oh.step = 16
	_sp_oh.custom_minimum_size.x = 96
	wh_row.add_child(_sp_oh)
	var b_wh := Button.new()
	b_wh.text = "適用"
	b_wh.pressed.connect(func():
		if _win.controller != null:
			_win.controller.bg_manager.apply_output_viewport({"width": int(_sp_ow.value), "height": int(_sp_oh.value)})
	)
	wh_row.add_child(b_wh)

	_opt_out_bg = UiWidgets.option_row(c_vp["body"], "出力背景モード", [
		["transparent", "背景透過 (αチャンネル)"],
		["match_main", "メイン画面と同じ"],
		["solid", "単色"],
		["chroma_green", "クロマキー (緑)"],
		["image", "画像"],
	], func(m: String):
		if _win.controller != null:
			_win.controller.bg_manager.apply_output_viewport({"background_mode": m}),
		is_sync
	)
	_cp_out = UiWidgets.color_row(c_vp["body"], "出力背景色", Color("#00ff00"), func(c: Color):
		if _win.controller != null:
			_win.controller.bg_manager.apply_output_viewport({"color": "#" + c.to_html(false)}),
		is_sync
	)

	_dlg_out_img = UiWidgets.file_dialog(_win, FileDialog.FILE_MODE_OPEN_FILE, PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Image Files"]), func(p: String):
		if _win.controller != null:
			_win.controller.bg_manager.apply_output_viewport({"image_path": p, "background_mode": "image"})
	)
	var oimg_row := UiWidgets.labeled_row(c_vp["body"], "出力背景画像")
	_lbl_out_img = Label.new()
	_lbl_out_img.theme_type_variation = "MutedLabel"
	_lbl_out_img.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_out_img.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_lbl_out_img.text = "(未設定)"
	oimg_row.add_child(_lbl_out_img)
	var b_oimg := Button.new()
	b_oimg.text = "選択..."
	b_oimg.pressed.connect(func(): _win.popup_at_vrm_dir(_dlg_out_img))
	oimg_row.add_child(b_oimg)

	# ---- スクショ・録画
	var c_cap: Dictionary = UiWidgets.card(vb, "スクリーンショット・録画")
	_build_ffmpeg_box(c_cap["body"])
	var b_shot := Button.new()
	b_shot.text = "スクリーンショット撮影 (F11)"
	b_shot.theme_type_variation = "AccentButton"
	b_shot.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b_shot.pressed.connect(func():
		if _win.controller == null:
			return
		var res: Dictionary = _win.controller.take_screenshot()
		if res.get("ok", false):
			_win.show_snackbar("スクリーンショット保存: " + str(res.get("path", "")).get_file())
		else:
			_win.show_snackbar("撮影失敗: " + str(res.get("error", "")))
	)
	c_cap["body"].add_child(b_shot)

	_opt_fmt = UiWidgets.option_row(c_cap["body"], "録画形式", [
		["mp4", "MP4 (H.264 / 標準)"],
		["webm_alpha", "WebM (VP9 / 透過α対応)"],
	], func(_v: String): pass, is_sync)
	_opt_fps = UiWidgets.option_row(c_cap["body"], "録画フレームレート", [
		["30", "30 FPS"],
		["60", "60 FPS"],
	], func(_v: String): pass, is_sync)
	_chk_rec_audio = UiWidgets.check(c_cap["body"], "リップシンクの音も録画に入れる", true, func(on: bool):
		if _win.controller != null:
			_win.controller.capture_manager.record_lipsync_audio = on
	, is_sync)
	_chk_rec_audio.tooltip_text = "録画中に「音声から」のリップシンクで流したファイルの音を、録画を止めたあとに重ねます (「音も鳴らす」がオフでも入ります)"

	_btn_rec = Button.new()
	_btn_rec.text = "● 録画開始 (F12)"
	_btn_rec.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_btn_rec.pressed.connect(func():
		if _win.controller == null:
			return
		var cm = _win.controller.capture_manager
		if cm.recording_active:
			var r: Dictionary = cm.stop_recording()
			if r.get("ok", false) and str(r.get("audio_error", "")) != "":
				_win.show_snackbar("録画を保存しましたが、リップシンクの音を入れられませんでした: " + str(r.get("audio_error", "")))
			elif r.get("ok", false):
				_win.show_snackbar("録画を保存しました%s: %s" % [" (リップシンクの音入り)" if r.get("lipsync_audio", false) else "", str(r.get("path", "")).get_file()])
			else:
				_win.show_snackbar("録画停止エラー: " + str(r.get("error", "")))
		else:
			var fmt := str(_opt_fmt.get_item_metadata(_opt_fmt.selected))
			var fps := int(str(_opt_fps.get_item_metadata(_opt_fps.selected)))
			var r: Dictionary = cm.start_recording({"format": fmt, "fps": fps})
			if r.get("ok", false):
				_win.show_snackbar("録画を開始しました。")
			else:
				_win.show_snackbar("録画開始エラー: " + str(r.get("error", "")))
	)
	c_cap["body"].add_child(_btn_rec)

	_lbl_dirs = Label.new()
	_lbl_dirs.theme_type_variation = "MutedLabel"
	_lbl_dirs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c_cap["body"].add_child(_lbl_dirs)

	# ---- Spout2 / 仮想カメラ
	var c_ext: Dictionary = UiWidgets.card(vb, "OBS 連携 (Spout2) / 仮想カメラ")
	_chk_spout = UiWidgets.check(c_ext["body"], "Spout2 出力を有効にする (Windows / OBS 用)", false, func(on: bool):
		if _win.controller != null:
			var sname := _edit_spout.text.strip_edges()
			_win.controller.capture_manager.set_spout({"enabled": on, "sender_name": sname if sname != "" else "UtsushiMirror"}),
		is_sync
	)
	var srow := UiWidgets.labeled_row(c_ext["body"], "Spout Sender 名")
	_edit_spout = LineEdit.new()
	_edit_spout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit_spout.text = "UtsushiMirror"
	_edit_spout.text_submitted.connect(func(txt: String):
		if _win.controller != null and _chk_spout.button_pressed:
			_win.controller.capture_manager.set_spout({"enabled": true, "sender_name": txt.strip_edges()})
	)
	srow.add_child(_edit_spout)

	_chk_vcam = UiWidgets.check(c_ext["body"], "仮想カメラ (Discord / Zoom 用)", false, func(on: bool):
		if _win.controller != null:
			var r: Dictionary = _win.controller.capture_manager.set_vcam({"enabled": on})
			if on and not r.get("ok", false) and not r.get("active", false):
				_win.show_snackbar("仮想カメラエラー: " + str(r.get("error", r.get("message", ""))), "", Callable(), 6.0),
		is_sync
	)
	_lbl_vcam = Label.new()
	_lbl_vcam.theme_type_variation = "DimLabel"
	_lbl_vcam.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c_ext["body"].add_child(_lbl_vcam)


# ---- FFmpeg (録画に要る)。見つからないときだけ案内とボタンを出す
func _build_ffmpeg_box(parent: Control) -> void:
	_ff_dlg = ConfirmationDialog.new()
	_ff_dlg.title = "FFmpeg を入れる"
	_ff_dlg.ok_button_text = "ダウンロードして入れる"
	_ff_dlg.dialog_autowrap = true
	_ff_dlg.min_size = Vector2i(520, 0)
	_ff_dlg.confirmed.connect(func():
		if _win.controller == null:
			return
		var r: Dictionary = _win.controller.ffmpeg.start_install()
		if not r.get("ok", false):
			_win.show_snackbar("FFmpeg を入れられません: " + str(r.get("error", "")))
		refresh_ffmpeg()
	)
	_win.add_child(_ff_dlg)

	_ff_box = VBoxContainer.new()
	_ff_box.add_theme_constant_override("separation", 8)
	parent.add_child(_ff_box)
	var note := Label.new()
	note.theme_type_variation = "DimLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "録画には FFmpeg が要りますが、見つかりません。ボタンを押すと、このアプリのフォルダに入れます (PATH などの設定は変えません)。"
	_ff_box.add_child(note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_ff_box.add_child(row)
	_ff_btn = Button.new()
	_ff_btn.text = "FFmpeg を入れる"
	_ff_btn.theme_type_variation = "AccentButton"
	_ff_btn.pressed.connect(func():
		if _win.controller == null:
			return
		var fm = _win.controller.ffmpeg
		_ff_dlg.dialog_text = ("FFmpeg %s (gyan.dev の essentials 版、GPLv3) を GitHub からダウンロードして、次の場所に入れます。\n\n%s\n\n" +
			"ダウンロード: 約 %d MB / 入れたあと: 約 %d MB\n消すときは、このフォルダを消すだけです。") % [
			fm.VERSION, fm.app_dir().path_join("tools/ffmpeg").replace("/", "\\"), fm.DOWNLOAD_MB, fm.INSTALLED_MB]
		_ff_dlg.popup_centered()
	)
	row.add_child(_ff_btn)
	_ff_lbl = Label.new()
	_ff_lbl.theme_type_variation = "MutedLabel"
	_ff_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ff_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_ff_lbl)


func refresh_ffmpeg() -> void:
	if _ff_box == null or _win.controller == null:
		return
	var fm = _win.controller.ffmpeg
	var installing: bool = fm.is_installing()
	var available: bool = fm.is_available()
	_ff_box.visible = installing or not available
	_ff_btn.disabled = installing
	_ff_btn.text = "入れています..." if installing else "FFmpeg を入れる"
	_ff_lbl.text = fm.progress_text()
	_ff_lbl.visible = _ff_lbl.text != ""
	if _btn_rec != null:
		_btn_rec.disabled = not available and not _win.controller.capture_manager.recording_active
		_btn_rec.tooltip_text = "" if available else "FFmpeg を入れると録画できます"


## 設定画面のタイマーから呼ばれる (インストール中の進み具合)
func update_live() -> void:
	if _win.controller != null and _win.controller.ffmpeg.is_installing():
		refresh_ffmpeg()


func on_ffmpeg_installed(ok: bool) -> void:
	refresh_ffmpeg()
	if ok:
		_win.show_snackbar("FFmpeg を入れました。録画できます。")
	else:
		_win.show_snackbar("FFmpeg を入れられませんでした: " + str(_win.controller.ffmpeg.install_error), "", Callable(), 8.0)


func sync(st: Dictionary) -> void:
	var ov: Dictionary = st.get("output_viewport", {})
	var ow := int(ov.get("width", 1280))
	var oh := int(ov.get("height", 720))
	_sp_ow.value = ow
	_sp_oh.value = oh
	var rkey := "%dx%d" % [ow, oh]
	if rkey in ["1280x720", "1920x1080", "2560x1440", "1080x1920"]:
		UiWidgets.select_option_by_meta(_opt_res, rkey)
	else:
		UiWidgets.select_option_by_meta(_opt_res, "custom")

	UiWidgets.select_option_by_meta(_opt_out_bg, str(ov.get("background_mode", "transparent")))
	_cp_out.color = Color(str(ov.get("color", "#00ff00")))
	var oip := str(ov.get("image_path", ""))
	_lbl_out_img.text = oip.get_file() if oip != "" else "(未設定)"
	_lbl_out_img.tooltip_text = oip

	var cap: Dictionary = st.get("capture", {})
	var rec_on := bool(cap.get("recording_active", false))
	_btn_rec.text = "■ 録画停止 (F12)" if rec_on else "● 録画開始 (F12)"
	_chk_rec_audio.button_pressed = bool(cap.get("record_lipsync_audio", true))
	_btn_rec.theme_type_variation = "DangerButton" if rec_on else ""
	if _win.controller != null and not _win.controller.ffmpeg.is_installing():
		_win.controller.ffmpeg.refresh()
	refresh_ffmpeg()

	if _win.controller != null:
		var sc_dir: String = _win.controller.get_capture_dir("screenshots")
		var rc_dir: String = _win.controller.get_capture_dir("recordings")
		_lbl_dirs.text = "保存先:\n・スクショ: %s\n・録画: %s" % [sc_dir, rc_dir]

	_chk_spout.button_pressed = bool(cap.get("spout_enabled", false))
	if not _edit_spout.has_focus():
		_edit_spout.text = str(cap.get("spout_sender_name", "UtsushiMirror"))

	_chk_vcam.button_pressed = bool(cap.get("vcam_enabled", false))
	var vc: Dictionary = st.get("vcam_status", {})
	_lbl_vcam.text = str(vc.get("message", ""))
