extends Window

## Separate native OS settings window (never captured by Spout2, VirtualCam, or screenshots).
## Every control delegates to AppController and syncs back on AppController.state_changed.

const TrackingManagerScript := preload("res://scripts/core/tracking_manager.gd")
const PostEffectsScript := preload("res://scripts/core/post_effects.gd")
const HelpMarkScript := preload("res://scripts/ui/help_mark.gd")
const UiHelpScript := preload("res://scripts/ui/ui_help.gd")

var controller = null
var _syncing: bool = false

const ConfigManagerScript := preload("res://scripts/core/config_manager.gd")
const AnimCategoryScript := preload("res://scripts/core/anim_category.gd")
const UiThemeScript := preload("res://scripts/ui/ui_theme.gd")
const LightDirectionPadScript := preload("res://scripts/ui/light_direction_pad.gd")
const LightingRigScript := preload("res://scripts/core/lighting_rig.gd")

const BONE_GROUPS := {
	"体幹・頭": ["hips", "spine", "chest", "upperChest", "neck", "head", "leftEye", "rightEye", "jaw"],
	"左腕・左指": [
		"leftShoulder", "leftUpperArm", "leftLowerArm", "leftHand",
		"leftThumbMetacarpal", "leftThumbProximal", "leftThumbDistal",
		"leftIndexProximal", "leftIndexIntermediate", "leftIndexDistal",
		"leftMiddleProximal", "leftMiddleIntermediate", "leftMiddleDistal",
		"leftRingProximal", "leftRingIntermediate", "leftRingDistal",
		"leftLittleProximal", "leftLittleIntermediate", "leftLittleDistal",
	],
	"右腕・右指": [
		"rightShoulder", "rightUpperArm", "rightLowerArm", "rightHand",
		"rightThumbMetacarpal", "rightThumbProximal", "rightThumbDistal",
		"rightIndexProximal", "rightIndexIntermediate", "rightIndexDistal",
		"rightMiddleProximal", "rightMiddleIntermediate", "rightMiddleDistal",
		"rightRingProximal", "rightRingIntermediate", "rightRingDistal",
		"rightLittleProximal", "rightLittleIntermediate", "rightLittleDistal",
	],
	"脚": [
		"leftUpperLeg", "leftLowerLeg", "leftFoot", "leftToes",
		"rightUpperLeg", "rightLowerLeg", "rightFoot", "rightToes",
	],
}

const DEFAULT_BONE_LIST: Array[String] = [
	"hips", "spine", "chest", "upperChest", "neck", "head",
	"leftShoulder", "leftUpperArm", "leftLowerArm", "leftHand",
	"rightShoulder", "rightUpperArm", "rightLowerArm", "rightHand",
	"leftUpperLeg", "leftLowerLeg", "leftFoot", "leftToes",
	"rightUpperLeg", "rightLowerLeg", "rightFoot", "rightToes",
]

var _tabs: TabContainer
var _file_dialog_out_img: FileDialog
var _status_footer_lbl: Label
## 下の段の「最近の設定」ドロップダウン
var _recent_cfg_btn: OptionButton
var _recent_cfg_paths: Array[String] = []

# Tab 1: Model
var _model_status_lbl: Label
var _recent_opt: OptionButton
var _m_pos_x: HSlider
var _m_pos_y: HSlider
var _m_pos_z: HSlider
var _m_rot_y: HSlider
var _m_scale: HSlider
var _first_person_chk: CheckBox
var _sb_enabled_chk: CheckBox
var _sb_grav_slider: HSlider
var _sb_stiff_slider: HSlider
var _spring_wind_x: HSlider
var _spring_wind_y: HSlider
var _spring_wind_z: HSlider
var _meta_text: RichTextLabel

# Tab 2: Camera
var _cam_yaw_slider: HSlider
var _cam_pitch_slider: HSlider
var _cam_dist_slider: HSlider
var _cam_tgt_x: HSlider
var _cam_tgt_y: HSlider
var _cam_tgt_z: HSlider
var _fov_slider: HSlider
var _ortho_chk: CheckBox

# Tab 3: Light
var _light_pad = null
var _light_dir_lbl: Label
var _light_gizmo_chk: CheckBox
var _key_az_slider: HSlider
var _key_el_slider: HSlider
var _key_en_slider: HSlider
var _key_col_btn: ColorPickerButton
var _fill_en_slider: HSlider
var _fill_col_btn: ColorPickerButton
var _rim_en_slider: HSlider
var _rim_col_btn: ColorPickerButton
var _amb_en_slider: HSlider
var _amb_col_btn: ColorPickerButton
var _shadows_chk: CheckBox
var _bloom_chk: CheckBox
var _bloom_int_slider: HSlider
var _exposure_slider: HSlider
var _tonemap_opt: OptionButton
var _fx_style_btns: Dictionary = {}
var _fx_sliders: Dictionary = {}
var _fx_light_sliders: Dictionary = {}
var _fx_colors: Dictionary = {}
var _fx_checks: Dictionary = {}
var _fx_desc_lbl: Label
var _fx_letterbox_opt: OptionButton
var _fx_quality_opt: OptionButton

# Tab 4: Pose
var _pose_stop_anim_chk: CheckBox
var _pose_filter_opt: OptionButton
var _pose_bone_opt: OptionButton
var _pose_bx: HSlider
var _pose_by: HSlider
var _pose_bz: HSlider
var _pose_hx: HSlider
var _pose_hy: HSlider
var _pose_hz: HSlider
var _pose_edited_lbl: Label
var _available_human_bones: Array[String] = []

# Tab 5: Anim
var _anim_list: GridContainer  # 動きの一覧 (2 列。見出しは Label、動きは Button)
var _anim_selected := ""  # 一覧で選んでいる動きの名前
var _anim_btn_group := ButtonGroup.new()
var _anim_cat_opt: OptionButton  # カテゴリーで絞る (0 = すべて)
var _anim_names_shown: Array = []  # 一覧に出している名前 (変わったときだけ作り直す)
var _fx_preset_flow: HFlowContainer
var _fx_preset_name: LineEdit
var _anim_scrub: HSlider
var _anim_time_lbl: Label
var _scrub_dragging: bool = false
var _anim_loop_chk: CheckBox
var _anim_speed_slider: HSlider
var _anim_blend_slider: HSlider
var _idle_enabled_chk: CheckBox
var _idle_breath_chk: CheckBox
var _idle_blink_chk: CheckBox
var _idle_saccade_chk: CheckBox
var _idle_sway_chk: CheckBox
var _idle_intensity_slider: HSlider

# Tab 6: Expr
var _lookat_opt: OptionButton
var _lookat_tx: HSlider
var _lookat_ty: HSlider
var _lookat_tz: HSlider
var _expr_trans_slider: HSlider
var _expr_box: VBoxContainer
var _expr_sliders: Dictionary = {}
var _global_hk_chk: CheckBox
var _hotkey_edits: Dictionary = {}

# Tab 7: Window
var _bg_mode_opt: OptionButton
var _bg_color_btn: ColorPickerButton
var _bg_grad_bot_btn: ColorPickerButton
var _bg_img_lbl: Label
var _win_trans_chk: CheckBox
var _win_border_chk: CheckBox
var _win_top_chk: CheckBox
var _win_click_chk: CheckBox
var _win_w_spin: SpinBox
var _win_h_spin: SpinBox

# Tab 8: Output
var _out_res_opt: OptionButton
var _out_bg_opt: OptionButton
var _out_color_btn: ColorPickerButton
var _rec_fps_opt: OptionButton
var _spout_chk: CheckBox
var _spout_name_edit: LineEdit
var _vcam_chk: CheckBox
var _vcam_status_lbl: Label
var _rec_status_lbl: Label
var _rec_mp4_btn: Button
var _rec_webm_btn: Button

# Tab 9: API/Config
var _api_status_lbl: Label
var _ws_port_spin: SpinBox
var _osc_port_spin: SpinBox


func _ready() -> void:
	title = "うつしみらー コントロール"
	size = Vector2i(880, 820)
	min_size = Vector2i(700, 560)
	transient = false
	theme = UiThemeScript.get_theme()
	close_requested.connect(_on_close_requested)
	window_input.connect(_on_window_input)
	# スライダーはマウスホイールで動かさない (ページをスクロールしようとして値が変わるのを防ぐ)。
	# ホイールは親のスクロールへそのまま渡す。後から作られるスライダーにも効くよう node_added で拾う
	get_tree().node_added.connect(func(n: Node):
		if n is Slider and is_ancestor_of(n):
			_no_wheel(n as Slider)
	)
	_build_ui()
	for n in find_children("*", "Slider", true, false):
		_no_wheel(n as Slider)
	var poll := Timer.new()
	poll.wait_time = 0.25
	poll.autostart = true
	poll.timeout.connect(func():
		if controller != null and visible:
			var running: bool = controller.tracking.is_running()
			if running != _trk_last_running:
				_trk_last_running = running
				_refresh_tracking_ui(controller.get_full_state())
			else:
				_update_tracking_live()
			_refresh_tracking_install()
	)
	add_child(poll)


func _on_close_requested() -> void:
	if controller != null and controller.has_method("close_settings_window"):
		controller.close_settings_window()
	else:
		visible = false


func _process(_delta: float) -> void:
	if not visible or controller == null or _anim_scrub == null:
		return
	if controller.vrma_player != null and controller.vrma_player.playing and controller.vrma_player.current_clip != null:
		var dur: float = maxf(float(controller.vrma_player.current_clip.duration), 0.01)
		var t: float = clampf(float(controller.vrma_player.time_sec), 0.0, dur)
		if not _scrub_dragging:
			_syncing = true
			_anim_scrub.max_value = dur
			_anim_scrub.value = t
			_syncing = false
		_anim_time_lbl.text = "%.2fs / %.2fs" % [t, dur]


func bind_controller(ctrl) -> void:
	controller = ctrl
	if not controller.state_changed.is_connected(_refresh_from_controller):
		controller.state_changed.connect(_refresh_from_controller)
	if not controller.model_loaded.is_connected(_on_model_loaded):
		controller.model_loaded.connect(_on_model_loaded)
	_refresh_from_controller()
	_refresh_recent_settings()
	if not controller.tracking.installation_finished.is_connected(_on_tracking_installed):
		controller.tracking.installation_finished.connect(_on_tracking_installed)
	_refresh_fx_presets()


const NAV_ITEMS := [
	["Model", "モデル", "読み込み・配置・揺れもの"],
	["Camera", "カメラ", "画角・距離・注視点"],
	["Light", "ライト", "方向・色・影・ポスト"],
	["Effects", "シェーダー", "画面効果・陰影・落ち影"],
	["Pose", "ポーズ", "プリセット・ボーン調整"],
	["Anim", "アニメーション", "VRMA 再生・待機動作"],
	["Expr", "表情・視線", "表情スライダー・LookAt"],
	["Tracking", "トラッキング", "Webカメラで顔・手・全身"],
	["Window", "背景・ウィンドウ", "透過・最前面・背景"],
	["Output", "出力", "撮影・録画・配信"],
	["API/Config", "API・設定", "外部制御・保存"],
	["License", "ライセンス", "利用している OSS・素材"],
]

var _nav_buttons: Dictionary = {}
var _tab_vbs: Array = []
var _header_title_lbl: Label
var _header_sub_lbl: Label
var _api_dot: Label


func _build_ui() -> void:
	var th: Theme = UiThemeScript.get_theme()

	var root_panel := PanelContainer.new()
	root_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_panel.theme = th
	add_child(root_panel)

	var root_vb := VBoxContainer.new()
	root_vb.add_theme_constant_override("separation", 0)
	root_panel.add_child(root_vb)

	# --- ヘッダー ---
	var header := PanelContainer.new()
	header.theme_type_variation = "Header"
	root_vb.add_child(header)
	var hhb := HBoxContainer.new()
	hhb.add_theme_constant_override("separation", 12)
	header.add_child(hhb)
	var logo := ColorRect.new()
	logo.color = UiThemeScript.ACCENT
	logo.custom_minimum_size = Vector2(6, 34)
	hhb.add_child(logo)
	var tvb := VBoxContainer.new()
	tvb.add_theme_constant_override("separation", 0)
	tvb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hhb.add_child(tvb)
	_header_title_lbl = Label.new()
	_header_title_lbl.theme_type_variation = "TitleLabel"
	_header_title_lbl.text = "うつしみらー"
	tvb.add_child(_header_title_lbl)
	_header_sub_lbl = Label.new()
	_header_sub_lbl.theme_type_variation = "DimLabel"
	_header_sub_lbl.text = "モデル未読み込み"
	_header_sub_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tvb.add_child(_header_sub_lbl)
	_api_dot = Label.new()
	_api_dot.theme_type_variation = "DimLabel"
	_api_dot.text = "● API"
	_api_dot.tooltip_text = "WebSocket / OSC 制御サーバーの状態"
	hhb.add_child(_api_dot)

	# --- 本体: サイドバー + 内容 ---
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vb.add_child(body)

	var sidebar := PanelContainer.new()
	sidebar.theme_type_variation = "Sidebar"
	sidebar.custom_minimum_size = Vector2(196, 0)
	body.add_child(sidebar)
	var nav_scroll := ScrollContainer.new()
	nav_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(nav_scroll)
	var nav_vb := VBoxContainer.new()
	nav_vb.add_theme_constant_override("separation", 2)
	nav_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_scroll.add_child(nav_vb)
	var nav_group := ButtonGroup.new()
	for i in NAV_ITEMS.size():
		var item: Array = NAV_ITEMS[i]
		var nb := Button.new()
		nb.theme_type_variation = "NavButton"
		nb.toggle_mode = true
		nb.button_group = nav_group
		nb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		nb.text = "%s\n%s" % [item[1], item[2]]
		nb.tooltip_text = item[2]
		nb.custom_minimum_size = Vector2(0, 48)
		nb.add_theme_font_size_override("font_size", 13)
		nb.pressed.connect(_select_tab.bind(str(item[0])))
		nav_vb.add_child(nb)
		_nav_buttons[str(item[0])] = nb

	_tabs = TabContainer.new()
	_tabs.tabs_visible = false
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_tabs)

	_build_tab_model()
	_build_tab_camera()
	_build_tab_lighting()
	_build_tab_effects()
	_build_tab_pose()
	_build_tab_animation()
	_build_tab_expressions()
	_build_tab_tracking()
	_build_tab_background()
	_build_tab_output()
	_build_tab_api()
	_build_tab_license()
	for vb in _tab_vbs:
		_cardify(vb)
	_select_tab("Model")

	# --- フッター ---
	var footer_panel := PanelContainer.new()
	footer_panel.theme_type_variation = "Footer"
	root_vb.add_child(footer_panel)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	footer_panel.add_child(footer)
	var b_save_fast := Button.new()
	b_save_fast.theme_type_variation = "AccentButton"
	b_save_fast.text = "設定を保存"
	b_save_fast.pressed.connect(func():
		if controller != null:
			var r: Dictionary = controller.save_config()
			if _status_footer_lbl != null:
				_status_footer_lbl.text = "✓ 保存しました" if r.get("ok", false) else "保存に失敗しました"
				show_snackbar("設定を保存しました" if r.get("ok", false) else "設定の保存に失敗しました", "", Callable(), 2.5)
	)
	footer.add_child(b_save_fast)

	# 設定をファイルに書き出す・読み込む (「設定を保存」は次回の起動用に、いつもの場所へ保存するだけ)
	var dlg_cfg_save := FileDialog.new()
	dlg_cfg_save.use_native_dialog = true  # Windows 標準のファイル選択画面
	dlg_cfg_save.theme = th
	dlg_cfg_save.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dlg_cfg_save.access = FileDialog.ACCESS_FILESYSTEM
	dlg_cfg_save.filters = PackedStringArray(["*.umset ; うつしみらーの設定"])
	dlg_cfg_save.current_file = "utsushimirror_settings.umset"
	dlg_cfg_save.file_selected.connect(func(p: String):
		if controller == null:
			return
		var r: Dictionary = controller.export_settings(p)
		show_snackbar("設定をファイルに書き出しました: " + str(r.get("path", p)) if r.get("ok", false) else "書き出しに失敗しました: " + str(r.get("error", "")), "", Callable(), 5.0)
	)
	add_child(dlg_cfg_save)
	var dlg_cfg_open := FileDialog.new()
	dlg_cfg_open.use_native_dialog = true  # Windows 標準のファイル選択画面
	dlg_cfg_open.theme = th
	dlg_cfg_open.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg_cfg_open.access = FileDialog.ACCESS_FILESYSTEM
	dlg_cfg_open.filters = PackedStringArray(["*.umset ; うつしみらーの設定", "*.json ; 以前の形式 (.json)"])
	dlg_cfg_open.file_selected.connect(func(p: String):
		if controller == null:
			return
		var r: Dictionary = controller.import_settings(p)
		show_snackbar("設定ファイルを読み込みました" if r.get("ok", false) else "読み込みに失敗しました: " + str(r.get("error", "")), "", Callable(), 5.0)
	)
	add_child(dlg_cfg_open)
	var b_cfg_export := Button.new()
	b_cfg_export.text = "ファイルに書き出す…"
	b_cfg_export.tooltip_text = "今の設定をすべて 1 つのファイル (.umset) に書き出します。バックアップや別の PC への移行に使えます。"
	b_cfg_export.pressed.connect(func(): _popup_at_vrm_dir(dlg_cfg_save, "umset"))
	footer.add_child(b_cfg_export)
	var b_cfg_import := Button.new()
	b_cfg_import.text = "ファイルから読み込む…"
	b_cfg_import.tooltip_text = "書き出した設定ファイルを読み込んで反映し、いつもの保存先にも保存します。"
	b_cfg_import.pressed.connect(func(): _popup_at_vrm_dir(dlg_cfg_open))
	footer.add_child(b_cfg_import)
	_recent_cfg_btn = OptionButton.new()
	_recent_cfg_btn.tooltip_text = "最近書き出した・読み込んだ設定ファイルを選んで読み込みます。"
	_recent_cfg_btn.fit_to_longest_item = false
	_recent_cfg_btn.custom_minimum_size.x = 150
	_recent_cfg_btn.get_popup().about_to_popup.connect(_refresh_recent_settings)
	_recent_cfg_btn.item_selected.connect(_on_recent_settings_selected)
	footer.add_child(_recent_cfg_btn)
	_refresh_recent_settings()

	_status_footer_lbl = Label.new()
	_status_footer_lbl.theme_type_variation = "DimLabel"
	_status_footer_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_status_footer_lbl)

	var b_close := Button.new()
	b_close.text = "閉じる"
	b_close.tooltip_text = "メイン画面の右クリックメニューから再表示できます"
	b_close.pressed.connect(_on_close_requested)
	footer.add_child(b_close)

	_build_snackbar()

	_file_dialog_out_img = FileDialog.new()
	_file_dialog_out_img.use_native_dialog = true  # Windows 標準のファイル選択画面
	_file_dialog_out_img.theme = th
	_file_dialog_out_img.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog_out_img.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog_out_img.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Image"])
	_file_dialog_out_img.file_selected.connect(func(p: String):
		if controller != null:
			controller.bg_manager.apply_output_viewport({"background_mode": "image", "image_path": p})
	)
	add_child(_file_dialog_out_img)


