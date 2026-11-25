extends RefCounted

const TrackingManagerScript := preload("res://scripts/core/tracking_manager.gd")
const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const UiWidgets := preload("res://scripts/ui/ui_widgets.gd")
const LipSyncCardScript := preload("res://scripts/ui/tabs/lipsync_card.gd")

var _win
var lipsync_card = LipSyncCardScript.new()

# テスト契約 (test_tracker_install.gd / test_tracking_ui.gd) 互換フィールド
var _install_box: VBoxContainer
var _install_btn: Button
var _install_prg_lbl: Label
var _start_row: HBoxContainer
var _install_dlg: ConfirmationDialog
var _status_lbl: Label
var _calib_lbl: Label
var _start_btn: Button
var _calib_btn: Button
var _mode_btns: Dictionary = {} # mode_id -> Button
var _sec: Dictionary = {}       # "eyes" / "expr" / "hands" / "upper" / "legs" -> card body (get_parent().get_parent() == Card)
var _cards: Dictionary = {}     # key -> PanelContainer card

var _chk_parts: Dictionary = {} # "face" / "hands" / "pose" / "legs" -> CheckBox
var _custom_parts_box: HBoxContainer

var _opt_cam: OptionButton
var _opt_res: OptionButton
var _opt_fps: OptionButton
var _opt_calib_delay: OptionButton
var _last_cams_key: String = "__init__"

var _checks: Dictionary = {}
var _sliders: Dictionary = {}
var _opt_gaze_mode: OptionButton
var _opt_pose_model: OptionButton

var _installing_btn_label := "トラッキングをインストール..."


