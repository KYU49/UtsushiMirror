extends RefCounted
## トラッキングタブの「リップシンク (音声・テキスト)」のカード。畳める。
## 口の動きの元を「なし / 音声から / テキストから」から選び、音声・動画ファイルか文で口を動かす。
## トラッキングやアニメーションと一緒に使え、動かしている間は口だけがこちらに揃う。

const UiWidgets := preload("res://scripts/ui/ui_widgets.gd")
const LipSyncScript := preload("res://scripts/core/lip_sync.gd")

const TITLE := "リップシンク (音声・テキスト)"

var _win
var card: PanelContainer
var opt_mode: OptionButton
var audio_box: VBoxContainer
var text_box: VBoxContainer
var chk_emotion: CheckBox
var chk_play: CheckBox
var sl_volume: HSlider
var sl_intensity: HSlider
var file_lbl: Label
var _file_path := ""
var status_lbl: Label
var text_edit: LineEdit
var _dlg: FileDialog


func build(win, vb: VBoxContainer) -> void:
	_win = win
	var is_sync: Callable = win.is_syncing_fn()
	var c: Dictionary = UiWidgets.card(vb, TITLE, true, true)
	var body: VBoxContainer = c["body"]
	card = body.get_parent().get_parent() as PanelContainer

	opt_mode = UiWidgets.option_row(body, "口の動き", [["off", "なし"], ["audio", "音声から"], ["text", "テキストから"]],
		func(m: String):
			if _ctl() != null:
				_ctl().set_lipsync_mode(m)
			_show_mode(m)
	, is_sync)

	# ---- 音声から
	audio_box = VBoxContainer.new()
	audio_box.add_theme_constant_override("separation", 7)
	body.add_child(audio_box)
	UiWidgets.note(audio_box, "音声・動画ファイル (mp3 / wav / ogg / flac / m4a / mp4 / mov / mkv など) に口を合わせます。「音も鳴らす」がオフのときは、別のソフトで流す音と同時に始めてください。ファイルをウィンドウへドロップしても始まります。")
	var exts := PackedStringArray()
	for e in LipSyncScript.MEDIA_EXTS:
		exts.append("*." + str(e))
	_dlg = UiWidgets.file_dialog(win, FileDialog.FILE_MODE_OPEN_FILE, PackedStringArray([", ".join(exts) + " ; 音声・動画"]), func(p: String):
		_start_audio(p)
	)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	audio_box.add_child(row)
	var b_open := Button.new()
	b_open.text = "ファイルを選んで始める..."
	b_open.theme_type_variation = "AccentButton"
	b_open.pressed.connect(func(): _win.popup_at_vrm_dir(_dlg))
	row.add_child(b_open)
	var b_again := Button.new()
	b_again.text = "もう一度"
	b_again.tooltip_text = "最後のファイルを最初から"
	b_again.pressed.connect(func():
		# ドロップで始めたものも含めて、最後のファイルを最初から
		if _ctl() != null and str(_ctl().lip_sync.last_path) != "":
			_start_audio(str(_ctl().lip_sync.last_path))
	)
	row.add_child(b_again)
	var b_stop := Button.new()
	b_stop.text = "止める"
	b_stop.pressed.connect(func():
		if _ctl() != null:
			_ctl().lip_sync.stop()
	)
	row.add_child(b_stop)
	file_lbl = Label.new()
	file_lbl.theme_type_variation = "MutedLabel"
	file_lbl.clip_text = true
	file_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	audio_box.add_child(file_lbl)
	UiWidgets.path_link(file_lbl, func(): return _file_path)
	sl_intensity = UiWidgets.slider(audio_box, "口の開き", 0.2, 1.5, 0.05, LipSyncScript.DEFAULT_INTENSITY, func(v: float):
		if _ctl() != null:
			_ctl().lip_sync.intensity = v
	, is_sync)
	chk_emotion = UiWidgets.check(audio_box, "声の調子から感情も乗せる", true, func(v: bool):
		if _ctl() != null:
			_ctl().lip_sync.emotion = v
	, is_sync)
	chk_play = UiWidgets.check(audio_box, "音も鳴らす", false, func(v: bool):
		if _ctl() != null:
			_ctl().lip_sync.play_audio = v
		sl_volume.get_parent().visible = v
	, is_sync)
	sl_volume = UiWidgets.slider(audio_box, "音量", 0.0, 1.0, 0.05, 1.0, func(v: float):
		if _ctl() != null:
			_ctl().lip_sync.set_volume(v)
	, is_sync)
	sl_volume.get_parent().visible = false

	# ---- テキストから
	text_box = VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 7)
	body.add_child(text_box)
	UiWidgets.note(text_box, "文の読み (かな) から、それらしく口を動かします。音は出ません。")
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 8)
	text_box.add_child(trow)
	text_edit = LineEdit.new()
	text_edit.placeholder_text = "しゃべらせる文"
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_edit.text_submitted.connect(func(_t: String): _start_text())
	trow.add_child(text_edit)
	var b_talk := Button.new()
	b_talk.text = "しゃべる"
	b_talk.theme_type_variation = "AccentButton"
	b_talk.pressed.connect(_start_text)
	trow.add_child(b_talk)
	var b_tstop := Button.new()
	b_tstop.text = "止める"
	b_tstop.pressed.connect(func():
		if _ctl() != null:
			_ctl().motion.stop_talk()
	)
	trow.add_child(b_tstop)

	status_lbl = Label.new()
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status_lbl)
	_show_mode("audio")