func _select_tab(key: String) -> void:
	for i in _tabs.get_tab_count():
		if _tabs.get_tab_control(i).name == key.validate_node_name():
			_tabs.current_tab = i
			break
	if _nav_buttons.has(key):
		_nav_buttons[key].button_pressed = true


func _new_tab(tab_title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_title.validate_node_name()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", 18)
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 18)
	scroll.add_child(pad)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 7)
	pad.add_child(vb)
	# ページ見出し
	for item in NAV_ITEMS:
		if str(item[0]) == tab_title:
			var t := Label.new()
			t.theme_type_variation = "TitleLabel"
			t.text = str(item[1])
			vb.add_child(t)
			var st := Label.new()
			st.theme_type_variation = "DimLabel"
			st.text = str(item[2])
			vb.add_child(st)
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 4)
			vb.add_child(gap)
	_tab_vbs.append(vb)
	return vb


func _add_section(parent: VBoxContainer, title_text: String) -> void:
	var hb := HBoxContainer.new()
	hb.set_meta("section", true)
	hb.add_theme_constant_override("separation", 8)
	var bar := ColorRect.new()
	bar.color = UiThemeScript.ACCENT
	bar.custom_minimum_size = Vector2(3, 16)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(bar)
	var lbl := Label.new()
	lbl.theme_type_variation = "SectionLabel"
	lbl.text = title_text
	hb.add_child(lbl)
	if UiHelpScript.HELP.has(title_text):
		hb.add_child(HelpMarkScript.new(UiHelpScript.HELP[title_text]))
	parent.add_child(hb)


## 見出し (_add_section) ごとに、それ以降の部品をカードにまとめ直す。
## 各タブの組み立て処理はそのままで見た目だけ整える。
func _cardify(vb: VBoxContainer) -> void:
	var children := vb.get_children()
	var card_vb: VBoxContainer = null
	vb.add_theme_constant_override("separation", 12)
	for c in children:
		if c is Control and c.has_meta("section"):
			var card := PanelContainer.new()
			card.theme_type_variation = "Card"
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			vb.add_child(card)
			vb.move_child(card, c.get_index())
			card_vb = VBoxContainer.new()
			card_vb.add_theme_constant_override("separation", 7)
			card.add_child(card_vb)
			c.reparent(card_vb, false)
			var sep := HSeparator.new()
			sep.add_theme_constant_override("separation", 6)
			card_vb.add_child(sep)
		elif card_vb != null:
			if c is HSeparator:
				c.queue_free()
				continue
			c.reparent(card_vb, false)


static func _no_wheel(sl: Slider) -> void:
	sl.scrollable = false
	sl.mouse_filter = Control.MOUSE_FILTER_PASS


func _add_slider(parent: VBoxContainer,label_text: String, min_v: float, max_v: float, step_v: float, def_v: float, cb: Callable) -> HSlider:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.theme_type_variation = "DimLabel"
	lbl.custom_minimum_size = Vector2(150, 0)
	lbl.clip_text = true
	lbl.tooltip_text = label_text
	lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	if UiHelpScript.HELP.has(label_text):
		var lab_box := HBoxContainer.new()
		lab_box.custom_minimum_size = Vector2(150, 0)
		lab_box.add_theme_constant_override("separation", 4)
		lbl.custom_minimum_size = Vector2(0, 0)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab_box.add_child(lbl)
		lab_box.add_child(HelpMarkScript.new(UiHelpScript.HELP[label_text]))
		hb.add_child(lab_box)
	else:
		hb.add_child(lbl)
	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step_v
	sl.value = def_v
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val_lbl := Label.new()
	val_lbl.theme_type_variation = "ValueLabel"
	val_lbl.custom_minimum_size = Vector2(54, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.text = str(snappedf(def_v, 0.01))
	sl.value_changed.connect(func(v: float):
		val_lbl.text = str(snappedf(v, 0.01))
		if not _syncing:
			cb.call(v)
	)
	# ダブルクリックで初期値に戻す
	var default_v := def_v
	lbl.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.double_click:
			sl.value = default_v
	)
	lbl.tooltip_text = "%s\n(ラベルをダブルクリックで初期値 %s に戻す)" % [label_text, str(snappedf(def_v, 0.01))]
	hb.add_child(sl)
	hb.add_child(val_lbl)
	parent.add_child(hb)
	return sl


func _add_check(parent: VBoxContainer, label_text: String, def_v: bool, cb: Callable) -> CheckBox:
	var chk := CheckBox.new()
	chk.text = label_text
	chk.button_pressed = def_v
	chk.toggled.connect(func(v: bool):
		if not _syncing:
			cb.call(v)
	)
	if UiHelpScript.HELP.has(label_text):
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		hb.add_child(chk)
		hb.add_child(HelpMarkScript.new(UiHelpScript.HELP[label_text]))
		parent.add_child(hb)
	else:
		parent.add_child(chk)
	return chk


## 項目名 (と説明があれば「?」) の固定幅ラベル
func _row_label(label_text: String) -> Control:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.theme_type_variation = "DimLabel"
	if not UiHelpScript.HELP.has(label_text):
		lbl.custom_minimum_size = Vector2(150, 0)
		return lbl
	var box := HBoxContainer.new()
	box.custom_minimum_size = Vector2(150, 0)
	box.add_theme_constant_override("separation", 4)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(lbl)
	box.add_child(HelpMarkScript.new(UiHelpScript.HELP[label_text]))
	return box


func _add_color_row(parent: VBoxContainer, label_text: String, def_col: Color, cb: Callable) -> ColorPickerButton:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var lbl := _row_label(label_text)
	var btn := ColorPickerButton.new()
	btn.color = def_col
	btn.edit_alpha = false
	btn.custom_minimum_size = Vector2(96, 28)
	btn.color_changed.connect(func(c: Color):
		if not _syncing:
			cb.call(c)
	)
	hb.add_child(lbl)
	hb.add_child(btn)
	parent.add_child(hb)
	return btn


# ---------------------------------------------------------------------------
# Tab: Tracking (Webカメラ)
# ---------------------------------------------------------------------------

var _trk_status_lbl: Label
var _trk_start_btn: Button
var _trk_cam_opt: OptionButton
var _trk_checks: Dictionary = {}
var _trk_sliders: Dictionary = {}
var _trk_opts: Dictionary = {}
var _trk_mode_btns: Dictionary = {}
var _trk_sec: Dictionary = {}
var _trk_mode_desc: Label
var _trk_custom_box: VBoxContainer
var _trk_live_lbl: Label
var _trk_warn_lbl: Label
var _trk_calib_btn: Button
var _trk_calib_lbl: Label
var _trk_last_running: bool = false
## トラッキング用のシステム (uv と Python の環境) が無いときに出すインストールの欄
var _trk_start_row: HBoxContainer
var _trk_install_box: VBoxContainer
var _trk_install_btn: Button
var _trk_install_lbl: Label
var _trk_install_dlg: ConfirmationDialog
var _trk_install_shown := ""
var _shot_dir_lbl: Label


func _build_tab_tracking() -> void:
	var vb := _new_tab("Tracking")
	# ---- 開始・状態
	_add_section(vb, "トラッキング")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_trk_start_btn = Button.new()
	_trk_start_btn.theme_type_variation = "AccentButton"
	_trk_start_btn.text = "▶ トラッキング開始"
	_trk_start_btn.custom_minimum_size = Vector2(190, 36)
	_trk_start_btn.pressed.connect(func():
		if controller == null:
			return
		if controller.tracking.is_running():
			controller.stop_tracking()
		else:
			var r: Dictionary = controller.start_tracking()
			if not r.get("ok", false):
				_status_footer_lbl.text = str(r.get("error", "開始できませんでした"))
		_refresh_tracking_ui(controller.get_full_state())
	)
	row.add_child(_trk_start_btn)
	_trk_status_lbl = Label.new()
	_trk_status_lbl.theme_type_variation = "DimLabel"
	_trk_status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trk_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_trk_status_lbl)
	vb.add_child(row)
	_trk_start_row = row
	_build_tracking_install(vb)
	_trk_live_lbl = Label.new()
	_trk_live_lbl.theme_type_variation = "ValueLabel"
	_trk_live_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_trk_live_lbl)
	_trk_warn_lbl = Label.new()
	_trk_warn_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_trk_warn_lbl.add_theme_color_override("font_color", Color("#ffb4a8"))
	_trk_warn_lbl.visible = false
	vb.add_child(_trk_warn_lbl)
	_trk_dim_note(vb, "カメラ映像はこのアプリに一切表示・保存されません。別ウィンドウには目・顔の輪郭・手・骨格のワイヤーだけが表示されます。")

	# ---- モード
	_add_section(vb, "モード")
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for m in ["face", "upper", "full", "custom"]:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = str(TrackingManagerScript.MODES[m].label)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 34)
		var mode_key: String = m
		b.pressed.connect(func(): _push_tracking({"mode": mode_key}))
		_trk_mode_btns[m] = b
		mrow.add_child(b)
	vb.add_child(mrow)
	_trk_mode_desc = Label.new()
	_trk_mode_desc.theme_type_variation = "DimLabel"
	_trk_mode_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_trk_mode_desc)
	_trk_custom_box = VBoxContainer.new()
	for item in [["face", "顔 (向き・表情・まばたき・視線)"], ["hands", "手と指 (体の推定も使います)"], ["pose", "上半身 (胴体・腕)"], ["legs", "脚と立ち位置 (全身が映るとき)"]]:
		var key: String = item[0]
		_trk_checks[key] = _add_check(_trk_custom_box, str(item[1]), true, func(v: bool): _push_tracking({key: v}))
	vb.add_child(_trk_custom_box)

	# ---- キャリブレーション
	_add_section(vb, "キャリブレーション")
	_trk_dim_note(vb, "画面を見るいつもの姿勢で、無表情のまま正面を向き、腕を下ろして実行してください。カメラの角度・座る向き・普段の目の開き具合や口元の癖を打ち消し、その姿勢をモデルの「正面・無表情」にします。結果は保存され、次回も使われます。")
	var crow2 := HBoxContainer.new()
	crow2.add_theme_constant_override("separation", 8)
	_trk_calib_btn = Button.new()
	_trk_calib_btn.theme_type_variation = "AccentButton"
	_trk_calib_btn.text = "◎ キャリブレーション"
	_trk_calib_btn.custom_minimum_size = Vector2(170, 34)
	_trk_calib_btn.pressed.connect(func():
		if controller == null:
			return
		var r: Dictionary = controller.tracking.calibrate()
		if not r.get("ok", false):
			_trk_calib_lbl.text = str(r.get("error", ""))
	)
	crow2.add_child(_trk_calib_btn)
	var b_reset_cal := Button.new()
	b_reset_cal.text = "補正を消す"
	b_reset_cal.pressed.connect(func():
		if controller != null:
			controller.tracking.reset_calibration()
			_refresh_tracking_ui(controller.get_full_state())
	)
	crow2.add_child(b_reset_cal)
	_trk_calib_lbl = Label.new()
	_trk_calib_lbl.theme_type_variation = "DimLabel"
	_trk_calib_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trk_calib_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	crow2.add_child(_trk_calib_lbl)
	vb.add_child(crow2)
	_trk_add_option(vb, "開始までの秒数", "calib_delay", [[0, "すぐ"], [3, "3 秒後"], [5, "5 秒後"], [10, "10 秒後"]])

	# ---- カメラ
	_add_section(vb, "カメラ")
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 10)
	var clbl := Label.new()
	clbl.text = "使うカメラ"
	clbl.theme_type_variation = "DimLabel"
	clbl.custom_minimum_size = Vector2(150, 0)
	crow.add_child(clbl)
	_trk_cam_opt = OptionButton.new()
	_trk_cam_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trk_cam_opt.add_item("自動選択 (仮想カメラを避ける)")
	_trk_cam_opt.set_item_metadata(0, "auto")
	_trk_cam_opt.item_selected.connect(func(i: int):
		if not _syncing:
			_push_tracking({"camera": str(_trk_cam_opt.get_item_metadata(i))})
	)
	crow.add_child(_trk_cam_opt)
	var b_ref := Button.new()
	b_ref.text = "一覧を更新"
	b_ref.pressed.connect(func():
		if controller != null:
			controller.tracking.refresh_cameras()
			_refresh_tracking_ui(controller.get_full_state())
	)
	crow.add_child(b_ref)
	vb.add_child(crow)
	_trk_add_option(vb, "解像度", "resolution", [["640x480", "640×480 (軽い)"], ["1280x720", "1280×720 (おすすめ)"], ["1920x1080", "1920×1080 (離れて全身を映すとき)"]])
	_trk_add_option(vb, "フレームレート", "fps", [[30, "30 fps"], [60, "60 fps (対応カメラのみ)"]])
	_trk_checks["mirror"] = _add_check(vb, "鏡のように動かす (ミラー)", true, func(v: bool): _push_tracking({"mirror": v}))
	_trk_checks["preview"] = _add_check(vb, "ワイヤー表示ウィンドウを出す", true, func(v: bool): _push_tracking({"preview": v}))
	_trk_dim_note(vb, "コツ: カメラは画面の上に置き、顔が映像の中央より少し上に来るように。部屋は明るく (暗いとカメラの fps が落ち、精度も下がります)。")

	# ---- 顔・表情
	_add_section(vb, "顔・表情")
	_trk_sec["face"] = vb.get_child(vb.get_child_count() - 1)
	_trk_add_slider(vb, "頭の動きの大きさ", "head_gain", 0.3, 2.0, 0.05)
	_trk_add_slider(vb, "体の追従 (顔だけ)", "body_follow", 0.0, 1.0, 0.05)
	_trk_add_slider(vb, "口の動きの大きさ", "mouth_gain", 0.3, 2.0, 0.05)
	_trk_add_check(vb, "笑顔・怒り・驚きを自動で付ける", "expressions")
	_trk_add_slider(vb, "笑顔の感度", "happy_sens", 0.0, 1.0, 0.05)
	_trk_add_slider(vb, "笑顔の強さ", "happy_gain", 0.0, 1.0, 0.05)
	_trk_add_slider(vb, "怒りの感度", "angry_sens", 0.0, 1.0, 0.05)
	_trk_add_slider(vb, "怒りの強さ", "angry_gain", 0.0, 1.0, 0.05)
	_trk_add_slider(vb, "驚きの感度", "surprised_sens", 0.0, 1.0, 0.05)
	_trk_add_slider(vb, "驚きの強さ", "surprised_gain", 0.0, 1.0, 0.05)
	_trk_dim_note(vb, "感度 = どれくらいの表情の変化で付け始めるか (上げると小さな変化でも付く)。強さ = 付いたときの最大の濃さ。笑顔が出すぎるときは感度か強さを下げてください。")

	# ---- 目
	_add_section(vb, "目")
	_trk_sec["eyes"] = vb.get_child(vb.get_child_count() - 1)
	_trk_add_check(vb, "左右のまばたきを同期 (片目だけの誤検出を防ぐ。ウィンクはできなくなります)", "blink_link")
	_trk_add_slider(vb, "まばたきの感度", "blink_sens", 0.0, 1.0, 0.05)
	_trk_add_option(vb, "視線", "gaze_mode", [["track", "視線を動かす (目の動きに合わせる)"], ["camera", "カメラ目線"], ["fixed", "目線固定 (正面を見たまま)"]])
	_trk_add_check(vb, "左右の視線を同期 (オフにすると片目ずつ動き、寄り目もできます)", "gaze_link")
	_trk_add_slider(vb, "視線の大きさ", "gaze_gain", 0.0, 2.0, 0.05)
	_trk_add_slider(vb, "可動限界 左右 (度)", "gaze_limit_h", 0.0, 45.0, 1.0)
	_trk_add_slider(vb, "可動限界 上 (度)", "gaze_limit_up", 0.0, 40.0, 1.0)
	_trk_add_slider(vb, "可動限界 下 (度)", "gaze_limit_down", 0.0, 40.0, 1.0)
	_trk_dim_note(vb, "目が白目をむく・寄りすぎるモデルは可動限界を小さく、目が動かなすぎるときは「視線の大きさ」を上げてください。")
	# ---- 手・腕
	_add_section(vb, "手・腕")
	_trk_sec["hands"] = vb.get_child(vb.get_child_count() - 1)
	_trk_add_check(vb, "指を動かす", "fingers")
	_trk_add_slider(vb, "手首のひねりを前腕へ回す割合", "forearm_twist", 0.0, 1.0, 0.05)
	_trk_add_check(vb, "腕が見えず手だけ見えているとき、手の位置から腕を推定する", "arm_from_hand")
	_trk_add_slider(vb, "肩の上げ下げの強さ", "shoulder_gain", 0.0, 2.0, 0.05)
	_trk_add_slider(vb, "肩の上げ下げの感度", "shoulder_sens", 0.0, 1.0, 0.05)
	_trk_dim_note(vb, "肩は耳と肩の距離から上げ下げを求めます (上半身・全身モード)。基準はキャリブレーションしたときの肩の高さです。感度を下げると小さな動きでは動かなくなります。")
	_trk_add_check(vb, "見失った腕・手を自然に下ろす", "arms_rest")
	_trk_add_slider(vb, "下ろし始めるまで (秒)", "lost_hold", 0.0, 3.0, 0.1)
	_trk_add_slider(vb, "下ろす時間 (秒)", "lost_return", 0.1, 2.0, 0.05)
	_trk_add_slider(vb, "画面端の手を無視", "hand_edge", 0.0, 0.15, 0.01)

	# ---- 全身
	_add_section(vb, "全身")
	_trk_sec["full"] = vb.get_child(vb.get_child_count() - 1)
	_trk_add_check(vb, "立ち位置の移動・しゃがみを反映する", "hips_move")
	_trk_dim_note(vb, "全身モードではカメラから 2〜3m 離れ、頭から足先まで映るようにしてください。立ち位置はキャリブレーションした場所が基準です。")

	# ---- 精度・安定性
	_add_section(vb, "精度・安定性")
	_trk_add_slider(vb, "なめらかさ", "smooth", 0.0, 0.95, 0.05)
	_trk_add_slider(vb, "小刻みな揺れの抑制", "stabilize", 0.0, 1.0, 0.05)
	_trk_add_slider(vb, "速い動きへの追従", "responsiveness", 0.0, 1.0, 0.05)
	_trk_dim_note(vb, "止まっているときの揺れは「なめらかさ」、細かいブルブルした振動は「小刻みな揺れの抑制」、素早く動いたときの遅れは「速い動きへの追従」で調整します。体の推定モデルを「高精度」にすると揺れがさらに減ります (少し重くなります)。")
	_trk_add_option(vb, "体の推定モデル", "pose_model", [["lite", "軽量 (速い)"], ["full", "標準"], ["heavy", "高精度 (重い)"]])
	_trk_add_slider(vb, "検出のしきい値", "confidence", 0.3, 0.9, 0.05)
	var b_def := Button.new()
	b_def.text = "トラッキング設定を初期値に戻す"
	b_def.pressed.connect(func():
		if controller != null:
			if controller.tracking.reset_settings():
				controller.stop_tracking()
				controller.start_tracking()
			_refresh_tracking_ui(controller.get_full_state())
	)
	vb.add_child(b_def)

	_add_section(vb, "外部ソフトとの連携")
	_trk_dim_note(vb, "VMC Protocol に対応した他のトラッカー (スマホアプリ等) からも、API・設定ページの OSC ポートへ送れば同じように動かせます。外部プログラムからは JSON-RPC の tracking.start / tracking.set / tracking.calibrate でも操作できます。")