func build(win, vb: VBoxContainer) -> void:
	_win = win
	var is_sync: Callable = win.is_syncing_fn()
	var apply_set := func(d: Dictionary):
		if _win.controller != null:
			_win.controller.apply_tracking_settings(d)

	# ---- インストール確認ダイアログ
	_install_dlg = ConfirmationDialog.new()
	_install_dlg.title = "Webカメラトラッキングのセットアップ"
	_install_dlg.ok_button_text = "インストール開始"
	_install_dlg.confirmed.connect(func():
		if _win.controller == null or _win.controller.tracking == null:
			return
		var res: Dictionary = _win.controller.tracking.start_install()
		if not res.get("ok", false):
			_win.show_snackbar("セットアップエラー: " + str(res.get("error", "")))
		refresh_install()
	)
	_win.add_child(_install_dlg)

	# ---- 操作・ステータスカード
	var c_ctl: Dictionary = UiWidgets.card(vb, "Webカメラトラッキング")
	_install_box = VBoxContainer.new()
	_install_box.add_theme_constant_override("separation", 8)
	c_ctl["body"].add_child(_install_box)

	var inst_note := Label.new()
	inst_note.theme_type_variation = "DimLabel"
	inst_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inst_note.text = "Webカメラトラッキングを使うには、初回のみ専用の Python 環境 (MediaPipe / OpenCV) のセットアップが必要です。"
	_install_box.add_child(inst_note)

	var inst_row := HBoxContainer.new()
	inst_row.add_theme_constant_override("separation", 8)
	_install_box.add_child(inst_row)

	_install_btn = Button.new()
	_install_btn.text = _installing_btn_label
	_install_btn.theme_type_variation = "AccentButton"
	_install_btn.pressed.connect(func(): show_install_dialog())
	inst_row.add_child(_install_btn)

	_install_prg_lbl = Label.new()
	_install_prg_lbl.theme_type_variation = "MutedLabel"
	_install_prg_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_install_prg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_install_box.add_child(_install_prg_lbl)

	_start_row = HBoxContainer.new()
	_start_row.add_theme_constant_override("separation", 8)
	c_ctl["body"].add_child(_start_row)

	_start_btn = Button.new()
	_start_btn.text = "トラッキング開始"
	_start_btn.theme_type_variation = "AccentButton"
	_start_btn.pressed.connect(func():
		if _win.controller == null:
			return
		if _win.controller.tracking.is_running():
			_win.controller.stop_tracking()
		else:
			var r: Dictionary = _win.controller.start_tracking()
			if not r.get("ok", false):
				_win.show_snackbar("トラッキング開始エラー: " + str(r.get("error", "")))
	)
	_start_row.add_child(_start_btn)

	_calib_btn = Button.new()
	_calib_btn.text = "正面を記憶 (キャリブ)"
	_calib_btn.pressed.connect(func():
		if _win.controller == null:
			return
		var r: Dictionary = _win.controller.tracking.calibrate()
		if not r.get("ok", false):
			_win.show_snackbar(str(r.get("error", "")))
	)
	_start_row.add_child(_calib_btn)

	var b_cam_scan := Button.new()
	b_cam_scan.text = "カメラ再検出"
	b_cam_scan.pressed.connect(func():
		if _win.controller != null:
			_win.controller.tracking.refresh_cameras_async()
	)
	_start_row.add_child(b_cam_scan)

	_status_lbl = Label.new()
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.text = "待機中"
	c_ctl["body"].add_child(_status_lbl)

	_calib_lbl = Label.new()
	_calib_lbl.theme_type_variation = "MutedLabel"
	c_ctl["body"].add_child(_calib_lbl)

	# ---- リップシンク (音声・テキスト)。中身は lipsync_card.gd
	lipsync_card.build(win, vb)

	# ---- カメラ設定
	var c_cam: Dictionary = UiWidgets.card(vb, "カメラ設定")
	var cam_row := UiWidgets.labeled_row(c_cam["body"], "使用カメラ")
	_opt_cam = OptionButton.new()
	_opt_cam.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opt_cam.item_selected.connect(func(idx: int):
		if _win.is_syncing:
			return
		var mv: String = str(_opt_cam.get_item_metadata(idx))
		apply_set.call({"camera": mv})
	)
	cam_row.add_child(_opt_cam)

	_opt_res = UiWidgets.option_row(c_cam["body"], "カメラ解像度", [
		["640x480", "640×480 (軽量)"],
		["1280x720", "1280×720 (HD 標準)"],
		["1920x1080", "1920×1080 (高精細)"],
	], func(v: String): apply_set.call({"resolution": v}), is_sync)

	_opt_fps = UiWidgets.option_row(c_cam["body"], "カメラ FPS", [
		["15", "15 FPS (省負荷)"],
		["24", "24 FPS"],
		["30", "30 FPS (標準)"],
		["60", "60 FPS"],
	], func(v: String): apply_set.call({"fps": int(v)}), is_sync)

	_opt_calib_delay = UiWidgets.option_row(c_cam["body"], "正面記憶の待ち秒", [
		["0", "即時 (0 秒)"],
		["3", "3 秒カウント後"],
		["5", "5 秒カウント後"],
	], func(v: String): apply_set.call({"calib_delay": int(v)}), is_sync)

	_checks["mirror"] = UiWidgets.check(c_cam["body"], "左右ミラー反転 (鏡写し)", true, func(on: bool): apply_set.call({"mirror": on}), is_sync)
	_checks["preview"] = UiWidgets.check(c_cam["body"], "プレビューウィンドウを表示 (デバッグ用)", true, func(on: bool): apply_set.call({"preview": on}), is_sync)

	# ---- モード・部位選択
	var c_mode: Dictionary = UiWidgets.card(vb, "トラッキングモード・部位")
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	c_mode["body"].add_child(mrow)

	for mid in ["face", "upper", "full", "custom"]:
		var mkey: String = mid
		var info: Dictionary = TrackingManagerScript.MODES.get(mkey, {})
		var b := Button.new()
		b.text = str(info.get("label", mkey))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			var upd := {"mode": mkey}
			var parts: Array = info.get("parts", [])
			if parts.size() >= 4:
				upd["face"] = bool(parts[0])
				upd["hands"] = bool(parts[1])
				upd["pose"] = bool(parts[2])
				upd["legs"] = bool(parts[3])
			apply_set.call(upd)
			_apply_part_visibility(
				mkey,
				bool(upd.get("face", _chk_parts["face"].button_pressed)),
				bool(upd.get("hands", _chk_parts["hands"].button_pressed)),
				bool(upd.get("pose", _chk_parts["pose"].button_pressed)),
				bool(upd.get("legs", _chk_parts["legs"].button_pressed))
			)
		)
		mrow.add_child(b)
		_mode_btns[mkey] = b

	_custom_parts_box = HBoxContainer.new()
	_custom_parts_box.add_theme_constant_override("separation", 12)
	c_mode["body"].add_child(_custom_parts_box)
	for pair in [["face", "顔・目"], ["hands", "手・指"], ["pose", "上半身・腕"], ["legs", "脚・腰移動"]]:
		var pkey: String = pair[0]
		var cb := CheckBox.new()
		cb.text = pair[1]
		cb.toggled.connect(func(on: bool):
			if _win.is_syncing:
				return
			apply_set.call({"mode": "custom", pkey: on})
			_apply_part_visibility(
				"custom",
				_chk_parts["face"].button_pressed,
				_chk_parts["hands"].button_pressed,
				_chk_parts["pose"].button_pressed,
				_chk_parts["legs"].button_pressed
			)
		)
		_custom_parts_box.add_child(cb)
		_chk_parts[pkey] = cb

	# ---- 目線・まばたき (eyes)
	var c_eyes: Dictionary = UiWidgets.card(vb, "目線・まばたき")
	_sec["eyes"] = c_eyes["body"]
	_cards["eyes"] = c_eyes["card"]
	_checks["gaze"] = UiWidgets.check(c_eyes["body"], "視線トラッキング有効", true, func(on: bool): apply_set.call({"gaze": on}), is_sync)
	_opt_gaze_mode = UiWidgets.option_row(c_eyes["body"], "目線モード", [
		["track", "トラッカーの動きに合わせる"],
		["camera", "常にカメラ目線にする"],
		["fixed", "正面で固定"],
	], func(v: String): apply_set.call({"gaze_mode": v}), is_sync)
	_checks["gaze_link"] = UiWidgets.check(c_eyes["body"], "左右の目を連動させる", true, func(on: bool): apply_set.call({"gaze_link": on}), is_sync)
	_sliders["gaze_gain"] = UiWidgets.slider(c_eyes["body"], "視線移動の倍率", 0.2, 2.5, 0.05, 1.0, func(v: float): apply_set.call({"gaze_gain": v}), is_sync)
	_sliders["gaze_limit_h"] = UiWidgets.slider(c_eyes["body"], "左右の可動上限 (°)", 5.0, 45.0, 1.0, 25.0, func(v: float): apply_set.call({"gaze_limit_h": v}), is_sync)
	_sliders["gaze_limit_up"] = UiWidgets.slider(c_eyes["body"], "上方向の可動上限 (°)", 5.0, 35.0, 1.0, 15.0, func(v: float): apply_set.call({"gaze_limit_up": v}), is_sync)
	_sliders["gaze_limit_down"] = UiWidgets.slider(c_eyes["body"], "下方向の可動上限 (°)", 5.0, 35.0, 1.0, 12.0, func(v: float): apply_set.call({"gaze_limit_down": v}), is_sync)
	_checks["blink_link"] = UiWidgets.check(c_eyes["body"], "両目を同時にまばたき", false, func(on: bool): apply_set.call({"blink_link": on}), is_sync)
	_sliders["blink_sens"] = UiWidgets.slider(c_eyes["body"], "まばたき感度", 0.0, 1.0, 0.02, 0.5, func(v: float): apply_set.call({"blink_sens": v}), is_sync)

	# ---- 表情・口 (expr)
	var c_expr: Dictionary = UiWidgets.card(vb, "表情・リップシンク")
	_sec["expr"] = c_expr["body"]
	_cards["expr"] = c_expr["card"]
	_checks["expressions"] = UiWidgets.check(c_expr["body"], "表情の自動反映を有効", true, func(on: bool): apply_set.call({"expressions": on}), is_sync)
	_sliders["mouth_gain"] = UiWidgets.slider(c_expr["body"], "口の開き倍率", 0.2, 2.5, 0.05, 1.0, func(v: float): apply_set.call({"mouth_gain": v}), is_sync)
	_sliders["happy_sens"] = UiWidgets.slider(c_expr["body"], "笑顔のしきい値", 0.0, 1.0, 0.02, 0.2, func(v: float): apply_set.call({"happy_sens": v}), is_sync)
	_sliders["happy_gain"] = UiWidgets.slider(c_expr["body"], "笑顔の強さ倍率", 0.0, 2.0, 0.05, 0.5, func(v: float): apply_set.call({"happy_gain": v}), is_sync)
	_sliders["angry_sens"] = UiWidgets.slider(c_expr["body"], "怒り (眉) のしきい値", 0.0, 1.0, 0.02, 0.5, func(v: float): apply_set.call({"angry_sens": v}), is_sync)
	_sliders["angry_gain"] = UiWidgets.slider(c_expr["body"], "怒りの強さ倍率", 0.0, 2.0, 0.05, 0.8, func(v: float): apply_set.call({"angry_gain": v}), is_sync)
	_sliders["surprised_sens"] = UiWidgets.slider(c_expr["body"], "驚きのしきい値", 0.0, 1.0, 0.02, 0.5, func(v: float): apply_set.call({"surprised_sens": v}), is_sync)
	_sliders["surprised_gain"] = UiWidgets.slider(c_expr["body"], "驚きの強さ倍率", 0.0, 2.0, 0.05, 0.8, func(v: float): apply_set.call({"surprised_gain": v}), is_sync)

	# ---- 手・指 (hands)
	var c_hands: Dictionary = UiWidgets.card(vb, "手・指トラッキング")
	_sec["hands"] = c_hands["body"]
	_cards["hands"] = c_hands["card"]
	_checks["fingers"] = UiWidgets.check(c_hands["body"], "指の曲げ伸ばしを反映", true, func(on: bool): apply_set.call({"fingers": on}), is_sync)
	_checks["arm_from_hand"] = UiWidgets.check(c_hands["body"], "手首位置から肘・肩を補間", true, func(on: bool): apply_set.call({"arm_from_hand": on}), is_sync)
	_sliders["hand_edge"] = UiWidgets.slider(c_hands["body"], "画面端のフェード領域", 0.0, 0.15, 0.005, 0.03, func(v: float): apply_set.call({"hand_edge": v}), is_sync)

	# ---- 上半身・腕・ポーズ (upper)
	var c_up: Dictionary = UiWidgets.card(vb, "上半身・頭・肩・腕")
	_sec["upper"] = c_up["body"]
	_cards["upper"] = c_up["card"]
	_opt_pose_model = UiWidgets.option_row(c_up["body"], "姿勢推定モデル", [
		["lite", "Lite (超軽量)"],
		["full", "Full (標準バランス)"],
		["heavy", "Heavy (高精度)"],
	], func(v: String): apply_set.call({"pose_model": v}), is_sync)
	_sliders["head_gain"] = UiWidgets.slider(c_up["body"], "頭の回転倍率", 0.2, 2.0, 0.05, 1.0, func(v: float): apply_set.call({"head_gain": v}), is_sync)
	_sliders["body_follow"] = UiWidgets.slider(c_up["body"], "体の追従 (体幹の連動)", 0.0, 1.0, 0.02, 0.35, func(v: float): apply_set.call({"body_follow": v}), is_sync)
	_sliders["shoulder_sens"] = UiWidgets.slider(c_up["body"], "肩の上下の感度", 0.0, 1.0, 0.02, 0.5, func(v: float): apply_set.call({"shoulder_sens": v}), is_sync)
	_sliders["shoulder_gain"] = UiWidgets.slider(c_up["body"], "肩の動きの倍率", 0.0, 2.0, 0.05, 1.0, func(v: float): apply_set.call({"shoulder_gain": v}), is_sync)
	_checks["arms_rest"] = UiWidgets.check(c_up["body"], "検出ロスト時は腕・脚を自然に戻す", true, func(on: bool): apply_set.call({"arms_rest": on}), is_sync)
	_checks["avoid_body"] = UiWidgets.check(c_up["body"], "胸・頭へのめり込みを避ける", true, func(on: bool): apply_set.call({"avoid_body": on}), is_sync)
	_checks["hand_spring_collide"] = UiWidgets.check(c_up["body"], "手で髪・揺れものを押す", true, func(on: bool): apply_set.call({"hand_spring_collide": on}), is_sync)
	_sliders["forearm_twist"] = UiWidgets.slider(c_up["body"], "前腕のねじり配分", 0.0, 1.0, 0.05, 0.7, func(v: float): apply_set.call({"forearm_twist": v}), is_sync)

	# ---- 脚・腰 (legs)
	var c_legs: Dictionary = UiWidgets.card(vb, "脚・腰の移動")
	_sec["legs"] = c_legs["body"]
	_cards["legs"] = c_legs["card"]
	_checks["hips_move"] = UiWidgets.check(c_legs["body"], "腰の前後・左右移動を反映", true, func(on: bool): apply_set.call({"hips_move": on}), is_sync)

	# ---- 安定化・感度
	var c_stab: Dictionary = UiWidgets.card(vb, "安定化・検出感度", true, false)
	_sliders["confidence"] = UiWidgets.slider(c_stab["body"], "検出しきい値 (Confidence)", 0.1, 0.95, 0.05, 0.5, func(v: float): apply_set.call({"confidence": v}), is_sync)
	_sliders["smooth"] = UiWidgets.slider(c_stab["body"], "スムージング (滑らかさ)", 0.0, 0.98, 0.02, 0.85, func(v: float): apply_set.call({"smooth": v}), is_sync)
	_sliders["responsiveness"] = UiWidgets.slider(c_stab["body"], "素早い動きへの追従性", 0.0, 1.0, 0.02, 0.5, func(v: float): apply_set.call({"responsiveness": v}), is_sync)
	_sliders["stabilize"] = UiWidgets.slider(c_stab["body"], "微小なブレ抑制", 0.0, 1.0, 0.02, 0.5, func(v: float): apply_set.call({"stabilize": v}), is_sync)
	_sliders["lost_hold"] = UiWidgets.slider(c_stab["body"], "ロスト時の姿勢保持 (秒)", 0.0, 3.0, 0.05, 0.5, func(v: float): apply_set.call({"lost_hold": v}), is_sync)
	_sliders["lost_return"] = UiWidgets.slider(c_stab["body"], "自然姿勢への復帰 (秒)", 0.1, 3.0, 0.05, 0.6, func(v: float): apply_set.call({"lost_return": v}), is_sync)

	var b_rst := Button.new()
	b_rst.text = "トラッキング設定を初期値に戻す"
	b_rst.theme_type_variation = "DangerButton"
	b_rst.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b_rst.pressed.connect(func():
		if _win.controller != null:
			_win.controller.tracking.reset_settings()
			_win.controller.state_changed.emit()
			_win.show_snackbar("トラッキング設定を初期値に戻しました。")
	)
	c_stab["body"].add_child(b_rst)