func _ctl():
	return _win.controller if _win != null else null


func _start_audio(p: String) -> void:
	if _ctl() == null:
		return
	_set_file(p)
	var r: Dictionary = _ctl().start_lipsync({"path": p})
	if not r.get("ok", false):
		_win.show_snackbar("リップシンクできません: " + str(r.get("error", "")))
	update_live()


func _set_file(p: String) -> void:
	file_lbl.text = p.get_file()
	_file_path = p
	UiWidgets.refresh_path_link(file_lbl)


func _start_text() -> void:
	if _ctl() == null or text_edit.text.strip_edges() == "":
		return
	var r: Dictionary = _ctl().start_text_talk({"text": text_edit.text})
	if not r.get("ok", false):
		_win.show_snackbar("しゃべれません: " + str(r.get("error", "")))
	update_live()


func _show_mode(m: String) -> void:
	audio_box.visible = m == "audio"
	text_box.visible = m == "text"


## 状態の表示 (トラッキングタブの定期更新から呼ぶ)
func update_live() -> void:
	if _ctl() == null:
		return
	var st: Dictionary = _ctl().lipsync_state()
	if bool(st.get("active", false)):
		status_lbl.text = "● %s  残り %.1f 秒" % ["音を鳴らして合わせています" if bool(st.get("playing_audio", false)) else "音声に合わせています", float(st.get("remaining_sec", 0.0))]
		_set_file(str(st.get("path", "")))
	elif bool(st.get("talking", false)):
		status_lbl.text = "● しゃべっています  残り %.1f 秒" % float(st.get("remaining_sec", 0.0))
	else:
		status_lbl.text = "停止中" if str(st.get("mode", "")) != "off" else "口はトラッキング・アニメーションのまま動きます"
	if not bool(st.get("active", false)) and str(st.get("last_path", "")) != "":
		_set_file(str(st.get("last_path", "")))
	file_lbl.visible = file_lbl.text != ""


func sync(st: Dictionary) -> void:
	var ls: Dictionary = st.get("lipsync", {})
	var m := str(ls.get("mode", "audio"))
	UiWidgets.select_option_by_meta(opt_mode, m)
	_show_mode(m)
	sl_intensity.value = float(ls.get("intensity", LipSyncScript.DEFAULT_INTENSITY))
	chk_emotion.button_pressed = bool(ls.get("emotion", true))
	chk_play.button_pressed = bool(ls.get("play_audio", false))
	sl_volume.value = float(ls.get("volume", 1.0))
	sl_volume.get_parent().visible = chk_play.button_pressed
	update_live()
