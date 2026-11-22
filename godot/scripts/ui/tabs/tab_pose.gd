extends RefCounted

const VrmHumanoidScript := preload("res://scripts/vrm/vrm_humanoid.gd")
const UiWidgets := preload("res://scripts/ui/ui_widgets.gd")

const BONE_GROUPS := [
	["all", "すべてのボーン"],
	["torso", "体幹・頭"],
	["arms", "腕・肩"],
	["legs", "脚・足"],
	["l_fingers", "左手指"],
	["r_fingers", "右手指"],
]

var _win
var _opt_group: OptionButton
var _opt_bone: OptionButton
var _cur_bone: String = "head"
var _sl_bx: HSlider
var _sl_by: HSlider
var _sl_bz: HSlider
var _sl_hx: HSlider
var _sl_hy: HSlider
var _sl_hz: HSlider


func build(win, vb: VBoxContainer) -> void:
	_win = win
	var is_sync: Callable = win.is_syncing_fn()

	# ---- プリセット
	var c_pre: Dictionary = UiWidgets.card(vb, "ポーズプリセット")
	var pg := GridContainer.new()
	pg.columns = 4
	pg.add_theme_constant_override("h_separation", 8)
	pg.add_theme_constant_override("v_separation", 8)
	c_pre["body"].add_child(pg)

	var presets := [
		["a_pose", "A ポーズ"],
		["attention", "気をつけ"],
		["wave", "手を振る"],
		["peace", "ピース"],
		["sit", "座る"],
		["hands_on_hips", "腰に手"],
	]
	for item in presets:
		var pid: String = item[0]
		var plabel: String = item[1]
		var b := Button.new()
		b.text = plabel
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			if _win.controller != null:
				_win.controller.apply_pose_preset(pid, 0.25, false)
		)
		pg.add_child(b)

	var b_reset := Button.new()
	b_reset.text = "全リセット"
	b_reset.theme_type_variation = "DangerButton"
	b_reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_reset.pressed.connect(func():
		if _win.controller != null:
			_win.controller.reset_bones_pose()
	)
	pg.add_child(b_reset)

	# ---- ボーン個別回転
	var c_bone: Dictionary = UiWidgets.card(vb, "ボーン個別調整 (正規化 Euler °)")
	_opt_group = UiWidgets.option_row(c_bone["body"], "部位フィルタ", BONE_GROUPS, func(grp: String):
		_populate_bone_list(grp),
		is_sync
	)

	var brow := UiWidgets.labeled_row(c_bone["body"], "ボーン選択")
	_opt_bone = OptionButton.new()
	_opt_bone.clip_text = true
	_opt_bone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opt_bone.item_selected.connect(func(idx: int):
		var meta: Variant = _opt_bone.get_item_metadata(idx)
		_cur_bone = str(meta) if meta != null else _opt_bone.get_item_text(idx)
		_sync_selected_bone_sliders()
	)
	brow.add_child(_opt_bone)
	_populate_bone_list("all")

	var qrow := GridContainer.new()
	qrow.columns = 4
	qrow.add_theme_constant_override("h_separation", 6)
	qrow.add_theme_constant_override("v_separation", 6)
	c_bone["body"].add_child(qrow)
	for qb_name in ["head", "neck", "spine", "leftUpperArm", "rightUpperArm", "leftUpperLeg", "rightUpperLeg"]:
		var qb := Button.new()
		qb.text = qb_name
		qb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		qb.pressed.connect(func():
			_cur_bone = qb_name
			UiWidgets.select_option_by_meta(_opt_group, "all")
			_populate_bone_list("all")
			UiWidgets.select_option_by_text(_opt_bone, qb_name)
			_sync_selected_bone_sliders()
		)
		qrow.add_child(qb)

	var push_bone := func(_v: float):
		if _win.controller != null:
			_win.controller.set_single_bone_euler(_cur_bone, Vector3(_sl_bx.value, _sl_by.value, _sl_bz.value))
	_sl_bx = UiWidgets.slider(c_bone["body"], "X (前後傾き °)", -180.0, 180.0, 1.0, 0.0, push_bone, is_sync)
	_sl_by = UiWidgets.slider(c_bone["body"], "Y (ひねり °)", -180.0, 180.0, 1.0, 0.0, push_bone, is_sync)
	_sl_bz = UiWidgets.slider(c_bone["body"], "Z (左右傾き °)", -180.0, 180.0, 1.0, 0.0, push_bone, is_sync)

	var act_row := HBoxContainer.new()
	act_row.add_theme_constant_override("separation", 8)
	c_bone["body"].add_child(act_row)
	var b_clr := Button.new()
	b_clr.text = "このボーンを解除"
	b_clr.pressed.connect(func():
		if _win.controller != null:
			_win.controller.clear_single_bone_pose(_cur_bone)
			_sync_selected_bone_sliders()
	)
	act_row.add_child(b_clr)

	var b_m_lr := Button.new()
	b_m_lr.text = "左 → 右 ミラー"
	b_m_lr.pressed.connect(func():
		if _win.controller != null:
			_win.controller.mirror_bones_pose(true)
			_sync_selected_bone_sliders()
	)
	act_row.add_child(b_m_lr)

	var b_m_rl := Button.new()
	b_m_rl.text = "右 → 左 ミラー"
	b_m_rl.pressed.connect(func():
		if _win.controller != null:
			_win.controller.mirror_bones_pose(false)
			_sync_selected_bone_sliders()
	)
	act_row.add_child(b_m_rl)

	# ---- Hips 位置オフセット
	var c_hips: Dictionary = UiWidgets.card(vb, "腰 (Hips) 位置オフセット (m)")
	var push_hips := func(_v: float):
		if _win.controller != null:
			_win.controller.set_direct_hips_offset(Vector3(_sl_hx.value, _sl_hy.value, _sl_hz.value), true)
	_sl_hx = UiWidgets.slider(c_hips["body"], "腰 X (左右 m)", -1.5, 1.5, 0.01, 0.0, push_hips, is_sync)
	_sl_hy = UiWidgets.slider(c_hips["body"], "腰 Y (上下 m)", -1.5, 1.5, 0.01, 0.0, push_hips, is_sync)
	_sl_hz = UiWidgets.slider(c_hips["body"], "腰 Z (前後 m)", -1.5, 1.5, 0.01, 0.0, push_hips, is_sync)

	var b_hrst := Button.new()
	b_hrst.text = "腰位置をリセット"
	b_hrst.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b_hrst.pressed.connect(func():
		if _win.controller != null:
			_win.controller.set_direct_hips_offset(Vector3.ZERO, false)
			_win.begin_sync()
			_sl_hx.value = 0.0
			_sl_hy.value = 0.0
			_sl_hz.value = 0.0
			_win.end_sync()
	)
	c_hips["body"].add_child(b_hrst)