func tracking_install_message(info: Dictionary) -> Dictionary:
	var lines := PackedStringArray()
	var script_ok := bool(info.get("script_found", false))
	if not script_ok:
		lines.append("インストール用スクリプトが見つかりません。")
		lines.append("確認先: " + str(info.get("tracker_dir", "")))
		return {"text": "\n".join(lines), "enough": false}

	lines.append("Webカメラトラッキングに必要な Python 環境 (MediaPipe / OpenCV / NumPy) をインストールします。")
	lines.append("要求スペック: Windows 10/11 (64bit) / メモリ 8 GB 以上推奨 / Webカメラ")
	lines.append("")
	var app_drive := str(info.get("app_drive", ""))
	var app_need := int(info.get("app_need_mb", 400))
	var app_free := int(info.get("app_free_mb", 0))
	lines.append("必要な空き容量 (%s): 約 %d MB（今の空き: %d MB）" % [app_drive, app_need, app_free])

	var same := bool(info.get("same_drive", true))
	var user_drive := str(info.get("user_drive", ""))
	var user_need := int(info.get("user_need_mb", 500))
	var user_free := int(info.get("user_free_mb", 0))
	if not same:
		lines.append("キャッシュ用に必要な空き容量 (%s): 約 %d MB（今の空き: %d MB）" % [user_drive, user_need, user_free])

	var enough_app := app_free < 0 or app_free >= app_need
	var enough_user := same or user_free < 0 or user_free >= user_need
	var enough := script_ok and enough_app and enough_user
	if not enough:
		lines.append("")
		lines.append("⚠ 注意: 空き容量が不足しています。空き容量を確保してからやり直してください。")

	lines.append("")
	if bool(info.get("uv_found", false)):
		lines.append("パッケージ構築ツール: 既存の環境を使用します (%s)" % str(info.get("uv_path", "")))
	else:
		lines.append("公式のインストーラー (uv) を自動取得して Python 環境を構築します。")
	return {"text": "\n".join(lines), "enough": enough}