func _trk_dim_note(vb: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.theme_type_variation = "DimLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = text
	vb.add_child(l)


func _trk_add_slider(vb: VBoxContainer, label_text: String, key: String, lo: float, hi: float, step: float) -> void:
	var def := float(TrackingManagerScript.DEFAULTS[key])
	_trk_sliders[key] = _add_slider(vb, label_text, lo, hi, step, def, func(v: float): _push_tracking({key: v}))


func _trk_add_check(vb: VBoxContainer, label_text: String, key: String) -> void:
	_trk_checks[key] = _add_check(vb, label_text, bool(TrackingManagerScript.DEFAULTS[key]), func(v: bool): _push_tracking({key: v}))


func _trk_add_option(vb: VBoxContainer, label_text: String, key: String, items: Array) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.theme_type_variation = "DimLabel"
	lbl.custom_minimum_size = Vector2(150, 0)
	hb.add_child(lbl)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in items.size():
		opt.add_item(str(items[i][1]))
		opt.set_item_metadata(i, items[i][0])
	opt.item_selected.connect(func(i: int):
		if not _syncing:
			_push_tracking({key: opt.get_item_metadata(i)})
	)
	hb.add_child(opt)
	vb.add_child(hb)
	_trk_opts[key] = opt


func _push_tracking(d: Dictionary) -> void:
	if controller == null:
		return
	controller.apply_tracking_settings(d)
	_refresh_tracking_ui(controller.get_full_state())


const _TRK_MODE_DESC := {
	"face": "顔の向き・表情・まばたき・視線だけを動かします。体は待機アニメーションのまま。いちばん軽いモードです。",
	"upper": "顔に加えて胴体・腕・手と指を動かします。机の前で上半身が映る配信向け。",
	"full": "全身 (脚と立ち位置の移動も) を動かします。カメラから離れて全身が映るようにしてください。",
	"custom": "動かす部位を個別に選びます。",
}


func _build_tracking_install(vb: VBoxContainer) -> void:
	_trk_install_box = VBoxContainer.new()
	_trk_install_box.add_theme_constant_override("separation", 8)
	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "トラッキングには「トラッキング用のシステム」(Python と、MediaPipe・OpenCV などのライブラリ) が要ります。まだ入っていないので、先にインストールしてください。インターネットから自動でダウンロードします。"
	_trk_install_box.add_child(note)
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 10)
	_trk_install_btn = Button.new()
	_trk_install_btn.theme_type_variation = "AccentButton"
	_trk_install_btn.text = "⬇ トラッキング用のシステムをインストール"
	_trk_install_btn.custom_minimum_size = Vector2(0, 36)
	_trk_install_btn.pressed.connect(_show_tracking_install_dialog)
	r.add_child(_trk_install_btn)
	_trk_install_box.add_child(r)
	_trk_install_lbl = Label.new()
	_trk_install_lbl.theme_type_variation = "DimLabel"
	_trk_install_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_trk_install_box.add_child(_trk_install_lbl)
	vb.add_child(_trk_install_box)

	_trk_install_dlg = ConfirmationDialog.new()
	_trk_install_dlg.theme = UiThemeScript.get_theme()
	_trk_install_dlg.title = "トラッキング用のシステムのインストール"
	_trk_install_dlg.ok_button_text = "インストールする"
	_trk_install_dlg.cancel_button_text = "やめる"
	_trk_install_dlg.dialog_autowrap = true
	_trk_install_dlg.min_size = Vector2i(620, 0)
	_trk_install_dlg.confirmed.connect(func():
		if controller == null:
			return
		var res: Dictionary = controller.tracking.start_install()
		if not res.get("ok", false):
			show_snackbar("インストールを始められませんでした: " + str(res.get("error", "")), "", Callable(), 8.0)
		_refresh_tracking_install()
	)
	add_child(_trk_install_dlg)


## インストール前の案内: 入るもの・場所・必要な空き容量・要求スペック
static func _mb_text(mb: int) -> String:
	if mb < 0:
		return "不明"
	return ("%.1f GB" % (mb / 1024.0)) if mb >= 1024 else ("%d MB" % mb)


func tracking_install_message(info: Dictionary) -> Dictionary:
	var lines: PackedStringArray = []
	lines.append("トラッキングに必要なものを、インターネットから自動でダウンロードして入れます。回線にもよりますが、数分かかります。")
	lines.append("")
	lines.append("■ 入るもの")
	if not bool(info.get("uv_found", false)):
		lines.append("・uv (Python の管理ツール) — まだ入っていないので、公式のインストーラー (astral.sh) で入れます。あなたのユーザーの PATH に uv が追加されます。")
	else:
		lines.append("・uv はもう入っているので、それを使います (%s)" % str(info.get("uv_path", "")))
	lines.append("・Python 3.11 と、MediaPipe・OpenCV などのライブラリ (uv が用意します)")
	lines.append("　入れる場所: %s\\.venv" % str(info.get("tracker_dir", "")))
	lines.append("")
	lines.append("■ 必要な空き容量")
	var app_need: int = int(info.get("app_need_mb", 400))
	var user_need: int = int(info.get("user_need_mb", 500))
	var app_free: int = int(info.get("app_free_mb", -1))
	var user_free: int = int(info.get("user_free_mb", -1))
	var enough := true
	if bool(info.get("same_drive", false)):
		var need := app_need + user_need
		lines.append("・%s ドライブに約 %s (アプリのフォルダに約 %s、ユーザーのフォルダに Python とダウンロードのキャッシュで約 %s) — 今の空き: %s" % [
			info.get("app_drive", ""), _mb_text(need), _mb_text(app_need), _mb_text(user_need), _mb_text(app_free)])
		enough = app_free < 0 or app_free >= need
	else:
		lines.append("・%s ドライブ (アプリのフォルダ): 約 %s — 今の空き: %s" % [info.get("app_drive", ""), _mb_text(app_need), _mb_text(app_free)])
		lines.append("・%s ドライブ (ユーザーのフォルダ。Python とダウンロードのキャッシュ): 約 %s — 今の空き: %s" % [info.get("user_drive", ""), _mb_text(user_need), _mb_text(user_free)])
		enough = (app_free < 0 or app_free >= app_need) and (user_free < 0 or user_free >= user_need)
	if not enough:
		lines.append("※ 空き容量が足りません。空きを増やしてから、もう一度押してください。")
	lines.append("")
	lines.append("■ 要求スペック (トラッキングを使うとき)")
	lines.append("・CPU: 4 コア以上の x64 CPU (おすすめ 6 コア以上)")
	lines.append("・メモリ: 4 GB 以上 (おすすめ 8 GB 以上)")
	lines.append("・Web カメラ: 720p・30fps 以上がおすすめ")
	lines.append("・インターネット接続 (インストールのときだけ)")
	return {"text": "\n".join(lines), "enough": enough}


func _show_tracking_install_dialog() -> void:
	if controller == null:
		return
	var info: Dictionary = controller.tracking.install_info()
	if not bool(info.get("script_found", true)):
		show_snackbar("インストール用のファイル (tracker\\install_tracker.ps1) が見つかりません。アプリを入れ直してください。", "", Callable(), 8.0)
		return
	var m := tracking_install_message(info)
	_trk_install_dlg.dialog_text = str(m.text)
	_trk_install_dlg.get_ok_button().disabled = not bool(m.enough)
	_trk_install_dlg.popup_centered()


## インストールの欄の表示を、今の状態に合わせる (0.25 秒ごとにも呼ぶ)
func _refresh_tracking_install() -> void:
	if _trk_install_box == null or controller == null:
		return
	var tm = controller.tracking
	var installed: bool = tm.is_installed()
	var installing: bool = tm.is_installing()
	var step: String = tm.install_step
	var key := "%s|%s|%s|%s" % [installed, installing, step, tm.install_last_line]
	if key == _trk_install_shown:
		return
	_trk_install_shown = key
	_trk_install_box.visible = not installed or installing
	_trk_start_row.visible = installed and not installing
	_trk_install_btn.disabled = installing
	_trk_install_btn.text = "インストール中…" if installing else ("⬇ もう一度インストールする" if step == "error" else "⬇ トラッキング用のシステムをインストール")
	var msg := ""
	match step:
		"starting":
			msg = "準備しています…"
		"uv":
			msg = "uv を入れています…"
		"sync":
			msg = "Python とライブラリをダウンロードしています… (数分かかります)"
		"error":
			msg = "インストールできませんでした: %s\n記録: %s" % [tm.install_error, tm.install_log_path()]
	if installing and str(tm.install_last_line) != "":
		msg += "\n" + str(tm.install_last_line).left(160)
	_trk_install_lbl.text = msg
	_trk_install_lbl.visible = msg != ""


func _refresh_tracking_ui(st: Dictionary) -> void:
	if _trk_start_btn == null:
		return
	_refresh_tracking_install()
	var trk: Dictionary = st.get("tracking", {})
	var running: bool = bool(trk.get("running", false))
	_trk_start_btn.text = "■ トラッキング停止" if running else "▶ トラッキング開始"
	_trk_start_btn.theme_type_variation = "" if running else "AccentButton"
	var err := str(trk.get("error", ""))
	_trk_status_lbl.text = err if err != "" else ("動作中 — VMC で受信しています" if running else "停止中")
	var cfg: Dictionary = trk.get("settings", {})
	var was := _syncing
	_syncing = true
	for k in _trk_checks.keys():
		if cfg.has(k):
			_trk_checks[k].button_pressed = bool(cfg[k])
	for k in _trk_sliders.keys():
		if cfg.has(k):
			_trk_sliders[k].value = float(cfg[k])
	for k in _trk_opts.keys():
		if not cfg.has(k):
			continue
		var opt: OptionButton = _trk_opts[k]
		for i in opt.item_count:
			if str(opt.get_item_metadata(i)) == str(cfg[k]):
				opt.select(i)
	var mode := str(cfg.get("mode", "upper"))
	for m in _trk_mode_btns.keys():
		_trk_mode_btns[m].set_pressed_no_signal(m == mode)
	_trk_mode_desc.text = str(_TRK_MODE_DESC.get(mode, ""))
	_trk_custom_box.visible = mode == "custom"
	var parts: Array = controller.tracking.parts() if controller != null else [true, true, true, false]
	_trk_set_section_visible("face", bool(parts[0]))
	_trk_set_section_visible("eyes", bool(parts[0]))
	_trk_set_section_visible("hands", bool(parts[1]) or bool(parts[2]))
	_trk_set_section_visible("full", bool(parts[3]))
	var cams: Array = trk.get("cameras", [])
	while _trk_cam_opt.item_count > 1:
		_trk_cam_opt.remove_item(_trk_cam_opt.item_count - 1)
	for c in cams:
		var idx: int = _trk_cam_opt.item_count
		_trk_cam_opt.add_item("%s: %s" % [str(c.get("index", "?")), str(c.get("name", ""))])
		_trk_cam_opt.set_item_metadata(idx, str(c.get("index", 0)))
	var want := str(cfg.get("camera", "auto"))
	var sel := 0
	for i in _trk_cam_opt.item_count:
		if str(_trk_cam_opt.get_item_metadata(i)) == want:
			sel = i
	if want != "auto" and sel == 0:
		_trk_cam_opt.add_item("カメラ %s" % want)
		sel = _trk_cam_opt.item_count - 1
		_trk_cam_opt.set_item_metadata(sel, want)
	_trk_cam_opt.select(sel)
	_syncing = was
	_update_tracking_live()


func _trk_set_section_visible(key: String, on: bool) -> void:
	var header: Control = _trk_sec.get(key)
	if header == null:
		return
	var card: Node = header.get_parent().get_parent() if header.get_parent() != null else null
	if card is PanelContainer:
		card.visible = on
	else:
		header.visible = on


## 動作中の状態 (fps・検出・明るさ・キャリブレーション) を表示する。0.25 秒ごとに呼ばれる。
func _update_tracking_live() -> void:
	if _trk_live_lbl == null or controller == null:
		return
	var tm = controller.tracking
	var s: Dictionary = tm.status
	var running: bool = tm.is_running()
	_trk_calib_btn.disabled = not running
	var cal_time: String = tm.calibration_time()
	if not running:
		_trk_live_lbl.text = ""
		_trk_warn_lbl.visible = false
		_trk_calib_lbl.text = ("実施済み (%s)" % cal_time) if cal_time != "" else "未実施 — トラッキング開始後に実行できます"
		return
	if s.is_empty():
		_trk_live_lbl.text = "起動中… (初回はモデルのダウンロードとカメラの準備に数秒かかります)"
		_trk_warn_lbl.visible = false
		_trk_calib_lbl.text = ("実施済み (%s)" % cal_time) if cal_time != "" else "未実施"
		return
	var p: Array = tm.parts()
	var items: PackedStringArray = []
	items.append("%.0f fps" % float(s.get("fps", 0)))
	if bool(p[0]):
		items.append("顔 " + ("●" if bool(s.get("face", false)) else "○"))
	if bool(p[1]):
		items.append("手 %d/2" % int(s.get("hands", 0)))
	if bool(p[2]):
		items.append("体 " + ("●" if bool(s.get("pose", false)) else "○"))
	var res: Array = s.get("resolution", [])
	if res.size() == 2:
		items.append("カメラ %s: %d×%d %.0f fps" % [str(int(s.get("camera", 0))), int(res[0]), int(res[1]), float(s.get("camera_fps", 0))])
	_trk_live_lbl.text = "   ".join(items)
	var warns: PackedStringArray = []
	if float(s.get("brightness", 128)) < 55.0:
		warns.append("⚠ 映像が暗いようです。部屋を明るくすると精度と fps が上がります。")
	var cam_fps := float(s.get("camera_fps", 30))
	if cam_fps > 0.0 and cam_fps < 20.0:
		warns.append("⚠ カメラが %.0f fps しか出ていません (暗いと自動露出で下がることがあります)。" % cam_fps)
	if bool(p[0]) and not bool(s.get("face", false)):
		warns.append("顔が見つかりません。カメラの正面に入ってください。")
	_trk_warn_lbl.text = "\n".join(warns)
	_trk_warn_lbl.visible = not warns.is_empty()
	var cd := float(s.get("calib_countdown", -1))
	var msg := str(s.get("message", ""))
	if cd >= 0.0:
		_trk_calib_lbl.text = "あと %d 秒… 正面を向いて無表情で、腕を下ろしてください" % int(ceil(cd))
	elif bool(s.get("calib_capturing", false)):
		_trk_calib_lbl.text = "記録中… そのまま動かないでください"
	elif msg.begins_with("calibration failed"):
		_trk_calib_lbl.text = "失敗: 顔 (または体) が映っていません。カメラの前で正面を向いてからもう一度"
	else:
		_trk_calib_lbl.text = ("実施済み (%s)" % cal_time) if cal_time != "" else "未実施 — 正面を向いてボタンを押してください"