func _populate_bone_list(grp: String) -> void:
	_opt_bone.clear()
	var idx := 0
	var sel_idx := 0
	for bname in VrmHumanoidScript.ALL_HUMAN_BONES:
		if not _matches_group(bname, grp):
			continue
		_opt_bone.add_item(bname)
		_opt_bone.set_item_metadata(idx, bname)
		if bname == _cur_bone:
			sel_idx = idx
		idx += 1
	if _opt_bone.item_count > 0:
		_opt_bone.select(sel_idx)
		_cur_bone = str(_opt_bone.get_item_metadata(sel_idx))


static func _matches_group(bname: String, grp: String) -> bool:
	match grp:
		"torso":
			return bname in ["hips", "spine", "chest", "upperChest", "neck", "head", "leftEye", "rightEye", "jaw"]
		"arms":
			return bname in ["leftShoulder", "leftUpperArm", "leftLowerArm", "leftHand", "rightShoulder", "rightUpperArm", "rightLowerArm", "rightHand"]
		"legs":
			return bname in ["leftUpperLeg", "leftLowerLeg", "leftFoot", "leftToes", "rightUpperLeg", "rightLowerLeg", "rightFoot", "rightToes"]
		"l_fingers":
			return bname.begins_with("leftThumb") or bname.begins_with("leftIndex") or bname.begins_with("leftMiddle") or bname.begins_with("leftRing") or bname.begins_with("leftLittle")
		"r_fingers":
			return bname.begins_with("rightThumb") or bname.begins_with("rightIndex") or bname.begins_with("rightMiddle") or bname.begins_with("rightRing") or bname.begins_with("rightLittle")
		_:
			return true


func _sync_selected_bone_sliders() -> void:
	if _win.controller == null:
		return
	var map: Dictionary = _win.controller.get_direct_bones_euler_deg()
	var e: Vector3 = map.get(_cur_bone, Vector3.ZERO)
	_win.begin_sync()
	_sl_bx.value = e.x
	_sl_by.value = e.y
	_sl_bz.value = e.z
	_win.end_sync()


func sync(_st: Dictionary) -> void:
	_sync_selected_bone_sliders()
	if _win.controller != null:
		var ho: Vector3 = _win.controller.get_direct_hips_offset()
		_sl_hx.value = ho.x
		_sl_hy.value = ho.y
		_sl_hz.value = ho.z