func show_install_dialog() -> void:
	if _win.controller == null or _win.controller.tracking == null:
		return
	var info: Dictionary = _win.controller.tracking.install_info()
	var msg: Dictionary = tracking_install_message(info)
	_install_dlg.dialog_text = str(msg.get("text", ""))
	var ok_btn: Button = _install_dlg.get_ok_button()
	if ok_btn != null:
		ok_btn.disabled = not bool(msg.get("enough", false))
	_install_dlg.popup_centered()


func refresh_install() -> void:
	if _win.controller == null or _win.controller.tracking == null:
		return
	var trk = _win.controller.tracking
	var installed: bool = bool(trk.is_installed())
	var installing: bool = bool(trk.is_installing())
	_install_box.visible = not installed or installing
	_start_row.visible = installed and not installing
	_install_btn.disabled = installing
	_install_btn.text = "インストール中..." if installing else _installing_btn_label
	var msg := ""
	if installing:
		msg = "手順: %s  %s" % [str(trk.install_step), str(trk.install_last_line)]
	elif str(trk.install_error) != "":
		msg = "エラー: " + str(trk.install_error)
	_install_prg_lbl.text = msg
	_install_prg_lbl.visible = (msg != "")
	if _calib_lbl != null:
		_calib_lbl.visible = installed and not installing