# ---------------------------------------------------------------------------
# シェーダー (画面効果・モデルの陰影・落ち影)
# ---------------------------------------------------------------------------

func _build_tab_effects() -> void:
	var vb := _new_tab("Effects")
	_add_section(vb, "画面効果のスタイル")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var group := ButtonGroup.new()
	for key in PostEffectsScript.PRESETS.keys():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = str(PostEffectsScript.PRESETS[key][0])
		b.tooltip_text = str(PostEffectsScript.PRESETS[key][1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 34)
		var k: String = key
		b.pressed.connect(func(): _push_fx({"style": k}))
		grid.add_child(b)
		_fx_style_btns[k] = b
	vb.add_child(grid)
	_fx_desc_lbl = Label.new()
	_fx_desc_lbl.theme_type_variation = "DimLabel"
	_fx_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_fx_desc_lbl)
	_fx_slider(vb, "効果の強さ", "strength", 0.0, 1.0, 0.05, 1.0)

	_add_section(vb, "色")
	_fx_slider(vb, "明るさ (段)", "exposure", -2.0, 2.0, 0.05)
	_fx_slider(vb, "コントラスト", "contrast", 0.5, 1.6, 0.01)
	_fx_slider(vb, "彩度", "saturation", 0.0, 2.0, 0.01)
	_fx_slider(vb, "自然な彩度", "vibrance", -1.0, 1.0, 0.05)
	_fx_slider(vb, "色温度", "temperature", -1.0, 1.0, 0.05)
	_fx_slider(vb, "色かぶり", "tint", -1.0, 1.0, 0.05)
	_fx_slider(vb, "黒の浮き", "black_lift", 0.0, 0.2, 0.005)
	_fx_slider(vb, "白の柔らかさ", "highlight_roll", 0.0, 0.5, 0.01)
	_fx_color(vb, "暗部の色", "shadow_color")
	_fx_slider(vb, "暗部の色の量", "shadow_amount", 0.0, 1.0, 0.01)
	_fx_color(vb, "明部の色", "highlight_color")
	_fx_slider(vb, "明部の色の量", "highlight_amount", 0.0, 1.0, 0.01)
	_fx_slider(vb, "セピア", "sepia", 0.0, 1.0, 0.01)
	_fx_slider(vb, "モノクロ", "mono", 0.0, 1.0, 0.01)

	_add_section(vb, "絵づくり (アニメ・絵画)")
	_fx_slider(vb, "明るさの段数 (セル画風)", "posterize", 0.0, 12.0, 1.0)
	_fx_slider(vb, "輪郭線", "edge", 0.0, 1.0, 0.01)
	_fx_slider(vb, "輪郭線の感度", "edge_threshold", 0.02, 0.4, 0.01)
	_fx_color(vb, "輪郭線の色", "edge_color")
	_fx_slider(vb, "絵画風の筆の大きさ", "kuwahara", 0.0, 6.0, 0.5)

	_add_section(vb, "光のにじみ・質感")
	_fx_slider(vb, "拡散 (Pro-Mist)", "diffusion", 0.0, 1.0, 0.01)
	_fx_slider(vb, "にじむ明るさ", "diffusion_threshold", 0.0, 1.0, 0.01)
	_fx_slider(vb, "ハレーション", "halation", 0.0, 0.5, 0.01)
	_fx_slider(vb, "ふんわり", "glow", 0.0, 0.5, 0.01)
	_fx_slider(vb, "ぼかし", "softness", 0.0, 1.0, 0.01)
	_fx_slider(vb, "シャープ", "sharpen", 0.0, 1.0, 0.01)

	_add_section(vb, "レンズ・フィルム・ビデオ")
	_fx_slider(vb, "周辺減光", "vignette", 0.0, 1.0, 0.01)
	_fx_slider(vb, "色収差", "chroma", 0.0, 3.0, 0.05)
	_fx_slider(vb, "粒子", "grain", 0.0, 0.6, 0.01)
	_fx_slider(vb, "粒子のコマ数", "grain_fps", 6.0, 60.0, 1.0)
	_fx_slider(vb, "傷", "scratches", 0.0, 1.0, 0.01)
	_fx_slider(vb, "ほこり", "dust", 0.0, 1.0, 0.01)
	_fx_slider(vb, "ちらつき", "flicker", 0.0, 1.0, 0.01)
	_fx_slider(vb, "揺れ", "jitter", 0.0, 1.0, 0.01)
	_fx_slider(vb, "走査線", "scanlines", 0.0, 1.0, 0.01)
	_fx_slider(vb, "ビデオの乱れ", "vhs", 0.0, 1.0, 0.01)
	var lb_row := _labeled_row(vb, "黒帯 (縦横比)")
	_fx_letterbox_opt = OptionButton.new()
	_fx_letterbox_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in [[0.0, "なし"], [1.78, "16:9"], [1.85, "ビスタ 1.85:1"], [2.39, "シネスコ 2.39:1"], [1.33, "4:3 (昔のテレビ)"]]:
		_fx_letterbox_opt.add_item(str(item[1]))
		_fx_letterbox_opt.set_item_metadata(_fx_letterbox_opt.item_count - 1, item[0])
	_fx_letterbox_opt.item_selected.connect(func(i: int):
		if not _syncing:
			_push_fx({"letterbox": float(_fx_letterbox_opt.get_item_metadata(i))})
	)
	lb_row.add_child(_fx_letterbox_opt)
	var b_fx_reset := Button.new()
	b_fx_reset.text = "画面効果をなしに戻す"
	b_fx_reset.pressed.connect(func(): _push_fx({"style": "none", "strength": 1.0}))
	vb.add_child(b_fx_reset)

	_add_section(vb, "モデルの陰影 (トゥーン)")
	_fx_slider(vb, "影の範囲", "shade_shift", -1.0, 1.0, 0.02)
	_fx_slider(vb, "影の境界のくっきりさ", "shade_toony", -1.0, 1.0, 0.02)
	_fx_slider(vb, "影の濃さ", "shade_strength", 0.0, 2.0, 0.02)
	_fx_color(vb, "影の色味", "shade_tint")
	var b_sh_reset := Button.new()
	b_sh_reset.text = "陰影をモデルの設定どおりに戻す"
	b_sh_reset.pressed.connect(func(): _push_fx(PostEffectsScript.SHADE_DEFAULTS.duplicate()))
	vb.add_child(b_sh_reset)

	_add_section(vb, "落ち影 (キーライトの影)")
	_fx_checks["shadows_enabled"] = _add_check(vb, "影を出す", true, func(v: bool): _push_light({"shadows_enabled": v}))
	_fx_light_slider(vb, "落ち影の濃さ", "shadow_opacity", 0.0, 2.0, 0.02, 1.0)
	_fx_light_slider(vb, "影のぼけ (光源の大きさ)", "shadow_softness", 0.0, 5.0, 0.1, 0.0)
	_fx_light_slider(vb, "影の縁のなめらかさ", "shadow_blur", 0.0, 4.0, 0.05, 1.0)
	var q_row := _labeled_row(vb, "影の品質")
	_fx_quality_opt = OptionButton.new()
	_fx_quality_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in [["low", "低 (軽い)"], ["medium", "中"], ["high", "高 (おすすめ)"], ["ultra", "最高 (重い)"]]:
		_fx_quality_opt.add_item(str(item[1]))
		_fx_quality_opt.set_item_metadata(_fx_quality_opt.item_count - 1, item[0])
	_fx_quality_opt.item_selected.connect(func(i: int):
		if not _syncing:
			_push_light({"shadow_quality": str(_fx_quality_opt.get_item_metadata(i))})
	)
	q_row.add_child(_fx_quality_opt)
	_fx_light_slider(vb, "影を描く距離 (m)", "shadow_distance", 2.0, 60.0, 1.0, 12.0)
	_fx_light_slider(vb, "影のずれ", "shadow_bias", 0.0, 1.0, 0.01, 0.1)
	_fx_light_slider(vb, "法線方向のずれ", "shadow_normal_bias", 0.0, 5.0, 0.05, 2.0)
	var sharp_row := HBoxContainer.new()
	sharp_row.add_theme_constant_override("separation", 8)
	var b_sharp := Button.new()
	b_sharp.text = "くっきり影 (鼻などの小さな影も出す)"
	b_sharp.tooltip_text = "影を面に近づけて細かく描き、ライトを少し横から当て、補助光を弱めます。
体に細かい縞模様が出たら「法線方向のずれ」を少し上げてください。"
	b_sharp.pressed.connect(func():
		_push_light(LightingRigScript.SHARP_SHADOW.duplicate())
		show_snackbar("くっきり影にしました。縞模様が出るときは「法線方向のずれ」を少し上げてください。", "", Callable(), 5.0)
	)
	var b_sharp_reset := Button.new()
	b_sharp_reset.text = "影を初期値に戻す"
	b_sharp_reset.pressed.connect(func(): _push_light(LightingRigScript.SHADOW_DEFAULTS.duplicate()))
	sharp_row.add_child(b_sharp)
	sharp_row.add_child(b_sharp_reset)
	vb.add_child(sharp_row)

	# ---- 保存したプリセット (プリセットのフォルダの .umshader)
	_add_section(vb, "保存したプリセット")
	_trk_dim_note(vb, "プリセットのフォルダに入れた .umshader (シェーダー設定の書き出しファイル) が、ここにボタンで並びます。押すとその設定になります。")
	_fx_preset_flow = HFlowContainer.new()
	_fx_preset_flow.add_theme_constant_override("h_separation", 6)
	_fx_preset_flow.add_theme_constant_override("v_separation", 6)
	vb.add_child(_fx_preset_flow)
	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 8)
	_fx_preset_name = LineEdit.new()
	_fx_preset_name.placeholder_text = "プリセットの名前"
	_fx_preset_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(_fx_preset_name)
	var b_preset_save := Button.new()
	b_preset_save.text = "今の設定をプリセットに保存"
	b_preset_save.pressed.connect(func():
		if controller == null:
			return
		var r: Dictionary = controller.save_shader_preset(_fx_preset_name.text)
		if r.get("ok", false):
			show_snackbar("プリセット「%s」を保存しました" % _fx_preset_name.text.strip_edges(), "", Callable(), 3.0)
			_fx_preset_name.text = ""
			_refresh_fx_presets()
		else:
			show_snackbar("保存できませんでした: " + str(r.get("error", "")), "", Callable(), 4.0)
	)
	save_row.add_child(b_preset_save)
	vb.add_child(save_row)
	var pdir_row := HBoxContainer.new()
	pdir_row.add_theme_constant_override("separation", 8)
	var b_fx_dir := Button.new()
	b_fx_dir.text = "プリセットのフォルダを開く"
	b_fx_dir.pressed.connect(func():
		if controller != null:
			controller.open_presets_folder("shaders")
	)
	pdir_row.add_child(b_fx_dir)
	var b_fx_reload := Button.new()
	b_fx_reload.text = "フォルダを読み直す"
	b_fx_reload.pressed.connect(func(): _refresh_fx_presets())
	pdir_row.add_child(b_fx_reload)
	vb.add_child(pdir_row)

	# ---- シェーダーの設定だけをファイルに書き出す・読み込む
	_add_section(vb, "シェーダー設定の書き出し・読み込み")
	_trk_dim_note(vb, "このページの設定 (画面効果・モデルの陰影・落ち影) だけを 1 つのファイルに保存し、あとで読み込めます。ほかの設定は変わりません。")
	var io_row := HBoxContainer.new()
	io_row.add_theme_constant_override("separation", 8)
	var b_fx_export := Button.new()
	b_fx_export.text = "書き出す…"
	var b_fx_import := Button.new()
	b_fx_import.text = "読み込む…"
	io_row.add_child(b_fx_export)
	io_row.add_child(b_fx_import)
	vb.add_child(io_row)
	var dlg_save := FileDialog.new()
	dlg_save.use_native_dialog = true  # Windows 標準のファイル選択画面
	dlg_save.theme = UiThemeScript.get_theme()
	dlg_save.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dlg_save.access = FileDialog.ACCESS_FILESYSTEM
	dlg_save.filters = PackedStringArray(["*.umshader ; うつしみらーのシェーダー設定"])
	dlg_save.current_file = "shader_settings.umshader"
	dlg_save.file_selected.connect(func(p: String):
		if controller == null:
			return
		var r: Dictionary = controller.export_effects(p)
		show_snackbar("シェーダー設定を書き出しました: " + p if r.get("ok", false) else "書き出しに失敗しました: " + str(r.get("error", "")), "", Callable(), 4.0)
	)
	add_child(dlg_save)
	var dlg_open := FileDialog.new()
	dlg_open.use_native_dialog = true  # Windows 標準のファイル選択画面
	dlg_open.theme = UiThemeScript.get_theme()
	dlg_open.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg_open.access = FileDialog.ACCESS_FILESYSTEM
	dlg_open.filters = PackedStringArray(["*.umshader ; うつしみらーのシェーダー設定", "*.json ; 以前の形式 (.json)"])
	dlg_open.file_selected.connect(func(p: String):
		if controller == null:
			return
		var r: Dictionary = controller.import_effects(p)
		show_snackbar("シェーダー設定を読み込みました" if r.get("ok", false) else "読み込みに失敗しました: " + str(r.get("error", "")), "", Callable(), 4.0)
	)
	add_child(dlg_open)
	b_fx_export.pressed.connect(func(): _popup_at_vrm_dir(dlg_save, "umshader"))
	b_fx_import.pressed.connect(func(): _popup_at_vrm_dir(dlg_open))


## 書き出し・読み込みの画面を、読み込んでいる VRM と同じフォルダで開く。
## save_ext を渡すと (書き出し)、ファイル名の初期値を「VRM の名前.拡張子」にする。
## 「最近の設定」の一覧を作り直す。先頭は見出し、最後に「履歴を消す」。
func _refresh_recent_settings() -> void:
	if _recent_cfg_btn == null:
		return
	_recent_cfg_paths = controller.get_recent_settings_paths() if controller != null else ([] as Array[String])
	_recent_cfg_btn.clear()
	_recent_cfg_btn.add_item("最近の設定…")
	_recent_cfg_btn.set_item_disabled(0, true)
	if _recent_cfg_paths.is_empty():
		_recent_cfg_btn.add_item("(まだありません)")
		_recent_cfg_btn.set_item_disabled(1, true)
	else:
		for p in _recent_cfg_paths:
			_recent_cfg_btn.add_item("%s   — %s" % [p.get_file().get_basename(), p.get_base_dir()])
			_recent_cfg_btn.set_item_tooltip(_recent_cfg_btn.item_count - 1, p)
		_recent_cfg_btn.add_separator()
		_recent_cfg_btn.add_item("履歴を消す")
	_recent_cfg_btn.select(0)


func _on_recent_settings_selected(idx: int) -> void:
	if controller == null:
		return
	var i := idx - 1
	if i >= 0 and i < _recent_cfg_paths.size():
		var p: String = _recent_cfg_paths[i]
		var r: Dictionary = controller.import_settings(p)
		show_snackbar(("設定を読み込みました: " + p.get_file()) if r.get("ok", false) else "読み込みに失敗しました: " + str(r.get("error", "")), "", Callable(), 5.0)
	elif _recent_cfg_btn.get_item_text(idx) == "履歴を消す":
		controller.clear_recent_settings_paths()
		show_snackbar("最近の設定の履歴を消しました", "", Callable(), 2.5)
	_refresh_recent_settings()


func _on_tracking_installed(ok: bool) -> void:
	_trk_install_shown = ""
	if controller != null:
		_refresh_tracking_ui(controller.get_full_state())
	if ok:
		show_snackbar("トラッキング用のシステムを入れました。「▶ トラッキング開始」で始められます。", "", Callable(), 8.0)
	else:
		show_snackbar("トラッキング用のシステムを入れられませんでした。トラッキングのページに理由を出しています。", "", Callable(), 8.0)


func _popup_at_vrm_dir(dlg: FileDialog, save_ext: String = "") -> void:
	var vrm_path := ""
	if controller != null and controller.current_vrm != null:
		vrm_path = str(controller.current_vrm.model_path)
	if vrm_path != "" and DirAccess.dir_exists_absolute(vrm_path.get_base_dir()):
		dlg.current_dir = vrm_path.get_base_dir()
		if save_ext != "":
			dlg.current_file = vrm_path.get_file().get_basename() + "." + save_ext
	dlg.popup_centered_ratio(0.6)


## プリセットのフォルダのシェーダー設定を、ボタンとして並べ直す
func _refresh_fx_presets() -> void:
	if _fx_preset_flow == null or controller == null:
		return
	for c in _fx_preset_flow.get_children():
		c.queue_free()
	var presets: Array = controller.list_shader_presets()
	if presets.is_empty():
		var l := Label.new()
		l.text = "(まだありません)"
		l.theme_type_variation = "DimLabel"
		_fx_preset_flow.add_child(l)
		return
	for pr in presets:
		var b := Button.new()
		b.text = str(pr.name)
		b.tooltip_text = str(pr.path)
		var nm: String = str(pr.name)
		b.pressed.connect(func():
			var r: Dictionary = controller.apply_shader_preset(nm)
			if not r.get("ok", false):
				show_snackbar("読み込めませんでした: " + str(r.get("error", "")), "", Callable(), 4.0)
		)
		_fx_preset_flow.add_child(b)


