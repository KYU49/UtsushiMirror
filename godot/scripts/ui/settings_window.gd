extends Window

## うつしみらー 設定ウィンドウ。
## 各ページは godot/scripts/ui/tabs/tab_*.gd に分割し、現在開いているタブだけを同期する。

const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const UiWidgets := preload("res://scripts/ui/ui_widgets.gd")

const TabModelScript := preload("res://scripts/ui/tabs/tab_model.gd")
const TabCameraScript := preload("res://scripts/ui/tabs/tab_camera.gd")
const TabLightScript := preload("res://scripts/ui/tabs/tab_light.gd")
const TabEffectsScript := preload("res://scripts/ui/tabs/tab_effects.gd")
const TabPoseScript := preload("res://scripts/ui/tabs/tab_pose.gd")
const TabAnimScript := preload("res://scripts/ui/tabs/tab_anim.gd")
const TabExprScript := preload("res://scripts/ui/tabs/tab_expr.gd")
const TabTrackingScript := preload("res://scripts/ui/tabs/tab_tracking.gd")
const TabWindowScript := preload("res://scripts/ui/tabs/tab_window.gd")
const TabOutputScript := preload("res://scripts/ui/tabs/tab_output.gd")
const TabApiScript := preload("res://scripts/ui/tabs/tab_api.gd")
const TabLicenseScript := preload("res://scripts/ui/tabs/tab_license.gd")

const NAV_GROUPS := [
	{
		"group": "シーン",
		"items": [
			["Model", "モデル", "読込・配置・揺れもの"],
			["Camera", "カメラ", "視点・距離・画角"],
			["Light", "ライト", "方向・3点照明・露出"],
			["Effects", "シェーダー", "画面効果・陰影・影"],
		],
	},
	{
		"group": "キャラクター",
		"items": [
			["Pose", "ポーズ", "プリセット・ボーン調整"],
			["Anim", "モーション", "VRMA・自然な待機動作"],
			["Expr", "表情・視線", "表情値・LookAt・キー"],
			["Tracking", "トラッキング", "Webカメラ・動作追跡"],
		],
	},
	{
		"group": "システム",
		"items": [
			["Window", "ウィンドウ", "背景・透過・マスコット"],
			["Output", "出力・録画", "OBS・Spout2・スクショ"],
			["API/Config", "連携・設定", "WS/OSC・設定リセット"],
			["License", "ライセンス", "OSS・著作権表記"],
		],
	},
]

var controller = null

# 公開・テスト互換プロパティ
var is_syncing: bool:
	get:
		return _sync_depth > 0

var _sync_depth: int = 0
var _syncing_cb: Callable
var _built: bool = false

var _root_bg: ColorRect
var _hdr_model_lbl: Label
var _hdr_api_lbl: Label

var _nav_btns: Dictionary = {}      # tab_id -> Button
var _nav_titles: Dictionary = {}    # tab_id -> Label
var _nav_idx: Dictionary = {}       # tab_id -> int
var _tab_handlers: Dictionary = {}  # tab_id -> Tab instance
var _dirty_tabs: Dictionary = {}    # tab_id -> bool
var _tab_container: TabContainer
var _active_tab_id: String = "Model"

var _tab_anim
var _tab_expr
var _tab_tracking
var _tab_api
var _tab_license

var _recent_cfg_btn: OptionButton

# Tracking テスト互換参照 (test_tracker_install.gd / test_tracking_ui.gd)
var _trk_install_box: Control
var _trk_install_btn: Button
var _trk_start_row: Control
var _trk_install_dlg: ConfirmationDialog
var _trk_status_lbl: Label
var _trk_start_btn: Button
var _trk_calib_btn: Button
var _trk_sec: Dictionary = {}
var _trk_mode_btns: Dictionary = {}

var _trk_timer: Timer

var _dlg_export_cfg: FileDialog
var _dlg_import_cfg: FileDialog
var _confirm_dlg: ConfirmationDialog
var _confirm_cb: Callable

var _sb_holder: MarginContainer
var _sb_panel: PanelContainer
var _sb_lbl: Label
var _sb_btn: Button
var _sb_close: Button
var _sb_action: Callable
var _sb_timer: Timer


