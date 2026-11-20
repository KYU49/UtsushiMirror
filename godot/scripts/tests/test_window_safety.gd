extends SceneTree
## モデル未表示時の窓状態解除とタスクトレイの確認。
## VRMVIEWER_CONFIG に「透過+枠なし+クリックスルー+モデルあり」の設定を入れて実行する。
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
	if _f == 40:
		_check("model loaded", _m.current_vrm != null)
		_check("model shown keeps transparent", _m.bg_manager.win_transparent and _m.bg_manager.win_click_through)
		_check("tray icon exists", _m._tray != null or not DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR))
		_m.load_vrm(ProjectSettings.globalize_path("res://../assets/samples/Seed-san.vrm"))
		_check("model switch keeps transparent", _m.bg_manager.win_transparent)
		_m.unload_vrm()
	if _f == 50:
		var bm = _m.bg_manager
		_check("unload restores window", not bm.win_transparent and not bm.win_borderless and not bm.win_click_through and not bm.win_always_on_top)
		print("TEST_WINDOW_SAFETY_RESULT=", "PASS" if _ok else "FAIL")
		return true
	return false