func _labeled_row(vb: VBoxContainer, label_text: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.add_child(_row_label(label_text))
	vb.add_child(hb)
	return hb


func _fx_slider(vb: VBoxContainer, label_text: String, key: String, lo: float, hi: float, step: float, def := NAN) -> void:
	var d: float = def
	if is_nan(d):
		d = float(PostEffectsScript.NEUTRAL.get(key, PostEffectsScript.SHADE_DEFAULTS.get(key, 0.0)))
	_fx_sliders[key] = _add_slider(vb, label_text, lo, hi, step, d, func(v: float): _push_fx({key: v}))


func _fx_light_slider(vb: VBoxContainer, label_text: String, key: String, lo: float, hi: float, step: float, def: float) -> void:
	_fx_light_sliders[key] = _add_slider(vb, label_text, lo, hi, step, def, func(v: float): _push_light({key: v}))


func _fx_color(vb: VBoxContainer, label_text: String, key: String) -> void:
	var def := Color(str(PostEffectsScript.NEUTRAL.get(key, PostEffectsScript.SHADE_DEFAULTS.get(key, "#ffffff"))))
	_fx_colors[key] = _add_color_row(vb, label_text, def, func(c: Color): _push_fx({key: "#" + c.to_html(false)}))


func _push_fx(d: Dictionary) -> void:
	if controller == null:
		return
	controller.apply_effects(d)


func _refresh_effects_ui(st: Dictionary) -> void:
	if _fx_desc_lbl == null:
		return
	var fx: Dictionary = st.get("effects", {})
	var lt: Dictionary = st.get("lighting", {})
	var style := str(fx.get("style", "none"))
	for k in _fx_style_btns.keys():
		_fx_style_btns[k].set_pressed_no_signal(k == style)
	if PostEffectsScript.PRESETS.has(style):
		_fx_desc_lbl.text = str(PostEffectsScript.PRESETS[style][1])
	else:
		_fx_desc_lbl.text = "カスタム — スタイルを元に細かい値を変えた状態です。"
	for k in _fx_sliders.keys():
		if fx.has(k):
			_fx_sliders[k].value = float(fx[k])
	for k in _fx_colors.keys():
		if fx.has(k):
			_fx_colors[k].color = Color(str(fx[k]))
	for k in _fx_light_sliders.keys():
		if lt.has(k):
			_fx_light_sliders[k].value = float(lt[k])
	if lt.has("shadows_enabled"):
		_fx_checks["shadows_enabled"].button_pressed = bool(lt.shadows_enabled)
	var lb := float(fx.get("letterbox", 0.0))
	for i in _fx_letterbox_opt.item_count:
		if absf(float(_fx_letterbox_opt.get_item_metadata(i)) - lb) < 0.01:
			_fx_letterbox_opt.select(i)
	var q := str(lt.get("shadow_quality", "high"))
	for i in _fx_quality_opt.item_count:
		if str(_fx_quality_opt.get_item_metadata(i)) == q:
			_fx_quality_opt.select(i)


# ---------------------------------------------------------------------------
# Tab 1: Model
# ---------------------------------------------------------------------------

func _build_tab_model() -> void:
	var vb := _new_tab("Model")
	_add_section(vb, "VRM 読み込み / サンプル")
	_model_status_lbl = Label.new()
	_model_status_lbl.text = "モデル未読み込み（ウィンドウへの D&D でも読込できます）"
	_model_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_model_status_lbl)

	var row := HFlowContainer.new()
	var btn_load := Button.new()
	btn_load.text = "VRMを開く..."
	btn_load.pressed.connect(func():
		if controller != null:
			controller.open_vrm_file_dialog()
	)
	row.add_child(btn_load)

	var btn_seed := Button.new()
	btn_seed.text = "Sample: Seed-san"
	btn_seed.pressed.connect(func():
		if controller != null:
			controller.load_vrm(ConfigManagerScript.get_app_root_dir().path_join("assets/samples/Seed-san.vrm"))
	)
	row.add_child(btn_seed)

	var btn_unload := Button.new()
	btn_unload.text = "アンロード"
	btn_unload.pressed.connect(func():
		if controller != null:
			controller.unload_vrm()
	)
	row.add_child(btn_unload)
	vb.add_child(row)

	var rec_row := HBoxContainer.new()
	var rec_lbl := Label.new()
	rec_lbl.text = "最近開いたモデル:"
	rec_lbl.custom_minimum_size = Vector2(142, 0)
	_recent_opt = OptionButton.new()
	_recent_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var btn_open_rec := Button.new()
	btn_open_rec.text = "開く"
	btn_open_rec.pressed.connect(func():
		if controller != null and _recent_opt.selected >= 0:
			var meta_p: String = str(_recent_opt.get_item_metadata(_recent_opt.selected))
			if meta_p != "":
				controller.load_vrm(meta_p)
	)
	rec_row.add_child(rec_lbl)
	rec_row.add_child(_recent_opt)
	rec_row.add_child(btn_open_rec)
	vb.add_child(rec_row)

	_add_section(vb, "モデル配置 (Transform)")
	_m_pos_x = _add_slider(vb, "位置 X", -3.0, 3.0, 0.02, 0.0, func(_v: float): _push_model_transform())
	_m_pos_y = _add_slider(vb, "位置 Y", -2.0, 3.0, 0.02, 0.0, func(_v: float): _push_model_transform())
	_m_pos_z = _add_slider(vb, "位置 Z", -3.0, 3.0, 0.02, 0.0, func(_v: float): _push_model_transform())
	_m_rot_y = _add_slider(vb, "回転 Y (deg)", -180.0, 180.0, 1.0, 0.0, func(_v: float): _push_model_transform())
	_m_scale = _add_slider(vb, "スケール", 0.2, 3.0, 0.02, 1.0, func(_v: float): _push_model_transform())
	var btn_rst_xf := Button.new()
	btn_rst_xf.text = "モデル配置をリセット"
	btn_rst_xf.pressed.connect(func():
		if controller != null:
			controller.reset_model_transform()
	)
	vb.add_child(btn_rst_xf)

	_add_section(vb, "FirstPerson / SpringBone (揺れ物)")
	_first_person_chk = _add_check(vb, "一人称表示モード (FirstPerson)", false, func(v: bool):
		if controller != null:
			controller.set_first_person_mode(v)
	)
	_sb_enabled_chk = _add_check(vb, "SpringBone 物理有効", true, func(v: bool):
		if controller != null:
			controller.set_spring_bone_params({"enabled": v})
	)
	_sb_grav_slider = _add_slider(vb, "重力倍率", 0.0, 3.0, 0.05, 1.0, func(v: float):
		if controller != null:
			controller.set_spring_bone_params({"gravity_scale": v})
	)
	_sb_stiff_slider = _add_slider(vb, "硬さ倍率", 0.0, 3.0, 0.05, 1.0, func(v: float):
		if controller != null:
			controller.set_spring_bone_params({"stiffness_scale": v})
	)
	_spring_wind_x = _add_slider(vb, "風 Wind X", -10.0, 10.0, 0.1, 0.0, func(v: float): _push_wind(v, _spring_wind_y.value, _spring_wind_z.value))
	_spring_wind_y = _add_slider(vb, "風 Wind Y", -10.0, 10.0, 0.1, 0.0, func(v: float): _push_wind(_spring_wind_x.value, v, _spring_wind_z.value))
	_spring_wind_z = _add_slider(vb, "風 Wind Z", -10.0, 10.0, 0.1, 0.0, func(v: float): _push_wind(_spring_wind_x.value, _spring_wind_y.value, v))

	var btn_reset_sb := Button.new()
	btn_reset_sb.text = "SpringBone 物理・風をリセット"
	btn_reset_sb.pressed.connect(func():
		if controller != null:
			controller.set_spring_bone_params({"enabled": true, "gravity_scale": 1.0, "stiffness_scale": 1.0, "wind": [0.0, 0.0, 0.0]})
			if controller.current_vrm != null:
				controller.current_vrm.spring_bone.reset_state()
	)
	vb.add_child(btn_reset_sb)

	_add_section(vb, "VRM 仕様・メタ情報")
	_meta_text = RichTextLabel.new()
	_meta_text.custom_minimum_size = Vector2(0, 210)
	_meta_text.fit_content = false
	_meta_text.text = "モデルを読み込むと Meta / Humanoid / Constraint / SpringBone 情報が表示されます。"
	vb.add_child(_meta_text)


func _push_model_transform() -> void:
	if controller != null:
		controller.set_model_transform({
			"position": [_m_pos_x.value, _m_pos_y.value, _m_pos_z.value],
			"rotation_y_deg": _m_rot_y.value,
			"scale": _m_scale.value,
		})


func _push_wind(x: float, y: float, z: float) -> void:
	if controller != null:
		controller.set_spring_bone_params({"wind": [x, y, z]})


# ---------------------------------------------------------------------------
# Tab 2: Camera
# ---------------------------------------------------------------------------

func _build_tab_camera() -> void:
	var vb := _new_tab("Camera")
	_add_section(vb, "カメラプリセット")
	var grid := GridContainer.new()
	grid.columns = 3
	var presets := [
		["全身 (full_body)", "full_body"],
		["バスト (bust)", "bust"],
		["顔 (face)", "face"],
		["背面 (back)", "back"],
		["左側面 (left)", "left"],
		["右側面 (right)", "right"],
		["俯瞰 (top_down)", "top_down"],
	]
	for pair in presets:
		var lbl_p: String = pair[0]
		var key_p: String = pair[1]
		var btn := Button.new()
		btn.text = lbl_p
		btn.pressed.connect(func():
			if controller != null:
				controller.camera_rig.apply_preset(key_p, controller._get_model_height())
		)
		grid.add_child(btn)
	var btn_auto := Button.new()
	btn_auto.text = "Auto Frame"
	btn_auto.pressed.connect(func():
		if controller != null and controller.current_vrm != null:
			controller.camera_rig.auto_frame(controller.current_vrm.get_approx_bounds())
	)
	grid.add_child(btn_auto)
	var btn_cam_rst := Button.new()
	btn_cam_rst.text = "カメラ初期化"
	btn_cam_rst.pressed.connect(func():
		if controller != null:
			controller.camera_rig.apply_params({"fov_deg": 35.0, "orthographic": false})
			controller.camera_rig.apply_preset("full_body", controller._get_model_height())
	)
	grid.add_child(btn_cam_rst)
	vb.add_child(grid)

	_add_section(vb, "カメラ角度・距離・注視点")
	_cam_yaw_slider = _add_slider(vb, "水平角 Yaw (deg)", -180.0, 180.0, 0.5, 0.0, func(v: float): _push_cam({"yaw_deg": v}))
	_cam_pitch_slider = _add_slider(vb, "仰角 Pitch (deg)", -85.0, 85.0, 0.5, 6.0, func(v: float): _push_cam({"pitch_deg": v}))
	_cam_dist_slider = _add_slider(vb, "距離 Distance", 0.25, 10.0, 0.02, 2.2, func(v: float): _push_cam({"distance": v}))
	_cam_tgt_x = _add_slider(vb, "注視点 Target X", -3.0, 3.0, 0.02, 0.0, func(_v: float): _push_cam_target())
	_cam_tgt_y = _add_slider(vb, "注視点 Target Y", -0.5, 2.5, 0.02, 0.95, func(_v: float): _push_cam_target())
	_cam_tgt_z = _add_slider(vb, "注視点 Target Z", -3.0, 3.0, 0.02, 0.0, func(_v: float): _push_cam_target())

	_add_section(vb, "レンズ設定")
	_fov_slider = _add_slider(vb, "FOV (deg)", 15.0, 95.0, 1.0, 35.0, func(v: float): _push_cam({"fov_deg": v}))
	_ortho_chk = _add_check(vb, "平行投影 (Orthographic)", false, func(v: bool): _push_cam({"orthographic": v}))


func _push_cam(d: Dictionary) -> void:
	if controller != null:
		controller.camera_rig.apply_params(d)


func _push_cam_target() -> void:
	_push_cam({"target": [_cam_tgt_x.value, _cam_tgt_y.value, _cam_tgt_z.value]})


# ---------------------------------------------------------------------------
# Tab 3: Light
# ---------------------------------------------------------------------------

func _build_tab_lighting() -> void:
	var vb := _new_tab("Light")
	_add_section(vb, "ライティングプリセット")
	var hb := HFlowContainer.new()
	for p in ["studio", "daylight", "sunset", "dramatic", "flat_toon"]:
		var pname: String = p
		var b := Button.new()
		b.text = pname
		b.pressed.connect(func():
			if controller != null:
				controller.lighting_rig.apply_preset(pname)
		)
		hb.add_child(b)
	var b_lrst := Button.new()
	b_lrst.text = "初期値"
	b_lrst.pressed.connect(func():
		if controller != null:
			controller.lighting_rig.apply_preset("studio")
			controller.lighting_rig.apply_params({"exposure": 1.0, "bloom_intensity": 0.25})
	)
	hb.add_child(b_lrst)
	vb.add_child(hb)

	_add_section(vb, "ライト方向・プレビュー (ドラッグで直感操作)")
	var hb_dir := HBoxContainer.new()
	hb_dir.add_theme_constant_override("separation", 10)
	_light_pad = LightDirectionPadScript.new()
	_light_pad.direction_changed.connect(func(az: float, el: float):
		_push_light({"key_azimuth_deg": az, "key_elevation_deg": el})
	)
	hb_dir.add_child(_light_pad)

	var dir_right := VBoxContainer.new()
	dir_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dir_right.add_theme_constant_override("separation", 6)
	_light_dir_lbl = Label.new()
	_light_dir_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_light_dir_lbl.add_theme_color_override("font_color", Color("#ff8a90"))
	dir_right.add_child(_light_dir_lbl)

	var dir_grid := GridContainer.new()
	dir_grid.columns = 2
	var dir_presets := [
		["左上前", -45.0, 35.0],
		["右上前", 45.0, 35.0],
		["正面", 0.0, 15.0],
		["左横", -90.0, 25.0],
		["右横", 90.0, 25.0],
		["真上", 0.0, 82.0],
		["逆光", 170.0, 20.0],
		["下から", 20.0, -28.0],
	]
	for pair in dir_presets:
		var dlbl: String = pair[0]
		var daz: float = float(pair[1])
		var del: float = float(pair[2])
		var db := Button.new()
		db.text = dlbl
		db.pressed.connect(func():
			_push_light({"key_azimuth_deg": daz, "key_elevation_deg": del})
		)
		dir_grid.add_child(db)
	dir_right.add_child(dir_grid)
	hb_dir.add_child(dir_right)
	vb.add_child(hb_dir)

	_light_gizmo_chk = _add_check(vb, "3D ライト方向矢印を表示 (撮影・OBSには写りません)", false, func(v: bool):
		_push_light({"show_gizmo": v})
	)

	_add_section(vb, "ライト方向・強さ・カラー (数値微調整)")
	_key_az_slider = _add_slider(vb, "Key 方位角", -180.0, 180.0, 1.0, 35.0, func(v: float): _push_light({"key_azimuth_deg": v}))
	_key_el_slider = _add_slider(vb, "Key 仰角", -80.0, 80.0, 1.0, 30.0, func(v: float): _push_light({"key_elevation_deg": v}))
	_key_en_slider = _add_slider(vb, "Key 強さ", 0.0, 3.0, 0.05, 1.15, func(v: float): _push_light({"key_energy": v}))
	_key_col_btn = _add_color_row(vb, "Key 色", Color("#fff8f0"), func(c: Color): _push_light({"key_color": "#" + c.to_html(false)}))
	_fill_en_slider = _add_slider(vb, "Fill 強さ", 0.0, 2.0, 0.05, 0.42, func(v: float): _push_light({"fill_energy": v}))
	_fill_col_btn = _add_color_row(vb, "Fill 色", Color("#dce8ff"), func(c: Color): _push_light({"fill_color": "#" + c.to_html(false)}))
	_rim_en_slider = _add_slider(vb, "Rim 強さ", 0.0, 3.0, 0.05, 0.55, func(v: float): _push_light({"rim_energy": v}))
	_rim_col_btn = _add_color_row(vb, "Rim 色", Color("#ffffff"), func(c: Color): _push_light({"rim_color": "#" + c.to_html(false)}))
	_amb_en_slider = _add_slider(vb, "環境光強さ", 0.0, 2.0, 0.05, 0.45, func(v: float): _push_light({"ambient_energy": v}))
	_amb_col_btn = _add_color_row(vb, "環境光色", Color("#e6ebf5"), func(c: Color): _push_light({"ambient_color": "#" + c.to_html(false)}))

	_add_section(vb, "シャドウ / ブルーム / トーンマップ")
	_shadows_chk = _add_check(vb, "シャドウ有効", true, func(v: bool): _push_light({"shadows_enabled": v}))
	_bloom_chk = _add_check(vb, "Bloom 有効", false, func(v: bool): _push_light({"bloom_enabled": v}))
	_bloom_int_slider = _add_slider(vb, "Bloom 強度", 0.0, 2.0, 0.05, 0.25, func(v: float): _push_light({"bloom_intensity": v}))
	_exposure_slider = _add_slider(vb, "露出 Exposure", 0.2, 3.0, 0.05, 1.0, func(v: float): _push_light({"exposure": v}))

	var hb_tm := HBoxContainer.new()
	hb_tm.add_theme_constant_override("separation", 10)
	var l_tm := _row_label("トーンマップ")
	_tonemap_opt = OptionButton.new()
	for tm in ["filmic", "aces", "reinhard", "linear"]:
		_tonemap_opt.add_item(tm)
	_tonemap_opt.item_selected.connect(func(idx: int):
		if not _syncing:
			_push_light({"tonemap": _tonemap_opt.get_item_text(idx)})
	)
	hb_tm.add_child(l_tm)
	hb_tm.add_child(_tonemap_opt)
	vb.add_child(hb_tm)


func _push_light(d: Dictionary) -> void:
	if controller != null:
		controller.lighting_rig.apply_params(d)


# ---------------------------------------------------------------------------
# Tab 4: Pose
# ---------------------------------------------------------------------------