func _ready() -> void:
	title = "うつしみらー 設定"
	theme = UiTheme.get_theme()
	if DisplayServer.get_name() != "headless":
		size = Vector2i(840, 820)
		min_size = Vector2i(680, 560)
	close_requested.connect(func():
		if controller != null:
			controller.close_settings_window()
		else:
			hide()
	)
	window_input.connect(_on_window_input)
	visibility_changed.connect(_on_visibility_changed)
	_ensure_built()


func bind_controller(ctrl) -> void:
	if controller == ctrl and _built:
		_on_state_changed()
		return
	controller = ctrl
	_ensure_built()
	if controller != null:
		if not controller.state_changed.is_connected(_on_state_changed):
			controller.state_changed.connect(_on_state_changed)
		if not controller.model_loaded.is_connected(_on_model_loaded):
			controller.model_loaded.connect(_on_model_loaded)
		if controller.tracking != null:
			if not controller.tracking.cameras_refreshed.is_connected(_on_cameras_refreshed):
				controller.tracking.cameras_refreshed.connect(_on_cameras_refreshed)
			if not controller.tracking.installation_finished.is_connected(_on_tracking_installed):
				controller.tracking.installation_finished.connect(_on_tracking_installed)
		if controller.current_vrm != null and _tab_expr != null:
			_tab_expr.on_model_loaded(controller.current_vrm.get_model_info())
	_refresh_recent_settings()
	_on_state_changed()


func is_syncing_fn() -> Callable:
	if not _syncing_cb.is_valid():
		_syncing_cb = Callable(self, "_check_syncing")
	return _syncing_cb


func _check_syncing() -> bool:
	return _sync_depth > 0


func begin_sync() -> void:
	_sync_depth += 1


