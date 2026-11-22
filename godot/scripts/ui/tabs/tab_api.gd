extends RefCounted

const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const UiWidgets := preload("res://scripts/ui/ui_widgets.gd")

var _win
var _lbl_srv: Label
var _sp_ws: SpinBox
var _sp_osc: SpinBox


func build(win, vb: VBoxContainer) -> void:
	_win = win

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
		_win.controller.osc_port = int(_sp_osc.value)
		var r: Dictionary = _win.controller.save_config()
		if r.get("ok", false):
			_win.show_snackbar("ポート設定を保存しました（アプリ再起動後に反映されます）。")
		else:
			_win.show_snackbar("保存失敗: " + str(r.get("error", "")))
	)
	c_srv["body"].add_child(b_port)

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
		_lbl_srv.text = "● 稼働中 — ws://127.0.0.1:%d / OSC UDP :%d" % [ws, osc]
		_lbl_srv.add_theme_color_override("font_color", UiTheme.STATUS_OK)
	else:
		_lbl_srv.text = "● 停止中（または別インスタンスがポートを使用中）— ws:%d / osc:%d" % [ws, osc]
		_lbl_srv.add_theme_color_override("font_color", UiTheme.STATUS_WARN)

	_sp_ws.value = ws
	_sp_osc.value = osc