func _build_tab_pose() -> void:
	var vb := _new_tab("Pose")
	_add_section(vb, "クイックポーズプリセット")
	var pgrid := GridContainer.new()
	pgrid.columns = 4
	var pose_presets := [
		["Tポーズ", "t_pose"],
		["Aポーズ", "a_pose"],
		["気を付け", "attention"],
		["手を振る", "wave"],
		["ピース", "peace"],
		["座り", "sit"],
		["腰に手", "hands_on_hips"],
		["全リセット", "reset"],
	]
	for pair in pose_presets:
		var lbl_p: String = pair[0]
		var key_p: String = pair[1]
		var b := Button.new()
		b.text = lbl_p
		b.pressed.connect(func():
			if controller != null:
				controller.apply_pose_preset(key_p)
		)
		pgrid.add_child(b)
	vb.add_child(pgrid)

	_add_section(vb, "個別ボーン回転 (VRM Humanoid 正規化角 deg)")
	_pose_stop_anim_chk = CheckBox.new()
	_pose_stop_anim_chk.text = "ボーン操作時にアニメーションを自動停止"
	_pose_stop_anim_chk.button_pressed = true
	vb.add_child(_pose_stop_anim_chk)

	var hb_f := HBoxContainer.new()
	var lf := Label.new()
	lf.text = "部位フィルタ"
	lf.custom_minimum_size = Vector2(142, 0)
	_pose_filter_opt = OptionButton.new()
	for grp in ["全て", "体幹・頭", "左腕・左指", "右腕・右指", "脚"]:
		_pose_filter_opt.add_item(grp)
	_pose_filter_opt.item_selected.connect(func(_idx: int):
		_rebuild_pose_bone_options()
		_sync_pose_sliders_to_selected_bone()
	)
	hb_f.add_child(lf)
	hb_f.add_child(_pose_filter_opt)
	vb.add_child(hb_f)

	var hb_b := HBoxContainer.new()
	var lb := Label.new()
	lb.text = "対象ボーン"
	lb.custom_minimum_size = Vector2(142, 0)
	_pose_bone_opt = OptionButton.new()
	_pose_bone_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pose_bone_opt.item_selected.connect(func(_idx: int): _sync_pose_sliders_to_selected_bone())
	hb_b.add_child(lb)
	hb_b.add_child(_pose_bone_opt)
	vb.add_child(hb_b)

	_pose_bx = _add_slider(vb, "回転 X (前後)", -180.0, 180.0, 0.5, 0.0, func(_v: float): _push_selected_bone_pose())
	_pose_by = _add_slider(vb, "回転 Y (ひねり)", -180.0, 180.0, 0.5, 0.0, func(_v: float): _push_selected_bone_pose())
	_pose_bz = _add_slider(vb, "回転 Z (横開閉)", -180.0, 180.0, 0.5, 0.0, func(_v: float): _push_selected_bone_pose())

	var row_b := HFlowContainer.new()
	var b_rst_one := Button.new()
	b_rst_one.text = "このボーンをリセット"
	b_rst_one.pressed.connect(func():
		if controller != null and _pose_bone_opt.selected >= 0:
			controller.clear_single_bone_pose(_pose_bone_opt.get_item_text(_pose_bone_opt.selected))
	)
	row_b.add_child(b_rst_one)

	var b_mir_lr := Button.new()
	b_mir_lr.text = "左→右ミラー"
	b_mir_lr.pressed.connect(func():
		if controller != null:
			controller.mirror_bones_pose(true)
	)
	row_b.add_child(b_mir_lr)

	var b_mir_rl := Button.new()
	b_mir_rl.text = "右→左ミラー"
	b_mir_rl.pressed.connect(func():
		if controller != null:
			controller.mirror_bones_pose(false)
	)
	row_b.add_child(b_mir_rl)
	vb.add_child(row_b)

	_pose_edited_lbl = Label.new()
	_pose_edited_lbl.text = "編集済みボーン: なし"
	_pose_edited_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_pose_edited_lbl)

	_add_section(vb, "腰オフセット (Hips Position Offset)")
	_pose_hx = _add_slider(vb, "Hips X", -2.0, 2.0, 0.01, 0.0, func(_v: float): _push_hips_offset())
	_pose_hy = _add_slider(vb, "Hips Y", -2.0, 2.0, 0.01, 0.0, func(_v: float): _push_hips_offset())
	_pose_hz = _add_slider(vb, "Hips Z", -2.0, 2.0, 0.01, 0.0, func(_v: float): _push_hips_offset())
	var b_hrst := Button.new()
	b_hrst.text = "Hips 位置リセット"
	b_hrst.pressed.connect(func():
		if controller != null and controller.current_vrm != null:
			controller.current_vrm.direct_hips_offset = Vector3.ZERO
			controller.current_vrm.has_direct_hips_offset = false
			controller._emit_state_changed()
	)
	vb.add_child(b_hrst)

	_rebuild_pose_bone_options()


func _rebuild_pose_bone_options() -> void:
	if _pose_bone_opt == null:
		return
	var prev_sel: String = _pose_bone_opt.get_item_text(_pose_bone_opt.selected) if _pose_bone_opt.selected >= 0 else ""
	var filter_name: String = _pose_filter_opt.get_item_text(_pose_filter_opt.selected) if _pose_filter_opt != null and _pose_filter_opt.selected >= 0 else "全て"
	var source: Array[String] = _available_human_bones if not _available_human_bones.is_empty() else DEFAULT_BONE_LIST
	_pose_bone_opt.clear()
	for bname in source:
		if filter_name == "全て" or (BONE_GROUPS.has(filter_name) and BONE_GROUPS[filter_name].has(bname)):
			_pose_bone_opt.add_item(bname)
	if prev_sel != "":
		_select_option_text(_pose_bone_opt, prev_sel)
	if _pose_bone_opt.item_count > 0 and _pose_bone_opt.selected < 0:
		_pose_bone_opt.selected = 0


func _sync_pose_sliders_to_selected_bone() -> void:
	if _pose_bone_opt == null or _pose_bx == null:
		return
	var ev := Vector3.ZERO
	if controller != null and _pose_bone_opt.selected >= 0:
		var bname: String = _pose_bone_opt.get_item_text(_pose_bone_opt.selected)
		var d: Dictionary = controller.get_direct_bones_euler_deg()
		if d.has(bname):
			ev = d[bname]
	var prev_sync: bool = _syncing
	_syncing = true
	_pose_bx.value = ev.x
	_pose_by.value = ev.y
	_pose_bz.value = ev.z
	_syncing = prev_sync


func _push_selected_bone_pose() -> void:
	if controller == null or _pose_bone_opt.selected < 0:
		return
	if _pose_stop_anim_chk.button_pressed and controller.vrma_player.playing:
		controller.stop_animation_internal()
	var bname: String = _pose_bone_opt.get_item_text(_pose_bone_opt.selected)
	controller.set_single_bone_euler(bname, Vector3(_pose_bx.value, _pose_by.value, _pose_bz.value))


func _push_hips_offset() -> void:
	if controller == null:
		return
	if _pose_stop_anim_chk.button_pressed and controller.vrma_player.playing:
		controller.stop_animation_internal()
	controller.set_bones_pose({"hips_position": [_pose_hx.value, _pose_hy.value, _pose_hz.value]})


# ---------------------------------------------------------------------------
# Tab 5: Anim
# ---------------------------------------------------------------------------

func _play_anim_selected() -> void:
	if controller != null and _anim_selected != "":
		controller.play_animation_internal(_anim_selected, _anim_loop_chk.button_pressed, _anim_speed_slider.value, _anim_blend_slider.value)


## 一覧の動きのボタン: 背景は普段なし、マウスを載せると薄く、選ぶとアクセントの色
func _anim_clip_button(text: String, clip_name: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = clip_name
	b.toggle_mode = true
	b.button_group = _anim_btn_group
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	var mk := func(bg: Color) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		return sb
	b.add_theme_stylebox_override("normal", mk.call(Color(0, 0, 0, 0)))
	b.add_theme_stylebox_override("hover", mk.call(UiThemeScript.BG_3))
	b.add_theme_stylebox_override("pressed", mk.call(UiThemeScript.ACCENT_LO))
	b.add_theme_stylebox_override("hover_pressed", mk.call(UiThemeScript.ACCENT))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", UiThemeScript.TEXT)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	b.button_pressed = clip_name == _anim_selected
	b.toggled.connect(func(on: bool):
		if on:
			_anim_selected = clip_name
	)
	b.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.double_click and ev.button_index == MOUSE_BUTTON_LEFT:
			_anim_selected = clip_name
			_play_anim_selected()
	)
	return b


## 一覧の見出し (マウスを載せても変わらない)
func _anim_label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## 動きの一覧を、カテゴリーごとに見出しを付けて作り直す。カテゴリーを選んでいれば、そのカテゴリーだけ
func _fill_anim_list() -> void:
	var groups: Array = AnimCategoryScript.group(_anim_names_shown)
	# カテゴリーの選び肢を、今あるカテゴリーに合わせる (選んでいたものは残す)
	var want := ["すべて"]
	for g in groups:
		want.append("%s (%d)" % [g[0], g[1].size()])
	var picked := ""
	if _anim_cat_opt.selected > 0:
		picked = _anim_cat_opt.get_item_text(_anim_cat_opt.selected).get_slice(" (", 0)
	var have := []
	for i in _anim_cat_opt.item_count:
		have.append(_anim_cat_opt.get_item_text(i))
	if have != want:
		_anim_cat_opt.clear()
		for t in want:
			_anim_cat_opt.add_item(t)
		_anim_cat_opt.select(0)
		for i in range(1, want.size()):
			if str(want[i]).get_slice(" (", 0) == picked:
				_anim_cat_opt.select(i)
	var only := ""
	if _anim_cat_opt.selected > 0:
		only = _anim_cat_opt.get_item_text(_anim_cat_opt.selected).get_slice(" (", 0)
	# 女性・男性を左右の 2 列に、性別の無いものは「共通」の下に
	for c in _anim_list.get_children():
		_anim_list.remove_child(c)
		c.queue_free()
	for row in AnimCategoryScript.layout(_anim_names_shown, only == "", only):
		for c in row:
			match str(c["kind"]):
				"clip":
					_anim_list.add_child(_anim_clip_button(str(c["text"]), str(c["name"])))
				"category":
					_anim_list.add_child(_anim_label(str(c["text"]), UiThemeScript.ACCENT_HI))
				"gender":
					_anim_list.add_child(_anim_label(str(c["text"]), UiThemeScript.TEXT_DIM))
				_:
					_anim_list.add_child(_anim_label("", UiThemeScript.TEXT_DIM))


func _build_tab_animation() -> void:
	var vb := _new_tab("Anim")
	_add_section(vb, "VRMA アニメーション再生")
	var crow := HBoxContainer.new()
	var cl := Label.new()
	cl.text = "カテゴリー"
	crow.add_child(cl)
	_anim_cat_opt = OptionButton.new()
	_anim_cat_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_anim_cat_opt.add_item("すべて")
	_anim_cat_opt.item_selected.connect(func(_i: int): _fill_anim_list())
	crow.add_child(_anim_cat_opt)
	vb.add_child(crow)
	# 一覧: 枠の中をスクロール。クリックで選び、ダブルクリックで再生
	var frame := PanelContainer.new()
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = UiThemeScript.BG_2
	fsb.border_color = UiThemeScript.LINE
	fsb.set_border_width_all(1)
	fsb.set_corner_radius_all(6)
	fsb.set_content_margin_all(6)
	frame.add_theme_stylebox_override("panel", fsb)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_anim_list = GridContainer.new()
	_anim_list.columns = 2
	_anim_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_anim_list.add_theme_constant_override("h_separation", 8)
	_anim_list.add_theme_constant_override("v_separation", 1)
	scroll.add_child(_anim_list)
	frame.add_child(scroll)
	vb.add_child(frame)

	var row := HFlowContainer.new()
	var b_play := Button.new()
	b_play.text = "再生"
	b_play.pressed.connect(func():
		_play_anim_selected()
	)
	row.add_child(b_play)

	var b_pause := Button.new()
	b_pause.text = "一時停止 / 再開"
	b_pause.pressed.connect(func():
		if controller != null:
			controller.set_animation_params({"paused": not controller.vrma_player.paused})
	)
	row.add_child(b_pause)

	var b_stop := Button.new()
	b_stop.text = "停止 (Rest Pose)"
	b_stop.pressed.connect(func():
		if controller != null:
			controller.stop_animation_internal()
			controller.reset_bones_pose()
	)
	row.add_child(b_stop)

	var b_load := Button.new()
	b_load.text = "外部 .vrma / .npz 読込..."
	b_load.pressed.connect(func():
		if controller != null:
			controller.open_vrma_file_dialog()
	)
	row.add_child(b_load)
	vb.add_child(row)

	var prow := HFlowContainer.new()
	var b_anim_dir := Button.new()
	b_anim_dir.text = "プリセットのフォルダを開く"
	b_anim_dir.tooltip_text = "ここに .vrma や .npz (SMPL 系のモーション) を入れると、上の一覧に出ます。"
	b_anim_dir.pressed.connect(func():
		if controller != null:
			controller.open_presets_folder("animations")
	)
	prow.add_child(b_anim_dir)
	var b_anim_reload := Button.new()
	b_anim_reload.text = "フォルダを読み直す"
	b_anim_reload.pressed.connect(func():
		if controller != null:
			var n: int = controller.reload_animation_presets()
			show_snackbar("プリセットのアニメーションを %d 個読み込みました" % n, "", Callable(), 3.0)
	)
	prow.add_child(b_anim_reload)
	vb.add_child(prow)
	_trk_dim_note(vb, "プリセットのフォルダに入れた .vrma と .npz (AMASS などの SMPL / SMPL-H / SMPL-X のモーション) は、起動時と「フォルダを読み直す」で一覧に加わります。")

	var hb_sc := HBoxContainer.new()
	var ls := Label.new()
	ls.text = "再生位置"
	ls.custom_minimum_size = Vector2(142, 0)
	_anim_scrub = HSlider.new()
	_anim_scrub.min_value = 0.0
	_anim_scrub.max_value = 1.0
	_anim_scrub.step = 0.01
	_anim_scrub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_anim_scrub.drag_started.connect(func(): _scrub_dragging = true)
	_anim_scrub.drag_ended.connect(func(_changed: bool): _scrub_dragging = false)
	_anim_scrub.value_changed.connect(func(v: float):
		if not _syncing and controller != null:
			controller.set_animation_params({"seek_sec": v})
	)
	_anim_time_lbl = Label.new()
	_anim_time_lbl.custom_minimum_size = Vector2(96, 0)
	_anim_time_lbl.text = "0.00s / 0.00s"
	hb_sc.add_child(ls)
	hb_sc.add_child(_anim_scrub)
	hb_sc.add_child(_anim_time_lbl)
	vb.add_child(hb_sc)

	_anim_loop_chk = _add_check(vb, "ループ再生", true, func(v: bool):
		if controller != null:
			controller.set_animation_params({"looping": v})
	)
	_anim_speed_slider = _add_slider(vb, "再生速度", 0.0, 3.0, 0.05, 1.0, func(v: float):
		if controller != null:
			controller.set_animation_params({"speed": v})
	)
	_anim_blend_slider = _add_slider(vb, "切替フェード秒", 0.0, 1.5, 0.05, 0.25, func(_v: float): pass)

	_add_section(vb, "自然な待機挙動 (Procedural Idle)")
	_idle_enabled_chk = _add_check(vb, "待機挙動 有効", true, func(v: bool): _set_idle({"enabled": v}))
	_idle_breath_chk = _add_check(vb, "呼吸", true, func(v: bool): _set_idle({"breathing": v}))
	_idle_blink_chk = _add_check(vb, "自動まばたき", true, func(v: bool): _set_idle({"blink": v}))
	_idle_saccade_chk = _add_check(vb, "視線サッケード", true, func(v: bool): _set_idle({"saccade": v}))
	_idle_sway_chk = _add_check(vb, "自然な重心揺れ", true, func(v: bool): _set_idle({"sway": v}))
	_idle_intensity_slider = _add_slider(vb, "待機強度", 0.0, 2.5, 0.05, 1.0, func(v: float): _set_idle({"intensity": v}))


func _set_idle(d: Dictionary) -> void:
	if controller != null:
		controller.procedural_idle.apply_params(d)


# ---------------------------------------------------------------------------
# Tab 6: Expr
# ---------------------------------------------------------------------------

func _build_tab_expressions() -> void:
	var vb := _new_tab("Expr")
	_add_section(vb, "視線 LookAt")
	_lookat_opt = OptionButton.new()
	for m in ["camera", "manual", "off"]:
		_lookat_opt.add_item(m)
	_lookat_opt.item_selected.connect(func(idx: int):
		if not _syncing and controller != null:
			controller.set_lookat_params({"mode": _lookat_opt.get_item_text(idx)})
	)
	vb.add_child(_lookat_opt)
	_lookat_tx = _add_slider(vb, "注視点 Target X", -3.0, 3.0, 0.05, 0.0, func(_v: float): _push_lookat_target())
	_lookat_ty = _add_slider(vb, "注視点 Target Y", 0.0, 3.0, 0.05, 1.4, func(_v: float): _push_lookat_target())
	_lookat_tz = _add_slider(vb, "注視点 Target Z", -3.0, 4.0, 0.05, 2.0, func(_v: float): _push_lookat_target())

	_add_section(vb, "クイック表情・トランジション")
	_expr_trans_slider = _add_slider(vb, "遷移時間 (秒)", 0.0, 1.0, 0.02, 0.12, func(_v: float): pass)
	var qrow := HFlowContainer.new()
	for ename in ["neutral", "happy", "angry", "sad", "relaxed", "surprised", "blink"]:
		var key_e: String = ename
		var b := Button.new()
		b.text = key_e
		b.pressed.connect(func():
			if controller != null:
				var tr: float = _expr_trans_slider.value
				if key_e == "neutral":
					controller.reset_expressions(tr)
				else:
					controller.set_expressions_weights({key_e: 1.0}, tr, true)
		)
		qrow.add_child(b)
	var btn_rst := Button.new()
	btn_rst.text = "すべてリセット"
	btn_rst.pressed.connect(func():
		if controller != null:
			controller.reset_expressions(_expr_trans_slider.value)
	)
	qrow.add_child(btn_rst)
	vb.add_child(qrow)

	_add_section(vb, "表情プリセット / カスタム")
	_expr_box = VBoxContainer.new()
	vb.add_child(_expr_box)

	_add_section(vb, "ショートカット (F1〜F12)")
	_global_hk_chk = _add_check(vb, "グローバルホットキー有効 (非アクティブ時も反応)", false, func(v: bool):
		if controller != null:
			controller.hotkey_manager.apply_params({"global_enabled": v})
	)
	for key in ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"]:
		var hk_key: String = key
		var hb := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = hk_key
		lbl.custom_minimum_size = Vector2(48, 0)
		var le := LineEdit.new()
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.text_submitted.connect(func(new_t: String):
			if controller != null:
				controller.hotkey_manager.apply_params({"bindings": {hk_key: new_t}})
		)
		le.focus_exited.connect(func():
			if not _syncing and controller != null:
				controller.hotkey_manager.apply_params({"bindings": {hk_key: le.text}})
		)
		_hotkey_edits[hk_key] = le
		hb.add_child(lbl)
		hb.add_child(le)
		vb.add_child(hb)


