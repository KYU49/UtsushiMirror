extends SceneTree
## 外部制御の結合確認: 一定時間 XR シーンを動かし、最後に PNG 保存。
var m
var t := 0.0
func _initialize() -> void:
	m = load("res://scenes/xr_main.tscn").instantiate()
	get_root().add_child(m)
func _process(d: float) -> bool:
	t += d
	if t > 14.0:
		get_root().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/remote_test.png"))
		print("REMOTE_SNAPSHOT_SAVED")
		return true
	return false
