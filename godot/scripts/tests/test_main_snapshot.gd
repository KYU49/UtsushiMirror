extends SceneTree

## メイン画面を一定時間後に PNG 保存する (VMC 受信などの結合確認用)。
## 実行: godot --path godot -s res://scripts/tests/test_main_snapshot.gd -- <秒数> <出力png>

var _main: Node
var _t := 0.0
var _wait := 8.0
var _out := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_wait = float(args[0])
	_out = args[1] if args.size() > 1 else ProjectSettings.globalize_path("res://../out/main_snapshot.png")
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)


func _process(delta: float) -> bool:
	_t += delta
	if _t >= _wait:
		get_root().get_texture().get_image().save_png(_out)
		print("SNAPSHOT_SAVED=", _out)
		return true
	return false