func _push_lookat_target() -> void:
	if controller != null:
		controller.set_lookat_params({"target": [_lookat_tx.value, _lookat_ty.value, _lookat_tz.value]})


# ---------------------------------------------------------------------------
# Tab 7: Window
# ---------------------------------------------------------------------------

func _build_tab_background() -> void:
	var vb := _new_tab("Window")
	_add_section(vb, "表示背景モード")
	_bg_mode_opt = OptionButton.new()
	for m in ["solid", "chroma_green", "chroma_blue", "gradient", "image", "transparent_window"]:
		_bg_mode_opt.add_item(m)
	_bg_mode_opt.item_selected.connect(func(idx: int):
		if not _syncing and controller != null:
			controller.bg_manager.apply_background({"mode": _bg_mode_opt.get_item_text(idx)})
	)
	vb.add_child(_bg_mode_opt)

	# ワンクリックの背景: 透過を切って、黒・白で塗りつぶす (配信の合成やキャプチャ用)
	var hb_solid := HBoxContainer.new()
	hb_solid.add_theme_constant_override("separation", 8)
	for item in [["真っ黒 (透過なし)", "#000000"], ["真っ白 (透過なし)", "#ffffff"]]:
		var b_solid := Button.new()
		b_solid.text = str(item[0])
		b_solid.tooltip_text = "ウィンドウの透過を切り、背景を %s の単色にします。" % str(item[1])
		var col := str(item[1])
		b_solid.pressed.connect(func():
			if controller != null:
				controller.bg_manager.apply_background({"mode": "solid", "color": col})
		)
		hb_solid.add_child(b_solid)
	vb.add_child(hb_solid)

	_bg_color_btn = _add_color_row(vb, "背景色 / グラデ上色", Color("#1e222b"), func(c: Color):
		if controller != null:
			controller.bg_manager.apply_background({"color": "#" + c.to_html(false)})
	)
	_bg_grad_bot_btn = _add_color_row(vb, "グラデ下色", Color("#0f1218"), func(c: Color):
		if controller != null:
			controller.bg_manager.apply_background({"gradient_bottom": "#" + c.to_html(false)})
	)

	var hb_img := HBoxContainer.new()
	var b_img := Button.new()
	b_img.text = "背景画像を選択..."
	b_img.pressed.connect(func():
		if controller != null:
			controller.open_bg_image_dialog()
	)
	_bg_img_lbl = Label.new()
	_bg_img_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bg_img_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hb_img.add_child(b_img)
	hb_img.add_child(_bg_img_lbl)
	vb.add_child(hb_img)

	_add_section(vb, "ウィンドウ / デスクトップマスコット設定")
	_win_trans_chk = _add_check(vb, "ウィンドウ背景透過", false, func(v: bool):
		if controller != null:
			controller.bg_manager.apply_window({"transparent": v})
			if v:
				_suggest_black_background()
	)
	_win_border_chk = _add_check(vb, "枠なしウィンドウ (Borderless / Alt+ドラッグ移動)", false, func(v: bool):
		if controller != null:
			controller.bg_manager.apply_window({"borderless": v})
	)
	_win_top_chk = _add_check(vb, "常に最前面 (Always on Top)", false, func(v: bool):
		if controller != null:
			controller.bg_manager.apply_window({"always_on_top": v})
	)
	_win_click_chk = _add_check(vb, "クリックスルー (マウス貫通 / 解除はタスクトレイから)", false, func(v: bool):
		if controller != null:
			controller.bg_manager.apply_window({"click_through": v})
			if v:
				show_snackbar("クリックスルー中はキャラクターをクリックできません。解除や設定ウィンドウの表示は、タスクトレイ (画面右下の「^」の中) の うつしみらー アイコンから行えます。", "", Callable(), 12.0)
	)

	var hb_mas := HFlowContainer.new()
	var b_mascot := Button.new()
	b_mascot.text = "デスクトップマスコットモード (透過+枠なし+最前面)"
	b_mascot.pressed.connect(func():
		if controller != null:
			controller.bg_manager.apply_background({"mode": "transparent_window"})
			controller.bg_manager.apply_window({"transparent": true, "borderless": true, "always_on_top": true})
			_suggest_black_background()
	)
	var b_norm := Button.new()
	b_norm.text = "通常ウィンドウに戻す"
	b_norm.pressed.connect(func():
		if controller != null:
			controller.bg_manager.restore_normal_window()
	)
	hb_mas.add_child(b_mascot)
	hb_mas.add_child(b_norm)
	vb.add_child(hb_mas)

	_add_section(vb, "メインウィンドウサイズ")
	var hb_ws := HBoxContainer.new()
	_win_w_spin = SpinBox.new()
	_win_w_spin.min_value = 320
	_win_w_spin.max_value = 3840
	_win_w_spin.step = 10
	_win_w_spin.value = 1000
	_win_h_spin = SpinBox.new()
	_win_h_spin.min_value = 240
	_win_h_spin.max_value = 2160
	_win_h_spin.step = 10
	_win_h_spin.value = 900
	var b_ws_apply := Button.new()
	b_ws_apply.text = "サイズ適用"
	b_ws_apply.pressed.connect(func():
		if controller != null:
			controller.bg_manager.apply_window({"size": [int(_win_w_spin.value), int(_win_h_spin.value)]})
	)
	hb_ws.add_child(Label.new())
	hb_ws.get_child(0).text = "W:"
	hb_ws.add_child(_win_w_spin)
	var lh := Label.new()
	lh.text = "H:"
	hb_ws.add_child(lh)
	hb_ws.add_child(_win_h_spin)
	hb_ws.add_child(b_ws_apply)
	vb.add_child(hb_ws)

	var hb_wpre := HFlowContainer.new()
	for sz in [[800, 900], [1000, 900], [1280, 720], [1920, 1080]]:
		var sw: int = int(sz[0])
		var sh: int = int(sz[1])
		var bp := Button.new()
		bp.text = "%dx%d" % [sw, sh]
		bp.pressed.connect(func():
			if controller != null:
				controller.bg_manager.apply_window({"size": [sw, sh]})
		)
		hb_wpre.add_child(bp)
	vb.add_child(hb_wpre)


# ---------------------------------------------------------------------------
# Tab 8: Output
# ---------------------------------------------------------------------------

func _build_tab_output() -> void:
	var vb := _new_tab("Output")
	_add_section(vb, "出力ビューポート設定 (OBS/録画/スクショ共通)")
	_out_res_opt = OptionButton.new()
	for r in ["1280x720", "1920x1080", "2560x1440", "3840x2160"]:
		_out_res_opt.add_item(r)
	_out_res_opt.item_selected.connect(func(idx: int):
		if not _syncing and controller != null:
			var parts := _out_res_opt.get_item_text(idx).split("x")
			controller.bg_manager.apply_output_viewport({"width": int(parts[0]), "height": int(parts[1])})
	)
	vb.add_child(_out_res_opt)

	_out_bg_opt = OptionButton.new()
	for m in ["transparent", "match_main", "chroma_green", "solid", "image"]:
		_out_bg_opt.add_item(m)
	_out_bg_opt.item_selected.connect(func(idx: int):
		if not _syncing and controller != null:
			controller.bg_manager.apply_output_viewport({"background_mode": _out_bg_opt.get_item_text(idx)})
	)
	vb.add_child(_out_bg_opt)

	_out_color_btn = _add_color_row(vb, "出力単色背景カラー", Color("#00ff00"), func(c: Color):
		if controller != null:
			controller.bg_manager.apply_output_viewport({"color": "#" + c.to_html(false)})
	)
	var b_out_img := Button.new()
	b_out_img.text = "出力背景画像を選択..."
	b_out_img.pressed.connect(func(): _file_dialog_out_img.popup_centered(Vector2i(760, 520)))
	vb.add_child(b_out_img)

	_add_section(vb, "スクリーンショット / 録画")
	var b_shot := Button.new()
	b_shot.text = "スクリーンショット撮影 (F11)"
	b_shot.pressed.connect(func():
		if controller != null:
			controller.take_screenshot()
	)
	vb.add_child(b_shot)

	_shot_dir_lbl = Label.new()
	_shot_dir_lbl.theme_type_variation = "DimLabel"
	_shot_dir_lbl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_shot_dir_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	_shot_dir_lbl.tooltip_text = "ここに PNG で保存されます (F11 でも撮影できます)"
	vb.add_child(_shot_dir_lbl)

	var hb_fps := HBoxContainer.new()
	var lfps := Label.new()
	lfps.text = "録画 FPS"
	lfps.custom_minimum_size = Vector2(142, 0)
	_rec_fps_opt = OptionButton.new()
	for fps_s in ["24", "30", "60"]:
		_rec_fps_opt.add_item(fps_s)
	_rec_fps_opt.selected = 2
	hb_fps.add_child(lfps)
	hb_fps.add_child(_rec_fps_opt)
	vb.add_child(hb_fps)

	var hb_rec := HFlowContainer.new()
	_rec_mp4_btn = Button.new()
	_rec_mp4_btn.text = "MP4録画 開始/停止"
	_rec_mp4_btn.pressed.connect(func(): _toggle_rec("mp4"))
	_rec_webm_btn = Button.new()
	_rec_webm_btn.text = "透過WebM録画 開始/停止"
	_rec_webm_btn.pressed.connect(func(): _toggle_rec("webm_alpha"))
	hb_rec.add_child(_rec_mp4_btn)
	hb_rec.add_child(_rec_webm_btn)
	vb.add_child(hb_rec)

	_rec_status_lbl = Label.new()
	_rec_status_lbl.text = "録画停止中"
	_rec_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_rec_status_lbl)

	var hb_dirs := HFlowContainer.new()
	var b_open_ss := Button.new()
	b_open_ss.text = "screenshots フォルダを開く"
	b_open_ss.pressed.connect(func(): _open_capture_dir("screenshots"))
	var b_open_rec := Button.new()
	b_open_rec.text = "recordings フォルダを開く"
	b_open_rec.pressed.connect(func(): _open_capture_dir("recordings"))
	hb_dirs.add_child(b_open_ss)
	hb_dirs.add_child(b_open_rec)
	vb.add_child(hb_dirs)

	_add_section(vb, "OBS連携 (Spout2) / 仮想カメラ (Discord・Zoom)")
	var hb_sp := HBoxContainer.new()
	_spout_chk = _add_check(vb, "Spout2 出力 (OBS)", false, func(v: bool):
		if controller != null:
			controller.capture_manager.set_spout({"enabled": v, "sender_name": _spout_name_edit.text})
	)
	_spout_name_edit = LineEdit.new()
	_spout_name_edit.text = "UtsushiMirror"
	_spout_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spout_name_edit.text_submitted.connect(func(new_s: String):
		if controller != null and _spout_chk.button_pressed:
			controller.capture_manager.set_spout({"enabled": true, "sender_name": new_s})
	)
	var ls_sp := Label.new()
	ls_sp.text = "Sender名:"
	ls_sp.custom_minimum_size = Vector2(142, 0)
	hb_sp.add_child(ls_sp)
	hb_sp.add_child(_spout_name_edit)
	vb.add_child(hb_sp)

	_vcam_chk = _add_check(vb, "仮想カメラ出力 (Discord / Zoom)", false, func(v: bool):
		if controller != null:
			controller.capture_manager.set_vcam({"enabled": v})
	)
	_vcam_status_lbl = Label.new()
	_vcam_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_vcam_status_lbl)


func _open_capture_dir(sub: String) -> void:
	var target_dir: String = ConfigManagerScript.get_app_root_dir().path_join(sub)
	if controller != null and controller.capture_manager != null:
		var rel: String = controller.capture_manager.screenshots_dir if sub == "screenshots" else controller.capture_manager.recordings_dir
		target_dir = controller.capture_manager._resolve_output_path(rel)
	DirAccess.make_dir_recursive_absolute(target_dir)
	OS.shell_open(target_dir)


func _toggle_rec(fmt: String) -> void:
	if controller == null:
		return
	if controller.capture_manager.recording_active:
		controller.capture_manager.stop_recording()
	else:
		var fps: int = int(_rec_fps_opt.get_item_text(_rec_fps_opt.selected)) if _rec_fps_opt.selected >= 0 else 60
		controller.capture_manager.start_recording({"format": fmt, "fps": fps})


# ---------------------------------------------------------------------------
# Tab 9: API/Config
# ---------------------------------------------------------------------------

func _build_tab_api() -> void:
	var vb := _new_tab("API/Config")
	_add_section(vb, "CLI / MCP / OSC(VMC) サーバー状態")
	_api_status_lbl = Label.new()
	_api_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_api_status_lbl)

	var hb_ports := HBoxContainer.new()
	_ws_port_spin = SpinBox.new()
	_ws_port_spin.min_value = 1024
	_ws_port_spin.max_value = 65535
	_ws_port_spin.value = 19100
	_osc_port_spin = SpinBox.new()
	_osc_port_spin.min_value = 1024
	_osc_port_spin.max_value = 65535
	_osc_port_spin.value = 39539
	var b_ports := Button.new()
	b_ports.text = "ポート保存 (次回起動時反映)"
	b_ports.pressed.connect(func():
		if controller != null:
			controller.ws_port = int(_ws_port_spin.value)
			controller.osc_port = int(_osc_port_spin.value)
			var r: Dictionary = controller.save_config()
			_api_status_lbl.text = "ポート設定を保存しました: " + str(r.get("path", ""))
	)
	var lw := Label.new()
	lw.text = "WS:"
	var lo := Label.new()
	lo.text = "OSC:"
	hb_ports.add_child(lw)
	hb_ports.add_child(_ws_port_spin)
	hb_ports.add_child(lo)
	hb_ports.add_child(_osc_port_spin)
	hb_ports.add_child(b_ports)
	vb.add_child(hb_ports)

	_add_section(vb, "設定の保存・復元・初期化")
	var hb := HFlowContainer.new()
	var b_save := Button.new()
	b_save.text = "設定を保存"
	b_save.pressed.connect(func():
		if controller != null:
			var r: Dictionary = controller.save_config()
			_api_status_lbl.text = "保存完了: " + str(r.get("path", ""))
	)
	var b_load := Button.new()
	b_load.text = "設定を再読込"
	b_load.pressed.connect(func():
		if controller != null:
			controller.reload_config()
	)
	var b_rst_all := Button.new()
	b_rst_all.text = "全設定を初期値に戻す"
	b_rst_all.pressed.connect(func():
		if controller != null:
			controller.reset_all_settings()
	)
	hb.add_child(b_save)
	hb.add_child(b_load)
	hb.add_child(b_rst_all)
	vb.add_child(hb)

	_add_section(vb, "操作・ショートカット一覧")
	var help_lbl := Label.new()
	help_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_lbl.text = (
		"• 左ドラッグ / 右ドラッグ: カメラ回転\n"
		+ "• Shift + 左ドラッグ / 中ドラッグ: カメラ平行移動\n"
		+ "• マウスホイール: ズームイン・アウト\n"
		+ "• 右クリック (メインウィンドウ): コンテキストメニュー\n"
		+ "• Alt + 左ドラッグ: 枠なしウィンドウの移動\n"
		+ "• F1〜F10: 表情プリセット切替\n"
		+ "• F11: スクリーンショット / F12: 録画開始・停止\n"
		+ "• Ctrl+Shift+S: 設定表示切替
"
		+ "• タスクトレイの うつしみらー アイコン: 設定を開く・クリックスルー解除・通常ウィンドウに戻す"
	)
	vb.add_child(help_lbl)


# ---------------------------------------------------------------------------
# State Synchronization
# ---------------------------------------------------------------------------

func _on_model_loaded(info: Dictionary) -> void:
	_available_human_bones.clear()
	for hb in info.get("human_bones", []):
		_available_human_bones.append(str(hb))
	_available_human_bones.sort()
	_rebuild_pose_bone_options()
	_rebuild_expression_sliders(info.get("expressions", []))
	var meta: Dictionary = info.get("meta", {})
	var authors := ", ".join(meta.get("authors", []))
	_meta_text.text = (
		"Name: %s\nVersion: %s\nAuthors: %s\nLicense: %s\nHumanBones: %d\nConstraints: %d\nSprings: %d"
		% [
			str(meta.get("name", "?")),
			str(info.get("vrm_version", "1.0")),
			authors,
			str(meta.get("licenseUrl", "")),
			info.get("human_bones", []).size(),
			info.get("constraints", []).size(),
			int(info.get("spring_bone", {}).get("springs", 0)),
		]
	)


