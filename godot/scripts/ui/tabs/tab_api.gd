extends RefCounted

const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const UiWidgets := preload("res://scripts/ui/ui_widgets.gd")

var _win
var _lbl_srv: Label
var _sp_ws: SpinBox
var _sp_osc: SpinBox

var _chk_vmc_recv_en: CheckBox
var _chk_vmc_recv_lan: CheckBox
var _lbl_local_ip: Label
var _sp_vmc_recv_port: SpinBox
var _lbl_vmc_recv_status: Label
var _chk_recv_root: CheckBox
var _chk_recv_bones: CheckBox
var _chk_recv_expr: CheckBox
var _chk_recv_cam: CheckBox

var _chk_vmc_send_en: CheckBox
var _le_send_host: LineEdit
var _sp_vmc_send_port: SpinBox
var _opt_send_fps: OptionButton
var _lbl_vmc_send_status: Label
var _chk_send_bones: CheckBox
var _chk_send_expr: CheckBox
var _chk_send_cam: CheckBox
var _chk_send_vrm0: CheckBox


func build(win, vb: VBoxContainer) -> void:
	_win = win
	var is_sync := func() -> bool: return _win.is_syncing
	var apply_vmc := func(d: Dictionary) -> void:
		if _win.controller == null:
			return
		var res: Dictionary = _win.controller.apply_vmc_settings(d)
		if not res.get("ok", true) and str(res.get("error", "")) != "":
			_win.show_snackbar(str(res.get("error", "")))

	# ---- API サーバー
	var c_srv: Dictionary = UiWidgets.card(vb, "外部連携サーバー (WebSocket / OSC・VMC)")
	_lbl_srv = Label.new()
	_lbl_srv.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c_srv["body"].add_child(_lbl_srv)

	var ws_row := UiWidgets.labeled_row(c_srv["body"], "WebSocket (JSON-RPC) ポート", 205)
	_sp_ws = SpinBox.new()
	_sp_ws.min_value = 1024
	_sp_ws.max_value = 65535
	_sp_ws.custom_minimum_size.x = 120
	ws_row.add_child(_sp_ws)

	var osc_row := UiWidgets.labeled_row(c_srv["body"], "OSC / VMC 受信ポート", 205)
	_sp_osc = SpinBox.new()
	_sp_osc.min_value = 1024
	_sp_osc.max_value = 65535
	_sp_osc.custom_minimum_size.x = 120
	osc_row.add_child(_sp_osc)

	var b_port := Button.new()
	b_port.text = "ポート設定を保存"
	b_port.theme_type_variation = "AccentButton"
	b_port.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b_port.pressed.connect(func():
		if _win.controller == null:
			return
		_win.controller.ws_port = int(_sp_ws.value)
		_win.controller.apply_vmc_settings({"recv_port": int(_sp_osc.value)})
		var r: Dictionary = _win.controller.save_config()
		if r.get("ok", false):
			_win.show_snackbar("ポート設定を保存しました（OSC 受信ポートは即時反映、WS ポートは再起動後に反映）。")
		else:
			_win.show_snackbar("保存失敗: " + str(r.get("error", "")))
	)
	c_srv["body"].add_child(b_port)

	# ---- VMC プロトコル (受信)
	var c_rx: Dictionary = UiWidgets.card(vb, "VMC プロトコル（受信：外部アプリから動かす）")
	UiWidgets.note(c_rx["body"], "VSeeFace / VirtualMotionCapture / Waidayo / mocopi / 内蔵トラッキング等からの OSC (UDP) 受信を設定します。")

	_chk_vmc_recv_en = UiWidgets.check(c_rx["body"], "VMC 受信を有効にする", true, func(on: bool):
		apply_vmc.call({"recv_enabled": on})
	, is_sync)

	_chk_vmc_recv_lan = UiWidgets.check(c_rx["body"], "LAN 内の別端末からも受信する (0.0.0.0 待受)", false, func(on: bool):
		apply_vmc.call({"recv_bind_lan": on})
	, is_sync)

	_lbl_local_ip = Label.new()
	_lbl_local_ip.theme_type_variation = "DimLabel"
	_lbl_local_ip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c_rx["body"].add_child(_lbl_local_ip)

	var rx_port_row := UiWidgets.labeled_row(c_rx["body"], "受信ポート (UDP)", 150)
	_sp_vmc_recv_port = SpinBox.new()
	_sp_vmc_recv_port.min_value = 1024
	_sp_vmc_recv_port.max_value = 65535
	_sp_vmc_recv_port.custom_minimum_size.x = 110
	rx_port_row.add_child(_sp_vmc_recv_port)

	var b_rx_apply := Button.new()
	b_rx_apply.text = "適用（再起動不要）"
	b_rx_apply.theme_type_variation = "AccentButton"
	b_rx_apply.pressed.connect(func():
		apply_vmc.call({
			"recv_enabled": _chk_vmc_recv_en.button_pressed,
			"recv_bind_lan": _chk_vmc_recv_lan.button_pressed,
			"recv_port": int(_sp_vmc_recv_port.value),
			"force": true,
		})
		_sp_osc.value = int(_sp_vmc_recv_port.value)
	)
	rx_port_row.add_child(b_rx_apply)

	_lbl_vmc_recv_status = Label.new()
	_lbl_vmc_recv_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c_rx["body"].add_child(_lbl_vmc_recv_status)

	_chk_recv_root = UiWidgets.check(c_rx["body"], "ルート移動・回転を反映 (/VMC/Ext/Root/Pos)", true, func(on: bool):
		apply_vmc.call({"recv_apply_root": on})
	, is_sync)
	_chk_recv_bones = UiWidgets.check(c_rx["body"], "ボーン姿勢を反映 (/VMC/Ext/Bone/Pos)", true, func(on: bool):
		apply_vmc.call({"recv_apply_bones": on})
	, is_sync)
	_chk_recv_expr = UiWidgets.check(c_rx["body"], "表情・まばたきを反映 (/VMC/Ext/Blend/Val)", true, func(on: bool):
		apply_vmc.call({"recv_apply_expressions": on})
	, is_sync)
	_chk_recv_cam = UiWidgets.check(c_rx["body"], "カメラ位置・画角を同期 (/VMC/Ext/Cam)", false, func(on: bool):
		apply_vmc.call({"recv_apply_camera": on})
	, is_sync)

	# ---- VMC プロトコル (送信)
	var c_tx: Dictionary = UiWidgets.card(vb, "VMC プロトコル（送信：他アプリへ送る）")
	UiWidgets.note(c_tx["body"], "表示中のアバターの姿勢・表情・リップシンク・カメラを他の VMC 対応アプリへ OSC (UDP) 送信します。")

	_chk_vmc_send_en = UiWidgets.check(c_tx["body"], "VMC 送信を有効にする", false, func(on: bool):
		apply_vmc.call({
			"send_enabled": on,
			"send_host": _le_send_host.text,
			"send_port": int(_sp_vmc_send_port.value),
		})
	, is_sync)

	var tx_host_row := UiWidgets.labeled_row(c_tx["body"], "送信先 IP / ホスト", 150)
	_le_send_host = LineEdit.new()
	_le_send_host.text = "127.0.0.1"
	_le_send_host.placeholder_text = "127.0.0.1 または相手の LAN IP"
	_le_send_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tx_host_row.add_child(_le_send_host)

	var tx_port_row := UiWidgets.labeled_row(c_tx["body"], "送信先ポート (UDP)", 150)
	_sp_vmc_send_port = SpinBox.new()
	_sp_vmc_send_port.min_value = 1024
	_sp_vmc_send_port.max_value = 65535
	_sp_vmc_send_port.value = 39540
	_sp_vmc_send_port.custom_minimum_size.x = 110
	tx_port_row.add_child(_sp_vmc_send_port)

	var b_tx_apply := Button.new()
	b_tx_apply.text = "送信先を適用"
	b_tx_apply.theme_type_variation = "AccentButton"
	b_tx_apply.pressed.connect(func():
		apply_vmc.call({
			"send_enabled": _chk_vmc_send_en.button_pressed,
			"send_host": _le_send_host.text,
			"send_port": int(_sp_vmc_send_port.value),
			"force": true,
		})
	)
	tx_port_row.add_child(b_tx_apply)

	_opt_send_fps = UiWidgets.option_row(c_tx["body"], "送信レート", [
		["30", "30 FPS（省負荷）"],
		["60", "60 FPS（標準）"],
		["90", "90 FPS"],
		["120", "120 FPS"],
	], func(v: String):
		apply_vmc.call({"send_fps": int(v)})
	, is_sync, 150)

	_lbl_vmc_send_status = Label.new()
	_lbl_vmc_send_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c_tx["body"].add_child(_lbl_vmc_send_status)

	_chk_send_bones = UiWidgets.check(c_tx["body"], "姿勢・ルートを送信 (/VMC/Ext/Bone/Pos・Root)", true, func(on: bool):
		apply_vmc.call({"send_bones": on})
	, is_sync)
	_chk_send_expr = UiWidgets.check(c_tx["body"], "表情・リップシンクを送信 (/VMC/Ext/Blend/Val)", true, func(on: bool):
		apply_vmc.call({"send_expressions": on})
	, is_sync)
	_chk_send_cam = UiWidgets.check(c_tx["body"], "カメラ位置・画角を送信 (/VMC/Ext/Cam)", false, func(on: bool):
		apply_vmc.call({"send_camera": on})
	, is_sync)
	_chk_send_vrm0 = UiWidgets.check(c_tx["body"], "表情名を VRM 0.x 互換 (Joy / A / Blink_L 等) で送る", true, func(on: bool):
		apply_vmc.call({"send_vrm0_names": on})
	, is_sync)

	# ---- 設定の管理
	var c_cfg: Dictionary = UiWidgets.card(vb, "設定ファイルの管理")
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	c_cfg["body"].add_child(brow)

	var b_save := Button.new()
	b_save.text = "設定を保存"
	b_save.pressed.connect(func(): _win.action_save_config())
	brow.add_child(b_save)

	var b_reload := Button.new()
	b_reload.text = "設定を再読込"
	b_reload.pressed.connect(func():
		if _win.controller == null:
			return
		var r: Dictionary = _win.controller.reload_config()
		if r.get("ok", false):
			_win.show_snackbar("設定ファイルから再読込しました。")
		else:
			_win.show_snackbar("再読込失敗: " + str(r.get("error", "")))
	)
	brow.add_child(b_reload)

	var b_exp := Button.new()
	b_exp.text = "別名で書き出し..."
	b_exp.pressed.connect(func(): _win.action_export_config())
	brow.add_child(b_exp)

	var b_imp := Button.new()
	b_imp.text = "別ファイルから読込..."
	b_imp.pressed.connect(func(): _win.action_import_config())
	brow.add_child(b_imp)

	var b_rst_all := Button.new()
	b_rst_all.text = "全設定を初期値に戻す"
	b_rst_all.theme_type_variation = "DangerButton"
	b_rst_all.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b_rst_all.pressed.connect(func():
		if _win.controller == null:
			return
		_win.confirm(
			"全設定を初期値に戻す",
			"カメラ・ライト・背景・シェーダー・ポーズなど全ての設定を初期値に戻しますか？",
			"初期値に戻す",
			func():
				if _win.controller != null:
					_win.controller.reset_all_settings()
					_win.show_snackbar("全設定を初期値に戻しました。")
		)
	)
	c_cfg["body"].add_child(b_rst_all)

	# ---- ショートカット一覧
	var c_sc: Dictionary = UiWidgets.card(vb, "操作・ショートカット一覧")
	var shortcuts := [
		["ファイル D&D", ".vrm / .vrma / .npz / 画像をメインウィンドウへドロップして読み込み"],
		["左ドラッグ", "カメラ回転 (オービット)"],
		["Shift + 左 / 中ドラッグ", "カメラ平行移動 (パン)"],
		["マウスホイール", "カメラ拡大・縮小 (ズーム)"],
		["Alt + 左ドラッグ", "枠なしウィンドウ時のウィンドウ移動"],
		["右クリック", "コンテキストメニュー表示 (設定・ポーズ・カメラ・背景など)"],
		["Ctrl + Shift + S", "設定ウィンドウを開く / 閉じる"],
		["F1 〜 F10", "表情ショートカット (表情タブでカスタマイズ可能)"],
		["F11 / F12", "スクリーンショット撮影 / 録画の開始・停止"],
	]
	for pair in shortcuts:
		var r := UiWidgets.labeled_row(c_sc["body"], str(pair[0]), 175)
		var l := Label.new()
		l.text = str(pair[1])
		l.theme_type_variation = "DimLabel"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(l)