func _apply_part_visibility(mode: String, face_on: bool, hands_on: bool, pose_on: bool, legs_on: bool) -> void:
	for mk in _mode_btns.keys():
		(_mode_btns[mk] as Button).theme_type_variation = "AccentButton" if str(mk) == mode else ""
	_custom_parts_box.visible = (mode == "custom")
	(_cards["eyes"] as PanelContainer).visible = face_on
	(_cards["expr"] as PanelContainer).visible = face_on
	(_cards["hands"] as PanelContainer).visible = hands_on
	(_cards["upper"] as PanelContainer).visible = pose_on
	(_cards["legs"] as PanelContainer).visible = legs_on


func on_cameras_refreshed(_cams: Array) -> void:
	if _win.controller != null:
		sync(_win.controller.get_full_state())


func on_installed(_ok: bool) -> void:
	refresh_install()
	if _win.controller != null:
		sync(_win.controller.get_full_state())


func update_live() -> void:
	if _win.controller == null or _win.controller.tracking == null:
		return
	lipsync_card.update_live()
	var trk = _win.controller.tracking
	var td: Dictionary = trk.to_dict()
	var running := bool(td.get("running", false))
	var st_d: Dictionary = td.get("status", {})
	var err := str(td.get("error", ""))
	if err != "":
		_status_lbl.text = "● エラー: " + err
		_status_lbl.add_theme_color_override("font_color", UiTheme.STATUS_WARN)
	elif running:
		var fps := float(st_d.get("fps", 0.0))
		var det_parts: Array[String] = []
		if bool(st_d.get("face", false)):
			det_parts.append("顔")
		if bool(st_d.get("pose", false)):
			det_parts.append("体")
		var h_cnt := int(st_d.get("hands", 0))
		if h_cnt > 0:
			det_parts.append("手(%d)" % h_cnt)
		if det_parts.is_empty():
			for x in st_d.get("detected", []):
				det_parts.append(str(x))
		_status_lbl.text = "● 動作中  %.1f FPS  検出: %s" % [fps, "・".join(det_parts) if not det_parts.is_empty() else "待機中"]
		_status_lbl.add_theme_color_override("font_color", UiTheme.STATUS_OK)
	else:
		_status_lbl.text = "● 停止中"
		_status_lbl.add_theme_color_override("font_color", UiTheme.TEXT_DIM)

	var cal := str(td.get("calibrated_at", ""))
	_calib_lbl.text = ("最終キャリブレーション: " + cal) if cal != "" else "キャリブレーション: 未実行"
	_calib_btn.disabled = not running
	if bool(td.get("install", {}).get("running", false)):
		refresh_install()