func _rebuild_expression_sliders(names: Array) -> void:
	for c in _expr_box.get_children():
		c.queue_free()
	_expr_sliders.clear()
	for ename in names:
		var s_name := str(ename)
		var sl := _add_slider(_expr_box, s_name, 0.0, 1.0, 0.01, 0.0, func(v: float):
			if controller != null:
				controller.set_expression_weight(s_name, v, 0.0)
		)
		_expr_sliders[s_name] = sl


func _refresh_from_controller() -> void:
	if controller == null:
		return
	_syncing = true
	var st: Dictionary = controller.get_full_state()
	_model_status_lbl.text = ("読み込み済み: " + str(st.get("model_name", ""))) if st.get("model_loaded", false) else "モデル未読み込み（ウィンドウへの D&D でも読込できます）"
	_first_person_chk.button_pressed = bool(st.get("first_person", false))
	if _header_sub_lbl != null:
		_header_sub_lbl.text = str(st.get("model_name", "")) if st.get("model_loaded", false) else "モデル未読み込み — ファイルをドラッグ＆ドロップで読み込めます"
	if _api_dot != null:
		var api_st: Dictionary = st.get("api", {})
		var running: bool = bool(api_st.get("running", false))
		_api_dot.text = "● API  WS:%s / OSC:%s" % [str(api_st.get("ws_port", "-")), str(api_st.get("osc_port", "-"))]
		_api_dot.add_theme_color_override("font_color", Color("#3ddc84") if running else UiThemeScript.TEXT_MUTED)
	_refresh_tracking_ui(st)
	_refresh_effects_ui(st)
	if _shot_dir_lbl != null:
		var last: String = controller.last_screenshot_path
		_shot_dir_lbl.text = "保存先: %s%s" % [controller.get_screenshots_dir(), ("\n最新: " + last.get_file()) if last != "" else ""]

	var rec_paths: Array = st.get("recent_vrm_paths", [])
	_recent_opt.clear()
	for rp in rec_paths:
		var sp: String = str(rp)
		var idx: int = _recent_opt.item_count
		_recent_opt.add_item(sp.get_file())
		_recent_opt.set_item_metadata(idx, sp)

	var xf: Dictionary = st.get("model_transform", {})
	var mpos: Array = xf.get("position", [0.0, 0.0, 0.0])
	if mpos.size() >= 3:
		_m_pos_x.value = float(mpos[0])
		_m_pos_y.value = float(mpos[1])
		_m_pos_z.value = float(mpos[2])
	_m_rot_y.value = float(xf.get("rotation_y_deg", 0.0))
	_m_scale.value = float(xf.get("scale", 1.0))

	var sb: Dictionary = st.get("spring_bone", {})
	_sb_enabled_chk.button_pressed = bool(sb.get("enabled", true))
	_sb_grav_slider.value = float(sb.get("gravity_scale", 1.0))
	_sb_stiff_slider.value = float(sb.get("stiffness_scale", 1.0))

	var cam: Dictionary = st.get("camera", {})
	_cam_yaw_slider.value = float(cam.get("yaw_deg", 0.0))
	_cam_pitch_slider.value = float(cam.get("pitch_deg", 6.0))
	_cam_dist_slider.value = float(cam.get("distance", 2.2))
	var ctgt: Array = cam.get("target", [0.0, 0.95, 0.0])
	if ctgt.size() >= 3:
		_cam_tgt_x.value = float(ctgt[0])
		_cam_tgt_y.value = float(ctgt[1])
		_cam_tgt_z.value = float(ctgt[2])
	_fov_slider.value = float(cam.get("fov_deg", 35.0))
	_ortho_chk.button_pressed = bool(cam.get("orthographic", false))

	var lit: Dictionary = st.get("lighting", {})
	var l_az: float = float(lit.get("key_azimuth_deg", 35.0))
	var l_el: float = float(lit.get("key_elevation_deg", 30.0))
	var l_kc := Color(str(lit.get("key_color", "#fff8f0")))
	var l_fc := Color(str(lit.get("fill_color", "#dce8ff")))
	var l_ae: float = float(lit.get("ambient_energy", 0.45))
	_key_az_slider.value = l_az
	_key_el_slider.value = l_el
	_key_en_slider.value = float(lit.get("key_energy", 1.15))
	_key_col_btn.color = l_kc
	_fill_en_slider.value = float(lit.get("fill_energy", 0.42))
	_fill_col_btn.color = l_fc
	_rim_en_slider.value = float(lit.get("rim_energy", 0.55))
	_rim_col_btn.color = Color(str(lit.get("rim_color", "#ffffff")))
	_amb_en_slider.value = l_ae
	_amb_col_btn.color = Color(str(lit.get("ambient_color", "#e6ebf5")))
	_shadows_chk.button_pressed = bool(lit.get("shadows_enabled", true))
	_bloom_chk.button_pressed = bool(lit.get("bloom_enabled", false))
	_bloom_int_slider.value = float(lit.get("bloom_intensity", 0.25))
	_exposure_slider.value = float(lit.get("exposure", 1.0))
	_select_option_text(_tonemap_opt, str(lit.get("tonemap", "filmic")))
	_light_gizmo_chk.button_pressed = bool(lit.get("show_gizmo", false))
	if _light_pad != null:
		_light_pad.set_values(l_az, l_el, l_kc, l_fc, l_ae)
	if _light_dir_lbl != null and controller != null:
		_light_dir_lbl.text = "現在: " + controller.lighting_rig.describe_direction(l_az, l_el)

	var w: Array = lit.get("wind", [0.0, 0.0, 0.0])
	if w.size() >= 3:
		_spring_wind_x.value = float(w[0])
		_spring_wind_y.value = float(w[1])
		_spring_wind_z.value = float(w[2])

	# Pose tab sync
	var dbones: Dictionary = controller.get_direct_bones_euler_deg()
	if dbones.is_empty():
		_pose_edited_lbl.text = "編集済みボーン: なし"
	else:
		var bkeys: Array[String] = []
		for bk in dbones.keys():
			bkeys.append(str(bk))
		bkeys.sort()
		_pose_edited_lbl.text = "編集済みボーン: " + ", ".join(bkeys)
	var hp: Vector3 = controller.get_direct_hips_offset()
	_pose_hx.value = hp.x
	_pose_hy.value = hp.y
	_pose_hz.value = hp.z

	# Animations list
	var new_names := []
	for a in st.get("available_animations", []):
		new_names.append(str(a))
	if _anim_names_shown != new_names:
		_anim_names_shown = new_names
		_fill_anim_list()
	var anim_st: Dictionary = st.get("animation", {})
	_anim_loop_chk.button_pressed = bool(anim_st.get("looping", true))
	_anim_speed_slider.value = float(anim_st.get("speed", 1.0))
	var adur: float = maxf(float(anim_st.get("duration", 0.0)), 0.01)
	var atime: float = clampf(float(anim_st.get("time_sec", 0.0)), 0.0, adur)
	_anim_scrub.max_value = adur
	_anim_scrub.value = atime
	_anim_time_lbl.text = "%.2fs / %.2fs" % [atime, float(anim_st.get("duration", 0.0))]

	var idle_st: Dictionary = st.get("idle", {})
	_idle_enabled_chk.button_pressed = bool(idle_st.get("enabled", true))
	_idle_breath_chk.button_pressed = bool(idle_st.get("breathing", true))
	_idle_blink_chk.button_pressed = bool(idle_st.get("blink", true))
	_idle_saccade_chk.button_pressed = bool(idle_st.get("saccade", true))
	_idle_sway_chk.button_pressed = bool(idle_st.get("sway", true))
	_idle_intensity_slider.value = float(idle_st.get("intensity", 1.0))

	var exprs: Dictionary = st.get("expressions", {})
	for ename in _expr_sliders.keys():
		if exprs.has(ename):
			(_expr_sliders[ename] as HSlider).value = float(exprs[ename])

	_select_option_text(_lookat_opt, str(st.get("lookat_mode", "camera")))
	var ltgt: Array = st.get("lookat_target", [0.0, 1.4, 2.0])
	if ltgt.size() >= 3:
		_lookat_tx.value = float(ltgt[0])
		_lookat_ty.value = float(ltgt[1])
		_lookat_tz.value = float(ltgt[2])

	var hk: Dictionary = st.get("hotkeys", {})
	_global_hk_chk.button_pressed = bool(hk.get("global_enabled", false))
	var bindings: Dictionary = hk.get("bindings", {})
	for k in _hotkey_edits.keys():
		if bindings.has(k):
			(_hotkey_edits[k] as LineEdit).text = str(bindings[k])

	var bg: Dictionary = st.get("background", {})
	_select_option_text(_bg_mode_opt, str(bg.get("mode", "solid")))
	_bg_color_btn.color = Color(str(bg.get("color", "#1e222b")))
	_bg_grad_bot_btn.color = Color(str(bg.get("gradient_bottom", "#0f1218")))
	var bg_img_p: String = str(bg.get("image_path", ""))
	_bg_img_lbl.text = bg_img_p.get_file() if bg_img_p != "" else "未選択"

	var win: Dictionary = st.get("window", {})
	_win_trans_chk.button_pressed = bool(win.get("transparent", false))
	_win_border_chk.button_pressed = bool(win.get("borderless", false))
	_win_top_chk.button_pressed = bool(win.get("always_on_top", false))
	_win_click_chk.button_pressed = bool(win.get("click_through", false))
	_win_w_spin.value = float(win.get("width", 1000))
	_win_h_spin.value = float(win.get("height", 900))

	var ov: Dictionary = st.get("output_viewport", {})
	_select_option_text(_out_res_opt, "%dx%d" % [int(ov.get("width", 1280)), int(ov.get("height", 720))])
	_select_option_text(_out_bg_opt, str(ov.get("background_mode", "transparent")))
	_out_color_btn.color = Color(str(ov.get("color", "#00ff00")))

	var cap: Dictionary = st.get("capture", {})
	_spout_chk.button_pressed = bool(cap.get("spout_enabled", false))
	_spout_name_edit.text = str(cap.get("spout_sender_name", "UtsushiMirror"))
	_rec_status_lbl.text = ("録画中: " + str(cap.get("recording_path", ""))) if bool(cap.get("recording_active", false)) else "録画停止中"

	var vc: Dictionary = st.get("vcam_status", {})
	var vc_avail := bool(vc.get("available", false))
	_vcam_chk.disabled = not vc_avail
	_vcam_chk.button_pressed = bool(cap.get("vcam_enabled", false)) and vc_avail
	_vcam_status_lbl.text = str(vc.get("message", ""))

	var api: Dictionary = st.get("api", {})
	_ws_port_spin.value = float(api.get("ws_port", 19100))
	_osc_port_spin.value = float(api.get("osc_port", 39539))
	_api_status_lbl.text = "WebSocket JSON-RPC: ws://127.0.0.1:%d (running=%s)\nOSC/VMC UDP: 127.0.0.1:%d" % [
		int(api.get("ws_port", 19100)),
		str(api.get("running", false)),
		int(api.get("osc_port", 39539)),
	]
	_syncing = false
	_sync_pose_sliders_to_selected_bone()


static func _select_option_text(opt: OptionButton, text_val: String) -> void:
	for i in range(opt.item_count):
		if opt.get_item_text(i) == text_val:
			opt.selected = i
			return

# ---------------------------------------------------------------------------
# スナックバー (画面下に一時的に出る通知。操作ボタンを1つ付けられる)
# ---------------------------------------------------------------------------

var _snack: PanelContainer
var _snack_lbl: Label
var _snack_btn: Button
var _snack_action: Callable
var _snack_timer: Timer
var _snack_tween: Tween


func _build_snackbar() -> void:
	var holder := MarginContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	holder.offset_top = -130
	holder.offset_bottom = -62  # フッターの上
	holder.add_theme_constant_override("margin_left", 216)  # サイドバーの右
	holder.add_theme_constant_override("margin_right", 20)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.theme = UiThemeScript.get_theme()
	add_child(holder)

	_snack = PanelContainer.new()
	var st := UiThemeScript.box(Color("#22252d"), 8, Color("#3a3f4a"), 1, 14, 10)
	st.border_color = UiThemeScript.ACCENT
	st.border_width_left = 4
	st.shadow_color = Color(0, 0, 0, 0.45)
	st.shadow_size = 10
	_snack.add_theme_stylebox_override("panel", st)
	_snack.size_flags_vertical = Control.SIZE_SHRINK_END
	_snack.visible = false
	holder.add_child(_snack)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	_snack.add_child(hb)
	_snack_lbl = Label.new()
	_snack_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_snack_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_snack_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(_snack_lbl)
	_snack_btn = Button.new()
	_snack_btn.theme_type_variation = "AccentButton"
	_snack_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_snack_btn.pressed.connect(func():
		var act := _snack_action
		hide_snackbar()
		if act.is_valid():
			act.call()
	)
	hb.add_child(_snack_btn)
	var b_close := Button.new()
	b_close.text = "✕"
	b_close.flat = true
	b_close.tooltip_text = "閉じる"
	b_close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b_close.pressed.connect(hide_snackbar)
	hb.add_child(b_close)

	_snack_timer = Timer.new()
	_snack_timer.one_shot = true
	_snack_timer.timeout.connect(hide_snackbar)
	add_child(_snack_timer)


## message を表示。action_text が空でなければ操作ボタンを出し、押すと action を呼ぶ。
## seconds <= 0 なら自動では消えない。
func show_snackbar(message: String, action_text: String = "", action: Callable = Callable(), seconds: float = 8.0) -> void:
	if _snack == null:
		return
	_snack_lbl.text = message
	_snack_btn.text = action_text
	_snack_btn.visible = action_text != ""
	_snack_action = action
	_snack.visible = true
	if _snack_tween != null:
		_snack_tween.kill()
	_snack.modulate.a = 0.0
	_snack_tween = create_tween()
	_snack_tween.tween_property(_snack, "modulate:a", 1.0, 0.18)
	_snack_timer.stop()
	if seconds > 0.0:
		_snack_timer.start(seconds)


func hide_snackbar() -> void:
	if _snack == null or not _snack.visible:
		return
	_snack_timer.stop()
	if _snack_tween != null:
		_snack_tween.kill()
	_snack_tween = create_tween()
	_snack_tween.tween_property(_snack, "modulate:a", 0.0, 0.15)
	_snack_tween.tween_callback(func(): _snack.visible = false)


## ウィンドウ透過にしたとき、背景色が黒でなければ黒にするよう案内する。
func _suggest_black_background() -> void:
	if controller == null:
		return
	var col: Color = controller.bg_manager.bg_color
	if col.r8 == 0 and col.g8 == 0 and col.b8 == 0:
		return
	show_snackbar(
		"ウィンドウを透過にしました。背景色が黒でないと、背景が半透明に残ることがあります。",
		"背景を黒にする", _set_black_background, 12.0)


func _set_black_background() -> void:
	if controller == null:
		return
	controller.bg_manager.apply_background({"color": "#000000"})
	controller.state_changed.emit()
	show_snackbar("背景色を黒 (#000000) にしました", "", Callable(), 2.5)

# ---------------------------------------------------------------------------
# Tab: License
# ---------------------------------------------------------------------------

func _build_tab_license() -> void:
	var vb := _new_tab("License")
	_add_section(vb, "このアプリについて")
	var about := Label.new()
	about.theme_type_variation = "DimLabel"
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.text = "うつしみらー (UtsushiMirror) — Godot %s で動いています。利用しているオープンソースソフトウェアと素材のライセンスを下に示します。" % Engine.get_version_info().get("string", "")
	vb.add_child(about)

	_add_section(vb, "サードパーティのライセンス")
	var te := TextEdit.new()
	te.editable = false
	te.custom_minimum_size = Vector2(0, 520)
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.text = _license_text()
	vb.add_child(te)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var b_copy := Button.new()
	b_copy.text = "全文をコピー"
	b_copy.pressed.connect(func():
		DisplayServer.clipboard_set(te.text)
		show_snackbar("ライセンス全文をクリップボードにコピーしました", "", Callable(), 2.5)
	)
	hb.add_child(b_copy)
	var b_godot := Button.new()
	b_godot.text = "Godot のライセンスを Web で見る"
	b_godot.pressed.connect(func(): OS.shell_open("https://godotengine.org/license"))
	hb.add_child(b_godot)
	vb.add_child(hb)


static func _license_text() -> String:
	var parts: PackedStringArray = []
	var root: String = ConfigManagerScript.get_app_root_dir()
	var f := FileAccess.open(root.path_join("assets/licenses/THIRD_PARTY_NOTICES.txt"), FileAccess.READ)
	if f != null:
		parts.append(f.get_as_text())
	else:
		parts.append("(assets/licenses/THIRD_PARTY_NOTICES.txt が見つかりません)")
	parts.append("
================================================================")
	parts.append("Godot Engine — License (MIT)")
	parts.append("================================================================
")
	parts.append(Engine.get_license_text())
	parts.append("
[Godot Engine に含まれるサードパーティ部品 / Third-party components in Godot]
")
	for info in Engine.get_copyright_info():
		var line := "- %s" % str(info.get("name", ""))
		for part in info.get("parts", []):
			var cr: Array = part.get("copyright", [])
			line += "
    (c) %s — %s" % [", ".join(PackedStringArray(cr)), str(part.get("license", ""))]
		parts.append(line)
	parts.append("
[ライセンス本文 / License texts]
")
	var lic: Dictionary = Engine.get_license_info()
	for k in lic.keys():
		parts.append("---- %s ----
%s
" % [str(k), str(lic[k])])
	return "
".join(parts)


## 設定ウィンドウにフォーカスがあるときも F1〜F12・Ctrl+Shift+S などを効かせる。
## 文字入力中 (LineEdit / TextEdit / SpinBox) はそちらを優先する。
func _on_window_input(event: InputEvent) -> void:
	if controller == null or not (event is InputEventKey):
		return
	var focus := gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	if controller.hotkey_manager.handle_key_event(event):
		set_input_as_handled()