func end_sync() -> void:
	_sync_depth = maxi(_sync_depth - 1, 0)


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_syncing_cb = Callable(self, "_check_syncing")

	var root_ctrl := Control.new()
	root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_ctrl)

	_root_bg = ColorRect.new()
	_root_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_bg.color = UiTheme.BG_0
	_root_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ctrl.add_child(_root_bg)

	var main_vb := VBoxContainer.new()
	main_vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vb.add_theme_constant_override("separation", 0)
	root_ctrl.add_child(main_vb)

	# 最上部アクセントライン
	var accent_bar := ColorRect.new()
	accent_bar.color = UiTheme.ACCENT
	accent_bar.custom_minimum_size = Vector2(0, 3)
	accent_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vb.add_child(accent_bar)

	# ---- ヘッダー
	var hdr := PanelContainer.new()
	hdr.theme_type_variation = "Header"
	main_vb.add_child(hdr)

	var hdr_hb := HBoxContainer.new()
	hdr_hb.add_theme_constant_override("separation", 12)
	hdr.add_child(hdr_hb)

	var title_vb := VBoxContainer.new()
	title_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_vb.add_theme_constant_override("separation", 2)
	hdr_hb.add_child(title_vb)

	var lbl_title := Label.new()
	lbl_title.theme_type_variation = "TitleLabel"
	lbl_title.text = "うつしみらー  設定"
	title_vb.add_child(lbl_title)

	_hdr_model_lbl = Label.new()
	_hdr_model_lbl.theme_type_variation = "DimLabel"
	_hdr_model_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hdr_model_lbl.text = "モデル未読み込み — .vrm をメイン画面へドロップできます"
	title_vb.add_child(_hdr_model_lbl)

	_hdr_api_lbl = Label.new()
	_hdr_api_lbl.theme_type_variation = "DimLabel"
	_hdr_api_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hdr_api_lbl.text = "● API"
	hdr_hb.add_child(_hdr_api_lbl)

	var b_hdr_close := Button.new()
	b_hdr_close.text = "閉じる"
	b_hdr_close.pressed.connect(func():
		if controller != null:
			controller.close_settings_window()
		else:
			hide()
	)
	hdr_hb.add_child(b_hdr_close)

	# ---- 中央 2 カラム (左サイドバー + 右コンテンツ)
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 0)
	main_vb.add_child(mid)

	var sb_panel := PanelContainer.new()
	sb_panel.theme_type_variation = "Sidebar"
	sb_panel.custom_minimum_size.x = 188
	mid.add_child(sb_panel)

	var sb_scroll := ScrollContainer.new()
	sb_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sb_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sb_panel.add_child(sb_scroll)

	var sb_vb := VBoxContainer.new()
	sb_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb_vb.add_theme_constant_override("separation", 3)
	sb_scroll.add_child(sb_vb)

	_tab_container = TabContainer.new()
	_tab_container.tabs_visible = false
	_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(_tab_container)

	var tab_scripts := {
		"Model": TabModelScript,
		"Camera": TabCameraScript,
		"Light": TabLightScript,
		"Effects": TabEffectsScript,
		"Pose": TabPoseScript,
		"Anim": TabAnimScript,
		"Expr": TabExprScript,
		"Tracking": TabTrackingScript,
		"Window": TabWindowScript,
		"Output": TabOutputScript,
		"API/Config": TabApiScript,
		"License": TabLicenseScript,
	}

	var idx := 0
	for grp in NAV_GROUPS:
		var glbl := Label.new()
		glbl.theme_type_variation = "SidebarGroupLabel"
		glbl.text = str(grp["group"])
		sb_vb.add_child(glbl)

		for item in grp["items"]:
			var tid: String = item[0]
			var ttitle: String = item[1]
			var tsub: String = item[2]

			var nb := Button.new()
			nb.theme_type_variation = "NavButton"
			nb.toggle_mode = true
			nb.custom_minimum_size = Vector2(168, 46)
			nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nb.pressed.connect(func(): _select_tab(tid))

			var nvb := VBoxContainer.new()
			nvb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			nvb.offset_left = 10
			nvb.offset_right = -6
			nvb.offset_top = 4
			nvb.offset_bottom = -4
			nvb.add_theme_constant_override("separation", 1)
			nvb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			nb.add_child(nvb)

			var nlbl := Label.new()
			nlbl.theme_type_variation = "NavTitleLabel"
			nlbl.text = ttitle
			nlbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			nvb.add_child(nlbl)

			var slbl := Label.new()
			slbl.theme_type_variation = "SubNavLabel"
			slbl.text = tsub
			slbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			slbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			nvb.add_child(slbl)

			sb_vb.add_child(nb)
			_nav_btns[tid] = nb
			_nav_titles[tid] = nlbl
			_nav_idx[tid] = idx

			# タブコンテンツ領域 (ScrollContainer -> MarginContainer -> VBoxContainer)
			var sc := ScrollContainer.new()
			sc.name = tid
			sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_tab_container.add_child(sc)

			var mg := MarginContainer.new()
			mg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			mg.add_theme_constant_override("margin_left", 16)
			mg.add_theme_constant_override("margin_right", 16)
			mg.add_theme_constant_override("margin_top", 14)
			mg.add_theme_constant_override("margin_bottom", 18)
			sc.add_child(mg)

			var page_vb := VBoxContainer.new()
			page_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			page_vb.add_theme_constant_override("separation", 12)
			mg.add_child(page_vb)

			var handler = tab_scripts[tid].new()
			handler.build(self, page_vb)
			_tab_handlers[tid] = handler
			_dirty_tabs[tid] = true
			idx += 1

	_tab_anim = _tab_handlers["Anim"]
	_tab_expr = _tab_handlers["Expr"]
	_tab_tracking = _tab_handlers["Tracking"]
	_tab_api = _tab_handlers["API/Config"]
	_tab_license = _tab_handlers["License"]

	# Tracking テスト互換参照をリンク
	_trk_install_box = _tab_tracking._install_box
	_trk_install_btn = _tab_tracking._install_btn
	_trk_start_row = _tab_tracking._start_row
	_trk_install_dlg = _tab_tracking._install_dlg
	_trk_status_lbl = _tab_tracking._status_lbl
	_trk_start_btn = _tab_tracking._start_btn
	_trk_calib_btn = _tab_tracking._calib_btn
	_trk_sec = _tab_tracking._sec
	_trk_mode_btns = _tab_tracking._mode_btns

	# ---- フッター
	var ftr := PanelContainer.new()
	ftr.theme_type_variation = "Footer"
	main_vb.add_child(ftr)

	var ftr_hb := HBoxContainer.new()
	ftr_hb.add_theme_constant_override("separation", 8)
	ftr.add_child(ftr_hb)

	var b_save := Button.new()
	b_save.text = "設定を保存"
	b_save.theme_type_variation = "AccentButton"
	b_save.pressed.connect(func(): action_save_config())
	ftr_hb.add_child(b_save)

	var b_rel := Button.new()
	b_rel.text = "再読込"
	b_rel.pressed.connect(func():
		if controller == null:
			return
		var r: Dictionary = controller.reload_config()
		if r.get("ok", false):
			show_snackbar("設定を再読込しました。")
		else:
			show_snackbar("再読込失敗: " + str(r.get("error", "")))
	)
	ftr_hb.add_child(b_rel)

	var b_exp := Button.new()
	b_exp.text = "書き出し..."
	b_exp.pressed.connect(func(): action_export_config())
	ftr_hb.add_child(b_exp)

	var b_imp := Button.new()
	b_imp.text = "読込..."
	b_imp.pressed.connect(func(): action_import_config())
	ftr_hb.add_child(b_imp)

	_recent_cfg_btn = OptionButton.new()
	_recent_cfg_btn.custom_minimum_size.x = 156
	_recent_cfg_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_recent_cfg_btn.item_selected.connect(_on_recent_settings_selected)
	ftr_hb.add_child(_recent_cfg_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ftr_hb.add_child(spacer)

	var b_close := Button.new()
	b_close.text = "ウィンドウを閉じる"
	b_close.pressed.connect(func():
		if controller != null:
			controller.close_settings_window()
		else:
			hide()
	)
	ftr_hb.add_child(b_close)

	# ---- ダイアログ / タイマー / スナックバー
	_dlg_export_cfg = UiWidgets.file_dialog(self, FileDialog.FILE_MODE_SAVE_FILE, PackedStringArray(["*.umset ; うつしみらー設定ファイル", "*.json ; JSON 設定ファイル"]), func(p: String):
		if controller == null:
			return
		var r: Dictionary = controller.export_settings(p)
		if r.get("ok", false):
			show_snackbar("設定を書き出しました: " + str(r.get("path", p)).get_file())
			_refresh_recent_settings()
		else:
			show_snackbar("書き出し失敗: " + str(r.get("error", "")))
	, "utsushimirror_settings.umset")

	_dlg_import_cfg = UiWidgets.file_dialog(self, FileDialog.FILE_MODE_OPEN_FILE, PackedStringArray(["*.umset, *.json ; うつしみらー設定ファイル (*.umset, *.json)", "*.umset ; うつしみらー設定ファイル", "*.json ; JSON 設定ファイル"]), func(p: String):
		if controller == null:
			return
		var r: Dictionary = controller.import_settings(p)
		if r.get("ok", false):
			show_snackbar("設定を読み込みました: " + p.get_file())
			_refresh_recent_settings()
		else:
			show_snackbar("読み込み失敗: " + str(r.get("error", "")))
	)

	_confirm_dlg = ConfirmationDialog.new()
	_confirm_dlg.confirmed.connect(func():
		if _confirm_cb.is_valid():
			_confirm_cb.call()
	)
	add_child(_confirm_dlg)

	_trk_timer = Timer.new()
	_trk_timer.wait_time = 0.35
	_trk_timer.timeout.connect(func():
		if _active_tab_id == "Tracking" and _tab_tracking != null:
			_tab_tracking.update_live()
		elif _active_tab_id == "API/Config" and _tab_api != null:
			_tab_api.update_live()
	)
	add_child(_trk_timer)

	_build_snackbar(root_ctrl)
	_refresh_recent_settings()
	_select_tab("Model")


func _select_tab(tab_id: String) -> void:
	if not _nav_idx.has(tab_id):
		return
	_active_tab_id = tab_id
	_tab_container.current_tab = int(_nav_idx[tab_id])

	for tid in _nav_btns.keys():
		var active := (str(tid) == tab_id)
		var nb: Button = _nav_btns[tid]
		nb.button_pressed = active
		var nlbl: Label = _nav_titles[tid]
		nlbl.add_theme_color_override("font_color", UiTheme.TEXT if active else UiTheme.TEXT_DIM)

	if tab_id == "License" and _tab_license != null:
		_tab_license.ensure_loaded()

	_update_active_polling()
	_sync_active_tab()


func _update_active_polling() -> void:
	if _trk_timer == null:
		return
	var active_win := visible or DisplayServer.get_name() == "headless"
	if active_win and (_active_tab_id == "Tracking" or _active_tab_id == "API/Config"):
		if _trk_timer.is_stopped():
			_trk_timer.start()
	else:
		if not _trk_timer.is_stopped():
			_trk_timer.stop()


func _on_visibility_changed() -> void:
	_update_active_polling()
	if visible:
		_sync_active_tab()


func _process(_delta: float) -> void:
	if _active_tab_id == "Anim" and visible and _tab_anim != null:
		_tab_anim.update_scrubber()


func _on_state_changed() -> void:
	for tid in _dirty_tabs.keys():
		_dirty_tabs[tid] = true
	if controller == null:
		return
	var st: Dictionary = controller.get_full_state()
	_sync_header(st)
	_sync_tab_with_state(_active_tab_id, st)


func _on_model_loaded(info: Dictionary) -> void:
	if _tab_expr != null:
		_tab_expr.on_model_loaded(info)
	_on_state_changed()


func _on_cameras_refreshed(cams: Array) -> void:
	if _tab_tracking != null:
		_tab_tracking.on_cameras_refreshed(cams)


func _on_tracking_installed(ok: bool) -> void:
	if _tab_tracking != null:
		_tab_tracking.on_installed(ok)


func _sync_header(st: Dictionary) -> void:
	if _hdr_model_lbl == null:
		return
	if bool(st.get("model_loaded", false)):
		var mname := str(st.get("model_name", ""))
		var mpath := str(st.get("model_path", "")).get_file()
		_hdr_model_lbl.text = (mname + " (" + mpath + ")") if mname != "" else mpath
	else:
		_hdr_model_lbl.text = "モデル未読み込み — .vrm をメイン画面へドロップできます"

	var api: Dictionary = st.get("api", {})
	var running := bool(api.get("running", false))
	var ws := int(api.get("ws_port", 19100))
	_hdr_api_lbl.text = ("● API :%d" % ws) if running else "● API 停止"
	_hdr_api_lbl.add_theme_color_override("font_color", UiTheme.STATUS_OK if running else UiTheme.TEXT_MUTED)


func _sync_active_tab() -> void:
	if controller == null or not bool(_dirty_tabs.get(_active_tab_id, false)):
		return
	var st: Dictionary = controller.get_full_state()
	_sync_header(st)
	_sync_tab_with_state(_active_tab_id, st)


func _sync_tab_with_state(tid: String, st: Dictionary) -> void:
	if not _tab_handlers.has(tid):
		return
	begin_sync()
	_tab_handlers[tid].sync(st)
	end_sync()
	_dirty_tabs[tid] = false


# ---- アクション / ヘルパー
func action_save_config() -> void:
	if controller == null:
		return
	var r: Dictionary = controller.save_config()
	if r.get("ok", false):
		show_snackbar("設定を保存しました。")
	else:
		show_snackbar("保存失敗: " + str(r.get("error", "")))


func action_export_config() -> void:
	popup_at_vrm_dir(_dlg_export_cfg)


func action_import_config() -> void:
	popup_at_vrm_dir(_dlg_import_cfg)


func confirm(title_text: String, body_text: String, ok_text: String, on_ok: Callable) -> void:
	_confirm_cb = on_ok
	_confirm_dlg.title = title_text
	_confirm_dlg.dialog_text = body_text
	_confirm_dlg.ok_button_text = ok_text
	if DisplayServer.get_name() == "headless":
		return
	_confirm_dlg.popup_centered()


func popup_at_vrm_dir(dlg: FileDialog) -> void:
	if dlg == null:
		return
	if controller != null and controller.current_vrm != null and str(controller.current_vrm.model_path) != "":
		dlg.current_dir = str(controller.current_vrm.model_path).get_base_dir()
	if DisplayServer.get_name() != "headless":
		dlg.popup_centered(Vector2i(760, 520))


# ---- 最近使った設定ファイル (test_recent_settings.gd 互換)
func _refresh_recent_settings() -> void:
	if _recent_cfg_btn == null:
		return
	_recent_cfg_btn.clear()
	_recent_cfg_btn.add_item("最近使った設定")
	_recent_cfg_btn.set_item_metadata(0, "")
	var paths: Array = controller.get_recent_settings_paths() if controller != null else []
	if paths.is_empty():
		_recent_cfg_btn.add_item("（履歴なし）")
		_recent_cfg_btn.set_item_metadata(1, "")
		_recent_cfg_btn.set_item_disabled(1, true)
	else:
		for p_raw in paths:
			var p := str(p_raw)
			_recent_cfg_btn.add_item(p.get_file())
			var item_idx := _recent_cfg_btn.item_count - 1
			_recent_cfg_btn.set_item_metadata(item_idx, p)
			_recent_cfg_btn.set_item_tooltip(item_idx, p)
		_recent_cfg_btn.add_separator()
		_recent_cfg_btn.add_item("履歴を消す")
		_recent_cfg_btn.set_item_metadata(_recent_cfg_btn.item_count - 1, "__clear__")
	_recent_cfg_btn.select(0)


func _on_recent_settings_selected(idx: int) -> void:
	if _recent_cfg_btn == null or idx < 0 or idx >= _recent_cfg_btn.item_count:
		return
	if _recent_cfg_btn.is_item_separator(idx) or _recent_cfg_btn.is_item_disabled(idx):
		_recent_cfg_btn.select(0)
		return
	var raw_meta: Variant = _recent_cfg_btn.get_item_metadata(idx)
	var meta: String = str(raw_meta) if raw_meta != null else ""
	_recent_cfg_btn.select(0)
	if meta == "":
		return
	if meta == "__clear__":
		if controller != null:
			controller.clear_recent_settings_paths()
		_refresh_recent_settings()
		show_snackbar("最近使った設定の履歴を消しました。")
		return
	if controller != null:
		var r: Dictionary = controller.import_settings(meta)
		if r.get("ok", false):
			show_snackbar("設定を読み込みました: " + meta.get_file())
		else:
			show_snackbar("読み込み失敗: " + str(r.get("error", "")))
		_refresh_recent_settings()


# ---- Tracking テスト互換転送メソッド
func tracking_install_message(info: Dictionary) -> Dictionary:
	return _tab_tracking.tracking_install_message(info) if _tab_tracking != null else {"text": "", "enough": false}


func _show_tracking_install_dialog() -> void:
	if _tab_tracking != null:
		_tab_tracking.show_install_dialog()


func _refresh_tracking_install() -> void:
	if _tab_tracking != null:
		_tab_tracking.refresh_install()


# ---- スナックバー (画面下端トースト通知)
func _build_snackbar(root_ctrl: Control) -> void:
	_sb_holder = MarginContainer.new()
	_sb_holder.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_sb_holder.offset_top = -124
	_sb_holder.offset_bottom = -58
	_sb_holder.add_theme_constant_override("margin_left", 24)
	_sb_holder.add_theme_constant_override("margin_right", 24)
	_sb_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sb_holder.visible = false
	root_ctrl.add_child(_sb_holder)

	var res: Dictionary = UiWidgets.make_toast_panel()
	_sb_panel = res["panel"]
	_sb_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_sb_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	_sb_holder.add_child(_sb_panel)

	var hb: HBoxContainer = res["hbox"]
	_sb_lbl = Label.new()
	_sb_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sb_lbl.custom_minimum_size.x = 180
	hb.add_child(_sb_lbl)

	_sb_btn = Button.new()
	_sb_btn.theme_type_variation = "AccentButton"
	_sb_btn.visible = false
	_sb_btn.pressed.connect(func():
		var cb := _sb_action
		hide_snackbar()
		if cb.is_valid():
			cb.call()
	)
	hb.add_child(_sb_btn)

	_sb_close = Button.new()
	_sb_close.text = "×"
	_sb_close.pressed.connect(hide_snackbar)
	hb.add_child(_sb_close)

	_sb_timer = Timer.new()
	_sb_timer.one_shot = true
	_sb_timer.timeout.connect(hide_snackbar)
	add_child(_sb_timer)


func show_snackbar(message: String, action_text: String = "", action: Callable = Callable(), seconds: float = 5.0) -> void:
	if _sb_holder == null:
		return
	_sb_lbl.text = message
	_sb_action = action
	if action_text != "" and action.is_valid():
		_sb_btn.text = action_text
		_sb_btn.visible = true
	else:
		_sb_btn.visible = false
	_sb_holder.visible = true
	_sb_timer.start(maxf(seconds, 0.5))


func hide_snackbar() -> void:
	if _sb_holder != null:
		_sb_holder.visible = false
	if _sb_timer != null and not _sb_timer.is_stopped():
		_sb_timer.stop()
	_sb_action = Callable()


# ---- ショートカットキー転送
func _on_window_input(event: InputEvent) -> void:
	if controller == null or controller.hotkey_manager == null:
		return
	var focus_owner: Control = gui_get_focus_owner()
	if focus_owner is LineEdit or focus_owner is TextEdit:
		return
	if controller.hotkey_manager.handle_key_event(event):
		get_viewport().set_input_as_handled()
