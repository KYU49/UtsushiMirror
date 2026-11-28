extends SceneTree
## 出力ページ: スクリーンショット撮影と録画開始のボタンが横に並び、同じ見た目か。
## 「ワイヤー表示も書き出す」のチェックが録画の設定に届くか。TEST_OUT_DIR があれば設定画面の絵を保存する。
## 実行 (利用者の設定を変えないよう、設定は一時ファイルに):
##   VRMVIEWER_CONFIG=<一時ファイル> godot --path godot -s res://scripts/tests/test_output_ui.gd
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
	var sw = _m.settings_window
	if _f == 20:
		sw.visible = true
		sw._select_tab("Output")
		var tab = sw._tab_handlers["Output"]
		var row: Node = tab._btn_rec.get_parent()
		var shot: Button = null
		for c in row.get_children():
			if c is Button and c != tab._btn_rec:
				shot = c
		_check("撮影と録画のボタンが同じ行に並ぶ", row is HBoxContainer and shot != null and shot.text.contains("スクリーンショット"))
		_check("撮影ボタンが録画ボタンの左", shot != null and shot.get_index() < tab._btn_rec.get_index())
		_check("見た目をそろえる (止まっているときは同じ色)", shot != null and shot.theme_type_variation == tab._btn_rec.theme_type_variation)
		_check("どちらも同じ幅に広がる", shot != null and shot.size_flags_horizontal == tab._btn_rec.size_flags_horizontal \
			and shot.size_flags_horizontal & Control.SIZE_EXPAND != 0)
		_check("ワイヤーのチェックは最初はオフ", not tab._chk_rec_wire.button_pressed)
		tab._chk_rec_wire.button_pressed = true
		_check("チェックすると録画でワイヤーも書き出す設定になる", _m.capture_manager.record_wire)
		_check("状態にも出る", bool(_m.capture_manager.to_dict().get("record_wire", false)))
		tab._chk_rec_wire.button_pressed = false
		_check("外すと書き出さない", not _m.capture_manager.record_wire)
		var r: Dictionary = _m.capture_manager.start_recording({"output_path": OS.get_temp_dir().path_join("utsushi_test_rec.mp4"), "wire": true})
		_check("トラッキングが止まっているときはワイヤーを書き出さない", str(r.get("wire_path", "x")) == "")
		if r.get("ok", false):
			var s: Dictionary = _m.capture_manager.stop_recording()
			DirAccess.remove_absolute(str(s.get("path", "")))
		# 絵を撮るため、録画の欄が見える所まで流す
		var sc := _find_scroll(sw)
		if sc != null:
			sc.ensure_control_visible(tab._btn_rec)
	if _f == 40:
		var out := OS.get_environment("TEST_OUT_DIR")
		if out != "":
			var img: Image = sw.get_viewport().get_texture().get_image()
			img.save_png(out.path_join("output_tab.png"))
			print("saved ", out.path_join("output_tab.png"))
		print("RESULT ", "OK" if _ok else "NG")
		quit(0 if _ok else 1)
	return false


func _find_scroll(n: Node) -> ScrollContainer:
	for c in n.get_children():
		if c is ScrollContainer and c.is_visible_in_tree():
			return c
		var r := _find_scroll(c)
		if r != null:
			return r
	return null