func sync(st: Dictionary) -> void:
	var api: Dictionary = st.get("api", {})
	var running := bool(api.get("running", false))
	var ws := int(api.get("ws_port", 19100))
	var osc := int(api.get("osc_port", 39539))
	if running:
		_lbl_srv.text = "● WebSocket 稼働中 — ws://127.0.0.1:%d" % ws
		_lbl_srv.add_theme_color_override("font_color", UiTheme.STATUS_OK)
	else:
		_lbl_srv.text = "● 停止中（または別インスタンスがポートを使用中）— ws:%d / osc:%d" % [ws, osc]
		_lbl_srv.add_theme_color_override("font_color", UiTheme.STATUS_WARN)

	_sp_ws.value = ws
	_sp_osc.value = osc

	var vmc: Dictionary = st.get("vmc", {})
	if not vmc.is_empty():
		_chk_vmc_recv_en.button_pressed = bool(vmc.get("recv_enabled", true))
		_chk_vmc_recv_lan.button_pressed = bool(vmc.get("recv_bind_lan", false))
		_sp_vmc_recv_port.value = int(vmc.get("recv_port", osc))
		_chk_recv_root.button_pressed = bool(vmc.get("recv_apply_root", true))
		_chk_recv_bones.button_pressed = bool(vmc.get("recv_apply_bones", true))
		_chk_recv_expr.button_pressed = bool(vmc.get("recv_apply_expressions", true))
		_chk_recv_cam.button_pressed = bool(vmc.get("recv_apply_camera", false))

		_chk_vmc_send_en.button_pressed = bool(vmc.get("send_enabled", false))
		if not _le_send_host.has_focus():
			_le_send_host.text = str(vmc.get("send_host", "127.0.0.1"))
		_sp_vmc_send_port.value = int(vmc.get("send_port", 39540))
		UiWidgets.select_option_by_meta(_opt_send_fps, str(int(vmc.get("send_fps", 60))))
		_chk_send_bones.button_pressed = bool(vmc.get("send_bones", true))
		_chk_send_expr.button_pressed = bool(vmc.get("send_expressions", true))
		_chk_send_cam.button_pressed = bool(vmc.get("send_camera", false))
		_chk_send_vrm0.button_pressed = bool(vmc.get("send_vrm0_names", true))
		_update_vmc_status_labels(vmc)


