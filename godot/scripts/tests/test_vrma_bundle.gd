extends SceneTree
## 同梱 VRMA (サブフォルダ含む) がすべて読み込めるか確認する。
const V := preload("res://scripts/vrm/vrma_loader.gd")
func _initialize() -> void:
	var root := ProjectSettings.globalize_path("res://../assets/animations").simplify_path()
	var ok := 0
	var ng := 0
	var subs: Array = [""]
	subs.append_array(Array(DirAccess.get_directories_at(root)))
	for sub in subs:
		var d := root.path_join(sub)
		for fn in DirAccess.get_files_at(d):
			if not fn.ends_with(".vrma"):
				continue
			var r: Dictionary = V.load_vrma(d.path_join(fn), null)
			if r.get("ok", false):
				ok += 1
			else:
				ng += 1
				print("NG ", fn, " ", r.get("error", ""))
	print("VRMA_BUNDLE ok=%d ng=%d" % [ok, ng])
	print("TEST_VRMA_BUNDLE_RESULT=", "PASS" if ng == 0 else "FAIL")
	quit()
