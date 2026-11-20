extends SceneTree
## PC (平面表示) で XR シーンを起動し、数秒後に PNG 保存する確認用スクリプト。
var _t := 0.0
func _initialize() -> void:
	get_root().add_child(load("res://scenes/xr_main.tscn").instantiate())
func _process(d: float) -> bool:
	_t += d
	if _t > 6.0:
		get_root().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/pc_snapshot.png"))
		print("XR_SNAPSHOT_SAVED")
		return true
	return false