func update_live() -> void:
	if _win.controller == null:
		return
	_update_vmc_status_labels(_win.controller.get_vmc_state())


func _update_vmc_status_labels(vmc: Dictionary) -> void:
	var rx_port := int(vmc.get("recv_port", 39539))
	var ips: Array = vmc.get("local_ips", [])
	if bool(vmc.get("recv_bind_lan", false)):
		if ips.is_empty():
			_lbl_local_ip.text = "LAN 待受中 (0.0.0.0:%d) — ローカル IP が見つかりません" % rx_port
		else:
			_lbl_local_ip.text = "スマホ等からの送信先 IP: %s (ポート %d)" % [", ".join(ips), rx_port]
	else:
		_lbl_local_ip.text = "同一 PC 限定 (127.0.0.1:%d)" % rx_port

	var rx: Dictionary = vmc.get("receiver", {})
	if bool(rx.get("running", false)):
		var baddr := str(rx.get("bind", "127.0.0.1"))
		var bport := int(rx.get("port", rx_port))
		var pps := int(rx.get("packets_per_sec", 0))
		var peer := str(rx.get("last_peer", ""))
		if bool(rx.get("active", false)) and peer != "":
			_lbl_vmc_recv_status.text = "● 受信中 (%s:%d) — 接続元 %s • %d pkt/s" % [baddr, bport, peer, pps]
			_lbl_vmc_recv_status.add_theme_color_override("font_color", UiTheme.STATUS_OK)
		else:
			_lbl_vmc_recv_status.text = "● 待機中 (%s:%d) — データ待ち" % [baddr, bport]
			_lbl_vmc_recv_status.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	else:
		var rerr := str(rx.get("error", ""))
		if rerr == "":
			rerr = str(vmc.get("last_error", ""))
		if rerr != "":
			_lbl_vmc_recv_status.text = "● 受信停止・エラー: " + rerr
			_lbl_vmc_recv_status.add_theme_color_override("font_color", UiTheme.DANGER_TEXT)
		elif bool(vmc.get("recv_enabled", true)):
			_lbl_vmc_recv_status.text = "● 受信未起動（連携サーバー停止中またはポート競合）"
			_lbl_vmc_recv_status.add_theme_color_override("font_color", UiTheme.STATUS_WARN)
		else:
			_lbl_vmc_recv_status.text = "● 受信オフ"
			_lbl_vmc_recv_status.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)

	var tx: Dictionary = vmc.get("sender", {})
	if bool(tx.get("running", false)):
		var tgt := str(tx.get("target", ""))
		var sent := int(tx.get("packets_sent", 0))
		var terr := str(tx.get("last_error", ""))
		if terr != "":
			_lbl_vmc_send_status.text = "● 送信エラー (%s): %s" % [tgt, terr]
			_lbl_vmc_send_status.add_theme_color_override("font_color", UiTheme.DANGER_TEXT)
		else:
			_lbl_vmc_send_status.text = "● 送信中 → %s • %d パケット送信済み" % [tgt, sent]
			_lbl_vmc_send_status.add_theme_color_override("font_color", UiTheme.STATUS_OK)
	else:
		var serr := str(tx.get("error", vmc.get("last_error", "")))
		if serr != "":
			_lbl_vmc_send_status.text = "● 送信停止: " + serr
			_lbl_vmc_send_status.add_theme_color_override("font_color", UiTheme.STATUS_WARN)
		else:
			_lbl_vmc_send_status.text = "● 送信オフ"
			_lbl_vmc_send_status.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