func sync(st: Dictionary) -> void:
	refresh_install()
	lipsync_card.sync(st)
	var tr: Dictionary = st.get("tracking", {})
	var running := bool(tr.get("running", false))
	_start_btn.text = "トラッキング停止" if running else "トラッキング開始"
	_start_btn.theme_type_variation = "DangerButton" if running else "AccentButton"

	var s: Dictionary = tr.get("settings", {})
	var cams: Array = tr.get("cameras", [])
	var cam_val := str(s.get("camera", "auto"))
	var ckey := JSON.stringify(cams) + "|" + cam_val
	if ckey != _last_cams_key:
		_last_cams_key = ckey
		_opt_cam.clear()
		_opt_cam.add_item("自動検出 (auto)")
		_opt_cam.set_item_metadata(0, "auto")
		var i := 1
		var found := (cam_val == "auto")
		for c_raw in cams:
			if typeof(c_raw) == TYPE_DICTIONARY:
				var cid := str(c_raw.get("index", c_raw.get("id", i - 1)))
				var clbl := str(c_raw.get("name", "Camera " + cid))
				_opt_cam.add_item("%s (ID: %s)" % [clbl, cid])
				_opt_cam.set_item_metadata(i, cid)
				if cid == cam_val:
					found = true
				i += 1
		if not found and cam_val != "":
			_opt_cam.add_item("カメラ " + cam_val)
			_opt_cam.set_item_metadata(i, cam_val)
	UiWidgets.select_option_by_meta(_opt_cam, cam_val)

	UiWidgets.select_option_by_meta(_opt_res, str(s.get("resolution", "1280x720")))
	UiWidgets.select_option_by_meta(_opt_fps, str(int(s.get("fps", 30))))
	UiWidgets.select_option_by_meta(_opt_calib_delay, str(int(s.get("calib_delay", 0))))
	UiWidgets.select_option_by_meta(_opt_gaze_mode, str(s.get("gaze_mode", "track")))
	UiWidgets.select_option_by_meta(_opt_pose_model, str(s.get("pose_model", "full")))

	var mode := str(s.get("mode", "upper"))
	var m_info: Dictionary = TrackingManagerScript.MODES.get(mode, {})
	var m_parts: Array = m_info.get("parts", [])
	var f_on := bool(m_parts[0]) if m_parts.size() >= 4 else bool(s.get("face", true))
	var h_on := bool(m_parts[1]) if m_parts.size() >= 4 else bool(s.get("hands", true))
	var p_on := bool(m_parts[2]) if m_parts.size() >= 4 else bool(s.get("pose", true))
	var l_on := bool(m_parts[3]) if m_parts.size() >= 4 else bool(s.get("legs", false))

	(_chk_parts["face"] as CheckBox).button_pressed = f_on
	(_chk_parts["hands"] as CheckBox).button_pressed = h_on
	(_chk_parts["pose"] as CheckBox).button_pressed = p_on
	(_chk_parts["legs"] as CheckBox).button_pressed = l_on
	_apply_part_visibility(mode, f_on, h_on, p_on, l_on)

	for k in _checks.keys():
		if s.has(k):
			(_checks[k] as CheckBox).button_pressed = bool(s[k])
	for k in _sliders.keys():
		if s.has(k):
			(_sliders[k] as HSlider).value = float(s[k])

	update_live()
